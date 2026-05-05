extends Node3D
# EditToolHandler — handles "swing tool, edit voxel" input.
#
# What this does in plain English:
#
# When Roland holds an axe / pickaxe / shovel in his weapon slot
# and presses LMB (the `attack` action), this script:
#
#   1. Reads which tool he has equipped (via InventoryManager).
#   2. Casts a ray forward from the camera to find the voxel he is
#      aiming at (via CameraRig.get_camera_forward_hit).
#   3. Checks whether the tool can affect that voxel material.
#   4. Calls VoxelEditManager.queue_set_voxel to remove the voxel.
#   5. Yields the matching raw-material item into Roland's inventory.
#
# A short cooldown gates swing rate. NoEditZone rejection is handled
# silently by VoxelEditManager — if it returns false, we print a
# placeholder rejection message until the bark system is wired up.
#
# Attached as a child of Player3D in scenes/Player3D.tscn so it
# inherits the player's transform and lives in the player scene.
#
# Reference: design/3D_VOXEL_MIGRATION.md → "Player Edit Verbs"


# =============================================================
# CONFIGURATION
# =============================================================

@export var max_reach_meters: float = 3.5
# How far forward the ray casts when looking for a voxel surface.
# 3.5m is the design-locked manual-tool reach (2026-05-05): mid-
# range of the 3-4m design window — about arm-length plus a
# comfortable forward stride. Prevents mining voxels that aren't
# credibly within striking distance. Raise for longer-haft tools
# (e.g. dwarven war-pickaxe) in a future per-tool config.

@export var swing_cooldown_seconds: float = 0.4
# Animation-pacing cooldown that runs AFTER a successful carve. The
# cycle is: player holds LMB → swing time accumulates against the
# target voxel's mining_time_seconds → when full, voxel breaks AND
# swing_cooldown_seconds locks input briefly so the swing animation
# has room to reset between voxels. Without this cooldown, breaking
# soft materials (sand, dirt) would spam multiple voxels per
# frame the moment mining_time hit zero.

@export var swing_carve_voxels_per_side: int = 3
# Manual tools (pickaxe / shovel / axe) carve a CUBE this many voxels
# on a side per swing. 3 → 3×3×3 = 27 voxels per swing — each tool
# strike opens up a chunky bite that's clearly visible from third-
# person distance and reads as a "good hit" without feeling like a
# bucket-scale carve. Tunable per tool tier later (iron pickaxe = 3,
# dwarven pickaxe = 4, drill = 5+).
#
# Implementation note: we used to use a sphere radius for this, but
# spheres carve roughly half their voxel volume due to the spherical
# packing — a 0.15 m sphere clears ~3-5 voxels, hard to predict and
# inconsistent across orientations. A box is exactly N×N×N voxels
# regardless of camera angle, easier to tune.

@export var smooth_voxels_per_side: int = 5
# Right-click "smooth" verb: levels the 5×5 column of terrain
# centred on the aim point toward the AVERAGE column height. Each
# right-click does ONE iteration of smoothing — high spots get one
# voxel shaved, low spots get one voxel filled. Multiple right-
# clicks converge toward flat. Cheaper computationally than a
# single full-flatten pass, easier to control (player can stop
# halfway and not destroy the natural bumpiness entirely).

const AIR_VOXEL: int = 0
# Voxel value 0 = air. Writing this removes the voxel.

# Map from equipped tool item_id to the Crafting sub-skill that gets
# XP on a successful edit. Pickaxe → mining, axe → felling, etc.
# Sub-skill names match the design doc XP_VALUES table in
# design/SKILLS_AND_PROGRESSION.md.
const TOOL_SUB_SKILLS: Dictionary = {
	"iron_pickaxe": "mining",
	"iron_axe":     "felling",
	"iron_shovel":  "excavation",
}

# XP awarded per successful single-voxel edit. Matches the design
# doc's XP_VALUES entries (ore_mined=5, tree_felled=8, earth_dug=2).
# A bigger edit (sphere via explosives) awards more — per-edit value
# is a coarse proxy for "voxels touched."
const TOOL_XP_PER_EDIT: Dictionary = {
	"iron_pickaxe": 5,
	"iron_axe":     8,
	"iron_shovel":  2,
}


# =============================================================
# RUNTIME STATE
# =============================================================

var _swing_cooldown_remaining: float = 0.0
# Post-carve animation cooldown. Set to swing_cooldown_seconds when
# a voxel is broken; ticks down each frame; while > 0 the player
# can't accumulate swing time on a new voxel.

var _current_target_voxel: Vector3i = Vector3i.ZERO
# The voxel-grid coordinate the player is currently swinging at.
# Reset (along with _swing_time_on_target) the moment the player
# looks at a different voxel — partial mining doesn't carry across
# voxels.

var _has_target: bool = false
# False when the player isn't aiming at any voxel (raycast missed
# or attack not held). Distinct from "target = (0,0,0)" since
# (0,0,0) is a valid voxel position.

var _swing_time_on_target: float = 0.0
# Accumulated seconds the player has been holding the active action
# against `_current_target_voxel`. When it reaches the target
# voxel's material's `mining_time_seconds`, the action fires
# (carve OR smooth).

var _current_action: String = ""
# "mine" while LMB is the active hold, "smooth" while RMB is.
# Resets when the player switches buttons or releases — the swing
# accumulator restarts so half-mining-then-smoothing doesn't get
# free progress on the smooth.

var _held_log_counter: int = 0
# Throttle counter for held-swing diagnostic prints — only print
# every Nth frame so we can see where _tick_held_swing bails
# without flooding Output (it runs every frame the LMB is held).

# --- Public read-only state for the HUD progress bar ---
# HUDOverlay polls these each frame to drive the mining-time bar
# (same style as HP / endurance). When mining_active is true, the
# bar is shown filled to mining_progress (0..1). When false, the
# bar hides. Updated in _tick_held_swing and reset in _clear_target.
var mining_active: bool = false
var mining_progress: float = 0.0
var mining_material_label: String = ""


# =============================================================
# REFERENCES (resolved in _ready)
# =============================================================

var _camera_rig: SpringArm3D
# The CameraRig (SpringArm3D) inside Player3D.tscn. Used to call
# get_camera_forward_hit() for voxel targeting.


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# Walk up to the player root, then down to the SpringArm3D that
	# holds CameraRig.gd. Hierarchy in scenes/Player3D.tscn:
	#
	#   Player3D
	#   ├── EditToolHandler (this node)
	#   ├── CameraTarget
	#   │   └── SpringArm3D (CameraRig.gd)  ← target
	#   └── ...
	var player := get_parent() as CharacterBody3D
	if player == null:
		push_error("[EditToolHandler] Parent must be Player3D (CharacterBody3D)")
		return
	_camera_rig = player.get_node_or_null("CameraTarget/SpringArm3D")
	if _camera_rig == null:
		push_error("[EditToolHandler] CameraTarget/SpringArm3D not found under Player3D")


func _process(delta: float) -> void:
	# Tick the post-carve cooldown.
	if _swing_cooldown_remaining > 0.0:
		_swing_cooldown_remaining -= delta

	# Diagnostic: log the moment the LMB is JUST pressed, regardless
	# of any other gate. Tells us "is the input even reaching this
	# script?" — the answer to the user's "left click does nothing".
	if Input.is_action_just_pressed("attack"):
		var mm: int = Input.mouse_mode
		var equipped_dbg: String = "(no InventoryManager)"
		if get_node_or_null("/root/InventoryManager"):
			equipped_dbg = InventoryManager.get_equipped("weapon")
		print("[EditTool] LMB just_pressed | mouse_mode=%d (need 2=CAPTURED) | equipped=%s | cooldown=%.2f" % [
			mm, equipped_dbg, _swing_cooldown_remaining,
		])

	# Mouse must be captured (no menu open) and attack action must be
	# HELD (not just-pressed) — held-swing accumulator gates progress
	# rather than per-press carve.
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_clear_target()
		return

	# If the equipped item is a throwable, ThrowableHandler owns LMB.
	# Bail entirely so we don't double-process the click (and don't
	# show a "wrong tool" mining diagnostic for grass).
	if get_node_or_null("/root/InventoryManager"):
		var eid: String = InventoryManager.get_equipped("weapon")
		if eid != "" and InventoryManager.ITEM_REGISTRY.has(eid) \
				and InventoryManager.ITEM_REGISTRY[eid].get("type", "") == "throwable":
			_clear_target()
			return

	# Bucket is one-shot per click (not held). Routes through its own
	# handler so the held-attack gate below doesn't apply.
	if Input.is_action_just_pressed("attack") and _swing_cooldown_remaining <= 0.0:
		var equipped: String = ""
		if get_node_or_null("/root/InventoryManager"):
			equipped = InventoryManager.get_equipped("weapon")
		if equipped == "bucket" or equipped == "bucket_filled":
			_handle_bucket_click(equipped)
			return

	# --- Held-action dispatch ---
	# LMB held → "mine" action (carve 3×3×3, drop pickup).
	# RMB held → "smooth" action (5×5 column-average smoothing).
	# LMB has priority if both are held simultaneously.
	# Both share the same accumulator + cooldown + HUD progress bar
	# so a smoothing pass takes the same wall time as a mining
	# pass — driven by the aim-point material's mining_time_seconds.
	var lmb_held: bool = Input.is_action_pressed("attack")
	var rmb_held: bool = Input.is_action_pressed("smooth_terrain")
	var action: String = ""
	if lmb_held:
		action = "mine"
	elif rmb_held:
		action = "smooth"
	if action == "":
		_clear_target()
		return
	if _swing_cooldown_remaining > 0.0:
		# Animation reset window after a successful carve / smooth.
		# Don't accumulate during this — the player should feel a
		# beat between strikes.
		return

	_tick_held_action(delta, action)


func _handle_bucket_click(equipped: String) -> void:
	# Bucket use is one-shot per click. Two states:
	#   "bucket"        : swing at water (any source region or flow
	#                     cell within reach) → fill the bucket.
	#   "bucket_filled" : swing at empty space → place a permanent
	#                     source cell at the targeted voxel and
	#                     empty the bucket.
	#
	# Targeting strategy: use the camera forward ray. For a fill
	# action we need to check whether the targeted air-voxel is
	# inside water; for a place action we need an air voxel just
	# in front of the player (one voxel-width along the camera
	# ray) so we don't try to place inside terrain.
	if get_node_or_null("/root/WaterFlowManager") == null:
		return
	if get_node_or_null("/root/InventoryManager") == null:
		return
	if _camera_rig == null:
		return

	# Compute a target world-space point: max_reach_meters in front
	# of the camera, regardless of whether the ray hits anything.
	# (Hitting voxels means we'd target the voxel surface; for water
	# placement we want to be IN AIR.)
	var camera: Camera3D = _camera_rig.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return
	var aim_origin: Vector3 = camera.global_position
	var aim_dir: Vector3 = -camera.global_transform.basis.z
	# Stop the aim shorter than the full reach so we land in front of
	# the player rather than at the terrain wall.
	var aim_distance: float = minf(max_reach_meters, 2.5)
	var target_world: Vector3 = aim_origin + aim_dir * aim_distance

	if equipped == "bucket":
		_bucket_fill_at(target_world)
	elif equipped == "bucket_filled":
		_bucket_place_at(target_world)
	_swing_cooldown_remaining = swing_cooldown_seconds


func _bucket_fill_at(world_pos: Vector3) -> void:
	# If the target world position is inside any water cell or source
	# region, swap the bucket → bucket_filled. Otherwise no-op.
	if not WaterFlowManager.is_position_in_water(world_pos):
		# Also try the player's feet — Roland is standing in water.
		var player := get_parent() as CharacterBody3D
		if player != null and WaterFlowManager.is_position_in_water(player.global_position):
			pass  # fall through to fill
		else:
			return
	InventoryManager.remove_item("bucket", 1)
	InventoryManager.add_item("bucket_filled", 1)
	InventoryManager.equip("weapon", "bucket_filled")
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Bucket filled.")
	else:
		print("[EditToolHandler] Bucket filled.")


func _bucket_place_at(world_pos: Vector3) -> void:
	# Place a permanent source cell at the voxel containing world_pos.
	# Refuses if the voxel is solid terrain or already a water cell.
	# NoEditZone with blocks_water_flow blocks placement (matching
	# flow rules).
	if not get_node_or_null("/root/VoxelEditManager"):
		return
	var voxel_pos: Vector3i = VoxelEditManager.world_to_voxel(world_pos)
	# Reject solid terrain at this cell (can't place water inside rock).
	# Material-id decoding goes through VoxelMaterialRegistry per the
	# CLAUDE.md "Critical patterns" rule — never decode the alpha byte
	# by hand.
	var terrain: VoxelLodTerrain = VoxelEditManager.get_terrain()
	if terrain != null:
		var tool: VoxelTool = terrain.get_voxel_tool()
		if tool != null:
			tool.channel = VoxelBuffer.CHANNEL_COLOR
			var packed: int = tool.get_voxel(voxel_pos)
			var mat_id: int = 0
			if get_node_or_null("/root/VoxelMaterialRegistry"):
				mat_id = VoxelMaterialRegistry.material_id_from_packed(packed)
			else:
				mat_id = packed & 0xFF
			if mat_id != 0:
				if get_node_or_null("/root/DebugOverlay"):
					DebugOverlay.log_action("Bucket place rejected: voxel solid.")
				return
	# NoEditZone gate.
	if get_node_or_null("/root/NoEditZoneRegistry") and \
		NoEditZoneRegistry.is_water_flow_blocked_at(world_pos):
		if get_node_or_null("/root/DebugOverlay"):
			DebugOverlay.log_action("Bucket place rejected: NoEditZone.")
		else:
			print("[EditToolHandler] This place doesn't yield to me.")
		return
	WaterFlowManager.add_source(voxel_pos)
	InventoryManager.remove_item("bucket_filled", 1)
	InventoryManager.add_item("bucket", 1)
	InventoryManager.equip("weapon", "bucket")
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Bucket placed water source at %s." % voxel_pos)
	else:
		print("[EditToolHandler] Bucket placed water source.")


func _clear_target() -> void:
	_has_target = false
	_swing_time_on_target = 0.0
	_current_action = ""
	mining_active = false
	mining_progress = 0.0
	mining_material_label = ""


func _tick_held_action(delta: float, action: String) -> void:
	# One frame of held-action progress. Drives both LMB mine and
	# RMB smooth — the only differences are (a) tool-gate is skipped
	# for smooth (any manual tool can smooth any material), and (b)
	# at completion we call _carve vs _do_smooth.
	#
	# Both share the same accumulator (_swing_time_on_target),
	# cooldown (_swing_cooldown_remaining), HUD progress bar, and
	# target-stability reset behaviour. Switching mid-press from
	# mine to smooth (or vice versa) on the same voxel doesn't
	# preserve progress — the action label changes and we restart
	# the swing.
	_held_log_counter += 1
	var should_log: bool = _held_log_counter >= 30
	if should_log:
		_held_log_counter = 0

	# --- What's equipped? ---
	if not get_node_or_null("/root/InventoryManager"):
		if should_log:
			print("[EditTool] held bail: no InventoryManager")
		return
	var equipped_id: String = InventoryManager.get_equipped("weapon")
	if equipped_id == "":
		if should_log:
			print("[EditTool] held bail: nothing equipped")
		_clear_target()
		return

	# --- Find the voxel the player is aiming at ---
	if _camera_rig == null:
		if should_log:
			print("[EditTool] held bail: no _camera_rig")
		return
	var hit: Dictionary = _camera_rig.get_camera_forward_hit(max_reach_meters)
	if hit.is_empty():
		if should_log:
			print("[EditTool] held bail: raycast empty (equipped=%s)" % equipped_id)
		_clear_target()
		return
	if should_log:
		var hp: Vector3 = hit.get("position", Vector3.ZERO)
		print("[EditTool] held: equipped=%s hit_at=%s" % [equipped_id, hp])

	# The raycast extends through the camera arm + max_reach so it can
	# reach max_reach meters past the player. Verify the hit position
	# is within max_reach_meters of the PLAYER, not just within the
	# ray length.
	var player := get_parent() as CharacterBody3D
	var hit_pos: Vector3 = hit.get("position", Vector3.ZERO)
	if player != null:
		var dist_from_player: float = player.global_position.distance_to(hit_pos)
		if dist_from_player > max_reach_meters:
			_clear_target()
			return

	# Offset slightly INTO the surface so we target the solid voxel,
	# not the air voxel above it.
	var hit_normal: Vector3 = hit.get("normal", Vector3.UP)
	var voxel_world_pos: Vector3 = hit_pos - hit_normal * 0.1

	# --- Read the voxel material ---
	var material: VoxelMaterial = _read_material_at(voxel_world_pos)
	if material == null:
		# Voxel is air, registry isn't loaded, or the read failed.
		# Either way, no swing progress.
		_clear_target()
		return

	# --- Tool gating ---
	# Only apply for "mine" — for "smooth", any manual tool works on
	# any material (the smoothing pass averages column heights;
	# matching tool-to-material doesn't make sense for that verb).
	if action == "mine":
		if material.allowed_tools.size() > 0 and not (equipped_id in material.allowed_tools):
			# Wrong tool — don't accumulate. Print a throttled
			# diagnostic so the silent failure isn't mysterious.
			if should_log:
				print("[EditTool] WRONG TOOL: %s cannot break %s (allowed: %s)" % [
					equipped_id, material.id_string, material.allowed_tools,
				])
			_clear_target()
			return

	# --- Target stability + accumulate ---
	# Compute the integer voxel grid coord and compare. If the
	# player's looking at a different voxel than last frame, OR if
	# they switched action (mine → smooth or vice versa), reset.
	var target_grid: Vector3i = VoxelEditManager.world_to_voxel(voxel_world_pos)
	if not _has_target or _current_target_voxel != target_grid or _current_action != action:
		_current_target_voxel = target_grid
		_current_action = action
		_swing_time_on_target = 0.0
		_has_target = true

	_swing_time_on_target += delta

	# Public state for the HUD progress bar. Same bar drives both
	# mine and smooth — label distinguishes which.
	mining_active = true
	mining_progress = clampf(
		_swing_time_on_target / maxf(material.mining_time_seconds, 0.0001),
		0.0,
		1.0,
	)
	mining_material_label = ("SMOOTHING " + material.display_name) if action == "smooth" else material.display_name

	if _swing_time_on_target < material.mining_time_seconds:
		# Still swinging.
		return

	# --- Action complete: carve OR smooth ---
	if action == "smooth":
		_do_smooth(voxel_world_pos)
	else:
		_carve(voxel_world_pos, material, equipped_id)
	_swing_time_on_target = 0.0
	_swing_cooldown_remaining = swing_cooldown_seconds
	# Snap the bar to "complete" briefly. _clear_target / next tick
	# will reset it. Keeps the HUD honest — it shows 100% in the
	# moment the action fires.
	mining_progress = 1.0


func _read_material_at(world_pos: Vector3) -> VoxelMaterial:
	# Read the voxel at world_pos, decode the material id from the
	# alpha byte, look up the VoxelMaterial in the registry. Returns
	# null if the voxel is air, the registry isn't available, or the
	# read fails for any other reason.
	#
	# Reads the same channel the generator writes (CHANNEL_COLOR).
	# CRITICAL: VoxelTool.get_voxel takes voxel-grid coords (Vector3i),
	# not world-space metres. We use VoxelEditManager.world_to_voxel
	# which already does the conversion (multiplies by VOXELS_PER_METER
	# = 6 and floors).
	if not get_node_or_null("/root/VoxelEditManager"):
		return null
	var terrain: VoxelLodTerrain = VoxelEditManager.get_terrain()
	if terrain == null:
		return null
	var tool: VoxelTool = terrain.get_voxel_tool()
	if tool == null:
		return null
	tool.channel = VoxelBuffer.CHANNEL_COLOR
	var grid_pos: Vector3i = VoxelEditManager.world_to_voxel(world_pos)
	var packed: int = tool.get_voxel(grid_pos)
	if (packed & 0xFF) == 0:
		# Air. Probably aimed at the wrong cell (sub-voxel margin).
		return null
	if not get_node_or_null("/root/VoxelMaterialRegistry"):
		return null
	var material_id: int = packed & 0xFF
	return VoxelMaterialRegistry.get_by_id(material_id)


func _carve(voxel_world_pos: Vector3, material: VoxelMaterial, equipped_id: String) -> void:
	# Apply the voxel edit, yield the material's item, and award
	# crafting XP. Called once per successful held-swing completion.
	#
	# Carve shape: an N×N×N box of voxels centred on `voxel_world_pos`
	# (where N = swing_carve_voxels_per_side, default 3). At 6 vox/m
	# the half-side in world units is N / 12. We snap the box AABB
	# to the voxel grid so the box edges align cleanly with cube
	# faces — without snapping, a 0.5 m box drifting off the grid
	# would carve an irregular 4-or-2 voxels on each axis depending
	# on sub-voxel alignment.
	if not get_node_or_null("/root/VoxelEditManager"):
		push_warning("[EditToolHandler] VoxelEditManager autoload not registered")
		return
	# Snap centre to the nearest voxel grid centre (world-space).
	# 6 vox/m → each voxel occupies a 1/6 m cell. Centre of voxel
	# (i, j, k) is at world ((i+0.5)/6, (j+0.5)/6, (k+0.5)/6).
	const VOXELS_PER_METER: float = 6.0
	const VOXEL_SIZE_M: float = 1.0 / VOXELS_PER_METER
	var snapped: Vector3 = Vector3(
		(floori(voxel_world_pos.x * VOXELS_PER_METER) + 0.5) * VOXEL_SIZE_M,
		(floori(voxel_world_pos.y * VOXELS_PER_METER) + 0.5) * VOXEL_SIZE_M,
		(floori(voxel_world_pos.z * VOXELS_PER_METER) + 0.5) * VOXEL_SIZE_M,
	)
	# Half-side in world units: N voxels of 1/6 m each, halved.
	# For N=3 this is 0.25 m; box AABB is 0.5 m on a side = exactly
	# 3 voxels.
	var half_side_m: float = float(swing_carve_voxels_per_side) * VOXEL_SIZE_M * 0.5
	var box_min: Vector3 = snapped - Vector3.ONE * half_side_m
	var box_max: Vector3 = snapped + Vector3.ONE * half_side_m
	var accepted: bool = VoxelEditManager.queue_edit_box(
		box_min, box_max, AIR_VOXEL
	)
	if not accepted:
		# Rejected by NoEditZone. Bark trigger lives on
		# VoxelEditManager.edit_rejected_no_edit_zone — no per-call
		# action needed here.
		if get_node_or_null("/root/DebugOverlay"):
			DebugOverlay.log_action("Edit rejected: NoEditZone at %s" % voxel_world_pos)
		else:
			print("[EditToolHandler] This place doesn't yield to me.")
		return

	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Mined %s with %s at (%.1f, %.1f, %.1f)" % [
			material.id_string, equipped_id, voxel_world_pos.x, voxel_world_pos.y, voxel_world_pos.z
		])

	# --- Spawn a physical pickup drop at the carve site ---
	# Replaces the old "instant add_item to inventory" path. The
	# drop falls under gravity, settles, and auto-collects when
	# Roland walks within VoxelDrop.pickup_radius_m. Despawns
	# after VoxelDrop.despawn_seconds (5 minutes) if abandoned.
	#
	# Stack size: ONE drop per swing carrying material.yield_quantity
	# of the *majority* material at the carve site. We currently
	# sample the single voxel at the aim point as the majority; this
	# is accurate for homogenous columns and slightly approximate at
	# material boundaries (e.g. an aim landing on a grass voxel
	# yields raw_dirt even if 14 of the 27 voxels were stone).
	# Acceptable for first-pass — a real majority sample would mean
	# reading all 27 voxels before each carve, which is expensive
	# and not visibly different to the player most of the time.
	#
	# Color from material.color_low so the drop visually matches
	# what was just broken (green grass → green cube, etc.). When
	# yield_item_id is empty, no drop spawns (rare placeholder
	# materials with no harvest).
	if material.yield_item_id != "":
		_spawn_voxel_drop(
			voxel_world_pos,
			material.yield_item_id,
			material.color_low,
			material.yield_quantity,
		)

	# --- Award Crafting sub-skill XP ---
	# Each tool maps to its corresponding sub-skill (mining/felling/
	# excavation). XP rolls up to the Crafting domain tier.
	if get_node_or_null("/root/GameState"):
		var sub_skill: String = TOOL_SUB_SKILLS.get(equipped_id, "")
		var xp_amount: int = TOOL_XP_PER_EDIT.get(equipped_id, 0)
		if sub_skill != "" and xp_amount > 0:
			GameState.add_skill_xp(GameState.SkillDomain.CRAFTING, sub_skill, xp_amount)


func _do_smooth(aim_pos: Vector3) -> void:
	# Right-click smoothing pass — CONSERVATIVE: each iteration
	# moves at most min(N_high, N_low) voxels and creates ZERO net
	# new voxels. The total solid voxel count inside the smoothed
	# volume is preserved exactly across the operation.
	#
	# Why conservation matters:
	#  1. The terrain is destructible — net-add smoothing would let
	#     the player magic free voxels into existence by spamming
	#     RMB on a hill. Net-remove would let them dissolve voxels
	#     by spamming on a pit.
	#  2. Net-add carves trigger VoxelGravityManager scans with
	#     newly-added voxels above ground; the gravity system can
	#     spawn FallingVoxelClusters that yank the just-placed
	#     voxels back out of the column, which is what was making
	#     smoothed voxels "unmineable" — they were physically gone
	#     by the time the player aimed at them.
	#  3. Iteratively converges to flat (each step reduces height
	#     variance by transferring 1 voxel from the highest column
	#     to the lowest column).
	#
	# Algorithm:
	#   1. Read top solid voxel Y for each column in the
	#      smooth_voxels_per_side × smooth_voxels_per_side grid.
	#   2. Compute the average top Y.
	#   3. Sort columns: high = those with top > avg (descending),
	#      low = those with top < avg (ascending).
	#   4. Pair high with low (n_pairs = min(n_high, n_low)).
	#   5. For each pair: carve from high column's top, fill low
	#      column's top+1 using the carved voxel's material id —
	#      true "move" semantics. The unpaired remainder keeps its
	#      voxels where they are (no creates, no destroys).
	#
	# Edits route through VoxelEditManager so NoEditZone / async
	# queue / EditedChunkRegistry all stay consistent with manual
	# mining.
	if not get_node_or_null("/root/VoxelEditManager"):
		return
	var terrain: VoxelLodTerrain = VoxelEditManager.get_terrain()
	if terrain == null:
		return
	var tool: VoxelTool = terrain.get_voxel_tool()
	if tool == null:
		return
	tool.channel = VoxelBuffer.CHANNEL_COLOR

	const VOXELS_PER_METER: float = 6.0
	const VOXEL_SIZE_M: float = 1.0 / VOXELS_PER_METER
	# Search Y range (in voxels) above and below the aim point. We
	# look up to 8 voxels above the aim for "current top" and treat
	# the column as "open" below if it's air. 8 vox = ~1.3 m which
	# covers normal terrain noise.
	const SEARCH_HALF_HEIGHT_VOXELS: int = 8

	var n: int = smooth_voxels_per_side
	var half: int = n / 2  # 5 → 2; 7 → 3

	# Centre voxel coord at the aim point.
	var centre_grid: Vector3i = Vector3i(
		floori(aim_pos.x * VOXELS_PER_METER),
		floori(aim_pos.y * VOXELS_PER_METER),
		floori(aim_pos.z * VOXELS_PER_METER),
	)

	# Gather column tops. Each entry: {grid_x, grid_z, top_y, mat_id}.
	# top_y == centre_grid.y - SEARCH_HALF_HEIGHT_VOXELS - 1 means
	# "no solid found in search range" — those columns are skipped
	# (player aimed at a sky chunk or a deep cave roof; smoothing
	# isn't well-defined there).
	var columns: Array = []
	for dz in range(-half, half + 1):
		for dx in range(-half, half + 1):
			var col_x: int = centre_grid.x + dx
			var col_z: int = centre_grid.z + dz
			var top_y: int = centre_grid.y - SEARCH_HALF_HEIGHT_VOXELS - 1
			var top_mat: int = 0
			# Walk DOWN from search top to search bottom to find first solid.
			for dy in range(SEARCH_HALF_HEIGHT_VOXELS, -SEARCH_HALF_HEIGHT_VOXELS - 1, -1):
				var probe_y: int = centre_grid.y + dy
				var packed: int = tool.get_voxel(Vector3i(col_x, probe_y, col_z))
				if (packed & 0xFF) != 0:
					top_y = probe_y
					top_mat = packed & 0xFF
					break
			if top_y > centre_grid.y - SEARCH_HALF_HEIGHT_VOXELS - 1:
				columns.append({
					"x": col_x,
					"z": col_z,
					"top_y": top_y,
					"mat_id": top_mat,
				})

	if columns.size() < 2:
		# Need at least 2 columns to compute a meaningful average.
		return

	# Average top Y. Mean is fine for a per-iteration nudge; median
	# would be more outlier-robust but a single click only moves
	# each column by 1 voxel anyway.
	var sum_y: int = 0
	for c in columns:
		sum_y += int(c["top_y"])
	@warning_ignore("integer_division")
	var avg_y: int = sum_y / columns.size()

	# Conservation pairing: separate columns by relation to avg,
	# sort, pair high-with-low.
	var high_cols: Array = []  # top > avg (will donate a voxel)
	var low_cols: Array  = []  # top < avg (will receive a voxel)
	for c in columns:
		var col_top: int = int(c["top_y"])
		if col_top > avg_y:
			high_cols.append(c)
		elif col_top < avg_y:
			low_cols.append(c)
	# At-avg columns (col_top == avg) are skipped entirely — they're
	# already at the target height.

	# Sort: highest donors first (largest variance reduction per
	# move), lowest receivers first (same reason on the receive
	# side). Stable order isn't important for correctness, only for
	# slightly better visual convergence.
	high_cols.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["top_y"]) > int(b["top_y"]))
	low_cols.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["top_y"]) < int(b["top_y"]))

	var n_pairs: int = mini(high_cols.size(), low_cols.size())
	if n_pairs == 0:
		# All columns are at avg, OR all are above (no donors with
		# receivers), OR all are below. Either way, no-op.
		return

	# Build the bulk edit: each pair contributes ONE carve and ONE
	# fill. n_pairs × 2 writes. Carved voxel's material is moved
	# to the receiving column's top+1 — true voxel "move".
	var writes: Array = []
	for i in n_pairs:
		var donor: Dictionary = high_cols[i]
		var receiver: Dictionary = low_cols[i]

		# Carve the donor's top voxel.
		var carve_world: Vector3 = Vector3(
			(float(donor["x"]) + 0.5) * VOXEL_SIZE_M,
			(float(donor["top_y"]) + 0.5) * VOXEL_SIZE_M,
			(float(donor["z"]) + 0.5) * VOXEL_SIZE_M,
		)
		writes.append({"pos": carve_world, "value": AIR_VOXEL})

		# Place a voxel ABOVE the receiver's current top, carrying
		# the donor's material id (true "move" — grass moved from
		# A appears as grass at B). RGB stays mid-grey because the
		# current terrain material ignores per-voxel RGB anyway.
		var fill_world: Vector3 = Vector3(
			(float(receiver["x"]) + 0.5) * VOXEL_SIZE_M,
			(float(int(receiver["top_y"]) + 1) + 0.5) * VOXEL_SIZE_M,
			(float(receiver["z"]) + 0.5) * VOXEL_SIZE_M,
		)
		var moved_mat_id: int = int(donor["mat_id"])
		var packed_fill: int = (0x80808000) | (moved_mat_id & 0xFF)
		writes.append({"pos": fill_world, "value": packed_fill})

	VoxelEditManager.queue_set_voxels_bulk(writes, "smooth_n%d" % writes.size())
	_swing_cooldown_remaining = swing_cooldown_seconds

	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Smooth: %d voxels moved (avg_y=%d, %d donors, %d receivers)" % [
			n_pairs, avg_y, high_cols.size(), low_cols.size(),
		])


func _spawn_voxel_drop(world_pos: Vector3, drop_item_id: String, color: Color, count: int) -> void:
	# Spawn a single VoxelDrop pickup at the carve site. Parented to
	# the World3D root (not the player) so the drop stays where it
	# fell when the player walks away. queue_free is handled by the
	# drop itself via the despawn timer or pickup proximity.
	#
	# We pick the parent by walking up to the player's parent (the
	# World3D scene root). If that's null for any reason, we fall
	# back to current_scene; if even that's null, the drop just
	# doesn't spawn — degraded but not crashing.
	var player := get_parent() as CharacterBody3D
	var world_root: Node = null
	if player != null:
		world_root = player.get_parent()
	if world_root == null:
		world_root = get_tree().current_scene
	if world_root == null:
		push_warning("[EditToolHandler] no world root to parent drop under; skipping spawn")
		return

	var drop: VoxelDrop = VoxelDrop.new()
	# IMPORTANT: setup() must come BEFORE add_child() so item_id /
	# count / colour are set when _ready fires (the visual is built
	# from those values).
	drop.setup(drop_item_id, color, count)
	world_root.add_child(drop)
	drop.global_position = world_pos
