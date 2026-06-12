extends CanvasLayer
# HUDOverlay — Health and endurance bars, bottom-center of the screen.
#
# What this does in plain English:
#   During gameplay two progress bars sit near the bottom of the screen.
#   The top bar (red) shows Roland's health. The bottom bar (green) shows
#   his endurance — how much sprinting energy he has left.
#   A small status label above the bars shows "CROUCHING" or "EXHAUSTED"
#   when those states are active.
#
#   This script finds the player automatically each frame by searching for
#   nodes in the "player" group (Player3D.tscn adds itself to that group).
#   If no player exists — e.g. when the main menu is showing — the HUD
#   hides itself cleanly.
#
# HOW TO ADJUST THE LOOK:
#   Edit the constants at the top of _build_ui() below.
#   PANEL_WIDTH / PANEL_HEIGHT — overall size of the HUD container.
#   BAR_HP_HEIGHT / BAR_END_HEIGHT — thickness of each bar.
#   Fill and background colors are in the StyleBoxFlat blocks.


# =============================================================
# PERFORMANCE DIAGNOSTIC (frame-spike aggregator + engine stats)
# =============================================================

const PERF_DIAG: bool = true
# Master toggle for the per-second diag print added 2026-05-07. When
# true, _perf_diag_tick aggregates frame spikes and engine-wide stats
# into one summary line per second instead of the old per-frame
# [FRAME SPIKE] flood. Flip false once the streaming/collision
# investigation lands.

const PERF_DIAG_SPIKE_MS: float = 50.0
# Frame-time threshold (ms) above which a frame counts as a "spike"
# in the per-second tally.

var _perf_spike_count: int = 0
var _perf_spike_max_ms: float = 0.0
var _perf_window_start_msec: int = 0

# Set by _build_spike_dump after a spike is logged in the per-second
# [PERF] line, so the same spike isn't re-printed every second until a
# worse one displaces it from Profiler._last_spike.
var _perf_last_logged_spike_frame: int = -1

# Per-autoload work attribution. Each autoload wraps its _process /
# _physics_process with Time.get_ticks_usec() and calls profile_record(
# label, usec). _perf_diag_tick dumps the top 3 buckets every second
# and resets, so the PERF line shows which scripts ate the spike.
# Replaces the proc=/phys= TIME_PROCESS columns, which turned out to
# track per-frame snapshot timings — useful as a sanity check but not
# attributable to specific scripts.
var _profile_buckets: Dictionary = {}


# =============================================================
# NODE REFERENCES (set in _build_ui, read in _process every frame)
# =============================================================

var _root: Control
var _hp_bar: ProgressBar
var _end_bar: ProgressBar
var _hp_value_label: Label
var _end_value_label: Label
var _status_label: Label

# Phase 6 (directional melee v1) — parry chain counter ("x2", "x3") shown
# right of the status label. Reads MeleeHandler.parry_chain.current_chain_count
# in _process; hidden when count is 0 or 1. Painted Colors.MANA (blue) so it
# reads as a distinct callout vs HP/STAM tints.
var _chain_count_label: Label

# Phase 6 — directional-attack arrows above committed enemies + a small
# combat radar bottom-center. Both added in _ready, hidden by
# _hide_all_chrome for dev scenes.
var _direction_arrows: Control
var _combat_radar: Control

# Voxelmark HUD chrome (added 2026-05-06 to match
# assets/ui/html/Voxelmark HUD v1.html). Each subtree builds and
# refreshes itself; layout positions match the mock except for the
# vitals stack (kept to two rows — HP + END — until the underlying
# Hunger / Mana systems are implemented). Mining bar, FPS readout,
# edit-volume label, and the quick-slot bar are gameplay-driven and
# sit above/around the mock chrome in the same screen positions they
# had pre-overhaul.
var _crosshair: Control                 # screen centre, 18×18
var _compass_root: Control              # top-centre
var _compass_strip: Panel
var _compass_ticks: Control             # custom-drawn — labels + tick marks scrolled by heading
var _compass_needle: ColorRect          # red 2 px line at strip centre
var _compass_coord_label: Label         # X/Y/Z under the strip
var _clock_root: Control                # top-right
var _clock_day_label: Label             # "DAY 47"
var _clock_time_label: Label            # "19:42"
var _clock_biome_label: Label           # "★ ASHWOOD HOLLOW · DUSK"
var _hotbar_tooltip: Panel              # floats above the quick-slot bar on hover/equip
var _hotbar_tooltip_name: Label
var _hotbar_tooltip_meta: Label
var _hotbar_tooltip_alpha_target: float = 0.0
var _damage_pulse: ColorRect            # full-screen red vignette tween on health drop
var _low_hp_pulse: ColorRect            # animated red vignette while HP < 25 %
var _last_known_health: float = -1.0    # for damage detection (subscribed via _process)
var _low_hp_pulse_t: float = 0.0        # phase accumulator for the slow blood pulse
var _bark_overlay: Control              # NPC bark frame; joins the "bark_overlay" group itself

# Mining-progress bar — shown only while the player is actively
# holding LMB on a mineable voxel. Sits ABOVE the HP/endurance
# panel so it doesn't push the layout around. Updated each frame
# from EditToolHandler.mining_progress (0..1) and visibility
# follows EditToolHandler.mining_active.
var _mining_root: Control
var _mining_bar: ProgressBar
var _mining_label: Label

# Quick-slot bar — 4 small slots in a horizontal row, just below
# the mining bar. Number keys 1-4 swap the equipped weapon to that
# slot's item. Right-click on a slot will eventually open a rebind
# picker (Phase 2). Currently-equipped slot is highlighted gold.
var _quick_root: Control
var _quick_slot_panels: Array[Panel] = []   # the visual frame
var _quick_slot_labels: Array[Label] = []   # item-name display
var _quick_slot_buttons: Array[Button] = [] # transparent click target for right-click rebind

# Cached so _find_player() doesn't search every frame when the player
# hasn't changed. Invalidated when the node becomes null.
#
# (FPS / worst-ms spike readout used to live here as `_fps_label` plus
# `_frame_times` ring buffer. It moved to DebugOverlay's top-right HUD
# in the 2026-05-06 pass — debug info belongs next to coords / aim /
# world-time on the dev overlay, not on the player-facing HUD.)
var _cached_player: Node = null

# Bottom-left carve-volume readout. Hidden when no manual tool is
# equipped (scroll-cycle only matters with pickaxe / shovel / axe).
var _edit_volume_label: Label


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	layer = 5
	# Layer 5: above the game world, below the journal (10) and pause (50).
	# Damage / low-HP overlays go in FIRST so they sit BEHIND the rest of
	# the HUD chrome (CanvasLayer renders children back-to-front).
	_build_damage_pulse()
	_build_low_hp_pulse()
	_build_ui()
	_build_mining_bar()
	_build_quick_slot_bar()
	_build_edit_mode_label()
	_build_crosshair()
	_build_compass()
	_build_clock()
	_build_hotbar_tooltip()
	_build_bark_overlay()
	_build_combat_hud()
	print("[HUDOverlay] Initialized.")


func _build_combat_hud() -> void:
	# Phase 6 (directional melee v1) — direction arrows above enemies +
	# small combat radar bottom-center. Both are pure read-only Controls
	# that read from LockOnManager + Enemy3D signals; mouse_filter is
	# IGNORE so they never intercept clicks.
	var arrows_script := preload("res://scripts/HUDDirectionArrows.gd")
	_direction_arrows = arrows_script.new()
	_direction_arrows.name = "DirectionArrows"
	add_child(_direction_arrows)

	var radar_script := preload("res://scripts/HUDCombatRadar.gd")
	_combat_radar = radar_script.new()
	_combat_radar.name = "CombatRadar"
	add_child(_combat_radar)


# Instantiates the BarkOverlay (scripts/ui/BarkOverlay.gd) as a child
# of this CanvasLayer. The script self-joins the "bark_overlay" group
# in its _ready, so BarkManager.fire() can find it via
# get_first_node_in_group. Hidden by _hide_all_chrome on dev scenes.
func _build_bark_overlay() -> void:
	var bark_script := preload("res://scripts/ui/BarkOverlay.gd")
	_bark_overlay = bark_script.new()
	add_child(_bark_overlay)


func _build_quick_slot_bar() -> void:
	# 4 slots in a horizontal row, pinned bottom-centre but ABOVE the
	# main HP/endurance panel and BELOW the mining bar. Each slot is
	# a small panel showing the slot number (top-left), the bound
	# item name (centre), and a highlight when that slot's item is
	# the currently-equipped weapon.
	#
	# Slot panel doubles as a click target for right-click rebinding
	# (Phase 2 — the gui_input handler is wired but currently a stub).
	const SLOT_W: float       = 110.0
	const SLOT_H: float       = 56.0
	const SLOT_GAP: float     = 6.0
	const PANEL_WIDTH: float  = 4.0 * SLOT_W + 3.0 * SLOT_GAP   # 4 slots + 3 gaps
	# Sits just below the mining bar (bottom_offset 156, height 40).
	# We sit 10 px below = 156 - 10 - SLOT_H from bottom.
	const BOTTOM_OFFSET: float = 36.0 + 110.0 + 10.0 + 40.0 + 10.0   # 206

	_quick_root = Control.new()
	_quick_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quick_root.anchor_left   = 0.5
	_quick_root.anchor_right  = 0.5
	_quick_root.anchor_top    = 1.0
	_quick_root.anchor_bottom = 1.0
	_quick_root.offset_left   = -(PANEL_WIDTH * 0.5)
	_quick_root.offset_right  =  (PANEL_WIDTH * 0.5)
	_quick_root.offset_top    = -(SLOT_H + BOTTOM_OFFSET)
	_quick_root.offset_bottom = -BOTTOM_OFFSET
	# Hidden by default — _process toggles to visible only when a
	# Player3D is in the tree. Without this initial hide the bar
	# flashes for a frame on the main menu before _process runs.
	_quick_root.visible = false
	add_child(_quick_root)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", int(SLOT_GAP))
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quick_root.add_child(hbox)

	for i in 4:
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(SLOT_W, SLOT_H)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Default (un-equipped) style — iron panel from the Voxelmark palette.
		var sb_idle := StyleBoxFlat.new()
		sb_idle.bg_color = Color(Colors.PANEL_IRON.r, Colors.PANEL_IRON.g, Colors.PANEL_IRON.b, 0.85)
		sb_idle.border_width_left = 1
		sb_idle.border_width_top = 1
		sb_idle.border_width_right = 1
		sb_idle.border_width_bottom = 1
		sb_idle.border_color = Colors.PANEL_IRON_EDGE
		panel.add_theme_stylebox_override("panel", sb_idle)
		hbox.add_child(panel)
		_quick_slot_panels.append(panel)

		# Slot number label (top-left) — gold pixel-font kbd chip.
		var num := Label.new()
		num.text = str(i + 1)
		num.position = Vector2(6, 4)
		UIStyles.apply_kbd_label(num)
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(num)

		# Item name label (centred).
		var name_lbl := Label.new()
		name_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		name_lbl.offset_top = 18  # below the number
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.text = "—"
		UIStyles.apply_body_label(name_lbl, 13)
		name_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		name_lbl.add_theme_constant_override("shadow_offset_x", 1)
		name_lbl.add_theme_constant_override("shadow_offset_y", 1)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(name_lbl)
		_quick_slot_labels.append(name_lbl)

		# Transparent button overlay — captures right-clicks for
		# Phase 2 rebind. Left-clicks fall through (we want the
		# player to click world objects, not the HUD).
		var btn := Button.new()
		btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn.flat = true
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		# bind the slot index to the handler so each button knows
		# which slot it represents.
		btn.gui_input.connect(_on_quick_slot_gui_input.bind(i))
		panel.add_child(btn)
		_quick_slot_buttons.append(btn)


func _on_quick_slot_gui_input(event: InputEvent, slot_idx: int) -> void:
	# Right-click → open the rebind picker (Phase 2). Left-clicks
	# fall through so the player can still click through the HUD
	# at world targets if they happen to be aiming behind the bar.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_open_quick_slot_rebind_picker(slot_idx)
			# Mark handled so the click doesn't propagate to world.
			get_viewport().set_input_as_handled()


func _open_quick_slot_rebind_picker(slot_idx: int) -> void:
	# Phase 2 stub. When the inventory grid UI lands this opens a
	# small list of all OWNED items; clicking one calls
	# InventoryManager.set_quick_slot(slot_idx, item_id). For now
	# log so the wiring is verifiable.
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Quick-slot %d right-click — rebind picker not built yet" % (slot_idx + 1))
	else:
		print("[HUDOverlay] Quick-slot %d right-clicked (rebind picker pending)" % (slot_idx + 1))


func _build_mining_bar() -> void:
	# Mining-progress bar — slim panel pinned bottom-centre, ABOVE the
	# main HP/endurance panel. Visible only while the player is
	# actively mining. Bar fill ramps 0..1 over the material's
	# mining_time_seconds; on completion it snaps to 100% for one
	# frame then hides on the next _clear_target.
	const PANEL_WIDTH: float    = 360.0
	const PANEL_HEIGHT: float   = 40.0
	# Sits above the existing HP/endurance panel (which has its own
	# 36 px bottom margin + 110 px height). Stack this just above with
	# a small gap.
	const BOTTOM_OFFSET: float  = 36.0 + 110.0 + 10.0  # = 156

	_mining_root = Control.new()
	_mining_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mining_root.anchor_left   = 0.5
	_mining_root.anchor_right  = 0.5
	_mining_root.anchor_top    = 1.0
	_mining_root.anchor_bottom = 1.0
	_mining_root.offset_left   = -(PANEL_WIDTH * 0.5)
	_mining_root.offset_right  =  (PANEL_WIDTH * 0.5)
	_mining_root.offset_top    = -(PANEL_HEIGHT + BOTTOM_OFFSET)
	_mining_root.offset_bottom = -BOTTOM_OFFSET
	_mining_root.visible = false  # hidden until first mining tick
	add_child(_mining_root)

	# Translucent dark backing panel — same style language as the
	# HP/endurance panel.
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(Colors.BG_NIGHT.r, Colors.BG_NIGHT.g, Colors.BG_NIGHT.b, 0.7)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mining_root.add_child(bg)

	# Horizontal layout: [label] [bar]
	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left   = 12
	hbox.offset_top    = 8
	hbox.offset_right  = -12
	hbox.offset_bottom = -8
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mining_root.add_child(hbox)

	_mining_label = Label.new()
	_mining_label.text = "MINING"
	_mining_label.custom_minimum_size = Vector2(120, 0)
	_mining_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIStyles.apply_subtitle_label(_mining_label)
	hbox.add_child(_mining_label)

	_mining_bar = ProgressBar.new()
	_mining_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mining_bar.custom_minimum_size = Vector2(0, 18)
	_mining_bar.min_value = 0.0
	_mining_bar.max_value = 1.0
	_mining_bar.value = 0.0
	_mining_bar.show_percentage = false
	# Fill colour — warm gold to read as "active effort", and
	# distinct from HP red and endurance green.
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Colors.GOLD
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2
	_mining_bar.add_theme_stylebox_override("fill", fill_style)
	# Empty (background) style for contrast.
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Colors.IRON_DEEP
	_mining_bar.add_theme_stylebox_override("background", bg_style)
	hbox.add_child(_mining_bar)


func _build_edit_mode_label() -> void:
	# Bottom-left "Volume: 1x1x1 [scroll]" readout. Visible when a
	# manual tool is equipped. Outlined text matches the FPS readout
	# style so it's readable on any background.
	_edit_volume_label = Label.new()
	_edit_volume_label.text = "Volume: 3x3x3  [scroll]"
	_edit_volume_label.add_theme_font_size_override("font_size", 18)
	_edit_volume_label.add_theme_color_override("font_color", Colors.INK)
	_edit_volume_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_edit_volume_label.add_theme_constant_override("outline_size", 4)
	_edit_volume_label.anchor_left = 0.0
	_edit_volume_label.anchor_right = 0.0
	_edit_volume_label.anchor_top = 1.0
	_edit_volume_label.anchor_bottom = 1.0
	_edit_volume_label.offset_left = 16
	_edit_volume_label.offset_right = 280
	_edit_volume_label.offset_top = -44
	_edit_volume_label.offset_bottom = -16
	_edit_volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_edit_volume_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_edit_volume_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edit_volume_label.visible = false
	add_child(_edit_volume_label)


func _build_ui() -> void:
	# --- Size / position constants — match Voxelmark HUD v1.html .vitals ---
	const PANEL_WIDTH: float    = 280.0   # Width of the vitals stack (mock spec).
	const PANEL_HEIGHT: float   = 100.0   # Height — fits status + 2 vital rows.
	const LEFT_MARGIN: float    = 24.0    # Pixels from the left edge of the screen.
	const BOTTOM_MARGIN: float  = 24.0    # Pixels from the bottom edge of the screen.
	const _LABEL_FONT: int      = 18      # "HP" / "END" label font size (kept for legacy).
	const _VALUE_FONT: int      = 16      # "80/100" value font size.
	const STATUS_FONT: int      = 16      # CROUCHING / EXHAUSTED font size.
	const BAR_HP_HEIGHT: float  = 22.0    # Height of the health bar (mock: 18, +4 for value label headroom).
	const BAR_END_HEIGHT: float = 22.0    # Height of the endurance bar.
	const ICON_SIZE: float      = 24.0    # Heart / lightning icon next to each bar (mock: 24×24).

	# Root control anchored to BOTTOM-LEFT of the viewport (mock layout).
	# mouse_filter = IGNORE so this purely-visual HUD never intercepts
	# clicks meant for menus or the world. The HUD only displays
	# HP/endurance/status; it doesn't take input.
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.anchor_left   = 0.0
	_root.anchor_right  = 0.0
	_root.anchor_top    = 1.0
	_root.anchor_bottom = 1.0
	_root.offset_left   = LEFT_MARGIN
	_root.offset_right  = LEFT_MARGIN + PANEL_WIDTH
	_root.offset_top    = -(PANEL_HEIGHT + BOTTOM_MARGIN)
	_root.offset_bottom = -BOTTOM_MARGIN
	add_child(_root)

	# Mock has no panel chrome behind the bottom-left vitals stack — the
	# bars carry their own iron borders. Skip the dark background that
	# the pre-2026-05-06 layout used for centre-mounted vitals.

	# Vertical layout inside the panel.
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   =  14
	vbox.offset_top    =  10
	vbox.offset_right  = -14
	vbox.offset_bottom = -10
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(vbox)

	# --- Status / chain row: status label on the left, chain count on the right ---
	# Status label = CROUCHING / EXHAUSTED / SWIMMING; chain label = "x2", "x3"
	# during a parry chain. Both sit in a horizontal row above the vitals.
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 8)
	vbox.add_child(status_row)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.custom_minimum_size = Vector2(0, STATUS_FONT + 4)
	UIStyles.apply_subtitle_label(_status_label)
	_status_label.add_theme_font_size_override("font_size", STATUS_FONT)
	_status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_status_label.add_theme_constant_override("shadow_offset_x", 1)
	_status_label.add_theme_constant_override("shadow_offset_y", 1)
	status_row.add_child(_status_label)

	_chain_count_label = Label.new()
	_chain_count_label.text = ""
	_chain_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_chain_count_label.add_theme_font_size_override("font_size", STATUS_FONT + 2)
	_chain_count_label.add_theme_color_override("font_color", Colors.MANA)
	_chain_count_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_chain_count_label.add_theme_constant_override("shadow_offset_x", 1)
	_chain_count_label.add_theme_constant_override("shadow_offset_y", 1)
	_chain_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_row.add_child(_chain_count_label)

	# --- Health row: [icon] [bar with overlaid 78/100] ---
	# Mock structure: small black-iron panel containing the glyph,
	# then the bar fills the rest with the value text overlaid right.
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	vbox.add_child(hp_row)

	var hp_icon := _build_vital_icon("♥", Colors.HP_BRIGHT, ICON_SIZE)
	hp_row.add_child(hp_icon)

	# Bar wrapper holds both the ProgressBar and the overlaid value label.
	var hp_bar_wrap := Control.new()
	hp_bar_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar_wrap.custom_minimum_size = Vector2(0, BAR_HP_HEIGHT)
	hp_bar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_child(hp_bar_wrap)

	_hp_bar = ProgressBar.new()
	_hp_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_bar.min_value = 0.0
	_hp_bar.max_value = 100.0
	_hp_bar.value     = 100.0
	_hp_bar.show_percentage = false
	_hp_bar.add_theme_stylebox_override("background", _vital_bar_bg_style())
	var hp_fill_style := StyleBoxFlat.new()
	hp_fill_style.bg_color = Colors.HP
	_hp_bar.add_theme_stylebox_override("fill", hp_fill_style)
	hp_bar_wrap.add_child(_hp_bar)

	_hp_value_label = Label.new()
	_hp_value_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_value_label.offset_right = -6
	_hp_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hp_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIStyles.apply_kbd_label(_hp_value_label)
	_hp_value_label.add_theme_color_override("font_color", Colors.INK)
	_hp_value_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hp_value_label.add_theme_constant_override("shadow_offset_x", 1)
	_hp_value_label.add_theme_constant_override("shadow_offset_y", 1)
	_hp_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar_wrap.add_child(_hp_value_label)

	# --- Endurance row: [icon] [bar with overlaid 50/100] ---
	var end_row := HBoxContainer.new()
	end_row.add_theme_constant_override("separation", 8)
	vbox.add_child(end_row)

	var end_icon := _build_vital_icon("⚡", Colors.STAM, ICON_SIZE)
	end_row.add_child(end_icon)

	var end_bar_wrap := Control.new()
	end_bar_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end_bar_wrap.custom_minimum_size = Vector2(0, BAR_END_HEIGHT)
	end_bar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_row.add_child(end_bar_wrap)

	_end_bar = ProgressBar.new()
	_end_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end_bar.min_value = 0.0
	_end_bar.max_value = 100.0
	_end_bar.value     = 100.0
	_end_bar.show_percentage = false
	_end_bar.add_theme_stylebox_override("background", _vital_bar_bg_style())
	var end_fill_style := StyleBoxFlat.new()
	end_fill_style.bg_color = Colors.STAM
	_end_bar.add_theme_stylebox_override("fill", end_fill_style)
	end_bar_wrap.add_child(_end_bar)

	_end_value_label = Label.new()
	_end_value_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end_value_label.offset_right = -6
	_end_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_end_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIStyles.apply_kbd_label(_end_value_label)
	_end_value_label.add_theme_color_override("font_color", Colors.INK)
	_end_value_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_end_value_label.add_theme_constant_override("shadow_offset_x", 1)
	_end_value_label.add_theme_constant_override("shadow_offset_y", 1)
	_end_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_bar_wrap.add_child(_end_value_label)


# Helper — black-iron panel containing a unicode glyph in `tint`.
# Match the .vital-icon spec from Voxelmark HUD v1.html: 24×24 black,
# 2 px black border, iron-edge inset.
func _build_vital_icon(glyph: String, tint: Color, sz: float) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(sz, sz)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.BLACK
	sb.border_color = Color.BLACK
	sb.set_border_width_all(2)
	sb.set_content_margin_all(0)
	# Inset 1 px iron-edge "rim" — emulate the box-shadow inset 1 px from
	# the mock by tinting the border's outer ring brighter.
	sb.border_color = Colors.PANEL_IRON_EDGE
	panel.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = glyph
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", tint)
	lbl.add_theme_font_size_override("font_size", int(sz * 0.7))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)
	return panel


# Helper — shared StyleBox for the bar BACKGROUND (the empty track).
# Matches .vital-bar in Voxelmark HUD v1.html: black fill, 2 px black
# border, inset iron-edge rim.
func _vital_bar_bg_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.03, 0.02, 1.0)
	sb.border_color = Color.BLACK
	sb.set_border_width_all(2)
	return sb


# =============================================================
# CHROME — crosshair / compass / clock / tooltip / pulses
# =============================================================
# Each subtree builds in _ready and refreshes every frame in
# _process via a dedicated _refresh_* call. None of them take input —
# they're all read-only HUD chrome — so every Control inside has
# mouse_filter = IGNORE.

# --- Crosshair ----------------------------------------------------
# 18×18 cross in INK at screen centre. Two thin Controls drawn on a
# wrapper that's anchored to the viewport centre.
func _build_crosshair() -> void:
	const CROSS_SIZE: float = 18.0
	const ARM_THICK: float = 2.0
	_crosshair = Control.new()
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.anchor_left   = 0.5
	_crosshair.anchor_right  = 0.5
	_crosshair.anchor_top    = 0.5
	_crosshair.anchor_bottom = 0.5
	_crosshair.offset_left   = -(CROSS_SIZE * 0.5)
	_crosshair.offset_right  =  (CROSS_SIZE * 0.5)
	_crosshair.offset_top    = -(CROSS_SIZE * 0.5)
	_crosshair.offset_bottom =  (CROSS_SIZE * 0.5)
	add_child(_crosshair)
	# Vertical arm.
	var v_arm := ColorRect.new()
	v_arm.color = Colors.INK
	v_arm.anchor_left = 0.5
	v_arm.anchor_right = 0.5
	v_arm.offset_left = -(ARM_THICK * 0.5)
	v_arm.offset_right = (ARM_THICK * 0.5)
	v_arm.offset_top = 0.0
	v_arm.offset_bottom = CROSS_SIZE
	v_arm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.add_child(v_arm)
	# Horizontal arm.
	var h_arm := ColorRect.new()
	h_arm.color = Colors.INK
	h_arm.anchor_top = 0.5
	h_arm.anchor_bottom = 0.5
	h_arm.offset_top = -(ARM_THICK * 0.5)
	h_arm.offset_bottom = (ARM_THICK * 0.5)
	h_arm.offset_left = 0.0
	h_arm.offset_right = CROSS_SIZE
	h_arm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.add_child(h_arm)


# --- Compass ------------------------------------------------------
# Iron-bordered 340×28 strip at top-centre with rotating cardinal
# markers + a fixed red needle. Cardinal letters / degree marks are
# custom-drawn so we can scroll them in screen space as the player
# rotates without rebuilding the label tree every frame.
const COMPASS_W: float = 340.0
const COMPASS_H: float = 28.0
const COMPASS_PX_PER_DEG: float = COMPASS_W / 90.0   # 3.78 px per degree of heading

func _build_compass() -> void:
	_compass_root = Control.new()
	_compass_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass_root.anchor_left   = 0.5
	_compass_root.anchor_right  = 0.5
	_compass_root.anchor_top    = 0.0
	_compass_root.anchor_bottom = 0.0
	_compass_root.offset_left   = -(COMPASS_W * 0.5)
	_compass_root.offset_right  =  (COMPASS_W * 0.5)
	_compass_root.offset_top    = 18.0
	_compass_root.offset_bottom = 18.0 + COMPASS_H + 24.0   # strip + coord label below
	add_child(_compass_root)

	# Strip — iron panel.
	_compass_strip = Panel.new()
	_compass_strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_compass_strip.offset_bottom = COMPASS_H
	_compass_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var strip_sb := StyleBoxFlat.new()
	strip_sb.bg_color = Colors.PANEL_IRON
	strip_sb.border_color = Color.BLACK
	strip_sb.set_border_width_all(2)
	_compass_strip.add_theme_stylebox_override("panel", strip_sb)
	_compass_root.add_child(_compass_strip)

	# Custom-drawn ticks/labels — scrolled by adjusting an offset stored
	# on the Control via metadata, then drawn in _draw via heading.
	_compass_ticks = Control.new()
	_compass_ticks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_compass_ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass_ticks.set_meta("heading_deg", 0.0)
	_compass_ticks.draw.connect(_draw_compass)
	_compass_strip.add_child(_compass_ticks)

	# Red needle at strip centre.
	_compass_needle = ColorRect.new()
	_compass_needle.color = Colors.HP
	_compass_needle.anchor_left = 0.5
	_compass_needle.anchor_right = 0.5
	_compass_needle.offset_left = -1.0
	_compass_needle.offset_right = 1.0
	_compass_needle.offset_top = 0.0
	_compass_needle.offset_bottom = COMPASS_H
	_compass_needle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass_strip.add_child(_compass_needle)

	# Coord label below the strip.
	_compass_coord_label = Label.new()
	_compass_coord_label.text = "X 0  Y 0  Z 0"
	_compass_coord_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_compass_coord_label.offset_top = COMPASS_H + 6.0
	_compass_coord_label.offset_bottom = COMPASS_H + 6.0 + 14.0
	_compass_coord_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyles.apply_kbd_label(_compass_coord_label)
	_compass_coord_label.add_theme_color_override("font_color", Colors.INK_MUTE)
	_compass_coord_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_compass_coord_label.add_theme_constant_override("shadow_offset_x", 1)
	_compass_coord_label.add_theme_constant_override("shadow_offset_y", 1)
	_compass_coord_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass_root.add_child(_compass_coord_label)


# Custom draw — every 30° draw a tick, every 90° draw a cardinal
# letter (N/E/S/W). Heading 0 = north; cardinal sits dead-centre when
# the player faces it.
func _draw_compass() -> void:
	if _compass_ticks == null:
		return
	var heading: float = _compass_ticks.get_meta("heading_deg", 0.0)
	var w: float = _compass_ticks.size.x
	var h: float = _compass_ticks.size.y
	if w <= 0.0:
		return
	var centre_x: float = w * 0.5
	# Draw ticks every 30°. The on-strip x of degree d is
	#   centre_x + (d - heading) * px_per_deg.
	# Heading wraps at 360 so we draw ticks for d = heading±60 around.
	const CARDINALS := { 0: "N", 90: "E", 180: "S", 270: "W" }
	for tick in range(0, 360, 30):
		# Find the smallest signed delta wrap [-180, 180].
		var delta: float = wrapf(float(tick) - heading, -180.0, 180.0)
		var x: float = centre_x + delta * COMPASS_PX_PER_DEG
		if x < -32.0 or x > w + 32.0:
			continue
		# Tick mark.
		var col: Color = Colors.INK_MUTE
		if CARDINALS.has(tick):
			col = Colors.GOLD
		_compass_ticks.draw_rect(Rect2(x - 0.5, h - 9.0, 1.0, 8.0), col, true)
		# Label — cardinals get a bigger gold letter, intermediate
		# 30° marks get a small grey degree number.
		if CARDINALS.has(tick):
			var glyph: String = CARDINALS[tick]
			var f: Font = ThemeDB.fallback_font
			var fs: int = 11
			var serif := UIStyles.font_serif()
			if serif:
				f = serif
				fs = 14
			var sz: Vector2 = f.get_string_size(glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
			_compass_ticks.draw_string(f, Vector2(x - sz.x * 0.5, 13.0),
				glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Colors.GOLD)
		else:
			var num: String = str(tick)
			var f2: Font = ThemeDB.fallback_font
			var fs2: int = 9
			var sz2: Vector2 = f2.get_string_size(num, HORIZONTAL_ALIGNMENT_CENTER, -1, fs2)
			_compass_ticks.draw_string(f2, Vector2(x - sz2.x * 0.5, 12.0),
				num, HORIZONTAL_ALIGNMENT_CENTER, -1, fs2, Colors.INK_DIM)


# Push the player's current heading + position into the compass.
# Heading: 0 = north (-Z), 90 = east (+X), 180 = south (+Z), 270 = west (-X).
func _refresh_compass(player: Node) -> void:
	if _compass_ticks == null or player == null:
		return
	# Bail if the player is mid-removal from the SceneTree — `global_position`
	# pushes "is_inside_tree() is true" errors when the node has been
	# detached but not yet freed (happens during scene transitions when
	# the destination scene root is reparented). Cheap is_inside_tree()
	# check covers it.
	if not player.is_inside_tree():
		return
	# Player3D is a CharacterBody3D — its forward direction is
	# -basis.z. Project onto XZ and convert to compass degrees.
	var forward: Vector3 = -player.transform.basis.z
	var heading_rad: float = atan2(forward.x, -forward.z)
	# atan2(x, -z): 0 when forward = -Z (north); +π/2 when forward = +X (east).
	var heading_deg: float = rad_to_deg(heading_rad)
	if heading_deg < 0.0:
		heading_deg += 360.0
	_compass_ticks.set_meta("heading_deg", heading_deg)
	_compass_ticks.queue_redraw()
	# Coord label.
	if _compass_coord_label != null:
		var p: Vector3 = player.global_position
		_compass_coord_label.text = "X %d  Y %d  Z %d" % [int(p.x), int(p.y), int(p.z)]


# --- Clock / day / biome ----------------------------------------
# Top-right strip: "DAY 47" in serif gold + "19:42" in mono ink, with
# biome / time-of-day band beneath. Driven by WorldClock autoload.
func _build_clock() -> void:
	_clock_root = Control.new()
	_clock_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_root.anchor_left = 1.0
	_clock_root.anchor_right = 1.0
	_clock_root.anchor_top = 0.0
	_clock_root.anchor_bottom = 0.0
	_clock_root.offset_left = -260.0   # 240 strip + 20 right margin
	_clock_root.offset_right = -18.0
	_clock_root.offset_top = 18.0
	_clock_root.offset_bottom = 70.0
	add_child(_clock_root)

	# Iron strip.
	var day_strip := Panel.new()
	day_strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	day_strip.offset_bottom = 26.0
	day_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ds_sb := StyleBoxFlat.new()
	ds_sb.bg_color = Colors.PANEL_IRON
	ds_sb.border_color = Color.BLACK
	ds_sb.set_border_width_all(2)
	day_strip.add_theme_stylebox_override("panel", ds_sb)
	_clock_root.add_child(day_strip)

	# HBox inside the strip — day | sep | time.
	var ds_hbox := HBoxContainer.new()
	ds_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ds_hbox.offset_left = 10.0
	ds_hbox.offset_right = -10.0
	ds_hbox.add_theme_constant_override("separation", 10)
	ds_hbox.alignment = BoxContainer.ALIGNMENT_END
	ds_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	day_strip.add_child(ds_hbox)

	_clock_day_label = Label.new()
	_clock_day_label.text = "DAY 1"
	_clock_day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIStyles.apply_subtitle_label(_clock_day_label)
	_clock_day_label.add_theme_font_size_override("font_size", 13)
	ds_hbox.add_child(_clock_day_label)

	var sep := ColorRect.new()
	sep.color = Colors.IRON
	sep.custom_minimum_size = Vector2(1, 14)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ds_hbox.add_child(sep)

	_clock_time_label = Label.new()
	_clock_time_label.text = "08:00"
	_clock_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIStyles.apply_kbd_label(_clock_time_label)
	_clock_time_label.add_theme_color_override("font_color", Colors.INK)
	_clock_time_label.add_theme_font_size_override("font_size", 10)
	ds_hbox.add_child(_clock_time_label)

	# Biome / time-of-day band beneath.
	_clock_biome_label = Label.new()
	_clock_biome_label.text = ""
	_clock_biome_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_clock_biome_label.offset_top = 32.0
	_clock_biome_label.offset_bottom = 46.0
	_clock_biome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UIStyles.apply_kbd_label(_clock_biome_label)
	_clock_biome_label.add_theme_color_override("font_color", Colors.INK_DIM)
	_clock_biome_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_clock_biome_label.add_theme_constant_override("shadow_offset_x", 1)
	_clock_biome_label.add_theme_constant_override("shadow_offset_y", 1)
	_clock_biome_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_root.add_child(_clock_biome_label)


# Read WorldClock state and push into the labels. Called every frame
# from _process. Cheap (3 string writes max) and idempotent.
func _refresh_clock() -> void:
	if _clock_day_label == null:
		return
	var wc := get_node_or_null("/root/WorldClock")
	if wc == null:
		return
	# WorldClock public vars: current_hour, current_minute, current_day.
	# Plus get_time_of_day_period() returns a period name (DAWN/MORNING/etc).
	var day: int = int(wc.get("current_day"))
	var hour: int = int(wc.get("current_hour"))
	var minute: int = int(wc.get("current_minute"))
	_clock_day_label.text = "DAY %d" % day
	_clock_time_label.text = "%02d:%02d" % [hour, minute]
	# Biome name isn't tracked yet (no zone/region tag in GameState).
	# Show the time-of-day period as a placeholder for the band line.
	var period: String = ""
	if wc.has_method("get_time_of_day_period"):
		period = String(wc.call("get_time_of_day_period")).to_upper()
	_clock_biome_label.text = "★ MIRA-THAL · " + period if period != "" else "★ MIRA-THAL"


# --- Hotbar item tooltip ----------------------------------------
# Floats above the quick-slot bar; shows the equipped item's name +
# meta line. Visible briefly after a quick-slot key press; otherwise
# hidden. Mock has it on hover, but the quick-slot bar has no
# pointer-hover events during gameplay (mouse is captured), so we
# trigger on equip-change instead.
func _build_hotbar_tooltip() -> void:
	_hotbar_tooltip = Panel.new()
	_hotbar_tooltip.custom_minimum_size = Vector2(180, 40)
	_hotbar_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchor bottom-centre, offset above the quick-slot bar.
	# Quick-slot bar sits 206 px from bottom (see _build_quick_slot_bar
	# BOTTOM_OFFSET). Tooltip floats just above it.
	const TOOLTIP_BOTTOM_OFFSET: float = 36.0 + 110.0 + 10.0 + 40.0 + 10.0 + 56.0 + 6.0
	_hotbar_tooltip.anchor_left = 0.5
	_hotbar_tooltip.anchor_right = 0.5
	_hotbar_tooltip.anchor_top = 1.0
	_hotbar_tooltip.anchor_bottom = 1.0
	_hotbar_tooltip.offset_left = -110.0
	_hotbar_tooltip.offset_right = 110.0
	_hotbar_tooltip.offset_top = -(TOOLTIP_BOTTOM_OFFSET + 40.0)
	_hotbar_tooltip.offset_bottom = -TOOLTIP_BOTTOM_OFFSET
	var sb := StyleBoxFlat.new()
	sb.bg_color = Colors.PANEL_OAK_2
	sb.border_color = Color.BLACK
	sb.set_border_width_all(2)
	sb.set_content_margin_all(6)
	_hotbar_tooltip.add_theme_stylebox_override("panel", sb)
	_hotbar_tooltip.modulate.a = 0.0
	_hotbar_tooltip.visible = false
	add_child(_hotbar_tooltip)

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hotbar_tooltip.add_child(v)

	_hotbar_tooltip_name = Label.new()
	_hotbar_tooltip_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyles.apply_subtitle_label(_hotbar_tooltip_name)
	_hotbar_tooltip_name.add_theme_font_size_override("font_size", 14)
	_hotbar_tooltip_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_hotbar_tooltip_name)

	_hotbar_tooltip_meta = Label.new()
	_hotbar_tooltip_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyles.apply_dim_label(_hotbar_tooltip_meta, 12)
	_hotbar_tooltip_meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_hotbar_tooltip_meta)


# Shows the tooltip for `seconds` seconds; auto-hides via tween.
# Called from _refresh_quick_slot_bar when the equipped item changes.
var _last_equipped_item: String = ""
var _tooltip_visible_until: float = -1.0
func _show_hotbar_tooltip(item_name: String, meta: String, seconds: float = 1.6) -> void:
	if _hotbar_tooltip == null:
		return
	_hotbar_tooltip_name.text = item_name
	_hotbar_tooltip_meta.text = meta
	_hotbar_tooltip.visible = true
	_hotbar_tooltip_alpha_target = 1.0
	_tooltip_visible_until = Time.get_ticks_msec() / 1000.0 + seconds


func _refresh_hotbar_tooltip(_delta: float) -> void:
	if _hotbar_tooltip == null:
		return
	# Fade target follows visibility window.
	var now: float = Time.get_ticks_msec() / 1000.0
	if _tooltip_visible_until > 0.0 and now > _tooltip_visible_until:
		_hotbar_tooltip_alpha_target = 0.0
	# Smooth alpha lerp.
	var cur: float = _hotbar_tooltip.modulate.a
	var goal: float = _hotbar_tooltip_alpha_target
	if absf(cur - goal) > 0.005:
		_hotbar_tooltip.modulate.a = lerp(cur, goal, 0.18)
	else:
		_hotbar_tooltip.modulate.a = goal
		if goal == 0.0:
			_hotbar_tooltip.visible = false


# --- Damage pulse + low-HP pulse --------------------------------
# Both are full-screen ColorRects that sit BEHIND every other HUD
# element (added in _ready before any other build). damage_pulse is
# a one-shot 0.55→0 alpha tween triggered when health drops; low_hp
# is a sin-driven heartbeat alpha while HP < 25 % of max.
func _build_damage_pulse() -> void:
	_damage_pulse = ColorRect.new()
	_damage_pulse.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_damage_pulse.color = Color(Colors.HP.r, Colors.HP.g, Colors.HP.b, 0.0)
	_damage_pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_damage_pulse)

func _build_low_hp_pulse() -> void:
	_low_hp_pulse = ColorRect.new()
	_low_hp_pulse.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_low_hp_pulse.color = Color(Colors.HP_DEEP.r, Colors.HP_DEEP.g, Colors.HP_DEEP.b, 0.0)
	_low_hp_pulse.visible = false
	_low_hp_pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_low_hp_pulse)


# Trigger a one-shot damage flash. Tween fades it out so the next
# refresh tick clears it cleanly.
func _trigger_damage_pulse() -> void:
	if _damage_pulse == null:
		return
	# Reset alpha; tween down to 0 over 0.35 s.
	_damage_pulse.color = Color(Colors.HP.r, Colors.HP.g, Colors.HP.b, 0.55)
	var t := create_tween()
	t.tween_property(_damage_pulse, "color:a", 0.0, 0.35)


# Slow heartbeat. Active when player.health < 25 % of max_health.
func _refresh_low_hp_pulse(player: Node, delta: float) -> void:
	if _low_hp_pulse == null:
		return
	if player == null:
		_low_hp_pulse.visible = false
		return
	var max_hp: float = float(player.max_health) if "max_health" in player else 100.0
	var cur_hp: float = float(player.health) if "health" in player else max_hp
	if max_hp <= 0.0:
		_low_hp_pulse.visible = false
		return
	var threshold: float = max_hp * 0.25
	if cur_hp <= 0.0 or cur_hp > threshold:
		_low_hp_pulse.visible = false
		return
	# Heartbeat: 1.4 s cycle, alpha 0.25 → 0.55.
	_low_hp_pulse.visible = true
	_low_hp_pulse_t += delta
	var phase: float = sin((_low_hp_pulse_t / 1.4) * TAU) * 0.5 + 0.5  # [0, 1]
	var alpha: float = lerp(0.25, 0.55, phase)
	_low_hp_pulse.color = Color(Colors.HP_DEEP.r, Colors.HP_DEEP.g, Colors.HP_DEEP.b, alpha)


# Detect health drops and trigger the damage pulse. Called from
# _process every frame; idempotent on no-change.
func _refresh_damage_pulse(player: Node) -> void:
	if player == null:
		_last_known_health = -1.0
		return
	var hp: float = float(player.health) if "health" in player else 0.0
	if _last_known_health < 0.0:
		_last_known_health = hp
		return
	if hp < _last_known_health - 0.5:
		_trigger_damage_pulse()
	_last_known_health = hp


# =============================================================
# UPDATE LOOP
# =============================================================

func _process(delta: float) -> void:
	# Dev-scene guard — when running BakeWorld / CopperIslesTest / any
	# scene that joins the "dev_scene" group, hide every HUD element so
	# the developer's view of the test scene isn't cluttered with HP /
	# stamina / compass / clock / FPS / volume chrome. Driven by
	# GameState.is_dev_scene() (group membership check). The check is
	# cheap (a single get_tree() + group lookup) so per-frame is fine.
	if get_node_or_null("/root/GameState") and GameState.is_dev_scene():
		_hide_all_chrome()
		return

	# DIAGNOSTIC — aggregate frame spikes over a 1-second window and
	# emit ONE summary line per second along with engine-wide stats.
	# Previous impl printed per-frame whenever delta > 50 ms; at sub-10
	# FPS that fired hundreds of times/sec and each print to Godot's
	# Output panel costs 0.5–2 ms, contributing to the very stutter it
	# was trying to measure. Aggregating gives us per-second visibility
	# without the feedback loop.
	#
	# Stats included in the summary:
	#   spikes  — count of frames with delta > 50 ms in the last second
	#   worst   — peak frame time (ms) in the last second
	#   draws   — Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME (last frame)
	#   prims   — Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME (last frame)
	#   bodies  — Performance.PHYSICS_3D_ACTIVE_OBJECTS
	#   nodes   — Performance.OBJECT_NODE_COUNT
	# Read these to triangulate the dominant cost: high `draws` means
	# rendering, high `bodies` means physics/collision rebuild, high
	# `nodes` means scene-tree churn. Flip PERF_DIAG to false once the
	# investigation lands.
	if PERF_DIAG:
		_perf_diag_tick(delta)

	# Profiler autoload — roll per-frame samples into rolling-window stats
	# and the spike ring buffer. Cheap (clears a dict) but must run every
	# frame regardless of PERF_DIAG so the F3 overlay stays live.
	var prof := get_node_or_null("/root/Profiler")
	if prof != null:
		prof.frame_finalize()

	# Quick-slot number-key dispatch. Polls the four input actions
	# directly each frame; on just_pressed we equip that slot's bound
	# item. Polling (not _input event handling) keeps it simple and
	# robust against Dialogic / GUI input absorption.
	_process_quick_slot_input()

	var player := _find_player()

	# Clean-screenshot mode (DebugOverlay → COMMANDS → TOGGLE CLEAN
	# SCREENSHOT). Same hide block as "no player in scene" — kills HP /
	# endurance / quick-slot / compass / clock / crosshair / mining /
	# tooltip / low-HP-pulse so the captured frame has no UI chrome.
	# The F1 dev panel itself isn't auto-hidden — close it manually
	# with F1 before the shot.
	var dbg := get_node_or_null("/root/DebugOverlay")
	var clean_shot: bool = (dbg != null and "clean_screenshot_enabled" in dbg
		and dbg.clean_screenshot_enabled)

	if player == null or clean_shot:
		_root.visible = false
		if _mining_root != null:
			_mining_root.visible = false
		# Quick-slot bar is gameplay-only too — hide on the main menu,
		# settings, load picker, and any other scene without a player.
		if _quick_root != null:
			_quick_root.visible = false
		# Hide the rest of the gameplay-only chrome.
		if _crosshair != null:
			_crosshair.visible = false
		if _compass_root != null:
			_compass_root.visible = false
		if _clock_root != null:
			_clock_root.visible = false
		if _hotbar_tooltip != null:
			_hotbar_tooltip.visible = false
		if _low_hp_pulse != null:
			_low_hp_pulse.visible = false
		_last_known_health = -1.0
		return

	_root.visible = true
	if _crosshair != null:
		_crosshair.visible = true
	if _compass_root != null:
		_compass_root.visible = true
	if _clock_root != null:
		_clock_root.visible = true

	# Read values from the player and push them into the bars.
	_hp_bar.max_value      = player.max_health
	_hp_bar.value          = player.health
	_hp_value_label.text   = "%d / %d" % [int(player.health), int(player.max_health)]

	_end_bar.max_value     = player.max_endurance
	_end_bar.value         = player.endurance
	_end_value_label.text  = "%d / %d" % [int(player.endurance), int(player.max_endurance)]

	# Status label: "CROUCHING", "EXHAUSTED", or blank.
	_status_label.text = player.status_text

	# Parry chain count (Phase 6, directional melee v1). Read from
	# MeleeHandler.parry_chain.current_chain_count if the handler is
	# attached. Shown as "x2", "x3" once a chain is active; hidden
	# otherwise so it doesn't add noise during non-combat play.
	if _chain_count_label != null:
		var melee: Node = player.get_node_or_null("MeleeHandler")
		var chain: int = 0
		if melee != null:
			var pc: Variant = melee.get("parry_chain")
			if pc != null:
				chain = int(pc.current_chain_count)
		if chain >= 2:
			_chain_count_label.text = "x%d" % chain
		else:
			_chain_count_label.text = ""

	# Voxelmark HUD chrome refreshers.
	_refresh_compass(player)
	_refresh_clock()
	_refresh_damage_pulse(player)
	_refresh_low_hp_pulse(player, delta)
	_refresh_hotbar_tooltip(delta)

	# Mining-progress bar — only visible while EditToolHandler reports
	# active mining. EditToolHandler is a child of Player3D
	# (scenes/Player3D.tscn) and exposes mining_active / mining_progress
	# / mining_material_label as plain vars updated each tick.
	var edit_tool: Node = player.get_node_or_null("EditToolHandler")
	if _mining_root != null:
		if edit_tool != null and "mining_active" in edit_tool and edit_tool.mining_active:
			_mining_root.visible = true
			_mining_bar.value = edit_tool.mining_progress
			# Display "MINING grass" / "MINING stone" so the player
			# sees what they're hitting and can swap tools if it's
			# the wrong material.
			var mat_name: String = edit_tool.mining_material_label if "mining_material_label" in edit_tool else ""
			if mat_name == "":
				_mining_label.text = "MINING"
			else:
				_mining_label.text = "MINING " + mat_name.to_upper()
		else:
			_mining_root.visible = false

	# Bottom-left volume indicator — only visible when a manual tool
	# (pickaxe / shovel / axe) is equipped, since the scroll-cycle
	# only matters then.
	if _edit_volume_label != null:
		var show_volume: bool = false
		var volume_size: int = 3
		var preset_name: String = ""
		if edit_tool != null and "carve_volume_size" in edit_tool \
				and get_node_or_null("/root/InventoryManager"):
			var equipped: String = InventoryManager.get_equipped("weapon")
			# Manual-tool list mirrors EditToolHandler.TOOL_SUB_SKILLS keys.
			# Keep in sync if new manual tools land.
			if equipped in ["iron_pickaxe", "iron_shovel", "iron_axe"]:
				show_volume = true
				volume_size = int(edit_tool.carve_volume_size)
				# Preset name (Small / Medium / Full) from the handler's
				# PRESET_NAMES map, keyed by its current carve_preset. Guard
				# both members so an older handler build still falls back to
				# a bare size-only readout instead of erroring.
				if "carve_preset" in edit_tool and "PRESET_NAMES" in edit_tool:
					preset_name = str(edit_tool.PRESET_NAMES.get(edit_tool.carve_preset, ""))
		_edit_volume_label.visible = show_volume
		if show_volume:
			# "Volume: Medium 3x3x3  [scroll]" — preset name first so the
			# player reads the intent, then the exact size in voxels.
			if preset_name != "":
				_edit_volume_label.text = "Volume: %s %dx%dx%d  [scroll]" % [
					preset_name, volume_size, volume_size, volume_size,
				]
			else:
				_edit_volume_label.text = "Volume: %dx%dx%d  [scroll]" % [
					volume_size, volume_size, volume_size,
				]

	# Quick-slot bar visible only during gameplay (player in tree).
	if _quick_root != null:
		_quick_root.visible = true
	# Refresh the quick-slot bar's text + highlight based on the
	# current InventoryManager state. Cheap (4 label writes per frame).
	_refresh_quick_slot_bar()


func _process_quick_slot_input() -> void:
	# Number keys 1-4 equip the bound item. Only fires when the mouse
	# is captured (gameplay), so the keys don't trigger while the
	# player is interacting with menus.
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if not get_node_or_null("/root/InventoryManager"):
		return
	const ACTIONS: Array[String] = ["quick_slot_1", "quick_slot_2", "quick_slot_3", "quick_slot_4"]
	for i in ACTIONS.size():
		if Input.is_action_just_pressed(ACTIONS[i]):
			InventoryManager.equip_quick_slot(i)


func _refresh_quick_slot_bar() -> void:
	# Sync the four panels' text + highlight to the current
	# InventoryManager bindings + equipped weapon. Called every frame
	# from _process — cheap (4 string writes max), idempotent.
	if _quick_slot_panels.is_empty():
		return
	if not get_node_or_null("/root/InventoryManager"):
		return
	var equipped: String = InventoryManager.get_equipped("weapon")
	# Surface the floating tooltip when the equipped item changes (a
	# quick-slot key was just pressed, or a slot rebind happened mid-game).
	if equipped != _last_equipped_item:
		_last_equipped_item = equipped
		if equipped != "" and InventoryManager.ITEM_REGISTRY.has(equipped):
			var entry: Dictionary = InventoryManager.ITEM_REGISTRY[equipped]
			var display: String = entry.get("name", equipped)
			# Compose a meta line — type + tier if present, falls back to type.
			var meta_bits: Array[String] = []
			if entry.has("type"):
				meta_bits.append(String(entry["type"]).capitalize())
			if entry.has("tier"):
				meta_bits.append("Tier %s" % str(entry["tier"]))
			_show_hotbar_tooltip(display, " · ".join(meta_bits))
	for i in _quick_slot_panels.size():
		var item_id: String = InventoryManager.get_quick_slot(i)
		# Display name from the registry, with quantity for stackables.
		var label_text: String = "—"
		if item_id != "":
			# Local "display_name" rather than "name" — `name` is the
			# Node base-class property; using it as a local shadows it.
			var display_name: String = item_id
			if InventoryManager.ITEM_REGISTRY.has(item_id):
				display_name = InventoryManager.ITEM_REGISTRY[item_id].get("name", item_id)
			# Show count for stackables (throwables, materials) — EXCEPT
			# powder charges, which read as a plain "Powder Charges" label
			# (designer call 2026-05-20: the ×N count cluttered the box).
			if item_id == "powder_charge":
				label_text = "Powder Charges"
			else:
				var count: int = InventoryManager.get_quantity(item_id)
				if count > 1:
					label_text = "%s ×%d" % [display_name, count]
				else:
					label_text = display_name
		_quick_slot_labels[i].text = label_text

		# Highlight when this slot's item is the currently-equipped weapon.
		var is_equipped: bool = (item_id != "" and item_id == equipped)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(Colors.PANEL_IRON.r, Colors.PANEL_IRON.g, Colors.PANEL_IRON.b, 0.85)
		sb.border_width_left = 2 if is_equipped else 1
		sb.border_width_top = 2 if is_equipped else 1
		sb.border_width_right = 2 if is_equipped else 1
		sb.border_width_bottom = 2 if is_equipped else 1
		sb.border_color = Colors.GOLD if is_equipped else Colors.PANEL_IRON_EDGE
		_quick_slot_panels[i].add_theme_stylebox_override("panel", sb)


# =============================================================
# PLAYER LOOKUP
# =============================================================

# Hide every HUD subtree at once. Used by the dev-scene guard in
# _process — keeps the test scenes uncluttered. Idempotent.
func _hide_all_chrome() -> void:
	if _root != null:
		_root.visible = false
	if _mining_root != null:
		_mining_root.visible = false
	if _quick_root != null:
		_quick_root.visible = false
	if _crosshair != null:
		_crosshair.visible = false
	if _compass_root != null:
		_compass_root.visible = false
	if _clock_root != null:
		_clock_root.visible = false
	if _hotbar_tooltip != null:
		_hotbar_tooltip.visible = false
	if _low_hp_pulse != null:
		_low_hp_pulse.visible = false
	if _edit_volume_label != null:
		_edit_volume_label.visible = false
	if _bark_overlay != null:
		_bark_overlay.visible = false
	if _damage_pulse != null:
		# Reset alpha — a damage event before entering the dev scene
		# could leave the pulse mid-tween.
		_damage_pulse.color = Color(Colors.HP.r, Colors.HP.g, Colors.HP.b, 0.0)


func _find_player() -> Node:
	# Use the cached reference if it's still valid.
	if is_instance_valid(_cached_player):
		return _cached_player

	# Search by group — Player3D.tscn adds itself to the "player" group.
	var players := get_tree().get_nodes_in_group("player")
	_cached_player = players[0] if not players.is_empty() else null
	return _cached_player


# =============================================================
# PERFORMANCE DIAGNOSTIC IMPLEMENTATION
# =============================================================

func profile_record(label: String, usec: int) -> void:
	# Called by other autoloads to report time spent in their _process /
	# _physics_process. Accumulates per second; _perf_diag_tick clears.
	#
	# As of 2026-05-12, this only feeds the always-on [PERF] log line.
	# The Profiler autoload is fed directly by each wrapper site (one
	# explicit prof.record call per wrap), categorized properly. The
	# old forwarder here (record(label, usec) → Profiler.record("OTHER",
	# label, usec)) was double-counting because every wrapper called
	# BOTH paths — so the Overview showed each system twice (once as
	# OTHER.X and once as PROPER.X with identical data). Dropping the
	# forwarder leaves single, categorized entries.
	_profile_buckets[label] = _profile_buckets.get(label, 0) + usec


func _perf_diag_tick(delta: float) -> void:
	# Per-frame: tally spikes. Per-second: emit one summary line with
	# spike count, worst frame, and engine-wide load indicators so the
	# user can correlate the cost with rendering / physics / scene-tree
	# pressure WITHOUT spamming Output every spike (see PERF_DIAG block
	# at top of file for rationale).
	var ms: float = delta * 1000.0
	if ms > PERF_DIAG_SPIKE_MS:
		_perf_spike_count += 1
		if ms > _perf_spike_max_ms:
			_perf_spike_max_ms = ms

	var now_msec: int = Time.get_ticks_msec()
	if _perf_window_start_msec == 0:
		_perf_window_start_msec = now_msec
		return
	if now_msec - _perf_window_start_msec < 1000:
		return

	# Window closed — emit summary and reset. Skip the print if nothing
	# eventful happened (zero spikes AND steady FPS) so an idle main
	# menu doesn't flood the log.
	var fps: int = int(Engine.get_frames_per_second())
	var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var vram_mb: int = int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024 * 1024))
	# Streaming-throughput probe (2026-05-25). Surface physics + render
	# object counts so a spike that the per-script attribution doesn't
	# explain has a chance of correlating with one of these. See the
	# matching commentary in Profiler.gd capture path.
	var phys_pairs: int = int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))
	var phys_active: int = int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	var render_objs: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	# Pull this second's worst spike's attribution AND Zylann snapshot
	# from the Profiler autoload so the [PERF] line shows what dominated
	# the spike (no opening the JSON for a quick glance).
	var spike_dump: String = _build_spike_dump()

	# Build the per-autoload "top contributors" string. Sort buckets
	# by accumulated usec descending and emit the top 3 in ms. Anything
	# below 1 ms is dropped — too noisy to print every second.
	var top_str: String = ""
	if not _profile_buckets.is_empty():
		var entries: Array = []
		for k in _profile_buckets.keys():
			entries.append([k, _profile_buckets[k]])
		entries.sort_custom(func(a, b): return a[1] > b[1])
		var parts: Array = []
		for i in range(mini(3, entries.size())):
			var bucket_ms: int = int(entries[i][1] / 1000)
			if bucket_ms < 1:
				continue
			parts.append("%s=%d" % [entries[i][0], bucket_ms])
		if not parts.is_empty():
			top_str = " | top: " + " ".join(parts)
		_profile_buckets.clear()

	# Viewer telemetry summary (added 2026-05-26). Compact one-line read
	# of every VoxelViewer's lead/alignment vs the player. Surfaced every
	# second alongside the [PERF] line so a misaligned viewer (today's
	# bug) is impossible to miss going forward.
	var viewer_dump: String = _build_viewer_dump()

	if _perf_spike_count > 0 or fps < 50:
		print("[PERF] fps=%d spikes=%d worst=%d ms%s | draws=%d prims=%d render_objs=%d phys_pairs=%d phys_active=%d nodes=%d orphans=%d vram=%d MB%s" % [
			fps, _perf_spike_count, int(round(_perf_spike_max_ms)),
			top_str,
			draws, prims, render_objs, phys_pairs, phys_active, nodes, orphans, vram_mb,
			spike_dump,
		])
		# Print viewer dump on the same beat as [PERF] so the two
		# correlate cleanly in the Output panel. Print on its own line —
		# the [PERF] line is already long enough to wrap.
		if viewer_dump != "":
			print(viewer_dump)

	_perf_spike_count = 0
	_perf_spike_max_ms = 0.0
	_perf_window_start_msec = now_msec


# Pull the Profiler autoload's last spike, sort its attribution buckets,
# and format a one-line " | spike@<frame>: <bucket>=<ms> <bucket>=<ms>
# z.detect=<ms> z.mesh=<ms>" suffix for the [PERF] line. Returns "" when
# the Profiler isn't loaded, or when no spike exists in the last 2 s of
# the ring buffer (the Profiler clears _last_spike each capture).
#
# Why surface this in [PERF] instead of only in the F3 overlay: the user's
# routine investigation flow is to paste the Output panel + a JSON path
# into the chat. Having the per-second top-attributor of THIS second's
# worst spike inline means we don't need to ask "which frame should I
# look at." It also gives us Zylann main-thread budgets (detect_us /
# mesh_us) without requiring the F3 overlay to be open.
func _build_viewer_dump() -> String:
	# Pull viewer telemetry from Profiler.read_viewer_telemetry() and
	# format one line per viewer. Returns "" when the Profiler is missing
	# or no viewers are present (loading screens, dev scenes). The
	# alignment dot product is what would have caught today's bug —
	# anything ≤ 0 while the player is actually moving means the viewer
	# is BEHIND or PERPENDICULAR to motion. Show "—" when idle so we
	# don't flag a meaningless 0.0 as a problem.
	var p: Node = get_node_or_null("/root/Profiler")
	if p == null or not p.has_method("read_viewer_telemetry"):
		return ""
	var vt: Dictionary = p.call("read_viewer_telemetry")
	var viewers: Array = vt.get("viewers", [])
	if viewers.is_empty():
		return ""
	var p_vel: Vector3 = vt.get("player_velocity", Vector3.ZERO)
	var moving: bool = Vector3(p_vel.x, 0.0, p_vel.z).length() > 0.5
	var parts: Array = []
	for v in viewers:
		var path: String = v["path"]
		# Shorten "/root/World3D/Player3D/VoxelViewer" -> "VoxelViewer"
		# (or the leaf node name) so the line stays scannable.
		var name: String = path.get_file() if path.contains("/") else path
		var lead_m: float = v["distance_to_player_m"]
		var vd: int = v["view_distance"]
		var align: float = v["alignment"]
		var align_str: String = "—" if not moving else ("%+.2f" % align)
		# Flag a misaligned viewer with a "!" so it pops in the log scroll.
		# Threshold: dot < 0.3 while moving means viewer is meaningfully
		# off-axis from motion (the bug fixed in a76d3ae produced -1.0).
		var flag: String = ""
		if moving and align < 0.3:
			flag = "  !MISALIGNED"
		parts.append("%s(lead=%.1fm vd=%d align=%s)%s" % [
			name, lead_m, vd, align_str, flag,
		])
	return "[VIEWERS] " + "  ".join(parts)


func _build_spike_dump() -> String:
	var p: Node = get_node_or_null("/root/Profiler")
	if p == null or not p.has_method("get_last_spike"):
		return ""
	var spike: Dictionary = p.call("get_last_spike")
	if spike.is_empty():
		return ""
	# Only surface spikes that occurred recently — Profiler ring is
	# 2 s @ 60 fps, but the last_spike dict has no timestamp. Skip if
	# this exact frame index has already been printed once (the spike
	# stays in _last_spike until a worse one comes along).
	var spike_frame: int = int(spike.get("frame", -1))
	if spike_frame == _perf_last_logged_spike_frame:
		return ""
	_perf_last_logged_spike_frame = spike_frame
	var attr: Dictionary = spike.get("attribution", {})
	if attr.is_empty():
		return " | spike@%d (unattributed)" % spike_frame
	var entries: Array = []
	for k in attr.keys():
		entries.append([k, attr[k]])
	entries.sort_custom(func(a, b): return a[1] > b[1])
	var parts: Array = []
	for i in range(mini(2, entries.size())):
		var us: int = entries[i][1]
		if us < 500:
			continue
		parts.append("%s=%.1fms" % [entries[i][0], us / 1000.0])
	# If the Profiler has a live VoxelLodTerrain reference, pull its
	# stats too. Same Variant call the capture uses; cost ~1 µs.
	if p.has_method("_read_zylann_stats"):
		var z: Dictionary = p.call("_read_zylann_stats")
		if not z.is_empty():
			var z_detect_ms: float = int(z.get("detect_us", 0)) / 1000.0
			var z_mesh_ms: float = int(z.get("mesh_us", 0)) / 1000.0
			if z_detect_ms >= 1.0:
				parts.append("z.detect=%.1fms" % z_detect_ms)
			if z_mesh_ms >= 1.0:
				parts.append("z.mesh=%.1fms" % z_mesh_ms)
	if parts.is_empty():
		return ""
	return " | spike@%d: %s" % [spike_frame, " ".join(parts)]
