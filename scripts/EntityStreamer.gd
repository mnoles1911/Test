extends Node3D
# EntityStreamer — load/free/tier persistent world entities around the player.
#
# What it does (in plain English):
#   - Watches what chunk the player is in.
#   - For every chunk within LOAD_RADIUS_CHUNKS, makes sure each
#     EntityRecord in that chunk has a live scene instance.
#   - For chunks beyond UNLOAD_RADIUS_CHUNKS, snapshots any live entities
#     in those chunks back to EntityRegistry then queue_frees the scenes.
#   - For live entities, picks an AI tier based on distance:
#       <  AWAKE_RADIUS_M     -> ACTIVE   (full physics + AI, 60Hz)
#       <  SLEEP_RADIUS_M     -> AWAKE    (10Hz logic, animations off)
#       <  unload boundary    -> SLEEPING (1Hz logic, physics off)
#       outside load radius   -> OFFLOADED (scene freed; record only)
#     Each entity type implements `set_ai_tier(tier)` to honour the
#     downgrade (Goblin disables shadows + animation tree; NPC freezes
#     pose; VoxelDrop sleeps its RigidBody3D).
#
# Headless-safe — every scene-tree call null-guards. With no terrain /
# no player the streamer just prints a warning and idles.
#
# Reference: design/ENTITY_STREAMING.md +
#            scripts/entities/EntityRegistry.gd +
#            scripts/entities/EntityRecord.gd.

const EntityRecord := preload("res://scripts/entities/EntityRecord.gd")


# AI tiers. Lower = closer + more lively. set_ai_tier on the entity gets
# the integer; entities decide what their tier downgrade looks like.
enum AITier {
	ACTIVE   = 0,  # Full physics + animation + 60Hz AI.
	AWAKE    = 1,  # Physics on, no animation, 10Hz AI.
	SLEEPING = 2,  # Physics off, no animation, 1Hz background AI.
	OFFLOADED = 3, # Scene freed; only the EntityRecord exists.
}

# Chunk grid (must match EntityRegistry.CHUNK_M).
@export var chunk_size: int = 16

# How wide a band of chunks around the player we keep "loaded as scenes".
# 5 chunks radius = ~80 m world distance — covers active gameplay range.
@export var load_radius_chunks: int = 5
# Hysteresis: unload only when an entity drifts past UNLOAD chunks so
# crossing back-and-forth at the boundary doesn't thrash spawn/despawn.
@export var unload_radius_chunks: int = 6

# Per-entity AI tier thresholds (metres, NOT chunks — finer-grained).
@export var awake_radius_m: float = 30.0
@export var sleep_radius_m: float = 80.0

# How often the streamer reconciles (re-scans load chunks, demotes/promotes
# entity tiers). 4 Hz is plenty given player walk speed ~5 m/s.
@export var tick_hz: float = 4.0

# Override for tests / dev scenes — set true to print every chunk transition
# + spawn / despawn event to the Output panel.
@export var print_events: bool = false

# Where the chunk-watch player is. Same fallback logic as the old stub.
@export var player_node_path: NodePath

var _player: Node3D = null
# Cached "what chunk is the player in now"; recompute each tick.
var _player_chunk: Vector2i = Vector2i(-999999, -999999)
# entity_id -> live Node3D currently in the scene tree.
var _live: Dictionary = {}
# Last tier we pushed to each entity, so we don't write redundant tier
# updates each tick.
var _last_tier_by_id: Dictionary = {}
# Tick accumulator.
var _tick_accum: float = 0.0


# ============================================================
# Lifecycle
# ============================================================

func _ready() -> void:
	_resolve_player()
	# First reconcile fires next _process tick — no need to do it in _ready
	# (entities may not be registered yet from a save load).


func _process(delta: float) -> void:
	_tick_accum += delta
	var interval: float = 1.0 / maxf(0.1, tick_hz)
	if _tick_accum < interval:
		return
	_tick_accum = 0.0
	_reconcile()


# ============================================================
# Public spawning API
# ============================================================

# Create a brand-new persistent entity.
#   scene_path : path to a .tscn whose root supports the entity protocol
#                (from_entity_record / to_entity_record / set_ai_tier)
#   transform  : initial world transform (position + rotation_y consumed,
#                pitch/roll discarded — entities are upright)
#   state      : initial type-specific blob
# Returns the EntityRecord (already registered + live in the scene). The
# caller can mutate state on the live node freely; on chunk evict we
# snapshot it back via to_entity_record before freeing.
func spawn_persistent(scene_path: String, transform: Transform3D, state: Dictionary = {}) -> EntityRecord:
	var rec := EntityRecord.new()
	rec.scene_path = scene_path
	rec.position = transform.origin
	rec.rotation_y = transform.basis.get_euler().y
	rec.state = state
	rec.ai_tier = AITier.ACTIVE
	EntityRegistry.register(rec)
	# Immediately try to bring it live — if the player is far away, the
	# next reconcile tick will demote it to OFFLOADED.
	_try_spawn_live(rec)
	return rec


# Adopt an already-live scene node into the streaming system. Useful for
# entities placed by .tscn (the hand-placed Goblins in CombatTest) so
# they participate in tiering + save without being rewritten.
#
# Caller is responsible for ensuring the node supports the protocol.
func adopt_live(node: Node3D, scene_path: String, state: Dictionary = {}) -> EntityRecord:
	var rec := EntityRecord.new()
	rec.scene_path = scene_path
	rec.position = node.global_position
	rec.rotation_y = node.global_transform.basis.get_euler().y
	rec.state = state
	rec.ai_tier = AITier.ACTIVE
	EntityRegistry.register(rec)
	_live[rec.entity_id] = node
	# Tag the node so to_entity_record snapshots can carry the id.
	node.set_meta("entity_id", rec.entity_id)
	return rec


# Force-snapshot every live entity (e.g. on save). Updates each record's
# position / rotation_y / state from the live node, but doesn't free.
func snapshot_all() -> void:
	for id in _live.keys():
		var node: Node3D = _live.get(id, null)
		if not is_instance_valid(node):
			_live.erase(id)
			continue
		_snapshot_entity(id, node)


# ============================================================
# Internals — reconcile
# ============================================================

# One pass of "load near, free far". O(records-in-load-region).
func _reconcile() -> void:
	if _player == null:
		_resolve_player()
		if _player == null:
			return

	var new_chunk: Vector2i = _world_to_chunk(_player.global_position)
	if new_chunk != _player_chunk:
		if print_events:
			print("[EntityStreamer] player chunk %s -> %s" % [_player_chunk, new_chunk])
		_player_chunk = new_chunk

	# Pass 1 — spawn any record inside the load radius that isn't already live.
	for dz in range(-load_radius_chunks, load_radius_chunks + 1):
		for dx in range(-load_radius_chunks, load_radius_chunks + 1):
			var k: Vector2i = _player_chunk + Vector2i(dx, dz)
			for rec in EntityRegistry.records_in_chunk(k):
				if not _live.has(rec.entity_id):
					_try_spawn_live(rec)

	# Pass 2 — demote / free anything outside the unload radius.
	# Walk _live snapshot since we may erase mid-iteration.
	for id in _live.keys():
		var node: Node3D = _live.get(id, null)
		if not is_instance_valid(node):
			_live.erase(id)
			_last_tier_by_id.erase(id)
			continue
		var c: Vector2i = _world_to_chunk(node.global_position)
		var dx: int = abs(c.x - _player_chunk.x)
		var dz: int = abs(c.y - _player_chunk.y)
		if max(dx, dz) > unload_radius_chunks:
			_evict_live(id, node)

	# Pass 3 — for each surviving live entity, pick its tier by distance.
	for id in _live.keys():
		var node: Node3D = _live.get(id, null)
		if not is_instance_valid(node):
			continue
		var dist: float = node.global_position.distance_to(_player.global_position)
		var tier: int = _tier_for_distance(dist)
		var prev: int = _last_tier_by_id.get(id, -1)
		if tier != prev:
			_last_tier_by_id[id] = tier
			if node.has_method("set_ai_tier"):
				node.call("set_ai_tier", tier)
			if print_events:
				print("[EntityStreamer] %s tier %d -> %d (d=%.1f m)" % [id, prev, tier, dist])


func _tier_for_distance(d: float) -> int:
	if d <= awake_radius_m:
		return AITier.ACTIVE
	if d <= sleep_radius_m:
		return AITier.AWAKE
	return AITier.SLEEPING


# Snapshot a live entity into its record (position, rotation_y, state).
func _snapshot_entity(id: String, node: Node3D) -> void:
	var rec: EntityRecord = EntityRegistry.get_record(id)
	if rec == null:
		return
	rec.position = node.global_position
	rec.rotation_y = node.global_transform.basis.get_euler().y
	if node.has_method("to_entity_record"):
		var blob: Variant = node.call("to_entity_record")
		if blob is Dictionary:
			rec.state = blob
	EntityRegistry.update(rec)


# Bring a record to life as a scene instance, parented to this streamer
# so dev scenes / world scenes don't need to know about each entity.
func _try_spawn_live(rec: EntityRecord) -> void:
	if rec.scene_path == "" or not ResourceLoader.exists(rec.scene_path):
		push_warning("[EntityStreamer] missing scene_path for %s: '%s'" % [rec.entity_id, rec.scene_path])
		return
	var packed: PackedScene = load(rec.scene_path) as PackedScene
	if packed == null:
		push_warning("[EntityStreamer] failed to load PackedScene at %s" % rec.scene_path)
		return
	var inst: Node = packed.instantiate()
	if not (inst is Node3D):
		push_warning("[EntityStreamer] scene root at %s is not Node3D — skipping" % rec.scene_path)
		inst.queue_free()
		return
	var node: Node3D = inst as Node3D
	add_child(node)
	# Apply transform AFTER add_child so global_position resolves.
	var basis := Basis(Vector3.UP, rec.rotation_y)
	node.global_transform = Transform3D(basis, rec.position)
	node.set_meta("entity_id", rec.entity_id)
	# Apply saved state if the entity supports it.
	if node.has_method("from_entity_record"):
		node.call("from_entity_record", rec.state)
	_live[rec.entity_id] = node
	# Initial tier — picked next reconcile, but set ACTIVE so the first
	# frame isn't a phantom-SLEEPING entity.
	if node.has_method("set_ai_tier"):
		node.call("set_ai_tier", AITier.ACTIVE)
	_last_tier_by_id[rec.entity_id] = AITier.ACTIVE


# Snapshot + free a live entity. Called when it drifts out of unload radius.
func _evict_live(id: String, node: Node3D) -> void:
	_snapshot_entity(id, node)
	_live.erase(id)
	_last_tier_by_id.erase(id)
	if print_events:
		print("[EntityStreamer] evict %s (out of radius)" % id)
	node.queue_free()


# ============================================================
# Internals — player resolution + chunk math
# ============================================================

func _resolve_player() -> void:
	if not player_node_path.is_empty():
		var n: Node = get_node_or_null(player_node_path)
		if n is Node3D:
			_player = n
			return
	var matches: Array = get_tree().get_nodes_in_group("player")
	for candidate in matches:
		if candidate is Node3D:
			_player = candidate
			return


func _world_to_chunk(world_pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(world_pos.x / float(chunk_size))),
	                int(floor(world_pos.z / float(chunk_size))))
