# setup_streaming_test.py - build a PLAYABLE streaming test level for P1-P4.
#
# Unlike setup_voxel_preview.py (a fixed, non-streaming preview), this configures
# the voxel world for live STREAMING + ASYNC + LOD and drops in a first-person test
# pawn (AMiraFPCharacter via AMiraTestGameMode) so you can press Play and fly/walk
# through the 10cm world while terrain pages in around you.
#
# CONTROLS once you press Play: WASD move, mouse look, Left-Shift sprint, C crouch,
# Space jump, F toggles fly (starts flying so you don't fall before terrain loads).
#
# Run via the mcp-unreal execute_script bridge with the editor open AND the module
# built (the MiraTestGameMode / MiraFPCharacter classes must exist).

import unreal, math, traceback

EXR = "C:/Users/Matt Noles/Test-ue5/ue5/MiraThal/Content/Heightmaps/Export.exr"

def log(m): unreal.log("MIRA-STREAM: " + m)

def set_prop(obj, names, value):
    """Set the first property name that exists (UE python snake_case can vary)."""
    for n in names:
        try:
            obj.set_editor_property(n, value)
            return True
        except Exception:
            continue
    unreal.log_warning("MIRA-STREAM: could not set any of %s" % (names,))
    return False

try:
    eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    unreal.EditorLoadingAndSavingUtils.new_blank_map(False)
    log("blank level created (transient)")

    def spawn(cls, loc=None, rot=None, label=None):
        a = eas.spawn_actor_from_class(cls, loc or unreal.Vector(0,0,0), rot or unreal.Rotator(0,0,0))
        if label: a.set_actor_label(label)
        return a

    # --- Lighting (same as the preview: sun drives atmosphere + skylight) ---
    sun = spawn(unreal.DirectionalLight, rot=unreal.Rotator(pitch=-45, yaw=-35, roll=0), label="Sun")
    c = sun.get_editor_property("light_component")
    c.set_editor_property("intensity", 10.0)
    for prop in ("atmosphere_sun_light","used_as_atmosphere_sun_light"):
        try: c.set_editor_property(prop, True)
        except Exception: pass
    spawn(unreal.SkyAtmosphere, label="SkyAtmosphere")
    spawn(unreal.SkyLight, loc=unreal.Vector(0,0,9600), label="SkyLight")
    log("lighting placed")

    terr  = unreal.load_asset("/Game/Voxel/Materials/M_VoxelTerrainV2")
    water = unreal.load_asset("/Game/Voxel/Materials/M_VoxelWater")
    flora = unreal.load_asset("/Game/Voxel/Materials/M_VoxelFlora")

    # --- Streaming voxel world (no upfront GenerateWorld; it streams in PIE) ---
    vw = spawn(unreal.VoxelWorld, label="MiraStreamWorld")
    set_prop(vw, ["terrain_material"], terr)
    set_prop(vw, ["water_material"], water)
    set_prop(vw, ["flora_material"], flora)
    set_prop(vw, ["height_source"], unreal.VoxelHeightSource.HEIGHTMAP_EXR)
    set_prop(vw, ["heightmap_file"], unreal.FilePath(file_path=EXR))
    set_prop(vw, ["map_span_meters"], 5000.0)
    set_prop(vw, ["heightmap_altitude_meters"], 700.0)
    set_prop(vw, ["heightmap_base_meters"], 12.0)
    set_prop(vw, ["chunk_depth_below"], 2)
    # NOTE: UE's Python API drops the leading 'b' on bool UPROPERTYs, so
    # bEnableStreaming is "enable_streaming" here, NOT "b_enable_streaming".
    set_prop(vw, ["create_collision"], True)
    # P1 async streaming ON
    set_prop(vw, ["enable_streaming"], True)
    set_prop(vw, ["async_streaming"], True)
    set_prop(vw, ["stream_radius_chunks"], 8)
    set_prop(vw, ["stream_evict_padding_chunks"], 2)
    set_prop(vw, ["max_column_ops_per_tick"], 16)
    set_prop(vw, ["max_column_jobs_in_flight"], 12)
    set_prop(vw, ["prefetch_lead_chunks"], 2)
    # P3 LOD ON, tight tiers so coarsening is visible within the radius
    set_prop(vw, ["enable_lod"], True)
    set_prop(vw, ["lod0_max_chunks"], 3)
    set_prop(vw, ["lod1_max_chunks"], 5)
    set_prop(vw, ["lod2_max_chunks"], 7)
    log("streaming voxel world configured (streaming+async+LOD ON)")

    # --- Far vista so the horizon is filled while near terrain streams (P4) ---
    fm = spawn(unreal.VoxelFarHeightmesh, label="MiraFarVista")
    set_prop(fm, ["material"], terr)
    set_prop(fm, ["heightmap_file"], unreal.FilePath(file_path=EXR))
    set_prop(fm, ["map_span_meters"], 5000.0)
    set_prop(fm, ["heightmap_altitude_meters"], 700.0)
    set_prop(fm, ["heightmap_base_meters"], 12.0)
    set_prop(fm, ["grid_resolution"], 512)
    fm.call_method("BuildFarMesh")
    log("far vista built")

    # --- PlayerStart at a vantage above the terrain centre (pawn starts flying) ---
    spawn(unreal.PlayerStart, loc=unreal.Vector(0,0,11000),
          rot=unreal.Rotator(pitch=-20, yaw=0, roll=0), label="PlayerStart")

    # --- Game mode override so Play spawns the first-person test pawn ---
    try:
        ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
        world = ues.get_editor_world()
        ws = world.get_world_settings()
        gm = None
        try: gm = unreal.MiraTestGameMode.static_class()
        except Exception: gm = unreal.load_class(None, "/Script/MiraThalCore.MiraTestGameMode")
        ws.set_editor_property("default_game_mode", gm)
        log("game mode override set -> MiraTestGameMode (spawns AMiraFPCharacter)")
    except Exception:
        unreal.log_error("MIRA-STREAM: game mode set FAILED:\n" + traceback.format_exc())

    log("DONE - press Play. WASD+mouse fly, F walk, Shift sprint, C crouch.")
except Exception:
    unreal.log_error("MIRA-STREAM EXC: " + traceback.format_exc())
