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
//   * world coverage = N * K voxels per axis (at 10 vox/m = N*K/10 metres)
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
    //   p_mat_color_table — 256 × 4 bytes (r, g, b, energy). Each entry
    //                       is the emission colour + energy for that
    //                       material id; energy == 0 means "not emissive,
    //                       skip." Built once on the GD side from
    //                       VoxelMaterialRegistry. C++ discovers emitters
    //                       by scanning the bulk channel bytes and looking
    //                       up each non-air voxel — no per-emitter Variant
    //                       crossing.
    //   p_air_neighbor_filter — when true, only EXPOSED emissive voxels
    //                           (at least one 6-face-neighbour is air)
    //                           seed light. Buried emissive voxels are
    //                           skipped entirely. This is the gate that
    //                           prevents a buried copper voxel from
    //                           lighting its own cell (the "amber-glow-
    //                           through-the-surface" cosmetic bug).
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
        godot::PackedByteArray p_mat_color_table,
        bool p_air_neighbor_filter,
        int p_max_steps,
        int p_falloff_q12);

protected:
    static void _bind_methods();
};
