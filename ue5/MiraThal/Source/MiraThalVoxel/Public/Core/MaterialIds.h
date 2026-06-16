// MaterialIds.h — single authority for voxel CHANNEL_TYPE material ids and the
// "what does this id mean?" predicates.
//
// Consolidates two Godot authorities into one engine-agnostic header:
//   - scripts/WaterMaterial.gd  -> water id range + level<->render-id projection
//   - scripts/FloraMaterial.gd  -> flora / surface-detail / pass-through ranges
//
// WHY ONE FILE (plain English): in the Godot build "water is 5" was once
// hardcoded in four places, and the flora/decoration pass-through range (24..28)
// is mirrored BY VALUE in the gravity flood-fill, the sever BFS, and the
// generator. Every one of those is a place the number can silently drift. Here
// the ranges live once; the water sim, gravity, generator, and the UE wrappers
// all range-check against these constants so a new decoration id is a one-line
// change, not a project-wide hunt.
//
// Pure C++17, no engine types — usable from the Unreal module and the clang
// headless harness alike.

#pragma once

#include <cstdint>

namespace mira {
namespace mat {

// ---------------------------------------------------------------------------
// Terrain / structure ids (carried from VoxelMaterialRegistry + the generator).
// Listed for readability at call sites; the generator port already emits these.
// ---------------------------------------------------------------------------
constexpr int AIR        = 0;
constexpr int STONE      = 1;
constexpr int DIRT       = 2;
constexpr int GRASS      = 3;
constexpr int SAND       = 4;
constexpr int MARBLE     = 9;
constexpr int LOG        = 10; // tree trunk
constexpr int LEAVES     = 11; // tree canopy
constexpr int STONE_DARK = 14;

// ---------------------------------------------------------------------------
// Water (from WaterMaterial.gd). Legacy single-cube id 5 stays "water" through
// the transition; the native fluid occupies the contiguous block [16..23],
// where sim level L (1..8) renders as id 16 + L - 1.
// ---------------------------------------------------------------------------
constexpr int LEGACY_WATER_ID    = 5;
constexpr int WATER_FLUID_BASE_ID = 16;
constexpr int WATER_LEVEL_COUNT   = 8;
constexpr int FULL_FLUID_ID       = WATER_FLUID_BASE_ID + WATER_LEVEL_COUNT - 1; // 23
constexpr int BODY_ID             = FULL_FLUID_ID;

// "Is this CHANNEL_TYPE value water?" — replaces every `== 5`. Accepts the
// legacy cube id plus the 8 fluid-level ids [16..23]. One branch on the hot path.
constexpr bool is_water_type(int type_id) {
    return type_id == LEGACY_WATER_ID
        || (type_id >= WATER_FLUID_BASE_ID
            && type_id < WATER_FLUID_BASE_ID + WATER_LEVEL_COUNT);
}

// Helper mirrored from WaterByteCodec::clampi so this header stays standalone.
constexpr int clampi(int v, int lo, int hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

// Project a sim water level (0 = air .. 8 = full) onto the CHANNEL_TYPE id the
// blocky mesher draws. level L -> fluid model id BASE + L - 1; 0 -> air.
constexpr int render_id_for_level(int level, int /*dir*/) {
    if (level <= 0) return 0;
    return WATER_FLUID_BASE_ID + clampi(level, 1, WATER_LEVEL_COUNT) - 1;
}

// Explicit save-migration only (not auto-applied): collapse the legacy cube id
// to the full-level fluid id; leave every other id untouched.
constexpr int map_legacy_id(int type_id) {
    return type_id == LEGACY_WATER_ID ? FULL_FLUID_ID : type_id;
}

// ---------------------------------------------------------------------------
// Flora + surface detail (from FloraMaterial.gd). Chosen ABOVE the water range
// so the id spaces never overlap. The combined pass-through block is 24..28.
// ---------------------------------------------------------------------------
constexpr int GRASS_BLADE_ID = 24;
constexpr int FLOWER_RED_ID  = 25;
constexpr int FLOWER_BLUE_ID = 26;
constexpr int FLORA_BASE_ID  = GRASS_BLADE_ID; // 24
constexpr int FLORA_COUNT    = 3;              // 24..26

constexpr int PEBBLE_ID = 27;
constexpr int TWIG_ID   = 28;
constexpr int SURFACE_DETAIL_BASE_ID = PEBBLE_ID; // 27
constexpr int SURFACE_DETAIL_COUNT   = 2;         // 27..28

// flora (24..26) + surface detail (27..28) = one contiguous block 24..28.
constexpr int PASSTHROUGH_BASE_ID = FLORA_BASE_ID;                   // 24
constexpr int PASSTHROUGH_COUNT   = FLORA_COUNT + SURFACE_DETAIL_COUNT; // 5 -> 24..28

// Vegetation only (24..26). Use is_passthrough() for the physics "treat as air".
constexpr bool is_flora(int type_id) {
    return type_id >= FLORA_BASE_ID && type_id < FLORA_BASE_ID + FLORA_COUNT;
}

// Pebble / twig scatter (27..28).
constexpr bool is_surface_detail(int type_id) {
    return type_id >= SURFACE_DETAIL_BASE_ID
        && type_id < SURFACE_DETAIL_BASE_ID + SURFACE_DETAIL_COUNT;
}

// THE physics/sim exclusion predicate: pass-through air for gravity, sever, and
// finite-water (24..28). Every exclusion site funnels through this one branch.
constexpr bool is_passthrough(int type_id) {
    return type_id >= PASSTHROUGH_BASE_ID
        && type_id < PASSTHROUGH_BASE_ID + PASSTHROUGH_COUNT;
}

// ---------------------------------------------------------------------------
// Aliases used by HeightmapGenerator.h. That header originally declared its own
// parallel `mat` namespace (TREE_LOG / FLORA_GRASS_BLADE / ...); co-including it
// with this authority inside the UE module collided. These aliases let the
// generator keep its names while THIS file stays the single source of the ids.
// ---------------------------------------------------------------------------
constexpr int TREE_LOG          = LOG;                  // 10
constexpr int TREE_LEAVES       = LEAVES;               // 11
constexpr int WATER_FLUID_BASE  = WATER_FLUID_BASE_ID;  // 16
constexpr int WATER_FULL        = FULL_FLUID_ID;        // 23
constexpr int WATER_SOURCE_BYTE = 0x18;                 // DATA5 source byte (== WaterByteCodec::SOURCE_BYTE)
constexpr int FLORA_GRASS_BLADE = GRASS_BLADE_ID;       // 24
constexpr int FLORA_FLOWER_RED  = FLOWER_RED_ID;        // 25
constexpr int FLORA_FLOWER_BLUE = FLOWER_BLUE_ID;       // 26
constexpr int DETAIL_PEBBLE     = PEBBLE_ID;            // 27
constexpr int DETAIL_TWIG       = TWIG_ID;              // 28

} // namespace mat
} // namespace mira
