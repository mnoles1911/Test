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

	# Stamp the current voxel generator version. Mismatch on load
	# is a hard error (see load_game). Defaults to 0 if the
	# VoxelEditManager autoload isn't available — old / non-voxel
	# saves still load.
	var voxel_gen_version: int = 0
	if get_node_or_null("/root/VoxelEditManager"):
		voxel_gen_version = VoxelEditManager.WORLD_GENERATOR_VERSION

	var data: Dictionary = {
		"version": 3,
		"slot": slot,
		"timestamp": Time.get_datetime_string_from_system(),
		"play_time_seconds": _play_time_seconds,
		"player_position": {"x": player_position.x, "y": player_position.y},
		"current_scene": current_scene,
		"flags": _flags.duplicate(),
		"companions": _companions.duplicate(),
		"skill_xp": _skill_xp.duplicate(),
		"voxel_generator_version": voxel_gen_version,
	}

	# Include inventory state. Previously orphaned —
	# InventoryManager.get_save_data() existed but was never called
	# from save_game(). This was a pre-existing bug; fixing it here.
	if get_node_or_null("/root/InventoryManager"):
		data["inventory"] = InventoryManager.get_save_data()

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

	# --- Voxel generator version check (HARD ERROR on mismatch) ---
	# If the saved version doesn't match the current generator, the
	# procedural baseline has changed. Player voxel deltas in
	# voxel_deltas.sqlite no longer make sense relative to the new
	# baseline. Refuse to load rather than silently corrupt the
	# world. (Old saves without this field load fine — treated as
	# version 0 which matches the default if the autoload is absent.)
	if data.has("voxel_generator_version") and get_node_or_null("/root/VoxelEditManager"):
		var saved_ver: int = int(data["voxel_generator_version"])
		var current_ver: int = VoxelEditManager.WORLD_GENERATOR_VERSION
		if saved_ver != current_ver:
			push_error("[GameState] Save was made with terrain generator v%d but current is v%d. Cannot load — the procedural baseline has changed and player voxel edits would no longer match the world." % [saved_ver, current_ver])
			return

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
	if data.has("skill_xp"):
		_skill_xp = data["skill_xp"]
	if data.has("inventory") and get_node_or_null("/root/InventoryManager"):
		InventoryManager.load_save_data(data["inventory"])
	if data.has("slot"):
		active_save_slot = data["slot"]
	print("[GameState] Loaded slot %d. Flags: %d, Skill XP entries: %d" % [slot, _flags.size(), _skill_xp.size()])

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
