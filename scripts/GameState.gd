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
# TransitionManager updates `current_scene` before every scene change.
# `player_position` is captured from the live player at save time via
# a group lookup — see _capture_player_position(). It's persisted to
# the save and applied on load when the scene re-instances.

var player_position: Vector3 = Vector3.ZERO
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

func companion_active(companion_id: String) -> bool:
	return _companions.get(companion_id, false)

func set_companion(companion_id: String, active: bool) -> void:
	_companions[companion_id] = active
	print("[GameState] Companion %s: %s" % [companion_id, "joined" if active else "left"])


# =============================================================
# SKILL XP — learn-by-doing progression
# =============================================================
# Per design/SKILLS_AND_PROGRESSION.md:
#   Four domains: COMBAT, VITALITY, CRAFTING, EXPLORATION
#   Each has sub-skills (e.g. crafting/mining, crafting/felling)
#   Tier names: Novice / Trained / Veteran / Master
#
# Storage uses string keys "<domain>/<sub_skill>" because dictionary
# keys are easier to debug than enum-int pairs and survive JSON
# round-tripping cleanly. Sub-skill names are lowercase strings.
#
# Roland's Crafting domain right now has four sub-skills wired:
#   crafting/mining       — pickaxe on rock/ore voxels
#   crafting/felling      — axe on wood voxels
#   crafting/excavation   — shovel on dirt/sand/clay/ash voxels
#   crafting/demolition   — explosives + spell terrain effects
#
# Award XP via add_skill_xp(SkillDomain.CRAFTING, "mining", 5).
# Tier thresholds match design/SKILLS_AND_PROGRESSION.md Section
# "How Skill Progress is Tracked".

enum SkillDomain { COMBAT, VITALITY, CRAFTING, EXPLORATION }

const TIER_NAMES: Array = ["Novice", "Trained", "Veteran", "Master"]

# Tier thresholds per domain — total XP needed to enter each tier.
# Index = tier (0=Novice, 1=Trained, 2=Veteran, 3=Master).
const TIER_THRESHOLDS: Dictionary = {
	SkillDomain.COMBAT:      [0, 300, 700, 1200],
	SkillDomain.VITALITY:    [0, 200, 500, 900],
	SkillDomain.CRAFTING:    [0, 150, 400, 800],
	SkillDomain.EXPLORATION: [0, 250, 600, 1000],
}

# In-memory storage. Keys: "0/mining", "2/parry_success", etc.
# (the leading int is the SkillDomain enum value).
var _skill_xp: Dictionary = {}

# Fired after every XP award. UI listeners can subscribe to update
# the Skills tab in real time without polling.
signal skill_xp_changed(domain: int, sub_skill: String, new_xp: int)

func add_skill_xp(domain: int, sub_skill: String, amount: int) -> void:
	# Award amount XP to a sub-skill under a domain. Idempotent in
	# the sense that calling repeatedly just stacks XP; no caps until
	# the design adds them.
	var key: String = "%d/%s" % [domain, sub_skill]
	var current: int = _skill_xp.get(key, 0)
	var new_value: int = current + amount
	_skill_xp[key] = new_value
	skill_xp_changed.emit(domain, sub_skill, new_value)
	print("[GameState] Skill XP: %s += %d (total %d)" % [key, amount, new_value])

func get_skill_xp(domain: int, sub_skill: String) -> int:
	# Returns 0 for any (domain, sub_skill) Roland has never earned.
	return _skill_xp.get("%d/%s" % [domain, sub_skill], 0)

func get_domain_total_xp(domain: int) -> int:
	# Sums every sub-skill XP under a domain. Used for tier rollup.
	var prefix: String = "%d/" % domain
	var total: int = 0
	for key in _skill_xp.keys():
		if key.begins_with(prefix):
			total += _skill_xp[key]
	return total

func get_skill_tier(domain: int) -> String:
	# Returns the tier name string for the given domain based on
	# total XP across all its sub-skills.
	var total: int = get_domain_total_xp(domain)
	var thresholds: Array = TIER_THRESHOLDS.get(domain, [0])
	var tier_index: int = 0
	for i in range(thresholds.size()):
		if total >= thresholds[i]:
			tier_index = i
		else:
			break
	return TIER_NAMES[tier_index]


# =============================================================
# CURRENT ENEMY
# =============================================================
# Set this to an EnemyData resource before calling
# TransitionManager.change_scene("res://scenes/Combat.tscn").
# Combat.gd reads it in _ready() to configure the fight.

var current_enemy_data = null  # Holds an EnemyData resource, or null for defaults


# =============================================================
# SAVE AND LOAD — NAMED FILES
# =============================================================
# Saves are stored as JSON files in user://saves/, one per save.
# Each file's basename is a slugified version of the player-given
# save name; the full display name is stored inside the JSON.
#
# Examples:
#   "First Cave"         → user://saves/first_cave.json
#   "Roland Day 3"       → user://saves/roland_day_3.json
#
# "user://" is a Godot shorthand for the OS user data folder:
#   Windows: %APPDATA%\Godot\app_userdata\Game One\
#   Linux:   ~/.local/share/godot/app_userdata/Game One/
#   Mac:     ~/Library/Application Support/Godot/app_userdata/Game One/
#
# The PauseMenu Save button opens a small dialog asking the player
# to name the save; the Load button opens a picker overlay that
# lists every save with its name, last-played timestamp, and the
# coordinates Roland was at when the save was taken.

const SAVES_DIR: String = "user://saves/"

# Legacy slot-file path — kept only for backward-compat detection.
const LEGACY_SAVE_PATH: String = "user://save.json"

# The most-recently saved or loaded filename. Used by autosave-on-
# quit and as the default "current save" reference.
var active_save_filename: String = ""


func _ensure_saves_dir() -> void:
	# Create user://saves/ on first use. DirAccess.make_dir_absolute
	# silently no-ops if the directory already exists.
	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		DirAccess.make_dir_absolute(SAVES_DIR)


func _slugify(name: String) -> String:
	# Convert a display name into a filesystem-safe slug.
	# "My Save 1!" → "my_save_1"
	# Empty or all-symbols → "untitled"
	var s := name.to_lower().strip_edges()
	var out := ""
	for i in range(s.length()):
		var c := s[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		elif c == " " or c == "_" or c == "-":
			out += "_"
	# Collapse repeated underscores so "  hi  " doesn't become "__hi__".
	while out.find("__") != -1:
		out = out.replace("__", "_")
	out = out.trim_prefix("_").trim_suffix("_")
	if out.is_empty():
		out = "untitled"
	return out


func save_path_for_name(save_name: String) -> String:
	return SAVES_DIR + _slugify(save_name) + ".json"


func _capture_player_position() -> Vector3:
	# Pull the live player's world position via group lookup so the
	# save reflects exactly where Roland was when the player hit save.
	# Falls back to the cached player_position if no player is in
	# the scene tree (e.g. on a main-menu save attempt).
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return player_position
	var player: Node3D = players[0] as Node3D
	if player == null:
		return player_position
	return player.global_position


func save_game(save_name: String = "") -> bool:
	# Write the current game state to user://saves/{slug}.json.
	#
	# save_name: the human-readable name shown in the load picker.
	# Empty string is auto-replaced with a timestamp-based default.
	#
	# Returns true on success, false on failure (path error, write
	# failure). The PauseMenu shows a toast on success.
	_ensure_saves_dir()

	if save_name.strip_edges() == "":
		save_name = "Save %s" % Time.get_datetime_string_from_system()

	# Capture the live player position before serializing.
	player_position = _capture_player_position()

	# Flush in-memory voxel edits to the SQLite stream so the save
	# captures all the digging / explosions the player has done up
	# to this moment. Without this, edits stay in Zylann's RAM and
	# are only written periodically — saving + immediately reloading
	# would lose recent edits.
	if get_node_or_null("/root/VoxelEditManager"):
		VoxelEditManager.flush_pending_edits()

	# Stamp the current voxel generator version. Mismatch on load
	# is a hard error (see load_save_file). Defaults to 0 if the
	# VoxelEditManager autoload isn't available.
	var voxel_gen_version: int = 0
	if get_node_or_null("/root/VoxelEditManager"):
		voxel_gen_version = VoxelEditManager.WORLD_GENERATOR_VERSION

	var data: Dictionary = {
		"version": 4,
		"save_name": save_name,
		"timestamp": Time.get_datetime_string_from_system(),
		"unix_time": Time.get_unix_time_from_system(),
		"play_time_seconds": _play_time_seconds,
		"player_position": {
			"x": player_position.x,
			"y": player_position.y,
			"z": player_position.z,
		},
		"current_scene": current_scene,
		"flags": _flags.duplicate(),
		"companions": _companions.duplicate(),
		"skill_xp": _skill_xp.duplicate(),
		"voxel_generator_version": voxel_gen_version,
	}

	if get_node_or_null("/root/InventoryManager"):
		data["inventory"] = InventoryManager.get_save_data()

	var path: String = save_path_for_name(save_name)
	var json_string: String = JSON.stringify(data, "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[GameState] Could not write save file: " + path)
		return false
	file.store_string(json_string)
	file.close()
	active_save_filename = path.get_file()
	print("[GameState] Saved '%s' → %s" % [save_name, path])
	if get_node_or_null("/root/SaveNotification"):
		SaveNotification.show_notification()
	return true


func load_save_file(filename: String) -> bool:
	# Loads a save by filename (just the basename, e.g. "first_cave.json").
	# Returns true on success, false on missing file / parse error / version
	# mismatch.
	_ensure_saves_dir()
	var path: String = SAVES_DIR + filename
	if not FileAccess.file_exists(path):
		# Legacy fallback: try the user://save.json path from the old
		# slot-based system if the named file doesn't exist.
		if FileAccess.file_exists(LEGACY_SAVE_PATH) and filename == LEGACY_SAVE_PATH.get_file():
			path = LEGACY_SAVE_PATH
		else:
			push_warning("[GameState] No save file found: " + path)
			return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[GameState] Could not open save file: " + path)
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed == null:
		push_error("[GameState] Save file JSON is malformed: " + path)
		return false
	var data: Dictionary = parsed

	# --- Voxel generator version check (HARD ERROR on mismatch) ---
	if data.has("voxel_generator_version") and get_node_or_null("/root/VoxelEditManager"):
		var saved_ver: int = int(data["voxel_generator_version"])
		var current_ver: int = VoxelEditManager.WORLD_GENERATOR_VERSION
		if saved_ver != current_ver:
			push_error("[GameState] Save was made with terrain generator v%d but current is v%d. Cannot load — the procedural baseline has changed and player voxel edits would no longer match the world." % [saved_ver, current_ver])
			return false

	# --- Restore state ---
	if data.has("player_position"):
		var p: Dictionary = data["player_position"]
		player_position = Vector3(
			float(p.get("x", 0.0)),
			float(p.get("y", 0.0)),
			float(p.get("z", 0.0)),
		)
	if data.has("current_scene"):
		current_scene = data["current_scene"]
	if data.has("flags"):
		_flags = data["flags"]
	if data.has("companions"):
		for key in data["companions"]:
			_companions[key] = data["companions"][key]
	if data.has("skill_xp"):
		_skill_xp = data["skill_xp"]
	if data.has("inventory") and get_node_or_null("/root/InventoryManager"):
		InventoryManager.load_save_data(data["inventory"])

	active_save_filename = filename
	var save_label: String = data.get("save_name", filename)
	print("[GameState] Loaded '%s'. Flags: %d, Skill XP entries: %d" % [save_label, _flags.size(), _skill_xp.size()])
	return true


func delete_save_file(filename: String) -> bool:
	var path: String = SAVES_DIR + filename
	if not FileAccess.file_exists(path):
		return false
	var err: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if err == OK:
		print("[GameState] Deleted save: " + filename)
		if active_save_filename == filename:
			active_save_filename = ""
		return true
	push_error("[GameState] Failed to delete save: " + filename)
	return false


func list_save_files() -> Array:
	# Returns an array of metadata dictionaries for every save file
	# in user://saves/. Used by the load picker UI to populate the
	# list. Sorted by unix_time descending (newest first).
	#
	# Each entry has:
	#   filename:       String  — basename, used by load_save_file
	#   save_name:      String  — human-readable display name
	#   timestamp:      String  — ISO datetime when the save was made
	#   unix_time:      int     — for sorting
	#   player_position: Vector3
	#   current_scene:  String
	#   play_time_seconds: float
	_ensure_saves_dir()
	var saves: Array = []
	var dir := DirAccess.open(SAVES_DIR)
	if dir == null:
		return saves
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var meta: Dictionary = _read_save_metadata(SAVES_DIR + fname)
			if not meta.is_empty():
				meta["filename"] = fname
				saves.append(meta)
		fname = dir.get_next()
	dir.list_dir_end()
	# Newest first.
	saves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.get("unix_time", 0) > b.get("unix_time", 0))
	return saves


func _read_save_metadata(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed == null:
		return {}
	var data: Dictionary = parsed
	var p: Dictionary = data.get("player_position", {})
	return {
		"save_name": data.get("save_name", path.get_file()),
		"timestamp": data.get("timestamp", "unknown"),
		"unix_time": int(data.get("unix_time", 0)),
		"player_position": Vector3(
			float(p.get("x", 0.0)),
			float(p.get("y", 0.0)),
			float(p.get("z", 0.0)),
		),
		"current_scene": data.get("current_scene", ""),
		"play_time_seconds": float(data.get("play_time_seconds", 0.0)),
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
