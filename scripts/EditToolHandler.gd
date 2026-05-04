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

@export var max_reach_meters: float = 4.0
# How far forward the ray casts when looking for a voxel surface.
# 4m is roughly arm + tool length. Increase if Roland feels like he
# can not reach voxels in front of him.

@export var swing_cooldown_seconds: float = 0.4
# Animation-pacing cooldown that runs AFTER a successful carve. The
# cycle is: player holds LMB → swing time accumulates against the
# target voxel's mining_time_seconds → when full, voxel breaks AND
# swing_cooldown_seconds locks input briefly so the swing animation
# has room to reset between voxels. Without this cooldown, breaking
# soft materials (sand, dirt) would spam multiple voxels per
# frame the moment mining_time hit zero.

@export var swing_carve_radius_meters: float = 0.8
# Sphere radius (meters) of voxel removed per swing. Bigger = more
# obvious visual chunk per swing, but feels less "precise". 0.8m
# is roughly a small bucket-sized hole — clearly visible from
# third-person camera distance, still feels like one pick strike.
# Tune per tool tier later (e.g. iron pickaxe = 0.5, dwarven
# pickaxe = 1.0).

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
# Accumulated seconds the player has been holding attack against
# `_current_target_voxel`. When it reaches the target voxel's
# material's `mining_time_seconds`, the voxel breaks.


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

	# Mouse must be captured (no menu open) and attack action must be
	# HELD (not just-pressed) — held-swing accumulator gates progress
	# rather than per-press carve.
	#
	# Why polling instead of _unhandled_input: HUD Control nodes with
	# mouse_filter=STOP eat the event before _unhandled_input runs,
	# and the swing silently never fires. Polling the action state is
	# global.
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
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

	if not Input.is_action_pressed("attack"):
		_clear_target()
		return
	if _swing_cooldown_remaining > 0.0:
		# Animation reset window after a successful carve. Don't
		# accumulate during this — the player should feel a beat
		# between strikes.
		return

	_tick_held_swing(delta)


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
	var terrain: VoxelLodTerrain = VoxelEditManager.get_terrain()
	if terrain != null:
		var tool: VoxelTool = terrain.get_voxel_tool()
		if tool != null:
			tool.channel = VoxelBuffer.CHANNEL_COLOR
			var packed: int = tool.get_voxel(voxel_pos)
			var mat_id: int = packed & 0xFF
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


func _tick_held_swing(delta: float) -> void:
	# One frame of held-attack progress. Either advances the swing
	# accumulator, switches targets, or bails on whatever's gone
	# wrong (no equipped tool, no raycast hit, etc).

	# --- What's equipped? ---
	if not get_node_or_null("/root/InventoryManager"):
		return
	var equipped_id: String = InventoryManager.get_equipped("weapon")
	if equipped_id == "":
		_clear_target()
		return

	# --- Find the voxel the player is aiming at ---
	if _camera_rig == null:
		return
	var hit: Dictionary = _camera_rig.get_camera_forward_hit(max_reach_meters)
	if hit.is_empty():
		_clear_target()
		return

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
	# A material's allowed_tools list trumps the legacy
	# tool_target_materials field on the tool itself. Empty
	# allowed_tools = any tool works.
	if material.allowed_tools.size() > 0 and not (equipped_id in material.allowed_tools):
		# Wrong tool — don't accumulate. Could play a "wrong tool"
		# bark here later.
		_clear_target()
		return

	# --- Target stability + accumulate ---
	# Compute the integer voxel grid coord and compare. If the
	# player's looking at a different voxel than last frame, reset.
	var target_grid: Vector3i = VoxelEditManager.world_to_voxel(voxel_world_pos)
	if not _has_target or _current_target_voxel != target_grid:
		_current_target_voxel = target_grid
		_swing_time_on_target = 0.0
		_has_target = true

	_swing_time_on_target += delta

	if _swing_time_on_target < material.mining_time_seconds:
		# Still swinging.
		return

	# --- Carve ---
	_carve(voxel_world_pos, material, equipped_id)
	_swing_time_on_target = 0.0
	_swing_cooldown_remaining = swing_cooldown_seconds


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
	if not get_node_or_null("/root/VoxelEditManager"):
		push_warning("[EditToolHandler] VoxelEditManager autoload not registered")
		return
	var accepted: bool = VoxelEditManager.queue_edit_sphere(
		voxel_world_pos, swing_carve_radius_meters, AIR_VOXEL
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

	# --- Yield raw material into inventory ---
	# Material drives both the item id AND the quantity. Empty
	# yield_item_id means "this material gives nothing on harvest"
	# (rare — perhaps placeholder voxels for level geometry).
	if material.yield_item_id != "":
		InventoryManager.add_item(material.yield_item_id, material.yield_quantity)

	# --- Award Crafting sub-skill XP ---
	# Each tool maps to its corresponding sub-skill (mining/felling/
	# excavation). XP rolls up to the Crafting domain tier.
	if get_node_or_null("/root/GameState"):
		var sub_skill: String = TOOL_SUB_SKILLS.get(equipped_id, "")
		var xp_amount: int = TOOL_XP_PER_EDIT.get(equipped_id, 0)
		if sub_skill != "" and xp_amount > 0:
			GameState.add_skill_xp(GameState.SkillDomain.CRAFTING, sub_skill, xp_amount)
