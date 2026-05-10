extends CanvasLayer
# SaveNotification — Autoload. Shows a brief "SAVING…" indicator.
#
# What this does in plain English:
#   Every time the game autosaves (on scene transitions, manual saves),
#   a small label appears in the corner of the screen for 1.5 seconds,
#   then fades out. This tells the player "your progress was saved."
#   It uses CanvasLayer layer 99 so it appears above the game but below
#   the TransitionManager's fade overlay (layer 100).
#
# Usage — call from anywhere:
#   SaveNotification.show_notification()
#
# GameState.save_game() calls this automatically, so you don't need
# to call it manually in most cases.
#
# HOW TO ADJUST THE LOOK:
#   - Change DISPLAY_DURATION to keep it on screen longer or shorter
#   - Change the position in _ready() (bottom-right is conventional)
#   - Change the label text ("AUTO SAVE", "✓ Saved", etc.)


# =============================================================
# CONSTANTS
# =============================================================

const DISPLAY_DURATION: float = 1.5
# How many seconds the label stays visible before fading out.

const FADE_DURATION: float = 0.4
# Fade-in and fade-out time in seconds.


# =============================================================
# STATE
# =============================================================

var _label: Label
var _is_showing: bool = false


# =============================================================
# SETUP
# =============================================================

func _ready() -> void:
	layer = 99

	_label = Label.new()
	_label.text = "— SAVING —"
	_label.add_theme_font_size_override("font_size", 20)
	_label.modulate = Color(0.7, 0.7, 0.7, 0.0)  # Start fully transparent

	# Position: bottom-right corner. At 1920×1080 the label is wider/taller
	# than the 320×180 era, so the offset is larger to keep it off the edge.
	_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_label.position = Vector2(-160, -40)

	add_child(_label)

	print("[SaveNotification] Initialized.")


# =============================================================
# PUBLIC API
# =============================================================

func show_notification() -> void:
	# Dev-scene guard — BakeWorld / CopperIslesTest / any scene in the
	# "dev_scene" group skips the "— SAVING —" indicator so dev workflows
	# (e.g. F5 mid-bake) don't paint the corner label.
	if get_node_or_null("/root/GameState") and GameState.is_dev_scene():
		return
	# If already showing, restart the sequence from the beginning.
	_is_showing = true
	_label.modulate.a = 0.0
	_animate()


# =============================================================
# ANIMATION
# =============================================================

func _animate() -> void:
	# Fade in.
	var tween_in = create_tween()
	tween_in.tween_property(_label, "modulate:a", 1.0, FADE_DURATION)
	await tween_in.finished

	# Hold.
	await get_tree().create_timer(DISPLAY_DURATION).timeout

	# Fade out.
	var tween_out = create_tween()
	tween_out.tween_property(_label, "modulate:a", 0.0, FADE_DURATION)
	await tween_out.finished

	_is_showing = false
