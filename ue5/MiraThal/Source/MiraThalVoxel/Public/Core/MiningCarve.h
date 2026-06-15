// MiningCarve.h — the mining / felling carve GEOMETRY, ported engine-agnostic.
//
// Ported from Godot scripts/EditToolHandler.gd (the parts that are pure MATH —
// not the input polling, the raycast, the SFX, or the inventory yield). Design
// intent: design/MINING_TIME_SCALING.md. Used by the UE5 port AND the standalone
// clang parity harness, so it touches NO engine types — pure C++17 + std only.
//
// ----------------------------------------------------------------------------
// WHAT THIS IS, IN PLAIN ENGLISH:
//
// When the player swings a pickaxe / shovel / axe at a voxel surface, the game
// carves a CUBE of voxels out of the terrain. This file answers four questions
// about that swing, with no engine and no world-mutation of its own:
//
//   1. WHICH voxels does the cube cover?  -> compute_carve_box() returns the
//      [vmin, vmax] inclusive integer-voxel bounds, anchored INTO the terrain
//      along the surface normal so a 3x3x3 against a wall is 27 SOLID voxels,
//      not 18 solid + 9 air. (the DEPTH_BIASED anchor — the game default.)
//
//   2. HOW BIG is the cube?  -> the S / M / F scroll-wheel presets. Small=1x1x1
//      (one 10 cm voxel, precision), Medium=3x3x3 (the everyday bite),
//      Full=NxNxN where N is the tool's max bite (today 5 -> ~0.5 m).
//
//   3. HOW LONG does the swing take?  -> the physical-volume mining-time anchor.
//      Time scales by how big a PHYSICAL hole you take (cubic metres), NOT by a
//      raw voxel count, so a "normal swing" feels identical at any grid scale.
//      BASELINE_VOLUME_M3 = 8/216 m^3 is the historic "1.0x" reference bite.
//
//   4. The DRESSING passes that make a carve READ right:
//      - compute_destroy_preview(): the exact set of SOLID voxels a swing would
//        remove (for the faint glow overlay — equals reality, skips air/water).
//      - compute_roughen_set() (D2): after the main carve, deterministically
//        knock out ~22% of SOFT (dirt/grass/sand) voxels in the 1-voxel shell
//        just OUTSIDE the box, so the dug walls read as chewed, not laser-cut.
//        The roll is a HASH of world grid coords (salt 0x6B0BB1E) — no RNG — so
//        every multiplayer replica that recomputes the shell agrees exactly.
//
// ----------------------------------------------------------------------------
// PURITY: the world is abstracted behind one injected predicate where we need
// to know a voxel's material:
//
//   get_type_at(pos) -> int   the voxel's CHANNEL_TYPE material id (0 = air)
//
// In the Godot build the carve read the live VoxelTool; here the UE wrapper /
// the clang harness pass a lambda over a snapshot. The carve PRODUCES voxel-
// coordinate lists (plus the value to write, normally 0 = air); the wrapper
// feeds them to UVoxelEditSubsystem. compute_carve_box itself needs no world at
// all — it's pure integer geometry. Everything here is deterministic.

#pragma once

#include <cstdint>
#include <cmath>
#include <algorithm>
#include <functional>
#include <vector>
#include <unordered_set>

#include "Core/MiraVec.h"
#include "Core/VoxelScale.h"
#include "Core/MaterialIds.h"

namespace mira {

// A single resolved voxel write: "set the voxel at `pos` to `value`". The carve
// emits these so the UE wrapper can hand them straight to the edit subsystem.
// `value` is normally AIR_VOXEL (0) — a carve removes voxels — but it's explicit
// so a future "fill" verb can reuse the same plumbing.
struct VoxelWrite {
    Vec3i pos;
    int   value = 0;
};

namespace mining {

// Voxel value 0 = air. Writing this removes the voxel. (Mirrors mat::AIR.)
constexpr int AIR_VOXEL = 0;

// ---------------------------------------------------------------------------
// Carve-volume PRESETS (the scroll wheel cycles Small -> Medium -> Full).
// ---------------------------------------------------------------------------
// WHY PRESETS: the old scroll wheel nudged the carve size by 1 voxel (1..5). At
// 10 vox/m that's a lot of tiny in-between sizes nobody picks, and "4x4x4" is
// meaningless to a player. So it collapses to THREE named choices:
//
//   Small  = 1x1x1  — one 10 cm voxel. Precision: stairs, a single ore.
//   Medium = 3x3x3  — a ~0.3 m bite. The everyday dig (the boot default).
//   Full   = N^3    — the biggest bite this tool allows. N is the tool's
//                     swing_carve_voxels_per_side (default 5, so 5x5x5 ~ 0.5 m),
//                     kept tunable so a future tool tier can raise the max bite.
enum class CarvePreset { Small, Medium, Full };

// Fixed voxels-per-side for Small and Medium. Full is dynamic (reads the tool's
// max bite) so tool tiers can raise it without touching these.
constexpr int PRESET_SMALL_SIZE  = 1;
constexpr int PRESET_MEDIUM_SIZE = 3;

// The default tool's Full side length — swing_carve_voxels_per_side in the Godot
// export, 5 since the 10 vox/m pivot (was 3 at 6 vox/m), keeping a full swing
// removing roughly the same PHYSICAL ~0.5 m cube. Callers may pass their own.
constexpr int DEFAULT_FULL_SIZE = 5;

// Human-readable preset names for the HUD readout (mirrors PRESET_NAMES).
inline const char* preset_name(CarvePreset p) {
    switch (p) {
        case CarvePreset::Small:  return "Small";
        case CarvePreset::Medium: return "Medium";
        case CarvePreset::Full:   return "Full";
    }
    return "Medium";
}

// Translate a preset into the live "voxels per side" (the carve_volume_size that
// every downstream consumer reads). Full clamps to >= 1 defensively, exactly
// like _apply_carve_preset. `full_size` is the tool's max bite (DEFAULT_FULL_SIZE
// for the starter tools).
inline int preset_side(CarvePreset p, int full_size = DEFAULT_FULL_SIZE) {
    switch (p) {
        case CarvePreset::Small:  return PRESET_SMALL_SIZE;
        case CarvePreset::Medium: return PRESET_MEDIUM_SIZE;
        case CarvePreset::Full:   return full_size < 1 ? 1 : full_size;
    }
    return PRESET_MEDIUM_SIZE;
}

// ---------------------------------------------------------------------------
// The carve-volume ANCHOR: where the N^3 box sits around the aimed voxel.
// ---------------------------------------------------------------------------
enum class MiningAnchor {
    // Bias the box INTO the terrain along the dominant axis of the surface
    // normal. The surface voxel becomes the box's corner closest to the player,
    // so 3x3x3 against a wall is 27 terrain voxels (no wasted air slab). DEFAULT
    // — matches Minecraft / Vintage Story: aim at a surface, fill the terrain.
    DepthBiased,
    // Symmetric box centred on the surface voxel. The aim point sits in the
    // box's middle; on a flat cliff face one slab of the carve is air (the side
    // facing the player). Useful for precision work with predictable centering.
    Centered,
};

// An inclusive integer-voxel bounding box: every voxel v with vmin <= v <= vmax
// (component-wise) on all three axes. Matches the [box_vmin, box_vmax] pair the
// GDScript passed around as a 2-element Array.
struct CarveBox {
    Vec3i vmin;
    Vec3i vmax;

    // Voxel count of the box = (extent+1) on each axis, multiplied. For a clean
    // N^3 carve this is exactly N*N*N.
    int voxel_count() const {
        const int dx = (vmax.x - vmin.x) + 1;
        const int dy = (vmax.y - vmin.y) + 1;
        const int dz = (vmax.z - vmin.z) + 1;
        return dx * dy * dz;
    }
};

// ---------------------------------------------------------------------------
// Sign helper — mirrors Godot's sign() returning -1 / 0 / +1 for a float.
// Used to decide which way along an axis the depth-bias pushes the box.
// ---------------------------------------------------------------------------
inline int sign_i(float v) {
    if (v > 0.0f) return 1;
    if (v < 0.0f) return -1;
    return 0;
}

// ---------------------------------------------------------------------------
// compute_carve_box — the [vmin, vmax] bounds for an N-per-side carve.
// ---------------------------------------------------------------------------
// Ported 1:1 from EditToolHandler._compute_carve_box. `centre_voxel` is the
// integer-grid coord of the aimed voxel (floor(world_pos * VoxelsPerMeter)).
// `hit_normal` is the surface normal the raycast returned. `n` is the carve's
// voxels-per-side (preset_side()).
//
// Asymmetric half_lo / half_hi split for even N. A 2x2x2 carve has no exact
// symmetric anchoring around a single voxel — biasing toward +X/+Y/+Z keeps the
// aimed voxel as the box's MIN corner so an even-N carve never extends "behind"
// the aim point:
//   half_lo = (N-1)/2  (integer divide), half_hi = N/2
//   N=1: lo=0, hi=0 -> [c, c]       (1 voxel)
//   N=2: lo=0, hi=1 -> [c, c+1]     (2 voxels)
//   N=3: lo=1, hi=1 -> [c-1, c+1]   (3 voxels)
//   N=4: lo=1, hi=2 -> [c-1, c+2]   (4 voxels)
//
// DEPTH_BIASED then shifts the whole box INTO the terrain along the normal's
// dominant axis by half_hi voxels (opposite the outward normal), so the aimed
// surface voxel sits on the player-facing corner and the box fills terrain.
inline CarveBox compute_carve_box(const Vec3i& centre_voxel,
                                  const Vec3& hit_normal,
                                  int n,
                                  MiningAnchor anchor = MiningAnchor::DepthBiased) {
    const int half_lo = (n - 1) / 2;  // integer division, matches floori in GD
    const int half_hi = n / 2;

    CarveBox box;
    box.vmin = centre_voxel - Vec3i(half_lo, half_lo, half_lo);
    box.vmax = centre_voxel + Vec3i(half_hi, half_hi, half_hi);

    // Length-squared of the normal — skip the bias if it's effectively zero
    // (degenerate hit), matching the GDScript guard.
    const float nlen2 = hit_normal.x * hit_normal.x
                      + hit_normal.y * hit_normal.y
                      + hit_normal.z * hit_normal.z;

    if (anchor == MiningAnchor::DepthBiased && nlen2 > 0.0001f) {
        const float ax = hit_normal.x < 0.0f ? -hit_normal.x : hit_normal.x;
        const float ay = hit_normal.y < 0.0f ? -hit_normal.y : hit_normal.y;
        const float az = hit_normal.z < 0.0f ? -hit_normal.z : hit_normal.z;

        Vec3i bias(0, 0, 0);
        // Dominant axis wins; ties resolve x > y > z exactly as the GD if/elif.
        if (ax >= ay && ax >= az) {
            bias.x = -sign_i(hit_normal.x) * half_hi;
        } else if (ay >= az) {
            bias.y = -sign_i(hit_normal.y) * half_hi;
        } else {
            bias.z = -sign_i(hit_normal.z) * half_hi;
        }
        box.vmin = box.vmin + bias;
        box.vmax = box.vmax + bias;
    }

    return box;
}

// Convenience: world-space hit point -> centre voxel, the floor(world * VPM)
// conversion EditToolHandler does before computing the box. Note the GDScript
// first nudges the hit point 0.1 m (one voxel at 10 vox/m... actually a fixed
// 0.1 m) INTO the surface (hit_pos - normal * 0.1) so it lands on the solid
// voxel, not the air above it. We expose that as `surface_inset_m`.
inline Vec3i hit_to_centre_voxel(const Vec3& hit_pos,
                                 const Vec3& hit_normal,
                                 float surface_inset_m = 0.1f) {
    const Vec3 inset(hit_pos.x - hit_normal.x * surface_inset_m,
                     hit_pos.y - hit_normal.y * surface_inset_m,
                     hit_pos.z - hit_normal.z * surface_inset_m);
    const double vpm = scale::VoxelsPerMeter;
    // floori — round toward negative infinity, NOT truncate-toward-zero.
    auto floori = [](double d) -> int32_t {
        return static_cast<int32_t>(std::floor(d));
    };
    return Vec3i(floori(inset.x * vpm), floori(inset.y * vpm), floori(inset.z * vpm));
}

// ---------------------------------------------------------------------------
// compute_carve — the voxels a swing removes (the carve box, as writes).
// ---------------------------------------------------------------------------
// The Godot carve was a single VoxelEditManager.queue_edit_box_voxels(vmin,
// vmax, AIR) — i.e. EVERY voxel in the box becomes air, solid or not (writing
// air over air is a harmless no-op the edit layer collapses). We mirror that:
// emit an AIR write for every voxel in the inclusive box. The caller (or the
// destroy-preview) is what filters to "only the solid ones" when that matters.
inline std::vector<VoxelWrite> compute_carve(const CarveBox& box) {
    std::vector<VoxelWrite> out;
    out.reserve(static_cast<size_t>(box.voxel_count()));
    for (int x = box.vmin.x; x <= box.vmax.x; ++x) {
        for (int y = box.vmin.y; y <= box.vmax.y; ++y) {
            for (int z = box.vmin.z; z <= box.vmax.z; ++z) {
                out.push_back(VoxelWrite{Vec3i(x, y, z), AIR_VOXEL});
            }
        }
    }
    return out;
}

// One-shot overload: aimed voxel + normal + preset -> the carve writes. This is
// the "give me the swing" entry point the UE wrapper calls.
inline std::vector<VoxelWrite> compute_carve(const Vec3i& centre_voxel,
                                             const Vec3& hit_normal,
                                             CarvePreset preset,
                                             int full_size = DEFAULT_FULL_SIZE,
                                             MiningAnchor anchor = MiningAnchor::DepthBiased) {
    const int n = preset_side(preset, full_size);
    return compute_carve(compute_carve_box(centre_voxel, hit_normal, n, anchor));
}

// ---------------------------------------------------------------------------
// compute_destroy_preview — the EXACT solid voxels a swing would remove.
// ---------------------------------------------------------------------------
// For the faint-glow overlay: the player should see precisely which voxels
// vanish, so an aim that grazes a ridge (front 12 solid, rest air) lights up
// only those 12. We walk the carve box and keep only voxels that are SOLID
// terrain — non-air AND non-water (water isn't mined by tools, matching
// _hl_is_solid which rejects WaterMaterial.is_water_type). Pass-through flora /
// detail (24..28) read as solid in the Godot blocky read (mat_id != 0 and not
// water), so we keep that behaviour: only air and water are excluded.
inline std::vector<Vec3i> compute_destroy_preview(
        const CarveBox& box,
        const std::function<int(const Vec3i&)>& get_type_at) {
    std::vector<Vec3i> out;
    for (int x = box.vmin.x; x <= box.vmax.x; ++x) {
        for (int y = box.vmin.y; y <= box.vmax.y; ++y) {
            for (int z = box.vmin.z; z <= box.vmax.z; ++z) {
                const Vec3i p(x, y, z);
                const int t = get_type_at(p);
                if (t == AIR_VOXEL) continue;          // air — nothing to remove
                if (mat::is_water_type(t)) continue;   // water — tools don't mine it
                out.push_back(p);
            }
        }
    }
    return out;
}

// ===========================================================================
// D2 carve-roughen — deterministic wall grain.
// ===========================================================================
// Master switch for the grain pass (CARVE_ROUGHEN_ENABLED). Const-gated so it
// can be flipped off without ripping the code out if the look is disliked.
constexpr bool CARVE_ROUGHEN_ENABLED = true;

// ~22% of eligible (soft, exposed) shell voxels get knocked out — tuned so walls
// read as "chewed" without losing the carve's shape. (CARVE_ROUGHEN_CHANCE.)
constexpr float CARVE_ROUGHEN_CHANCE = 0.22f;

// Hash salt for the roughen roll — keeps it independent of any other coord-hash
// in the project (e.g. the generator's flora/detail scatter). (CARVE_ROUGHEN_SALT.)
constexpr int32_t CARVE_ROUGHEN_SALT = 0x6B0BB1E;

// Deterministic [0,1) hash of a voxel's WORLD GRID coords + the roughen salt.
// Ported 1:1 from _roughen_hash. Same coord -> same value on every machine, so
// the D2 grain is identical across multiplayer replicas. Pure integer math, no
// RNG state; mixing constants are the classic xorshift-spatial odd primes. The
// 0x7FFFFFFF mask keeps every step a non-negative 31-bit int exactly like the
// GDScript (& 0x7FFFFFFF after each xor), so the final /0x7FFFFFFF matches.
inline float roughen_hash(const Vec3i& vp) {
    // IMPORTANT: GDScript ints are 64-bit, so the GD original multiplies in
    // 64-bit and masks AFTER. We must match that bit-for-bit, so we carry the
    // intermediate in int64_t (a bare int32_t would overflow on the multiplies
    // — signed UB — before the & 0x7FFFFFFF clamp, diverging from the game and
    // from every multiplayer replica). The mask keeps every step a 31-bit
    // non-negative value, exactly as GD does.
    int64_t h = CARVE_ROUGHEN_SALT;
    h = (h ^ (static_cast<int64_t>(vp.x) * 73856093)) & 0x7FFFFFFF;
    h = (h ^ (static_cast<int64_t>(vp.y) * 19349663)) & 0x7FFFFFFF;
    h = (h ^ (static_cast<int64_t>(vp.z) * 83492791)) & 0x7FFFFFFF;
    // Final avalanche so neighbouring coords don't produce correlated rolls.
    h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF;
    return static_cast<float>(h) / static_cast<float>(0x7FFFFFFF);
}

// "Is this material SOFT diggable earth we may roughen?" — dirt / grass / sand
// only. Mirrors _is_soft_diggable, which compared the registry's id_string. The
// engine-agnostic Core keys off the material ids in MaterialIds.h instead. Stone
// / ore are never roughened (precision mining stays precise); water and the
// pass-through flora/detail block (24..28) are never roughened either.
inline bool is_soft_diggable(int type_id) {
    return type_id == mat::DIRT
        || type_id == mat::GRASS
        || type_id == mat::SAND;
}

// ---------------------------------------------------------------------------
// compute_roughen_set — the D2 extra air writes outside the carve box.
// ---------------------------------------------------------------------------
// Ported from _roughen_carve_walls. After the main carve, we look at the
// one-voxel-thick SHELL just outside the box's six faces (the box interior is
// already air). For each UNIQUE shell voxel that is SOFT earth, we roll the
// deterministic hash; if it's under CARVE_ROUGHEN_CHANCE the voxel is knocked
// out (becomes air) so the dug wall ends up bumpy instead of flat.
//
// The shell is de-duplicated (the GDScript used a Dictionary keyed by Vector3i;
// we use an unordered_set) so a voxel shared by two faces is considered once.
// We iterate the shell in a fixed, deterministic order (sorted ascending y,x,z)
// so the OUTPUT order is reproducible too — though correctness only needs the
// SET to match, the harness checks the set, and a stable order makes diffs easy.
//
// get_type_at supplies each shell voxel's current material id (read from the
// pre-roughen world; the box interior was just air-ed but the shell wasn't
// touched, so reads are correct). Voxels already air, or not soft, are skipped.
inline std::vector<VoxelWrite> compute_roughen_set(
        const CarveBox& box,
        const std::function<int(const Vec3i&)>& get_type_at) {
    std::vector<VoxelWrite> writes;
    if (!CARVE_ROUGHEN_ENABLED) return writes;

    // Collect the unique shell coords (the layer just outside each of the 6
    // box faces). De-dup so overlaps at the box's edges/corners count once.
    std::unordered_set<Vec3i> shell;
    // -X / +X faces.
    for (int y = box.vmin.y; y <= box.vmax.y; ++y) {
        for (int z = box.vmin.z; z <= box.vmax.z; ++z) {
            shell.insert(Vec3i(box.vmin.x - 1, y, z));
            shell.insert(Vec3i(box.vmax.x + 1, y, z));
        }
    }
    // -Y / +Y faces.
    for (int x = box.vmin.x; x <= box.vmax.x; ++x) {
        for (int z = box.vmin.z; z <= box.vmax.z; ++z) {
            shell.insert(Vec3i(x, box.vmin.y - 1, z));
            shell.insert(Vec3i(x, box.vmax.y + 1, z));
        }
    }
    // -Z / +Z faces.
    for (int x = box.vmin.x; x <= box.vmax.x; ++x) {
        for (int y = box.vmin.y; y <= box.vmax.y; ++y) {
            shell.insert(Vec3i(x, y, box.vmin.z - 1));
            shell.insert(Vec3i(x, y, box.vmax.z + 1));
        }
    }

    // Deterministic iteration: copy to a vector and sort (y, x, z) ascending.
    std::vector<Vec3i> shell_sorted(shell.begin(), shell.end());
    std::sort(shell_sorted.begin(), shell_sorted.end(),
              [](const Vec3i& a, const Vec3i& b) {
                  if (a.y != b.y) return a.y < b.y;
                  if (a.x != b.x) return a.x < b.x;
                  return a.z < b.z;
              });

    for (const Vec3i& vp : shell_sorted) {
        const int mat_id = get_type_at(vp);
        if (mat_id == AIR_VOXEL) continue;        // already air — nothing to chew
        if (!is_soft_diggable(mat_id)) continue;  // stone/ore/water/flora — leave it
        // Deterministic per-voxel roll on world grid coords.
        if (roughen_hash(vp) >= CARVE_ROUGHEN_CHANCE) continue;
        writes.push_back(VoxelWrite{vp, AIR_VOXEL});
    }
    return writes;
}

// ===========================================================================
// Physical-volume mining-time anchor (scale-proof).
// ===========================================================================
// WHY (plain English): mining time scales with how BIG a bite you take. We need
// a "normal swing" reference. The original was "8 voxels = 1.0x", but that 8 was
// authored at 6 vox/m, where 8 voxels is 8 / 6^3 = 8/216 ~ 0.037 m^3. When the
// world moved to 10 vox/m the raw 8 silently described a tinier hole, so the same
// real-world dig counted ~4.6x more voxels. The fix anchors on PHYSICAL VOLUME
// (m^3) and re-derives the voxel count at today's scale every run.
constexpr double BASELINE_VOLUME_M3 = 8.0 / 216.0;  // ~0.037 m^3 — the 1.0x bite.

// Non-preferred-tool penalty: mining a material with a tool not in its preferred
// list takes 3x the baseline swing time (WRONG_TOOL_SPEED_MULTIPLIER).
constexpr double WRONG_TOOL_SPEED_MULTIPLIER = 3.0;

// How many voxels the baseline (1.0x) bite is AT TODAY'S SCALE.
//   baseline_voxels = BASELINE_VOLUME_M3 * VoxelsPerMeter^3
//                   = (8/216) * 10^3 ~ 37.04 at 10 vox/m
//                   = (8/216) * 6^3  =  8     at the old 6 vox/m
inline double baseline_voxels() {
    const double vpm = scale::VoxelsPerMeter;
    return BASELINE_VOLUME_M3 * vpm * vpm * vpm;
}

// The carve-volume multiplier: how today's carve compares to the baseline bite.
//   multiplier = voxel_count / baseline_voxels
// So a 5^3 = 125-voxel Full swing is ~3.375x at 10 vox/m (exactly how the old
// 3^3 = 27-voxel default FELT at 6 vox/m: 27/8 = 3.375). A 1^3 Small carve is
// ~0.027x — a fast precision pick. maxf guard mirrors the GDScript's 0.0001.
inline double volume_multiplier(int voxel_count) {
    const double bv = baseline_voxels();
    return static_cast<double>(voxel_count) / (bv > 0.0001 ? bv : 0.0001);
}

// Final swing time for ONE carve. `slowest_per_voxel_secs` is the slowest
// material's per-voxel time in the box (material.mining_time_seconds *
// tool_multiplier — the slowest-wins scan lives in the wrapper, which reads the
// material table). We just apply the physical-volume scaling, mirroring the tail
// of _tick_held_action: mine_secs = slowest_per_voxel * (voxel_count / baseline).
inline double mining_time_secs(double slowest_per_voxel_secs, int voxel_count) {
    return slowest_per_voxel_secs * volume_multiplier(voxel_count);
}

} // namespace mining
} // namespace mira
