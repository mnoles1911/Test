extends Node
# CharacterStore — autoload for loading + saving portable characters.
#
# WHAT THIS IS (plain English):
#
#   The file-system layer for portable characters. Knows how to:
#     - List every character saved on this machine (for the
#       CharacterSelect UI's roster).
#     - Load a specific character by Steam ID.
#     - Save the working character back to disk.
#     - Create a new character for the local Steam ID.
#     - Delete a character.
#
# WHERE FILES LIVE:
#
#   user://characters/
#     index.tres                  — list of known character_ids
#                                   (sorted by last_played desc;
#                                   makes the UI fast without
#                                   stat'ing every .tres)
#     {steam_id_decimal}.tres     — one file per character
#
#   For MP-6 v1 we assume one character per Steam ID. Multi-character
#   support per Steam ID requires keying by character_id instead of
#   steam_id; the filename pattern + lookup logic can change without
#   touching CharacterRecord. The schema_version on CharacterRecord
#   tags the file so any migration knows which fields existed.
#
# AUTOLOAD ORDER:
#   Must load BEFORE InventoryManager. When MP-6 wires the runtime
#   integration, InventoryManager._ready calls
#   CharacterStore.get_active_character() and rehydrates its
#   ITEM_REGISTRY state from there. For MP-6 v1 the integration is
#   pure data — runtime hookup is a follow-up.
#
# WHAT'S DEFERRED FROM MP-6 v1:
#
#   - Runtime sync with InventoryManager. The store ships the data
#     model + I/O; bridging it into the live ITEM_REGISTRY state
#     requires touching ~6 call sites in InventoryManager. Filed
#     for a runtime-integration follow-up so reviewers can land the
#     storage layer first.
#
#   - Autosave during session. Plan calls for 60s autosave plus save
#     on clean disconnect / host save / graceful quit. The triggers
#     are listed but not wired in this PR — the data model lands
#     here so other systems can call save_character() once they're
#     ready to push state into the record.
#
#   - Steam ID resolution. The local Steam ID comes from
#     SteamP2PBackend.get_steam_id_for_peer(local_peer_id) once a
#     session is active, OR from Engine.get_singleton("Steam") +
#     getSteamID() if the Steam client is logged in. For local
#     LAN testing (no Steam) we fall back to a synthesized
#     "dev_user" ID. The "active Steam ID" concept is documented
#     here but is a read-only export until MP-7 wires the live
#     resolution.


# =============================================================
# CONFIG
# =============================================================

const CHARACTERS_DIR: String = "user://characters/"
const INDEX_PATH: String = "user://characters/index.tres"

## When no Steam client is available (LAN testing, headless), this
## is the synthesized "local user" Steam ID. Real Steam IDs are
## uint64 starting at 76561197960265728; using a low number means
## the dev fallback can't collide with a real account.
const DEV_FALLBACK_STEAM_ID: int = 1


# =============================================================
# STATE
# =============================================================

## In-memory cache of loaded records, keyed by steam_id. Avoid
## hitting disk twice during a session.
var _cache: Dictionary = {}

## The character the local player has selected for this session.
## Set by select_character() once the UI confirms a pick.
var _active_character: CharacterRecord = null


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	_ensure_characters_dir()


# =============================================================
# PUBLIC API
# =============================================================

## True if a character file exists for the given Steam ID.
func has_character(steam_id: int) -> bool:
	return FileAccess.file_exists(_path_for(steam_id))


## Load a character by Steam ID. Returns null if no file exists or
## the load fails. Cached after first load.
func load_character(steam_id: int) -> CharacterRecord:
	if _cache.has(steam_id):
		return _cache[steam_id]
	var path: String = _path_for(steam_id)
	if not FileAccess.file_exists(path):
		return null
	var loaded: Variant = ResourceLoader.load(path, "CharacterRecord", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null or not (loaded is CharacterRecord):
		push_warning("[CharacterStore] failed to load %s — file exists but unreadable" % path)
		return null
	var record: CharacterRecord = loaded
	_cache[steam_id] = record
	return record


## Save the given record to disk. Bumps last_played_unix to "now"
## so the index UI sorts it to the top. Idempotent — safe to call
## from autosave + on-disconnect + on-quit paths.
func save_character(record: CharacterRecord) -> Error:
	if record == null:
		push_warning("[CharacterStore] save_character: null record, skipping")
		return ERR_INVALID_PARAMETER
	if record.steam_id == 0:
		push_warning("[CharacterStore] save_character: record has steam_id=0; assigning fallback")
		record.steam_id = DEV_FALLBACK_STEAM_ID
	record.last_played_unix = Time.get_unix_time_from_system()
	_ensure_characters_dir()
	var path: String = _path_for(record.steam_id)
	var err: Error = ResourceSaver.save(record, path)
	if err != OK:
		push_warning("[CharacterStore] save_character: ResourceSaver returned %s for %s" % [err, path])
		return err
	# Refresh cache to ensure the next load sees the saved state.
	_cache[record.steam_id] = record
	return OK


## Create a brand-new character for the given Steam ID, save it,
## and set it active. Returns the new record.
func create_character(for_steam_id: int, display_name: String) -> CharacterRecord:
	var record := CharacterRecord.make_new(for_steam_id, display_name)
	save_character(record)
	_active_character = record
	return record


## Delete a character file. Idempotent. Returns OK if either the
## file didn't exist or removal succeeded.
func delete_character(steam_id: int) -> Error:
	_cache.erase(steam_id)
	if _active_character != null and _active_character.steam_id == steam_id:
		_active_character = null
	var path: String = _path_for(steam_id)
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Mark a loaded record as the local player's active character.
## The active character is what gets shipped in the handshake on
## host/join, and what gets saved during autosave / disconnect /
## graceful quit.
func select_character(record: CharacterRecord) -> void:
	_active_character = record


## The currently selected character, or null if none yet.
func get_active_character() -> CharacterRecord:
	return _active_character


## Enumerate every character file on disk. Returns an Array of
## { steam_id, display_name, last_played_unix } summaries — enough
## for a CharacterSelect roster without loading every record.
##
## For MP-6 v1 this just walks the directory; an index.tres
## optimisation lands in MP-8 polish if rosters get big.
func list_characters() -> Array:
	var summaries: Array = []
	_ensure_characters_dir()
	var dir: DirAccess = DirAccess.open(CHARACTERS_DIR)
	if dir == null:
		return summaries
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not fname.ends_with(".tres") or fname == "index.tres":
			fname = dir.get_next()
			continue
		var path: String = CHARACTERS_DIR + fname
		var rec: Variant = ResourceLoader.load(path, "CharacterRecord", ResourceLoader.CACHE_MODE_IGNORE)
		if rec is CharacterRecord:
			var r: CharacterRecord = rec
			summaries.append({
				"steam_id": r.steam_id,
				"display_name": r.display_name,
				"last_played_unix": r.last_played_unix,
				"character_id": r.character_id,
			})
		fname = dir.get_next()
	dir.list_dir_end()
	# Sort newest first.
	summaries.sort_custom(func(a, b): return int(a.get("last_played_unix", 0)) > int(b.get("last_played_unix", 0)))
	return summaries


## Resolve the local Steam ID. Tries (in order):
##   1. Active Steam singleton via Engine.get_singleton("Steam")
##   2. Project setting "multiplayer/dev_steam_id" (operator-set)
##   3. DEV_FALLBACK_STEAM_ID (so LAN ENet testing has a stable id)
##
## Returns int because Steam IDs are uint64 and Godot ints hold them.
func resolve_local_steam_id() -> int:
	if Engine.has_singleton("Steam"):
		var steam_obj: Object = Engine.get_singleton("Steam")
		if steam_obj.has_method("getSteamID"):
			var sid: int = int(steam_obj.call("getSteamID"))
			if sid != 0:
				return sid
	var override: Variant = ProjectSettings.get_setting("multiplayer/dev_steam_id", null)
	if override != null and int(override) != 0:
		return int(override)
	return DEV_FALLBACK_STEAM_ID


# =============================================================
# INTERNALS
# =============================================================

func _path_for(steam_id: int) -> String:
	return "%s%d.tres" % [CHARACTERS_DIR, steam_id]


func _ensure_characters_dir() -> void:
	# DirAccess.make_dir is idempotent — already-exists is OK.
	if not DirAccess.dir_exists_absolute(CHARACTERS_DIR):
		var err: Error = DirAccess.make_dir_recursive_absolute(CHARACTERS_DIR)
		if err != OK:
			push_warning("[CharacterStore] could not create %s (err %s)" % [CHARACTERS_DIR, err])
