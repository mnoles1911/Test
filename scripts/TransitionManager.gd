extends Node
# TransitionManager — Autoload singleton. Handles all scene changes.
#
# What "scene transition" means in plain English:
#   When Roland walks through a door, we don't just teleport him — we fade
#   the screen to black, load the next room, then fade back in. This script
#   handles that entire sequence so every scene in the game works the same way.
#
# Usage from any script (e.g. a door trigger):
#   TransitionManager.change_scene("res://scenes/act1/Archive.tscn", "entrance_south")
#   TransitionManager.change_scene("res://scenes/act1/Archive.tscn", "entrance_south", TransitionManager.Type.FADE_WHITE)
#   TransitionManager.go_back()   ← return to the previous scene
#
# What this script does automatically:
#   1. Fades screen (black, white, or cut)
#   2. Saves GameState to disk (autosave on every transition)
#   3. Loads the new scene
#   4. Fades back in


# =============================================================
# TRANSITION TYPE
# =============================================================

enum Type {
	FADE_BLACK,   # Standard: fade to black, load, fade back in
	FADE_WHITE,   # Dream / memory sequence: fade to white and back
	CUT           # Instant: no fade at all, just swap the scene
}


# =============================================================
# CONSTANTS
# =============================================================

const FADE_DURATION: float = 0.4
# Seconds for fade-out and fade-in.

const HISTORY_MAX: int = 10
# How many scenes to remember for go_back().

# Loading-screen tuning. The hourglass progresses linearly across
# `loading_seconds`. Background art rotates on its own timer, and the
# dark-humor quip line rotates on yet another (faster) timer.
const LOADING_BG_DIR: String = "res://assets/menu_backgrounds/"
const LOADING_BG_ROTATE_S: float = 20.0   # swap to a new background every N seconds
const LOADING_BG_FADE_S: float = 1.0      # crossfade duration when swapping
const LOADING_QUIP_ROTATE_S: float = 2.5  # swap to a new quip every N seconds
const LOADING_MUSIC_FADEOUT_S: float = 1.5
const LOADING_TIP_ROTATE_S: float = 8.0   # bottom-screen TIP footer cadence

# Gameplay tips for the bottom-of-screen TIP footer (mock:
# Voxelmark Loading Screen.html .tip element). Distinct from the
# LOADING_QUIPS humour list above — these are short, useful nudges
# that teach a control or a system. Add freely; rotated in shuffled
# order so the player rarely sees the same opener twice in a row.
const TIPS_GAMEPLAY: Array[String] = [
	"Press [E] to talk to NPCs. Most have things to do.",
	"Edits to the world persist. The pit you dug last week is still there.",
	"Hold attack longer for a heavier swing — at the cost of stamina.",
	"Lock-on with [RMB]. Useful when one-vs-many.",
	"Settlements are protected. The world won't yield inside their walls.",
	"Water flows. If you carve under a pond, expect a small flood.",
	"Save anywhere from the pause menu. Rest at a fire to autosave.",
	"Lethe's Draught lets you re-spec — once. Spend it carefully.",
	"Rain dampens fire. Wet bowstrings misfire. Dress for the weather.",
	"The compass points north. The sun rises east. The map is hand-drawn.",
	"You can throw most things. Sometimes that solves the problem.",
	"Roland flinches when low. The HUD rarely lies, but his body never does.",
	"Press Q / E to cycle quick slots. Shovels won't break stone.",
]

# Thematic dark-humor loading lines. Add or rewrite freely — pulled at
# random and shuffled so the player rarely sees the same opener twice
# in a row.
const LOADING_QUIPS: Array[String] = [
	"Pillaging villages...",
	"Organizing goblin bands...",
	"Conjuring sorcerer spells...",
	"Inviting pirates to the royal feast...",
	"Sharpening dwarven axes...",
	"Lighting the ash-throne's braziers...",
	"Forging cursed blades...",
	"Plucking arrows from corpses...",
	"Counting the king's gold (twice)...",
	"Polishing the executioner's block...",
	"Whispering rumours in tavern corners...",
	"Teaching wolves to read maps...",
	"Reminding the Aelorin who they were...",
	"Bargaining with the dwindling dead...",
	"Stoking the volcano under Drûn-Khazad...",
	"Rehearsing Roland's funeral oration...",
	"Apologizing to the goats...",
	"Bribing the night watch...",
	"Translating goblin curses...",
	"Salting the fields after harvest...",
	"Drafting unfair trade agreements...",
	"Misremembering the prophecy...",
	"Pouring mead for the long-dead...",
	"Stealing songs from minstrels...",
]


# =============================================================
# STATE
# =============================================================

var _is_transitioning: bool = false
# Guard flag — prevents double-triggering if two triggers fire at once.

var _scene_history: Array = []
# Stack of {path, spawn_id} dicts — most recent at the back.
# go_back() pops the last entry and transitions to it.

var _canvas_layer: CanvasLayer
var _fade_rect: ColorRect

# Loading screen — a labelled overlay shown WHILE the fade rect is
# still opaque, AFTER the destination scene has been loaded but
# BEFORE we fade back in. Gives Zylann's worker threads a window to
# stream the player's nearby chunks so the world is partially
# rendered the moment the fade clears. Only used for transitions
# into the open world (NEW GAME, LOAD GAME); regular door-to-door
# scene swaps skip the loading screen entirely.
var _loading_root: Control
var _loading_bg_a: TextureRect           # crossfade pair A
var _loading_bg_b: TextureRect           # crossfade pair B
var _loading_bg_using_a: bool = true     # which of A/B currently shows
var _loading_bg_textures: Array = []     # Texture2D list, shuffled
var _loading_bg_index: int = 0
var _loading_bg_timer: float = 0.0
var _loading_tint: ColorRect             # darkening overlay above the bg

var _loading_hourglass: LoadingHourglass
var _loading_hourglass_bob_t: float = 0.0   # phase for the slow Y-bob animation
var _loading_hourglass_base_y: float = 0.0  # captured at build time so the bob lerps around it
var _loading_title_label: Label
var _loading_quip_label: Label
var _loading_quip_timer: float = 0.0
var _loading_quip_index: int = 0
var _loading_quip_order: Array = []      # shuffled indices into LOADING_QUIPS

# Progress bar (520×8 sand-gradient, mock spec) + percentage label.
# Both update each tick from `_loading_elapsed / _loading_total_seconds`.
var _loading_bar_bg: ColorRect
var _loading_bar_fill: ColorRect
var _loading_pct_label: Label

# Bottom-of-screen TIP footer — rotates through TIPS_GAMEPLAY (a
# different list from LOADING_QUIPS) every LOADING_TIP_ROTATE_S so the
# player always has fresh gameplay context. Mock spec: smaller (14 px),
# more transparent (~0.55 alpha), gold "TIP" prefix in serif before the
# italic body. Built as a RichTextLabel so we can inline-colour the
# prefix without two separate nodes.
var _loading_tip_label: RichTextLabel
var _loading_tip_timer: float = 0.0
var _loading_tip_index: int = 0
var _loading_tip_order: Array = []       # shuffled indices into TIPS_GAMEPLAY

var _loading_active: bool = false
var _loading_total_seconds: float = 0.0
var _loading_elapsed: float = 0.0

# Top-right FPS readout — visible only while the loading screen is up.
# Mirrors DebugOverlay / PauseMenu: smoothed FPS plus a 60-sample
# sliding-window worst-frame-ms so the user can watch how the load
# performs without flipping on the dev overlay.
var _loading_fps_label: Label
var _loading_frame_times: PackedFloat32Array = PackedFloat32Array()
var _loading_frame_times_idx: int = 0
var _loading_fps_text_timer: float = 0.0   # gates label-text updates to ~4 Hz

# Records every CanvasLayer whose visibility we forced to false at
# loading-screen open. Each entry: {"node": Node, "prev_visible": bool}.
# Kept in a list so we can restore exact prior state (e.g. JournalUI
# may have been mid-fade) rather than blindly setting `visible = true`.
var _hidden_canvases: Array = []

# Music adopted from the previous scene (typically MainMenu) so it
# keeps playing through the loading screen. Faded out and freed when
# the loading screen ends.
var _adopted_music: AudioStreamPlayer = null


# =============================================================
# SETUP
# =============================================================

func _ready() -> void:
	# CanvasLayer at 100 renders above everything — UI, player, dialogue boxes.
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 100
	add_child(_canvas_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas_layer.add_child(_fade_rect)

	_build_loading_screen()
	process_mode = Node.PROCESS_MODE_ALWAYS

	print("[TransitionManager] Initialized.")


func _build_loading_screen() -> void:
	# All loading-screen UI is built once, here, then toggled visible
	# by _show_loading_screen / _hide_loading_screen. Layered bottom-up:
	#   1. _loading_root (fills viewport, ignores mouse)
	#   2. _loading_bg_a / _loading_bg_b (rotating background art, crossfade pair)
	#   3. _loading_tint (50% black tint for legibility — same as MainMenu)
	#   4. Centred column: title, hourglass, quip label
	_loading_root = Control.new()
	_loading_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_root.visible = false
	_canvas_layer.add_child(_loading_root)

	# Background pair. Both fill the screen; we crossfade modulate.a
	# between them when rotating. B starts transparent.
	_loading_bg_a = _make_loading_bg()
	_loading_root.add_child(_loading_bg_a)
	_loading_bg_b = _make_loading_bg()
	_loading_bg_b.modulate.a = 0.0
	_loading_root.add_child(_loading_bg_b)

	_loading_tint = ColorRect.new()
	_loading_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Mock spec: rgba(0,0,0,0.62) — pure black at 62% over the bg image.
	_loading_tint.color = Color(0.0, 0.0, 0.0, 0.62)
	_loading_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_root.add_child(_loading_tint)

	# (Vignette removed for performance.) The mock's
	# `box-shadow: inset 0 0 240px rgba(0,0,0,0.7)` was originally
	# implemented here as a full-screen radial-darken canvas_item
	# shader, but during the loading hold the GPU is also chewing
	# through Zylann's chunk mesh streaming behind the curtain — and
	# adding a full-viewport per-pixel shader on top spikes frame
	# delta into the visible-stutter range on slower GPUs. The 0.62
	# black tint above already provides the corner-darkened feel; if
	# we want the radial shape back later, bake a vignette texture
	# offline and load it as a single full-screen TextureRect (no
	# per-frame shader work).

	# Centre column — small hourglass on top, "L O A D I N G" title,
	# rotating quip line, then progress bar + percentage. Bottom-screen
	# TIP footer is built separately so it can pin to the viewport edge
	# regardless of the centred stack's position.
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.size = Vector2(600, 360)
	vbox.position = Vector2(-300, -180)
	vbox.add_theme_constant_override("separation", 18)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_root.add_child(vbox)

	# Hourglass — small (96×144), centred. Drains as progress advances
	# AND bobs subtly on a 5.2 s cycle (Voxelmark Loading Screen.html
	# spec). The bob motion is driven from _process so it's always
	# alive even if `progress` hasn't changed for a frame.
	#
	# The hourglass sits inside a non-Container Control wrapper so the
	# parent VBoxContainer doesn't override its position every layout
	# pass (Container parents reset position on each layout, which
	# would fight the bob animation). The wrapper takes the layout
	# slot; the hourglass inside it moves freely.
	var hg_wrap := Control.new()
	hg_wrap.custom_minimum_size = Vector2(96, 156)   # +12 px breathing room for bob + cap overflow
	hg_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hg_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hg_wrap)

	_loading_hourglass = LoadingHourglass.new()
	_loading_hourglass.size = Vector2(96, 144)
	_loading_hourglass.position = Vector2(0, 6)      # 6 px headroom so top cap overflow doesn't clip
	hg_wrap.add_child(_loading_hourglass)
	_loading_hourglass_base_y = _loading_hourglass.position.y  # captured for the bob to lerp around

	_loading_title_label = Label.new()
	# Faked letter-spacing — Godot Labels have no native letter-spacing
	# property, so insert a thin space between letters to match the
	# mock's open feel. Tradeoff: subtle screen-reader artefact, but
	# this is decorative chrome, not navigation.
	_loading_title_label.text = "L O A D I N G"
	_loading_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyles.apply_title_label(_loading_title_label, 44)
	# Hard 3 px black shadow so the title pops against busy backgrounds
	# (matches the .title text-shadow in the mock).
	_loading_title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_loading_title_label.add_theme_constant_override("shadow_offset_x", 3)
	_loading_title_label.add_theme_constant_override("shadow_offset_y", 3)
	vbox.add_child(_loading_title_label)

	# Centred rotating message — italic-ish parchment line that swaps
	# every LOADING_QUIP_ROTATE_S. Same role as the .msg in the mock.
	_loading_quip_label = Label.new()
	_loading_quip_label.text = ""
	_loading_quip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyles.apply_dim_label(_loading_quip_label, 20)
	_loading_quip_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_loading_quip_label.add_theme_constant_override("shadow_offset_x", 2)
	_loading_quip_label.add_theme_constant_override("shadow_offset_y", 2)
	_loading_quip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loading_quip_label.custom_minimum_size = Vector2(0, 56)   # leave room for two lines
	vbox.add_child(_loading_quip_label)

	# Progress bar + percentage — sand-gradient fill, dark leather
	# track. Mirrors the .bar / .pct pair in the mock.
	const BAR_W: float = 520.0
	const BAR_H: float = 8.0

	var bar_wrap := Control.new()
	bar_wrap.custom_minimum_size = Vector2(BAR_W, BAR_H)
	bar_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(bar_wrap)

	_loading_bar_bg = ColorRect.new()
	_loading_bar_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_bar_bg.color = Color(0.04, 0.024, 0.016, 1.0)   # dark leather
	_loading_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(_loading_bar_bg)

	# Bar fill — flat sand-bright. Originally a per-pixel shader doing
	# the mock's `linear-gradient(90deg, sand-deep, sand-bright)` plus
	# a trailing white-fade highlight, but full-pixel work on every
	# frame during the chunk-stream load is too expensive on slower
	# GPUs (the same reason the vignette shader was retired above).
	# A flat sand-bright reads close enough at 8 px tall.
	_loading_bar_fill = ColorRect.new()
	_loading_bar_fill.color = Color("#F5D06E")   # --sand-bright from the mock
	_loading_bar_fill.anchor_left = 0.0
	_loading_bar_fill.anchor_right = 0.0
	_loading_bar_fill.anchor_top = 0.0
	_loading_bar_fill.anchor_bottom = 1.0
	_loading_bar_fill.offset_left = 0.0
	_loading_bar_fill.offset_top = 0.0
	_loading_bar_fill.offset_right = 0.0   # widened each tick by _process
	_loading_bar_fill.offset_bottom = 0.0
	_loading_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(_loading_bar_fill)

	_loading_pct_label = Label.new()
	_loading_pct_label.text = "0%"
	_loading_pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyles.apply_title_label(_loading_pct_label, 18)
	_loading_pct_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_loading_pct_label.add_theme_constant_override("shadow_offset_x", 2)
	_loading_pct_label.add_theme_constant_override("shadow_offset_y", 2)
	vbox.add_child(_loading_pct_label)

	# Bottom-screen TIP footer — gold "TIP" prefix in serif then a
	# dimmer parchment body. Pinned bottom-centre with a small margin.
	# RichTextLabel so we can inline the gold prefix via BBCode.
	_loading_tip_label = RichTextLabel.new()
	_loading_tip_label.bbcode_enabled = true
	_loading_tip_label.fit_content = true
	_loading_tip_label.scroll_active = false
	_loading_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_tip_label.anchor_left = 0.0
	_loading_tip_label.anchor_right = 1.0
	_loading_tip_label.anchor_top = 1.0
	_loading_tip_label.anchor_bottom = 1.0
	_loading_tip_label.offset_left = 60
	_loading_tip_label.offset_right = -60
	_loading_tip_label.offset_top = -56
	_loading_tip_label.offset_bottom = -16
	# Centre the body line. fit_content + horizontal_alignment isn't
	# directly available on RichTextLabel; the wrapping anchor + fixed
	# offsets give the same effect.
	_loading_tip_label.text = ""
	# Default font + size — overridden via theme_color when we push
	# BBCode-coloured strings. Ink_dim @ ~0.55 alpha to match the mock.
	var tip_font := UIStyles.font_serif()
	if tip_font:
		_loading_tip_label.add_theme_font_override("normal_font", tip_font)
	_loading_tip_label.add_theme_font_size_override("normal_font_size", 14)
	_loading_tip_label.add_theme_color_override("default_color",
		Color(Colors.INK_DIM.r, Colors.INK_DIM.g, Colors.INK_DIM.b, 0.55))
	_loading_root.add_child(_loading_tip_label)

	# Top-right FPS readout — same style as the PauseMenu / DebugOverlay
	# version. Outlined white text, two lines, updated every frame in
	# _process while the loading screen is active.
	_loading_fps_label = Label.new()
	_loading_fps_label.text = "FPS: --\nworst: --"
	_loading_fps_label.add_theme_font_size_override("font_size", 14)
	_loading_fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_loading_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_loading_fps_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_loading_fps_label.add_theme_constant_override("outline_size", 4)
	_loading_fps_label.add_theme_constant_override("shadow_offset_x", 1)
	_loading_fps_label.add_theme_constant_override("shadow_offset_y", 1)
	_loading_fps_label.anchor_left = 1.0
	_loading_fps_label.anchor_right = 1.0
	_loading_fps_label.anchor_top = 0.0
	_loading_fps_label.anchor_bottom = 0.0
	_loading_fps_label.offset_left = -160
	_loading_fps_label.offset_right = -12
	_loading_fps_label.offset_top = 12
	_loading_fps_label.offset_bottom = 56
	_loading_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_loading_fps_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_loading_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_root.add_child(_loading_fps_label)

	# Pre-size the frame-time ring so per-frame writes don't allocate.
	_loading_frame_times.resize(60)
	for i in _loading_frame_times.size():
		_loading_frame_times[i] = 0.0


func _make_loading_bg() -> TextureRect:
	# Helper for the crossfade pair — both children are identical
	# except for their modulate alpha, which we tween at swap time.
	# (Variable name avoids `tr`, which shadows Object.tr() — Godot
	# emits a SHADOWED_VARIABLE_BASE_CLASS warning for that.)
	var bg_rect := TextureRect.new()
	bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bg_rect


func _process(delta: float) -> void:
	# Loading-screen animation tick. No-op when the screen is hidden.
	if not _loading_active:
		return

	# Delta clamp — at very low FPS (heavy chunk-stream load) raw delta
	# can exceed 100 ms. Animations driven by raw delta then jump in
	# huge increments, which reads as "jerky / stuttering" even though
	# the cadence is technically correct. Clamping to 50 ms makes the
	# bob, fill, and particle motion advance in consistent visible
	# steps. The wall-clock loading hold uses real delta below for the
	# actual elapsed bookkeeping so the screen still hides on schedule.
	var anim_delta: float = min(delta, 0.05)

	_loading_elapsed += delta

	# Hourglass progress maps elapsed → [0, 1]. Past 1.0 we just clamp
	# (the screen will be hidden by the awaited timer in _do_transition).
	var p: float = 0.0
	if _loading_total_seconds > 0.0:
		p = clamp(_loading_elapsed / _loading_total_seconds, 0.0, 1.0)
	if _loading_hourglass != null:
		_loading_hourglass.set_progress(p)
		# Subtle bob — sin-driven Y offset on a 5.2 s cycle, ±2 px.
		# Keeps the hourglass feeling alive even when progress is paused.
		# Uses the clamped anim_delta so the phase advances at a sane rate
		# even on stuttery frames.
		_loading_hourglass_bob_t += anim_delta
		var bob_phase: float = sin((_loading_hourglass_bob_t / 5.2) * TAU)
		_loading_hourglass.position.y = _loading_hourglass_base_y + bob_phase * -2.0

	# Progress bar fill + percentage label. Bar fills from left to right;
	# percentage rounds down to whole percent (matches the mock).
	#
	# Both updates are guarded against redundant writes — Label.text and
	# ColorRect.offset assignments trigger Control invalidation/redraw,
	# which is wasted work when the displayed value didn't change. At 10
	# FPS the integer percentage only changes ~once per frame anyway.
	if _loading_bar_fill != null and _loading_bar_bg != null:
		var bar_w: float = _loading_bar_bg.size.x
		var new_offset: float = bar_w * p
		if absf(_loading_bar_fill.offset_right - new_offset) > 0.5:
			_loading_bar_fill.offset_right = new_offset
	if _loading_pct_label != null:
		var new_pct: String = "%d%%" % int(floor(p * 100.0))
		if _loading_pct_label.text != new_pct:
			_loading_pct_label.text = new_pct

	# Bottom-screen TIP rotation — slower than the centred quip so the
	# player gets time to actually read it.
	_loading_tip_timer += delta
	if _loading_tip_timer >= LOADING_TIP_ROTATE_S:
		_loading_tip_timer = 0.0
		_advance_loading_tip()

	# Top-right FPS / worst-frame readout. Same logic as DebugOverlay:
	# 60-sample sliding window for spike detection. Tints red when worst
	# > 33 ms (sub-30 fps spike) so the user can see chunk-stream
	# stutters at a glance.
	#
	# Sample the frame time every tick (cheap), but only update the
	# label text every ~250 ms — Label glyph re-rasterisation on
	# gl_compatibility is non-trivial when the font is anti-aliased,
	# and the digits change too fast to read frame-by-frame anyway.
	if _loading_fps_label != null:
		_loading_frame_times[_loading_frame_times_idx] = delta
		_loading_frame_times_idx = (_loading_frame_times_idx + 1) % _loading_frame_times.size()
		_loading_fps_text_timer += delta
		if _loading_fps_text_timer >= 0.25:
			_loading_fps_text_timer = 0.0
			var worst: float = 0.0
			for ft in _loading_frame_times:
				if ft > worst:
					worst = ft
			var worst_ms: int = int(round(worst * 1000.0))
			_loading_fps_label.text = "FPS: %d\nworst: %d ms" % [
				Engine.get_frames_per_second(), worst_ms,
			]
			if worst_ms > 33:
				_loading_fps_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5, 0.95))
			else:
				_loading_fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))

	# Background rotation. First swap fires after LOADING_BG_ROTATE_S.
	if _loading_bg_textures.size() > 1:
		_loading_bg_timer += delta
		if _loading_bg_timer >= LOADING_BG_ROTATE_S:
			_loading_bg_timer = 0.0
			_advance_loading_background()

	# Quip rotation.
	_loading_quip_timer += delta
	if _loading_quip_timer >= LOADING_QUIP_ROTATE_S:
		_loading_quip_timer = 0.0
		_advance_loading_quip()


# =============================================================
# PUBLIC API
# =============================================================

func change_scene(scene_path: String, spawn_id: String = "", type: Type = Type.FADE_BLACK, loading_seconds: float = 0.0) -> void:
	# Call this from any trigger to change scenes.
	# scene_path       — "res://scenes/zones/Aldenholt.tscn"
	# spawn_id         — matches a SpawnPoint.spawn_id in the destination scene
	# type             — FADE_BLACK (default), FADE_WHITE, or CUT
	# loading_seconds  — if > 0, hold the destination scene under a "Loading..."
	#                    overlay for this many seconds AFTER the scene loads
	#                    but BEFORE the fade-in. Use this for transitions into
	#                    the open world where chunks need time to stream in
	#                    (NEW GAME / LOAD GAME). Door-to-door swaps leave it 0.
	if _is_transitioning:
		return

	_is_transitioning = true

	# Push current scene onto history before leaving it.
	# On first launch GameState.current_scene is empty (TransitionManager
	# was never called before), so fall back to the tree's actual scene
	# path — that way go_back() can return to MainMenu even from the
	# very first scene change the player triggers.
	var current_path: String = GameState.current_scene
	if current_path == "" and get_tree().current_scene != null:
		current_path = get_tree().current_scene.scene_file_path
	if current_path != "":
		_push_history(current_path, GameState.player_spawn_id)

	# Store where to spawn the player in the new scene.
	GameState.player_spawn_id = spawn_id
	GameState.current_scene = scene_path

	# (Previously called GameState.save_game() here on every scene
	# transition. Removed: it created an untagged save on top of the
	# PauseMenu's already-explicit '[Auto]' save on EXIT TO MENU and
	# QUIT, so going to the menu produced two saves at the same
	# timestamp. Save points are now exclusively the explicit player
	# action (SAVE button) and the on-exit/on-quit auto-save in
	# PauseMenu, both of which produce one named/autosave file each.)

	_do_transition(scene_path, type, loading_seconds)


func go_back() -> void:
	# Return to the previous scene. Does nothing if there is no history.
	if _scene_history.is_empty():
		print("[TransitionManager] go_back() called with no history.")
		return
	if _is_transitioning:
		return

	var entry: Dictionary = _scene_history.pop_back()
	change_scene(entry["path"], entry["spawn_id"], Type.FADE_BLACK)


func fade_in_only() -> void:
	# Call from a scene's _ready() if you need manual fade-in control
	# (e.g. after a cutscene that should start black).
	_fade_in(Type.FADE_BLACK)


func has_history() -> bool:
	return not _scene_history.is_empty()


func peek_back() -> String:
	# Returns the scene path that go_back() would transition to,
	# without actually popping it. Returns "" if history is empty.
	if _scene_history.is_empty():
		return ""
	return _scene_history.back()["path"]


# =============================================================
# HISTORY
# =============================================================

func _push_history(path: String, spawn_id: String) -> void:
	_scene_history.append({"path": path, "spawn_id": spawn_id})
	# Keep history bounded so it doesn't grow forever.
	if _scene_history.size() > HISTORY_MAX:
		_scene_history.pop_front()


# =============================================================
# TRANSITION SEQUENCE
# =============================================================

func _do_transition(scene_path: String, type: Type, loading_seconds: float = 0.0) -> void:
	if type == Type.CUT:
		# No fade — swap immediately.
		get_tree().change_scene_to_file(scene_path)
		await get_tree().process_frame
		_is_transitioning = false
		return

	# Determine the fade color.
	var fade_color: Color = Color(0.0, 0.0, 0.0, 0.0) if type == Type.FADE_BLACK else Color(1.0, 1.0, 1.0, 0.0)
	var _opaque_color: Color = Color(fade_color.r, fade_color.g, fade_color.b, 1.0)

	_fade_rect.color = fade_color

	# Fade out.
	var tween = create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, FADE_DURATION)
	await tween.finished

	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame

	# Optional loading-screen hold — fade rect stays opaque, loading
	# overlay shows on top, the destination scene streams in
	# behind the curtain. Skipped when loading_seconds <= 0.
	if loading_seconds > 0.0:
		_show_loading_screen(loading_seconds)
		await get_tree().create_timer(loading_seconds, true).timeout
		_hide_loading_screen()

	_fade_in(type)


func _show_loading_screen(total_seconds: float) -> void:
	if _loading_root == null:
		return
	# Reset all the rotating timers and pick fresh shuffles so the
	# player isn't starting from the same image / quip every load.
	_loading_total_seconds = max(total_seconds, 0.001)
	_loading_elapsed = 0.0
	_loading_bg_timer = 0.0
	_loading_quip_timer = 0.0

	_refresh_loading_backgrounds()
	_refresh_loading_quips()
	_refresh_loading_tips()
	if _loading_hourglass != null:
		_loading_hourglass.set_progress(0.0)
		# Reset bob phase so the hourglass starts at base position.
		_loading_hourglass_bob_t = 0.0
	# Reset progress bar visuals — fill starts at zero width.
	if _loading_bar_fill != null:
		_loading_bar_fill.offset_right = 0.0
	if _loading_pct_label != null:
		_loading_pct_label.text = "0%"
	# Reset quip alpha in case a previous session left it mid-tween.
	if _loading_quip_label != null:
		_loading_quip_label.modulate.a = 1.0

	# Perf optimisations during the loading hold. The whole point of
	# the 20 s – 1.5 min hold is to let Zylann's worker threads
	# generate AND upload chunks so the world is hot when the curtain
	# lifts. So we MUST NOT pause VoxelLodTerrain, the heavy autoloads,
	# or the destination scene's processing — those are exactly the
	# things doing the load work.
	#
	# The only legitimate optimisations are the ones that take work
	# AWAY from the renderer without slowing chunk loading:
	#
	# 1. `viewport.disable_3d = true` — skips 3D rasterisation on the
	#    viewport. Zylann's chunk-mesh GPU uploads still happen
	#    (they're issued via RenderingServer regardless of the
	#    viewport's render flag), but the per-frame draw of the
	#    visible 3D scene behind our opaque curtain is suppressed.
	#
	# 2. Hide the gameplay UI CanvasLayers (`HUDOverlay`, `JournalUI`).
	#    Both render at layer 5/10 — visually covered by the
	#    layer-100 loading overlay, but Godot still issues draw calls
	#    for them every frame. HUDOverlay's compass calls
	#    queue_redraw + multiple draw_string (font glyph rasterisation
	#    on gl_compatibility is real work) every tick. Hiding the
	#    CanvasLayer itself stops the draw calls — _process keeps
	#    running, _draw doesn't.
	#
	# Earlier iterations of this fix also paused VoxelLodTerrain +
	# heavy autoloads + the destination scene root — that fixed the
	# loading-screen FPS but defeated the user's intent (chunks
	# couldn't actually load during the hold). Removed; chrome hides
	# alone are enough for smooth load-screen FPS while letting the
	# world fully stream in.
	var vp := get_viewport()
	if vp != null:
		vp.disable_3d = true

	# Hide gameplay UI CanvasLayers. Stored in _hidden_canvases
	# ({node, prev_visible}) so we can restore exact prior state —
	# JournalUI may have been mid-fade and we don't want to silently
	# force it open.
	_hidden_canvases.clear()
	for canvas_path in [
			"/root/HUDOverlay",
			"/root/JournalUI",
		]:
		var c: Node = get_node_or_null(canvas_path)
		if c != null and "visible" in c:
			_hidden_canvases.append({"node": c, "prev_visible": c.get("visible")})
			c.set("visible", false)

	print("[TransitionManager] Loading screen open — hid %d UI canvases (chunk loading active)" % _hidden_canvases.size())
	_loading_root.visible = true
	_loading_active = true


func _hide_loading_screen() -> void:
	_loading_active = false
	if _loading_root != null:
		_loading_root.visible = false
	# Re-enable 3D rendering on the viewport AND restore every node we
	# forced to DISABLED in _show_loading_screen. Doing this BEFORE the
	# fade-in so the world starts rendering during the fade and the
	# player doesn't see a black frame on the seam.
	var vp := get_viewport()
	if vp != null:
		vp.disable_3d = false
	for entry in _hidden_canvases:
		var c: Node = entry["node"]
		if is_instance_valid(c) and "visible" in c:
			c.set("visible", entry["prev_visible"])
	print("[TransitionManager] Loading screen closed — restored %d canvases" % _hidden_canvases.size())
	_hidden_canvases.clear()
	# Whatever music we adopted from the previous scene fades out and
	# is freed here. World scenes start their own ambient audio after
	# the fade-in clears.
	_stop_adopted_music()


# Background rotation -----------------------------------------------

func _refresh_loading_backgrounds() -> void:
	# Re-scan the menu_backgrounds folder each time the screen opens
	# so newly-dropped art shows up without a restart. Shuffles the
	# list and picks index 0 as the starting image.
	_loading_bg_textures = _scan_loading_background_textures()
	_loading_bg_textures.shuffle()
	_loading_bg_index = 0
	_loading_bg_using_a = true

	if _loading_bg_textures.is_empty():
		# No art in the folder — show the dark fallback only.
		_loading_bg_a.texture = null
		_loading_bg_b.texture = null
		_loading_bg_a.modulate.a = 0.0
		_loading_bg_b.modulate.a = 0.0
		return

	_loading_bg_a.texture = _loading_bg_textures[0]
	_loading_bg_a.modulate.a = 1.0
	_loading_bg_b.texture = null
	_loading_bg_b.modulate.a = 0.0


func _advance_loading_background() -> void:
	if _loading_bg_textures.size() <= 1:
		return
	_loading_bg_index = (_loading_bg_index + 1) % _loading_bg_textures.size()
	var next_tex: Texture2D = _loading_bg_textures[_loading_bg_index]

	# Crossfade: load `next_tex` into the inactive slot, then fade A↔B.
	var fading_in: TextureRect = _loading_bg_b if _loading_bg_using_a else _loading_bg_a
	var fading_out: TextureRect = _loading_bg_a if _loading_bg_using_a else _loading_bg_b
	fading_in.texture = next_tex
	fading_in.modulate.a = 0.0

	var tween := create_tween().set_parallel(true)
	tween.tween_property(fading_in, "modulate:a", 1.0, LOADING_BG_FADE_S)
	tween.tween_property(fading_out, "modulate:a", 0.0, LOADING_BG_FADE_S)
	_loading_bg_using_a = not _loading_bg_using_a


func _scan_loading_background_textures() -> Array:
	# Returns Array[Texture2D] from LOADING_BG_DIR. Same scanner shape
	# as MainMenu._load_random_background, kept inline so this module
	# has no hard dependency on MainMenu being loaded.
	var out: Array = []
	var dir := DirAccess.open(LOADING_BG_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var lower: String = fname.to_lower()
			if lower.ends_with(".png") \
				or lower.ends_with(".jpg") \
				or lower.ends_with(".jpeg") \
				or lower.ends_with(".webp"):
				var tex: Texture2D = load(LOADING_BG_DIR + fname) as Texture2D
				if tex != null:
					out.append(tex)
		fname = dir.get_next()
	dir.list_dir_end()
	return out


# Quip rotation ------------------------------------------------------

func _refresh_loading_quips() -> void:
	# Build a freshly-shuffled order so the player rarely sees the same
	# opener twice. Index 0 is the first line shown.
	_loading_quip_order.clear()
	for i in range(LOADING_QUIPS.size()):
		_loading_quip_order.append(i)
	_loading_quip_order.shuffle()
	_loading_quip_index = 0
	if _loading_quip_label != null and not _loading_quip_order.is_empty():
		_loading_quip_label.text = LOADING_QUIPS[_loading_quip_order[0]]


func _advance_loading_quip() -> void:
	if _loading_quip_order.is_empty() or _loading_quip_label == null:
		return
	_loading_quip_index = (_loading_quip_index + 1) % _loading_quip_order.size()
	# Mock spec: 0.4 s fade-out, swap text, 0.4 s fade-in. Cleaner than
	# a hard cut on a centred prominent line.
	var tween := create_tween()
	tween.tween_property(_loading_quip_label, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func():
		_loading_quip_label.text = LOADING_QUIPS[_loading_quip_order[_loading_quip_index]]
	)
	tween.tween_property(_loading_quip_label, "modulate:a", 1.0, 0.4)


# Bottom-TIP rotation (separate cadence from the centred quip) -------

# Build a fresh shuffled order through TIPS_GAMEPLAY and prime the
# label with the first entry. Called whenever the loading screen opens
# so the player sees a fresh tip on every load.
func _refresh_loading_tips() -> void:
	_loading_tip_order.clear()
	for i in range(TIPS_GAMEPLAY.size()):
		_loading_tip_order.append(i)
	_loading_tip_order.shuffle()
	_loading_tip_index = 0
	_loading_tip_timer = 0.0
	if _loading_tip_label != null and not _loading_tip_order.is_empty():
		_loading_tip_label.text = _format_tip(TIPS_GAMEPLAY[_loading_tip_order[0]])


func _advance_loading_tip() -> void:
	if _loading_tip_order.is_empty() or _loading_tip_label == null:
		return
	_loading_tip_index = (_loading_tip_index + 1) % _loading_tip_order.size()
	_loading_tip_label.text = _format_tip(TIPS_GAMEPLAY[_loading_tip_order[_loading_tip_index]])


# Format a tip line with the gold "TIP" prefix in serif. RichTextLabel
# BBCode lets us inline a coloured prefix without a second node.
func _format_tip(body: String) -> String:
	# Voxelmark gold (#f0c14b) for the prefix; the body inherits the
	# label's default_color (parchment-ink @ 0.55 alpha).
	return "[center][color=#f0c14b]TIP[/color]   %s[/center]" % body


# Music adoption -----------------------------------------------------

func adopt_music(player: AudioStreamPlayer) -> void:
	# Called by MainMenu just before it triggers a loading-screen
	# transition. We reparent the AudioStreamPlayer onto this autoload
	# so it survives the change_scene_to_file() that frees MainMenu.
	# When the loading screen ends, _stop_adopted_music fades it out
	# and frees it.
	#
	# AudioStreamPlayer stops when it leaves the scene tree, so we
	# capture the current playback position and resume from it after
	# reparenting — the audible result is one almost-imperceptible blip.
	if player == null:
		return
	# If we somehow still hold one from a previous run, drop it cleanly
	# before adopting the new one.
	if _adopted_music != null and is_instance_valid(_adopted_music):
		_adopted_music.queue_free()
		_adopted_music = null

	var was_playing: bool = player.playing
	var pos: float = player.get_playback_position() if was_playing else 0.0

	var parent: Node = player.get_parent()
	if parent != null:
		parent.remove_child(player)
	add_child(player)

	if was_playing:
		player.play(pos)

	_adopted_music = player


func _stop_adopted_music() -> void:
	if _adopted_music == null or not is_instance_valid(_adopted_music):
		_adopted_music = null
		return
	# Capture into a local so the closure doesn't see a null-by-then var.
	var player: AudioStreamPlayer = _adopted_music
	_adopted_music = null
	var tween := create_tween()
	tween.tween_property(player, "volume_db", -40.0, LOADING_MUSIC_FADEOUT_S)
	tween.tween_callback(player.queue_free)


func _fade_in(type: Type = Type.FADE_BLACK) -> void:
	# Reset the rect to the correct opaque color first (in case a cut transition
	# left it transparent), then animate to transparent.
	var r: float = 0.0 if type == Type.FADE_BLACK else 1.0
	_fade_rect.color = Color(r, r, r, 1.0)

	var tween = create_tween()
	tween.tween_property(_fade_rect, "color:a", 0.0, FADE_DURATION)
	await tween.finished
	_is_transitioning = false
