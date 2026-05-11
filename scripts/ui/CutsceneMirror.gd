extends CanvasLayer
# CutsceneMirror — read-only Dialogic overlay shown to in-radius guests.
#
# WHAT THIS IS (plain English):
#
#   When the host triggers a Dialogic timeline and the local peer
#   (this guest) is within the trigger's cutscene_pull_radius, the
#   ProximityCutsceneManager broadcasts _rpc_cutscene_begin to this
#   peer. The handler does a group-lookup and calls show_cutscene
#   on every node tagged "cutscene_mirror_overlay" — including this
#   one.
#
#   The overlay shows:
#     - Current speaker name (top)
#     - Current line text (center-bottom)
#     - A faint hint that the host is driving ("watching" indicator)
#
#   The overlay does NOT accept input. Choices are host-only;
#   advancing the timeline is host-only. The guest is a spectator
#   until either the timeline ends OR they walk out of radius.
#
# WHEN INSTANCED:
#
#   The scene `scenes/ui/CutsceneMirror.tscn` is autoloaded by every
#   client. It stays invisible until show_cutscene() is called.
#   Lives at layer 8 — above HUDOverlay (layer 5) but below the
#   PauseMenu's overlay layer.
#
# WHY MANUAL DISPATCH IS NOT USED HERE:
#   This overlay has no clickable controls (read-only). The standard
#   manual _input pattern from CLAUDE.md isn't needed.


# =============================================================
# UI (built programmatically)
# =============================================================

var _panel: PanelContainer
var _speaker_label: Label
var _line_label: Label
var _choices_container: VBoxContainer
var _watching_label: Label


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# Join the group so ProximityCutsceneManager can find us via
	# get_tree().get_nodes_in_group(...). No hard-coded path needed.
	add_to_group("cutscene_mirror_overlay")
	layer = 8
	_build_ui()
	visible = false


# =============================================================
# PUBLIC API — called by ProximityCutsceneManager
# =============================================================

func show_cutscene(timeline_id: String, _origin: Vector3, _radius: float) -> void:
	# Reset to a neutral state — speaker / line will land via
	# set_line() after the host's next poll broadcasts.
	_speaker_label.text = ""
	_line_label.text = "(host is starting %s...)" % timeline_id
	_watching_label.text = "Watching — only the host can advance the dialogue."
	visible = true


func set_line(speaker: String, line: String) -> void:
	if not visible:
		# Late text arriving after we closed — ignore.
		return
	_speaker_label.text = speaker
	_line_label.text = line


## PR-B — render the host's current pending choices in a grayed-out
## list so guests can SEE the decision the host is about to make
## without being able to interact. Empty array hides the choices
## panel entirely (no decision pending).
func set_choices(choices: PackedStringArray) -> void:
	if not visible:
		return
	# Clear existing choice labels.
	for c in _choices_container.get_children():
		c.queue_free()
	if choices.is_empty():
		_choices_container.visible = false
		return
	_choices_container.visible = true
	for label in choices:
		var lbl := Label.new()
		lbl.text = "▸ %s" % label
		lbl.add_theme_font_size_override("font_size", 14)
		# Grayed-out modulate — visually communicates "host-only."
		lbl.modulate = Color(0.65, 0.65, 0.65, 1.0)
		_choices_container.add_child(lbl)


func hide_cutscene() -> void:
	visible = false
	if _choices_container != null:
		for c in _choices_container.get_children():
			c.queue_free()
		_choices_container.visible = false


# =============================================================
# UI BUILD
# =============================================================

func _build_ui() -> void:
	# Bottom-centered panel, similar to a subtitle bar.
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -380
	_panel.offset_top = -180
	_panel.offset_right = 380
	_panel.offset_bottom = -40
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	_speaker_label = Label.new()
	_speaker_label.text = ""
	_speaker_label.add_theme_font_size_override("font_size", 18)
	_speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vbox.add_child(_speaker_label)

	_line_label = Label.new()
	_line_label.text = ""
	_line_label.add_theme_font_size_override("font_size", 16)
	_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line_label.custom_minimum_size = Vector2(0, 64)
	vbox.add_child(_line_label)

	# PR-B — grayed-out choices panel; hidden when no choice pending.
	_choices_container = VBoxContainer.new()
	_choices_container.add_theme_constant_override("separation", 2)
	_choices_container.visible = false
	vbox.add_child(_choices_container)

	_watching_label = Label.new()
	_watching_label.text = ""
	_watching_label.add_theme_font_size_override("font_size", 12)
	_watching_label.modulate = Color(0.7, 0.7, 0.7, 0.9)
	vbox.add_child(_watching_label)
