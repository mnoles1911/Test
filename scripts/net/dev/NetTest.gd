extends Node
# NetTest — MP-1 acceptance scene.
#
# WHAT THIS DOES (plain English):
#
#   Two-instance smoke test for the multiplayer connection layer
#   (NetTransport + MultiplayerManager). No gameplay, no replication —
#   just "do two Godot instances see each other as connected peers."
#
#   Buttons:
#     • HOST (ENet)         — start an ENet server on 127.0.0.1:7777.
#     • JOIN (ENet, 127.0.0.1) — connect to a local ENet host.
#     • HOST (Steam)        — start a friends-only Steam lobby. Greyed
#                             out unless the Steam plugin is installed.
#     • JOIN (Steam)        — paste a lobby ID, then join. Greyed out
#                             unless the plugin is installed.
#     • LEAVE               — tear down the active session.
#
#   The status panel shows:
#     - Active backend (ENet / Steam P2P)
#     - Mode (OFFLINE / HOST / CLIENT)
#     - Lifecycle (IDLE / LOBBY_READY / PLAYING / ...)
#     - Local peer ID
#     - Remote peers connected (with their display names)
#
#   Acceptance for MP-1 closes when:
#     1. ENet path: two Godot instances of this project on one machine
#        connect via 127.0.0.1 and each shows the other in their
#        peer list.
#     2. Steam path (after MP-0 is complete and GodotSteam is
#        installed): two friend Steam accounts can host + join via
#        lobby ID and end up in the same peer list.
#
# WHY MANUAL CLICK DISPATCH:
#   Per CLAUDE.md, Button.pressed never fires in this project
#   (Dialogic consumes mouse events globally). Every UI scene rolls
#   its own _input handler and routes clicks via rect-checks. We
#   follow that pattern from the first commit.
#
# Attached to the root Node of scenes/_dev/NetTest.tscn.


# =============================================================
# UI (built programmatically in _build_ui)
# =============================================================

var _ui_root: CanvasLayer
var _status_label: Label
var _output_label: Label
var _peer_list_label: Label
var _join_target_edit: LineEdit

var _host_enet_btn: Button
var _join_enet_btn: Button
var _host_steam_btn: Button
var _join_steam_btn: Button
var _leave_btn: Button
var _quit_btn: Button

# Cached at _ready to avoid allocating a SteamP2PBackend on every
# UI refresh. Plugin install state can't change mid-session anyway.
var _steam_available: bool = false


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# Dev scenes opt out of gameplay UI. See CLAUDE.md "Dev-scene
	# group convention".
	add_to_group("dev_scene")
	_steam_available = SteamP2PBackend.new().is_available()
	_build_ui()
	_wire_signals()
	_refresh_status()


func _input(event: InputEvent) -> void:
	# Manual click dispatch — Button.pressed doesn't fire in this
	# project. See CLAUDE.md "Critical GDScript patterns".
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_dispatch_click(mb.position)


func _wire_signals() -> void:
	# Watch MultiplayerManager state for UI refreshes.
	MultiplayerManager.session_started.connect(_on_session_started)
	MultiplayerManager.session_failed.connect(_on_session_failed)
	MultiplayerManager.session_ended.connect(_on_session_ended)
	MultiplayerManager.peer_joined.connect(_on_peer_joined)
	MultiplayerManager.peer_left.connect(_on_peer_left)
	MultiplayerManager.lifecycle_changed.connect(_on_lifecycle_changed)


# =============================================================
# UI BUILD
# =============================================================

func _build_ui() -> void:
	_ui_root = CanvasLayer.new()
	_ui_root.layer = 10
	add_child(_ui_root)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -300
	panel.offset_top = -260
	panel.offset_right = 300
	panel.offset_bottom = 260
	_ui_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# --- Header
	var title := Label.new()
	title.text = "MP-1  ·  Net Connection Test"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_status_label = Label.new()
	_status_label.text = "(status)"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)

	vbox.add_child(_make_separator())

	# --- ENet section
	var enet_label := Label.new()
	enet_label.text = "ENet (LAN, no plugin needed)"
	enet_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(enet_label)

	_host_enet_btn = _make_button("Host (ENet, port 7777)")
	vbox.add_child(_host_enet_btn)

	var enet_join_row := HBoxContainer.new()
	vbox.add_child(enet_join_row)
	_join_target_edit = LineEdit.new()
	_join_target_edit.text = "127.0.0.1"
	_join_target_edit.placeholder_text = "ip[:port]   or   <steam lobby id>"
	_join_target_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enet_join_row.add_child(_join_target_edit)
	_join_enet_btn = _make_button("Join (ENet)")
	enet_join_row.add_child(_join_enet_btn)

	vbox.add_child(_make_separator())

	# --- Steam section
	var steam_label := Label.new()
	steam_label.text = "Steam P2P (requires GodotSteam plugin)"
	steam_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(steam_label)

	_host_steam_btn = _make_button("Host (Steam, friends-only, 10 slots)")
	vbox.add_child(_host_steam_btn)
	_join_steam_btn = _make_button("Join (Steam, paste lobby id above)")
	vbox.add_child(_join_steam_btn)

	vbox.add_child(_make_separator())

	# --- Common controls
	_leave_btn = _make_button("Leave Session")
	vbox.add_child(_leave_btn)
	_quit_btn = _make_button("Quit")
	vbox.add_child(_quit_btn)

	# --- Peer list / log
	_peer_list_label = Label.new()
	_peer_list_label.text = "(no peers)"
	_peer_list_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_peer_list_label)

	_output_label = Label.new()
	_output_label.text = "(no events yet)"
	_output_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_output_label)


func _make_button(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(0, 32)
	return b


func _make_separator() -> HSeparator:
	return HSeparator.new()


# =============================================================
# CLICK DISPATCH
# =============================================================

func _dispatch_click(pos: Vector2) -> void:
	if _hits(_host_enet_btn, pos):
		_on_host_enet_pressed()
		return
	if _hits(_join_enet_btn, pos):
		_on_join_enet_pressed()
		return
	if _hits(_host_steam_btn, pos):
		_on_host_steam_pressed()
		return
	if _hits(_join_steam_btn, pos):
		_on_join_steam_pressed()
		return
	if _hits(_leave_btn, pos):
		_on_leave_pressed()
		return
	if _hits(_quit_btn, pos):
		get_tree().quit()
		return


func _hits(ctrl: Control, pos: Vector2) -> bool:
	if ctrl == null or not ctrl.visible:
		return false
	if ctrl is Button and (ctrl as Button).disabled:
		return false
	return ctrl.get_global_rect().has_point(pos)


# =============================================================
# BUTTON HANDLERS
# =============================================================

func _on_host_enet_pressed() -> void:
	NetTransport.select_backend(NetTransport.BACKEND_ENET)
	_log("Hosting via ENet on port 7777...")
	var err: Error = MultiplayerManager.host_session(MultiplayerManager.DEFAULT_MAX_PEERS)
	if err != OK:
		_log("host_session returned error: %s" % error_string(err))


func _on_join_enet_pressed() -> void:
	NetTransport.select_backend(NetTransport.BACKEND_ENET)
	var target: String = _join_target_edit.text.strip_edges()
	if target.is_empty():
		_log("Enter an IP (e.g. 127.0.0.1) in the target box first.")
		return
	_log("Joining ENet host: %s" % target)
	var err: Error = MultiplayerManager.join_session(target)
	if err != OK:
		_log("join_session returned error: %s" % error_string(err))


func _on_host_steam_pressed() -> void:
	NetTransport.select_backend(NetTransport.BACKEND_STEAM)
	if not NetTransport.is_backend_available():
		_log("Steam backend not available. Install GodotSteam (see addons/godotsteam/INSTALL.md) and ensure the Steam client is running.")
		_refresh_status()
		return
	_log("Creating Steam friends-only lobby (10 slots)...")
	var err: Error = MultiplayerManager.host_session(MultiplayerManager.DEFAULT_MAX_PEERS)
	if err != OK:
		_log("host_session returned error: %s" % error_string(err))


func _on_join_steam_pressed() -> void:
	NetTransport.select_backend(NetTransport.BACKEND_STEAM)
	if not NetTransport.is_backend_available():
		_log("Steam backend not available. Install GodotSteam (see addons/godotsteam/INSTALL.md) and ensure the Steam client is running.")
		_refresh_status()
		return
	var lobby_id_raw: String = _join_target_edit.text.strip_edges()
	if lobby_id_raw.is_empty() or int(lobby_id_raw) == 0:
		_log("Paste a Steam lobby id (the long uint64 number) into the target box first.")
		return
	_log("Joining Steam lobby: %s" % lobby_id_raw)
	var err: Error = MultiplayerManager.join_session(lobby_id_raw)
	if err != OK:
		_log("join_session returned error: %s" % error_string(err))


func _on_leave_pressed() -> void:
	if MultiplayerManager.is_offline():
		_log("Already offline — nothing to leave.")
		return
	_log("Leaving session.")
	MultiplayerManager.leave_session("user clicked Leave")


# =============================================================
# MultiplayerManager SIGNAL HANDLERS
# =============================================================

func _on_session_started(mode: int) -> void:
	_log("session_started: mode=%s  backend=%s" % [
		MultiplayerManager.MP_MODE.keys()[mode],
		NetTransport.backend_name(),
	])
	_refresh_status()


func _on_session_failed(reason: String) -> void:
	_log("session_failed: %s" % reason)
	_refresh_status()


func _on_session_ended(reason: String) -> void:
	_log("session_ended: %s" % reason)
	_refresh_status()


func _on_peer_joined(peer_id: int) -> void:
	_log("peer_joined: %d" % peer_id)
	_refresh_status()


func _on_peer_left(peer_id: int) -> void:
	_log("peer_left: %d" % peer_id)
	_refresh_status()


func _on_lifecycle_changed(state: int) -> void:
	_log("lifecycle: %s" % MultiplayerManager.LIFECYCLE.keys()[state])
	_refresh_status()


# =============================================================
# STATUS RENDERING
# =============================================================

func _refresh_status() -> void:
	var lines: Array[String] = []
	lines.append("Backend: %s   Available: %s" % [
		NetTransport.backend_name(),
		NetTransport.is_backend_available(),
	])
	lines.append("Mode: %s   Lifecycle: %s" % [
		MultiplayerManager.MP_MODE.keys()[MultiplayerManager.mode()],
		MultiplayerManager.LIFECYCLE.keys()[MultiplayerManager.lifecycle()],
	])
	lines.append("Local peer id: %d" % MultiplayerManager.local_peer_id())
	_status_label.text = "\n".join(lines)

	# Steam buttons greyed out if Steam backend isn't available.
	_host_steam_btn.disabled = not _steam_available
	_join_steam_btn.disabled = not _steam_available
	if not _steam_available:
		_host_steam_btn.text = "Host (Steam, plugin not installed)"
		_join_steam_btn.text = "Join (Steam, plugin not installed)"

	# Peer list.
	if MultiplayerManager.peers.is_empty():
		_peer_list_label.text = "(no peers)"
	else:
		var peer_lines: Array[String] = ["Peers:"]
		for pid in MultiplayerManager.peers.keys():
			var rec: Dictionary = MultiplayerManager.peers[pid]
			var marker: String = "  (you)" if pid == MultiplayerManager.local_peer_id() else ""
			peer_lines.append("  • %d  %s%s" % [pid, rec.get("display_name", "?"), marker])
		_peer_list_label.text = "\n".join(peer_lines)


func _log(msg: String) -> void:
	print("[NetTest] " + msg)
	if _output_label != null:
		_output_label.text = msg
