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

@export var throwable_item_id: String = "powder_charge"
# Inventory item the throw input consumes. Currently hardcoded;
# real quick-slot UI will let the player rotate between throwables.

@export var throwable_scene: PackedScene = preload("res://scenes/throwables/powder_charge.tscn")
# Scene to instance on throw. One throwable per scene file; map
# from item_id → scene at the call site, or as a const dict here
# once we have more than one type.

@export var throw_input_action: String = "quick_slot_1"
# Input action that triggers a throw. Bound to "1" by default in
# project.godot (per design/INPUT_AND_CONTROLS.md → Quick Slots).

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
	_try_throw()


func _try_throw() -> void:
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Throw triggered (%s)" % throwable_item_id)
	else:
		print("[ThrowableHandler] throw action triggered")
	if _player == null:
		return
	if not get_node_or_null("/root/InventoryManager"):
		return

	# --- Inventory check ---
	# Debug mode: skip the inventory gating entirely so testing
	# explosion behavior doesn't require farming materials.
	if not infinite_inventory:
		if not InventoryManager.has_item(throwable_item_id):
			print("[ThrowableHandler] No %s available." % throwable_item_id)
			return
		# Decrement first so a failed instance doesn't burn the item.
		InventoryManager.remove_item(throwable_item_id, 1)

	# --- Spawn the throwable ---
	if throwable_scene == null:
		push_error("[ThrowableHandler] No throwable_scene set")
		return
	var charge: Node = throwable_scene.instantiate()
	if not charge is RigidBody3D:
		push_error("[ThrowableHandler] throwable_scene root must be RigidBody3D")
		charge.queue_free()
		return
	var rigid_body := charge as RigidBody3D

	# Compute spawn position: in front of Roland at chest height.
	# transform.basis.z is the player body's BACK direction (Godot
	# convention), so -basis.z points forward.
	var forward: Vector3 = -_player.transform.basis.z.normalized()
	var spawn_pos: Vector3 = _player.global_position + (forward * spawn_offset_forward_meters) + Vector3(0, spawn_offset_up_meters, 0)

	# Add to the world tree (the player's parent — the World3D root)
	# so the throwable's lifetime is tied to the world, not Roland.
	_player.get_parent().add_child(rigid_body)
	rigid_body.global_position = spawn_pos

	# Forward + slight upward arc — like an underhand toss.
	var throw_velocity: Vector3 = (forward + Vector3.UP * 0.3).normalized() * throw_speed_meters_per_second
	rigid_body.linear_velocity = throw_velocity
