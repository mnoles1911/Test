"""
tools/build_texture_atlas.py

Packs source face textures into the game's voxel texture atlas.
Run from the repo root:

    python tools/build_texture_atlas.py [pack_name]

Defaults to pack_name="default". Requires Pillow:

    pip install Pillow

The script reads source PNGs from
  assets/voxels/texture_packs/<pack_name>/source/
nearest-neighbour-downscales each to the pack's tile_size, packs them
into a single atlas.png, and emits a manifest.json mapping
material_id -> face tile coordinates that the Godot side reads at
startup.

Downscale uses NEAREST because the target is pixel art. The pipeline
assumes source PNGs are pixel-art-on-grid renders: a 16x16 (or 32x32)
underlying tile upscaled to 1024x1024 so each output pixel is a
64x64 (or 32x32) flat block of one colour. On that input NEAREST
samples one source pixel per output tile pixel, preserving the grid
exactly — no averaging, no anti-aliasing, no blur.

Designer 2026-05-27: if your source PNG is a photo-style texture
(continuous gradients, no clean pixel grid), NEAREST will sample 16
essentially-random pixels and produce noise. The build will print a
WARN line for any source whose mean-2x2-block-variance suggests
non-pixel-art input — switch to a pixel-art generator (Retrodiffusion,
PixelLab.ai, or hand-paint in Aseprite) rather than changing the
downscale algorithm. See tools/AI_TEXTURE_PROMPTS.md for the
recommended generation workflow.

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
from PIL import Image, ImageStat, ImageChops


PACKS_DIR = "assets/voxels/texture_packs"


# Sources whose white background should be color-keyed to alpha during
# atlas build. AI image generators (Gemini, DALL-E, Midjourney) tend to
# output flat RGB with white "transparent gaps" rather than true RGBA,
# so we convert that white to alpha here to keep the artist workflow
# simple — drop in a PNG, re-run the builder, done.
CHROMA_KEY_MATERIALS = {"leaves_all"}


# Filename aliases. If an AI generator (or the artist) saves a source
# PNG under a "close but wrong" filename, the builder would silently
# skip it and leave that slot blank. The aliases below map common
# typos to the canonical slot name so the build still picks the file
# up — with a loud warning so the artist can rename it for next time.
#
# Add new aliases here when you catch a recurring naming mistake.
FILENAME_ALIASES = {
    "dark_ore_all":   "stone_dark_all",   # stone variant, not an ore
    "dark_stone_all": "stone_dark_all",   # word order swap
}


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
    "stone_all":       (0, 0),
    "dirt_all":        (1, 0),
    "grass_top":       (2, 0),
    "grass_side":      (3, 0),   # auto-composited; not in source/
    "sand_all":        (4, 0),
    "gravel_all":      (5, 0),
    "clay_all":        (6, 0),
    "marble_all":      (7, 0),
    "snow_all":        (8, 0),   # new — Tier 2 snow caps (paint source PNG to enable)
    "stone_dark_all":  (9, 0),   # new — Tier 3 marble-jitter sibling
    "iron_ore_all":    (10, 0),  # new — Tier 4 vein ore
    # Row 1
    "log_top":         (0, 1),
    "log_side":        (1, 1),
    "leaves_all":      (2, 1),
    "copper_ore_all":  (3, 1),
    "bedrock_all":     (4, 1),
    # Tree-asset palette (ids 24-28) — placeholder pixel art; replace with
    # real tiles. Emitted by tools/voxel_tree_studio. See DESIGNER_TODO.
    "bark_all":        (5, 1),
    "heartwood_all":   (6, 1),
    "deadwood_all":    (7, 1),
    "leaf_dark_all":   (8, 1),
    "leaf_light_all":  (9, 1),
    # Vegetation (ground cover, ferns) — ids 29-31. Placeholders; replace.
    "grass_blade_all": (10, 1),
    "grass_dry_all":   (11, 1),
    "fern_frond_all":  (12, 1),
    "moss_all":        (13, 1),   # rock cover (id 32) — placeholder
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
    13: {"all": "snow_all"},        # Tier 2 — snow caps above the snow line
    14: {"all": "stone_dark_all"},  # Tier 3 — darker stone variant
    15: {"all": "iron_ore_all"},    # Tier 4 — iron ore vein
    # Tree-asset palette (placeholders) — from tools/voxel_tree_studio.
    24: {"all": "bark_all"},
    25: {"all": "heartwood_all"},
    26: {"all": "deadwood_all"},
    27: {"all": "leaf_dark_all"},
    28: {"all": "leaf_light_all"},
    29: {"all": "grass_blade_all"},
    30: {"all": "grass_dry_all"},
    31: {"all": "fern_frond_all"},
    32: {"all": "moss_all"},
}


# --------------------------------------------------------------
# Utilities
# --------------------------------------------------------------

def composite_grass_side(dirt_img, grass_top_img, tile_size):
    """
    Build the grass-block side face: a dirt base with a green band
    along the top edge. The band uses two discrete tones so it reads
    as crisp pixel art at 16 px (a linear sub-pixel fade looked
    anti-aliased once we dropped to a 16 px atlas).

    For tile_size >= 12: 2-row solid green + 1-row mixed dirt+green
    "messy edge" row that imitates the classic Minecraft scatter
    without producing AA gradients. For smaller tiles we fall back to
    1 + 1.

    The green's color is the average of the central band of grass_top
    so it stays in tone with the top face even if the user edits one
    and not the other.
    """
    result = dirt_img.copy().convert("RGBA")
    # Sample the average green from the central horizontal band of the
    # grass_top texture — avoids picking up any darker edges if the AI
    # output has vignette or non-tiling artifacts.
    crop = grass_top_img.convert("RGB").crop(
        (0, tile_size // 3, tile_size, 2 * tile_size // 3)
    )
    avg = ImageStat.Stat(crop).mean[:3]
    green = (int(avg[0]), int(avg[1]), int(avg[2]))

    # Band heights. The "messy" row is a scatter of grass pixels among
    # dirt pixels — no per-pixel blending, so every pixel reads as
    # either fully green or fully dirt (pixel-art-correct).
    solid_h = max(1, tile_size // 8)            # 2 rows at 16 px
    messy_h = 1 if tile_size >= 12 else 0       # 1 row at 16 px, 0 at 8 px

    pixels = result.load()
    for y in range(solid_h):
        for x in range(tile_size):
            a = pixels[x, y][3] if len(pixels[x, y]) > 3 else 255
            pixels[x, y] = (green[0], green[1], green[2], a)

    # Messy row: deterministic scatter (alternate pixels, offset by row)
    # so the result is stable across builds and tiles seamlessly.
    for y in range(solid_h, solid_h + messy_h):
        for x in range(tile_size):
            if (x + y) % 2 == 0:
                a = pixels[x, y][3] if len(pixels[x, y]) > 3 else 255
                pixels[x, y] = (green[0], green[1], green[2], a)
            # else: leave the dirt pixel as-is

    return result


def chroma_key_white(img, threshold=200, softness=40):
    """
    Convert white background to alpha. Any pixel whose minimum RGB
    channel is <= `threshold` stays fully opaque (these are the leafy
    parts); pixels with min channel >= `threshold + softness` become
    fully transparent (the background); pixels in the soft band fade
    linearly. Using min-channel rather than luminance handles
    saturated greens correctly — bright lime would have high luminance
    but low minimum channel, so it stays opaque.
    """
    img = img.convert("RGBA")
    r, g, b, _ = img.split()
    min_rg = ImageChops.darker(r, g)
    min_rgb = ImageChops.darker(min_rg, b)

    def lut(v):
        if v <= threshold:
            return 255
        if v >= threshold + softness:
            return 0
        return int(255 * (1.0 - (v - threshold) / softness))

    mask = min_rgb.point(lut)
    img.putalpha(mask)
    return img


def _warn_if_not_pixel_art(img, tile_size, name):
    """
    Heuristic: if the source is pixel-art-on-grid, each (src_w/tile_size)
    by (src_h/tile_size) cell should be a flat block of one colour (low
    intra-cell variance). If most cells have high intra-cell variance
    the source is a photo / painterly texture and NEAREST will discard
    everything but one pixel per cell — producing noise.

    We sample a 16x16 subgrid (not the full tile_size grid — that would
    be slow on 1024x1024 sources) and flag if mean cell-variance is
    above a permissive threshold (covers obvious photo input without
    false-positiving slightly-hand-shaky pixel art).
    """
    src_w, src_h = img.size
    cell_w = src_w // 16
    cell_h = src_h // 16
    if cell_w < 4 or cell_h < 4:
        return  # tiny source — heuristic won't be reliable
    rgb = img.convert("RGB")
    high_variance_cells = 0
    total_cells = 0
    threshold = 15.0   # ~1.5 levels of 0-255 stddev per channel
    for cy in range(16):
        for cx in range(16):
            total_cells += 1
            cell = rgb.crop((cx * cell_w, cy * cell_h,
                             cx * cell_w + cell_w, cy * cell_h + cell_h))
            stat = ImageStat.Stat(cell)
            # mean per-channel stddev across R/G/B; high = lots of
            # within-cell colour variation (= NOT a flat pixel-art cell).
            mean_stddev = sum(stat.stddev) / 3.0
            if mean_stddev > threshold:
                high_variance_cells += 1
    pct = (high_variance_cells / total_cells) * 100.0
    if pct >= 50.0:
        print(f"  WARN: {name} looks like PHOTO input ({pct:.0f}% of cells "
              f"have intra-cell variance > {threshold:.0f}). NEAREST will "
              f"sample one source pixel per cell -> noise.")
        print(f"        Regenerate this material with a pixel-art generator "
              f"(Retrodiffusion / PixelLab.ai) or hand-paint in Aseprite. "
              f"See tools/AI_TEXTURE_PROMPTS.md.")


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
            # Try filename aliases (common typos) before giving up.
            # If we find one, rename it in place so the next build is
            # clean and the artist gets a loud warning to rename at
            # generation time.
            aliased_name = None
            for alias, canonical in FILENAME_ALIASES.items():
                if canonical != name:
                    continue
                alias_path = os.path.join(source_dir, alias + ".png")
                if os.path.exists(alias_path):
                    aliased_name = alias
                    print(f"  WARN: found {alias}.png but slot is {name}.png "
                          f"-- renaming. Save future generations as "
                          f"{name}.png to avoid this warning.")
                    os.replace(alias_path, path)
                    # The .import file Godot generated for the alias
                    # is now orphaned; remove it so Godot reimports
                    # under the canonical name on next editor load.
                    alias_import = alias_path + ".import"
                    if os.path.exists(alias_import):
                        os.remove(alias_import)
                    break
            if aliased_name is None:
                print(f"  MISSING source PNG: {path} (slot will be blank)")
                continue
        img = Image.open(path).convert("RGBA")
        if name in CHROMA_KEY_MATERIALS:
            img = chroma_key_white(img)
            print(f"  {name}: white background -> alpha (chroma key applied)")
        if img.size != (tile_size, tile_size):
            # Detect photo-style input before downscaling — see module
            # docstring. We sample the source on the assumed pixel-art
            # grid (tile_size cells, each cell is src_w/tile_size px
            # wide). If most cells have low internal variance, the
            # source IS pixel art and NEAREST is correct. If most cells
            # have high internal variance, the source is a photo and
            # NEAREST will produce noise — warn the designer to swap
            # the source rather than the algorithm.
            _warn_if_not_pixel_art(img, tile_size, name)
            img = img.resize((tile_size, tile_size), Image.NEAREST)
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
