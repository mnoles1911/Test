// GDExtension entry point for the voxel_gen module.
//
// Phase 0 (spike): registers only SpikeStoneGenerator. Subsequent phases will
// register CubicHeightmapGenerator and CopperIslesHeightmapGenerator here
// once they're ported. The Spike class proves that a C++ subclass of
// Zylann's VoxelGeneratorScript loads, attaches to a VoxelLodTerrain, and
// has its _generate_block called from the worker pool.

#include "register_types.h"
#include "parity_probe.h"
#include "spike_stone_generator.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_voxel_gen_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    ClassDB::register_class<SpikeStoneGenerator>();
    ClassDB::register_class<ParityProbe>();
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
