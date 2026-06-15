// BandPolicy.h — decides how each chunk is drawn, and which bricks stay resident.
//
// THE THREE BANDS (plain English): we can't draw the whole world the expensive way,
// so each chunk falls into one of three treatments by distance + how recently it was
// edited:
//   HOT  — near AND recently dug. Drawn with the live dynamic mesher (+ collision,
//          + Lumen). This is the only band you can edit in real time.
//   COLD — near but untouched for a while. Baked to a cheap static (Nanite) mesh.
//          The instant it's edited again it snaps back to HOT.
//   FAR  — far away. Not meshed at all; ray-marched from the brickmap. No collision.
//
// HYSTERESIS: a chunk sitting exactly on the near/far line must not flip band every
// frame as the camera jitters (that would thrash meshing). So the near<->far switch
// uses two thresholds — you cross OUT to FAR past `far_radius`, but only come back to
// near once you're `hysteresis` chunks inside it again. The HOT->COLD switch is its
// own natural hysteresis: a chunk must go `cold_dwell_seconds` with no edit to cool,
// and any edit resets that timer to 0 (instant re-HOT).
//
// RESIDENCY: only so many bricks fit in memory near the player. LruResidency tracks
// "least recently used" so when we go over budget we evict the brick nobody has
// touched in the longest. Pure C++17, no engine types. `bands` selector.

#pragma once

#include <cstddef>
#include <list>
#include <unordered_map>
#include "Core/MiraVec.h"

namespace mira {
namespace bands {

enum class Band { HOT, COLD, FAR };

// Tunables. Distances are in CHUNK units (1.0 == one 32-voxel chunk edge).
struct BandConfig {
    float far_radius          = 8.0f;  // beyond this many chunks -> FAR (ray-marched)
    float hysteresis          = 1.0f;  // chunks you must re-enter before leaving FAR
    float cold_dwell_seconds  = 5.0f;  // unedited this long in the near band -> COLD
};

// Classify one chunk. `dist_chunks` = camera distance in chunk units. `prev` = the
// band it had last frame (for hysteresis). `seconds_since_edit` = time since this
// chunk was last edited (0 right after an edit). An out-of-range/never-edited chunk
// passes a large seconds_since_edit so it cools normally.
inline Band classify(float dist_chunks, Band prev, float seconds_since_edit,
                     const BandConfig& cfg = BandConfig{}) {
    // Near <-> FAR with hysteresis: leave near only past far_radius; return to near
    // only once back inside (far_radius - hysteresis).
    const bool is_far = (prev == Band::FAR)
        ? (dist_chunks > cfg.far_radius - cfg.hysteresis) // stay FAR until well inside
        : (dist_chunks > cfg.far_radius);                 // become FAR only past the line
    if (is_far) return Band::FAR;

    // Inside the near band: recency decides. A fresh edit (small seconds_since_edit)
    // keeps it HOT; once it's been quiet for cold_dwell_seconds it bakes to COLD.
    if (seconds_since_edit < cfg.cold_dwell_seconds) return Band::HOT;
    return Band::COLD;
}

// ---------------------------------------------------------------------------
// LruResidency — a fixed-capacity "keep the most recently used" set.
//
// touch(k) marks k as just-used (most recent). If that pushes the set over
// capacity, the least-recently-used key is evicted and returned via `evicted`.
// Used for brick residency; Key is usually Vec3i (which ships a std::hash).
// ---------------------------------------------------------------------------
template <class Key>
class LruResidency {
public:
    explicit LruResidency(size_t capacity) : capacity_(capacity == 0 ? 1 : capacity) {}

    size_t size() const { return pos_.size(); }
    size_t capacity() const { return capacity_; }
    bool contains(const Key& k) const { return pos_.find(k) != pos_.end(); }

    // Mark k as most-recently-used (inserting it if new). Returns true if an
    // eviction happened, writing the evicted key to `evicted`.
    bool touch(const Key& k, Key& evicted) {
        auto it = pos_.find(k);
        if (it != pos_.end()) {
            order_.splice(order_.begin(), order_, it->second); // move to front
            return false;
        }
        order_.push_front(k);
        pos_[k] = order_.begin();
        if (pos_.size() > capacity_) {
            evicted = order_.back();
            pos_.erase(evicted);
            order_.pop_back();
            return true;
        }
        return false;
    }

    // The least-recently-used key (back of the order). Caller checks size() first.
    const Key& lru() const { return order_.back(); }

    void clear() { order_.clear(); pos_.clear(); }

private:
    size_t capacity_;
    std::list<Key> order_; // front = most recent, back = least recent
    std::unordered_map<Key, typename std::list<Key>::iterator> pos_;
};

} // namespace bands
} // namespace mira
