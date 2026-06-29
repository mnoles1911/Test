// Brickmap.h — the sparse, authoritative CPU store for the voxel world.
//
// THE BIG IDEA (plain English): the world is enormous and mostly air, so we do
// NOT keep a giant dense array. Instead we chop space into BRICKS — 8x8x8 blocks
// of voxels — and only keep the bricks that actually contain something. A brick
// nobody has touched simply doesn't exist, and reads there return air. Editing a
// voxel touches exactly one brick (O(1)), not the whole world. This one structure
// is the single source of truth that the mesher, the water/gravity sim, collision,
// and the GPU mirror all read from.
//
// It also provides the RAY-MARCH (raycast_solid): walk a ray through the world and
// report the first solid voxel it hits. This is the CPU reference oracle — when the
// GPU far-field renderer ray-marches the same world in HLSL, its hits must match
// this function voxel-for-voxel. (The brick index — has_brick / brick_solid_count —
// is exposed so the GPU can do the coarse "skip whole empty bricks" optimisation;
// this reference walks voxels for obvious correctness, which is the oracle's job.)
//
// Pure C++17, no engine types. `brickmap` selector pins storage + traversal.

#pragma once

#include <cstdint>
#include <array>
#include <cmath>
#include <unordered_map>
#include "Core/MiraVec.h"
#include "Core/ChunkCoords.h"
#include "Core/MaterialIds.h"

namespace mira {

// One 8x8x8 brick: the two voxel channels plus two small occupancy counters that
// let us answer "is this brick worth meshing / ray-stepping?" without scanning it.
struct Brick {
    std::array<uint8_t, coords::VOXELS_PER_BRICK> type{};  // material id, 0 = air
    std::array<uint8_t, coords::VOXELS_PER_BRICK> water{}; // WaterByteCodec byte

    int solid_count   = 0; // voxels with type != AIR  (drives ray empty-skip)
    int nonzero_count = 0; // voxels with type!=0 OR water!=0 (drives sparse GC)
};

class Brickmap {
public:
    // ---- Voxel reads (absent brick => air / no water) ----
    uint8_t type_at(const Vec3i& v) const {
        const Brick* b = find_brick(coords::brick_of_voxel(v));
        return b ? b->type[local_index(v)] : static_cast<uint8_t>(mat::AIR);
    }
    uint8_t water_at(const Vec3i& v) const {
        const Brick* b = find_brick(coords::brick_of_voxel(v));
        return b ? b->water[local_index(v)] : uint8_t{0};
    }

    // ---- Voxel writes (allocate on demand, free a brick when it empties) ----
    void set_type(const Vec3i& v, uint8_t id) {
        const Vec3i bc = coords::brick_of_voxel(v);
        // Writing air into a brick that doesn't exist is a no-op (it's already air).
        if (id == mat::AIR && !has_brick(bc)) return;
        Brick& b = get_or_create(bc);
        const int li = local_index(v);
        write_cell(b, li, id, b.water[li]);
        gc_if_empty(bc, b);
    }
    void set_water(const Vec3i& v, uint8_t byte) {
        const Vec3i bc = coords::brick_of_voxel(v);
        if (byte == 0 && !has_brick(bc)) return;
        Brick& b = get_or_create(bc);
        const int li = local_index(v);
        write_cell(b, li, b.type[li], byte);
        gc_if_empty(bc, b);
    }

    // ---- Brick index (the coarse layer the GPU skip keys off) ----
    bool   has_brick(const Vec3i& brick_coord) const { return bricks_.count(brick_coord) > 0; }
    size_t brick_count() const { return bricks_.size(); }
    int    brick_solid_count(const Vec3i& brick_coord) const {
        const Brick* b = find_brick(brick_coord);
        return b ? b->solid_count : 0;
    }
    bool brick_has_solid(const Vec3i& brick_coord) const { return brick_solid_count(brick_coord) > 0; }

    // ---- Ray-march: first solid voxel along a ray (the GPU's reference oracle) ----
    struct Hit {
        bool    hit    = false;
        Vec3i   voxel  = {};       // the solid voxel struck
        Vec3i   normal = {};       // face normal (outward); {0,0,0} if origin started inside solid
        double  t      = 0.0;      // distance along the (normalised) ray to the entry face
        uint8_t type   = 0;        // material id at the hit
    };

    // origin/dir are in VOXEL UNITS. dir need not be normalised. max_dist is in the
    // same units. Standard Amanatides-Woo grid traversal; returns the first voxel
    // whose type != air. Empty bricks are stepped through (correctly, if not as fast
    // as the GPU's brick-skip — see the file header).
    Hit raycast_solid(const Vec3& origin, const Vec3& dir, double max_dist) const {
        Hit out;

        double dx = dir.x, dy = dir.y, dz = dir.z;
        const double len = std::sqrt(dx*dx + dy*dy + dz*dz);
        if (len <= 0.0) return out; // a zero-length ray hits nothing
        dx /= len; dy /= len; dz /= len; // normalise so t is true distance

        // Current voxel = the cell containing the origin.
        Vec3i voxel{ ifloor(origin.x), ifloor(origin.y), ifloor(origin.z) };

        // The origin may already be inside solid terrain.
        if (type_at(voxel) != mat::AIR) {
            out.hit = true; out.voxel = voxel; out.t = 0.0;
            out.type = type_at(voxel); out.normal = {0, 0, 0};
            return out;
        }

        const int   stepx = sign(dx), stepy = sign(dy), stepz = sign(dz);
        double tMaxX = axis_tmax(origin.x, dx, voxel.x, stepx);
        double tMaxY = axis_tmax(origin.y, dy, voxel.y, stepy);
        double tMaxZ = axis_tmax(origin.z, dz, voxel.z, stepz);
        const double tDeltaX = (dx != 0.0) ? std::abs(1.0 / dx) : kInf;
        const double tDeltaY = (dy != 0.0) ? std::abs(1.0 / dy) : kInf;
        const double tDeltaZ = (dz != 0.0) ? std::abs(1.0 / dz) : kInf;

        double t = 0.0;
        Vec3i normal{0, 0, 0};
        // Hard iteration cap as a safety net (never spin forever on degenerate input).
        const long long max_steps = static_cast<long long>(max_dist) * 3 + 8;
        for (long long i = 0; i < max_steps; ++i) {
            // Advance to the nearest voxel boundary.
            if (tMaxX <= tMaxY && tMaxX <= tMaxZ) {
                t = tMaxX; voxel.x += stepx; tMaxX += tDeltaX; normal = {-stepx, 0, 0};
            } else if (tMaxY <= tMaxZ) {
                t = tMaxY; voxel.y += stepy; tMaxY += tDeltaY; normal = {0, -stepy, 0};
            } else {
                t = tMaxZ; voxel.z += stepz; tMaxZ += tDeltaZ; normal = {0, 0, -stepz};
            }
            if (t > max_dist) break;

            const uint8_t ty = type_at(voxel);
            if (ty != mat::AIR) {
                out.hit = true; out.voxel = voxel; out.normal = normal;
                out.t = t; out.type = ty;
                return out;
            }
        }
        return out; // ran past max_dist without hitting anything
    }

private:
    static constexpr double kInf = 1e300;

    std::unordered_map<Vec3i, Brick> bricks_;

    static int local_index(const Vec3i& v) {
        const Vec3i l = coords::local_in_brick(v);
        return coords::flatten(l.x, l.y, l.z, coords::BRICK);
    }
    const Brick* find_brick(const Vec3i& bc) const {
        auto it = bricks_.find(bc);
        return it == bricks_.end() ? nullptr : &it->second;
    }
    Brick& get_or_create(const Vec3i& bc) { return bricks_[bc]; }

    // Apply a (type, water) write to one cell and keep the counters in sync.
    static void write_cell(Brick& b, int li, uint8_t new_type, uint8_t new_water) {
        const uint8_t old_type  = b.type[li];
        const uint8_t old_water = b.water[li];

        if (old_type != mat::AIR && new_type == mat::AIR) --b.solid_count;
        if (old_type == mat::AIR && new_type != mat::AIR) ++b.solid_count;

        const bool old_nz = (old_type != 0) || (old_water != 0);
        const bool new_nz = (new_type != 0) || (new_water != 0);
        if (old_nz && !new_nz) --b.nonzero_count;
        if (!old_nz && new_nz) ++b.nonzero_count;

        b.type[li]  = new_type;
        b.water[li] = new_water;
    }
    void gc_if_empty(const Vec3i& bc, Brick& b) {
        if (b.nonzero_count == 0) bricks_.erase(bc); // brick went fully empty -> drop it
    }

    static int ifloor(float f) { return static_cast<int>(std::floor(f)); }
    static int sign(double v)  { return v > 0.0 ? 1 : (v < 0.0 ? -1 : 0); }

    // Distance along the ray (per axis) to the first voxel boundary crossed.
    static double axis_tmax(double origin, double d, int voxel, int step) {
        if (d == 0.0) return kInf;
        const double boundary = (step > 0) ? (voxel + 1) : voxel;
        return (boundary - origin) / d;
    }
};

} // namespace mira
