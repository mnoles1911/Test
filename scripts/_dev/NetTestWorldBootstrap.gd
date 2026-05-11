extends Node3D
# NetTestWorldBootstrap — runs the MP-2 acceptance world.
#
# WHAT THIS IS (plain English):
#
#   Attached to the root of scenes/_dev/NetTestWorld.tscn. A minimal
#   flat dev arena with one job: prove that two Godot instances can
#   spawn into the same scene, walk around, and see each other.
#
#   Responsibilities:
#     1. Join the "dev_scene" group so HUDOverlay / PauseMenu /
#        JournalUI / SaveNotification stay dormant.
#     2. Capture the mouse so CameraRig responds to look input
#        (locked-mouse mode; ESC releases it).
#     3. Build a tiny on-screen status panel (top-right) showing peers
#        connected + a "Leave Session" button.
#     4. If session ends (host quits, guest disconnects, etc.),
#        transition back to NetTest.tscn so the tester isn't stranded
#        in an empty world.
#
# NO GAMEPLAY:
#   No goblins, no edits, no NPCs. This scene is the simplest possible
#   stage on which two characters can stand. MP-3 and onward will add
#   layers (voxel terrain, combat, etc.) on top of the same connection
#   layer this proves out.
#
# WHY MANUAL CLICK DISPATCH:
#   Per CLAUDE.md, Button.pressed never fires in this project. Every
#   UI scene rolls its own _input handler.


# =============================================================
# UI (built programmatically)
# =============================================================

var _ui_root: CanvasLayer
var _status_label: Label
var _leave_btn: Button


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	add_to_group("dev_scene")
	# Lock the mouse for camera control. CameraRig + Player3D's
	# _unhandled_input rely on captured mode for mouse-look.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_build_ui()
	_wire_signals()
	_refresh_status()


func _input(event: InputEvent) -> void:
	# Manual click dispatch + ESC to release mouse / return to menu.
	if event is InputEventKey:
		var k: InputEventKey = event as InputEventKey
		if k.pressed and k.keycode == KEY_ESCAPE:
			# Toggle mouse capture. If already free, treat as "leave".
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				_on_leave_pressed()
			get_viewport().set_input_as_handled()
		return

	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		# Re-capture on click if the mouse was released for UI.
		if not _hits(_leave_btn, mb.position):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	_dispatch_click(mb.position)


func _wire_signals() -> void:
	# Watch session state so we can return to NetTest.tscn cleanly if
	# the host quits or the connection drops mid-test.
	if get_node_or_null("/root/MultiplayerManager") == null:
		return
	MultiplayerManager.session_ended.connect(_on_session_ended)
	MultiplayerManager.peer_joined.connect(func(_id): _refresh_status())
	MultiplayerManager.peer_left.connect(func(_id): _refresh_status())


# =============================================================
# UI
# =============================================================

func _build_ui() -> void:
	_ui_root = CanvasLayer.new()
	_ui_root.layer = 10
	add_child(_ui_root)

	var panel := PanelContainer.new()
	# Top-right anchor.
	panel.anchor_left = 1.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -340
	panel.offset_top = 16
	panel.offset_right = -16
	panel.offset_bottom = 160
	_ui_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "MP-2 · Net Test World"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	_status_label = Label.new()
	_status_label.text = "(status)"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)

	_leave_btn = Button.new()
	_leave_btn.text = "Leave Session (ESC×2)"
	_leave_btn.custom_minimum_size = Vector2(0, 28)
	vbox.add_child(_leave_btn)


func _dispatch_click(pos: Vector2) -> void:
	if _hits(_leave_btn, pos):
		_on_leave_pressed()


func _hits(ctrl: Control, pos: Vector2) -> bool:
	if ctrl == null or not ctrl.visible:
		return false
	if ctrl is Button and (ctrl as Button).disabled:
		return false
	return ctrl.get_global_rect().has_point(pos)


func _refresh_status() -> void:
	if get_node_or_null("/root/MultiplayerManager") == null:
		_status_label.text = "MultiplayerManager not loaded."
		return
	var lines: Array[String] = []
	lines.append("Mode: %s" % MultiplayerManager.MP_MODE.keys()[MultiplayerManager.mode()])
	lines.append("Peers: %d" % MultiplayerManager.peers.size())
	for pid in MultiplayerManager.peers.keys():
		var rec: Dictionary = MultiplayerManager.peers[pid]
		var marker: String = " (you)" if pid == MultiplayerManager.local_peer_id() else ""
		lines.append("  • %d  %s%s" % [pid, rec.get("display_name", "?"), marker])
	_status_label.text = "\n".join(lines)


# =============================================================
# BUTTON HANDLERS
# =============================================================

func _on_leave_pressed() -> void:
	if get_node_or_null("/root/MultiplayerManager") != null and not MultiplayerManager.is_offline():
		MultiplayerManager.leave_session("user requested via NetTestWorld leave button")
	# Whether we were connected or not, return to the connection-test menu.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/_dev/NetTest.tscn")


func _on_session_ended(_reason: String) -> void:
	# Host quit or connection dropped — bounce back to NetTest.tscn so
	# the tester can re-host / re-join without restarting the editor.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/_dev/NetTest.tscn")
