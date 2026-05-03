extends Control
# MainMenu — the game's title screen.
#
# What this does in plain English:
#   Shows the game title and four buttons: New Game, Load Game, Settings, Quit.
#   New Game starts fresh (deletes any existing save, loads World.tscn).
#   Load Game loads the last save and continues from the saved scene.
#   Settings opens the Settings screen (Settings.tscn).
#   Quit closes the application.
#
# This scene is set as the main scene in project.godot once you're ready
# to use it. While developing, World.tscn remains the main scene.
# To switch: Project → Project Settings → Application → Run → Main Scene.


# =============================================================
# CONSTANTS
# =============================================================

const WORLD_SCENE: String = "res://scenes/World.tscn"
const SETTINGS_SCENE: String = "res://scenes/ui/Settings.tscn"


# =============================================================
# NODE REFERENCES
# =============================================================

@onready var new_game_btn: Button   = $VBox/NewGameBtn
@onready var load_game_btn: Button  = $VBox/LoadGameBtn
@onready var settings_btn: Button   = $VBox/SettingsBtn
@onready var quit_btn: Button       = $VBox/QuitBtn


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	new_game_btn.pressed.connect(_on_new_game)
	load_game_btn.pressed.connect(_on_load_game)
	settings_btn.pressed.connect(_on_settings)
	quit_btn.pressed.connect(_on_quit)

	# Grey out Load Game if there are no saves on disk.
	load_game_btn.disabled = GameState.list_save_files().is_empty()

	print("[MainMenu] Ready.")


# =============================================================
# BUTTON HANDLERS
# =============================================================

func _on_new_game() -> void:
	# A fresh playthrough does NOT delete existing saves any more —
	# saves are named files; players manage them via the load picker.
	# Just clear the active reference so we don't accidentally write
	# back to an old save on quit.
	GameState.active_save_filename = ""
	GameState.player_spawn_id = ""
	TransitionManager.change_scene(WORLD_SCENE, "default")

func _on_load_game() -> void:
	# Load the most recent save (first in the list — sorted newest first).
	var saves: Array = GameState.list_save_files()
	if saves.is_empty():
		print("[MainMenu] No saves to load.")
		return
	GameState.load_save_file(saves[0]["filename"])
	var scene: String = GameState.current_scene
	if scene == "" or not ResourceLoader.exists(scene):
		scene = WORLD_SCENE
	TransitionManager.change_scene(scene, GameState.player_spawn_id)

func _on_settings() -> void:
	TransitionManager.change_scene(SETTINGS_SCENE, "", TransitionManager.Type.CUT)

func _on_quit() -> void:
	get_tree().quit()
