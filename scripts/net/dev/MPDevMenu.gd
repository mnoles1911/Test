extends Node
# MPDevMenu — operator overlay for live multiplayer sessions.
#
# WHAT THIS IS (plain English):
#
#   A small always-on overlay (top-right by default; togglable with
#   F10) that shows the operator the live state of their MP session
#   and lets them act on it:
#
#     • Live peer list with per-peer ping (when transport supports it)
#     • Kick button per remote peer (host-only)
#     • Session lifecycle indicator (mode, lobby visibility)
#     • Quick "Leave Session" button
#     • Backend name + active multiplayer/backend setting
#     • In-game session log of recent events (joins, leaves, errors)
#
#   This is the dev / operator tool — NOT a player-facing UI. It
#   joins the "dev_scene" group equivalent style so it stays out of
#   the way of regular gameplay HUD, but it's available in every
#   scene that loads MultiplayerManager (i.e. always).
#
# AUTOLOAD:
#   Registered in project.godot. Stays invisible until F10. Cost when
#   hidden: zero (no UI updates, no _process work).
#
# WHY MANUAL CLICK DISPATCH:
#   Per CLAUDE.md, Button.pressed signals don't fire — Dialogic
#   consumes mouse events globally. Every UI in the project rolls
#   its own _input dispatch.
#
# WHAT'S DELIBERATELY DEFERRED FROM MP-8 v1:
#
#   - Bandwidth stats per-peer. Godot doesn't surface per-peer
#     send/recv byte counters as a public API; we'd need to wrap
#     the MultiplayerAPI's packet handlers and tally manually.
#     Defer to a future profiling pass.
#
#   - Lobby visibility toggle (public / friends-only / invite-only).
#     Requires Steam-specific calls; not wired in NetTransport's
#     abstract surface. When the operator wants to change visibility
#     they currently relaunch a new lobby.
#
#   - Steam voice toggle. Was deferred per MP-0 plan note.
#
#   - Configurable per-system sync rates. Operator twiddles plumb
#     into NetTransport / per-system constants; not exposed as
#     runtime knobs yet.
#
#   - Reconnect after kick. Currently the kicked peer is dropped
#     to main menu (via NetTestWorldBootstrap.session_ended); they
#     can re-host or re-join through normal flow. A "rejoin" button
#     would need persistent host info.
#
#   - Ping latency for ENet backend. SteamMultiplayerPeer exposes
#     get_peer_latency; ENet doesn't have an equivalent in Godot's
#     wrapper. Pinger RPC pair (timestamped) is the standard
#     workaround; defer to follow-up.


# =============================================================
# CONFIG
# =============================================================

const TOGGLE_ACTION: String = "ui_text_completion_query"  # F10-style default
const UPDATE_INTERVAL: float = 0.5
const LOG_MAX_LINES: int = 12


# =============================================================
# UI (built programmatically)
# =============================================================

var _ui_root: CanvasLayer
var _panel: PanelContainer
var _status_label: Label
var _peers_container: VBoxContainer
var _log_label: Label
var _leave_btn: Button

var _peer_row_buttons: Array[Button] = []  # mirror of kick buttons for hit-testing

var _update_accumulator: float = 0.0
var _log_lines: Array[String] = []


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	_build_ui()
	# Hidden by default — F10 toggles. Operator-on-demand UI.
	_ui_root.visible = false
	# Hook MultiplayerManager events for the session log.
	if get_node_or_null("/root/MultiplayerManager") != null:
		MultiplayerManager.session_started.connect(func(m): _log("session_started mode=%s" % MultiplayerManager.MP_MODE.keys()[m]))
		MultiplayerManager.session_failed.connect(func(r): _log("session_failed: %s" % r))
		MultiplayerManager.session_ended.connect(func(r): _log("session_ended: %s" % r))
		MultiplayerManager.peer_joined.connect(func(id): _log("peer_joined: %d" % id))
		MultiplayerManager.peer_left.connect(func(id): _log("peer_left: %d" % id))


func _process(delta: float) -> void:
	if not _ui_root.visible:
		return
	_update_accumulator += delta
	if _update_accumulator >= UPDATE_INTERVAL:
		_update_accumulator = 0.0
		_refresh()


func _input(event: InputEvent) -> void:
	# Toggle on F10. We hardcode the physical keycode rather than
	# add a new Input Map action to keep this autoload self-contained
	# (no project.godot input section edit required).
	if event is InputEventKey:
		var k: InputEventKey = event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_F10:
			_ui_root.visible = not _ui_root.visible
			if _ui_root.visible:
				_refresh()
			get_viewport().set_input_as_handled()
			return

	# Manual click dispatch (see CLAUDE.md).
	if not _ui_root.visible:
		return
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_dispatch_click(mb.position)


# =============================================================
# UI BUILD
# =============================================================

func _build_ui() -> void:
	_ui_root = CanvasLayer.new()
	_ui_root.layer = 12  # above HUDOverlay (5) and CutsceneMirror (8)
	add_child(_ui_root)

	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -360
	_panel.offset_top = 16
	_panel.offset_right = -16
	_panel.offset_bottom = 480
	_ui_root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "MP Dev Menu  (F10 to toggle)"
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	_status_label = Label.new()
	_status_label.text = "(status)"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)

	vbox.add_child(HSeparator.new())

	var peers_title := Label.new()
	peers_title.text = "Peers:"
	peers_title.add_theme_font_size_override("font_size", 12)
	vbox.add_child(peers_title)

	_peers_container = VBoxContainer.new()
	_peers_container.add_theme_constant_override("separation", 2)
	vbox.add_child(_peers_container)

	vbox.add_child(HSeparator.new())

	var log_title := Label.new()
	log_title.text = "Session Log (last %d events):" % LOG_MAX_LINES
	log_title.add_theme_font_size_override("font_size", 12)
	vbox.add_child(log_title)

	_log_label = Label.new()
	_log_label.text = "(no events yet)"
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_log_label)

	_leave_btn = Button.new()
	_leave_btn.text = "Leave Session"
	_leave_btn.custom_minimum_size = Vector2(0, 28)
	vbox.add_child(_leave_btn)


# =============================================================
# CLICK DISPATCH
# =============================================================

func _dispatch_click(pos: Vector2) -> void:
	if _hits(_leave_btn, pos):
		_on_leave_pressed()
		return
	# Per-peer kick buttons (recomputed every _refresh).
	for btn in _peer_row_buttons:
		if _hits(btn, pos):
			var peer_id: int = int(btn.get_meta("peer_id", 0))
			if peer_id != 0:
				_on_kick_pressed(peer_id)
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

func _on_leave_pressed() -> void:
	if get_node_or_null("/root/MultiplayerManager") == null:
		return
	if MultiplayerManager.is_offline():
		_log("leave pressed but already offline")
		return
	MultiplayerManager.leave_session("operator leave via dev menu")
	_log("operator leave")


func _on_kick_pressed(peer_id: int) -> void:
	if get_node_or_null("/root/MultiplayerManager") == null:
		return
	if not MultiplayerManager.is_host():
		_log("kick %d ignored — only host can kick" % peer_id)
		return
	MultiplayerManager.kick_peer(peer_id, "kicked by host via dev menu")
	_log("kicked peer %d" % peer_id)


# =============================================================
# REFRESH
# =============================================================

func _refresh() -> void:
	if get_node_or_null("/root/MultiplayerManager") == null:
		_status_label.text = "MultiplayerManager not loaded."
		return

	var lines: Array[String] = []
	lines.append("Backend: %s   Available: %s" % [
		NetTransport.backend_name(),
		NetTransport.is_backend_available(),
	])
	lines.append("Mode: %s   Lifecycle: %s" % [
		MultiplayerManager.MP_MODE.keys()[MultiplayerManager.mode()],
		MultiplayerManager.LIFECYCLE.keys()[MultiplayerManager.lifecycle()],
	])
	lines.append("Local: %d   Total peers: %d" % [
		MultiplayerManager.local_peer_id(),
		MultiplayerManager.peers.size(),
	])
	_status_label.text = "\n".join(lines)

	# Rebuild peer rows. Always cheap — at most ~10 entries.
	for c in _peers_container.get_children():
		c.queue_free()
	_peer_row_buttons.clear()

	for peer_id in MultiplayerManager.peers.keys():
		var pid: int = int(peer_id)
		var rec: Dictionary = MultiplayerManager.peers[pid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_peers_container.add_child(row)

		var lbl := Label.new()
		var marker: String = " (you)" if pid == MultiplayerManager.local_peer_id() else ""
		var ping: int = MultiplayerManager.get_peer_latency_ms(pid)
		var ping_text: String = "ping=%d ms" % ping if ping >= 0 else "ping=?"
		lbl.text = "  • %d  %s%s   %s" % [pid, rec.get("display_name", "?"), marker, ping_text]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		# Kick button only for remote peers, only when host.
		if pid != MultiplayerManager.local_peer_id() and MultiplayerManager.is_host():
			var kick := Button.new()
			kick.text = "Kick"
			kick.custom_minimum_size = Vector2(60, 22)
			kick.set_meta("peer_id", pid)
			row.add_child(kick)
			_peer_row_buttons.append(kick)


func _log(msg: String) -> void:
	_log_lines.append("[%s] %s" % [Time.get_time_string_from_system(), msg])
	if _log_lines.size() > LOG_MAX_LINES:
		_log_lines = _log_lines.slice(_log_lines.size() - LOG_MAX_LINES)
	if _log_label != null:
		_log_label.text = "\n".join(_log_lines)
	# Always echo to console for after-the-fact debugging.
	print("[MPDevMenu] " + msg)
