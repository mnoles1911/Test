// VoxelGravity.h — engine-agnostic port of the voxel gravity / sever flood-fill.
//
// WHAT THIS DOES (plain English):
// When you blast or chop away the voxels that were holding something up, the
// game has to answer one question fast: "which chunks of the world are now
// floating, disconnected from the ground, and should therefore fall?"
//
// We answer it with a flood-fill. Think of pouring water in from the ground:
// every solid voxel the water can reach (walking 6 directions through other
// solids) is "anchored" — it's still attached to the world and stays put.
// Anything the water can't reach is floating, and gets sorted into how it
// should fall:
//   * LOOSE       — sand/gravel-like: each cell drops straight down its column
//                   until it lands on something anchored.
//   * PICKUP_DROP — small drop-able items: pop into a pickup, no physics body.
//   * everything else (NEVER / SOLID / unknown) — gets grouped by a SECOND
//     flood-fill into connected CLUSTERS, so a chopped tree detaches as one
//     rigid falling lump instead of a hail of single voxels.
//
// Ported 1:1 from the Godot parity reference scripts/_dev/GravityReference.gd
// (which is itself the stripped-down pure core of VoxelGravityManager's
// _process_bubble inner loop) and cross-checked against the godot-cpp
// extension extensions/voxel_gen/src/voxel_gravity_cpp.cpp. This Core version
// has ZERO engine types — the world is read through an injected predicate, so
// the exact same math compiles inside Unreal AND under clang for parity tests.
//
// The optional "sever follow" BFS at the bottom mirrors
// scripts/_dev/SeverFollowLib.gd — it lets a caller chase a severed tree-trunk
// upward past the analysis box's roof so the whole tree falls as ONE cluster.
//
// Keep this header free of engine headers — only the std library + MiraVec.h.

#pragma once

#include <cstdint>
#include <functional>
#include <vector>
#include <unordered_map>

#include "Core/MiraVec.h"

namespace mira {

// ---------------------------------------------------------------------------
// Fall-behavior enum mirror (Godot scripts/VoxelMaterial.gd FallBehavior).
//
// These int values ARE the storage representation: the Godot reference, the
// godot-cpp extension, and this Core port all agree on them BY VALUE. Do not
// renumber — save data and the fall_table snapshot depend on these integers.
//   NEVER = 0, SOLID = 1, LOOSE = 2, LIQUID = 3, PICKUP_DROP = 4
// ---------------------------------------------------------------------------
enum FallBehavior : int {
    FALL_NEVER       = 0,
    FALL_SOLID       = 1,
    FALL_LOOSE       = 2,
    FALL_LIQUID      = 3,
    FALL_PICKUP_DROP = 4,
};

// R4 flora + D1 surface-detail pass-through range (mirrors Godot
// scripts/FloraMaterial.gd + GravityReference: 24..28 = grass/flowers 24..26
// PLUS pebbles/twigs 27..28). Every one of these decoration ids is treated as
// PASS-THROUGH AIR for the gravity analysis: a grass blade, flower, pebble or
// twig must NEVER anchor a structure (so a tree can't "connect" to the ground
// through one) and must NEVER be carried in a falling cluster. Kept as a plain
// literal range — exactly like the Godot side — so the cross-language contract
// is a constant both ends agree on by value.
static constexpr int PASSTHROUGH_BASE_ID = 24;
static constexpr int PASSTHROUGH_COUNT   = 5;   // 24..28 inclusive

// True if a packed voxel value's low byte is a pass-through decoration id.
inline bool IsFloraType(int32_t packed) {
    const int t = packed & 0xFF;
    return t >= PASSTHROUGH_BASE_ID && t < PASSTHROUGH_BASE_ID + PASSTHROUGH_COUNT;
}

// ---------------------------------------------------------------------------
// Result types.
//
// In the Godot build these come back as flat PackedInt32Array streams to dodge
// per-Variant marshalling cost. Here in pure C++ there's no marshalling tax, so
// we return honest little structs — the UE wrapper layer flattens them at the
// boundary if it wants the stream format.
// ---------------------------------------------------------------------------

// One LOOSE voxel that should slide straight down its column.
struct LooseMove {
    Vec3i   from;    // where the voxel is now (bubble-local coords)
    Vec3i   to;      // where it lands (same x/z, lower y)
    int32_t packed;  // the full packed TYPE value being moved
};

// One PICKUP_DROP voxel that should pop into a collectible.
struct PickupDrop {
    Vec3i   pos;     // bubble-local coords
    int32_t packed;  // the full packed TYPE value
};

// One voxel belonging to a falling cluster.
struct ClusterVoxel {
    Vec3i   pos;     // bubble-local coords
    int32_t packed;  // the full packed TYPE value
};

// Everything analyze_bubble found, in the same shape as the Godot return Dict.
struct GravityResult {
    std::vector<LooseMove>    loose;            // LOOSE column-fall moves
    std::vector<PickupDrop>   pickup;           // PICKUP_DROP pop-outs
    std::vector<int>          cluster_counts;   // voxel count per cluster
    std::vector<ClusterVoxel> cluster_voxels;   // all cluster voxels, segmented
                                                // by cluster_counts in order
    int bubble_solid_count       = 0;           // total non-air, non-flora cells
    int unanchored_cluster_count = 0;           // sum of cluster_counts
};

// ---------------------------------------------------------------------------
// analyze_bubble — the main port.
//
// Runs the whole pipeline over a cubic region of side `side` (bubble-local
// coords run 0..side-1 on each axis):
//   1. Read pass     — gather solid voxels (skip air, skip flora pass-through).
//   2. Anchor seed   — y==0 (bottom face = the ground) plus any cell flagged
//                      by the NoEditZone mask is an anchor.
//   3. Anchor flood  — 6-connected flood-fill spreads "anchored" through solids.
//   4. Partition     — unanchored solids split into LOOSE / PICKUP / cluster
//                      by their fall_behavior.
//   5. LOOSE fall    — each loose cell drops down its column to a landing.
//   6. Cluster BFS   — connected-component flood over the cluster cells.
//
// Inputs (all injected so the Core never touches an engine):
//   side         — cube edge length in voxels.
//   get_packed   — returns the packed CHANNEL_TYPE value at a bubble-local
//                  coord (low byte = material id). 0 means air. The caller maps
//                  this onto whatever its real voxel buffer is.
//   fall_of      — material id (low byte) -> FallBehavior int. Mirrors the
//                  fall_table snapshot; default to FALL_NEVER for unknown ids.
//   is_anchor_mask — optional. Given a bubble-local coord, returns true if that
//                  cell is a NoEditZone anchor (always-attached terrain). Pass
//                  an empty std::function (or nullptr-wrapped) for "no zones".
//
// The semantics — iteration order, stack-based flood, (y,x,z) loose sort,
// cluster neighbour gate — are preserved exactly from the Godot reference so a
// diff against it stays set-for-set identical.
// ---------------------------------------------------------------------------
GravityResult analyze_bubble(
    int side,
    const std::function<int32_t(const Vec3i&)>& get_packed,
    const std::function<int(int /*mat_id*/)>&    fall_of,
    const std::function<bool(const Vec3i&)>&     is_anchor_mask = {});

// ---------------------------------------------------------------------------
// Sever-follow BFS — port of scripts/_dev/SeverFollowLib.gd continue_bfs.
//
// Once analyze_bubble decides a cluster is severed AND that cluster touches the
// roof of the analysis box, the caller can chase the connected solids UPWARD
// into a taller extension box so a whole chopped tree falls as one piece instead
// of bubble-height salami slices. This is that chase: a 6-connected solid flood
// from the seed cells, treating water AND flora/decoration as pass-through air,
// that REFUSES to grow back down past the bubble roof (nb.y < 0 is rejected).
//
// CONSERVATIVE BY DESIGN. If the flood reaches a side/top wall, or runs over
// budget, it sets the matching abort flag and stops — the caller then keeps the
// old, correct-but-uglier salami behaviour rather than risk ripping up terrain
// it never proved was severed.
//
// Inputs:
//   box_size   — dimensions of the extension box (voxels) on each axis.
//   seeds      — box-local coords to start from (just above the bubble roof).
//   is_solid_at— given a box-local coord, true if that cell is SOLID and should
//                ride the cluster. The caller bakes the "non-air, non-water,
//                non-flora" test into this predicate (matching the GD branch
//                set: skip type==0, water types, and flora pass-through 24..28).
//   get_packed — packed TYPE value at a box-local coord (for the carried list).
//   max_voxels — budget; exceeding it aborts (reported via touched_top).
// ---------------------------------------------------------------------------
struct SeverFollowResult {
    // Carried voxels keyed by box-local coord -> packed TYPE value. Order is the
    // BFS visit order (deterministic given the seed order + neighbour order).
    std::vector<ClusterVoxel> voxels;
    bool touched_side = false;  // reached an X/Z wall — possible anchored arch
    bool touched_top  = false;  // reached the top Y, or blew the voxel budget
};

SeverFollowResult sever_follow_bfs(
    const Vec3i&                                 box_size,
    const std::vector<Vec3i>&                    seeds,
    const std::function<bool(const Vec3i&)>&     is_solid_at,
    const std::function<int32_t(const Vec3i&)>&  get_packed,
    int                                          max_voxels);

} // namespace mira
