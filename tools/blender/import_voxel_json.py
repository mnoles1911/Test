# ===========================================================================
# import_voxel_json.py — import a Voxel Studio export into Blender
# ===========================================================================
# Reads a tree/rock JSON export from tools/voxel_*_studio (the {x,y,z,m} +
# palette schema) and builds a single welded surface mesh (internal faces
# culled), with one material per voxel material id colored from the palette.
#
# THREE WAYS TO USE IT
#   1. Add-on: Edit > Preferences > Add-ons > Install… this file, enable it.
#      Then File > Import > Voxel Studio JSON (.json).
#   2. Scripting tab: open this file, press Run, then call
#         import_voxel_json("/path/tree.json")
#   3. Headless / CLI (see tools/blender/run.sh):
#         blender --background --python import_voxel_json.py -- \
#             /path/tree.json --save out.blend --render out.png --turntable 8
#
# Axes: the studios are +Y up; Blender is +Z up, so studio (x,y,z) maps to
# Blender (x, z, y). Voxels are placed at voxel_size_m (default 0.1 m) so the
# model is real-world scale (a 14 m tree = 14 Blender units).

bl_info = {
    "name": "Voxel Studio JSON Importer",
    "author": "Mira-Thal tools",
    "version": (1, 0, 0),
    "blender": (3, 0, 0),
    "location": "File > Import > Voxel Studio JSON",
    "description": "Import tree/rock voxel JSON from the Voxel Studios",
    "category": "Import-Export",
}

import json
import os
import sys
import math

# Preview colors per material id — kept in sync with the studios' palettes.
PALETTE = {
    # collapsed deployable ids
    10: (0.42, 0.27, 0.12), 11: (0.18, 0.29, 0.10),
    # tree/vegetation rich palette
    24: (0.30, 0.22, 0.12), 25: (0.42, 0.32, 0.18), 26: (0.14, 0.12, 0.10),
    27: (0.18, 0.32, 0.13), 28: (0.34, 0.55, 0.22), 29: (0.24, 0.46, 0.18),
    30: (0.50, 0.50, 0.26), 31: (0.18, 0.42, 0.28), 32: (0.16, 0.28, 0.13),
    # rock/stone (existing engine materials)
    1: (0.46, 0.47, 0.49), 7: (0.42, 0.38, 0.33), 9: (0.84, 0.80, 0.74),
    12: (0.60, 0.42, 0.23), 14: (0.27, 0.28, 0.31), 15: (0.48, 0.42, 0.37),
}
DEFAULT_RGB = (0.6, 0.6, 0.6)

# face = (neighbor offset, [4 corner offsets]) using a min-corner convention:
# a voxel (x,y,z) occupies the unit cell [x..x+1] in studio space.
_FACES = [
    ((1, 0, 0),  [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]),
    ((-1, 0, 0), [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)]),
    ((0, 1, 0),  [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)]),
    ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
    ((0, 0, 1),  [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]),
    ((0, 0, -1), [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)]),
]


def build_surface(solid, size):
    """PURE (no bpy): given {(x,y,z): material_id} build a welded surface mesh.

    Returns (verts, quads, quad_mat):
      verts    : list of (X, Y, Z) Blender coords (studio +Y up -> Blender +Z up)
      quads    : list of [i0, i1, i2, i3] vertex indices
      quad_mat : list of material ids, one per quad
    Internal faces (neighbor cell also solid) are culled.
    """
    vcache, verts, quads, quad_mat = {}, [], [], []

    def vid(corner):
        v = vcache.get(corner)
        if v is not None:
            return v
        sx, sy, sz = corner
        verts.append((sx * size, sz * size, sy * size))  # +Y up -> +Z up
        vcache[corner] = len(verts) - 1
        return len(verts) - 1

    for (x, y, z), mid in solid.items():
        for off, corners in _FACES:
            if (x + off[0], y + off[1], z + off[2]) in solid:
                continue  # internal face — cull
            quads.append([vid((x + c[0], y + c[1], z + c[2])) for c in corners])
            quad_mat.append(mid)
    return verts, quads, quad_mat


def load_export(path):
    with open(path) as f:
        data = json.load(f)
    if not isinstance(data, dict) or not isinstance(data.get("voxels"), list):
        raise ValueError("not a Voxel Studio export (missing voxels array)")
    return data


# --------------------------------------------------------------------------
# bpy-dependent: build the Blender object (only runs inside Blender)
# --------------------------------------------------------------------------
def import_voxel_json(path, scale=None, name=None):
    import bpy  # imported lazily so the pure functions stay testable
    data = load_export(path)
    size = float(scale if scale is not None else data.get("voxel_size_m", 0.1))
    name = name or os.path.splitext(os.path.basename(path))[0]

    solid = {(int(v["x"]), int(v["y"]), int(v["z"])): int(v["m"]) for v in data["voxels"]}
    verts, quads, quad_mat = build_surface(solid, size)

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], quads)
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    # materials: one slot per used id, in sorted order
    used = sorted(set(quad_mat))
    slot_of = {}
    for mid in used:
        m = bpy.data.materials.new(f"vox_{mid}")
        m.diffuse_color = (*PALETTE.get(mid, DEFAULT_RGB), 1.0)
        try:
            m.use_nodes = True
            bsdf = m.node_tree.nodes.get("Principled BSDF")
            if bsdf:
                bsdf.inputs["Base Color"].default_value = (*PALETTE.get(mid, DEFAULT_RGB), 1.0)
                bsdf.inputs["Roughness"].default_value = 0.9
        except Exception:
            pass
        obj.data.materials.append(m)
        slot_of[mid] = len(slot_of)
    for poly, mid in zip(mesh.polygons, quad_mat):
        poly.material_index = slot_of[mid]

    mesh.validate()
    mesh.update()
    print(f"[import_voxel_json] {name}: {len(solid)} voxels -> {len(verts)} verts, {len(quads)} faces")
    return obj


def _frame_and_render(obj, render_path, turntable=0):
    import bpy
    # camera + sun framing the object
    bbox = [obj.matrix_world @ v.co for v in obj.data.vertices] if obj.data.vertices else []
    cx = sum(p.x for p in bbox) / len(bbox); cy = sum(p.y for p in bbox) / len(bbox); cz = sum(p.z for p in bbox) / len(bbox)
    rad = max((max(abs(p.x-cx), abs(p.y-cy), abs(p.z-cz)) for p in bbox), default=5) * 2.5 + 2

    sun_data = bpy.data.lights.new("Sun", 'SUN'); sun_data.energy = 3
    sun = bpy.data.objects.new("Sun", sun_data); bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(55), 0, math.radians(35))

    cam_data = bpy.data.cameras.new("Cam"); cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam); bpy.context.scene.camera = cam
    scene = bpy.context.scene
    scene.render.resolution_x = 1024; scene.render.resolution_y = 1024

    def look_from(angle_deg):
        a = math.radians(angle_deg)
        cam.location = (cx + math.cos(a)*rad, cy - math.sin(a)*rad, cz + rad*0.6)
        dx, dy, dz = cx-cam.location.x, cy-cam.location.y, cz-cam.location.z
        cam.rotation_euler = (math.atan2(math.hypot(dx, dy), dz), 0, math.atan2(dy, dx) + math.pi/2)

    frames = max(1, turntable)
    base, ext = os.path.splitext(render_path)
    for i in range(frames):
        look_from(45 + (360 / frames) * i)
        scene.render.filepath = render_path if frames == 1 else f"{base}_{i:02d}{ext or '.png'}"
        bpy.ops.render.render(write_still=True)
        print(f"[import_voxel_json] rendered {scene.render.filepath}")


# --------------------------------------------------------------------------
# Add-on operator (interactive File > Import)
# --------------------------------------------------------------------------
def _register_addon():
    import bpy
    from bpy_extras.io_utils import ImportHelper
    from bpy.props import StringProperty, FloatProperty

    class IMPORT_OT_voxel_studio_json(bpy.types.Operator, ImportHelper):
        bl_idname = "import_scene.voxel_studio_json"
        bl_label = "Import Voxel Studio JSON"
        filename_ext = ".json"
        filter_glob: StringProperty(default="*.json", options={'HIDDEN'})
        scale: FloatProperty(name="Voxel size (m)", default=0.0, description="0 = use file's voxel_size_m")

        def execute(self, context):
            import_voxel_json(self.filepath, scale=(self.scale or None))
            return {'FINISHED'}

    def menu(self, context):
        self.layout.operator(IMPORT_OT_voxel_studio_json.bl_idname, text="Voxel Studio JSON (.json)")

    bpy.utils.register_class(IMPORT_OT_voxel_studio_json)
    bpy.types.TOPBAR_MT_file_import.append(menu)
    _register_addon._cls = IMPORT_OT_voxel_studio_json
    _register_addon._menu = menu


def register():
    _register_addon()


def unregister():
    import bpy
    try:
        bpy.types.TOPBAR_MT_file_import.remove(_register_addon._menu)
        bpy.utils.unregister_class(_register_addon._cls)
    except Exception:
        pass


# --------------------------------------------------------------------------
# CLI entry (headless) + interactive Run
# --------------------------------------------------------------------------
def _cli():
    argv = sys.argv
    args = argv[argv.index("--") + 1:] if "--" in argv else []
    if not args:
        # interactive "Run" in the Text editor: just register the menu
        try:
            register()
            print("[import_voxel_json] registered — use File > Import > Voxel Studio JSON")
        except Exception as e:
            print("register skipped:", e)
        return
    path = args[0]
    opt = {"scale": None, "render": None, "save": None, "turntable": 0}
    i = 1
    while i < len(args):
        a = args[i]
        if a == "--scale": opt["scale"] = float(args[i+1]); i += 2
        elif a == "--render": opt["render"] = args[i+1]; i += 2
        elif a == "--save": opt["save"] = args[i+1]; i += 2
        elif a == "--turntable": opt["turntable"] = int(args[i+1]); i += 2
        else: i += 1
    obj = import_voxel_json(path, scale=opt["scale"])
    if opt["render"]:
        _frame_and_render(obj, opt["render"], turntable=opt["turntable"])
    if opt["save"]:
        import bpy
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(opt["save"]))
        print(f"[import_voxel_json] saved {opt['save']}")


if __name__ == "__main__":
    _cli()
