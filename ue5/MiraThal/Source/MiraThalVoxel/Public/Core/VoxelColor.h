// VoxelColor.h — solid per-face voxel coloring (header-only Core).
//
// WHAT THIS DOES (plain English):
//   At 10cm voxels an old-school texture atlas is overkill — a single tiny tile
//   stretched across a 10cm face reads as a flat color anyway. So instead of
//   sampling a texture, we give each MATERIAL one flat base color and then darken
//   it a bit per FACE DIRECTION. A plain cube therefore shows six visibly distinct
//   shades (top brightest, bottom darkest, sides in between) so the silhouette of
//   the terrain reads clearly even before any real lighting is applied.
//
//   The color is computed PER MATERIAL + PER DIRECTION — NOT per voxel. That is
//   deliberate: the greedy mesher merges neighbouring faces of the same material
//   and direction into one big quad, and because every one of those faces would
//   get the exact same color, the merge is preserved. (If color varied per voxel
//   the mesher could not merge, and the chunk would explode in quad count.)
//
//   The baked color goes into the vertex's cr/cg/cb fields. Ambient occlusion
//   (the `ao` field) stays SEPARATE — the UE material multiplies albedo (rgb) by
//   AO (alpha) at shade time, so we don't pre-multiply AO into the color here.
//
// Pure C++17, no engine headers — compiles in the standalone clang harness.

#pragma once

#include <cstdint>
#include "Core/MeshTypes.h"   // FaceDir
#include "Core/MaterialIds.h" // mat:: ids + is_water_type

namespace mira {

// A plain 8-bit-per-channel RGB color (0..255). No alpha — AO rides separately.
struct Rgb8 { uint8_t r, g, b; };

// ---------------------------------------------------------------------------
// base_color — one flat color per material id (0..255 per channel).
//
// Values transcribed DIRECTLY from the Godot material `color_high` palette so the
// UE build matches the look the designer authored in Godot. Named constants from
// MaterialIds.h are used where they exist; bare numeric ids elsewhere. Any id we
// don't recognise falls back to stone so an unknown material is still visible (a
// neutral grey) rather than black or a crash.
// ---------------------------------------------------------------------------
inline Rgb8 base_color(int material_id) {
    // Water spans a whole id range (legacy id 5 + the 8 fluid levels 16..23), so
    // it can't be a single `case`; handle it up front via the range predicate.
    if (mat::is_water_type(material_id)) return Rgb8{ 51, 102, 153 };

    switch (material_id) {
        case mat::STONE:      return Rgb8{ 158, 153, 140 }; // 1
        case mat::DIRT:       return Rgb8{ 107,  77,  46 }; // 2
        case mat::GRASS:      return Rgb8{  97, 140,  56 }; // 3
        case mat::SAND:       return Rgb8{ 224, 204, 148 }; // 4
        case 6:               return Rgb8{  46,  46,  51 }; // bedrock
        case 7:               return Rgb8{ 122, 122, 122 }; // gravel
        case 8:               return Rgb8{ 122, 138, 150 }; // clay
        case mat::MARBLE:     return Rgb8{ 232, 224, 212 }; // 9
        case mat::LOG:        return Rgb8{  92,  59,  26 }; // 10
        case mat::LEAVES:     return Rgb8{  59,  92,  33 }; // 11
        case 12:              return Rgb8{ 184, 115,  51 }; // copper_ore
        case 13:              return Rgb8{ 255, 255, 255 }; // snow
        case mat::STONE_DARK: return Rgb8{ 102, 102, 115 }; // 14
        case 15:              return Rgb8{ 148, 122, 102 }; // iron_ore

        case mat::GRASS_BLADE_ID: return Rgb8{ 115, 158,  66 }; // 24
        case mat::FLOWER_RED_ID:  return Rgb8{ 217,  46,  41 }; // 25
        case mat::FLOWER_BLUE_ID: return Rgb8{  92, 133, 230 }; // 26
        case mat::PEBBLE_ID:      return Rgb8{ 128, 117, 102 }; // 27
        case mat::TWIG_ID:        return Rgb8{ 102,  74,  46 }; // 28

        default:              return Rgb8{ 158, 153, 140 }; // unknown -> stone
    }
}

// ---------------------------------------------------------------------------
// face_shade — a brightness multiplier per face direction (0..1).
//
// Each of the 6 faces gets a DISTINCT shade so a single cube shows six different
// tones. Top is fully lit (1.00), bottom darkest (0.50), and the four sides sit
// in between, each a different value so even two side faces are distinguishable.
// This is a cheap fake-AO / fake-directional-light that gives strong form
// definition before any real lighting touches the mesh.
// ---------------------------------------------------------------------------
inline float face_shade(FaceDir dir) {
    switch (dir) {
        case FACE_POS_Y: return 1.00f; // top (brightest)
        case FACE_NEG_Y: return 0.50f; // bottom (darkest)
        case FACE_POS_X: return 0.86f;
        case FACE_NEG_X: return 0.76f;
        case FACE_POS_Z: return 0.80f;
        case FACE_NEG_Z: return 0.70f;
    }
    return 1.0f; // unreachable; keeps the compiler happy
}

// ---------------------------------------------------------------------------
// shaded_color — base_color(material) × face_shade(dir), per channel.
//
// Each channel is multiplied by the face shade, rounded to nearest, and clamped
// into [0,255] so it always fits a uint8_t. This is the value baked into the
// vertex cr/cg/cb fields by the meshers.
// ---------------------------------------------------------------------------
inline Rgb8 shaded_color(int material_id, FaceDir dir) {
    const Rgb8  c = base_color(material_id);
    const float s = face_shade(dir);

    // Multiply, round to nearest, clamp to [0,255].
    auto ch = [s](uint8_t v) -> uint8_t {
        float f = static_cast<float>(v) * s + 0.5f; // +0.5 -> round to nearest
        if (f < 0.0f)   f = 0.0f;
        if (f > 255.0f) f = 255.0f;
        return static_cast<uint8_t>(f);
    };

    return Rgb8{ ch(c.r), ch(c.g), ch(c.b) };
}

// ---------------------------------------------------------------------------
// lod_debug_color — DIAGNOSTIC palette: one flat, vivid color per LOD LEVEL.
//
// This is a DEBUG-ONLY render override (cvar `mira.LodDebug` on the UE side). It
// has NOTHING to do with a voxel's material — when the tester flips the cvar, the
// terrain is recolored by which LOD a chunk loaded at, so the concentric LOD rings
// are visible at a glance. It NEVER touches voxel/brick data; it is only written
// into the mesh-upload vertex color in place of the real albedo.
//
// COLOR CHOICE (important — read this if you ever wonder why these bytes):
//   The UE terrain material takes the vertex color as if it were sRGB and decodes
//   it to linear with Power(2.2) before using it as BaseColor. So a stored byte
//   value v ends up on screen at roughly (v/255)^2.2. We WANT vivid, clearly-
//   distinct hues, so we just store strong primaries/secondaries near 0 or 255 in
//   each channel: 255 stays ~1.0 after decode, 0 stays 0.0, so the hue survives the
//   Power(2.2) cleanly (only mid-grays get pulled dark, and we avoid those). The
//   ramp green->yellow->orange->red->magenta is the same "cool=near, hot=far" ramp
//   the Godot build used, so the designer reads it the same way.
//
//   PER-CHUNK LODs (is_super = false) use the bright ramp:
//     L0 = green        (near / finest)
//     L1 = yellow-green
//     L2 = yellow
//     L3 = orange
//     L4 = red
//     L5 = magenta      (far / coarsest per-chunk)
//
//   SUPER-CHUNK LODs (is_super = true) use a BLUE-SHIFTED, darker variant of the
//   same ramp so a super tile is never confused with a per-chunk tile at the same
//   LOD number — supers always read "cooler / bluer":
//     L0 = teal         L1 = cyan        L2 = sky-blue
//     L3 = blue         L4 = indigo      L5 = violet
//
// `lod` is clamped to [0,5]. AO (the vertex alpha) is left untouched by the caller,
// so the debug terrain still gets the same fake-AO shading the real terrain has.
// ---------------------------------------------------------------------------
inline Rgb8 lod_debug_color(int lod, bool is_super) {
    if (lod < 0) lod = 0;
    if (lod > 5) lod = 5;

    if (!is_super) {
        // Per-chunk: bright green -> magenta ramp (cool=near, hot=far).
        switch (lod) {
            case 0: return Rgb8{   0, 255,   0 }; // green
            case 1: return Rgb8{ 160, 255,   0 }; // yellow-green
            case 2: return Rgb8{ 255, 255,   0 }; // yellow
            case 3: return Rgb8{ 255, 140,   0 }; // orange
            case 4: return Rgb8{ 255,   0,   0 }; // red
            default:return Rgb8{ 255,   0, 255 }; // L5 magenta
        }
    }

    // Super-chunk: blue-shifted cool ramp, so per-chunk vs super is unmistakable.
    switch (lod) {
        case 0: return Rgb8{   0, 200, 180 }; // teal
        case 1: return Rgb8{   0, 220, 255 }; // cyan
        case 2: return Rgb8{   0, 140, 255 }; // sky-blue
        case 3: return Rgb8{   0,  60, 255 }; // blue
        case 4: return Rgb8{  90,   0, 255 }; // indigo
        default:return Rgb8{ 160,   0, 255 }; // L5 violet
    }
}

} // namespace mira
