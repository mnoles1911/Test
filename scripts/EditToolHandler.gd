extends Node3D

const WaterMaterial := preload("res://scripts/WaterMaterial.gd")

# EditToolHandler â€” handles "swing tool, edit voxel" input.
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
# silently by VoxelEditManager â€” if it returns false, we print a
# placeholder rejection message until the bark system is wired up.
#
# Attached as a child of Player3D in scenes/Player3D.tscn so it
# inherits the player's transform and lives in the player scene.
#
# Reference: design/3D_VOXEL_MIGRATION.md â†’ "Player Edit Verbs"


# =============================================================
# CONFIGURATION
# =============================================================

@export var max_reach_meters: float = 3.5
# How far forward the ray casts when looking for a voxel surface.
# 3.5m is the design-locked manual-tool reach (2026-05-05): mid-
# range of the 3-4m design window â€” about arm-length plus a
# comfortable forward stride. Prevents mining voxels that aren't
# credibly within striking distance. Raise for longer-haft tools
# (e.g. dwarven war-pickaxe) in a future per-tool config.

@export var swing_cooldown_seconds: float = 0.4
# Animation-pacing cooldown that runs AFTER a successful carve. The
# cycle is: player holds LMB â†’ swing time accumulates against the
# target voxel's mining_time_seconds â†’ when full, voxel breaks AND
# swing_cooldown_seconds locks input briefly so the swing animation
# has room to reset between voxels. Without this cooldown, breaking
# soft materials (sand, dirt) would spam multiple voxels per
# frame the moment mining_time hit zero.

@export var swing_carve_voxels_per_side: int = 3
# Default carve volume on world load. Manual tools (pickaxe / shovel /
# axe) carve a CUBE this many voxels on a side per swing â€” runtime
# value lives in `carve_volume_size` (which the player adjusts via
# scroll wheel between 1 and `swing_carve_voxels_per_side`). 3Ã—3Ã—3
# = 27 voxels feels like a "good hit" at third-person distance.
#
# Implementation note: we used to use a sphere radius for this, but
# spheres carve roughly half their voxel volume due to the spherical
# packing â€” a 0.15 m sphere clears ~3-5 voxels, hard to predict and
# inconsistent across orientations. A box is exactly NÃ—NÃ—N voxels
# regardless of camera angle, easier to tune.

const AIR_VOXEL: int = 0
# Voxel value 0 = air. Writing this removes the voxel.

const WRONG_TOOL_SPEED_MULTIPLIER: float = 3.0
# Mining a material with a non-preferred tool takes 3× the baseline
# swing time. The material's `allowed_tools` list now acts as the
# PREFERRED-tools list — equipping a tool from the list mines at
# 1.0× speed, equipping any other manual tool mines at this
# multiplier instead. Empty `allowed_tools` (bedrock) still rejects
# every tool — the multiplier doesn't apply, the swing is blocked
# entirely. So in practice:
#   pickaxe on stone     = 1.0× (preferred)
#   shovel on stone      = 3.0× (mismatch — chip through slowly)
#   shovel on dirt/grass = 1.0× (preferred)
#   pickaxe on dirt/grass= 3.0× (mismatch — pickaxe is bad at soil)
#   any tool on bedrock  = blocked (allowed_tools is empty)

# Mining-volume anchor: how the carve box is positioned around the
# voxel the player is aiming at. Player can flip between these in the
# Settings overlay (which writes to Settings.mining_volume_anchor —
# we read it lazily via _get_mining_anchor()).
enum MiningAnchor {
	# Bias the box INTO the terrain along the surface normal axis.
	# 3×3×3 against a wall = 27 terrain voxels (no wasted air slab).
	# DEFAULT — matches Minecraft / Vintage Story conventions: aim
	# at a surface, the carve fills the terrain side.
	DEPTH_BIASED,
	# Symmetric box centred on the surface voxel. The aim point sits
	# in the box's middle, but on a flat cliff face one slab of the
	# carve is air (the side facing the player). Useful for precision
	# work where you want predictable visual centering.
	CENTERED,
}

# Map from equipped tool item_id to the Crafting sub-skill that gets
# XP on a successful edit. Pickaxe â†’ mining, axe â†’ felling, etc.
# Sub-skill names match the design doc XP_VALUES table in
# design/SKILLS_AND_PROGRESSION.md.
const TOOL_SUB_SKILLS: Dictionary = {
	"iron_pickaxe": "mining",
	"iron_axe":     "felling",
	"iron_shovel":  "excavation",
}

# XP awarded per successful single-voxel edit. Matches the design
# doc's XP_VALUES entries (ore_mined=5, tree_felled=8, earth_dug=2).
# A bigger edit (sphere via explosives) awards more â€” per-edit value
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
# looks at a different voxel â€” partial mining doesn't carry across
# voxels.

var _has_target: bool = false
# False when the player isn't aiming at any voxel (raycast missed
# or attack not held). Distinct from "target = (0,0,0)" since
# (0,0,0) is a valid voxel position.

var _swing_time_on_target: float = 0.0
# Accumulated seconds the player has been holding LMB against
# `_current_target_voxel`. When it reaches the target voxel
# material's `mining_time_seconds * (N³ / 8)` (volume-scaled), the
# carve fires.

# Runtime carve volume â€” 1, 2, or 3 voxels per side. Player cycles
# this with the mouse scroll wheel while a manual tool is equipped.
# HUD reads this to show the "Volume: 1Ã—1Ã—1" line in the bottom-left.
var carve_volume_size: int = 3

# Aim-outline visualisation â€” a translucent emissive box drawn at
# the voxel volume the player is currently aiming at. Only visible
# in mining mode with a manual tool equipped, so the player can see
# what their next swing will remove. Built in _ready, repositioned
# every physics frame from the camera raycast.
var _aim_outline: MeshInstance3D
var _aim_outline_mesh: BoxMesh
var _aim_outline_material: Material  # ShaderMaterial (default v2) or StandardMaterial3D (v1 fallback)

var _held_log_counter: int = 0
# Throttle counter for held-swing diagnostic prints â€” only print
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

# Continuous dig-loop SFX (see _update_dig_loop). Plays while the player
# holds the mine button with a manual tool; the per-carve strike (in
# _carve) is separate. 0 = not playing.
var _dig_loop_handle: int = 0
var _dig_loop_id: String = ""


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
	#   â”œâ”€â”€ EditToolHandler (this node)
	#   â”œâ”€â”€ CameraTarget
	#   â”‚   â””â”€â”€ SpringArm3D (CameraRig.gd)  â† target
	#   â””â”€â”€ ...
	var player := get_parent() as CharacterBody3D
	if player == null:
		push_error("[EditToolHandler] Parent must be Player3D (CharacterBody3D)")
		return
	_camera_rig = player.get_node_or_null("CameraTarget/SpringArm3D")
	if _camera_rig == null:
		push_error("[EditToolHandler] CameraTarget/SpringArm3D not found under Player3D")

	# Initial carve volume from the @export default. Player can change
	# at runtime via scroll wheel; clamp to [1, swing_carve_voxels_per_side].
	carve_volume_size = clampi(swing_carve_voxels_per_side, 1, swing_carve_voxels_per_side)

	# Build the aim-outline mesh. top_level = true so global_position
	# is world-space, not relative to the player's transform â€” the
	# outline is anchored to where the player is aiming, not to
	# Roland himself.
	_build_aim_outline()


func _build_aim_outline() -> void:
	# Edge-only outline on the targeted voxel BoxMesh (v2 2026-05-27).
	# v1 was a translucent emissive cyan FILL — designer wanted Minecraft-
	# style WIREFRAME edges, not a solid see-through cube. Switched to a
	# ShaderMaterial that draws the 12 cube edges only (see
	# assets/shaders/selection_outline.gdshader). Bright cyan + emission
	# so it pops against any terrain tint. cull_disabled + depth_test_off
	# so the player sees the outline from inside the box AND through
	# occluding terrain — matches v1's effective visibility.
	#
	# If the shader fails to load (asset import order edge case), fall
	# back to the v1 StandardMaterial3D fill so the player still has SOME
	# targeting feedback. The shader is asset-pipeline simple (no atlas
	# dep, no textures) so load failures are unlikely.
	var shader: Shader = load("res://assets/shaders/selection_outline.gdshader") as Shader
	if shader != null:
		var smat := ShaderMaterial.new()
		smat.shader = shader
		_aim_outline_material = smat
	else:
		push_warning("[EditToolHandler] selection_outline.gdshader missing; falling back to v1 fill material.")
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color(0.25, 0.95, 1.0, 0.30)
		fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fallback.emission_enabled = true
		fallback.emission = Color(0.30, 1.0, 1.0, 1.0)
		fallback.emission_energy_multiplier = 1.6
		fallback.cull_mode = BaseMaterial3D.CULL_DISABLED
		fallback.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fallback.disable_receive_shadows = true
		_aim_outline_material = fallback

	_aim_outline_mesh = BoxMesh.new()
	# Default size â€” overwritten each frame in _update_aim_outline().
	_aim_outline_mesh.size = Vector3.ONE * 0.5

	_aim_outline = MeshInstance3D.new()
	_aim_outline.mesh = _aim_outline_mesh
	_aim_outline.material_override = _aim_outline_material
	_aim_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_outline.top_level = true
	_aim_outline.visible = false
	add_child(_aim_outline)


func _update_aim_outline() -> void:
	# Show the outline whenever a manual tool is equipped and the
	# player is actually aiming at a voxel within reach. All other
	# states hide.
	if _aim_outline == null:
		return
	# Respect the GraphicsManager debug toggle (Phase K bundle, 2026-05-27).
	# Designer can hide the outline from the DebugOverlay GRAPHICS sub-view
	# without touching any other effect; master toggle folds in too.
	var gm := get_node_or_null("/root/GraphicsManager")
	if gm != null and not gm.is_effect_enabled("selection_outline"):
		_aim_outline.visible = false
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_aim_outline.visible = false
		return
	if get_node_or_null("/root/InventoryManager") == null:
		_aim_outline.visible = false
		return
	var equipped: String = InventoryManager.get_equipped("weapon")
	if not (equipped in TOOL_SUB_SKILLS):
		_aim_outline.visible = false
		return
	if _camera_rig == null:
		_aim_outline.visible = false
		return
	var hit: Dictionary = _camera_rig.get_camera_forward_hit(max_reach_meters)
	if hit.is_empty():
		_aim_outline.visible = false
		return
	# Verify the hit is within reach of the PLAYER body, not just the
	# camera arm â€” same gate as _tick_held_action so the outline
	# only shows where the swing would actually land.
	var hit_pos: Vector3 = hit.get("position", Vector3.ZERO)
	var hit_normal: Vector3 = hit.get("normal", Vector3.UP)
	var player := get_parent() as CharacterBody3D
	if player != null and player.global_position.distance_to(hit_pos) > max_reach_meters:
		_aim_outline.visible = false
		return

	# Mirror the carve box computation from _carve via the shared
	# helper so the outline exactly matches what an LMB press will
	# remove — including the depth-bias along the surface normal.
	var voxel_world_pos: Vector3 = hit_pos - hit_normal * 0.1
	const VOXELS_PER_METER: float = 6.0
	const VOXEL_SIZE_M: float = 1.0 / VOXELS_PER_METER
	var centre_voxel: Vector3i = Vector3i(
		floori(voxel_world_pos.x * VOXELS_PER_METER),
		floori(voxel_world_pos.y * VOXELS_PER_METER),
		floori(voxel_world_pos.z * VOXELS_PER_METER),
	)
	var box: Array = _compute_carve_box(centre_voxel, hit_normal, carve_volume_size)
	var box_vmin: Vector3i = box[0]
	var box_vmax: Vector3i = box[1]
	# World-space size = N voxels × VOXEL_SIZE_M. World-space centre
	# is the midpoint of the inclusive voxel range — `(vmin + vmax + 1)
	# * 0.5 / VPM` because vmin/vmax are voxel INDICES (each voxel
	# occupies the span i .. i+1 in world units after the /VPM scale),
	# so the "+1" pushes vmax to the FAR face of its voxel.
	# Tiny scale fudge (×1.02) so the outline sits just outside the
	# cube faces and z-fights less with the terrain mesh.
	var size_m: float = float(carve_volume_size) * VOXEL_SIZE_M
	_aim_outline_mesh.size = Vector3.ONE * size_m * 1.02
	var centre_world: Vector3 = (
		(Vector3(box_vmin) + Vector3(box_vmax) + Vector3.ONE) * 0.5 / VOXELS_PER_METER
	)
	_aim_outline.global_position = centre_world
	# Phase K bundle v2 (2026-05-27): push the BoxMesh half-extents to the
	# outline shader so its object-space edge detection knows where the cube
	# faces sit. Without this the v2 shader assumes a 1m³ box (default
	# uniform) and outlines collapse / disappear when carve_volume_size != 6.
	if _aim_outline_material is ShaderMaterial:
		var half: float = size_m * 1.02 * 0.5
		(_aim_outline_material as ShaderMaterial).set_shader_parameter(
			"mesh_half_size", Vector3(half, half, half))
	_aim_outline.visible = true


func _input(event: InputEvent) -> void:
	# Scroll wheel cycles the carve volume size when a manual tool is
	# equipped and the mouse is captured. accept_event() (via
	# set_input_as_handled) prevents CameraRig from also seeing the
	# scroll for camera-arm zoom.
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed:
		return
	# Only cycle when a manual tool is equipped â€” otherwise scroll
	# stays as zoom for buckets / throwables / unequipped.
	if get_node_or_null("/root/InventoryManager") == null:
		return
	var equipped: String = InventoryManager.get_equipped("weapon")
	if not (equipped in TOOL_SUB_SKILLS):
		return
	var max_size: int = max(1, swing_carve_voxels_per_side)
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		carve_volume_size = clampi(carve_volume_size + 1, 1, max_size)
		get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		carve_volume_size = clampi(carve_volume_size - 1, 1, max_size)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# Aim-outline visibility + position update. Runs every frame
	# (cheap — one raycast already done elsewhere, plus a
	# global_position write). Hidden when no manual tool is equipped.
	_update_aim_outline()

	# Continuous dig-loop SFX. Called every frame BEFORE the early-return
	# gates below so it always runs and self-corrects (it stops itself
	# the moment the player isn't holding-to-mine — no stuck loop).
	_update_dig_loop()

	# Tick the post-carve cooldown.
	if _swing_cooldown_remaining > 0.0:
		_swing_cooldown_remaining -= delta

	# Diagnostic: log the moment the LMB is JUST pressed, regardless
	# of any other gate. Tells us "is the input even reaching this
	# script?" â€” the answer to the user's "left click does nothing".
	if Input.is_action_just_pressed("attack"):
		var mm: int = Input.mouse_mode
		var equipped_dbg: String = "(no InventoryManager)"
		if get_node_or_null("/root/InventoryManager"):
			equipped_dbg = InventoryManager.get_equipped("weapon")
		print("[EditTool] LMB just_pressed | mouse_mode=%d (need 2=CAPTURED) | equipped=%s | cooldown=%.2f" % [
			mm, equipped_dbg, _swing_cooldown_remaining,
		])

	# Mouse must be captured (no menu open) and attack action must be
	# HELD (not just-pressed) â€” held-swing accumulator gates progress
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
	# LMB held â†’ mine. Cooldown gates between successful swings so
	# the player feels a beat between strikes.
	if not Input.is_action_pressed("attack"):
		_clear_target()
		return
	if _swing_cooldown_remaining > 0.0:
		return

	_tick_held_action(delta)


func _handle_bucket_click(equipped: String) -> void:
	# Bucket use is one-shot per click. Two states:
	#   "bucket"        : swing at water (any source region or flow
	#                     cell within reach) â†’ fill the bucket.
	#   "bucket_filled" : swing at empty space â†’ place a permanent
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
	# region, swap the bucket â†’ bucket_filled. Otherwise no-op.
	if not WaterFlowManager.is_position_in_water(world_pos):
		# Also try the player's feet â€” Roland is standing in water.
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
	# CLAUDE.md "Critical patterns" rule â€” never decode the alpha byte
	# by hand.
	var terrain: VoxelLodTerrain = VoxelEditManager.get_terrain()
	if terrain != null:
		var tool: VoxelTool = terrain.get_voxel_tool()
		if tool != null:
			tool.channel = VoxelBuffer.CHANNEL_TYPE
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
	mining_active = false
	mining_progress = 0.0
	mining_material_label = ""


func _tick_held_action(delta: float) -> void:
	# One frame of LMB-held mining progress. Drives the swing
	# accumulator (_swing_time_on_target) toward the per-material
	# `mining_time_seconds` (volume-scaled), then fires `_carve` and
	# starts the post-swing cooldown.
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

	# --- Read the aimed voxel's material (for the per-swing yield) ---
	# The aimed-voxel material drives the inventory yield from
	# _spawn_voxel_drop in _carve. Mining time uses the SLOWEST
	# material in the carve box (see below) so a 1-grass + 26-stone
	# 3×3×3 carve doesn't get a fast grass swing time.
	var material: VoxelMaterial = _read_material_at(voxel_world_pos)
	if material == null:
		# Voxel is air, registry isn't loaded, or the read failed.
		# No swing progress.
		_clear_target()
		return

	# --- Mixed-volume mining time (slowest-wins) ---
	# The carve box may span multiple materials. Sample EVERY voxel
	# in the box, compute its per-voxel time (mining_time_seconds ×
	# tool_multiplier for that voxel's material), take the max, then
	# apply the carve-volume multiplier. This means the swing speed
	# is set by the hardest material in the box — exactly like real
	# digging where stone in your dirt is the limiter.
	#
	# Aiming reticle position no longer games the swing time: a
	# stone voxel anywhere in the 3×3×3 box makes the swing as slow
	# as a pure-stone carve, regardless of where the crosshair lies.
	var centre_voxel: Vector3i = Vector3i(
		floori(voxel_world_pos.x * 6.0),
		floori(voxel_world_pos.y * 6.0),
		floori(voxel_world_pos.z * 6.0),
	)
	var box: Array = _compute_carve_box(centre_voxel, hit_normal, carve_volume_size)
	var box_vmin: Vector3i = box[0]
	var box_vmax: Vector3i = box[1]
	var mix: Dictionary = _compute_mixed_volume_mine_secs(box_vmin, box_vmax, equipped_id)
	if mix["blocked"]:
		# At least one voxel in the box is unmineable (bedrock).
		# VoxelEditManager will reject the carve anyway, so don't
		# even start the swing.
		if should_log:
			print("[EditTool] UNMINEABLE voxel in box (e.g. bedrock); swing blocked")
		_clear_target()
		return
	var slowest_per_voxel: float = float(mix["secs"])
	var slowest_mat: VoxelMaterial = mix["material"]
	if slowest_per_voxel <= 0.0 or slowest_mat == null:
		# Whole box is air. Aim is off the surface.
		_clear_target()
		return

	# Mining-volume time scaling. The slowest per-voxel time is the
	# swing time for the 2×2×2 (= 8 voxels) baseline. Scale
	# proportionally to the actual voxel count being carved:
	#   N=1 (1 vox)  → multiplier 1/8  = 0.125× (fast precision dig)
	#   N=2 (8 vox)  → multiplier 8/8  = 1.0×   (baseline, unchanged)
	#   N=3 (27 vox) → multiplier 27/8 ≈ 3.375× (slow bulk dig)
	var voxel_count: int = carve_volume_size * carve_volume_size * carve_volume_size
	var volume_multiplier: float = float(voxel_count) / 8.0
	var mine_secs: float = slowest_per_voxel * volume_multiplier

	# DEV: instant-mine accelerator (DebugOverlay COMMANDS tab →
	# TOGGLE INSTANT MINE, default OFF). Zero the per-swing mining
	# time so one click carves the aimed voxel box immediately —
	# turns slow multi-chunk test excavations (e.g. validating water
	# flood coverage) into a few clicks. The post-carve swing cooldown
	# below still paces held repeats; NoEditZone / bedrock rejection
	# and the carve path itself are unchanged. No effect unless a dev
	# explicitly enabled it this session.
	var _dbg: Node = get_node_or_null("/root/DebugOverlay")
	if _dbg != null and bool(_dbg.get("instant_mine_enabled")):
		mine_secs = 0.0

	# --- Target stability + accumulate ---
	# Compute the integer voxel grid coord and compare. If the
	# player's looking at a different voxel than last frame, reset.
	var target_grid: Vector3i = VoxelEditManager.world_to_voxel(voxel_world_pos)
	if not _has_target or _current_target_voxel != target_grid:
		_current_target_voxel = target_grid
		_swing_time_on_target = 0.0
		_has_target = true

	_swing_time_on_target += delta

	# Public state for the HUD progress bar. Label shows the SLOWEST
	# material so the player sees what's gating the swing time
	# (e.g. "STONE" for a mostly-grass carve that contains stone).
	mining_active = true
	mining_progress = clampf(
		_swing_time_on_target / maxf(mine_secs, 0.0001),
		0.0,
		1.0,
	)
	mining_material_label = slowest_mat.display_name

	if _swing_time_on_target < mine_secs:
		# Still swinging.
		return

	# --- Swing complete: carve ---
	_carve(voxel_world_pos, material, equipped_id, hit_normal)
	_swing_time_on_target = 0.0
	_swing_cooldown_remaining = swing_cooldown_seconds
	# Snap the bar to "complete" briefly. _clear_target / next tick
	# will reset it. Keeps the HUD honest â€” it shows 100% in the
	# moment the action fires.
	mining_progress = 1.0


func _compute_carve_box(centre_voxel: Vector3i, hit_normal: Vector3, n: int) -> Array:
	# Compute the [vmin, vmax] voxel-grid bounds for the carve box,
	# applying the player's MiningAnchor preference.
	#
	# Asymmetric half_lo / half_hi split for even N. A 2×2×2 carve has
	# no exact symmetric anchoring around a single voxel — biasing
	# toward +X/+Y/+Z keeps the aimed voxel as the box's MIN corner
	# so an even-N carve never accidentally extends "behind" the
	# player's aim point.
	#   half_lo = (N-1)/2, half_hi = N/2
	#   N=1: lo=0, hi=0 → [c, c]       (1 voxel)
	#   N=2: lo=0, hi=1 → [c, c+1]     (2 voxels)
	#   N=3: lo=1, hi=1 → [c-1, c+1]   (3 voxels)
	#   N=4: lo=1, hi=2 → [c-1, c+2]   (4 voxels)
	@warning_ignore("integer_division")
	var half_lo: int = (n - 1) / 2
	@warning_ignore("integer_division")
	var half_hi: int = n / 2
	var vmin: Vector3i = centre_voxel - Vector3i(half_lo, half_lo, half_lo)
	var vmax: Vector3i = centre_voxel + Vector3i(half_hi, half_hi, half_hi)

	# DEPTH_BIASED (default): shift the box INTO the terrain along
	# the dominant axis of the surface normal. The surface voxel
	# becomes the box's corner closest to the player, so 3×3×3
	# against a wall is 27 terrain voxels instead of 18 + 9 air.
	# CENTERED: leave vmin/vmax symmetric around centre_voxel.
	if _get_mining_anchor() == MiningAnchor.DEPTH_BIASED \
			and hit_normal.length_squared() > 0.0001:
		var n_abs: Vector3 = hit_normal.abs()
		var bias: Vector3i = Vector3i.ZERO
		if n_abs.x >= n_abs.y and n_abs.x >= n_abs.z:
			bias.x = -int(sign(hit_normal.x)) * half_hi
		elif n_abs.y >= n_abs.z:
			bias.y = -int(sign(hit_normal.y)) * half_hi
		else:
			bias.z = -int(sign(hit_normal.z)) * half_hi
		vmin += bias
		vmax += bias

	return [vmin, vmax]


func _compute_mixed_volume_mine_secs(
	box_vmin: Vector3i, box_vmax: Vector3i, equipped_id: String,
) -> Dictionary:
	# Sample every voxel in the [box_vmin, box_vmax] inclusive range
	# and compute the SLOWEST per-voxel mining time across all
	# non-air voxels.
	#
	# Per-voxel time = material.mining_time_seconds × tool_multiplier
	# where tool_multiplier is 1.0 if `equipped_id` is in
	# `material.allowed_tools` (the preferred-tools list) or
	# WRONG_TOOL_SPEED_MULTIPLIER otherwise.
	#
	# Returns:
	#   {
	#     "secs":     float,           # slowest per-voxel time
	#     "material": VoxelMaterial,   # the material that won the max
	#     "blocked":  bool,            # true if any voxel is unmineable
	#                                  # (allowed_tools empty, e.g. bedrock)
	#   }
	# `blocked = true` overrides everything — the caller should bail
	# because VoxelEditManager will reject the carve. If the box is
	# entirely air, secs = 0 and material = null (caller should bail).
	#
	# Cost: up to 27 tool.get_voxel calls per held tick (3×3×3 box).
	# Cheap enough to run every frame the swing is held — comparable
	# to what _update_aim_outline already does.
	var result: Dictionary = {
		"secs": 0.0,
		"material": null,
		"blocked": false,
	}
	if not get_node_or_null("/root/VoxelEditManager"):
		return result
	var terrain: VoxelLodTerrain = VoxelEditManager.get_terrain()
	if terrain == null:
		return result
	var tool: VoxelTool = terrain.get_voxel_tool()
	if tool == null:
		return result
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	var registry := get_node_or_null("/root/VoxelMaterialRegistry")
	if registry == null:
		return result

	for x in range(box_vmin.x, box_vmax.x + 1):
		for y in range(box_vmin.y, box_vmax.y + 1):
			for z in range(box_vmin.z, box_vmax.z + 1):
				var packed: int = tool.get_voxel(Vector3i(x, y, z))
				var mat_id: int = packed & 0xFF
				if mat_id == 0:
					continue  # air contributes nothing
				var mat: VoxelMaterial = registry.get_by_id(mat_id)
				if mat == null:
					continue  # unknown material — defensive skip
				if mat.allowed_tools.size() == 0:
					# Unmineable (bedrock). Whole swing blocked.
					result["blocked"] = true
					result["material"] = mat
					return result
				var tool_mult: float = 1.0
				if not (equipped_id in mat.allowed_tools):
					tool_mult = WRONG_TOOL_SPEED_MULTIPLIER
				var per_voxel_secs: float = mat.mining_time_seconds * tool_mult
				if per_voxel_secs > float(result["secs"]):
					result["secs"] = per_voxel_secs
					result["material"] = mat
	return result


func _get_mining_anchor() -> int:
	# Read the player's preference from the Settings autoload. Falls
	# back to DEPTH_BIASED (the recommended default) if the autoload
	# isn't registered or the field is missing.
	var settings_node := get_node_or_null("/root/Settings")
	if settings_node != null and "mining_volume_anchor" in settings_node:
		return int(settings_node.mining_volume_anchor)
	return MiningAnchor.DEPTH_BIASED


func _read_material_at(world_pos: Vector3) -> VoxelMaterial:
	# Read the voxel at world_pos, get the material_id from
	# CHANNEL_TYPE, look up the VoxelMaterial in the registry. Returns
	# null if the voxel is air, the registry isn't available, or the
	# read fails for any other reason.
	#
	# Reads the same channel the generator writes (CHANNEL_TYPE).
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
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	var grid_pos: Vector3i = VoxelEditManager.world_to_voxel(world_pos)
	var packed: int = tool.get_voxel(grid_pos)
	if (packed & 0xFF) == 0:
		# Air. Probably aimed at the wrong cell (sub-voxel margin).
		return null
	if not get_node_or_null("/root/VoxelMaterialRegistry"):
		return null
	var material_id: int = packed & 0xFF
	# Water Voxel V2 (2026-05-17): water is TYPE id 5. Terrain tools
	# (shovel/pickaxe/axe) must NOT mine water like dirt — water and
	# terrain "work differently". Returning null here makes the dig
	# path treat a water-targeted swing as "nothing to mine" (the swing
	# passes through). Water interaction is bucket-only (which uses
	# WaterFlowManager.is_position_in_water, not this function).
	if WaterMaterial.is_water_type(material_id):
		return null
	return VoxelMaterialRegistry.get_by_id(material_id)


func _carve(voxel_world_pos: Vector3, material: VoxelMaterial, equipped_id: String, hit_normal: Vector3) -> void:
	# Apply the voxel edit, yield the material's item, and award
	# crafting XP. Called once per successful held-swing completion.
	#
	# Carve shape: an N×N×N box of voxels positioned by
	# `_compute_carve_box`. Position depends on the player's
	# Settings.mining_volume_anchor preference (DEPTH_BIASED default
	# vs CENTERED). `hit_normal` lets the helper bias the box INTO
	# the terrain along the surface-normal axis so a cliff-face
	# carve is fully terrain-filled, not 1/3 wasted on air.
	if not get_node_or_null("/root/VoxelEditManager"):
		push_warning("[EditToolHandler] VoxelEditManager autoload not registered")
		return
	# Compute the carve box in integer voxel-grid coordinates.
	# Using queue_edit_box (world-space) caused _terrain.to_local() to
	# return -0.999... instead of -1.0 due to FP rounding, collapsing
	# the 3×3×3 carve to 1×1×1 after truncation. Integer arithmetic
	# avoids the conversion entirely.
	const VOXELS_PER_METER: float = 6.0
	var centre_voxel: Vector3i = Vector3i(
		floori(voxel_world_pos.x * VOXELS_PER_METER),
		floori(voxel_world_pos.y * VOXELS_PER_METER),
		floori(voxel_world_pos.z * VOXELS_PER_METER),
	)
	var box: Array = _compute_carve_box(centre_voxel, hit_normal, carve_volume_size)
	var box_vmin: Vector3i = box[0]
	var box_vmax: Vector3i = box[1]
	var accepted: bool = VoxelEditManager.queue_edit_box_voxels(
		box_vmin, box_vmax, AIR_VOXEL
	)
	if not accepted:
		# Rejected by NoEditZone. Bark trigger lives on
		# VoxelEditManager.edit_rejected_no_edit_zone â€” no per-call
		# action needed here.
		if get_node_or_null("/root/DebugOverlay"):
			DebugOverlay.log_action("Edit rejected: NoEditZone at %s" % voxel_world_pos)
		else:
			print("[EditToolHandler] This place doesn't yield to me.")
		return

	# Dig SFX — one strike per accepted carve. Tool + material are both
	# known here. No-op-safe: silent (one notice) until the vox_* .ogg/
	# .mp3 are curated in, then automatic. (NoEditZone rejects took the
	# early return above and are handled by AudioManager's subscription
	# to edit_rejected_no_edit_zone -> vox_bedrock_blocked.)
	var _am := get_node_or_null("/root/AudioManager")
	if _am != null:
		_am.play(_dig_sfx_id(equipped_id, material.id_string), voxel_world_pos)

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
	# Acceptable for first-pass â€” a real majority sample would mean
	# reading all 27 voxels before each carve, which is expensive
	# and not visibly different to the player most of the time.
	#
	# Color from material.color_low so the drop visually matches
	# what was just broken (green grass â†’ green cube, etc.). When
	# yield_item_id is empty, no drop spawns (rare placeholder
	# materials with no harvest).
	if material.yield_item_id != "":
		_spawn_voxel_drop(
			voxel_world_pos,
			material.yield_item_id,
			material.color_low,
			material.yield_quantity,
		)

	# --- Award flat-skill XP through SkillManager ---
	# Each tool maps to its corresponding skill (mining / felling /
	# excavation). The sub_skill name in TOOL_SUB_SKILLS happens to
	# match the canonical skill name 1:1, so no translation table is
	# needed. Also dispatch on_voxel_broken so any active perks (Vein
	# Sense, Swing Through, Lucky Strike, etc) can react.
	if get_node_or_null("/root/SkillManager"):
		var skill: String = TOOL_SUB_SKILLS.get(equipped_id, "")
		var xp_amount: int = TOOL_XP_PER_EDIT.get(equipped_id, 0)
		if skill != "" and xp_amount > 0:
			SkillManager.add_xp(skill, float(xp_amount))
			SkillManager.dispatch("on_voxel_broken", {
				"skill": skill,
				"tool_id": equipped_id,
			})


func _spawn_voxel_drop(world_pos: Vector3, drop_item_id: String, color: Color, count: int) -> void:
	# Spawn a single VoxelDrop pickup at the carve site. Parented to
	# the World3D root (not the player) so the drop stays where it
	# fell when the player walks away. queue_free is handled by the
	# drop itself via the despawn timer or pickup proximity.
	#
	# We pick the parent by walking up to the player's parent (the
	# World3D scene root). If that's null for any reason, we fall
	# back to current_scene; if even that's null, the drop just
	# doesn't spawn â€” degraded but not crashing.
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


# Map (equipped tool item_id, voxel material id_string) -> a Cat-04 vox_*
# SFX id. Preferred tool+material combos get the dedicated strike; any
# mismatch (and axe, whose dedicated wood set is a later sub-phase) falls
# back to the wrong-tool scrape, hard vs soft. See SFX_PROMPTS.md §7b.
func _dig_sfx_id(equipped_id: String, mat: String) -> String:
	var hard := mat in [
		"stone", "marble", "bedrock", "stone_dark", "copper_ore", "iron_ore"
	]
	var tool := ""
	if "pickaxe" in equipped_id:
		tool = "pick"
	elif "shovel" in equipped_id:
		tool = "shovel"
	elif "axe" in equipped_id:
		tool = "axe"
	if tool == "pick" and hard:
		return "vox_pick_strike_stone"
	if tool == "shovel" and not hard:
		if mat == "grass" or mat == "leaves":
			return "vox_shovel_strike_grass"
		if mat == "sand" or mat == "gravel":
			return "vox_shovel_strike_sand"
		return "vox_shovel_strike_dirt"   # dirt/clay/snow/other soft
	# Wrong tool for the material (incl. axe until its set is rendered).
	return "vox_wrongtool_stone" if hard else "vox_wrongtool_soft"


func _update_dig_loop() -> void:
	# Continuous "I'm digging" loop while the mine button is HELD with a
	# manual tool (separate from the per-carve strike in _carve). Fully
	# self-correcting: recomputes the wanted loop every frame and stops
	# the instant the player isn't mining, so it can never get stuck.
	var want_id := ""
	if Input.is_action_pressed("attack") \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and get_node_or_null("/root/InventoryManager"):
		var eq: String = InventoryManager.get_equipped("weapon")
		if eq in TOOL_SUB_SKILLS:   # a manual tool (pick/shovel/axe)
			want_id = "vox_dig_loop_hard" if "pickaxe" in eq \
				else "vox_dig_loop_soft"
	var am := get_node_or_null("/root/AudioManager")
	if am == null:
		return
	if want_id == "":
		if _dig_loop_handle != 0:
			am.stop_loop(_dig_loop_handle)
			_dig_loop_handle = 0
			_dig_loop_id = ""
		return
	if want_id != _dig_loop_id:
		if _dig_loop_handle != 0:
			am.stop_loop(_dig_loop_handle)
			_dig_loop_handle = 0
		var h: int = am.play_loop(want_id)
		# Only latch the id if it actually started — if the file isn't
		# imported yet (h == 0) leave it unset so we retry next frame
		# (works with AudioManager's no-cache-on-miss fix).
		if h != 0:
			_dig_loop_handle = h
			_dig_loop_id = want_id


func _exit_tree() -> void:
	# Don't leak the dig loop on scene change / node removal.
	var am := get_node_or_null("/root/AudioManager")
	if am != null and _dig_loop_handle != 0:
		am.stop_loop(_dig_loop_handle)
