// GDExtension entry point for the voxel_gen module.
//
// Active classes:
//   CubicHeightmapGeneratorCpp — World3D terrain generator (Mira). Used via
//       CubicHeightmapGeneratorAdapter.gd as the VoxelLodTerrain's generator.
//   ParityProbe — bit-exact verification shim for voxel_gen_math (hash3,
//       cliff_threshold_for_angle_voxels). Retained between ports so each new
//       C++ port can extend a parity harness against the GDScript original.

#include "register_types.h"
#include "copper_isles_heightmap_generator.h"
#include "cubic_heightmap_generator.h"
#include "parity_probe.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_voxel_gen_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    ClassDB::register_class<ParityProbe>();
    ClassDB::register_class<CubicHeightmapGeneratorCpp>();
    ClassDB::register_class<CopperIslesHeightmapGeneratorCpp>();
}

void uninitialize_voxel_gen_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
}

extern "C" {
GDExtensionBool GDE_EXPORT voxel_gen_library_init(
        GDExtensionInterfaceGetProcAddress p_get_proc_address,
        GDExtensionClassLibraryPtr p_library,
        GDExtensionInitialization *r_initialization) {
    GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
    init_obj.register_initializer(initialize_voxel_gen_module);
    init_obj.register_terminator(uninitialize_voxel_gen_module);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}
}
