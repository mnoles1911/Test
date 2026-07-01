// Erosion.h — deterministic terrain EROSION for the AI-terrain Core (Phase 3).
//
// WHAT THIS IS (plain English):
//   Given a flat-ish AI-generated terrain heightfield, this module "weathers" it so
//   it looks like real geology: water runs downhill and carves valleys + branching
//   drainage networks, and loose material slumps off cliffs that are too steep to
//   stand. Two classic algorithms do the work:
//
//     * HYDRAULIC (droplet) erosion — the Sebastian Lague / Hans Beyer method.
//       We drop thousands of virtual rain droplets on the terrain. Each droplet
//       rolls downhill, picks up soil where the water moves fast (steep, downhill)
//       and drops it where the water slows down or pools (flat, uphill, basins).
//       Run enough droplets and you get carved river valleys and silted-up deltas.
//
//     * THERMAL (talus) erosion — where the slope between two neighbouring cells is
//       steeper than a material's natural "angle of repose" (the talus angle), the
//       overhang crumbles: material slides from the high cell to the low one until
//       the slope is stable. This conserves total mass (nothing is created or lost,
//       it just moves) and rounds off knife-edge ridges into believable scree slopes.
//
// UNITS: the grid holds terrain heights in VOXELS (the world is 10 voxels = 1 metre).
//   The grid is row-major, W columns by H rows; cell (x,z) lives at index z*W + x.
//   Cell-to-cell spacing is treated as 1 unit, so a "slope" here is simply the height
//   difference (in voxels) between adjacent cells.
//
// DETERMINISM IS MANDATORY. This feeds a multiplayer-bound terrain system, so the
//   SAME (grid, params, seed) MUST produce byte-identical output on every machine.
//   The ONLY source of randomness is droplet start positions, and those come solely
//   from the portable PCG64 RNG in PortableRng.h — never std::rand / std::mt19937 /
//   wall-clock time. All arithmetic is plain IEEE-754 float/double (+,-,*,/,sqrt),
//   evaluated in a fixed order, so the result does not drift between compilers/CPUs.
//
// BORDERS: every neighbour/corner read is CLAMPED to the grid edge — never wraps,
//   never reads out of bounds. A cell on the edge simply sees itself as its own
//   off-grid neighbour (slope 0 there), so nothing flows across the boundary.
//
// Pure C++17, header-only, no engine headers -> lives in Core/ so the standalone
// clang harness (tests/standalone) can verify it before any Unreal build.
#pragma once

#include "Core/Tdiff/PortableRng.h"   // mira::tdiff::pcg64_next / next_seed (the ONLY RNG)

#include <cstdint>
#include <cmath>      // std::sqrt, std::floor
#include <algorithm>  // std::fill
#include <vector>

namespace mira {
namespace tdiff {

// ---------------------------------------------------------------------------
// Tunable knobs. Every field is commented in plain English; the defaults are
// sensible starting points that give visible-but-not-destructive weathering.
// ---------------------------------------------------------------------------
struct ErosionParams
{
    // ----- HYDRAULIC (droplet rain) -----

    // How many droplets to simulate, expressed PER GRID CELL so the effort scales
    // with map size automatically (total droplets = round(dropletsPerCell * W * H)).
    // 0.5 means "one droplet for every two cells" — enough to carve clear channels
    // without taking forever. Raise for deeper, more mature drainage networks.
    float dropletsPerCell = 0.5f;

    // The most steps a single droplet is allowed to take before we retire it. Longer
    // lifetimes let a droplet travel further downhill and carve longer rivers, but
    // cost more time. 30 is the classic default.
    int   maxDropletLifetime = 30;

    // Inertia: how much a droplet keeps its previous direction vs. turning straight
    // downhill (0 = always follow the steepest descent, 1 = never turn). A little
    // inertia (0.05) makes droplets carve smoother, more natural meanders.
    float inertia = 0.05f;

    // Sediment capacity factor: how much soil a droplet can carry, per unit of speed,
    // water and downhill drop. Higher = droplets carry more = deeper carving.
    float sedimentCapacityFactor = 4.0f;

    // A floor on capacity so that even a slow droplet on near-flat ground can still
    // carry a tiny bit of sediment (prevents it from dumping everything instantly).
    float minSedimentCapacity = 0.01f;

    // Deposition rate: the fraction of "excess" sediment a droplet drops each step
    // when it is over capacity (0..1). Higher = fills basins/valleys faster.
    float depositionRate = 0.3f;

    // Erosion rate: the fraction of the remaining capacity a droplet claws out of the
    // ground each step when it has room to carry more (0..1). Higher = digs harder.
    float erosionRate = 0.3f;

    // Evaporation: the fraction of the droplet's water that disappears each step
    // (0..1). As water evaporates the droplet loses carrying power and settles out,
    // which is what leaves silt at the end of a river's run.
    float evaporation = 0.01f;

    // Gravity: scales how much a downhill drop accelerates the droplet. Faster water
    // erodes more. 4.0 is the classic default.
    float gravity = 4.0f;

    // Erosion radius: when a droplet digs, it removes material from a soft circular
    // brush of this radius (in cells) around it, not a single cell. This spreads the
    // cut so valleys have smooth banks instead of 1-cell-wide spikes. 0 = single cell.
    int   erosionRadius = 3;

    // Starting water volume and speed for every droplet. Rarely need changing.
    float initialWater = 1.0f;
    float initialSpeed = 1.0f;

    // ----- THERMAL (talus / slumping) -----

    // Talus threshold: the MAX stable height difference (in voxels) between two
    // adjacent cells. Any slope steeper than this is unstable and material slides
    // down until it is back within the limit. Smaller = terrain slumps to gentler,
    // rounder slopes; larger = allows steeper cliffs to survive.
    float thermalTalus = 4.0f;

    // How many thermal relaxation passes to run. Each pass moves a little material;
    // more passes settle steeper terrain more fully. 8 is a good default.
    int   thermalIterations = 8;

    // Thermal strength: what fraction of the "excess" over the talus limit to move
    // per pass (0..1). ~0.5 is stable and converges quickly; higher can overshoot.
    float thermalStrength = 0.5f;
};

// ===========================================================================
// Small internal helpers (kept in the header so this stays engine-free).
// ===========================================================================
namespace detail_erosion {

// Clamp an integer coordinate into [0, hi] so we never index outside the grid.
inline int clampi(int v, int hi)
{
    if (v < 0)  return 0;
    if (v > hi) return hi;
    return v;
}

// A single brush cell: an (dx,dy) offset from the droplet and a normalized weight.
struct BrushCell { int dx; int dy; float weight; };

// Build a soft circular brush of the given radius whose weights sum to 1.
// weight = (1 - dist/radius), so the centre digs hardest and the rim barely at all.
// radius 0 collapses to a single centre cell (weight 1).
inline std::vector<BrushCell> build_brush(int radius)
{
    std::vector<BrushCell> brush;
    if (radius <= 0)
    {
        brush.push_back(BrushCell{0, 0, 1.0f});
        return brush;
    }
    const float r = static_cast<float>(radius);
    float total = 0.0f;
    for (int dy = -radius; dy <= radius; ++dy)
    {
        for (int dx = -radius; dx <= radius; ++dx)
        {
            const float dist = std::sqrt(static_cast<float>(dx * dx + dy * dy));
            if (dist < r)
            {
                const float w = 1.0f - dist / r;
                brush.push_back(BrushCell{dx, dy, w});
                total += w;
            }
        }
    }
    // Normalize so a full brush removes exactly the requested amount of material.
    if (total > 0.0f)
    {
        const float inv = 1.0f / total;
        for (BrushCell& c : brush) { c.weight *= inv; }
    }
    return brush;
}

// Bilinear height sample + surface gradient at floating-point position (px,pz).
// Returns height and the gradient (gx,gz) = direction of INCREASING height, so a
// droplet flows along the NEGATIVE gradient. All four corner reads are clamped.
struct HeightGrad { float height; float gx; float gz; };

inline HeightGrad sample_height_grad(const float* grid, int W, int H, float px, float pz)
{
    const int nodeX = static_cast<int>(std::floor(px));
    const int nodeZ = static_cast<int>(std::floor(pz));
    const float fx = px - static_cast<float>(nodeX); // fractional offset within cell
    const float fz = pz - static_cast<float>(nodeZ);

    const int x0 = clampi(nodeX,     W - 1);
    const int x1 = clampi(nodeX + 1, W - 1);
    const int z0 = clampi(nodeZ,     H - 1);
    const int z1 = clampi(nodeZ + 1, H - 1);

    const float hNW = grid[z0 * W + x0];
    const float hNE = grid[z0 * W + x1];
    const float hSW = grid[z1 * W + x0];
    const float hSE = grid[z1 * W + x1];

    HeightGrad out;
    out.gx = (hNE - hNW) * (1.0f - fz) + (hSE - hSW) * fz;
    out.gz = (hSW - hNW) * (1.0f - fx) + (hSE - hNE) * fx;
    out.height = hNW * (1.0f - fx) * (1.0f - fz)
               + hNE * fx * (1.0f - fz)
               + hSW * (1.0f - fx) * fz
               + hSE * fx * fz;
    return out;
}

} // namespace detail_erosion

// ===========================================================================
// (2) HYDRAULIC EROSION — droplet-based (Lague / Beyer style).
//
// Simulates N rain droplets. Each starts at a seeded-random spot, rolls downhill
// with a little inertia, erodes soil where the water runs fast/downhill and
// deposits it where the water slows or pools, and slowly evaporates. The net
// effect over many droplets: carved valleys + drainage networks, silt in basins.
// ===========================================================================
inline void erode_hydraulic(float* grid, int W, int H, const ErosionParams& p, uint64_t seed)
{
    using namespace detail_erosion;
    if (grid == nullptr || W < 2 || H < 2) { return; } // nothing sensible to erode

    // Precompute the digging brush once (relative offsets + normalized weights).
    const std::vector<BrushCell> brush = build_brush(p.erosionRadius);

    // How many droplets? Scale with area; always at least one if the map is non-empty.
    long long count = static_cast<long long>(
        static_cast<double>(p.dropletsPerCell) * static_cast<double>(W) * static_cast<double>(H) + 0.5);
    if (count < 0) { count = 0; }

    // Deterministic RNG stream: derive the working state from the seed via the
    // portable PCG64 helper. Same seed -> same stream on every machine.
    uint64_t rng = next_seed(seed);
    const double inv2p32 = 1.0 / 4294967296.0; // 1 / 2^32, to map uint32 -> (0,1)

    const float maxX = static_cast<float>(W - 1);
    const float maxZ = static_cast<float>(H - 1);

    for (long long d = 0; d < count; ++d)
    {
        // --- Seed a random start position (the ONLY randomness in the whole sim) ---
        const uint32_t rx = pcg64_next(rng);
        const uint32_t rz = pcg64_next(rng);
        float posX = static_cast<float>((static_cast<double>(rx) + 0.5) * inv2p32) * maxX;
        float posZ = static_cast<float>((static_cast<double>(rz) + 0.5) * inv2p32) * maxZ;

        float dirX = 0.0f, dirZ = 0.0f;
        float speed    = p.initialSpeed;
        float water    = p.initialWater;
        float sediment = 0.0f;

        for (int life = 0; life < p.maxDropletLifetime; ++life)
        {
            // Height + gradient at the droplet's CURRENT cell (the cell it will
            // deposit into / erode around this step).
            const int nodeX = static_cast<int>(std::floor(posX));
            const int nodeZ = static_cast<int>(std::floor(posZ));
            const float cellX = posX - static_cast<float>(nodeX);
            const float cellZ = posZ - static_cast<float>(nodeZ);
            const HeightGrad hg = sample_height_grad(grid, W, H, posX, posZ);

            // Turn the droplet: blend old direction (inertia) with steepest descent.
            dirX = dirX * p.inertia - hg.gx * (1.0f - p.inertia);
            dirZ = dirZ * p.inertia - hg.gz * (1.0f - p.inertia);

            // Normalize to a unit step (so lifetime ~ distance travelled).
            const float len = std::sqrt(dirX * dirX + dirZ * dirZ);
            if (len != 0.0f) { dirX /= len; dirZ /= len; }

            posX += dirX;
            posZ += dirZ;

            // Stopped (no downhill) or ran off the edge of the map -> retire droplet.
            if ((dirX == 0.0f && dirZ == 0.0f) ||
                posX < 0.0f || posX > maxX || posZ < 0.0f || posZ > maxZ)
            {
                break;
            }

            // Height at the NEW position; how far did we drop (negative) or climb (positive)?
            const float newHeight = sample_height_grad(grid, W, H, posX, posZ).height;
            const float deltaHeight = newHeight - hg.height;

            // How much sediment can this droplet carry right now?
            float capacity = -deltaHeight * speed * water * p.sedimentCapacityFactor;
            if (capacity < p.minSedimentCapacity) { capacity = p.minSedimentCapacity; }

            if (sediment > capacity || deltaHeight > 0.0f)
            {
                // Over capacity, or heading UPHILL -> DEPOSIT into the old cell.
                // Uphill: fill the pit up to (at most) the step we just climbed.
                float deposit = (deltaHeight > 0.0f)
                    ? (deltaHeight < sediment ? deltaHeight : sediment)
                    : (sediment - capacity) * p.depositionRate;
                sediment -= deposit;

                // Spread the deposit across the four corners of the OLD cell,
                // weighted by how close the droplet was to each (bilinear), clamped.
                const int ox0 = clampi(nodeX,     W - 1);
                const int ox1 = clampi(nodeX + 1, W - 1);
                const int oz0 = clampi(nodeZ,     H - 1);
                const int oz1 = clampi(nodeZ + 1, H - 1);
                grid[oz0 * W + ox0] += deposit * (1.0f - cellX) * (1.0f - cellZ);
                grid[oz0 * W + ox1] += deposit * cellX          * (1.0f - cellZ);
                grid[oz1 * W + ox0] += deposit * (1.0f - cellX) * cellZ;
                grid[oz1 * W + ox1] += deposit * cellX          * cellZ;
            }
            else
            {
                // Room to carry more -> ERODE. Never dig deeper than the drop itself
                // (so we can't invert the slope), and spread the cut over the brush.
                float erodeAmt = (capacity - sediment) * p.erosionRate;
                const float maxCut = -deltaHeight; // deltaHeight < 0 here, so this is > 0
                if (erodeAmt > maxCut) { erodeAmt = maxCut; }

                for (const BrushCell& bc : brush)
                {
                    const int bx = clampi(nodeX + bc.dx, W - 1);
                    const int bz = clampi(nodeZ + bc.dy, H - 1);
                    grid[bz * W + bx] -= erodeAmt * bc.weight;
                }
                sediment += erodeAmt;
            }

            // Update speed from the drop (fast water where it falls) and evaporate.
            float speedSq = speed * speed + deltaHeight * p.gravity;
            speed = std::sqrt(speedSq > 0.0f ? speedSq : 0.0f);
            water *= (1.0f - p.evaporation);
        }
    }
}

// ===========================================================================
// (3) THERMAL EROSION — talus / slumping. CONSERVES TOTAL MASS.
//
// Wherever the height difference to a lower neighbour exceeds the talus limit,
// move the excess material downhill until the slope is stable. Each pass reads
// the whole grid, computes all the moves into a separate delta buffer, then
// applies them at once (so every cell sees the same "before" state). Every move
// subtracts exactly what it adds, so the grid's total height is preserved.
// ===========================================================================
inline void erode_thermal(float* grid, int W, int H, const ErosionParams& p)
{
    using namespace detail_erosion;
    if (grid == nullptr || W < 1 || H < 1) { return; }

    const float talus = p.thermalTalus;
    const int iters = p.thermalIterations;

    // The 4 orthogonal neighbours (von Neumann). Border reads are clamped to the
    // edge, which yields a self-neighbour (slope 0) so no material leaves the map.
    const int NX[4] = { -1, 1, 0, 0 };
    const int NZ[4] = { 0, 0, -1, 1 };

    std::vector<float> delta(static_cast<size_t>(W) * static_cast<size_t>(H));

    for (int it = 0; it < iters; ++it)
    {
        std::fill(delta.begin(), delta.end(), 0.0f);

        for (int z = 0; z < H; ++z)
        {
            for (int x = 0; x < W; ++x)
            {
                const float h = grid[z * W + x];

                // Look at the (up to) 4 neighbours; find those enough lower to slump.
                float diff[4];
                float sumDiff = 0.0f;
                float maxDiff = 0.0f;
                for (int k = 0; k < 4; ++k)
                {
                    const int nx = clampi(x + NX[k], W - 1);
                    const int nz = clampi(z + NZ[k], H - 1);
                    const float dh = h - grid[nz * W + nx];
                    if (dh > talus)
                    {
                        diff[k] = dh;
                        sumDiff += dh;
                        if (dh > maxDiff) { maxDiff = dh; }
                    }
                    else
                    {
                        diff[k] = 0.0f;
                    }
                }

                if (sumDiff <= 0.0f) { continue; } // this cell is already stable

                // Total material to shed this pass: a fraction of the worst overshoot.
                const float totalMove = p.thermalStrength * (maxDiff - talus) * 0.5f;

                // Distribute it to the lower neighbours in proportion to their drop.
                // Accumulate exactly what we hand out, then remove that same sum from
                // this cell -> per-cell mass balance is exact (no drift).
                float moved = 0.0f;
                for (int k = 0; k < 4; ++k)
                {
                    if (diff[k] > 0.0f)
                    {
                        const int nx = clampi(x + NX[k], W - 1);
                        const int nz = clampi(z + NZ[k], H - 1);
                        const float portion = totalMove * (diff[k] / sumDiff);
                        delta[nz * W + nx] += portion;
                        moved += portion;
                    }
                }
                delta[z * W + x] -= moved;
            }
        }

        // Apply all the moves at once.
        const size_t n = static_cast<size_t>(W) * static_cast<size_t>(H);
        for (size_t i = 0; i < n; ++i) { grid[i] += delta[i]; }
    }
}

// ===========================================================================
// (4) erode() — convenience pipeline: settle steep bits first (thermal), carve
// with rain (hydraulic), then a final thermal pass to smooth the fresh banks.
// ===========================================================================
inline void erode(float* grid, int W, int H, const ErosionParams& p, uint64_t seed)
{
    if (grid == nullptr || W < 2 || H < 2) { return; }
    erode_thermal(grid, W, H, p);          // a few thermal passes (settle cliffs)
    erode_hydraulic(grid, W, H, p, seed);  // rain carves valleys + drainage
    erode_thermal(grid, W, H, p);          // final thermal smooth of the new banks
}

} // namespace tdiff
} // namespace mira
