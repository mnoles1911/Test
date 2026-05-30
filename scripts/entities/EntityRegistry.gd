extends Node
# EntityRegistry — persistent per-chunk store of every world entity.
#
# Sits next to VoxelStreamSQLite (which stores terrain edits) as the
# canonical record of WHO is in the world and WHERE — NPCs, enemies,
# dropped items, etc. EntityStreamer reads it on chunk load to spawn
# the right scene instances, and writes back to it on chunk evict so
# state survives the player walking away.
#
# Data model:
#   _records_by_chunk : Dictionary[Vector2i, Array[EntityRecord]]
#   _by_id            : Dictionary[String,   EntityRecord]
#
# Chunk key = floor(pos.x / CHUNK_M), floor(pos.z / CHUNK_M)  (CHUNK_M=16m).
# We use the same horizontal-chunk key EntityStreamer uses so there's a
# single coordinate system. Vertical is folded into pos.y on the record.
#
# Persistence: JSON sidecar at `user://saves/slot_{N}/entities.json`.
# Picked over VoxelStreamSQLite because (a) it's the same lifecycle as
# the save-slot directory the rest of the project uses and (b) JSON is
# trivially diff-able when debugging save corruption.

const EntityRecord := preload("res://scripts/entities/EntityRecord.gd")

# Same chunk size EntityStreamer uses. Must match.
const CHUNK_M: int = 16

# In-memory state. _records_by_chunk holds the live records (one entity
# may appear in exactly one chunk). _by_id is a fast-path lookup.
var _records_by_chunk: Dictionary = {}      # Vector2i -> Array[EntityRecord]
var _by_id: Dictionary = {}                 # String   -> EntityRecord
# Monotonic ID counter — combined with a session prefix so IDs are unique
# across save loads (we never reuse a freed slot).
var _next_id: int = 0
var _session_prefix: String = ""


# ============================================================
# Lifecycle
# ============================================================

func _ready() -> void:
	# Generate a per-session prefix so the same world loaded twice doesn't
	# collide IDs across sessions if the user later imports/merges saves.
	# get_unix_time_from_system returns a float; cast to int for the
	# modulo (% doesn't accept float operands).
	_session_prefix = "e_%d_" % (int(Time.get_unix_time_from_system()) % 1000000)
	print("[EntityRegistry] Ready — session prefix '%s'." % _session_prefix)


# ============================================================
# World coordinate helpers
# ============================================================

static func chunk_key_for_position(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / float(CHUNK_M))),
	                int(floor(pos.z / float(CHUNK_M))))


# ============================================================
# Public API — register / update / unregister
# ============================================================

# Register a brand-new record (or re-register an existing one moved between
# chunks). Assigns an entity_id if missing. Returns the (possibly newly-
# generated) id. `record` is an EntityRecord (untyped because the script
# has no class_name — see EntityRecord.gd header).
func register(record) -> String:
	if record == null:
		push_warning("[EntityRegistry] register(null) — ignored.")
		return ""
	if record.entity_id == "":
		record.entity_id = _generate_id()
	# If we already have this id, update is the right call — but the
	# common case is fresh register, so handle that first.
	if _by_id.has(record.entity_id):
		# Re-register == update (handles moved chunk too).
		update(record)
		return record.entity_id
	_by_id[record.entity_id] = record
	_index_record(record)
	return record.entity_id


# Update an existing record's chunk indexing — call after changing its
# position. If the record isn't yet registered, treats it as a new one.
func update(record: EntityRecord) -> void:
	if record == null or record.entity_id == "":
		return
	if not _by_id.has(record.entity_id):
		register(record)
		return
	_deindex_record(record.entity_id)
	_by_id[record.entity_id] = record  # in case fields were re-assigned
	_index_record(record)


# Remove a record. Idempotent.
func unregister(entity_id: String) -> void:
	if entity_id == "" or not _by_id.has(entity_id):
		return
	_deindex_record(entity_id)
	_by_id.erase(entity_id)


func get_record(entity_id: String) -> EntityRecord:
	return _by_id.get(entity_id, null)


# Returns the array of records in the named chunk. Empty array if none.
# The returned array is a COPY — modifying it doesn't affect the index.
func records_in_chunk(chunk_key: Vector2i) -> Array[EntityRecord]:
	var out: Array[EntityRecord] = []
	var bucket: Variant = _records_by_chunk.get(chunk_key, null)
	if bucket is Array:
		for rec in bucket:
			if rec is EntityRecord:
				out.append(rec)
	return out


func record_count() -> int:
	return _by_id.size()


func chunk_count() -> int:
	return _records_by_chunk.size()


# ============================================================
# Internals — chunk indexing
# ============================================================

func _index_record(record: EntityRecord) -> void:
	var key: Vector2i = chunk_key_for_position(record.position)
	var bucket: Array = _records_by_chunk.get(key, [])
	bucket.append(record)
	_records_by_chunk[key] = bucket


func _deindex_record(entity_id: String) -> void:
	# We don't store the old chunk key, so we have to walk the chunks. In
	# practice this is cheap — typical record counts per chunk are <20.
	for key in _records_by_chunk.keys():
		var bucket: Array = _records_by_chunk[key]
		for i in range(bucket.size() - 1, -1, -1):
			var rec: EntityRecord = bucket[i] as EntityRecord
			if rec != null and rec.entity_id == entity_id:
				bucket.remove_at(i)
		# Tidy: drop empty chunk buckets so iteration stays cheap.
		if bucket.is_empty():
			_records_by_chunk.erase(key)
		else:
			_records_by_chunk[key] = bucket


func _generate_id() -> String:
	var id := "%s%d" % [_session_prefix, _next_id]
	_next_id += 1
	return id


# ============================================================
# Save / load
# ============================================================

# Write the full registry to a JSON file. Caller chooses the path
# (typically `user://saves/slot_{N}/entities.json`). Returns OK or an
# Error code.
func save_to_disk(path: String) -> Error:
	# Build a plain-data payload that survives JSON.stringify cleanly.
	var records: Array = []
	for rec in _by_id.values():
		if rec is EntityRecord:
			records.append((rec as EntityRecord).to_dict())
	var payload: Dictionary = {
		"version": 1,
		"session_prefix": _session_prefix,
		"next_id": _next_id,
		"records": records,
	}
	# Ensure the directory exists. FileAccess.open will fail with FILE_CANT_OPEN
	# otherwise.
	var dir_path: String = path.get_base_dir()
	if dir_path != "" and not DirAccess.dir_exists_absolute(dir_path):
		var err := DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			push_warning("[EntityRegistry] save_to_disk: mkdir failed (%s) for %s" % [error_string(err), dir_path])
			return err
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		var open_err := FileAccess.get_open_error()
		push_warning("[EntityRegistry] save_to_disk: open failed (%s) for %s" % [error_string(open_err), path])
		return open_err
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	return OK


# Wipe the in-memory registry and reload from disk. Missing file is
# treated as an empty registry (return OK, registry stays empty).
func load_from_disk(path: String) -> Error:
	clear()
	if not FileAccess.file_exists(path):
		return OK
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		var open_err := FileAccess.get_open_error()
		push_warning("[EntityRegistry] load_from_disk: open failed (%s) for %s" % [error_string(open_err), path])
		return open_err
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("[EntityRegistry] load_from_disk: invalid JSON at %s" % path)
		return ERR_PARSE_ERROR
	var payload: Dictionary = parsed
	_session_prefix = String(payload.get("session_prefix", _session_prefix))
	_next_id = int(payload.get("next_id", _next_id))
	var records: Array = payload.get("records", [])
	for r in records:
		if r is Dictionary:
			var rec: EntityRecord = EntityRecord.from_dict(r)
			_by_id[rec.entity_id] = rec
			_index_record(rec)
	return OK


# Reset the registry (in-memory only — disk untouched).
func clear() -> void:
	_records_by_chunk.clear()
	_by_id.clear()
