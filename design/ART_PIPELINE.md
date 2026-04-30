# Art Pipeline — Mira-Thal: Game One
## Workflow reference for creating, exporting, and importing game art

> This document covers HOW to make the art. For WHAT it should look like (palettes, location identity, character design), see `design/ART_DIRECTION.md`.

---

## Confirmed Approach

**2D pixel art in Godot 4.3.** Not 3D. The "2.5D" look comes from how sprites and tiles are drawn, not from a 3D camera or engine.

This is the same approach as Sea of Stars, Octopath Traveler, and Chained Echoes:
- Floors and terrain: **TileMap** with a tile atlas (32×32 tiles)
- Background layers (sky, distant mountains): **hand-painted single assets**, not tiled
- Characters, NPCs, props: **individual Sprite2D nodes** with AnimationTree
- Lighting: Godot `PointLight2D` + **normal maps** on tiles and character sprites

---

## Tools

| Tool | Role |
|---|---|
| **Aseprite** | Primary sprite and tile creation tool |
| AI-assisted generation | Background layer assistance (hand-paint over, do not ship raw) |
| Godot 4.3 editor | TileSet assembly, AnimationTree setup, scene composition |

---

## Tile Specification

| Property | Value |
|---|---|
| Tile size | **32×32 pixels** |
| Native scene resolution | 320×180 px (Godot viewport) |
| Tiles visible across screen (horizontal) | 10 tiles at 1:1 |
| Tiles visible vertically | ~5.6 tiles at 1:1 |
| Texture filter | Nearest (no blurring — set in project.godot) |

### What "32×32 tiles" means for art:

Each tile is a 32×32 pixel square drawn in Aseprite. In Godot, tiles are assembled into a `TileSet` resource, then placed in a `TileMapLayer` (Godot 4.3) to build rooms.

The **3/4 perspective** is baked into tile art:
- Floor tiles: drawn as if viewed slightly from above (10–15° depression angle)
- Wall tiles: drawn with a visible top face + front face — the top face is the "floor" of the level above
- Wall height in tiles: typically 2 tiles tall (64px), sometimes 3 for grand spaces

See `design/CAMERA_AND_PERSPECTIVE.md` for why this is an art decision, not a camera setting.

---

## Character Sprite Specification

| Property | Value |
|---|---|
| Sprite size | **32×48 pixels** (width × height) |
| Collision origin | Bottom center of the sprite (feet) |
| Facing directions | 4 (down, up, left, right) — side-view left/right can be mirrored |
| Walk cycle frames | 6 frames per direction (minimum) |
| Idle frames | 3–4 frames per direction |

### Aseprite setup for a character sprite sheet:

1. Canvas: 32×48 px per frame
2. Directions as separate **tags** in Aseprite: `walk_down`, `walk_up`, `walk_left`, `idle_down`, etc.
3. Export: `character_name_spritesheet.png` (all frames in a horizontal strip or grid)
4. Export JSON: Aseprite's built-in JSON export (for frame data) — **not required** if using Godot's SpriteFrames resource directly

---

## Normal Map Workflow

Normal maps add surface depth so `PointLight2D` sources cast micro-shadows across tiles and sprites. This is what gives the painted-rock look in the reference image.

### For tiles:
1. Paint the tile in Aseprite (the diffuse/color layer)
2. In Aseprite, create a **second file** with the same dimensions — this is the normal map
3. Paint the normal map using Aseprite's built-in Normal Map mode (`Edit → Generate Normal Map` from a height layer, or paint manually):
   - Flat surfaces → RGB (128, 128, 255) — neutral flat normal
   - Surfaces angled toward the viewer → shift B channel higher
   - Edges catching side light → shift R channel (left/right) or G (up/down)
4. Export as `tilename_normal.png` alongside `tilename.png`
5. In Godot's `TileSet` editor: assign the normal map texture to the tile

### For characters:
- Normal maps on characters are lower priority than terrain
- Focus first on: Roland's armor, cave stone tiles, dungeon wall tiles
- Characters can be added post-launch if needed — the tile normals matter more for visual quality

### Godot import settings for normal maps:
- Normal map textures must be imported as **Normal Map** type (not Default)
- In the Import panel: change `Texture Type` to `Normal Map`
- Godot will automatically apply the correct sRGB correction

---

## Folder Structure

```
/assets/
  sprites/
    player/
      roland_spritesheet.png
      roland_spritesheet_normal.png
    npcs/
      henrietta_spritesheet.png
    enemies/
      ashfallen_spritesheet.png
  portraits/
    henrietta_placeholder.svg
    (64×80 px per portrait)
  tilesets/
    cave/
      cave_walls.png
      cave_walls_normal.png
      cave_floor.png
      cave_floor_normal.png
    aldenholt/
      cobblestone.png
      stone_walls.png
      ...
  backgrounds/
    aldenholt_sky.png        ← hand-painted, not tiled
    cave_depth.png
  audio/
    music/
    sfx/
```

---

## AnimationTree Setup

`AnimationTree` (not `AnimatedSprite2D`) is the correct tool for character movement animations. It handles blending between walk directions and transition states.

### Per-character setup in Godot:
1. Add `AnimationPlayer` to the character root node
2. Create animations named `walk_down`, `walk_up`, `walk_left`, `walk_right`, `idle_down`, `idle_up`, etc.
3. Add `AnimationTree` node alongside `AnimationPlayer`
4. Set `AnimationTree.anim_player` to point at your `AnimationPlayer`
5. Create a `BlendSpace2D` in the AnimationTree:
   - X axis: horizontal movement (-1 = left, +1 = right)
   - Y axis: vertical movement (-1 = up, +1 = down)
   - Place walk animations at the 4 cardinal positions
6. Drive the blend position from Player.gd:

```gdscript
# In Player.gd _physics_process():
var dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
if dir != Vector2.ZERO:
    $AnimationTree.set("parameters/BlendSpace2D/blend_position", dir)
    $AnimationTree["parameters/BlendSpace2D/blend_position"] = dir
```

---

## Aseprite Export Workflow (Per Asset)

### Single sprite export:
1. File → Export Sprite Sheet
2. Type: **Horizontal Strip** (for Godot SpriteFrames) or **By Tag** (one file per animation)
3. Output: `assets/sprites/[category]/[name].png`
4. Check "Trim Sprite" = OFF (keep canvas size consistent)

### Tileset export:
1. Each tile is a separate Aseprite file (or tiles organized in one sheet)
2. Export as PNG at 1× scale (no upscaling in Aseprite — Godot handles display scaling)
3. Import into Godot → TileSet editor → New TileSet → add the texture → auto-slice at 32×32

### Background export:
1. Hand-painted in Aseprite at scene dimensions (320×180 or multiples)
2. Export as `assets/backgrounds/[scene_name].png`
3. Add to scene as `Sprite2D` or `TextureRect` on a background layer (below TileMap)

---

## Milestone 5 (Art Pass) — Build Order

When ready to start art:

1. **Cave tiles** — floor + walls (2 tiles each = 4 files)
2. **Roland walk cycle** — down direction only first (prove the pipeline)
3. **Roland all directions** — complete the 4-direction set
4. **Cave normal maps** — floor and wall tiles
5. **Aldenholt cobblestone** — first outdoor tileset
6. **Henrietta NPC** — first non-player character
7. **Combat sprites** — Ashfallen enemy, attack frames
8. Portraits, backgrounds, remaining NPCs in story order

Do not build art for locations that appear later in the game before locations that appear earlier. Build Act I locations first, in the order the player visits them.

---

## What NOT to do

- Do not upscale sprites in Aseprite — export at native resolution
- Do not use bilinear filtering in Godot — keep `default_texture_filter=0` (Nearest)
- Do not create character sprites wider than 32px or taller than 64px for normal NPCs
- Do not ship AI-generated backgrounds without hand-painting over them — the pixel art style requires consistent noise and color decisions that raw AI generation won't match
- Do not animate Mordvar or the Ashlord until Game Three — see `design/ART_DIRECTION.md`
