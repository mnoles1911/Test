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

func _on_damaged(amount: int, hit_dir: Vector3, hit_point: Vector3) -> void:
	# Phase 4 will wire BloodVFX.spawn_burst(hit_point, hit_dir, intensity)
	# and BloodVFX.spawn_bleed(_chest_socket) here. v1 placeholder: log.
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Goblin %s wounded (%d) → HP %d" % [name, amount, health])


func _on_died(damage_at_kill: int, hit_dir: Vector3, hit_point: Vector3) -> void:
	# Phase 5 will branch on damage_at_kill (topple vs. explosion),
	# spawn FallingVoxelCluster, hide the visual, and spawn the pool.
	# v1 placeholder: hide the mesh and log.
	if _visual != null:
		_visual.visible = false
	if _eye_glow != null:
		_eye_glow.visible = false
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Goblin %s killed (%d dmg)" % [name, damage_at_kill])
