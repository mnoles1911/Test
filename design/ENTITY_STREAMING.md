# Entity Streaming

The canonical record of WHO is in the world, WHERE they are, and the
plumbing that loads / frees / tiers them as the player moves around.

Sits next to `VoxelStreamSQLite` (terrain edits) and `WaterByteCodec`
(water sim) as one of the three persistent data layers of the world.

## Pieces

- **`scripts/entities/EntityRecord.gd`** — POD snapshot. Fields:
  `entity_id`, `scene_path`, `position`, `rotation_y`, `state`
  (opaque type-specific Dictionary), `ai_tier`. JSON round-trips via
  `to_dict()` / `from_dict()`. NO `class_name` (path-preloaded so the
  headless harness parses cleanly — same rule as `ShaderProfile.gd`
  and `WaterMaterial.gd`).
- **`scripts/entities/EntityRegistry.gd`** — autoload (after `WaterDiag`
  in `project.godot`). Per-chunk index
  `Dictionary[Vector2i, Array[EntityRecord]]` keyed at `CHUNK_M=16m`
  + fast-path `_by_id`. Public API: `register / update / unregister /
  get_record / records_in_chunk / record_count / chunk_count`. Save
  / load via JSON sidecar (typical path
  `user://saves/slot_{N}/entities.json`).
- **`scripts/EntityStreamer.gd`** — Node3D, scene-attached (NOT autoload
  — needs a scene-specific player reference). Reconciles 4×/s:
  spawn missing records in load radius, snapshot + free live entities
  outside unload radius (hysteresis kills boundary thrash), pick AI
  tier by distance.

## AI tier protocol

Entity scene roots opt in to streaming by implementing three methods:

```gdscript
func set_ai_tier(tier: int) -> void:
    # 0 ACTIVE (full physics + AI, 60Hz)
    # 1 AWAKE  (physics + 10Hz AI, no animation)
    # 2 SLEEPING (physics off, 1Hz background — physics_process disabled)
    # 3 OFFLOADED — never delivered to the live node; the streamer
    #               frees the scene + keeps only the EntityRecord.

func to_entity_record() -> Dictionary:
    # Snapshot the dynamic state EntityStreamer should save off. Adding
    # keys is forward-compatible — from_entity_record uses .get(...).

func from_entity_record(blob: Dictionary) -> void:
    # Reverse: restore state from a saved snapshot. Idempotent against
    # an empty / missing blob.
```

Entities that don't implement any of them just don't get tiered / saved
— they still spawn from the scene_path but are static.

## Reconciliation algorithm

Each 4 Hz tick `EntityStreamer._reconcile()` does three passes:

1. **Spawn pass.** For every chunk inside `load_radius_chunks` of the
   player chunk, iterate `EntityRegistry.records_in_chunk(k)`. If the
   record isn't already live, `_try_spawn_live` instances the scene at
   `position` + `rotation_y` and pushes the saved state via
   `from_entity_record`.
2. **Evict pass.** Walk live entities; for any whose current chunk is
   further than `unload_radius_chunks`, `_snapshot_entity` updates the
   record (position / rotation_y / state via `to_entity_record`) then
   `queue_free`s the scene. Hysteresis (load < unload) prevents
   boundary thrash.
3. **Tier pass.** For surviving live entities, distance-classify into
   ACTIVE / AWAKE / SLEEPING. Push only when the tier actually changes
   (skip writes on stable distances).

## Spawning a new persistent entity

Game code calls one of two public APIs:

```gdscript
# Brand-new entity (gameplay-side):
EntityStreamer.spawn_persistent(
    "res://scenes/enemies/Goblin.tscn",
    Transform3D(Basis(), Vector3(10, 35, 5)),
    {"health": 50, "ai_state": 0})

# Adopt an existing live scene node (for hand-placed entities in .tscn):
EntityStreamer.adopt_live(my_goblin_node,
    "res://scenes/enemies/Goblin.tscn",
    {"health": 50, "ai_state": 0})
```

## Save / load

On save: `EntityStreamer.snapshot_all()` forces every live entity to
push its current state into the registry, then
`EntityRegistry.save_to_disk(slot_path)` writes JSON.

On load: `EntityRegistry.load_from_disk(slot_path)` reads the JSON
back into the registry. The streamer's next reconcile tick lazily
spawns the records inside load_radius — no eager scene instancing.

## Headless parity gate

`tools/headless/run.ps1 entity` synthesises 50 EntityRecords across 5
chunks, saves, clears, reloads, and asserts:

- pre-save `record_count` / `chunk_count` / `records_in_chunk` per
  chunk
- save / clear / load round-trip preserves count + chunk indexing
- per-record recovery by id (all 50 round-trip)
- post-load mutation: `update` moves a record between chunks,
  `unregister` removes it

66 checks. Bit-for-bit JSON round-trip — anything breaking the JSON
schema or chunk indexing fails this gate.

## Retrofitted entity types

- **Goblin (via `scripts/Enemy3D.gd` base)** —
  `state = {"health", "state" (enum int), "is_dead"}`. Tier 2+ disables
  `_physics_process` entirely; tier 1 gates work to 10 Hz.
- **NPC (`scripts/NPC.gd`)** —
  `state = {"npc_data_path", "disposition"}`. Tier 2+ disables both
  `_physics_process` and `_process`. Bark/Interact Area3Ds stay live
  so triggers still fire when the player approaches.
- **VoxelDrop (`scripts/VoxelDrop.gd`)** —
  `state = {"item_id", "count", "color", "picked_up"}`. Tier 2+ sets
  `sleeping = true + freeze = true` on the RigidBody3D so the cube
  stops integrating physics; tier 0/1 wakes it back up. `picked_up`
  drops are auto-freed on respawn (no rezombie loot).

## Not in scope

- Per-chunk SQLite persistence (JSON sidecar is sufficient at current
  entity counts; revisit if the registry grows past ~10 k records).
- Vertical chunk streaming (current model is 2D horizontal chunks +
  pos.y on the record — caves don't yet need vertical chunking).
- Multiplayer synchronisation (`EntityStreamer.spawn_persistent` is
  authority-side only; clients receive entities via the existing
  MultiplayerSpawner pattern). MP-aware entity replication is a
  follow-up if/when the entity count exceeds what MultiplayerSpawner
  handles comfortably.

## Files requiring maintenance

| File | Update when... |
|---|---|
| `scripts/entities/EntityRecord.gd` | New top-level field added to the snapshot |
| `scripts/entities/EntityRegistry.gd` | New public API; load/save schema bump |
| `scripts/EntityStreamer.gd` | New AI tier, new spawn API, new reconcile pass |
| Goblin / NPC / VoxelDrop | A new field needs to round-trip through state |
| `tools/headless/runner.gd` `_entity()` | Any of the above |
