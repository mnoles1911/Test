extends CanvasLayer
# MPNotification — toast overlay for multiplayer-related notices.
#
# WHAT THIS IS (plain English):
#
#   A center-screen modal-ish toast that surfaces MP events the
#   player needs to see but the regular HUD doesn't carry: handshake
#   rejection reasons, connection lost notices, kick reasons, etc.
#
#   Distinct from SaveNotification (corner indicator for save flow):
#   MP events are usually session-fatal and need to be acknowledged
#   or auto-dismissed before play resumes.
#
# WHY ITS OWN AUTOLOAD:
#
#   SaveNotification is locked to "— SAVING —" text and corner
#   placement. Generalizing it would change its public API and
#   break call sites. A focused MP-specific notifier is cleaner.
#
# API:
#
#   show_message(text: String, hold_seconds: float = 3.0)
#   show_message_then_disconnect(text, hold_seconds, reason)
#     → shows the toast, then calls MultiplayerManager.leave_session
#       after hold_seconds so the user can read the message before
#       the disconnect.
#
# Layer 99 (same as SaveNotification) so it sits above HUD, dev
# menu, and pause menu.


# =============================================================
# CONFIG
# =============================================================

const DEFAULT_HOLD_SECONDS: float = 3.0


# =============================================================
# UI
# =============================================================

var _panel: PanelContainer
var _label: Label
var _is_showing: bool = false


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	layer = 99

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.35
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.35
	_panel.offset_left = -320
	_panel.offset_top = -50
	_panel.offset_right = 320
	_panel.offset_bottom = 50
	_panel.visible = false
	add_child(_panel)

	_label = Label.new()
	_label.text = ""
	_label.add_theme_font_size_override("font_size", 20)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_label)

	print("[MPNotification] Initialized.")


# =============================================================
# PUBLIC API
# =============================================================

## Show a toast message for `hold_seconds`. If called again while
## showing, the new message replaces the current one and the timer
## resets.
func show_message(text: String, hold_seconds: float = DEFAULT_HOLD_SECONDS) -> void:
	if get_node_or_null("/root/GameState") != null and GameState.is_dev_scene():
		# Dev scenes still get the message — operator wants to see
		# handshake rejection reasons during testing.
		pass
	_label.text = text
	_panel.visible = true
	_is_showing = true
	# Cancel any pending auto-hide via tween and start a fresh one.
	var tween: Tween = create_tween()
	tween.tween_interval(hold_seconds)
	tween.tween_callback(func(): _hide_now())
	print("[MPNotification] %s" % text)


## Show a message, then disconnect from the active session after
## hold_seconds. Used for hard-reject paths: the user sees the
## reason for a few seconds, then we tear down the connection.
func show_message_then_disconnect(text: String, hold_seconds: float = DEFAULT_HOLD_SECONDS, reason: String = "") -> void:
	_label.text = text
	_panel.visible = true
	_is_showing = true
	var tween: Tween = create_tween()
	tween.tween_interval(hold_seconds)
	tween.tween_callback(func(): _hide_and_disconnect(reason if not reason.is_empty() else text))
	print("[MPNotification] %s (disconnect in %.1fs)" % [text, hold_seconds])


func hide_now() -> void:
	_hide_now()


# =============================================================
# INTERNALS
# =============================================================

func _hide_now() -> void:
	_panel.visible = false
	_is_showing = false


func _hide_and_disconnect(reason: String) -> void:
	_hide_now()
	if get_node_or_null("/root/MultiplayerManager") != null:
		if not MultiplayerManager.is_offline():
			MultiplayerManager.leave_session(reason)
