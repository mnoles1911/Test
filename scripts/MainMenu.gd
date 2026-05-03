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


# =============================================================
# NODE REFERENCES (all built in _ready)
# =============================================================

# Main button column.
var _main_panel: Control
var _new_game_btn: Button
var _load_btn: Button
var _settings_btn: Button
var _quit_btn: Button

# Load picker.
var _load_panel: Panel
var _load_list_container: VBoxContainer
var _load_cancel_btn: Button


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
	_build_main_column()
	_build_load_picker()
	_show_main_column()
	_build_debug_click_test()

	print("[MainMenu] Ready. mouse_mode=%d (0=VISIBLE, 2=CAPTURED)" % Input.mouse_mode)


# Big red test rectangle to validate the basic click pipeline.
# If clicking on this prints, but the actual menu buttons don't,
# the issue is button-specific (focus, layout). If clicking on
# this also doesn't print, an autoload is absorbing all clicks
# before they reach MainMenu.
func _build_debug_click_test() -> void:
	var rect := ColorRect.new()
	rect.color = Color(0.8, 0.1, 0.1, 0.85)
	rect.position = Vector2(20, 200)
	rect.size = Vector2(200, 80)
	rect.gui_input.connect(_on_debug_rect_input)
	add_child(rect)

	var lbl := Label.new()
	lbl.text = "CLICK ME (debug)"
	lbl.position = Vector2(30, 230)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)


func _on_debug_rect_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		print("[MainMenu] DEBUG RECT CLICKED — input pipeline works.")


# LMB click handler — bypasses Godot's gui_input routing.
#
# Why: Godot's GUI input dispatch (Button.pressed signal) only
# fires when Input.mouse_mode is MOUSE_MODE_VISIBLE. If anything
# upstream captures the mouse (CameraRig from a prior World3D
# run, etc.) and the captured state survives, _gui_input never
# fires for any Control even when the cursor is visually shown.
#
# Workaround: handle clicks in _input (Node-level, fires regardless
# of mouse_mode) and manually check whether the click position
# overlaps each interactive Control's global rect. This is robust
# against the mouse_mode quirk and works reliably.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	print("[MainMenu] _input: LMB at %s, mouse_mode=%d" % [mb.position, Input.mouse_mode])
	_dispatch_click(mb.position)


func _dispatch_click(pos: Vector2) -> void:
	# Routes a click position to whichever interactive Control's
	# rect contains it. Handles main panel buttons when visible,
	# load picker buttons when visible. Mirrors what the GUI
	# system would do via _gui_input + Button.pressed.
	if _main_panel != null and _main_panel.visible:
		if _hits(_new_game_btn, pos): _on_new_game(); return
		if _hits(_load_btn,     pos): _on_load();     return
		if _hits(_settings_btn, pos): _on_settings(); return
		if _hits(_quit_btn,     pos): _on_quit();     return
	if _load_panel != null and _load_panel.visible:
		# Cancel button.
		if _hits(_load_cancel_btn, pos):
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
					(child as Button).pressed.emit()
					return


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
	_main_panel.offset_left   = -260
	_main_panel.offset_top    = -300
	_main_panel.offset_right  =  260
	_main_panel.offset_bottom =  300
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
	# All four buttons share a layout: flat, 1080p-sized font,
	# fixed minimum height so they don't shrink.
	var make_btn := func(label: String) -> Button:
		var b := Button.new()
		b.text = label
		b.flat = true
		b.custom_minimum_size = Vector2(0, 56)
		b.add_theme_font_size_override("font_size", 28)
		b.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75, 1))
		return b

	_new_game_btn = make_btn.call("NEW GAME")
	_load_btn     = make_btn.call("LOAD EXISTING GAME")
	_settings_btn = make_btn.call("EDIT SETTINGS")
	_quit_btn     = make_btn.call("CLOSE GAME")

	for btn in [_new_game_btn, _load_btn, _settings_btn, _quit_btn]:
		v.add_child(btn)

	_new_game_btn.pressed.connect(_on_new_game)
	_load_btn.pressed.connect(_on_load)
	_settings_btn.pressed.connect(_on_settings)
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
# PANEL SWITCHING
# =============================================================

func _show_main_column() -> void:
	_main_panel.visible = true
	_load_panel.visible = false
	_load_btn.disabled = GameState.list_save_files().is_empty()


func _show_load_picker() -> void:
	_main_panel.visible = false
	_load_panel.visible = true
	_populate_load_list()


# =============================================================
# BUTTON HANDLERS — main column
# =============================================================

func _on_new_game() -> void:
	# Fresh playthrough — clear the active save reference (no
	# auto-overwrite of an old save on next exit) and load World3D.
	print("[MainMenu] NEW GAME pressed")
	GameState.active_save_filename = ""
	GameState.player_spawn_id = ""
	TransitionManager.change_scene(WORLD_SCENE, "default")


func _on_load() -> void:
	print("[MainMenu] LOAD pressed")
	_show_load_picker()


func _on_settings() -> void:
	print("[MainMenu] SETTINGS pressed")
	TransitionManager.change_scene(SETTINGS_SCENE, "", TransitionManager.Type.CUT)


func _on_quit() -> void:
	print("[MainMenu] QUIT pressed")
	get_tree().quit()


# =============================================================
# BUTTON HANDLERS — load picker
# =============================================================

func _on_load_select(filename: String) -> void:
	if filename == "":
		return
	if not GameState.load_save_file(filename):
		print("[MainMenu] Load failed for: %s" % filename)
		return
	var scene: String = GameState.current_scene
	if scene == "" or not ResourceLoader.exists(scene):
		scene = WORLD_SCENE
	TransitionManager.change_scene(scene, GameState.player_spawn_id)


func _on_load_delete(filename: String) -> void:
	if filename == "":
		return
	GameState.delete_save_file(filename)
	# Refresh in place so the deleted row disappears.
	_populate_load_list()
