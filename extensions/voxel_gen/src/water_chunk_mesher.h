#pragma once

// WaterChunkMesherCpp — per-chunk water surface mesh builder.
//
// Port of the hot loop inside scripts/WaterChunkMesher.gd:
//   * _gather_surface_quads   (per-column topmost-water scan +
//                              greedy 2D run-merge of column-tops by Y)
//   * _build_array_mesh       (subdivide each rectangle 4× per side,
//                              emit verts/normals/uvs/indices)
//
// Everything that touches the SceneTree (MeshInstance3D pool,
// queue_free, signal subscriptions, the time-budget drain loop)
// stays in GDScript. This class is a pure Resource that takes the
// chunk's CHANNEL_DATA5 contents (passed in as a Variant wrapping a
// Zylann VoxelBuffer) and returns a built ArrayMesh — or null
// when the chunk has no water voxels.
//
// The adapter pattern from the heightmap port (godot-cpp can't
// subclass Zylann classes) does not apply here: WaterChunkMesher.gd
// is plain Node3D and stays GDScript; the C++ class is a Resource
// the GD side instantiates once in _ready and calls per chunk.

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector3i.hpp>

class WaterChunkMesherCpp : public godot::Resource {
    GDCLASS(WaterChunkMesherCpp, godot::Resource)

public:
    WaterChunkMesherCpp();
    ~WaterChunkMesherCpp();

    // Build the water-surface mesh for a single chunk.
    //
    // p_buffer is a Zylann VoxelBuffer (16×16×16 at LOD0) snapshot of
    // CHANNEL_DATA5 for the chunk. Caller must have already issued
    // tool.copy(origin, buffer, 1 << CHANNEL_DATA5). p_chunk is passed
    // through for diagnostics only — verts are LOCAL to the chunk
    // origin, the GD caller sets MeshInstance3D.global_position to
    // chunk-origin world coords.
    //
    // Returns a valid Ref<ArrayMesh> when the chunk contains water,
    // or an empty Ref<ArrayMesh>() when the chunk is dry. Caller
    // treats an empty Ref as "free the existing mesh if any".
    godot::Ref<godot::ArrayMesh> build_chunk_mesh(godot::Variant p_buffer,
                                                  godot::Vector3i p_chunk);

protected:
    static void _bind_methods();
};
