// EntityRegistry.h — the persistent per-chunk store of every world entity.
//
// Ported from Godot scripts/entities/EntityRegistry.gd (+ EntityRecord.gd).
// Design intent: design/ENTITY_STREAMING.md.
//
// ----------------------------------------------------------------------------
// WHAT THIS IS, IN PLAIN ENGLISH:
//
// This is the world's address book. Every persistent thing — an NPC, an enemy,
// a dropped item — lives here as ONE EntityRecord: who it is (an id), where it
// is (a world position), what kind of thing it is, plus an opaque "state" blob
// the entity type fills with whatever it needs. The registry's whole job is to
// keep two indexes over those records so the streamer can answer two questions
// fast:
//
//   1. "Give me the entity with this id."          -> _by_id
//   2. "Give me everything standing in this chunk." -> _by_chunk
//
// A "chunk" here is just a 16-metre horizontal tile of the world. We slice the
// world into a grid of these tiles and file each record under the tile it sits
// in. When a record MOVES far enough to cross a tile boundary, the registry
// re-files it (drops it from the old tile, adds it to the new one) so the chunk
// index never goes stale.
//
// PURITY: this is pure data + bookkeeping. There is NO scene tree here, no
// spawning, no freeing, no file I/O. In the Godot build the registry also did
// JSON save/load and ID generation off a wall clock; the UE wrapper layer owns
// those concerns now (a clock and a save file are engine business), so Core
// keeps only the load-bearing indexing logic. The streamer (EntityStreaming.h)
// asks this store for records; the UE subsystem turns the answers into actors.
//
// ----------------------------------------------------------------------------
// GDScript -> C++ divergences (all deliberate, all noted):
//   * The chunk key in Godot is a Vector2i (x, z). Here it is a mira::Vec3i with
//     y forced to 0 (we already have a hash for Vec3i in MiraVec.h, and a 2D
//     key would need its own hash specialization for nothing). Treat it as 2D.
//   * Godot generated entity ids off Time.get_unix_time_from_system(). That is
//     a clock read — engine business — so ID generation is NOT in Core. The
//     caller supplies the id (the UE subsystem mints them). register() requires
//     a non-empty id and returns whether it took.
//   * JSON save_to_disk / load_from_disk are dropped from Core (file I/O). The
//     UE layer serializes the records it pulls via for_each_record().

#pragma once

#include <cmath>
#include <cstdint>
#include <functional>
#include <string>
#include <unordered_map>
#include <vector>

#include "Core/MiraVec.h"

namespace mira {

// ----------------------------------------------------------------------------
// EntityRecord — the POD snapshot of one persistent entity.
//
// Mirrors EntityRecord.gd. `state` is intentionally an opaque key/value blob so
// each entity type (Goblin: health + ai_state; drop: item_id + quantity; NPC:
// npc_id + schedule) can stash what it needs without this struct growing a
// field per type. In Godot `state` was a Dictionary; here it is a string->string
// map (the UE wrapper round-trips richer values through it as needed) — the Core
// never reads INTO state, it only carries it.
// ----------------------------------------------------------------------------
struct EntityRecord {
    std::string id;                 // Unique id. Supplied by the caller (see header note).
    Vec3        position;           // World position in metres (x, y, z). y is free height.
    std::string type;               // Entity type tag (e.g. "goblin", "npc", "drop").
    float       rotation_y = 0.0f;  // Yaw in radians. Pitch/roll live in state if needed.
    int32_t     ai_tier    = 0;     // Last AI tier the streamer assigned (see EntityStreaming.h).
    std::unordered_map<std::string, std::string> state;  // Opaque per-type blob.
};

// ----------------------------------------------------------------------------
// EntityRegistry — id index + chunk index over EntityRecords.
// ----------------------------------------------------------------------------
class EntityRegistry {
public:
    // The chunk grid pitch in metres. MUST match EntityStreaming's chunk size
    // and the Godot EntityRegistry.CHUNK_M (= 16). One value, one grid, so the
    // registry and the streamer agree on which records live in which tile.
    static constexpr int CHUNK_M = 16;

    EntityRegistry() = default;

    // The horizontal chunk key for a world position. Mirrors the GDScript
    // chunk_key_for_position(): floor(x / CHUNK_M), floor(z / CHUNK_M). The y
    // component of the returned key is always 0 — this is a 2D tile key carried
    // in a Vec3i (see header note). floor() matters: it gives a continuous grid
    // across the origin (-0.1 m -> chunk -1, not 0), exactly like Godot's floor.
    static Vec3i chunk_key_for_position(const Vec3& pos) {
        return Vec3i(floor_div(pos.x, CHUNK_M), 0, floor_div(pos.z, CHUNK_M));
    }

    // Register a brand-new record, or re-file one that already exists (which is
    // just an update — handles a moved chunk too). The id must be non-empty;
    // an empty id is ignored and returns false. Returns true if the store now
    // holds the record. Mirrors register() + the "re-register == update" path.
    bool register_record(const EntityRecord& record) {
        if (record.id.empty()) {
            return false;
        }
        if (_by_id.count(record.id) != 0) {
            // Already present — treat as an update (re-indexes if the chunk moved).
            update(record);
            return true;
        }
        _by_id[record.id] = record;
        index_record(record.id);
        return true;
    }

    // Update an existing record (call after moving it). If it isn't registered
    // yet, this falls through to a register. The record is re-indexed so a
    // chunk change drops it from the old tile and adds it to the new one.
    // Mirrors update().
    void update(const EntityRecord& record) {
        if (record.id.empty()) {
            return;
        }
        auto it = _by_id.find(record.id);
        if (it == _by_id.end()) {
            register_record(record);
            return;
        }
        // Drop the OLD entry from its OLD chunk first (using the stored
        // position), then overwrite the stored record and re-index at the NEW
        // position. This is the re-index-on-chunk-change contract.
        deindex_record(record.id);
        it->second = record;
        index_record(record.id);
    }

    // Remove a record. Idempotent — unregistering an unknown id is a no-op.
    // Mirrors unregister().
    void unregister(const std::string& id) {
        if (id.empty() || _by_id.count(id) == 0) {
            return;
        }
        deindex_record(id);
        _by_id.erase(id);
    }

    // Fast-path id lookup. Returns nullptr if the id is unknown. The pointer is
    // valid until the next mutating call. Mirrors get_record().
    const EntityRecord* get_record(const std::string& id) const {
        auto it = _by_id.find(id);
        return it == _by_id.end() ? nullptr : &it->second;
    }

    // All records currently filed under the given chunk key. Returns a copied
    // vector (modifying it doesn't touch the index), matching the GDScript
    // records_in_chunk() "returned array is a COPY" contract. Empty if none.
    std::vector<EntityRecord> records_in_chunk(const Vec3i& chunk_key) const {
        std::vector<EntityRecord> out;
        auto it = _by_chunk.find(chunk_key);
        if (it == _by_chunk.end()) {
            return out;
        }
        out.reserve(it->second.size());
        for (const std::string& id : it->second) {
            auto rec = _by_id.find(id);
            if (rec != _by_id.end()) {
                out.push_back(rec->second);
            }
        }
        return out;
    }

    // Visit every record without copying (for save/serialize in the UE layer).
    void for_each_record(const std::function<void(const EntityRecord&)>& fn) const {
        for (const auto& kv : _by_id) {
            fn(kv.second);
        }
    }

    // Total record count. Mirrors record_count().
    size_t record_count() const { return _by_id.size(); }

    // Number of non-empty chunk buckets. Mirrors chunk_count(). Empty buckets
    // are pruned on deindex, so this is the count of tiles that hold >= 1 record.
    size_t chunk_count() const { return _by_chunk.size(); }

    // Wipe the in-memory store. Mirrors clear().
    void clear() {
        _by_chunk.clear();
        _by_id.clear();
    }

private:
    // floor(value / divisor) for an integer divisor, done in floating point and
    // floored exactly like Godot's int(floor(pos.x / CHUNK_M)). We compute in
    // double then floor so negative coordinates round toward -infinity (C++
    // integer division truncates toward zero, which would mis-bin -0.1 m).
    static int32_t floor_div(float value, int divisor) {
        const double q = static_cast<double>(value) / static_cast<double>(divisor);
        return static_cast<int32_t>(std::floor(q));
    }

    // Add the record's id to the chunk bucket for its CURRENT stored position.
    // Assumes _by_id already holds the (current) record. Mirrors _index_record().
    void index_record(const std::string& id) {
        auto rec = _by_id.find(id);
        if (rec == _by_id.end()) {
            return;
        }
        const Vec3i key = chunk_key_for_position(rec->second.position);
        _by_chunk[key].push_back(id);
    }

    // Remove the record's id from whatever chunk bucket currently lists it.
    //
    // The Godot version walked EVERY chunk because it didn't store the old key.
    // We can do better: the stored record still holds the OLD position (callers
    // deindex BEFORE overwriting it), so we go straight to the right bucket.
    // This is an O(bucket) erase instead of O(all chunks) — same result, less
    // work — and it is the one efficiency divergence from the GDScript.
    void deindex_record(const std::string& id) {
        auto rec = _by_id.find(id);
        if (rec == _by_id.end()) {
            return;
        }
        const Vec3i key = chunk_key_for_position(rec->second.position);
        auto bucket = _by_chunk.find(key);
        if (bucket == _by_chunk.end()) {
            return;
        }
        std::vector<std::string>& ids = bucket->second;
        for (size_t i = ids.size(); i-- > 0;) {
            if (ids[i] == id) {
                ids[i] = ids.back();
                ids.pop_back();
            }
        }
        // Tidy: drop empty buckets so chunk_count() and iteration stay honest,
        // exactly like the GDScript erased empty buckets.
        if (ids.empty()) {
            _by_chunk.erase(bucket);
        }
    }

    // id -> the canonical record.
    std::unordered_map<std::string, EntityRecord> _by_id;
    // chunk key (Vec3i, y always 0) -> the ids filed under that chunk.
    std::unordered_map<Vec3i, std::vector<std::string>> _by_chunk;
};

} // namespace mira
