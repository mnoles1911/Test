extends Node3D
# ThrowableHandler — handles throwable item input (explosives, bombs,
# eventually traps and consumables).
#
# What this does in plain English:
#
# When the player presses the throw input (currently bound to
# `quick_slot_1` = key 1 — placeholder until the proper quick slot
# bar lands), this script:
#
#   1. Checks if Roland has the configured throwable in his inventory.
#   2. If yes, decrements the inventory and spawns one in front of
#      him with a forward velocity.
#   3. The thrown object handles its own arc, impact, and effects.
#
# This is debug-only wiring for the slice. Real quick-slot rotation
# (Q/E to cycle, F to use; per design/INPUT_AND_CONTROLS.md) needs
# a HUD UI that doesn't exist yet. When that lands, this script
# becomes the implementation behind quick_slot_use.
#
# Attached as a child of Player3D in scenes/Player3D.tscn.


# =============================================================
# CONFIGURATION
# =============================================================

@export var throw_input_action: String = "attack"
# LMB. ThrowableHandler only fires when the EQUIPPED weapon is a
# throwable (type == "throwable" in InventoryManager.ITEM_REGISTRY);
# EditToolHandler short-circuits in that case, so the same key
# does the right thing whether you have a tool or a bomb out.

# Mapping from item_id → scene file. Add new throwables here.
const THROWABLE_SCENES: Dictionary = {
	"powder_charge":  preload("res://scenes/throwables/powder_charge.tscn"),
	# "sappers_bundle": preload("res://scenes/throwables/sappers_bundle.tscn"),
	# Each new throwable item drops its scene here and the equip-driven
	# routing picks it up automatically — no per-item code paths.
}

@export var throw_speed_meters_per_second: float = 12.0
# How fast the charge leaves Roland's hand. Roughly grenade-toss
# velocity — fast enough to clear a body length but not so fast
# the player has trouble aiming.

@export var spawn_offset_forward_meters: float = 1.0
# How far in front of Roland the charge spawns, so it doesn't
# clip into his body or detonate on his own collision.

@export var spawn_offset_up_meters: float = 1.4
# Spawn height above Roland's pivot. Roughly chest height — the
# arm position from which a thrown object leaves a hand.

@export var infinite_inventory: bool = true
# DEBUG: when true, throws bypass the inventory check and decrement.
# Useful while tuning detonation behavior, voxel destruction radii,
# and physics arc — no need to grind for materials between tests.
# Flip to false (or remove this property entirely) when you want
# real economy gating again.


# =============================================================
# REFERENCES
# =============================================================

var _player: CharacterBody3D


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	if _player == null:
		push_error("[ThrowableHandler] Parent must be Player3D (CharacterBody3D)")


func _process(_delta: float) -> void:
	# Poll the action state instead of listening via _unhandled_input
	# — same rationale as EditToolHandler: UI Control nodes with
	# mouse_filter=STOP can eat the input event before it reaches
	# _unhandled_input, silently swallowing the throw.
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if not Input.is_action_just_pressed(throw_input_action):
		return
	# Only handle LMB when the equipped weapon is a throwable.
	# Otherwise EditToolHandler owns the LMB action (mine / fill /
	# place via bucket).
	if not get_node_or_null("/root/InventoryManager"):
		return
	var equipped_id: String = InventoryManager.get_equipped("weapon")
	if equipped_id == "":
		return
	if not InventoryManager.ITEM_REGISTRY.has(equipped_id):
		return
	if InventoryManager.ITEM_REGISTRY[equipped_id].get("type", "") != "throwable":
		return
	_try_throw(equipped_id)


func _try_throw(item_id: String) -> void:
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Throw triggered (%s)" % item_id)
	else:
		print("[ThrowableHandler] throw action triggered: %s" % item_id)
	if _player == null:
		return
	if not get_node_or_null("/root/InventoryManager"):
		return

	# --- Inventory check ---
	# Debug mode: skip the inventory gating entirely so testing
	# explosion behavior doesn't require farming materials.
	if not infinite_inventory:
		if not InventoryManager.has_item(item_id):
			print("[ThrowableHandler] No %s available." % item_id)
			return
		# Decrement first so a failed instance doesn't burn the item.
		InventoryManager.remove_item(item_id, 1)

	# --- Resolve the scene for this throwable ---
	if not THROWABLE_SCENES.has(item_id):
		push_error("[ThrowableHandler] No scene registered for throwable '%s'" % item_id)
		return
	var throwable_scene: PackedScene = THROWABLE_SCENES[item_id]
	if throwable_scene == null:
		push_error("[ThrowableHandler] THROWABLE_SCENES['%s'] is null" % item_id)
		return
	var charge: Node = throwable_scene.instantiate()
	if not charge is RigidBody3D:
		push_error("[ThrowableHandler] throwable_scene root must be RigidBody3D")
		charge.queue_free()
		return
	var rigid_body := charge as RigidBody3D

	# Spawn position: chest height, slightly in front of Roland's body.
	# We deliberately use the PLAYER BODY's forward (horizontal only)
	# for the spawn offset — NOT the camera's aim direction — so the
	# spawn point stays near Roland's chest regardless of camera pitch.
	# (Spawning along camera forward would put the charge near the
	# ground when looking down, which detonates immediately at his
	# feet.)
	var body_forward: Vector3 = -_player.transform.basis.z.normalized()
	var spawn_pos: Vector3 = _player.global_position + (body_forward * spawn_offset_forward_meters) + Vector3(0, spawn_offset_up_meters, 0)

	# Add to the world tree (the player's parent — the World3D root)
	# so the throwable's lifetime is tied to the world, not Roland.
	_player.get_parent().add_child(rigid_body)
	rigid_body.global_position = spawn_pos

	# Push inventory-driven sizing onto the spawned charge.
	# Without this the PowderCharge.aoe_radius_meters export keeps its
	# hardcoded default (2.0) and inventory-side tuning of
	# voxel_aoe_radius is silently ignored.
	if InventoryManager.ITEM_REGISTRY.has(item_id):
		var data: Dictionary = InventoryManager.ITEM_REGISTRY[item_id]
		if data.has("voxel_aoe_radius") and "aoe_radius_meters" in rigid_body:
			rigid_body.aoe_radius_meters = float(data["voxel_aoe_radius"])
		if data.has("combat_damage") and "combat_damage" in rigid_body:
			rigid_body.combat_damage = int(data["combat_damage"])

	# Throw direction: follow the camera's aim (includes pitch). The
	# camera lives a few nodes deep on Player3D — see Player3D.tscn.
	# Falls back to body_forward if the camera isn't where expected,
	# so a missing rig still throws something reasonable rather than
	# silently dropping at Roland's feet.
	#
	# No hardcoded upward bias here (the previous +UP*0.3 fought
	# aiming down). Gravity provides the natural arc; the player
	# compensates for distance by aiming a bit above the target,
	# the same way real-world grenade throws work.
	var aim_direction: Vector3 = body_forward
	var camera: Camera3D = _player.get_node_or_null("CameraTarget/SpringArm3D/Camera3D") as Camera3D
	if camera != null:
		aim_direction = -camera.global_transform.basis.z.normalized()

	rigid_body.linear_velocity = aim_direction * throw_speed_meters_per_second
