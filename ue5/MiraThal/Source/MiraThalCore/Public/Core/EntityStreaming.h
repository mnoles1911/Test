// EntityStreaming.h — the 4-tier "AI sleep" + load-ring decision logic.
//
// Ported from Godot scripts/EntityStreamer.gd (design: design/ENTITY_STREAMING.md).
//
// ----------------------------------------------------------------------------
// WHAT THIS IS, IN PLAIN ENGLISH:
//
// As the player walks the world we cannot keep every NPC, enemy and dropped
// item fully alive at once — that would melt the CPU. So the streamer demotes
// distant things through four "liveliness" tiers, like turning the brightness
// down on something the player isn't looking at:
//
//   ACTIVE    — full physics + animation + 60 Hz AI. (the things near you)
//   AWAKE     — physics on, animation off, 10 Hz AI. (just out of reach)
//   SLEEPING  — physics off, animation off, 1 Hz background AI. (far but loaded)
//   OFFLOADED — the scene/actor is freed entirely; only the EntityRecord
//               survives in the registry. (out past the load ring)
//
// The Godot EntityStreamer did three jobs every reconcile tick:
//   1. SPAWN any record inside the load ring that isn't live yet.
//   2. EVICT (snapshot + free) any live thing that has drifted out past the
//      UNLOAD ring — note the load and unload rings are DIFFERENT sizes on
//      purpose (hysteresis), so an entity sitting right on the boundary doesn't
//      flicker spawn/despawn as the player jitters back and forth.
//   3. TIER every surviving live thing by its straight-line distance.
//
// PURITY: this Core file owns only the DECISIONS — the math that says "this
// entity should be tier AWAKE", "these chunk keys are in the load ring",
// "this entity is far enough to evict". It does NOT spawn actors, free actors,
// or touch a scene tree. The UE wrapper (a UEntityStreamSubsystem, later) calls
// these pure functions and then does the actual spawn/free/SetAITier work. That
// is the same split the Godot file hinted at: the reconcile glue lived in the
// Node3D, but the rules underneath are plain arithmetic, and that arithmetic is
// what we port so the parity harness can pin it.
//
// ----------------------------------------------------------------------------
// GDScript -> C++ divergences (all deliberate, all noted):
//   * The scene-tree glue is dropped: _try_spawn_live / _evict_live /
//     _snapshot_entity / _resolve_player / the _live + _last_tier_by_id dicts
//     and the _process tick accumulator are all engine business. Core exposes
//     the decisions those routines were built around as free functions.
//   * Tiers ACTIVE/AWAKE/SLEEPING come straight from _tier_for_distance(). The
//     fourth tier OFFLOADED is what the streamer's evict pass produced (the
//     scene freed) — here it is a first-class classifier result so the caller
//     can ask "what should this entity BE?" in one call: an entity outside the
//     load ring classifies OFFLOADED.
//   * Distance thresholds use <= exactly as the GDScript did (d <= awake_radius
//     -> ACTIVE). The task brief phrased these as "< 30 m / < 80 m"; the ported
//     behaviour follows the source file's <= so an entity sitting EXACTLY on
//     30.0 m reads ACTIVE, not AWAKE. Noted, not changed.
//   * Chunk distance is Chebyshev (max(|dx|, |dz|)), matching the GDScript's
//     square ring: range(-R, R+1) in both axes for the spawn pass and
//     max(dx, dz) > unload for the evict pass.

#pragma once

#include <cmath>
#include <cstdint>
#include <vector>

#include "Core/MiraVec.h"
#include "Core/EntityRegistry.h"

namespace mira {

// ----------------------------------------------------------------------------
// AITier — lower = closer + more lively. Mirrors EntityStreamer.AITier; the
// integer values match the Godot enum (and EntityRecord.ai_tier) exactly so a
// saved record's tier survives the port unchanged.
// ----------------------------------------------------------------------------
enum class AITier : int32_t {
    ACTIVE    = 0,  // Full physics + animation + 60 Hz AI.
    AWAKE     = 1,  // Physics on, no animation, 10 Hz AI.
    SLEEPING  = 2,  // Physics off, no animation, 1 Hz background AI.
    OFFLOADED = 3,  // Scene/actor freed; only the EntityRecord exists.
};

// ----------------------------------------------------------------------------
// EntityStreamConfig — the designer dials, lifted verbatim from the GDScript
// @export defaults. One config object so the registry and the streamer agree on
// the chunk grid (chunk_size MUST equal EntityRegistry::CHUNK_M).
// ----------------------------------------------------------------------------
struct EntityStreamConfig {
    // Chunk grid pitch in metres. MUST match EntityRegistry::CHUNK_M (= 16).
    int chunk_size = EntityRegistry::CHUNK_M;

    // How wide a band of chunks around the player we keep loaded as actors.
    // 5 chunks radius ~= 80 m world distance — covers active gameplay range.
    int load_radius_chunks = 5;

    // Hysteresis: don't EVICT until an entity drifts past this LARGER ring, so
    // crossing the load boundary back and forth doesn't thrash spawn/despawn.
    int unload_radius_chunks = 6;

    // Per-entity AI tier thresholds (metres, finer-grained than chunks).
    // d <= awake_radius_m -> ACTIVE; d <= sleep_radius_m -> AWAKE; else SLEEPING.
    float awake_radius_m = 30.0f;
    float sleep_radius_m = 80.0f;

    // How often the streamer reconciles. 4 Hz is plenty at ~5 m/s walk speed.
    // Pure metadata here (Core does no ticking); the UE subsystem drives it.
    float tick_hz = 4.0f;
};

// ----------------------------------------------------------------------------
// Per-tier logic tick rates (Hz). The "60/10/1" cadence the GDScript header
// documented for ACTIVE/AWAKE/SLEEPING. OFFLOADED has no tick (the actor is
// gone), reported as 0 Hz. The UE subsystem reads this to gate each tier's
// per-frame work; Core only carries the table.
// ----------------------------------------------------------------------------
inline float tier_tick_hz(AITier tier) {
    switch (tier) {
        case AITier::ACTIVE:    return 60.0f;
        case AITier::AWAKE:     return 10.0f;
        case AITier::SLEEPING:  return 1.0f;
        case AITier::OFFLOADED: return 0.0f;
    }
    return 0.0f;
}

// ----------------------------------------------------------------------------
// Chunk math (free functions). The chunk key for a world position MUST agree
// with EntityRegistry::chunk_key_for_position — we delegate to it so there is
// exactly one floor()-based formula in the whole port.
// ----------------------------------------------------------------------------

// floor(x / chunk_size), floor(z / chunk_size); y forced 0. Same 2D tile key
// the registry files records under. Mirrors EntityStreamer._world_to_chunk().
inline Vec3i world_to_chunk(const Vec3& world_pos) {
    return EntityRegistry::chunk_key_for_position(world_pos);
}

// Chebyshev (square-ring) chunk distance between two chunk keys: max(|dx|, |dz|).
// This is the ring shape the GDScript used — range(-R, R+1) on both axes is a
// square, and the evict test was max(dx, dz). The y component is ignored (2D).
inline int chunk_chebyshev_distance(const Vec3i& a, const Vec3i& b) {
    const int dx = std::abs(a.x - b.x);
    const int dz = std::abs(a.z - b.z);
    return dx > dz ? dx : dz;
}

// ----------------------------------------------------------------------------
// Tier classification.
// ----------------------------------------------------------------------------

// Distance-only tier, mirroring _tier_for_distance(): the three "loaded" tiers.
// This NEVER returns OFFLOADED — distance alone doesn't free a scene; being
// outside the load ring does (see classify_tier below). Kept separate so the
// caller can tier a thing it already knows is loaded.
inline AITier tier_for_distance(float distance_m, const EntityStreamConfig& cfg) {
    if (distance_m <= cfg.awake_radius_m) {
        return AITier::ACTIVE;
    }
    if (distance_m <= cfg.sleep_radius_m) {
        return AITier::AWAKE;
    }
    return AITier::SLEEPING;
}

// The full classifier the UE subsystem actually wants: "given where the player
// is and where this entity is, what tier should it BE right now?"
//
// An entity OUTSIDE the unload ring is OFFLOADED (its actor would be freed).
// Anything within the unload ring is tiered by straight-line distance. We test
// against the UNLOAD (larger) ring on purpose: an entity between the load and
// unload rings is NOT offloaded — that band is exactly the hysteresis zone
// where a thing that is already loaded stays loaded (just SLEEPING) until it
// finally crosses the unload boundary.
inline AITier classify_tier(const Vec3& player_pos, const Vec3& entity_pos,
                            const EntityStreamConfig& cfg) {
    const Vec3i player_chunk = world_to_chunk(player_pos);
    const Vec3i entity_chunk = world_to_chunk(entity_pos);
    if (chunk_chebyshev_distance(player_chunk, entity_chunk) > cfg.unload_radius_chunks) {
        return AITier::OFFLOADED;
    }
    const float dx = entity_pos.x - player_pos.x;
    const float dy = entity_pos.y - player_pos.y;
    const float dz = entity_pos.z - player_pos.z;
    const float distance_m = std::sqrt(dx * dx + dy * dy + dz * dz);
    return tier_for_distance(distance_m, cfg);
}

// ----------------------------------------------------------------------------
// Load-ring + hysteresis decisions (the spawn/evict passes' geometry).
// ----------------------------------------------------------------------------

// Every chunk key inside the load ring around the player's chunk. Mirrors the
// spawn pass's nested range(-load_radius, load_radius+1) loops: a square of
// (2*R+1)^2 chunk keys centred on the player chunk. The order is dz outer, dx
// inner — same iteration order the GDScript walked.
inline std::vector<Vec3i> chunks_in_load_ring(const Vec3& player_pos,
                                              const EntityStreamConfig& cfg) {
    std::vector<Vec3i> out;
    const Vec3i center = world_to_chunk(player_pos);
    const int R = cfg.load_radius_chunks;
    out.reserve(static_cast<size_t>((2 * R + 1) * (2 * R + 1)));
    for (int dz = -R; dz <= R; ++dz) {
        for (int dx = -R; dx <= R; ++dx) {
            out.push_back(Vec3i(center.x + dx, 0, center.z + dz));
        }
    }
    return out;
}

// Should a record at this chunk be SPAWNED (brought live) this tick? True when
// it is inside the load ring. Mirrors the spawn pass's membership test.
inline bool should_be_loaded(const Vec3i& player_chunk, const Vec3i& entity_chunk,
                             const EntityStreamConfig& cfg) {
    return chunk_chebyshev_distance(player_chunk, entity_chunk) <= cfg.load_radius_chunks;
}

// Should a CURRENTLY-LIVE entity be EVICTED (snapshot + freed) this tick? True
// only when it has drifted PAST the unload ring. Mirrors the evict pass test
// max(dx, dz) > unload_radius_chunks. This is the other half of the hysteresis:
// load uses load_radius (<=), evict uses unload_radius (>), and the band
// between them is the "sticky" zone where state doesn't change.
inline bool should_be_evicted(const Vec3i& player_chunk, const Vec3i& entity_chunk,
                              const EntityStreamConfig& cfg) {
    return chunk_chebyshev_distance(player_chunk, entity_chunk) > cfg.unload_radius_chunks;
}

} // namespace mira
