// AtlasUV.h — maps (material id, cube face) to a tile in the texture atlas.
//
// Ported from the Godot blocky_library.tres face-tile assignments. The atlas is
// 1024x1024 px, 16px tiles, 64 columns x 64 rows. Each opaque material picks a
// tile per face group: TOP (the +Y face), SIDE (the four vertical faces), and
// BOTTOM (the -Y face) — so grass can be green on top, dirt underneath, grass+dirt
// on the sides, exactly as in the shipped game.
//
// The greedy mesher calls tile_for(id, dir) for opaque/cutout faces and writes
// the resulting UV rect onto the quad. Water and flora use their own meshers +
// materials, so this table only needs the solid/cutout ids (1..15).
//
// Pure lookup, no engine types. The `atlas` selector pins the tile coordinates so
// a wrong tile shows up as a test failure, not a mystery texture in-engine.

#pragma once

#include "Core/MeshTypes.h" // FaceDir
#include "Core/MaterialIds.h"

namespace mira {
namespace atlas {

constexpr int ATLAS_PX = 1024;
constexpr int TILE_PX  = 16;
constexpr int COLS     = ATLAS_PX / TILE_PX; // 64
constexpr int ROWS     = ATLAS_PX / TILE_PX; // 64

// A tile address in the atlas grid (column, row).
struct Tile {
    int col = 0;
    int row = 0;
    constexpr bool operator==(const Tile& o) const { return col == o.col && row == o.row; }
};

// Per-material face tiles. SIDE is reused for all four vertical faces.
struct TileSet {
    Tile top;
    Tile side;
    Tile bottom;
};

// The face-tile table, indexed by material id. Values transcribed from the Godot
// blocky_library (see design parity inventory). Ids with no entry fall back to a
// single tile (col,row 0,0 = stone) so a missing mapping is visible but not a crash.
constexpr TileSet tileset_for(int id) {
    switch (id) {
        case mat::STONE:      return { {0,0}, {0,0}, {0,0} };
        case mat::DIRT:       return { {1,0}, {1,0}, {1,0} };
        case mat::GRASS:      return { {2,0}, {3,0}, {1,0} }; // grass top, grass-side, dirt bottom
        case mat::SAND:       return { {4,0}, {4,0}, {4,0} };
        case 6 /*bedrock*/:   return { {4,1}, {4,1}, {4,1} };
        case 7 /*gravel*/:    return { {5,0}, {5,0}, {5,0} };
        case 8 /*clay*/:      return { {6,0}, {6,0}, {6,0} };
        case mat::MARBLE:     return { {7,0}, {7,0}, {7,0} };
        case mat::LOG:        return { {0,1}, {1,1}, {0,1} }; // log top rings, bark side
        case mat::LEAVES:     return { {2,1}, {2,1}, {2,1} };
        case 12 /*copper_ore*/: return { {3,1}, {3,1}, {3,1} };
        case 13 /*snow*/:     return { {8,0}, {8,0}, {8,0} };
        case mat::STONE_DARK: return { {9,0}, {9,0}, {9,0} };
        case 15 /*iron_ore*/: return { {10,0}, {10,0}, {10,0} };
        default:              return { {0,0}, {0,0}, {0,0} };
    }
}

// The tile for one specific face direction.
constexpr Tile tile_for(int id, FaceDir dir) {
    const TileSet ts = tileset_for(id);
    if (dir == FACE_POS_Y) return ts.top;
    if (dir == FACE_NEG_Y) return ts.bottom;
    return ts.side; // the four vertical faces
}

// UV rectangle (0..1) for a tile. u0,v0 = min corner; u1,v1 = max corner.
struct UVRect { float u0, v0, u1, v1; };

constexpr UVRect uv_rect(Tile t) {
    const float s = 1.0f / static_cast<float>(COLS); // tile edge in UV space (1/64)
    return { t.col * s, t.row * s, (t.col + 1) * s, (t.row + 1) * s };
}

constexpr UVRect uv_for(int id, FaceDir dir) { return uv_rect(tile_for(id, dir)); }

} // namespace atlas
} // namespace mira
