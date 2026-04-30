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

# Flag change history — a ring buffer of the last FLAG_HISTORY_MAX entries.
# Each entry: { "flag": String, "old": Variant, "new": Variant, "time": String }
const FLAG_HISTORY_MAX: int = 100
var _flag_history: Array = []

func set_flag(flag_name: String, value) -> void:
	var old_value = _flags.get(flag_name, null)
	_flags[flag_name] = value
	_record_flag_change(flag_name, old_value, value)
	print("[GameState] Flag set: %s = %s" % [flag_name, str(value)])

func get_flag(flag_name: String, default_value = false):
	return _flags.get(flag_name, default_value)

func has_flag(flag_name: String) -> bool:
	return _flags.has(flag_name)

func _record_flag_change(flag_name: String, old_value, new_value) -> void:
	_flag_history.append({
		"flag": flag_name,
		"old":  str(old_value) if old_value != null else "(unset)",
		"new":  str(new_value),
		"time": Time.get_time_string_from_system(),
	})
	if _flag_history.size() > FLAG_HISTORY_MAX:
		_flag_history.pop_front()

func get_flag_history(count: int = 20) -> Array:
	# Returns the most recent `count` entries, newest first.
	var result: Array = _flag_history.duplicate()
	result.reverse()
	return result.slice(0, min(count, result.size()))


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
# SAVE AND LOAD — MULTI-SLOT
# =============================================================
# Three save slots (0, 1, 2). The active slot is tracked in active_save_slot.
# Autosaves always go to active_save_slot.
# The slot picker UI (SaveSlotPicker.tscn) lets the player choose a slot
# for manual saves and loads.
#
# File names: user://save_0.json, user://save_1.json, user://save_2.json
#
# "user://" is a Godot shorthand for the OS user data folder:
#   Windows: %APPDATA%\Godot\app_userdata\Game One\
#   Linux:   ~/.local/share/godot/app_userdata/Game One/
#   Mac:     ~/Library/Application Support/Godot/app_userdata/Game One/

const SAVE_SLOT_COUNT: int = 3
const SAVE_PATH: String = "user://save.json"  # legacy — kept for compatibility checks

var active_save_slot: int = 0
# Which slot autosaves go to. Set when the player picks a slot.

func save_path_for_slot(slot: int) -> String:
	return "user://save_%d.json" % slot

func save_game(slot: int = -1) -> void:
	# slot = -1 means "use active_save_slot".
	if slot < 0:
		slot = active_save_slot
	slot = clampi(slot, 0, SAVE_SLOT_COUNT - 1)

	var data: Dictionary = {
		"version": 2,
		"slot": slot,
		"timestamp": Time.get_datetime_string_from_system(),
		"play_time_seconds": _play_time_seconds,
		"player_position": {"x": player_position.x, "y": player_position.y},
		"current_scene": current_scene,
		"flags": _flags.duplicate(),
		"companions": _companions.duplicate(),
	}
	var path: String = save_path_for_slot(slot)
	var json_string: String = JSON.stringify(data, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("[GameState] Saved to slot %d (%s)." % [slot, path])
		if get_node_or_null("/root/SaveNotification"):
			SaveNotification.show_notification()
	else:
		push_error("[GameState] Could not write save file: " + path)

func load_game(slot: int = -1) -> void:
	if slot < 0:
		slot = active_save_slot
	slot = clampi(slot, 0, SAVE_SLOT_COUNT - 1)

	var path: String = save_path_for_slot(slot)
	if not FileAccess.file_exists(path):
		# Fall back to the legacy single save file so old saves still work.
		if FileAccess.file_exists(SAVE_PATH):
			path = SAVE_PATH
		else:
			print("[GameState] No save file found for slot %d." % slot)
			return

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[GameState] Could not open save file: " + path)
		return
	var result = JSON.parse_string(file.get_as_text())
	file.close()
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
		for key in data["companions"]:
			_companions[key] = data["companions"][key]
	if data.has("slot"):
		active_save_slot = data["slot"]
	print("[GameState] Loaded slot %d. Flags: %d" % [slot, _flags.size()])

func delete_save(slot: int = -1) -> void:
	if slot < 0:
		slot = active_save_slot
	var path: String = save_path_for_slot(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		print("[GameState] Deleted save slot %d." % slot)

func get_slot_info(slot: int) -> Dictionary:
	# Returns metadata for a slot without fully loading it.
	# Used by the slot picker UI to show timestamps and scene names.
	var path: String = save_path_for_slot(slot)
	if not FileAccess.file_exists(path):
		return {"exists": false, "slot": slot}
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {"exists": false, "slot": slot}
	var result = JSON.parse_string(file.get_as_text())
	file.close()
	if result == null:
		return {"exists": false, "slot": slot}
	return {
		"exists": true,
		"slot": slot,
		"timestamp": result.get("timestamp", "unknown"),
		"current_scene": result.get("current_scene", ""),
	}


# =============================================================
# PLAY TIME TRACKING
# =============================================================

var _play_time_seconds: float = 0.0

func _process(delta: float) -> void:
	_play_time_seconds += delta


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	print("[GameState] Initialized.")
