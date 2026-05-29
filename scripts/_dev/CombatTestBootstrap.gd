extends Node3D
# CombatTestBootstrap — wires up the v1 combat test arena.
#
# What this does in plain English:
#
#   The combat test scene is a flat dev arena where Roland and three
#   placeholder goblins stand in a clearing. This script handles the
#   one-time setup that happens when the scene loads, plus the
#   developer-facing debug menu and key bindings used during iteration.
#
#   ON LOAD:
#     1. Joins the "dev_scene" group so HUDOverlay, PauseMenu,
#        JournalUI, and SaveNotification all stay quiet (they check
#        GameState.is_dev_scene() and skip rendering for dev scenes).
#     2. Captures the mouse so the camera responds to look input.
#     3. Equips the spear into Roland's weapon slot.
#     4. Records the original goblin positions so Reset can respawn
#        them in the same triangle.
#     5. Builds a small on-screen debug menu (top-right) listing the
#        keybinds.
#
#   DEBUG KEY BINDINGS:
#     F1 — Toggle debug menu visibility (the on-screen overlay).
#          Matches the project-wide convention used by DebugOverlay
#          and LockpickTestBootstrap. The keybinds keep working when
#          the menu is hidden.
#     F8 — kill nearest goblin (charged-spear-equivalent damage = 60)
#     F9 — wound nearest goblin (light-spear-equivalent damage = 30)
#     R  — Reset enemies: free all current goblins (alive or corpses)
#          and respawn three fresh ones at the original triangle
#          positions. Restores the arena to first-frame state without
#          reloading the scene.
#     Q  — Quit: closes the running game window. Equivalent to
#          pressing the X on the window or hitting F8 in the editor.
#          Does NOT save anything (this is a dev arena).
#
# Phase 1 SCOPE:
#   Setup + debug damage keys + debug menu. No gameplay logic here —
#   that's all in Enemy3D / Goblin / Player3D. This script is the
#   dev-arena harness.
#
# Attached to the root Node3D of scenes/_dev/CombatTest.tscn.


# =============================================================
# CONSTANTS
# =============================================================

const _GOBLIN_SCENE: PackedScene = preload("res://scenes/enemies/Goblin.tscn")

## Triangle formation matching the original placement in
## CombatTest.tscn. Reset Enemies respawns goblins at these exact
## positions so the encounter is reproducible across resets.
const _GOBLIN_SPAWN_POSITIONS: Array[Vector3] = [
	Vector3(-3.0, 0.0, -2.0),
	Vector3(3.0, 0.0, -2.0),
	Vector3(0.0, 0.0, -6.0),
]


# =============================================================
# STATE
# =============================================================

## Reference to the on-screen debug menu (CanvasLayer + Label). We
## hold a reference so M can toggle visibility without searching the
## tree each press.
var _debug_menu: CanvasLayer


# =============================================================
# LIFECYCLE
# =============================================================

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

	# Spawn an EntityStreamer so the F1 "SPAWN TEST GOBLIN" debug command
	# works in this dev scene. World3D.tscn ships one as a scene child;
	# CombatTest.tscn does not, so the streamer is added programmatically
	# here. Joins the "entity_streamer" group on _ready so
	# DebugOverlay._spawn_test_goblin resolves it via
	# get_first_node_in_group without a hardcoded node path.
	var streamer_script: Script = load("res://scripts/EntityStreamer.gd")
	if streamer_script != null:
		var streamer: Node3D = streamer_script.new()
		streamer.name = "EntityStreamer"
		add_child(streamer)

	# Build the on-screen debug menu.
	_build_debug_menu()

	# Briefly log to confirm the arena loaded cleanly.
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("[CombatTest] Arena ready — see top-right debug menu")
	else:
		print("[CombatTest] Arena ready — F8/F9 damage, R reset, Q quit, M toggle menu")


func _unhandled_input(event: InputEvent) -> void:
	# Debug keys only — strip these or guard with OS.is_debug_build()
	# before shipping anything that's not the dev arena.
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return

	match key.keycode:
		KEY_F1:
			# Toggle the debug menu's on-screen visibility. Project-
			# standard convention (matches DebugOverlay and
			# LockpickTestBootstrap). Keybinds remain active when the
			# menu is hidden.
			_toggle_debug_menu()
		KEY_F8:
			# One-shot kill nearest goblin (full charged-spear damage).
			_apply_debug_damage(60)
		KEY_F9:
			# Wound nearest goblin (light-spear damage).
			_apply_debug_damage(30)
		KEY_R:
			# Reset Enemies: clear current goblins (alive + corpses)
			# and respawn three fresh ones at the original positions.
			_reset_enemies()
		KEY_Q:
			# Quit the game window. Dev arena only — no save.
			_quit_game()


# =============================================================
# DEBUG MENU
# =============================================================

func _build_debug_menu() -> void:
	# CanvasLayer with a single Label in the top-right corner.
	# Layer index 100 puts it above almost everything else (HUDOverlay
	# uses 5; the journal uses 10; the pause menu uses 50). Dev tooling
	# can sit higher because its purpose is "always visible during
	# active iteration."
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-260.0, 12.0)
	panel.custom_minimum_size = Vector2(248.0, 0.0)
	# Translucent dark panel so the text reads against any background
	# in the dev arena.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 0.78)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)

	var label := Label.new()
	label.text = "[ COMBAT TEST DEBUG — F1 ]\n"
	label.text += "  F8 — Kill nearest\n"
	label.text += "  F9 — Wound nearest\n"
	label.text += "  R  — Reset enemies\n"
	label.text += "  Q  — Quit"
	label.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78, 1.0))
	panel.add_child(label)

	_debug_menu = layer


func _toggle_debug_menu() -> void:
	if _debug_menu == null:
		return
	_debug_menu.visible = not _debug_menu.visible


# =============================================================
# RESET / QUIT
# =============================================================

func _reset_enemies() -> void:
	# Free every existing enemy (alive or corpse) and respawn fresh
	# ones at the original triangle positions. Bypasses the
	# corpse_lifetime_seconds timer in Enemy3D.die().
	#
	# Uses queue_free so the freeing happens at end-of-frame; the
	# spawning happens in the same call so the next frame the player
	# sees three goblins regardless of what was on screen before.
	#
	# Also clears EntityRegistry of any test goblins spawned via the
	# F1 "SPAWN TEST GOBLIN" debug command — otherwise the streamer
	# would re-spawn them on the next reconcile, defeating the reset.
	# A dev-arena clear is safe; production save/load uses its own path.
	if get_node_or_null("/root/EntityRegistry") != null \
			and EntityRegistry.has_method("clear"):
		EntityRegistry.clear()

	var existing := get_tree().get_nodes_in_group("enemy")
	for n in existing:
		if is_instance_valid(n):
			n.queue_free()

	for spawn_pos in _GOBLIN_SPAWN_POSITIONS:
		var goblin := _GOBLIN_SCENE.instantiate() as Node3D
		add_child(goblin)
		goblin.global_position = spawn_pos

	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("[CombatTest] Reset — %d goblins respawned" % _GOBLIN_SPAWN_POSITIONS.size())
	else:
		print("[CombatTest] Reset — %d goblins respawned" % _GOBLIN_SPAWN_POSITIONS.size())


func _quit_game() -> void:
	# get_tree().quit() closes the application cleanly. From the editor
	# this also stops the playtest. No save — this is a dev arena.
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("[CombatTest] Quit requested via Q key")
	get_tree().quit()


# =============================================================
# DEBUG DAMAGE (F8 / F9)
# =============================================================

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
