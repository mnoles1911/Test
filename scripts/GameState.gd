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
var player_rotation_y: float = 0.0
# Player's facing direction in radians. Captured at save time from
# the live Player3D's rotation.y so the load drops Roland looking
# the same way he was looking when the save was taken.

var current_scene: String = ""
var player_spawn_id: String = ""
# player_spawn_id is the name of the SpawnPoint node the receiving scene
# should place the player at. Empty string = use the scene's default position.

var loading_voxel_save: bool = false
# Transient runtime flag — NOT persisted to the save JSON. The load-save
# path sets this true immediately before (re)loading World3D so
# World3DBootstrap KEEPS the working voxel SQLite (the saved world)
# instead of wiping it. Default false: a plain run of World3D.tscn is
# ALWAYS a fresh world — voxel edits never silently carry between runs.
# See World3DBootstrap._enter_tree / _wipe_working_session_db.


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

# =============================================================
# DEV-SCENE GUARD
# =============================================================

# Returns true when the currently-running scene is a developer test
# scene (e.g. scenes/_dev/BakeWorld.tscn, scenes/CopperIslesTest.tscn).
# Dev scenes opt in by adding their root to the "dev_scene" group in
# their _ready() — see CopperIslesTestBootstrap.gd / WorldBakeController.gd
# for the canonical pattern. UI autoloads (HUDOverlay, PauseMenu,
# JournalUI, SaveNotification) check this and skip rendering / input
# so the dev scene is uncluttered by gameplay chrome.
func is_dev_scene() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var scene := tree.current_scene
	if scene == null:
		return false
	return scene.is_in_group("dev_scene")


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
	# DEPRECATED: routes to the new flat 12-skill SkillManager when it
	# is loaded. The (domain, sub_skill) call sites in EditToolHandler
	# and PowderCharge are migrated in the same PR as the SkillManager
	# autoload; this shim keeps things working between commits and for
	# any future caller that hasn't been moved yet.
	var key: String = "%d/%s" % [domain, sub_skill]
	var current: int = _skill_xp.get(key, 0)
	var new_value: int = current + amount
	_skill_xp[key] = new_value
	skill_xp_changed.emit(domain, sub_skill, new_value)
	# Forward to the new system if available.
	if get_node_or_null("/root/SkillManager"):
		SkillManager.legacy_route(domain, sub_skill, amount)

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
# FLAT 12-SKILL STATE (new system — SkillManager-owned)
# =============================================================
# These dictionaries back SkillManager. We keep them on GameState
# instead of a dedicated CharacterRecord because MP-6 (the resource
# that will eventually own per-character state) hasn't landed yet.
# When it does, SkillManager swaps the backing store without changing
# its public API; these fields stay only for migration of old saves.

var _skill_levels: Dictionary = {}        # skill_name -> int (1..100)
var _skill_xp_progress: Dictionary = {}   # skill_name -> float (XP toward next level)
var _owned_perks: Dictionary = {}         # perk_id -> true (set semantics on a dict)
var _perk_points_unspent: int = 0
var _legendary_resets: Dictionary = {}    # skill_name -> int
var _faction_dispositions: Dictionary = {}  # faction_id -> int 0..100
var _trainer_visits: Dictionary = {}      # trainer_id -> Dictionary[skill, int]

signal skill_level_changed(skill: String, new_level: int)

func ensure_skill_initialized(skill: String) -> void:
	if not _skill_levels.has(skill):
		_skill_levels[skill] = 1
	if not _skill_xp_progress.has(skill):
		_skill_xp_progress[skill] = 0.0

func get_skill_level(skill: String) -> int:
	return int(_skill_levels.get(skill, 1))

func get_skill_xp_progress(skill: String) -> float:
	return float(_skill_xp_progress.get(skill, 0.0))

func set_skill_state(skill: String, level: int, progress: float) -> void:
	var prev: int = int(_skill_levels.get(skill, 1))
	_skill_levels[skill] = level
	_skill_xp_progress[skill] = progress
	if level != prev:
		skill_level_changed.emit(skill, level)

func get_owned_perks() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for pid in _owned_perks.keys():
		out.append(pid)
	return out

func has_perk(perk_id: String) -> bool:
	return _owned_perks.has(perk_id)

func add_owned_perk(perk_id: String) -> void:
	_owned_perks[perk_id] = true

func remove_owned_perk(perk_id: String) -> void:
	_owned_perks.erase(perk_id)

func get_perk_points_unspent() -> int:
	return _perk_points_unspent

func set_perk_points_unspent(n: int) -> void:
	_perk_points_unspent = max(0, n)

func increment_legendary_reset(skill: String) -> int:
	var c: int = int(_legendary_resets.get(skill, 0)) + 1
	_legendary_resets[skill] = c
	return c

func get_legendary_reset_count(skill: String) -> int:
	return int(_legendary_resets.get(skill, 0))

# Faction disposition (0..100). Pre-game disposition for most factions
# is in the 30-50 range; trainers gate at >= 75 (Friendly).
func get_faction_disposition(faction_id: String) -> int:
	return int(_faction_dispositions.get(faction_id, 30))

func set_faction_disposition(faction_id: String, value: int) -> void:
	_faction_dispositions[faction_id] = clamp(value, 0, 100)

func modify_faction_disposition(faction_id: String, delta: int) -> int:
	var cur: int = get_faction_disposition(faction_id)
	var next: int = clamp(cur + delta, 0, 100)
	_faction_dispositions[faction_id] = next
	return next

# Trainer visit cap (per-Act, per-skill, per-trainer).
func get_trainer_visits(trainer_id: String, skill: String) -> int:
	var d: Dictionary = _trainer_visits.get(trainer_id, {})
	return int(d.get(skill, 0))

func increment_trainer_visits(trainer_id: String, skill: String) -> int:
	var d: Dictionary = _trainer_visits.get(trainer_id, {})
	var c: int = int(d.get(skill, 0)) + 1
	d[skill] = c
	_trainer_visits[trainer_id] = d
	return c

func reset_trainer_visits_for_new_act() -> void:
	_trainer_visits.clear()


# =============================================================
# CURRENT ENEMY
# =============================================================
# Set this to an EnemyData resource before calling
# TransitionManager.change_scene("res://scenes/Combat.tscn").
# Combat.gd reads it in _ready() to configure the fight.

var current_enemy_data = null  # Holds an EnemyData resource, or null for defaults


# =============================================================
# NEW GAME RESET
# =============================================================
# Called when the player clicks NEW GAME from the main menu.
# Clears every piece of session state that persists across scene
# transitions in autoloads — without this, a "New Game" inherits
# voxel edits, flags, inventory, skill XP, and player position
# from the previous playthrough running in the same Godot session.
#
# What gets reset:
#   - GameState in-memory state (flags, companions, skill XP,
#     position, rotation, scene refs, play time, active save)
#   - InventoryManager (clears inventory + equipped slots, then
#     re-applies the debug starting kit: pickaxe + 5 charges)
#   - Voxel deltas on disk (user://voxel_deltas.sqlite plus
#     Zylann's auxiliary -journal / -wal / -shm files)
#
# What does NOT get reset (preserved across playthroughs):
#   - Saved files in user://saves/ — players manage those by name
#     via the load picker
#   - Settings (display, audio, controls) — player preferences
#   - The randomly-loaded menu background

func reset_for_new_game() -> void:
	_flags.clear()
	_flag_history.clear()
	_skill_xp.clear()
	_skill_levels.clear()
	_skill_xp_progress.clear()
	_owned_perks.clear()
	_perk_points_unspent = 0
	_legendary_resets.clear()
	_faction_dispositions.clear()
	_trainer_visits.clear()
	_companions = {
		"orion":  false,
		"dagna":  false,
		"corvus": false,
		"seren":  false,
		"aldric": false,
	}
	player_position = Vector3.ZERO
	player_rotation_y = 0.0
	player_spawn_id = ""
	current_scene = ""
	active_save_filename = ""
	active_save_display_name = ""
	last_save_unix_time = 0
	_play_time_seconds = 0.0

	_delete_voxel_deltas_files()

	if get_node_or_null("/root/InventoryManager"):
		InventoryManager.reset_to_defaults()

	# Reset the in-game clock to 8:00 AM Day 1. Without this the clock
	# keeps ticking from the previous playthrough's last saved time.
	if get_node_or_null("/root/WorldClock"):
		WorldClock.current_day = 1
		WorldClock.set_time(8, 0)

	print("[GameState] Reset for new game.")


func _delete_voxel_deltas_files() -> void:
	# Delete voxel_deltas.sqlite plus any Zylann SQLite auxiliary
	# files (-journal, -wal, -shm). Without removing the journals,
	# SQLite may recreate the database from them on next open and
	# resurrect the deleted edits.
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	var deleted: int = 0
	while fname != "":
		if not dir.current_is_dir() and fname.begins_with(VOXEL_DELTAS_BASENAME):
			var abs_path: String = ProjectSettings.globalize_path("user://" + fname)
			var err: int = DirAccess.remove_absolute(abs_path)
			if err == OK:
				deleted += 1
				print("[GameState] Deleted: %s" % fname)
			else:
				push_warning("[GameState] Failed to delete %s (err %d)" % [fname, err])
		fname = dir.get_next()
	dir.list_dir_end()
	print("[GameState] Cleared %d voxel-delta file(s)." % deleted)


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

# Voxel-edit-delta SQLite database path. Must match the
# database_path on the VoxelStreamSQLite sub_resource in
# scenes/World3D.tscn — wiping this file (and Zylann's
# auxiliary -journal / -wal / -shm files) on New Game gives
# the player a clean baseline.
const VOXEL_DELTAS_BASENAME: String = "voxel_deltas_v10.sqlite"
# Renamed from "voxel_deltas.sqlite" at the 10 vox/m pivot (2026-06-12)
# so any stale 6 vox/m delta file on disk becomes inert instead of
# painting wrong-scale edits into the new world.

# The most-recently saved or loaded filename. Used by autosave-on-
# quit and as the default "current save" reference.
var active_save_filename: String = ""

# Display name of the active save (the human-readable name typed
# into the save dialog or shown in the load picker). Pre-fills
# the save dialog's text field on the next manual save so the
# player can hit Enter to overwrite the same named save without
# re-typing — e.g. "Roland Day 1" stays "Roland Day 1" until the
# player explicitly renames it.
var active_save_display_name: String = ""

# Unix timestamp of the most recent successful save (any kind).
# Used by PauseMenu to suppress the redundant auto-save on EXIT
# TO MENU / QUIT when the player already saved very recently.
var last_save_unix_time: int = 0


func seconds_since_last_save() -> int:
	# Returns how many seconds since save_game succeeded last,
	# or a very large number if the player has never saved this
	# session. Callers use this to gate auto-save logic.
	if last_save_unix_time == 0:
		return 999999
	return int(Time.get_unix_time_from_system()) - last_save_unix_time


func _ensure_saves_dir() -> void:
	# Create user://saves/ on first use. DirAccess.make_dir_absolute
	# silently no-ops if the directory already exists.
	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		DirAccess.make_dir_absolute(SAVES_DIR)


func _slugify(display_name: String) -> String:
	# Convert a display name into a filesystem-safe slug.
	# "My Save 1!" → "my_save_1"
	# Empty or all-symbols → "untitled"
	#
	# Parameter is named display_name (not name) because Node has a
	# `name` property — using `name` here would shadow it and emit
	# a SHADOWED_VARIABLE_BASE_CLASS warning at parse time.
	var s := display_name.to_lower().strip_edges()
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


func _capture_player_rotation_y() -> float:
	# Y rotation in radians (the only rotation axis Player3D uses
	# — pitch and roll live on the camera, not the body). Captured
	# at save time so reload preserves which way Roland was looking.
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return player_rotation_y
	var player: Node3D = players[0] as Node3D
	if player == null:
		return player_rotation_y
	return player.rotation.y


const MAX_AUTOSAVES: int = 5
# Hard cap on simultaneous autosaves on disk. After every autosave
# write, the oldest autosaves beyond this count are deleted (FIFO
# eviction). Named saves (is_autosave == false) are never pruned;
# the player manages those by name via the load picker's DELETE
# button.

func save_game(save_name: String = "", is_autosave: bool = false) -> bool:
	# Write the current game state to user://saves/{slug}.json.
	#
	# save_name: the human-readable name shown in the load picker.
	#   Empty string is auto-replaced with a timestamp-based default.
	# is_autosave: marks this save as an autosave for FIFO pruning
	#   (max MAX_AUTOSAVES kept). Named saves pass false here and
	#   accumulate freely until the player manually deletes them.
	#
	# Returns true on success, false on failure (path error, write
	# failure). The PauseMenu shows a toast on success.
	_ensure_saves_dir()

	if save_name.strip_edges() == "":
		save_name = "Save %s" % Time.get_datetime_string_from_system()

	# Capture the live player position + facing direction before
	# serializing. _capture_* helpers fall back to cached values
	# if no player exists in the scene tree.
	player_position = _capture_player_position()
	player_rotation_y = _capture_player_rotation_y()

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
		"version": 5,
		"save_name": save_name,
		"is_autosave": is_autosave,
		"timestamp": Time.get_datetime_string_from_system(),
		"unix_time": Time.get_unix_time_from_system(),
		"play_time_seconds": _play_time_seconds,
		"player_position": {
			"x": player_position.x,
			"y": player_position.y,
			"z": player_position.z,
		},
		"player_rotation_y": player_rotation_y,
		"current_scene": current_scene,
		"flags": _flags.duplicate(),
		"companions": _companions.duplicate(),
		"skill_xp": _skill_xp.duplicate(),
		"skill_levels": _skill_levels.duplicate(),
		"skill_xp_progress": _skill_xp_progress.duplicate(),
		"owned_perks": _owned_perks.duplicate(),
		"perk_points_unspent": _perk_points_unspent,
		"legendary_resets": _legendary_resets.duplicate(),
		"faction_dispositions": _faction_dispositions.duplicate(),
		"trainer_visits": _trainer_visits.duplicate(),
		"voxel_generator_version": voxel_gen_version,
	}

	if get_node_or_null("/root/InventoryManager"):
		data["inventory"] = InventoryManager.get_save_data()

	# Phase 5+ (Minecraft-style ocean): water lives in CHANNEL_DATA and
	# persists via the chunk SQLite stream alongside terrain edits, so
	# nothing extra needs to go in the JSON save. Old saves (pre-v13)
	# wrote a "water_sources" array; new saves omit it. Loaders ignore
	# missing keys, so this is forward-compatible — and the v13
	# WORLD_GENERATOR_VERSION rejection at load already guarantees no
	# pre-v13 save can reach this code path.

	# Weather state — current/target state, override timer. Compact dict;
	# missing keys read as defaults on load so older saves stay valid.
	if get_node_or_null("/root/WeatherManager"):
		data["weather"] = WeatherManager.get_save_data()

	var path: String = save_path_for_name(save_name)
	var json_string: String = JSON.stringify(data, "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[GameState] Could not write save file: " + path)
		return false
	file.store_string(json_string)
	file.close()
	active_save_filename = path.get_file()
	last_save_unix_time = int(Time.get_unix_time_from_system())
	# Only update the display-name reference for NAMED saves —
	# autosave names ("[Auto] <timestamp>") shouldn't pre-fill the
	# next manual save dialog. The player wants to keep editing
	# their named save's name across sessions.
	if not is_autosave:
		active_save_display_name = save_name
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("%s save: '%s'" % [
			"AUTO" if is_autosave else "Named", save_name
		])
	else:
		print("[GameState] Saved '%s' → %s" % [save_name, path])
	if get_node_or_null("/root/SaveNotification"):
		SaveNotification.show_notification()

	# After an autosave write succeeds, prune old autosaves so disk
	# usage stays bounded. Named saves are not affected.
	if is_autosave:
		_prune_autosaves(MAX_AUTOSAVES)

	return true


func _prune_autosaves(max_keep: int) -> void:
	# Lists every save flagged is_autosave, sorts newest-first
	# (list_save_files already does this), and deletes everything
	# past max_keep. The just-written autosave is the newest and
	# therefore always retained.
	var autosaves: Array = []
	for s in list_save_files():
		if s.get("is_autosave", false):
			autosaves.append(s)
	if autosaves.size() <= max_keep:
		return
	for entry in autosaves.slice(max_keep):
		var fname: String = entry.get("filename", "")
		if fname == "":
			continue
		print("[GameState] Pruning old autosave: %s" % fname)
		delete_save_file(fname)


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
	if data.has("player_rotation_y"):
		player_rotation_y = float(data["player_rotation_y"])
	if data.has("current_scene"):
		current_scene = data["current_scene"]
	if data.has("flags"):
		_flags = data["flags"]
	if data.has("companions"):
		for key in data["companions"]:
			_companions[key] = data["companions"][key]
	if data.has("skill_xp"):
		_skill_xp = data["skill_xp"]
	# Flat 12-skill state. Pre-skill-PR saves omit these keys; loaders
	# leave the fields empty and SkillManager initializes defaults on
	# first XP grant.
	_skill_levels = data.get("skill_levels", {})
	_skill_xp_progress = data.get("skill_xp_progress", {})
	_owned_perks = data.get("owned_perks", {})
	_perk_points_unspent = int(data.get("perk_points_unspent", 0))
	_legendary_resets = data.get("legendary_resets", {})
	_faction_dispositions = data.get("faction_dispositions", {})
	_trainer_visits = data.get("trainer_visits", {})
	if get_node_or_null("/root/SkillManager"):
		# Re-instantiate any owned active perks against the loaded state.
		SkillManager._rebuild_active_instances()
	if data.has("inventory") and get_node_or_null("/root/InventoryManager"):
		InventoryManager.load_save_data(data["inventory"])

	# Phase 5+: water lives in CHANNEL_DATA and reloads with the chunk
	# SQLite. The only thing to clear here is the transient flow-cell
	# dict so stale in-memory state from the previous session doesn't
	# leak. The legacy "water_sources" load path is gone — pre-v13 saves
	# can't reach this code (rejected by the version check above).
	if get_node_or_null("/root/WaterFlowManager"):
		WaterFlowManager.clear_persistent_state()

	# Reset and reload weather state. clear_persistent_state hands the
	# fresh world to the schedule-driven path; load_save_data restores
	# any in-flight override timer from the saved value.
	if get_node_or_null("/root/WeatherManager"):
		WeatherManager.clear_persistent_state()
		if data.has("weather"):
			WeatherManager.load_save_data(data["weather"])

	# Resume the total-play-time counter from the saved value. Without
	# this, "time in game since inception" would reset to 0 every load.
	if data.has("play_time_seconds"):
		_play_time_seconds = float(data["play_time_seconds"])

	# WorldClock writes its time into _flags every minute, so restoring
	# _flags above already brought the saved hour/minute/day back into
	# GameState. But WorldClock keeps its own in-memory copy that needs
	# to re-read those flags before the next tick — otherwise the clock
	# keeps ticking from wherever it was when load was clicked.
	if get_node_or_null("/root/WorldClock"):
		WorldClock.load_from_state()

	active_save_filename = filename
	var save_label: String = data.get("save_name", filename)
	# If the loaded save is a NAMED save, remember its display name
	# so the next manual save dialog pre-fills with the same text
	# (Roland Day 1 → quick edit → Save again as Roland Day 2).
	# Autosaves don't pre-fill — the player names their next save
	# from a clean slate.
	if not bool(data.get("is_autosave", false)):
		active_save_display_name = save_label
	else:
		active_save_display_name = ""
	last_save_unix_time = int(Time.get_unix_time_from_system())
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Loaded save: '%s'" % save_label)
	else:
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


func delete_all_save_files() -> int:
	# Wipes every .json file under user://saves/ and returns the
	# count of files removed. Used by the F1 debug overlay's
	# "DELETE ALL SAVES" button. Voxel deltas (the SQLite file)
	# are NOT touched here — that's a separate concern; the player
	# may want to keep the in-progress world but reset the save
	# slot list. To wipe BOTH, click NEW GAME from the main menu.
	_ensure_saves_dir()
	var dir := DirAccess.open(SAVES_DIR)
	if dir == null:
		return 0
	var deleted: int = 0
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var abs_path: String = ProjectSettings.globalize_path(SAVES_DIR + fname)
			var err: int = DirAccess.remove_absolute(abs_path)
			if err == OK:
				deleted += 1
		fname = dir.get_next()
	dir.list_dir_end()
	active_save_filename = ""
	print("[GameState] Deleted %d save file(s)." % deleted)
	return deleted


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
		"is_autosave": bool(data.get("is_autosave", false)),
		"timestamp": data.get("timestamp", "unknown"),
		"unix_time": int(data.get("unix_time", 0)),
		"player_position": Vector3(
			float(p.get("x", 0.0)),
			float(p.get("y", 0.0)),
			float(p.get("z", 0.0)),
		),
		"player_rotation_y": float(data.get("player_rotation_y", 0.0)),
		"current_scene": data.get("current_scene", ""),
		"play_time_seconds": float(data.get("play_time_seconds", 0.0)),
	}


# =============================================================
# PLAY TIME TRACKING
# =============================================================

var _play_time_seconds: float = 0.0

func _process(delta: float) -> void:
	_play_time_seconds += delta


## Returns total wall-clock seconds the player has been in this run,
## across all sessions (accumulated and persisted via save/load).
func get_play_time_seconds() -> float:
	return _play_time_seconds


## Returns total play time formatted as "Hh Mm Ss".
## Drops the leading hours when zero, e.g. "12m 04s".
func get_play_time_string() -> String:
	var total: int = int(_play_time_seconds)
	# Integer division is intentional — we want whole hours and minutes.
	@warning_ignore("integer_division")
	var hours: int = total / 3600
	@warning_ignore("integer_division")
	var minutes: int = (total % 3600) / 60
	var seconds: int = total % 60
	if hours > 0:
		return "%dh %02dm %02ds" % [hours, minutes, seconds]
	return "%dm %02ds" % [minutes, seconds]


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	print("[GameState] Initialized.")
