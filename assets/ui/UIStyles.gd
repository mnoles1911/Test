class_name UIStyles
extends RefCounted

# UI style factory — static methods that produce StyleBox/FontVariation
# resources matching the Voxelmark CSS spec in assets/ui/css/menus_shared.css.
#
# Why a helper class instead of theme.tres: every UI scene in this project is
# built programmatically (HUDOverlay, PauseMenu, MainMenu all do _ready()
# scene construction). Centralising styles here means each scene can call
# `panel.add_theme_stylebox_override("panel", UIStyles.menu_body())` and
# pick up any future visual tweaks in one place.
#
# Builders cache where it makes sense — rarity styleboxes are built once
# per call site (cheap), font variations are built once per call (also
# cheap, FontVariation is a thin Resource).
#
# Color reference: Colors autoload (assets/ui/Colors.gd).
# Font reference:  assets/fonts/MacondoSwashCaps-Regular.ttf
#                  (VT323 + PressStart2P pending — drop into assets/fonts/
#                   when downloaded; FONT_MONO_PATH and FONT_PIXEL_PATH below
#                   point at where they will live).

# Single-font setup: Macondo Swash Caps fills the serif slot; the mono
# and pixel slots point at the same file because the project's only on-
# disk font is Macondo. When dedicated mono / pixel TTFs land in
# assets/fonts/, swap FONT_MONO_PATH / FONT_PIXEL_PATH below — the
# `_try_load_font` guard handles missing files gracefully.
const FONT_SERIF_PATH := "res://assets/fonts/MacondoSwashCaps-Regular.ttf"
const FONT_MONO_PATH  := "res://assets/fonts/MacondoSwashCaps-Regular.ttf"
const FONT_PIXEL_PATH := "res://assets/fonts/MacondoSwashCaps-Regular.ttf"


# --- Fonts ----------------------------------------------------------------

# Loads a font by path, returning null silently if the file is missing.
# Used so VT323 / PressStart2P slots fall back to the default font until
# those TTFs are dropped into assets/fonts/.
static func _try_load_font(path: String) -> Font:
	if not ResourceLoader.exists(path):
		return null
	return load(path)

static func font_serif() -> Font:
	return _try_load_font(FONT_SERIF_PATH)

static func font_mono() -> Font:
	return _try_load_font(FONT_MONO_PATH)

static func font_pixel() -> Font:
	return _try_load_font(FONT_PIXEL_PATH)


# --- Panels ---------------------------------------------------------------

# Oak-gradient menu body — used for pause menu, save/load dialogs, settings,
# inventory body. Mirrors .menu-body in CSS: 2px black border, oak gradient,
# layered inset shadows fudged into a single bg color (gradient requires
# StyleBoxTexture; flat is close enough).
static func menu_body_panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Colors.PANEL_OAK_1
	sb.border_color = Color.BLACK
	sb.set_border_width_all(2)
	sb.set_content_margin_all(18)
	sb.set_corner_radius_all(0)
	# Inset gold seam (fake the inset shadow with a light expand_margin)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	return sb

# Parchment panel — used for quest detail, codex entries, save context band,
# HUD tooltip. Mirrors .parchment in CSS.
static func parchment_panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Colors.PARCHMENT
	sb.border_color = Colors.PARCHMENT_EDGE
	sb.set_border_width_all(2)
	sb.set_content_margin_all(12)
	return sb

# Iron strip — HUD compass, hotbar background, slot empty state.
static func iron_panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Colors.PANEL_IRON
	sb.border_color = Colors.PANEL_IRON_EDGE
	sb.set_border_width_all(2)
	sb.set_content_margin_all(6)
	return sb

# Translucent backdrop behind modal overlays.
static func modal_backdrop() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Colors.BG_NIGHT.r, Colors.BG_NIGHT.g, Colors.BG_NIGHT.b, 0.65)
	return sb


# --- Buttons --------------------------------------------------------------

# Standard menu button — oak background, inset gold seam on hover.
# Returns a dict { "normal": ..., "hover": ..., "pressed": ..., "disabled": ... }
# for easy assignment via a loop.
static func menu_button_styles() -> Dictionary:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Colors.PANEL_OAK_2
	normal.border_color = Color.BLACK
	normal.set_border_width_all(2)
	normal.set_content_margin_all(10)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Colors.PANEL_OAK_1
	hover.border_color = Colors.GOLD
	hover.set_border_width_all(2)
	hover.set_content_margin_all(10)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Colors.PANEL_OAK_2.darkened(0.15)
	pressed.border_color = Colors.GOLD_DEEP
	pressed.set_border_width_all(2)
	pressed.set_content_margin_all(10)

	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Colors.PANEL_OAK_2.darkened(0.3)
	disabled.border_color = Colors.IRON_DEEP
	disabled.set_border_width_all(2)
	disabled.set_content_margin_all(10)

	return {
		"normal": normal,
		"hover": hover,
		"pressed": pressed,
		"disabled": disabled,
	}

# Apply menu_button_styles + font color overrides to a Button.
static func apply_menu_button(btn: Button) -> void:
	var styles := menu_button_styles()
	btn.add_theme_stylebox_override("normal", styles["normal"])
	btn.add_theme_stylebox_override("hover", styles["hover"])
	btn.add_theme_stylebox_override("pressed", styles["pressed"])
	btn.add_theme_stylebox_override("disabled", styles["disabled"])
	btn.add_theme_color_override("font_color", Colors.INK)
	btn.add_theme_color_override("font_hover_color", Colors.GOLD)
	btn.add_theme_color_override("font_pressed_color", Colors.GOLD_DEEP)
	btn.add_theme_color_override("font_disabled_color", Colors.INK_MUTE)
	var serif := font_serif()
	if serif:
		btn.add_theme_font_override("font", serif)
	btn.add_theme_font_size_override("font_size", 18)


# --- Tab buttons (MenuTabBar) --------------------------------------------

# Inactive tab — flat oak, dim text.
static func tab_inactive_styles() -> Dictionary:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Colors.PANEL_OAK_2
	normal.border_color = Color.BLACK
	normal.border_width_top = 2
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 0
	normal.set_content_margin_all(10)
	normal.content_margin_left = 18
	normal.content_margin_right = 18

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Colors.PANEL_OAK_1
	hover.border_color = Colors.GOLD_DEEP

	return { "normal": normal, "hover": hover, "pressed": hover, "disabled": normal }

# Active tab — oak top, gold inset, no bottom border.
static func tab_active_styles() -> Dictionary:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Colors.PANEL_OAK_1
	sb.border_color = Colors.GOLD
	sb.border_width_top = 3
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 0
	sb.set_content_margin_all(10)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	return { "normal": sb, "hover": sb, "pressed": sb, "disabled": sb }

static func apply_tab_button(btn: Button, active: bool) -> void:
	var styles: Dictionary = tab_active_styles() if active else tab_inactive_styles()
	for state in styles.keys():
		btn.add_theme_stylebox_override(state, styles[state])
	btn.add_theme_color_override("font_color", Colors.GOLD if active else Colors.INK_DIM)
	btn.add_theme_color_override("font_hover_color", Colors.GOLD)
	var serif := font_serif()
	if serif:
		btn.add_theme_font_override("font", serif)
	btn.add_theme_font_size_override("font_size", 16)


# --- Slot (inventory tile) -----------------------------------------------

# Slot background — iron gradient with optional rarity-coloured border.
# `rarity` may be empty string for the default common look.
static func slot_panel(rarity: String = "") -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Colors.PANEL_IRON
	if rarity != "" and Colors.RARITY_COLORS.has(rarity):
		sb.border_color = Colors.RARITY_COLORS[rarity]
	else:
		sb.border_color = Color.BLACK
	sb.set_border_width_all(2)
	sb.set_content_margin_all(4)
	return sb

# Slot hover — gold highlight on top of base.
static func slot_panel_hover(rarity: String = "") -> StyleBoxFlat:
	var sb := slot_panel(rarity)
	sb.border_color = Colors.GOLD
	return sb


# --- Save row (LoadDialog list item) -------------------------------------

static func save_row_panel(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Colors.PANEL_OAK_2 if not selected else Colors.PANEL_OAK_1
	sb.border_color = Colors.GOLD if selected else Colors.PANEL_OAK_EDGE
	sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	if selected:
		sb.shadow_color = Color(Colors.GOLD.r, Colors.GOLD.g, Colors.GOLD.b, 0.4)
		sb.shadow_size = 6
	return sb


# --- LineEdit -------------------------------------------------------------

static func line_edit_styles() -> Dictionary:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Colors.PANEL_IRON
	normal.border_color = Colors.PANEL_IRON_EDGE
	normal.set_border_width_all(2)
	normal.set_content_margin_all(6)

	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Colors.GOLD

	return { "normal": normal, "focus": focus, "read_only": normal }

static func apply_line_edit(le: LineEdit) -> void:
	var styles := line_edit_styles()
	le.add_theme_stylebox_override("normal", styles["normal"])
	le.add_theme_stylebox_override("focus", styles["focus"])
	le.add_theme_stylebox_override("read_only", styles["read_only"])
	le.add_theme_color_override("font_color", Colors.INK)
	le.add_theme_color_override("caret_color", Colors.GOLD)
	le.add_theme_color_override("selection_color", Color(Colors.GOLD.r, Colors.GOLD.g, Colors.GOLD.b, 0.3))


# --- Labels ---------------------------------------------------------------

# Big serif title (Macondo Swash) — VOXELMARK on main menu, "PAUSED" etc.
static func apply_title_label(lbl: Label, size: int = 36) -> void:
	var serif := font_serif()
	if serif:
		lbl.add_theme_font_override("font", serif)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", Colors.GOLD)

# Small uppercase serif sub-title (e.g. "AUDIO", "DISPLAY" sections in Settings)
static func apply_subtitle_label(lbl: Label) -> void:
	var serif := font_serif()
	if serif:
		lbl.add_theme_font_override("font", serif)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Colors.GOLD)
	lbl.uppercase = true

# Body text — VT323 mono if available, fallback default.
static func apply_body_label(lbl: Label, size: int = 16) -> void:
	var mono := font_mono()
	if mono:
		lbl.add_theme_font_override("font", mono)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", Colors.INK)

# Dim label (e.g. coords, secondary meta)
static func apply_dim_label(lbl: Label, size: int = 14) -> void:
	apply_body_label(lbl, size)
	lbl.add_theme_color_override("font_color", Colors.INK_DIM)

# Muted label (tip text, footer)
static func apply_muted_label(lbl: Label, size: int = 13) -> void:
	apply_body_label(lbl, size)
	lbl.add_theme_color_override("font_color", Colors.INK_MUTE)

# Keyboard chip — small pixel-font pill, gold-on-iron.
# Apply to a Label for inline kbd hints in footers.
static func apply_kbd_label(lbl: Label) -> void:
	var pixel := font_pixel()
	if pixel:
		lbl.add_theme_font_override("font", pixel)
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Colors.GOLD)


# --- Sliders + Checkboxes (Settings) -------------------------------------

static func apply_slider(s: HSlider) -> void:
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Colors.IRON_DEEP
	slider_bg.set_corner_radius_all(2)
	s.add_theme_stylebox_override("slider", slider_bg)

	var grabber_area := StyleBoxFlat.new()
	grabber_area.bg_color = Colors.BRONZE
	grabber_area.set_corner_radius_all(2)
	s.add_theme_stylebox_override("grabber_area", grabber_area)
	s.add_theme_stylebox_override("grabber_area_highlight", grabber_area)

	# Knob is a separate icon override; default arrow texture works.
