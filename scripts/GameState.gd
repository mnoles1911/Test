extends Node
# GameState — Autoload singleton. Stays alive for the entire game session.
#
# What "Autoload singleton" means in plain English:
#   Godot loads this script once at startup and never destroys it, even when
#   scenes change. Every script in the game can read and write to it like a
#   shared notepad. Access it from any script: GameState.set_flag("key", value)
#
# This file does two things:
#   1. Stores everything that needs to survive scene transitions
#      (story flags, player position, companions, current enemy)
#   2. Saves and loads that state to a JSON file on disk


# =============================================================
# PLAYER POSITION AND SCENE TRACKING
# =============================================================
# TransitionManager updates these before every scene change so the
# receiving scene knows where to spawn the player.

var player_position: Vector2 = Vector2.ZERO
var current_scene: String = ""
var player_spawn_id: String = ""
# player_spawn_id is the name of the SpawnPoint node the receiving scene
# should place the player at. Empty string = use the scene's default position.


# =============================================================
# STORY FLAGS
# =============================================================
# All story state lives in one dictionary: flag_name -> value.
# Values can be bool, int, or String.
#
# Use set_flag() and get_flag() — never access _flags directly.
# This keeps all flag reads and writes logged, which is very useful
# for debugging "why did this dialogue option appear?"
#
# Example flags (set as the story progresses):
#   henrietta_dead          bool  — set when Roland finds Henrietta's body
#   pommel_piece_1_acquired bool  — set when Roland takes the pommel from the chapel
#   aldric_vane_name_logged bool  — set when Roland reads the Archive footnote
#   tomlin_helped           bool  — set when Tomlin cooperates with Roland
#   orion_joined            bool  — set when Orion joins at Caer Brannoch

var _flags: Dictionary = {}

func set_flag(flag_name: String, value) -> void:
	# Set a story flag and log it for debugging.
	_flags[flag_name] = value
	print("[GameState] Flag set: %s = %s" % [flag_name, str(value)])

func get_flag(flag_name: String, default_value = false):
	# Read a story flag. Returns default_value if the flag has never been set.
	return _flags.get(flag_name, default_value)

func has_flag(flag_name: String) -> bool:
	# Returns true only if this flag has been explicitly set (even to false).
	return _flags.has(flag_name)


# =============================================================
# COMPANION ROSTER
# =============================================================
# Tracks which companions are currently available in the party.
# Set companion_active("orion", true) when Orion joins at Caer Brannoch.

var _companions: Dictionary = {
	"orion":  false,   # Joins mid Game One (Caer Brannoch)
	"dagna":  false,   # Joins Game One Act III (Underway)
	"corvus": false,   # Joins Game Two
	"seren":  false,   # Joins Game Two
	"aldric": false,   # Game Three
}

func companion_active(name: String) -> bool:
	return _companions.get(name, false)

func set_companion(name: String, active: bool) -> void:
	_companions[name] = active
	print("[GameState] Companion %s: %s" % [name, "joined" if active else "left"])


# =============================================================
# CURRENT ENEMY
# =============================================================
# Set this to an EnemyData resource before calling
# TransitionManager.change_scene("res://scenes/Combat.tscn").
# Combat.gd reads it in _ready() to configure the fight.

var current_enemy_data = null  # Holds an EnemyData resource, or null for defaults


# =============================================================
# SAVE AND LOAD
# =============================================================
# The save file lives at user://save.json.
# "user://" is a Godot shorthand for the OS user data folder:
#   Windows: %APPDATA%\Godot\app_userdata\Game One\
#   Linux:   ~/.local/share/godot/app_userdata/Game One/
#   Mac:     ~/Library/Application Support/Godot/app_userdata/Game One/
#
# TransitionManager calls save_game() automatically on every scene change.
# The player can also save manually at rest points.

const SAVE_PATH: String = "user://save.json"

func save_game() -> void:
	var data: Dictionary = {
		"version": 1,
		"player_position": {"x": player_position.x, "y": player_position.y},
		"current_scene": current_scene,
		"flags": _flags.duplicate(),
		"companions": _companions.duplicate(),
	}
	var json_string: String = JSON.stringify(data, "\t")
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("[GameState] Game saved.")
		# Show the on-screen save indicator if the autoload exists.
		if get_node_or_null("/root/SaveNotification"):
			SaveNotification.show_notification()
	else:
		push_error("[GameState] Could not write save file at: " + SAVE_PATH)

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		print("[GameState] No save file found — starting fresh.")
		return
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		push_error("[GameState] Could not open save file.")
		return
	var json_string: String = file.get_as_text()
	file.close()
	var result = JSON.parse_string(json_string)
	if result == null:
		push_error("[GameState] Save file JSON is malformed.")
		return
	var data: Dictionary = result
	if data.has("player_position"):
		player_position = Vector2(
			data["player_position"].get("x", 0.0),
			data["player_position"].get("y", 0.0)
		)
	if data.has("current_scene"):
		current_scene = data["current_scene"]
	if data.has("flags"):
		_flags = data["flags"]
	if data.has("companions"):
		# Merge loaded companions over the defaults so new companions
		# added in future updates still appear.
		for key in data["companions"]:
			_companions[key] = data["companions"][key]
	print("[GameState] Game loaded. Flags: %d" % _flags.size())

func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		print("[GameState] Save file deleted.")


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	print("[GameState] Initialized.")
