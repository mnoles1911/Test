# setup_default_level.py - build + SAVE the default startup level so opening the
# editor and pressing Play "just works": streaming voxel world + first-person pawn +
# far vista + locked exposure, all pre-configured. Run ONCE via the bridge; after that
# DefaultEngine.ini points the editor's startup map here (set separately).
#
# Result: open editor -> this level loads -> press Play -> fly the streamed 10cm world,
# dig with LMB. No regenerate, no flipping settings. (The editor VIEWPORT is empty
# until Play because streaming geometry only builds in play - that's inherent.)

import unreal, traceback

EXR = "C:/Users/Matt Noles/Test-ue5/ue5/MiraThal/Content/Heightmaps/Export.exr"
MAP = "/Game/Maps/MiraStreamTest"

def log(m): unreal.log("MIRA-DEF: " + m)
def setp(obj, names, value):
    for n in names:
        try: obj.set_editor_property(n, value); return True
        except Exception: continue
    return False

try:
    les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

    # Fresh level saved at MAP (creates Content/Maps/MiraStreamTest.umap).
    les.new_level(MAP)
    # IDEMPOTENT: new_level can append to / reopen an existing level rather than
    # wiping it, so re-running this script used to STACK duplicate actors. Explicitly
    # clear every actor first so a re-run always yields exactly one of each.
    for a in list(eas.get_all_level_actors()):
        eas.destroy_actor(a)
    log("new level created + cleared at " + MAP)

    def spawn(cls, loc=None, rot=None, label=None):
        a = eas.spawn_actor_from_class(cls, loc or unreal.Vector(0,0,0), rot or unreal.Rotator(0,0,0))
        if label: a.set_actor_label(label)
        return a

    # --- Lighting ---
    sun = spawn(unreal.DirectionalLight, rot=unreal.Rotator(pitch=-45, yaw=-35, roll=0), label="Sun")
    c = sun.get_editor_property("light_component")
    c.set_editor_property("intensity", 10.0)
    for prop in ("atmosphere_sun_light","used_as_atmosphere_sun_light"):
        try: c.set_editor_property(prop, True)
        except Exception: pass
    spawn(unreal.SkyAtmosphere, label="SkyAtmosphere")
    spawn(unreal.SkyLight, loc=unreal.Vector(0,0,9600), label="SkyLight")

    # --- Exposure lock (fixes the washed-out auto-exposure adaptation) ---
    # An unbound PostProcessVolume covering the whole level; lock auto-exposure so the
    # bright flat terrain stops blowing out. (Absolute level may still want the
    # designer's eye, but this removes the adapting wash.)
    ppv = spawn(unreal.PostProcessVolume, label="ExposureLock")
    setp(ppv, ["unbound"], True)
    s = ppv.get_editor_property("settings")
    # Histogram auto-exposure LOCKED to scale 1.0 (min==max==1.0) with bias 0 = a
    # neutral, non-adapting exposure. NOTE: an earlier draft of this script set
    # AEM_MANUAL + bias 11, which is +11 EV (~2000x) and blows everything to white.
    # The saved level was corrected to the values below; keep them in sync here so a
    # re-run can't regress. Fine-tune AutoExposureBias to taste (it is NOT the cause of
    # the greyscale wash — that's a voxel vertex-color/material matter).
    setp(s, ["override_auto_exposure_method"], True)
    setp(s, ["auto_exposure_method"], unreal.AutoExposureMethod.AEM_HISTOGRAM)
    setp(s, ["override_auto_exposure_bias"], True)
    setp(s, ["auto_exposure_bias"], 0.0)    # neutral EV comp; tune to taste
    setp(s, ["override_auto_exposure_min_brightness"], True)
    setp(s, ["auto_exposure_min_brightness"], 1.0)  # min==max locks the exposure scale
    setp(s, ["override_auto_exposure_max_brightness"], True)
    setp(s, ["auto_exposure_max_brightness"], 1.0)
    # Colour grading: boost saturation (vivid voxel colours), a touch of contrast, slight
    # brightness gain. Mirrors the values dialled in via the bridge so a re-run keeps them.
    setp(s, ["override_color_saturation"], True)
    setp(s, ["color_saturation"], unreal.Vector4(1.30, 1.30, 1.30, 1.0))
    setp(s, ["override_color_contrast"], True)
    setp(s, ["color_contrast"], unreal.Vector4(1.05, 1.05, 1.05, 1.0))
    setp(s, ["override_color_gain"], True)
    setp(s, ["color_gain"], unreal.Vector4(1.06, 1.06, 1.06, 1.0))
    ppv.set_editor_property("settings", s)
    log("exposure lock + colour grading placed")

    terr  = unreal.load_asset("/Game/Voxel/Materials/M_VoxelTerrainV2")
    water = unreal.load_asset("/Game/Voxel/Materials/M_VoxelWater")
    flora = unreal.load_asset("/Game/Voxel/Materials/M_VoxelFlora")

    # --- Streaming voxel world (flags now default-ON in C++, but set explicitly) ---
    vw = spawn(unreal.VoxelWorld, label="MiraStreamWorld")
    setp(vw, ["terrain_material"], terr); setp(vw, ["water_material"], water); setp(vw, ["flora_material"], flora)
    setp(vw, ["height_source"], unreal.VoxelHeightSource.HEIGHTMAP_EXR)
    setp(vw, ["heightmap_file"], unreal.FilePath(file_path=EXR))
    setp(vw, ["map_span_meters"], 5000.0)
    # Gaea "height" 2500 m is the height-field CEILING; the EXR's partial values
    # (~0..0.31) are fraction-of-ceiling, so value x 2500 = each peak's TRUE height.
    # Do NOT normalize (it would fake a real <2500 m peak up to 2500 m). Verified this
    # gives ~300 m local relief (peaks ~775 m global) instead of the old flat look.
    setp(vw, ["heightmap_altitude_meters"], 2500.0)
    setp(vw, ["heightmap_base_meters"], 12.0)
    setp(vw, ["chunk_depth_below"], 2)
    setp(vw, ["create_collision"], True)
    setp(vw, ["enable_streaming"], True)
    setp(vw, ["async_streaming"], True)
    setp(vw, ["enable_lod"], True)
    # "See far": radius 64 chunks (~205 m each way) with SIX LOD tiers spread wide so
    # the far rings render coarse-and-cheap (LOD5 = a single 320 cm cube per chunk).
    # 1 chunk = 3.2 m. Async generation + async meshing keep the big radius smooth.
    # NOTE: render distance is ultimately capped by chunk-ACTOR count (one draw call
    # each), not by LOD — reaching ~1.5 km needs merged far meshes (a bigger change).
    setp(vw, ["stream_radius_chunks"], 64)
    setp(vw, ["max_column_ops_per_tick"], 16)
    setp(vw, ["max_column_jobs_in_flight"], 32)
    setp(vw, ["prefetch_lead_chunks"], 3)
    setp(vw, ["lod0_max_chunks"], 8)    # full 10 cm out to ~25 m
    setp(vw, ["lod1_max_chunks"], 16)   # 20 cm  to ~51 m
    setp(vw, ["lod2_max_chunks"], 26)   # 40 cm  to ~83 m
    setp(vw, ["lod3_max_chunks"], 40)   # 80 cm  to ~128 m
    setp(vw, ["lod4_max_chunks"], 54)   # 160 cm to ~173 m; beyond -> 320 cm to the edge
    log("streaming world configured (radius 64, 6 LOD tiers)")

    # --- Far vista (builds on begin play; PMC geometry isn't saved into the umap) ---
    fm = spawn(unreal.VoxelFarHeightmesh, label="MiraFarVista")
    setp(fm, ["material"], terr)
    setp(fm, ["heightmap_file"], unreal.FilePath(file_path=EXR))
    setp(fm, ["map_span_meters"], 5000.0)
    setp(fm, ["heightmap_altitude_meters"], 2500.0)  # MUST match the near terrain above
    setp(fm, ["heightmap_base_meters"], 12.0)
    setp(fm, ["grid_resolution"], 384)
    setp(fm, ["build_on_begin_play"], True)
    log("far vista placed (builds on play)")

    # --- PlayerStart above terrain centre (pawn starts flying) ---
    spawn(unreal.PlayerStart, loc=unreal.Vector(0,0,11000), rot=unreal.Rotator(pitch=-20, yaw=0, roll=0), label="PlayerStart")

    # --- Game mode override so Play spawns the first-person test pawn ---
    ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
    world = ues.get_editor_world()
    ws = world.get_world_settings()
    try: gm = unreal.MiraTestGameMode.static_class()
    except Exception: gm = unreal.load_class(None, "/Script/MiraThalCore.MiraTestGameMode")
    ws.set_editor_property("default_game_mode", gm)
    log("game mode override set")

    # --- Save the level ---
    les.save_current_level()
    log("DONE - saved %s. Set it as EditorStartupMap, then open+Play needs no setup." % MAP)
except Exception:
    unreal.log_error("MIRA-DEF EXC: " + traceback.format_exc())
