// GDExtension entry point for the voxel_gen module.
//
// Active classes:
//   HeightmapGeneratorBase — abstract shared base for the two heightmap
//       generators (registered as abstract so the editor doesn't offer
//       "New Resource" for it).
//   CubicHeightmapGeneratorCpp — World3D terrain generator (Mira). Used
//       via CubicHeightmapGeneratorAdapter.gd as the VoxelLodTerrain's
//       generator.
//   CopperIslesHeightmapGeneratorCpp — Copper Isles demo. Used via
//       CopperIslesHeightmapGeneratorAdapter.gd.
//   ParityProbe — bit-exact verification shim for voxel_gen_math (hash3,
//       cliff_threshold_for_angle_voxels). Retained between ports so each
//       new C++ port can extend a parity harness against the GDScript
//       original.
//   VoxelGravityCpp — autoload C++ partition for VoxelGravityManager
//       (Phase 0 stub; real flood-fill + cluster BFS lands in Phase 2).
//   EmissiveLightCpp — autoload C++ scan for EmissiveLightManager
//       (Phase 0 stub; real classification lands in Phase 4).
// (WaterChunkMesherCpp removed 2026-05-18 by the native-fluid pivot —
//  it had ZERO GDScript references; the Zylann blocky mesher now draws
//  water as native VoxelBlockyModelFluid models, no separate water
//  surface mesher and no horizon plane.)

#include "register_types.h"
#include "copper_isles_heightmap_generator.h"
#include "cubic_heightmap_generator.h"
#include "distant_terrain_mesher.h"
#include "emissive_baked_cpp.h"
#include "emissive_light_cpp.h"
#include "heightmap_generator_base.h"
#include "parity_probe.h"
#include "voxel_gravity_cpp.h"

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
    // The base class must register BEFORE its subclasses so godot-cpp
    // can resolve the inheritance chain. Abstract so the editor doesn't
    // let users instantiate it directly (compute_ground_y is pure
    // virtual; instantiation would crash on first generate_block call).
    ClassDB::register_abstract_class<HeightmapGeneratorBase>();
    ClassDB::register_class<CubicHeightmapGeneratorCpp>();
    ClassDB::register_class<CopperIslesHeightmapGeneratorCpp>();
    // DistantTerrainMesher — standalone heightmesh builder for the
    // streaming distant-terrain LOD system. Not a generator; needs no
    // ordering vs the HeightmapGeneratorBase chain above.
    ClassDB::register_class<DistantTerrainMesher>();
    // VoxelGravityCpp / EmissiveLightCpp / EmissiveBakedCpp — standalone
    // autoload helpers. No ordering vs the generator chain (no shared
    // inheritance).
    ClassDB::register_class<VoxelGravityCpp>();
    ClassDB::register_class<EmissiveLightCpp>();
    ClassDB::register_class<EmissiveBakedCpp>();
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
