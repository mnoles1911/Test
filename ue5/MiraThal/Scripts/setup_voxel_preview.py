# setup_voxel_preview.py — build a CLEAN, lit preview level for the imported EXR
# voxel terrain. Run via the mcp-unreal execute_script bridge with the editor open.
#
# WHAT IT MAKES (and why it's clean):
#   * a brand-new EMPTY level — NOT the "Open World" template, so there is no
#     stock sky/landscape/background, only what we add;
#   * minimal lighting that makes the voxel palette read right (sun + sky +
#     fog + a locked daylight exposure so a small terrain under a big sky isn't
#     crushed to tan by auto-exposure);
#   * the MiraVoxelWorld actor configured for the 5 km Export.exr, generating a
#     ~67 m region at full 10 cm detail around the map centre;
#   * the level SAVED as /Game/Maps/VoxelPreview so it's reusable (reopen it any
#     time instead of rebuilding by hand).
#
# NOTE: the EXR path below is this machine's absolute path. This is a local
# editor convenience script, not shipping code.

import unreal, traceback

EXR = "C:/Users/Matt Noles/Test-ue5/ue5/MiraThal/Content/Heightmaps/Export.exr"
MAP = "/Game/Maps/VoxelPreview"
CHUNK_RADIUS = 10          # ~67 m each way of full-detail terrain (21x21 columns)
ALTITUDE_M   = 700.0       # white pixel = +700 m (raise for taller mountains)


def log(m):
    unreal.log("MIRA-SETUP: " + m)


try:
    les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

    # 1. Fresh EMPTY level — no template background.
    les.new_level(MAP)
    log("empty level created: " + MAP)

    def spawn(cls, loc=None, rot=None, label=None):
        a = eas.spawn_actor_from_class(cls, loc or unreal.Vector(0, 0, 0),
                                       rot or unreal.Rotator(0, 0, 0))
        if label:
            a.set_actor_label(label)
        return a

    # 2. Lighting.
    sun = spawn(unreal.DirectionalLight, rot=unreal.Rotator(-45, -35, 0), label="Sun")
    try:
        sc = sun.get_editor_property("directional_light_component")
        sc.set_intensity(8.0)
        sc.set_editor_property("atmosphere_sun_light", True)
    except Exception:
        log("sun component tweak skipped (SkyAtmosphere still auto-binds the sun)")

    spawn(unreal.SkyAtmosphere, label="SkyAtmosphere")
    spawn(unreal.ExponentialHeightFog, loc=unreal.Vector(0, 0, 9000), label="HeightFog")

    sky = spawn(unreal.SkyLight, loc=unreal.Vector(0, 0, 9600), label="SkyLight")
    try:
        skc = sky.get_editor_property("light_component")
        skc.set_editor_property("real_time_capture", True)
    except Exception:
        log("skylight real-time-capture tweak skipped")

    # Exposure lock (the key fix for the washed-out look): unbound PPV, EV100 ~11.
    ppv = spawn(unreal.PostProcessVolume, loc=unreal.Vector(0, 0, 9600), label="ExposureLock")
    ppv.set_editor_property("unbound", True)
    s = ppv.get_editor_property("settings")
    s.set_editor_property("override_auto_exposure_min_brightness", True)
    s.set_editor_property("auto_exposure_min_brightness", 11.0)
    s.set_editor_property("override_auto_exposure_max_brightness", True)
    s.set_editor_property("auto_exposure_max_brightness", 11.0)
    ppv.set_editor_property("settings", s)
    log("lighting + exposure lock placed")

    # 3. The voxel world (EXR region preview).
    vw = spawn(unreal.VoxelWorld, label="MiraVoxelWorld")
    vw.set_editor_property("terrain_material", unreal.load_asset("/Game/Voxel/Materials/M_VoxelTerrainV2"))
    vw.set_editor_property("water_material",   unreal.load_asset("/Game/Voxel/Materials/M_VoxelWater"))
    vw.set_editor_property("flora_material",   unreal.load_asset("/Game/Voxel/Materials/M_VoxelFlora"))
    vw.set_editor_property("height_source", unreal.VoxelHeightSource.HEIGHTMAP_EXR)
    vw.set_editor_property("heightmap_file", unreal.FilePath(file_path=EXR))
    vw.set_editor_property("map_span_meters", 5000.0)
    vw.set_editor_property("heightmap_altitude_meters", ALTITUDE_M)
    vw.set_editor_property("heightmap_base_meters", 12.0)
    vw.set_editor_property("chunk_radius_xz", CHUNK_RADIUS)
    vw.call_method("GenerateWorld")
    log("voxel terrain generated (radius %d)" % CHUNK_RADIUS)

    # 4. Frame the camera on the terrain (it sits ~95 m up at the map centre).
    ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
    ues.set_level_viewport_camera_info(unreal.Vector(6500, 6500, 12800), unreal.Rotator(-22, 225, 0))

    # 5. Save the level so it's reusable.
    unreal.EditorLoadingAndSavingUtils.save_current_level()
    log("DONE — saved level " + MAP)
except Exception:
    unreal.log_error("MIRA-SETUP EXC: " + traceback.format_exc())
