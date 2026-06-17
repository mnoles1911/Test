# setup_voxel_preview.py — build a CLEAN, lit preview showing the imported EXR
# voxel terrain PLUS the whole-map far heightmesh vista. Run via the mcp-unreal
# execute_script bridge with the editor open.
#
# WHAT IT MAKES:
#   * a transient BLANK level (no Open-World template background) — not saved, so
#     no 1.3 GB .umap; re-run this to rebuild it;
#   * lighting that reads right: a sun that drives the Sky Atmosphere + sky light
#     + height fog, with plain auto-exposure (the hard EV100 lock crushed it dark);
#   * the MiraVoxelWorld near terrain (~67 m full-detail region from Export.exr);
#   * the AVoxelFarHeightmesh VISTA — one coarse mesh of the entire 5 km map so the
#     horizon is filled in behind the near voxels.
#
# NOTE: the EXR path below is this machine's absolute path. Local editor convenience.

import unreal, math, traceback

EXR = "C:/Users/Matt Noles/Test-ue5/ue5/MiraThal/Content/Heightmaps/Export.exr"
CHUNK_RADIUS = 10          # ~67 m each way of full-detail near terrain
ALTITUDE_M   = 700.0       # white pixel = +700 m (raise for taller mountains)
FAR_GRID     = 512         # far vista vertices per side (~10 m/vertex on 5 km)

def log(m): unreal.log("MIRA-SETUP: " + m)

try:
    eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    # Transient blank level — no template background, nothing saved to disk.
    unreal.EditorLoadingAndSavingUtils.new_blank_map(False)
    log("blank level created (transient)")

    def spawn(cls, loc=None, rot=None, label=None):
        a = eas.spawn_actor_from_class(cls, loc or unreal.Vector(0,0,0), rot or unreal.Rotator(0,0,0))
        if label: a.set_actor_label(label)
        return a

    # --- Lighting (the version that reads right) ---
    sun = spawn(unreal.DirectionalLight, rot=unreal.Rotator(-45,-35,0), label="Sun")
    c = sun.get_editor_property("light_component")
    c.set_editor_property("intensity", 10.0)
    for prop in ("atmosphere_sun_light","used_as_atmosphere_sun_light"):
        try: c.set_editor_property(prop, True)
        except Exception: pass
    spawn(unreal.SkyAtmosphere, label="SkyAtmosphere")
    # NOTE: no ExponentialHeightFog — at 10 cm (cm world units) the default fog
    # density (per-cm) hazes even near objects to grey. Add fog later with a tiny
    # density (~3e-5) tuned for cm units if atmospheric depth is wanted.
    spawn(unreal.SkyLight, loc=unreal.Vector(0,0,9600), label="SkyLight")
    log("lighting placed (sun drives atmosphere, auto-exposure)")

    terr = unreal.load_asset("/Game/Voxel/Materials/M_VoxelTerrainV2")
    water = unreal.load_asset("/Game/Voxel/Materials/M_VoxelWater")
    flora = unreal.load_asset("/Game/Voxel/Materials/M_VoxelFlora")

    # --- Near voxel terrain ---
    vw = spawn(unreal.VoxelWorld, label="MiraVoxelWorld")
    vw.set_editor_property("terrain_material", terr)
    vw.set_editor_property("water_material", water)
    vw.set_editor_property("flora_material", flora)
    vw.set_editor_property("height_source", unreal.VoxelHeightSource.HEIGHTMAP_EXR)
    vw.set_editor_property("heightmap_file", unreal.FilePath(file_path=EXR))
    vw.set_editor_property("map_span_meters", 5000.0)
    vw.set_editor_property("heightmap_altitude_meters", ALTITUDE_M)
    vw.set_editor_property("heightmap_base_meters", 12.0)
    vw.set_editor_property("chunk_radius_xz", CHUNK_RADIUS)
    vw.call_method("GenerateWorld")
    log("near voxel terrain generated (radius %d)" % CHUNK_RADIUS)

    # --- Far vista (whole-map heightmesh) ---
    fm = spawn(unreal.VoxelFarHeightmesh, label="MiraFarVista")
    fm.set_editor_property("material", terr)
    fm.set_editor_property("heightmap_file", unreal.FilePath(file_path=EXR))
    fm.set_editor_property("map_span_meters", 5000.0)
    fm.set_editor_property("heightmap_altitude_meters", ALTITUDE_M)
    fm.set_editor_property("heightmap_base_meters", 12.0)
    fm.set_editor_property("grid_resolution", FAR_GRID)
    fm.set_editor_property("reverse_winding", False)  # up-facing front faces (verified)
    fm.call_method("BuildFarMesh")
    log("far vista mesh built (grid %d)" % FAR_GRID)

    # --- Frame the camera on the near terrain ---
    xs=[]; ys=[]; zs=[]
    for a in eas.get_all_level_actors():
        if a.get_class().get_name() == "VoxelChunkActor":
            o=a.get_actor_location(); xs.append(o.x); ys.append(o.y); zs.append(o.z)
    if xs:
        cx=(min(xs)+max(xs))/2; cy=(min(ys)+max(ys))/2; cz=(min(zs)+max(zs))/2
        span=max(max(xs)-min(xs), max(ys)-min(ys), 3000.0)
        cam=unreal.Vector(cx+span*0.9, cy+span*0.9, cz+span*0.7)
        d=unreal.Vector(cx-cam.x, cy-cam.y, cz-cam.z)
        yaw=math.degrees(math.atan2(d.y,d.x)); pitch=math.degrees(math.atan2(d.z, math.sqrt(d.x*d.x+d.y*d.y)))
        unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).set_level_viewport_camera_info(cam, unreal.Rotator(pitch,yaw,0))
    log("DONE — near terrain + far vista built")
except Exception:
    unreal.log_error("MIRA-SETUP EXC: " + traceback.format_exc())
