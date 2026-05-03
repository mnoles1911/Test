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
# Minimum seconds between swings. Prevents holding LMB from being a
# continuous voxel-eraser at frame rate. Real animation will replace
# this once Roland's rig has tool-swing animations.

const AIR_VOXEL: int = 0
# Voxel value 0 = air. Writing this removes the voxel.

# Map from voxel-material-tag (set by the generator) to the raw
# material item ID yielded when the player removes that voxel.
#
# For the slice, all voxels are tagged "stone" because
# VoxelGeneratorFlat writes voxel_type=1 uniformly. When we add
# real material tagging via VoxelGeneratorGraph + a material
# library, this mapping expands.
const VOXEL_MATERIAL_YIELDS: Dictionary = {
	"stone": "raw_stone",
	"wood":  "raw_log",
	"dirt":  "raw_dirt",
}

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
	if _swing_cooldown_remaining > 0.0:
		_swing_cooldown_remaining -= delta


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("attack"):
		return
	if _swing_cooldown_remaining > 0.0:
		return

	# --- What's equipped? ---
	if not get_node_or_null("/root/InventoryManager"):
		return
	var equipped_id: String = InventoryManager.get_equipped("weapon")
	if equipped_id == "":
		return

	# Look up the equipped item. Tools have a tool_target_materials
	# field; non-tools (regular weapons) don't, so they fall through
	# to the combat handler when that lands.
	var item_data: Dictionary = InventoryManager.ITEM_REGISTRY.get(equipped_id, {})
	var target_materials: Array = item_data.get("tool_target_materials", [])
	if target_materials.is_empty():
		# Equipped item is not a terrain-edit tool. Combat handler
		# would handle it — but combat is not wired yet.
		return

	# --- Find the voxel the player is aiming at ---
	if _camera_rig == null:
		return
	var hit: Dictionary = _camera_rig.get_camera_forward_hit(max_reach_meters)
	if hit.is_empty():
		# Aimed at empty space — no voxel to edit. Still spend the
		# cooldown so spam-clicking doesn't bypass swing pacing.
		_swing_cooldown_remaining = swing_cooldown_seconds
		return

	# Offset slightly INTO the surface so we target the solid voxel,
	# not the air voxel above it. The raycast hits the surface; the
	# voxel center is just inside.
	var hit_pos: Vector3 = hit.get("position", Vector3.ZERO)
	var hit_normal: Vector3 = hit.get("normal", Vector3.UP)
	var voxel_world_pos: Vector3 = hit_pos - hit_normal * 0.1

	# --- What material is this voxel? ---
	# For the slice, every voxel is "stone" — the test generator
	# writes a single voxel type uniformly. Real per-voxel material
	# tagging arrives with VoxelGeneratorGraph + a material library.
	var voxel_material: String = "stone"

	# Tool can only edit matching materials.
	if not voxel_material in target_materials:
		print("[EditToolHandler] Wrong tool for material '%s'." % voxel_material)
		_swing_cooldown_remaining = swing_cooldown_seconds
		return

	# --- Queue the edit ---
	if not get_node_or_null("/root/VoxelEditManager"):
		push_warning("[EditToolHandler] VoxelEditManager autoload not registered")
		return
	var accepted: bool = VoxelEditManager.queue_set_voxel(voxel_world_pos, AIR_VOXEL)
	_swing_cooldown_remaining = swing_cooldown_seconds

	if not accepted:
		# Rejected by NoEditZone. The bark system will eventually fire
		# Roland's "This place doesn't yield to me." line here.
		print("[EditToolHandler] This place doesn't yield to me.")
		return

	# --- Yield raw material into inventory ---
	var yield_item: String = VOXEL_MATERIAL_YIELDS.get(voxel_material, "")
	if yield_item != "":
		InventoryManager.add_item(yield_item, 1)

	# --- Award Crafting sub-skill XP ---
	# Each tool maps to its corresponding sub-skill (mining/felling/
	# excavation). XP rolls up to the Crafting domain tier.
	if get_node_or_null("/root/GameState"):
		var sub_skill: String = TOOL_SUB_SKILLS.get(equipped_id, "")
		var xp_amount: int = TOOL_XP_PER_EDIT.get(equipped_id, 0)
		if sub_skill != "" and xp_amount > 0:
			GameState.add_skill_xp(GameState.SkillDomain.CRAFTING, sub_skill, xp_amount)
