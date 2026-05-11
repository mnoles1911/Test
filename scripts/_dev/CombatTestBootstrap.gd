extends Node3D
# CombatTestBootstrap — wires up the v1 combat test arena.
#
# What this does in plain English:
#
#   The combat test scene is a flat dev arena where Roland and three
#   placeholder goblins stand in a clearing. This script handles the
#   one-time setup that happens when the scene loads:
#
#     1. Joins the "dev_scene" group so HUDOverlay, PauseMenu,
#        JournalUI, and SaveNotification all stay quiet (they check
#        GameState.is_dev_scene() and skip rendering for dev scenes).
#     2. Captures the mouse so the camera responds to look input.
#     3. Wires a debug F8 key to one-shot-kill the nearest goblin —
#        useful for testing death visuals before the spear is wired.
#     4. Wires a debug F9 key to wound the nearest goblin for 30 dmg —
#        useful for testing the wound + bleed Layer B blood once
#        Phase 4 lands.
#
# Phase 1 SCOPE:
#   Setup + debug damage keys only. No gameplay logic here — that's all
#   in Enemy3D / Goblin / Player3D. This script is the dev-arena harness.
#
# Attached to the root Node3D of scenes/_dev/CombatTest.tscn.


func _ready() -> void:
	# Mark this as a dev scene so the gameplay UI autoloads stay dormant.
	# Pattern matches scripts/_dev/WorldBakeController.gd and
	# CopperIslesTestBootstrap.gd — see CLAUDE.md "Dev-scene group convention".
	add_to_group("dev_scene")

	# Capture the mouse for camera control. Player3D / CameraRig require
	# MOUSE_MODE_CAPTURED to register look input.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Equip the spear so LMB throws it. The InventoryManager autoload
	# already added 5× spear to the debug starting inventory; we just
	# move it into the weapon slot so ThrowableHandler routes LMB to
	# the spear scene rather than to the equipped shovel.
	if get_node_or_null("/root/InventoryManager"):
		InventoryManager.equip("weapon", "spear")

	# Briefly log to confirm the arena loaded cleanly.
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("[CombatTest] Arena ready — F8 kill nearest, F9 wound nearest")
	else:
		print("[CombatTest] Arena ready — F8 kill nearest, F9 wound nearest")


func _unhandled_input(event: InputEvent) -> void:
	# Debug keys only — strip these or guard with OS.is_debug_build()
	# before shipping anything that's not the dev arena.
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return

	# F8 — one-shot kill nearest goblin (full charged-spear damage = 60).
	if key.keycode == KEY_F8:
		_apply_debug_damage(60)

	# F9 — wound nearest goblin for 30 dmg (matches a light spear hit).
	elif key.keycode == KEY_F9:
		_apply_debug_damage(30)


func _apply_debug_damage(amount: int) -> void:
	var enemy := _find_nearest_enemy()
	if enemy == null:
		print("[CombatTest] No enemies in scene")
		return
	var player := _find_player()
	# hit_dir points from the player toward the enemy — the same
	# direction the spear would have travelled if it caused this hit.
	var hit_dir: Vector3 = Vector3.FORWARD
	if player != null:
		var to_enemy: Vector3 = enemy.global_position - player.global_position
		to_enemy.y = 0.0
		if to_enemy.length() > 0.01:
			hit_dir = to_enemy.normalized()
	# hit_point at chest height for a plausible spear strike.
	var hit_point: Vector3 = enemy.global_position + Vector3(0, 1.2, 0)
	enemy.take_damage(amount, hit_dir, hit_point)


func _find_nearest_enemy() -> Node3D:
	var enemies := get_tree().get_nodes_in_group("enemy")
	var player := _find_player()
	if enemies.size() == 0:
		return null
	if player == null:
		# No player to measure from — return the first enemy.
		return enemies[0] as Node3D
	var nearest: Node3D = null
	var best_dist_sq: float = INF
	for n in enemies:
		var enemy := n as Node3D
		if enemy == null:
			continue
		var d_sq: float = enemy.global_position.distance_squared_to(player.global_position)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			nearest = enemy
	return nearest


func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() == 0:
		return null
	return players[0] as Node3D
