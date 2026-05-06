extends Control
# MainMenu — the homescreen / title screen.
#
# What this does in plain English:
#
#   A standalone 2D scene the game opens to (set as main_scene in
#   project.godot). Shows the game title and four buttons:
#
#     NEW GAME           — clears the active save reference and
#                          loads World3D for a fresh playthrough
#     LOAD EXISTING GAME — opens an in-place picker listing every
#                          save in user://saves/ with name, last-
#                          played timestamp, and Roland's coords
#                          at save time. Click LOAD to restore.
#     EDIT SETTINGS      — opens the Settings scene
#     CLOSE GAME         — quits the application
#
#   The load picker is built programmatically in _ready and lives
#   as a sibling of the main button column inside the same scene.
#   Only one is visible at a time. The picker mirrors the one in
#   PauseMenu so the experience is consistent: same data, same
#   layout, same DELETE row action.
#
#   World3D is NOT loaded until the player clicks NEW GAME or LOAD.
#   Showing the menu means no game scene runs in the background —
#   no voxel terrain streaming, no NPC ticks, no audio bleeding
#   through. Switching scenes via TransitionManager replaces the
#   current scene entirely.


# =============================================================
# CONSTANTS
# =============================================================

const WORLD_SCENE: String    = "res://scenes/World3D.tscn"
const SETTINGS_SCENE: String = "res://scenes/ui/Settings.tscn"

# Folder scanned for menu-background images. Drop PNG / JPG / WEBP
# files in here and the homescreen picks one at random on each
# launch. See assets/menu_backgrounds/README.md for guidance on
# image specs (1920×1080 minimum, vertical safe area, etc.).
const MENU_BACKGROUNDS_DIR: String = "res://assets/menu_backgrounds/"

# Folder scanned for menu music. Drop OGG, MP3, or WAV files in
# here and the main menu picks one at random on each launch.
# The file plays through the "Music" audio bus so the player's
# volume setting (once wired in Settings) will affect it.
const MENU_MUSIC_DIR: String = "res://assets/audio/music/"


# =============================================================
# NODE REFERENCES (all built in _ready)
# =============================================================

# Main button column.
var _main_panel: Control
var _continue_btn: Button
var _new_game_btn: Button
var _load_btn: Button
var _settings_btn: Button
var _help_btn: Button
var _credits_btn: Button
var _quit_btn: Button

# Load picker.
var _load_panel: Panel
var _load_list_container: VBoxContainer
var _load_cancel_btn: Button

# Help / Credits panels (placeholder content until authored).
var _help_panel: Panel
var _help_cancel_btn: Button
var _credits_panel: Panel
var _credits_cancel_btn: Button

# Music player — created in _setup_music(), plays one random track
# from MENU_MUSIC_DIR each time the main menu opens.
var _music_player: AudioStreamPlayer


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# This scene must accept input even though no game is paused.
	# Default PROCESS_MODE_INHERIT works fine here (nothing's paused).

	# Force mouse to be visible. If the previous run captured it
	# (CameraRig in World3D does so) and that state somehow
	# survived, the menu would render correctly but clicks would
	# never reach Controls. Set it unconditionally.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_setup_background()
	_setup_music()
	_build_main_column()
	_build_load_picker()
	_build_help_panel()
	_build_credits_panel()
	_show_main_column()

	print("[MainMenu] Ready. mouse_mode=%d (0=VISIBLE, 2=CAPTURED)" % Input.mouse_mode)


# Mouse handler — bypasses Godot's gui_input routing.
#
# Why: GUI dispatch is silently disabled in this project (see
# chat history; likely Dialogic's input subsystem). _input fires
# regardless, so we manually route:
#   - LMB → click dispatch (button-rect lookup)
#   - Wheel → scroll dispatch (find the visible ScrollContainer
#     and adjust scroll_vertical)
func _input(event: InputEvent) -> void:
	# Settings overlay is a higher-priority layer — let it handle its own clicks.
	# Check the Root Control's visibility directly; avoids calling script methods
	# on a CanvasLayer reference, which can fail if the script hasn't compiled.
	var settings_root := get_node_or_null("/root/Settings/Root")
	if settings_root != null and (settings_root as Control).visible:
		return

	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		print("[MainMenu] _input: LMB at %s, mouse_mode=%d" % [mb.position, Input.mouse_mode])
		_dispatch_click(mb.position)
	elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_dispatch_scroll(-60)
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_dispatch_scroll(60)


func _dispatch_scroll(delta_pixels: int) -> void:
	# Only the load picker has a scrollable list. Find the
	# ScrollContainer that wraps _load_list_container and adjust
	# its vertical scroll position.
	# Stringify the visibility separately so the ternary returns a
	# consistent type (avoids the INCOMPATIBLE_TERNARY warning).
	var panel_state: String = "null"
	if _load_panel != null:
		panel_state = str(_load_panel.visible)
	print("[MainMenu] _dispatch_scroll(%d), load_panel.visible=%s" % [delta_pixels, panel_state])
	if not _load_panel.visible:
		return
	if _load_list_container == null:
		return
	var scroll: ScrollContainer = _load_list_container.get_parent() as ScrollContainer
	if scroll == null:
		print("[MainMenu]   ! ScrollContainer parent not found")
		return
	var before: int = scroll.scroll_vertical
	scroll.scroll_vertical += delta_pixels
	print("[MainMenu]   scroll_vertical: %d → %d" % [before, scroll.scroll_vertical])


func _dispatch_click(pos: Vector2) -> void:
	# Routes a click position to whichever interactive Control's
	# rect contains it. Handles main panel buttons when visible,
	# load picker buttons when visible. Mirrors what the GUI
	# system would do via _gui_input + Button.pressed.
	if _main_panel != null and _main_panel.visible:
		if _hits(_continue_btn, pos): _on_continue(); return
		if _hits(_new_game_btn, pos): _on_new_game(); return
		if _hits(_load_btn,     pos): _on_load();     return
		if _hits(_settings_btn, pos): _on_settings(); return
		if _hits(_help_btn,     pos): _on_help();     return
		if _hits(_credits_btn,  pos): _on_credits();  return
		if _hits(_quit_btn,     pos): _on_quit();     return
	if _help_panel != null and _help_panel.visible:
		if _hits(_help_cancel_btn, pos):
			print("[MainMenu] dispatch: hit HELP CANCEL → returning to main")
			_show_main_column()
		return
	if _credits_panel != null and _credits_panel.visible:
		if _hits(_credits_cancel_btn, pos):
			print("[MainMenu] dispatch: hit CREDITS CANCEL → returning to main")
			_show_main_column()
		return
	if _load_panel != null and _load_panel.visible:
		# Cancel button.
		if _hits(_load_cancel_btn, pos):
			print("[MainMenu] dispatch: hit LOAD CANCEL → returning to main")
			_show_main_column()
			return
		# Per-row LOAD / DELETE buttons. Walk the dynamic list_container.
		for row in _load_list_container.get_children():
			if not (row is HBoxContainer):
				continue
			# Each row has [info_label, load_btn, delete_btn]; iterate
			# the children and dispatch on the first matching button.
			for child in row.get_children():
				if child is Button and _hits(child as Button, pos):
					print("[MainMenu] dispatch: hit row button '%s'" % (child as Button).text)
					(child as Button).pressed.emit()
					return
		print("[MainMenu] dispatch: pos %s missed all load-picker buttons" % pos)


func _hits(ctrl: Control, pos: Vector2) -> bool:
	# Returns true if the click position is inside the Control's
	# visible global rect. get_global_rect() returns the actual
	# screen-space rect including any layout/offsets.
	if ctrl == null or not ctrl.visible:
		return false
	return ctrl.get_global_rect().has_point(pos)


# =============================================================
# BACKGROUND IMAGE
# =============================================================

func _setup_background() -> void:
	# Picks a random image from assets/menu_backgrounds/ and shows
	# it as a full-screen TextureRect over the dark Background
	# ColorRect from the .tscn. If the folder is empty (or doesn't
	# exist), the dark fallback stays in place.
	#
	# A semi-transparent tint is layered on top of the image so
	# the title and buttons remain readable against busy art.
	var tex: Texture2D = _load_random_background()
	if tex == null:
		print("[MainMenu] No menu backgrounds found — using dark fallback.")
		return

	# Insert just above the Background ColorRect so it covers the
	# fallback but stays behind all UI added later.
	var bg_node: Node = get_node_or_null("Background")
	var insert_index: int = (bg_node.get_index() + 1) if bg_node != null else 0

	var bg_image := TextureRect.new()
	bg_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_image.texture = tex
	bg_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# IGNORE so the image never absorbs clicks meant for the buttons.
	bg_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_image)
	move_child(bg_image, insert_index)

	# Darkening tint for legibility — sits between the image and
	# the menu UI. Tuned at 50% to keep art visible while the title
	# text stays readable against most pieces.
	var tint := ColorRect.new()
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(0, 0, 0, 0.5)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tint)
	move_child(tint, insert_index + 1)


func _load_random_background() -> Texture2D:
	# Returns a randomly-picked Texture2D from MENU_BACKGROUNDS_DIR,
	# or null if the directory is missing or has no image files.
	var dir := DirAccess.open(MENU_BACKGROUNDS_DIR)
	if dir == null:
		return null

	var images: Array = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var lower := fname.to_lower()
			if lower.ends_with(".png") \
				or lower.ends_with(".jpg") \
				or lower.ends_with(".jpeg") \
				or lower.ends_with(".webp"):
				images.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()

	if images.is_empty():
		return null

	var pick: String = images[randi() % images.size()]
	var path: String = MENU_BACKGROUNDS_DIR + pick
	print("[MainMenu] Loaded background: %s" % pick)
	return load(path) as Texture2D


# =============================================================
# UI — main column
# =============================================================

func _build_main_column() -> void:
	# Vertical column centered horizontally, ~30% from the top of
	# the screen. Title on top, buttons below.
	#
	# IMPORTANT: _main_panel uses MOUSE_FILTER_PASS so clicks fall
	# through to the buttons inside instead of being absorbed by
	# the empty area of the wrapper Control. The buttons themselves
	# have STOP filter (default) and consume their own clicks.
	_main_panel = Control.new()
	_main_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	# Taller box to fit seven buttons + a tabbed Quit at the bottom.
	_main_panel.offset_left   = -260
	_main_panel.offset_top    = -400
	_main_panel.offset_right  =  260
	_main_panel.offset_bottom =  400
	_main_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_main_panel)

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	_main_panel.add_child(v)

	# --- Title ---
	var title := Label.new()
	title.text = "GAME ONE"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.92, 0.86, 0.7, 1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Mira-Thal Trilogy"
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", Color(0.55, 0.5, 0.42, 1))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(subtitle)

	# Spacer between title and buttons.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 36)
	v.add_child(spacer)

	# --- Buttons ---
	# All buttons share a layout: flat, 1080p-sized font,
	# fixed minimum height so they don't shrink.
	var make_btn := func(label: String) -> Button:
		var b := Button.new()
		b.text = label
		b.flat = true
		b.custom_minimum_size = Vector2(0, 56)
		b.add_theme_font_size_override("font_size", 28)
		b.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75, 1))
		return b

	# Order from top to bottom: Continue, New Game, Load Game,
	# Settings, Help, Credits, then a tall spacer, then Quit.
	_continue_btn = make_btn.call("CONTINUE")
	_new_game_btn = make_btn.call("NEW GAME")
	_load_btn     = make_btn.call("LOAD GAME")
	_settings_btn = make_btn.call("SETTINGS")
	_help_btn     = make_btn.call("HELP")
	_credits_btn  = make_btn.call("CREDITS")
	_quit_btn     = make_btn.call("QUIT")

	v.add_child(_continue_btn)
	v.add_child(_new_game_btn)
	v.add_child(_load_btn)
	v.add_child(_settings_btn)
	v.add_child(_help_btn)
	v.add_child(_credits_btn)

	# Tall gap so Quit sits visually separated several lines below.
	var quit_spacer := Control.new()
	quit_spacer.custom_minimum_size = Vector2(0, 80)
	quit_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(quit_spacer)

	v.add_child(_quit_btn)

	_continue_btn.pressed.connect(_on_continue)
	_new_game_btn.pressed.connect(_on_new_game)
	_load_btn.pressed.connect(_on_load)
	_settings_btn.pressed.connect(_on_settings)
	_help_btn.pressed.connect(_on_help)
	_credits_btn.pressed.connect(_on_credits)
	_quit_btn.pressed.connect(_on_quit)

	# --- Version stamp in the corner ---
	var version := Label.new()
	version.text = "Milestone 5-3D — dev build"
	version.add_theme_font_size_override("font_size", 12)
	version.add_theme_color_override("font_color", Color(0.32, 0.32, 0.32, 1))
	version.position = Vector2(16, 16)
	# Anchor to bottom-left.
	version.anchor_top = 1.0
	version.anchor_bottom = 1.0
	version.offset_top = -32
	version.offset_bottom = -16
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(version)


# =============================================================
# UI — load picker
# =============================================================

func _build_load_picker() -> void:
	# Same picker UI as PauseMenu: scrollable list of saves, each
	# row shows name + timestamp + coords + LOAD/DELETE buttons.
	# Hidden until LOAD EXISTING GAME is clicked.
	_load_panel = Panel.new()
	_load_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_load_panel.offset_left   = -360
	_load_panel.offset_top    = -280
	_load_panel.offset_right  =  360
	_load_panel.offset_bottom =  280
	_load_panel.visible = false
	add_child(_load_panel)

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left   = 16
	v.offset_top    = 16
	v.offset_right  = -16
	v.offset_bottom = -16
	v.add_theme_constant_override("separation", 10)
	_load_panel.add_child(v)

	var title := Label.new()
	title.text = "— LOAD GAME —"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.92, 0.86, 0.7, 1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)

	_load_list_container = VBoxContainer.new()
	_load_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_list_container.add_theme_constant_override("separation", 6)
	scroll.add_child(_load_list_container)

	_load_cancel_btn = Button.new()
	_load_cancel_btn.text = "CANCEL"
	_load_cancel_btn.add_theme_font_size_override("font_size", 20)
	_load_cancel_btn.custom_minimum_size = Vector2(160, 44)
	_load_cancel_btn.pressed.connect(_show_main_column)
	v.add_child(_load_cancel_btn)


func _populate_load_list() -> void:
	for child in _load_list_container.get_children():
		child.queue_free()

	var saves: Array = GameState.list_save_files()
	if saves.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No saves yet. Start a New Game to begin."
		empty_lbl.add_theme_font_size_override("font_size", 16)
		empty_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65, 1))
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_load_list_container.add_child(empty_lbl)
		return

	for meta in saves:
		_load_list_container.add_child(_make_save_row(meta))


func _make_save_row(meta: Dictionary) -> Control:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 60)
	hbox.add_theme_constant_override("separation", 10)

	var pos: Vector3 = meta.get("player_position", Vector3.ZERO)

	var info_lbl := Label.new()
	info_lbl.text = "%s\n%s   X %.0f  Y %.0f  Z %.0f" % [
		meta.get("save_name", "?"),
		meta.get("timestamp", "?"),
		pos.x, pos.y, pos.z,
	]
	info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_lbl.add_theme_font_size_override("font_size", 16)
	info_lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75, 1))
	hbox.add_child(info_lbl)

	var load_btn := Button.new()
	load_btn.text = "LOAD"
	load_btn.add_theme_font_size_override("font_size", 16)
	load_btn.custom_minimum_size = Vector2(96, 44)
	load_btn.pressed.connect(_on_load_select.bind(meta.get("filename", "")))
	hbox.add_child(load_btn)

	var delete_btn := Button.new()
	delete_btn.text = "DELETE"
	delete_btn.add_theme_font_size_override("font_size", 16)
	delete_btn.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5, 1))
	delete_btn.custom_minimum_size = Vector2(96, 44)
	delete_btn.pressed.connect(_on_load_delete.bind(meta.get("filename", "")))
	hbox.add_child(delete_btn)

	return hbox


# =============================================================
# UI — help panel
# =============================================================

func _build_help_panel() -> void:
	# Placeholder Help screen — same panel/cancel pattern as the
	# load picker. Real content can be authored later by editing
	# the body label below or pulling text from a .md file.
	_help_panel = Panel.new()
	_help_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_help_panel.offset_left   = -360
	_help_panel.offset_top    = -280
	_help_panel.offset_right  =  360
	_help_panel.offset_bottom =  280
	_help_panel.visible = false
	add_child(_help_panel)

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left   = 16
	v.offset_top    = 16
	v.offset_right  = -16
	v.offset_bottom = -16
	v.add_theme_constant_override("separation", 12)
	_help_panel.add_child(v)

	var title := Label.new()
	title.text = "— HELP —"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.92, 0.86, 0.7, 1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var body := Label.new()
	body.text = "Help content coming soon."
	body.add_theme_font_size_override("font_size", 18)
	body.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75, 1))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(body)

	_help_cancel_btn = Button.new()
	_help_cancel_btn.text = "BACK"
	_help_cancel_btn.add_theme_font_size_override("font_size", 20)
	_help_cancel_btn.custom_minimum_size = Vector2(160, 44)
	_help_cancel_btn.pressed.connect(_show_main_column)
	v.add_child(_help_cancel_btn)


# =============================================================
# UI — credits panel
# =============================================================

func _build_credits_panel() -> void:
	# Placeholder Credits screen.
	_credits_panel = Panel.new()
	_credits_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_credits_panel.offset_left   = -360
	_credits_panel.offset_top    = -280
	_credits_panel.offset_right  =  360
	_credits_panel.offset_bottom =  280
	_credits_panel.visible = false
	add_child(_credits_panel)

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left   = 16
	v.offset_top    = 16
	v.offset_right  = -16
	v.offset_bottom = -16
	v.add_theme_constant_override("separation", 12)
	_credits_panel.add_child(v)

	var title := Label.new()
	title.text = "— CREDITS —"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.92, 0.86, 0.7, 1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var body := Label.new()
	body.text = "Credits coming soon."
	body.add_theme_font_size_override("font_size", 18)
	body.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75, 1))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(body)

	_credits_cancel_btn = Button.new()
	_credits_cancel_btn.text = "BACK"
	_credits_cancel_btn.add_theme_font_size_override("font_size", 20)
	_credits_cancel_btn.custom_minimum_size = Vector2(160, 44)
	_credits_cancel_btn.pressed.connect(_show_main_column)
	v.add_child(_credits_cancel_btn)


# =============================================================
# PANEL SWITCHING
# =============================================================

func _show_main_column() -> void:
	_main_panel.visible = true
	_load_panel.visible = false
	if _help_panel != null:
		_help_panel.visible = false
	if _credits_panel != null:
		_credits_panel.visible = false
	# Continue and Load both depend on at least one save existing.
	var no_saves: bool = GameState.list_save_files().is_empty()
	_continue_btn.disabled = no_saves
	_load_btn.disabled = no_saves


func _show_load_picker() -> void:
	_main_panel.visible = false
	_load_panel.visible = true
	_populate_load_list()


# =============================================================
# BUTTON HANDLERS — main column
# =============================================================

func _on_continue() -> void:
	# Loads the most recent save. list_save_files() returns saves
	# sorted newest-first, so index 0 is the right pick.
	print("[MainMenu] CONTINUE pressed")
	var saves: Array = GameState.list_save_files()
	if saves.is_empty():
		print("[MainMenu]   ! no saves to continue from")
		return
	var newest: Dictionary = saves[0]
	_on_load_select(newest.get("filename", ""))


func _on_new_game() -> void:
	# Fresh playthrough — wipe every piece of session state that
	# persists across scene transitions in autoloads (voxel deltas
	# on disk, GameState flags + skill XP + companions, inventory,
	# player position/rotation). Without this reset, "New Game"
	# inherits the previous playthrough's voxel edits, inventory,
	# and flags from autoload memory.
	print("[MainMenu] NEW GAME pressed")
	GameState.reset_for_new_game()
	_handoff_music_to_loading_screen()
	# 10 s loading hold — gives Zylann's worker threads a window to
	# stream the player's spawn-area chunks before the fade clears.
	# Without this the player sees half-loaded blocky terrain for
	# the first few seconds of every new game.
	TransitionManager.change_scene(WORLD_SCENE, "default", TransitionManager.Type.FADE_BLACK, 10.0)


func _on_load() -> void:
	print("[MainMenu] LOAD pressed")
	_show_load_picker()


func _on_settings() -> void:
	print("[MainMenu] SETTINGS pressed")
	var settings := get_node_or_null("/root/Settings")
	if settings != null:
		settings.call("open", false)
	else:
		TransitionManager.change_scene(SETTINGS_SCENE, "", TransitionManager.Type.CUT)


func _on_help() -> void:
	print("[MainMenu] HELP pressed")
	_main_panel.visible = false
	_load_panel.visible = false
	_credits_panel.visible = false
	_help_panel.visible = true


func _on_credits() -> void:
	print("[MainMenu] CREDITS pressed")
	_main_panel.visible = false
	_load_panel.visible = false
	_help_panel.visible = false
	_credits_panel.visible = true


func _on_quit() -> void:
	print("[MainMenu] QUIT pressed")
	get_tree().quit()


# =============================================================
# BUTTON HANDLERS — load picker
# =============================================================

func _on_load_select(filename: String) -> void:
	print("[MainMenu] _on_load_select called with filename='%s'" % filename)
	if filename == "":
		print("[MainMenu]   ! empty filename, returning")
		return
	if not GameState.load_save_file(filename):
		print("[MainMenu] Load failed for: %s" % filename)
		return
	var scene: String = GameState.current_scene
	print("[MainMenu]   GameState.current_scene='%s'" % scene)
	if scene == "" or not ResourceLoader.exists(scene):
		print("[MainMenu]   scene unresolvable, falling back to WORLD_SCENE")
		scene = WORLD_SCENE
	print("[MainMenu]   transitioning to '%s' (spawn='%s')" % [scene, GameState.player_spawn_id])
	_handoff_music_to_loading_screen()
	# Same 10 s loading hold as NEW GAME — restored saves still need
	# chunk streaming time, plus voxel deltas reading from SQLite.
	TransitionManager.change_scene(scene, GameState.player_spawn_id, TransitionManager.Type.FADE_BLACK, 10.0)


func _on_load_delete(filename: String) -> void:
	if filename == "":
		return
	GameState.delete_save_file(filename)
	# Refresh in place so the deleted row disappears.
	_populate_load_list()


# =============================================================
# MUSIC
# =============================================================

func _setup_music() -> void:
	# Picks a random audio file from MENU_MUSIC_DIR and plays it.
	# If the folder is empty or doesn't exist yet, does nothing.
	#
	# The AudioStreamPlayer is created here in code (no .tscn change
	# needed) and routed to the "Music" bus defined in
	# default_bus_layout.tres. When the player starts or loads a game
	# the entire scene is replaced, which automatically frees this
	# node and stops playback — no manual cleanup needed.
	var stream: AudioStream = _load_random_music()
	if stream == null:
		print("[MainMenu] No menu music found in %s — playing silent." % MENU_MUSIC_DIR)
		return

	_music_player = AudioStreamPlayer.new()
	_music_player.stream = stream
	_music_player.bus = "Music"   # routes through the Music bus in default_bus_layout.tres
	_music_player.volume_db = 0.0 # 0 dB = full volume; lower this (e.g. -6.0) if it's too loud
	add_child(_music_player)
	_music_player.play()
	print("[MainMenu] Playing menu music on 'Music' bus.")


func _load_random_music() -> AudioStream:
	# Returns a randomly-picked AudioStream from MENU_MUSIC_DIR,
	# or null if the directory is missing or has no audio files.
	# Supported formats: .ogg, .mp3, .wav (all work in Godot 4).
	var dir := DirAccess.open(MENU_MUSIC_DIR)
	if dir == null:
		return null

	var tracks: Array = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var lower := fname.to_lower()
			if lower.ends_with(".ogg") \
				or lower.ends_with(".mp3") \
				or lower.ends_with(".wav"):
				tracks.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()

	if tracks.is_empty():
		return null

	var pick: String = tracks[randi() % tracks.size()]
	var path: String = MENU_MUSIC_DIR + pick
	print("[MainMenu] Loaded music track: %s" % pick)
	return load(path) as AudioStream


# Handoff: reparent our AudioStreamPlayer onto TransitionManager so it
# survives change_scene_to_file (which frees this entire MainMenu
# scene). TransitionManager fades and frees the player when the
# loading screen ends. Safe to call when no music is playing.
func _handoff_music_to_loading_screen() -> void:
	if _music_player == null:
		return
	if not is_instance_valid(_music_player):
		_music_player = null
		return
	var tm := get_node_or_null("/root/TransitionManager")
	if tm == null or not tm.has_method("adopt_music"):
		# No autoload available — let the scene change free the player normally.
		return
	tm.call("adopt_music", _music_player)
	_music_player = null
