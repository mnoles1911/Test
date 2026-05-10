"""
tools/build_texture_atlas.py

Packs source face textures into the game's voxel texture atlas.
Run from the repo root:

    python tools/build_texture_atlas.py [pack_name]

Defaults to pack_name="default". Requires Pillow:

    pip install Pillow

The script reads source PNGs from
  assets/voxels/texture_packs/<pack_name>/source/
downscales each to the pack's tile_size, packs them into a single
atlas.png, and emits a manifest.json mapping material_id -> face tile
coordinates that the Godot side reads at startup.

Two faces are auto-built and do NOT need to exist in source/:
  - grass_side.png is composited from dirt_all + grass_top (top-edge
    green strip blended into a dirt base — Minecraft-style)
  - log_bottom is the same image as log_top (end-grain on both ends)

Empty material slots (e.g. water, which is rendered separately by
WaterChunkMesher) are recorded in the manifest as null.
"""

import sys
import os
import json
from PIL import Image, ImageStat


PACKS_DIR = "assets/voxels/texture_packs"


# --------------------------------------------------------------
# Atlas grid layout
# --------------------------------------------------------------
# Each entry maps a source filename (without extension) to its
# (column, row) position in the atlas grid. One slot = tile_size px.
# Add new entries here when adding new materials. Keep slots stable
# across releases — moving a tile invalidates UV coords baked into
# the VoxelBlockyLibrary in Godot.

ATLAS_LAYOUT = {
    # Row 0
    "stone_all":      (0, 0),
    "dirt_all":       (1, 0),
    "grass_top":      (2, 0),
    "grass_side":     (3, 0),   # auto-composited; not in source/
    "sand_all":       (4, 0),
    "gravel_all":     (5, 0),
    "clay_all":       (6, 0),
    "marble_all":     (7, 0),
    # Row 1
    "log_top":        (0, 1),
    "log_side":       (1, 1),
    "leaves_all":     (2, 1),
    "copper_ore_all": (3, 1),
    "bedrock_all":    (4, 1),
}


# --------------------------------------------------------------
# Material -> face -> source key mapping
# --------------------------------------------------------------
# For each VoxelMaterial.material_id, which atlas tile drives each
# of the three faces? "all" means top/side/bottom share one tile.
#
# This mirrors the table in the .tres files. When a new material
# lands, add an entry here AND an entry in ATLAS_LAYOUT above.

MATERIAL_FACES = {
    1:  {"all": "stone_all"},
    2:  {"all": "dirt_all"},
    3:  {"top": "grass_top", "side": "grass_side", "bottom": "dirt_all"},
    4:  {"all": "sand_all"},
    5:  {},   # water — rendered by WaterChunkMesher, no atlas tiles
    6:  {"all": "bedrock_all"},
    7:  {"all": "gravel_all"},
    8:  {"all": "clay_all"},
    9:  {"all": "marble_all"},
    10: {"top": "log_top", "side": "log_side", "bottom": "log_top"},
    11: {"all": "leaves_all"},
    12: {"all": "copper_ore_all"},
}


# --------------------------------------------------------------
# Utilities
# --------------------------------------------------------------

def composite_grass_side(dirt_img, grass_top_img, tile_size):
    """
    Build the grass-block side face: a dirt base with a green strip
    along the top edge that fades into the dirt below.

    Strip height = max(4, tile_size // 5). The green's color is the
    average of the central band of grass_top (so it stays in tone with
    the top face even if the user edits one and not the other).
    """
    result = dirt_img.copy().convert("RGBA")
    # Sample the average green from the central horizontal band of the
    # grass_top texture — avoids picking up any darker edges if the AI
    # output has vignette or non-tiling artifacts.
    crop = grass_top_img.convert("RGB").crop(
        (0, tile_size // 3, tile_size, 2 * tile_size // 3)
    )
    avg = ImageStat.Stat(crop).mean[:3]
    avg = (int(avg[0]), int(avg[1]), int(avg[2]))
    strip_h = max(4, tile_size // 5)

    pixels = result.load()
    for y in range(strip_h):
        # Linear fade from full green at the top to full dirt at strip_h.
        # The 0.6 multiplier prevents a hard-edge transition — even at
        # the bottom of the strip we keep a hint of green creeping into
        # the dirt for the classic Minecraft "messy edge" look.
        fade = 1.0 - (y / strip_h) * 0.6
        for x in range(tile_size):
            base = pixels[x, y]
            r, g, b = base[0], base[1], base[2]
            a = base[3] if len(base) > 3 else 255
            nr = int(r * (1.0 - fade) + avg[0] * fade)
            ng = int(g * (1.0 - fade) + avg[1] * fade)
            nb = int(b * (1.0 - fade) + avg[2] * fade)
            pixels[x, y] = (nr, ng, nb, a)
    return result


def load_pack_meta(pack_dir):
    with open(os.path.join(pack_dir, "pack.json")) as f:
        return json.load(f)


def load_source_images(source_dir, tile_size):
    """
    Read every source PNG referenced by ATLAS_LAYOUT (skipping the
    auto-built grass_side) and resize to tile_size.

    Returns: { name: PIL.Image }
    """
    loaded = {}
    for name in ATLAS_LAYOUT:
        if name == "grass_side":
            continue
        path = os.path.join(source_dir, name + ".png")
        if not os.path.exists(path):
            print(f"  MISSING source PNG: {path} (slot will be blank)")
            continue
        img = Image.open(path).convert("RGBA")
        if img.size != (tile_size, tile_size):
            img = img.resize((tile_size, tile_size), Image.LANCZOS)
        loaded[name] = img
    return loaded


# --------------------------------------------------------------
# Main
# --------------------------------------------------------------

def build_atlas(pack_name):
    pack_dir = os.path.join(PACKS_DIR, pack_name)
    if not os.path.isdir(pack_dir):
        print(f"ERROR: pack directory not found: {pack_dir}")
        sys.exit(1)

    meta = load_pack_meta(pack_dir)
    tile_size = int(meta["tile_size"])
    atlas_size = int(meta["atlas_size"])
    source_dir = os.path.join(pack_dir, "source")

    print(f"[atlas] building pack '{pack_name}'")
    print(f"        tile_size = {tile_size}px, atlas_size = {atlas_size}px")
    print(f"        source = {source_dir}")

    loaded = load_source_images(source_dir, tile_size)

    # Composite grass_side from dirt_all + grass_top.
    if "dirt_all" in loaded and "grass_top" in loaded:
        loaded["grass_side"] = composite_grass_side(
            loaded["dirt_all"], loaded["grass_top"], tile_size
        )
        print("        grass_side: auto-composited from dirt_all + grass_top")
    else:
        print("        grass_side: SKIPPED (need both dirt_all + grass_top)")

    # Build the atlas image, transparent background so missing tiles
    # are visibly missing rather than filled with arbitrary colour.
    atlas = Image.new("RGBA", (atlas_size, atlas_size), (0, 0, 0, 0))
    tiles = {}
    for name, (col, row) in ATLAS_LAYOUT.items():
        x = col * tile_size
        y = row * tile_size
        if x + tile_size > atlas_size or y + tile_size > atlas_size:
            print(f"  ERROR: tile {name} at ({col},{row}) overflows atlas")
            continue
        tiles[name] = {"x": x, "y": y, "w": tile_size, "h": tile_size}
        if name in loaded:
            atlas.paste(loaded[name], (x, y))

    # Build the per-material face manifest. Coordinates are normalized
    # UVs (0..1) for direct use in shaders, plus pixel coords for the
    # Godot Inspector flow which uses tile indices.
    materials = {}
    for mat_id, face_map in MATERIAL_FACES.items():
        mat_entry = {"top": None, "side": None, "bottom": None}
        if "all" in face_map:
            tile = tiles.get(face_map["all"])
            mat_entry["top"] = tile
            mat_entry["side"] = tile
            mat_entry["bottom"] = tile
        else:
            for face, key in face_map.items():
                mat_entry[face] = tiles.get(key)
        materials[str(mat_id)] = mat_entry

    # Write outputs.
    out_atlas = os.path.join(pack_dir, "atlas.png")
    out_manifest = os.path.join(pack_dir, "manifest.json")
    atlas.save(out_atlas)
    manifest = {
        "pack": meta,
        "tiles": tiles,
        "materials": materials,
    }
    with open(out_manifest, "w") as f:
        json.dump(manifest, f, indent=2)

    print(f"[atlas] wrote {out_atlas}")
    print(f"[atlas] wrote {out_manifest}")
    print(f"[atlas] packed {len(loaded)} tiles into {atlas_size}x{atlas_size} atlas")
    if len(loaded) < len(ATLAS_LAYOUT):
        missing = sorted(set(ATLAS_LAYOUT) - set(loaded))
        print(f"[atlas] MISSING: {', '.join(missing)}")
        print(f"[atlas] (those slots are blank in the atlas)")


if __name__ == "__main__":
    pack = sys.argv[1] if len(sys.argv) > 1 else "default"
    build_atlas(pack)
