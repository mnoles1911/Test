# Goblin.gd — the v1 enemy. Lanky, green, glowing eyes, gibs spectacularly.
#
# What this does in plain English:
#
#   Extends Enemy3D to give a goblin its specific behaviors:
#     - When IDLE, stand still
#     - When ALERT (player spotted), eyes go from off to dim
#     - When COMBAT (player close enough to engage), eyes blaze full
#       green and the goblin walks toward the player
#     - When damaged, flinch + fire blood VFX (wired in Phase 4)
#     - When killed, hide the body and spawn a falling-voxel cluster
#       (wired in Phase 5) — topple for normal kills, explosion for
#       overkill (≥80 damage)
#
# v1 SCOPE:
#   No swing animation, no attack token system, no group alerting, no
#   fleeing. Goblin walks at the player and deals contact damage on
#   touch. The full attack-pool / token / swarm rules from
#   design/ENEMY_AI.md land in a later combat pass.
#
# SCENE STRUCTURE expected (Goblin.tscn):
#   Goblin (CharacterBody3D + this script)
#   ├── Visual (MeshInstance3D — green box placeholder until .glb lands)
#   ├── CollisionShape3D (capsule, 0.4 m radius, 1.8 m tall)
#   ├── ChestSocket (Node3D, Y=+1.2 — spear embed point)
#   └── EyeGlow (MeshInstance3D — small green box at head height with
#         an emissive StandardMaterial3D the script tweaks per state)

class_name Goblin
extends Enemy3D


# =============================================================
# MOVEMENT
# =============================================================

@export var walk_speed_meters_per_second: float = 2.8
## Slower than Roland (~4.5 m/s walk) so the player can outpace a
## goblin to set up a charged spear throw. Tweak after combat
## playtests — too slow feels like training dummies; too fast feels
## like the player can never breathe.


# =============================================================
# EYE GLOW STATE TABLE
# =============================================================
# Three intensities driven by Enemy3D.current_state. The values are
# emission_energy_multiplier passed to a StandardMaterial3D.
# 0.0 = invisible, 6.0 = strongly self-lit (overpowers ambient).

const _EYE_GLOW_BY_STATE: Dictionary = {
	State.IDLE:   0.0,
	State.ALERT:  2.0,
	State.COMBAT: 6.0,
}


# =============================================================
# NODE REFERENCES
# =============================================================

@onready var _visual: MeshInstance3D = $Visual
@onready var _eye_glow: MeshInstance3D = get_node_or_null("EyeGlow")
@onready var _chest_socket: Node3D = get_node_or_null("ChestSocket")
## Cached reference to the eye mesh's material. We read this once and
## then poke its emission_energy_multiplier directly each state change
## — cheaper than re-fetching every frame.
var _eye_material: StandardMaterial3D


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	super._ready()
	# Configure the eye material if the EyeGlow node was authored.
	# (We tolerate the EyeGlow being missing so the placeholder Goblin
	# scene can ship without it — the goblin still walks and dies.)
	if _eye_glow != null:
		var mat := _eye_glow.get_active_material(0)
		if mat is StandardMaterial3D:
			_eye_material = mat
		else:
			# Build one inline so the placeholder works even if the
			# .tscn forgot to set up an emissive material.
			_eye_material = StandardMaterial3D.new()
			_eye_material.albedo_color = Color(0.0, 1.0, 0.25, 1.0)
			_eye_material.emission_enabled = true
			_eye_material.emission = Color(0.0, 1.0, 0.25, 1.0)
			_eye_material.emission_energy_multiplier = 0.0
			_eye_glow.material_override = _eye_material
	_apply_eye_glow_for_state()


# =============================================================
# MOVEMENT (override of Enemy3D._enemy_physics_step)
# =============================================================

func _enemy_physics_step(_delta: float) -> void:
	# Only move during COMBAT. IDLE / ALERT goblins stand still.
	if current_state != State.COMBAT:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	if _player == null:
		return
	# Walk toward the player on the XZ plane only; Y is gravity.
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	var distance: float = to_player.length()
	if distance < 0.8:
		# Close enough — stop walking, contact damage will fire.
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var dir: Vector3 = to_player / distance
	velocity.x = dir.x * walk_speed_meters_per_second
	velocity.z = dir.z * walk_speed_meters_per_second
	# Face the player so the body and eyes track. Use look_at on the
	# horizontal plane only to avoid tipping the goblin forward.
	var look_target: Vector3 = global_position + Vector3(dir.x, 0.0, dir.z)
	look_at(look_target, Vector3.UP)


# =============================================================
# STATE → VISUALS
# =============================================================

func _on_state_changed(_old: State, new_state: State) -> void:
	_apply_eye_glow_for_state()
	# Brief log for v1 debugging; remove once combat AI lands.
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Goblin %s → %s" % [name, State.keys()[new_state]])


func _apply_eye_glow_for_state() -> void:
	if _eye_material == null:
		return
	var energy: float = float(_EYE_GLOW_BY_STATE.get(current_state, 0.0))
	_eye_material.emission_energy_multiplier = energy


# =============================================================
# DAMAGE + DEATH (Phase 4 + Phase 5 wire blood + cluster here)
# =============================================================

func _on_damaged(amount: int, _hit_dir: Vector3, _hit_point: Vector3) -> void:
	# ThrowableSpear already fires the Layer A burst at the hit point
	# (it has the precise impact location + direction; we'd be guessing
	# from over here). Goblin is responsible for the Layer B wound
	# drip — start it on the first non-lethal hit. start_drip is a
	# no-op if a drip is already attached, so it's safe to call on
	# every wound event.
	if get_node_or_null("/root/BloodVFX"):
		BloodVFX.start_drip(self, "ChestSocket")
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Goblin %s wounded (%d) → HP %d" % [name, amount, health])


func _on_died(damage_at_kill: int, hit_dir: Vector3, hit_point: Vector3) -> void:
	# Phase 5 (Combat) — branch on damage_at_kill:
	#   damage >= OVERKILL_DAMAGE_THRESHOLD (80):  GIB EXPLOSION
	#     - Hide the visual + eye glow
	#     - Spawn GIB_CHUNK_COUNT chunks with radial outward impulse
	#     - Reparent any embedded spears to a random gib chunk so they
	#       visibly travel with the explosion rather than floating where
	#       the (now hidden) corpse was
	#     - Enemy3D.die() already fired the time-slow + camera kick
	#       before calling us (lines up the explosion with the punch)
	#   damage <  OVERKILL_DAMAGE_THRESHOLD: topple (v1 behaviour)
	#     - Lay the visual flat, rotate chest socket so embedded spears
	#       pivot with the body, darken to corpse-grey
	# In both cases: kill the eye glow, stop the wound drip, drop a
	# Layer C blood pool.
	# Enemy3D.die() handles the eventual queue_free via
	# corpse_lifetime_seconds and spawns the corpse-interaction Area3D
	# for E-press loot (gibs are still part of the corpse — looting
	# returns embedded spears from whatever chunk they ride).

	var overkill: bool = damage_at_kill >= OVERKILL_DAMAGE_THRESHOLD

	if overkill:
		# Hide the visual + eye glow. Body chunks ARE the corpse now.
		if _visual != null:
			_visual.visible = false
		if _eye_glow != null:
			_eye_glow.visible = false
		# Spawn the chunks via the Enemy3D base helper. Skin = goblin
		# green, core = darker red (interior body voxels).
		var skin := Color(0.20, 0.55, 0.18, 1.0)
		var core := Color(0.55, 0.10, 0.10, 1.0)
		var chunks: Array = _spawn_gib_explosion(global_position, hit_point, hit_dir, skin, core)
		# Reparent any embedded spears in the ChestSocket onto random
		# gib chunks so the spear visibly tumbles with the explosion.
		# Children are freed-by-reparent so we iterate over a copy.
		if _chest_socket != null and not chunks.is_empty():
			var embedded := _chest_socket.get_children()
			for child in embedded:
				if child is ThrowableSpear:
					var target_chunk: RigidBody3D = chunks[randi() % chunks.size()]
					var spear: Node3D = child as Node3D
					var world_xform: Transform3D = spear.global_transform
					spear.get_parent().remove_child(spear)
					target_chunk.add_child(spear)
					spear.global_transform = world_xform
	else:
		# Non-overkill topple — original v1 behaviour preserved.
		if _visual != null:
			# Rotate -90° on X (faceplant forward), then sink so the
			# now-horizontal box rests on the ground rather than floating
			# at original chest height. Box was 0.5×1.8×0.4 with origin
			# at Y=0.9; after the X-rotation its vertical extent becomes
			# 0.4, half-height 0.2, so origin Y=0.2 puts the bottom on
			# the ground.
			_visual.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
			_visual.position = Vector3(0.0, 0.2, 0.0)
			var corpse_mat: StandardMaterial3D = StandardMaterial3D.new()
			corpse_mat.albedo_color = Color(0.18, 0.22, 0.14, 1.0)
			_visual.material_override = corpse_mat
		if _chest_socket != null:
			# Rotate the chest socket the same -90° X so any spears
			# parented inside it pivot with the body. The spear's local
			# transform (relative to ChestSocket) doesn't change — only
			# its global transform follows the rotation.
			_chest_socket.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
			_chest_socket.position = Vector3(0.0, 0.5, 0.0)
		if _eye_glow != null:
			_eye_glow.visible = false

	if get_node_or_null("/root/BloodVFX"):
		BloodVFX.stop_drip(self)
		# Pool grows larger and faster on overkill — a charged-spear
		# kill leaves more visible mess than a finishing tap.
		var size: float = 4.5 if damage_at_kill >= 50 else 3.0
		var grow: float = 1.5 if damage_at_kill >= 50 else 2.5
		BloodVFX.spawn_pool(global_position, size, grow)
	if get_node_or_null("/root/DebugOverlay"):
		var verdict: String = "OVERKILL" if overkill else "kill"
		DebugOverlay.log_action("Goblin %s %s (%d dmg)" % [name, verdict, damage_at_kill])


## Override of Enemy3D._loot_corpse. Walks the chest socket's child
## list, returns any embedded ThrowableSpear instances to the
## player's inventory, and frees them. Future: also deposit any
## non-spear items the goblin was carrying (none in v1).
##
## Called by Enemy3D._physics_process when the player is in the
## corpse interaction area and presses the "interact" action (E).
## The base class guards against double-loot via _corpse_looted.
func _loot_corpse() -> void:
	if _chest_socket == null:
		return
	var spears_recovered: int = 0
	# Iterate over a copy because we're going to free children
	# during the loop.
	var children := _chest_socket.get_children()
	for child in children:
		if child is ThrowableSpear:
			child.queue_free()
			spears_recovered += 1
	if spears_recovered > 0 and get_node_or_null("/root/InventoryManager"):
		InventoryManager.add_item("spear", spears_recovered)
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Looted goblin %s — %d spear(s) recovered" % [name, spears_recovered])
