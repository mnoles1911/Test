// WaterByteCodec.h — single source of truth for the water byte layout.
//
// Ported 1:1 from Godot scripts/WaterByteCodec.gd. In the Godot build every
// water voxel is one byte in VoxelBuffer.CHANNEL_DATA5; in the UE build it is
// one byte in the Voxel Plugin per-voxel data channel. The bit layout is
// identical so save data and the finite-water sim stay format-compatible.
//
// Bit layout (8 bits total):
//   bits 0-3 : level     (0 = air; 1-8 = water level, 8 = full cell)
//   bit  4   : source    (1 = permanent source, 0 = flow cell)
//   bits 5-7 : direction (which way the cell drains; STILL = settled)
//
// All functions are static inline (the whole codec is tiny, hot, and called
// from generator/mesher/sim/edit/query paths). No Unreal types.

#pragma once

#include <cstdint>
#include "Core/MiraVec.h"

namespace mira {

struct WaterByteCodec {
    // ---- Bit masks ----
    static constexpr int LEVEL_MASK = 0x0F; // bits 0-3
    static constexpr int SOURCE_BIT = 0x10; // bit 4
    static constexpr int DIR_SHIFT  = 5;
    static constexpr int DIR_MASK   = 0xE0; // bits 5-7, in place

    static constexpr int MAX_LEVEL = 8; // full water cell (sources are always 8)
    static constexpr int MIN_LEVEL = 1; // below this = air

    // ---- Flow direction codes (3 bits, 0-7), bits 5-7 ----
    static constexpr int DIR_STILL = 0;
    static constexpr int DIR_POS_X = 1; // +X
    static constexpr int DIR_NEG_X = 2; // -X
    static constexpr int DIR_POS_Z = 3; // +Z
    static constexpr int DIR_NEG_Z = 4; // -Z
    static constexpr int DIR_DOWN  = 5; // -Y (waterfall / vertical drain)
    static constexpr int DIR_UP    = 6; // +Y (reserved — pressure; sim never emits yet)
    static constexpr int DIR_RSVD  = 7; // reserved; decodes as STILL

    // ---- Pre-baked common values ----
    static constexpr int AIR_BYTE    = 0;
    static constexpr int SOURCE_BYTE = MAX_LEVEL | SOURCE_BIT; // level 8 + source + STILL

    // ---- helpers (replace GDScript clampi) ----
    static constexpr int clampi(int v, int lo, int hi) {
        return v < lo ? lo : (v > hi ? hi : v);
    }

    // ---- Pack / unpack ----
    static constexpr int pack(int level, bool source, int dir) {
        const int lvl = clampi(level, 0, MAX_LEVEL);
        const int src = source ? SOURCE_BIT : 0;
        const int d   = (clampi(dir, 0, 7) << DIR_SHIFT) & DIR_MASK;
        return lvl | src | d;
    }

    static constexpr int  level_of(int byte)  { return byte & LEVEL_MASK; }
    static constexpr bool is_source(int byte) { return (byte & SOURCE_BIT) != 0; }
    static constexpr int  dir_of(int byte)    { return (byte & DIR_MASK) >> DIR_SHIFT; }
    static constexpr bool is_water(int byte)  { return (byte & LEVEL_MASK) > 0; }

    // Height-aware point test: a level-N cell is water only up to N/8 of its
    // height, so wading a level-2 puddle is not "swimming".
    static bool is_inside_water_column(int byte, float frac_y) {
        const int lvl = byte & LEVEL_MASK;
        if (lvl <= 0) return false;
        return frac_y <= static_cast<float>(lvl) / static_cast<float>(MAX_LEVEL);
    }

    // ---- Field mutators (return a NEW byte, other fields preserved) ----
    static constexpr int set_level(int byte, int level) {
        return (byte & ~LEVEL_MASK) | clampi(level, 0, MAX_LEVEL);
    }
    static constexpr int set_dir(int byte, int dir) {
        return (byte & ~DIR_MASK) | ((clampi(dir, 0, 7) << DIR_SHIFT) & DIR_MASK);
    }
    static constexpr int set_source(int byte, bool source) {
        return source ? (byte | SOURCE_BIT) : (byte & ~SOURCE_BIT);
    }

    // ---- Direction <-> grid offset (single source of spatial meaning) ----
    static Vec3i dir_to_offset(int dir) {
        switch (dir) {
            case DIR_POS_X: return {1, 0, 0};
            case DIR_NEG_X: return {-1, 0, 0};
            case DIR_POS_Z: return {0, 0, 1};
            case DIR_NEG_Z: return {0, 0, -1};
            case DIR_DOWN:  return {0, -1, 0};
            case DIR_UP:    return {0, 1, 0};
            default:        return {0, 0, 0}; // STILL / reserved
        }
    }

    static int offset_to_dir(const Vec3i& o) {
        if (o == Vec3i(1, 0, 0))  return DIR_POS_X;
        if (o == Vec3i(-1, 0, 0)) return DIR_NEG_X;
        if (o == Vec3i(0, 0, 1))  return DIR_POS_Z;
        if (o == Vec3i(0, 0, -1)) return DIR_NEG_Z;
        if (o == Vec3i(0, -1, 0)) return DIR_DOWN;
        if (o == Vec3i(0, 1, 0))  return DIR_UP;
        return DIR_STILL;
    }
};

} // namespace mira
