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

	# Grey out Load Game if there is no save file.
	load_game_btn.disabled = not FileAccess.file_exists(GameState.SAVE_PATH)

	print("[MainMenu] Ready.")


# =============================================================
# BUTTON HANDLERS
# =============================================================

func _on_new_game() -> void:
	# Delete any existing save so there's no stale state.
	GameState.delete_save()
	# Clear the in-memory state as well.
	GameState.player_spawn_id = ""
	TransitionManager.change_scene(WORLD_SCENE, "default")

func _on_load_game() -> void:
	GameState.load_game()
	var scene: String = GameState.current_scene
	# Fallback in case the saved scene is empty or the file has moved.
	if scene == "" or not ResourceLoader.exists(scene):
		scene = WORLD_SCENE
	TransitionManager.change_scene(scene, GameState.player_spawn_id)

func _on_settings() -> void:
	TransitionManager.change_scene(SETTINGS_SCENE, "", TransitionManager.Type.CUT)

func _on_quit() -> void:
	get_tree().quit()
