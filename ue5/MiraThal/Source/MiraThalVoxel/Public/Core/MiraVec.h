// MiraVec.h — tiny integer/float vector types for the engine-agnostic core.
//
// WHY THIS EXISTS (plain English):
// The "Core" layer is the load-bearing voxel math ported 1:1 from the Godot
// build (water sim, gravity flood-fill, generator, scale). It must compile in
// TWO places:
//   1. Inside the Unreal module (where FVector / FIntVector exist), and
//   2. Standalone under clang for headless parity tests (no Unreal headers).
// So Core never touches Unreal types. It uses these small std-only structs.
// The UE wrapper layer converts FVector <-> mira::Vec3 at the boundary.
//
// Keep this header dependency-free (only <cstdint> + <functional> for hashing).

#pragma once

#include <cstdint>
#include <functional>

namespace mira {

// Integer voxel coordinate. Mirrors Godot's Vector3i used all over the sim.
struct Vec3i {
    int32_t x = 0;
    int32_t y = 0;
    int32_t z = 0;

    constexpr Vec3i() = default;
    constexpr Vec3i(int32_t ix, int32_t iy, int32_t iz) : x(ix), y(iy), z(iz) {}

    constexpr Vec3i operator+(const Vec3i& o) const { return {x + o.x, y + o.y, z + o.z}; }
    constexpr Vec3i operator-(const Vec3i& o) const { return {x - o.x, y - o.y, z - o.z}; }
    constexpr bool   operator==(const Vec3i& o) const { return x == o.x && y == o.y && z == o.z; }
    constexpr bool   operator!=(const Vec3i& o) const { return !(*this == o); }
};

// Float world-space position (metres). Mirrors Godot's Vector3.
struct Vec3 {
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;

    constexpr Vec3() = default;
    constexpr Vec3(float ix, float iy, float iz) : x(ix), y(iy), z(iz) {}
};

} // namespace mira

// Hash specialization so Vec3i can key an unordered_map (the water ledger and
// gravity visited-set both need this). Same role as Godot's Dictionary keys.
namespace std {
template <>
struct hash<mira::Vec3i> {
    size_t operator()(const mira::Vec3i& v) const noexcept {
        // 64-bit mix of the three int32s; cheap and good enough for spatial keys.
        uint64_t h = static_cast<uint32_t>(v.x);
        h = h * 0x9E3779B97F4A7C15ull + static_cast<uint32_t>(v.y);
        h = h * 0x9E3779B97F4A7C15ull + static_cast<uint32_t>(v.z);
        h ^= (h >> 29);
        return static_cast<size_t>(h);
    }
};
} // namespace std
