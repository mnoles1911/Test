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
	"spear":          preload("res://scenes/throwables/throwable_spear.tscn"),
	# "sappers_bundle": preload("res://scenes/throwables/sappers_bundle.tscn"),
	# Each new throwable item drops its scene here and the equip-driven
	# routing picks it up automatically — no per-item code paths.
}

@export var throw_speed_meters_per_second: float = 12.0
# How fast the charge leaves Roland's hand. Roughly grenade-toss
# velocity — fast enough to clear a body length but not so fast
# the player has trouble aiming. SPEAR ONLY: this is the LIGHT-throw
# speed; a fully-charged spear release lerps toward
# CHARGED_THROW_SPEED below.

# =============================================================
# CHARGE MECHANIC (Combat Phase 3, design/COMBAT_NEXT_PHASES.md)
# Spears support hold-to-charge. Hold LMB to ramp damage + velocity;
# release to throw. Holding pinches camera FOV via CameraRig.
# =============================================================

const CHARGE_MIN_HOLD_MS: int = 150
# Below this hold duration the throw is treated as a light tap — same
# damage + velocity as before charge existed. Stops "I just clicked and
# the spear came out underpowered" complaints.

const CHARGE_MAX_HOLD_MS: int = 700
# At or above this duration the throw is fully charged. The 150–700 ms
# window is the spec from design/COMBAT_NEXT_PHASES.md Phase 3.

const CHARGED_THROW_SPEED: float = 16.0
# Spear velocity at full charge. Lerps from throw_speed_meters_per_second
# (12.0) at CHARGE_MIN_HOLD_MS up to this at CHARGE_MAX_HOLD_MS.

const CHARGED_DAMAGE: int = 60
# Spear damage at full charge. Lerps from the item's base combat_damage
# (typically 30 for spear) up to this at CHARGE_MAX_HOLD_MS.

# Hold tracking state. _charge_start_msec == -1 means "no charge in
# progress." Set on press, cleared on release.
var _charge_start_msec: int = -1
var _charging_item_id: String = ""

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
		# Mouse uncaptured (pause menu, dialogue) — drop any in-flight
		# charge so the player doesn't release into a stale state when
		# the menu closes.
		_cancel_charge()
		return

	# Resolve the equipped throwable (if any) before deciding which
	# input path to run. Non-throwable weapons (tools, future swords)
	# are owned by other handlers.
	var equipped_id: String = ""
	if get_node_or_null("/root/InventoryManager"):
		equipped_id = InventoryManager.get_equipped("weapon")
	var is_throwable: bool = false
	if equipped_id != "" \
			and InventoryManager.ITEM_REGISTRY.has(equipped_id) \
			and InventoryManager.ITEM_REGISTRY[equipped_id].get("type", "") == "throwable":
		is_throwable = true

	# Charge mechanic ONLY applies to spears for now. Non-spear
	# throwables (powder_charge, future bombs) use the original instant-
	# fire flow because charge doesn't map to them sensibly.
	var supports_charge: bool = is_throwable and equipped_id == "spear"

	if supports_charge:
		_handle_charge_input(equipped_id)
		return

	if not is_throwable:
		_cancel_charge()
		return

	# Legacy instant-fire path for non-spear throwables.
	if Input.is_action_just_pressed(throw_input_action):
		_try_throw(equipped_id, 0)


# Hold-to-charge state machine. Press records the start time + pinches
# the camera FOV each frame while held; release computes hold_ms and
# throws with damage + velocity lerped across the 150–700 ms window.
func _handle_charge_input(item_id: String) -> void:
	if Input.is_action_just_pressed(throw_input_action):
		_charge_start_msec = Time.get_ticks_msec()
		_charging_item_id = item_id

	# Active-charge tick — push camera FOV pinch each frame while held
	# so the FOV responds smoothly.
	if _charge_start_msec >= 0 and Input.is_action_pressed(throw_input_action):
		var hold_ms: int = Time.get_ticks_msec() - _charge_start_msec
		var t: float = _charge_t_from_hold(hold_ms)
		_push_camera_pinch(t)

	if Input.is_action_just_released(throw_input_action):
		if _charge_start_msec < 0:
			# Released without a tracked press — happens if the press
			# fired in a frame when the equipped weapon wasn't a spear.
			# Restore camera FOV and bail.
			_push_camera_pinch(0.0)
			return
		var hold_ms: int = Time.get_ticks_msec() - _charge_start_msec
		_charge_start_msec = -1
		_push_camera_pinch(0.0)
		_try_throw(item_id, hold_ms)


func _charge_t_from_hold(hold_ms: int) -> float:
	# 0 at <= MIN_HOLD_MS, 1 at >= MAX_HOLD_MS, linear in between.
	if hold_ms <= CHARGE_MIN_HOLD_MS:
		return 0.0
	if hold_ms >= CHARGE_MAX_HOLD_MS:
		return 1.0
	return float(hold_ms - CHARGE_MIN_HOLD_MS) / float(CHARGE_MAX_HOLD_MS - CHARGE_MIN_HOLD_MS)


func _push_camera_pinch(t: float) -> void:
	var cam_rig: Node = get_tree().get_first_node_in_group("camera_rig")
	if cam_rig != null and cam_rig.has_method("set_charge_pinch"):
		cam_rig.call("set_charge_pinch", t)


func _cancel_charge() -> void:
	if _charge_start_msec < 0:
		return
	_charge_start_msec = -1
	_push_camera_pinch(0.0)


func _try_throw(item_id: String, hold_ms: int = 0) -> void:
	# hold_ms == 0 means "instant throw" (non-spear throwables, or a
	# spear release before CHARGE_MIN_HOLD_MS). Spears compute a charge
	# t from hold_ms and scale damage + velocity.
	var charge_t: float = _charge_t_from_hold(hold_ms) if item_id == "spear" else 0.0
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Throw triggered (%s, hold=%d ms, charge=%.2f)" % [item_id, hold_ms, charge_t])
	else:
		print("[ThrowableHandler] throw action triggered: %s (hold=%d ms, charge=%.2f)" % [item_id, hold_ms, charge_t])
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
			# Spear damage lerps from base (30) up to CHARGED_DAMAGE (60)
			# by charge_t. Non-spear throwables get their base damage.
			var base_dmg: int = int(data["combat_damage"])
			var final_dmg: int = base_dmg
			if item_id == "spear" and charge_t > 0.0:
				final_dmg = int(round(lerpf(float(base_dmg), float(CHARGED_DAMAGE), charge_t)))
			rigid_body.combat_damage = final_dmg

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

	# Spear velocity lerps from throw_speed_meters_per_second (light)
	# to CHARGED_THROW_SPEED at full charge. Other throwables get the
	# base speed.
	var final_speed: float = throw_speed_meters_per_second
	if item_id == "spear" and charge_t > 0.0:
		final_speed = lerpf(throw_speed_meters_per_second, CHARGED_THROW_SPEED, charge_t)
	rigid_body.linear_velocity = aim_direction * final_speed
