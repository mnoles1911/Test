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
var _loading_title_label: Label
var _loading_quip_label: Label
var _loading_quip_timer: float = 0.0
var _loading_quip_index: int = 0
var _loading_quip_order: Array = []      # shuffled indices into LOADING_QUIPS

var _loading_active: bool = false
var _loading_total_seconds: float = 0.0
var _loading_elapsed: float = 0.0

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
	_loading_tint.color = Color(0.0, 0.0, 0.0, 0.5)
	_loading_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_root.add_child(_loading_tint)

	# Centre column.
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.size = Vector2(600, 520)
	vbox.position = Vector2(-300, -260)
	vbox.add_theme_constant_override("separation", 24)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_root.add_child(vbox)

	_loading_title_label = Label.new()
	_loading_title_label.text = "Loading"
	_loading_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_title_label.add_theme_font_size_override("font_size", 48)
	_loading_title_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85, 1.0))
	vbox.add_child(_loading_title_label)

	# Hourglass — fixed 240×320 area, centred horizontally inside its
	# row by an HBoxContainer with two flexible spacers around it.
	var hg_row := HBoxContainer.new()
	hg_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hg_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(hg_row)

	_loading_hourglass = LoadingHourglass.new()
	_loading_hourglass.custom_minimum_size = Vector2(240, 320)
	hg_row.add_child(_loading_hourglass)

	_loading_quip_label = Label.new()
	_loading_quip_label.text = ""
	_loading_quip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_quip_label.add_theme_font_size_override("font_size", 22)
	_loading_quip_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.72, 1.0))
	_loading_quip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_loading_quip_label)


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

	_loading_elapsed += delta

	# Hourglass progress maps elapsed → [0, 1]. Past 1.0 we just clamp
	# (the screen will be hidden by the awaited timer in _do_transition).
	var p: float = 0.0
	if _loading_total_seconds > 0.0:
		p = clamp(_loading_elapsed / _loading_total_seconds, 0.0, 1.0)
	if _loading_hourglass != null:
		_loading_hourglass.set_progress(p)

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
	if _loading_hourglass != null:
		_loading_hourglass.set_progress(0.0)

	_loading_root.visible = true
	_loading_active = true


func _hide_loading_screen() -> void:
	_loading_active = false
	if _loading_root != null:
		_loading_root.visible = false
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
	_loading_quip_label.text = LOADING_QUIPS[_loading_quip_order[_loading_quip_index]]


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
