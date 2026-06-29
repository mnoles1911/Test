// MeshBudget.h — dirty-chunk scheduler with a per-frame quad budget.
//
// PLAIN ENGLISH OVERVIEW:
// When the player digs a hole, explodes something, or the world streams in,
// many chunks may need their meshes rebuilt at once. Rebuilding everything
// immediately would freeze the game for multiple frames ("hitching"). The
// MeshBudget solves that:
//
//   1. Any system marks a chunk dirty with mark_dirty(coord, tier, est_quads).
//      "tier" is a priority band (0 = most urgent, e.g. right next to the
//      camera; higher numbers = less urgent, e.g. distant background chunks).
//      "est_quads" is a rough guess at how expensive this chunk will be to
//      mesh (more faces → more quads → more GPU cost).
//
//   2. Each frame, the mesher calls drain(camera_chunk, quad_budget). This
//      returns a prioritised slice of dirty chunks whose total estimated cost
//      fits within the budget. Those chunks are removed from the queue;
//      the rest wait for the next frame.
//
//   3. Chunks that were re-marked while already queued (e.g. the player digs
//      again in the same spot) are DEDUPED — the queue always has at most one
//      entry per chunk coord, with the most urgent tier winning.
//
// WHY HEADER-ONLY:
// Like the rest of the engine-agnostic Core, this file contains no engine
// types (no Unreal, no Godot). It compiles cleanly in the headless clang
// harness AND inside the UE5 module. All logic fits comfortably in one header
// so callers can include it without a separate .cpp build step.
//
// No engine types — only C++17 std headers.

#pragma once

#include <cstdint>
#include <vector>
#include <unordered_map>
#include <algorithm>

#include "Core/MiraVec.h"  // mira::Vec3i

namespace mira {

// ---------------------------------------------------------------------------
// MeshBudget
// ---------------------------------------------------------------------------

class MeshBudget {
public:

    // -----------------------------------------------------------------------
    // mark_dirty — put a chunk on the to-do list (or refresh it if it's
    //              already there).
    //
    // Parameters:
    //   chunk     — which chunk (in chunk-space coordinates, not voxels).
    //   tier      — priority band. 0 = most urgent (e.g. HOT zone right next
    //               to the player). Higher numbers = less urgent (e.g. WARM,
    //               COLD, FAR background ring). The mesher drains tier 0
    //               first, then tier 1, etc.
    //   est_quads — rough estimate of the quad output when this chunk is
    //               meshed. Used to respect the per-frame budget. Doesn't
    //               need to be exact; a flat per-chunk constant is fine when
    //               you don't have a better guess.
    //
    // DEDUP RULE (why we do it this way):
    //   If the same chunk coord is marked twice, we keep ONE entry. For tier,
    //   we take the SMALLER (more urgent) of the two values. Rationale: if
    //   something said this chunk is HOT (tier 0) and something else says
    //   it's COLD (tier 3), it would be wrong to downgrade it — the first
    //   caller had a reason to want it soon. For est_quads, we take the NEW
    //   value because the freshest caller has the freshest context (e.g. a
    //   second edit may have changed the chunk's content, making the original
    //   estimate stale).
    // -----------------------------------------------------------------------
    void mark_dirty(Vec3i chunk, int tier, int est_quads) {
        // Build the packed key for this chunk coord (see pack_key below).
        uint64_t key = pack_key(chunk);

        auto it = entries_.find(key);
        if (it != entries_.end()) {
            // Already in the queue. Apply the dedup rule:
            //   - Tier:      take the smaller (more urgent) of the two.
            //   - est_quads: take the new value — freshest caller wins.
            it->second.tier      = std::min(it->second.tier, tier);
            it->second.est_quads = est_quads;
        } else {
            // Brand-new entry.
            entries_[key] = Entry{ chunk, tier, est_quads };
        }
    }

    // -----------------------------------------------------------------------
    // is_dirty — returns true if this chunk is currently queued for meshing.
    // -----------------------------------------------------------------------
    bool is_dirty(Vec3i chunk) const {
        return entries_.count(pack_key(chunk)) > 0;
    }

    // -----------------------------------------------------------------------
    // pending_count — how many chunks are waiting to be meshed.
    // -----------------------------------------------------------------------
    int pending_count() const {
        return static_cast<int>(entries_.size());
    }

    // -----------------------------------------------------------------------
    // clear — remove ALL pending chunks. Use when the world reloads, the
    //         player teleports far away, or you want a clean slate.
    // -----------------------------------------------------------------------
    void clear() {
        entries_.clear();
    }

    // -----------------------------------------------------------------------
    // drain — return the chunks to mesh THIS frame, respecting the budget.
    //
    // PRIORITY ORDER (three-key sort, applied in this order):
    //   1. Ascending tier (lower tier = more urgent → drains first).
    //   2. Ascending squared distance from camera_chunk (nearer → first).
    //      We use squared distance so there's no sqrt, and chunk coords are
    //      already at chunk granularity so the numbers are small.
    //   3. Deterministic tiebreak on the packed coord key (so two chunks at
    //      equal tier and distance always come out in the same order across
    //      frames and across platforms — no non-determinism from hash
    //      iteration order).
    //
    // BUDGET ACCUMULATION:
    //   We add chunks from the sorted list one by one, accumulating their
    //   est_quads. A chunk is included if adding it would NOT push the
    //   running total above quad_budget — OR if it is the very first chunk
    //   we're considering (see "AT LEAST ONE" rule below).
    //
    // AT LEAST ONE RULE (anti-deadlock):
    //   Even if a single chunk's est_quads exceeds quad_budget, we always
    //   return it if it is the highest-priority pending chunk and the
    //   returned slice is still empty. Without this rule, a very large chunk
    //   (e.g. a chunk full of complex foliage estimated at 50 000 quads
    //   against a budget of 10 000) would NEVER drain — the queue would grow
    //   forever and the game would visually never update that area. "At least
    //   one" guarantees forward progress no matter the cost estimate.
    //
    // Drained chunks are REMOVED from the pending set. Chunks that didn't
    // fit remain queued and will be candidates for the next drain call.
    //
    // Returns: the ordered list of chunk coords to mesh this frame.
    // -----------------------------------------------------------------------
    std::vector<Vec3i> drain(Vec3i camera_chunk, int quad_budget) {
        if (entries_.empty()) return {};

        // --- Step 1: collect all pending entries into a sortable list. ---
        // We copy them out of the hash map so we can sort without invalidating
        // iterators. The map stays intact until we know which ones to remove.
        std::vector<Entry> candidates;
        candidates.reserve(entries_.size());
        for (auto& [key, entry] : entries_) {
            candidates.push_back(entry);
        }

        // --- Step 2: sort by (tier asc, dist² asc, packed_key asc). ---
        // All three keys are deterministic, so the sort is stable across runs.
        std::sort(candidates.begin(), candidates.end(),
            [&camera_chunk](const Entry& a, const Entry& b) {
                // Key 1: tier (lower = more urgent).
                if (a.tier != b.tier) return a.tier < b.tier;

                // Key 2: squared distance from camera (nearer = first).
                int64_t da = sq_dist(a.coord, camera_chunk);
                int64_t db = sq_dist(b.coord, camera_chunk);
                if (da != db) return da < db;

                // Key 3: packed coord key for a stable, deterministic tiebreak.
                // (Without this, two chunks at equal tier and distance could
                // swap positions between frames depending on hash map iteration
                // order, causing flickering or inconsistent frame costs.)
                return pack_key(a.coord) < pack_key(b.coord);
            });

        // --- Step 3: drain greedily up to the budget. ---
        std::vector<Vec3i> result;
        int running_quads = 0;
        bool first = true;  // tracks whether we've added ANY chunk yet

        for (const Entry& e : candidates) {
            bool fits = (running_quads + e.est_quads) <= quad_budget;

            if (fits || first) {
                // Take this chunk: either it fits, OR it's the mandatory first
                // chunk (anti-deadlock rule — we must always make progress).
                result.push_back(e.coord);
                running_quads += e.est_quads;
                entries_.erase(pack_key(e.coord));  // remove from pending set
                first = false;
            }
            // If it doesn't fit AND we already have at least one result, skip
            // it for this frame — it stays in entries_ for the next drain.
        }

        return result;
    }

private:

    // -----------------------------------------------------------------------
    // Internal per-chunk record stored in the pending map.
    // -----------------------------------------------------------------------
    struct Entry {
        Vec3i coord;      // which chunk this is
        int   tier;       // priority band (0 = most urgent)
        int   est_quads;  // estimated meshing cost in quads
    };

    // Map from packed 64-bit key → entry. unordered_map gives O(1) insert
    // and lookup for the dedup check, which matters when many chunks are
    // dirtied per frame (e.g. a large cave collapse marking 50+ chunks).
    std::unordered_map<uint64_t, Entry> entries_;

    // -----------------------------------------------------------------------
    // pack_key — deterministic 64-bit key for a chunk coord.
    //
    // WHY 21 BITS PER AXIS:
    // 21 bits can represent 2^21 = 2 097 152 distinct values. With a 32-voxel
    // chunk size and a 12 km world (120 000 voxels per axis), the chunk range
    // is ±1 875 chunks per axis. 21 bits biased by 2^20 (= 1 048 576) covers
    // ±1 048 576 chunks — comfortably larger than any planned world, with room
    // for future expansion. Three axes × 21 bits = 63 bits, fitting cleanly
    // into a uint64_t with one bit to spare.
    //
    // The bias (AXIS_BIAS) shifts the signed int32 range into an unsigned
    // 21-bit window so negative chunk coords pack correctly (e.g. chunk -1
    // maps to bias-1, not to a large unsigned number that might alias a
    // positive coord).
    //
    // This is the same 21-bit/axis brickmap convention referenced in the
    // project brief, applied to chunk coords instead of brick coords.
    // -----------------------------------------------------------------------
    static constexpr uint64_t AXIS_BIAS = (1u << 20);  // 1 048 576
    static constexpr uint64_t AXIS_MASK = (1u << 21) - 1u;  // 21-bit mask

    static uint64_t pack_key(const Vec3i& c) {
        uint64_t px = static_cast<uint64_t>(static_cast<int64_t>(c.x) + AXIS_BIAS) & AXIS_MASK;
        uint64_t py = static_cast<uint64_t>(static_cast<int64_t>(c.y) + AXIS_BIAS) & AXIS_MASK;
        uint64_t pz = static_cast<uint64_t>(static_cast<int64_t>(c.z) + AXIS_BIAS) & AXIS_MASK;
        // Pack: x in bits [0,20], y in bits [21,41], z in bits [42,62].
        return px | (py << 21) | (pz << 42);
    }

    // -----------------------------------------------------------------------
    // sq_dist — squared distance between two chunk coords.
    // No sqrt needed; we only compare distances, not measure them.
    // Uses int64_t to avoid overflow when coords are large (e.g. ±1M chunks).
    // -----------------------------------------------------------------------
    static int64_t sq_dist(const Vec3i& a, const Vec3i& b) {
        int64_t dx = static_cast<int64_t>(a.x) - b.x;
        int64_t dy = static_cast<int64_t>(a.y) - b.y;
        int64_t dz = static_cast<int64_t>(a.z) - b.z;
        return dx*dx + dy*dy + dz*dz;
    }
};

} // namespace mira
