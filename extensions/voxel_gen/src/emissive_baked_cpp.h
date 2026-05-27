#pragma once

// EmissiveBakedCpp — BFS-floodfill emissive-voxel light baker.
//
// The original Phase J spec from design/GRAPHICS_PASS_2026-05-19.md:
//   "BFS floodfill from emissive voxels into a 3D storage texture,
//    triggered on VoxelEditManager.edit_applied, scoped to a radius
//    around the edit ... the terrain shader samples it for indirect
//    block light."
//
// Phase J v1 went with engine-native OmniLight3D streaming instead
// (EmissiveLightManager.gd). That works but bleeds light through rock
// (shadowless cluster lights) — designer flagged the wall-bleed as
// cosmetic-but-noticeable 2026-05-26 testing the VGM/ELM ports. This
// is the original Phase J done properly: a real 3D light texture that
// the terrain shader samples, with BFS propagation through air voxels
// only so a buried-but-exposed copper voxel's light stops at the rock.
//
// Boundary:
//   GD-side EmissiveBakedManager autoload owns the 3D texture, the
//   shader-global plumbing, edit_applied wiring, periodic refresh,
//   and the emissive-voxel discovery (mirrors ELM). C++ owns the
//   pure-data bake: BFS floodfill from each emitter into a flat
//   PackedByteArray (R8G8B8A8 per cell), returning a 1D byte array
//   the autoload uploads to the 3D texture.
//
// Volume sizing (autoload-driven, configurable):
//   * cells_per_axis = N           (the texture is NxNxN cells)
//   * cell_size_voxels = K         (each cell spans K voxels per axis)
//   * world coverage = N * K voxels per axis (at 6 vox/m = N*K/6 metres)
//   * volume origin = min-corner world-voxel coord, snapped to cell grid
//   * memory = N^3 * 4 bytes (R8G8B8A8)
//
// Default sweet spot (autoload-set): N=64, K=4 — a 256-voxel cube
// (~42 m) around the player, 1 MB of RGBA bytes.
//
// VoxelBuffer is passed as godot::Variant and accessed via
// Variant::call("get_voxel", ...) — same pattern as the existing
// voxel_gravity_cpp / emissive_light_cpp ports. The buffer is expected
// to cover the volume (one byte per voxel, CHANNEL_TYPE only) so the
// floodfill can test "is the cell's centre voxel air?" without going
// back to GD for each step.

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector3i.hpp>

class EmissiveBakedCpp : public godot::Resource {
    GDCLASS(EmissiveBakedCpp, godot::Resource)

public:
    EmissiveBakedCpp();
    ~EmissiveBakedCpp();

    // --- Main bake call (pure; no SceneTree access) -----------------------
    //
    // Inputs:
    //   p_buf            — VoxelBuffer holding CHANNEL_TYPE for the volume.
    //                      Buffer dimensions must be cells_per_axis * cell_size_voxels
    //                      on each axis (the autoload sizes it that way).
    //   p_volume_origin_v — world voxel coord of the buffer's minimum corner.
    //                      Used only to translate emitter world-voxel coords
    //                      into local (cell-space) coords.
    //   p_cell_size_voxels— K (clamped to >=1).
    //   p_cells_per_axis  — N (clamped to >=1; <=256).
    //   p_emitters        — flat stream, 7 ints per emitter:
    //                       [g_x, g_y, g_z, r_byte, g_byte, b_byte, energy_byte]
    //                       (world voxel coords + pre-resolved RGB byte colour
    //                        + energy scaled to 0..255).
    //   p_max_steps       — BFS cell-step depth cap (clamped to >=1, <=cells_per_axis).
    //   p_falloff_q12     — per-step attenuation as Q12 fixed-point
    //                       (e.g. 0.85 -> 3482). Clamped to (0, 4096].
    //
    // Returns:
    //   PackedByteArray of size N^3 * 4, RGBA8 (R/G/B = max-blended
    //   incident light colour, A = max intensity / 255 — currently unused
    //   by the shader but useful for diagnostics). Air-zero cells receive
    //   no light and remain 0.
    //
    // Behaviour:
    //   * Each emitter does its own BFS from its containing cell.
    //   * A neighbour cell is visited only if its CENTRE voxel is air
    //     (CHANNEL_TYPE == 0 there). This is the "light through air only"
    //     gate that prevents the wall bleed-through.
    //   * Each step multiplies the current colour by falloff_q12/4096.
    //   * Within a single emitter's BFS, the FIRST visit's colour wins
    //     (so the result is the brightest path = the shortest path from
    //     this emitter). Across emitters, per-channel MAX blend wins.
    //   * The emitter's own cell receives the full emitter colour
    //     unattenuated regardless of whether that voxel is "air" (so the
    //     emissive voxel itself always glows).
    godot::PackedByteArray bake_light_volume(
        godot::Variant p_buf,
        godot::Vector3i p_volume_origin_v,
        int p_cell_size_voxels,
        int p_cells_per_axis,
        godot::PackedInt32Array p_emitters,
        int p_max_steps,
        int p_falloff_q12);

protected:
    static void _bind_methods();
};
