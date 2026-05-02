# Art Pipeline — Mira-Thal: Game One
## Voxel + low-poly 3D workflow reference

> This document covers HOW to make the art. For WHAT it should look like, see `design/ART_DIRECTION.md`. For the full technical migration plan, see `design/3D_VOXEL_MIGRATION.md`.

---

## Confirmed Approach

**3D voxel open world in Godot 4.3.**

- **Terrain**: Zylann's Voxel Tools plugin (`godot_voxel`) — `VoxelLodTerrain` with `VoxelMesherCubes` (blocky stepped terrain, LOD streaming). Generated from a 3D density field in `WorldGenerator.gd` — not a heightmap, so caves and overhangs work. Static, not editable by player.
- **Buildings and structures**: `VoxelMesherCubes` mesher for constructed architecture; MagicaVoxel (free) → export `.glb` → Godot `MeshInstance3D` for props
- **Characters**: Low-poly Blender models from Act I onward — `.glb` exports, 200–500 tris for named characters, rigged with `AnimationPlayer`. No billboard sprites for characters.
- **Lighting**: real 3D — `OmniLight3D`, `DirectionalLight3D`, `WorldEnvironment` with SSAO and fog

---

## Tools

| Tool | Role | Cost |
|---|---|---|
| **MagicaVoxel** | Props, buildings, dungeon tiles | Free |
| **Blender** | Character models, rigging, animation | Free |
| **Aseprite** | Portrait art (dialogue UI, 256×320 px) | ~$20 |
| **Zylann's Voxel Tools** | Godot 4 voxel terrain plugin | Free / open source |
| **Godot 4.3** | Scene assembly, rendering, logic | Free |
| AI-assisted generation | Concept reference, texture starting points (always hand-edit) | Variable |

---

## Tool 1: MagicaVoxel — Props and Buildings

MagicaVoxel is the standard voxel art tool. It is free, intuitive, and exports directly to formats Godot reads.

### What to build in MagicaVoxel:
- Cave wall sections (2×2×3 voxel tiles)
- Archways, doorframes
- Campfire prop
- Furniture (chairs, tables, beds)
- Storage (crates, barrels, chests)
- Building facades (Iron Chalice chapel exterior, Archive entrance)
- Dungeon set-pieces (stone altars, columns, sarcophagi)
- Crown pieces (7 distinct objects, each with a visual identity)

### MagicaVoxel export workflow:
1. Model in MagicaVoxel at the chosen voxel scale (1 voxel = ~0.125m in Godot)
2. File → Export → `.glb` (preferred) or `.obj`
3. Export settings: **Enable vertex colors** (no texture atlas needed for solid voxel art)
4. Place in `res://assets/voxel/` folder with descriptive name
5. In Godot: drag `.glb` into scene → automatically becomes `MeshInstance3D`
6. Set material to `BaseMaterial3D` with `vertex_color_use_as_albedo = true`

### Voxel block size convention:
- All props use **1 voxel = 0.125 meters** (8 voxels per meter)
- A human-height doorway = ~16 voxels tall
- A standard wall section = 8 voxels wide × 12 voxels tall
- This matches the terrain voxel scale so props align to terrain edges

---

## Tool 2: Zylann's Voxel Tools — Terrain

**Plugin repo:** https://github.com/Voxel-And-Module-Tools/godot_voxel

### Installation in Godot 4.3:
1. Download from the repo (or Godot Asset Library if available)
2. Copy `addons/zylann.voxel` into `res://addons/`
3. Project → Project Settings → Plugins → Enable "Voxel Tools"
4. Restart Godot editor

### Scene setup for open world terrain:
```
World3D (Node3D)
├── VoxelLodTerrain       ← streaming open world terrain with LOD
│   └── VoxelGeneratorGraph  ← node-graph generator wired in the Godot editor (NOT a GDScript subclass)
├── EntityStreamer         ← node that loads/unloads world entities by player proximity
├── Player3D (instance)
├── DirectionalLight3D
└── WorldEnvironment
```

### WorldGenerator — VoxelGeneratorGraph (Godot editor node, not GDScript):

**`VoxelGeneratorGraph`** is a built-in node in Zylann's plugin. You wire it visually in the
Godot editor — it compiles to a SIMD/compute shader and runs significantly faster than a
GDScript subclass could. **Do not write a `VoxelGeneratorScript` GDScript subclass for this.**

**Gaea → Godot terrain pipeline:**
1. Author Mira's terrain in **Gaea** (free tier sufficient) — sculpt the Spine ridge, Greatwood, Aldwater valley, settlement flat zones
2. Export as a **32-bit single-channel EXR heightmap** (Gaea: Output node → Format: EXR 32-bit)
3. Export a **biome splatmap** (RGB channels: R = grassland, G = forest, B = rock/ash) as a separate EXR
4. In Godot, import both files with **"Keep as Image"** import mode (not as textures)
5. Wire them into the VoxelGeneratorGraph:
   - Heightmap EXR → `Image` input node → `HeightmapShape` → drives the base SDF surface
   - 3D `FastNoiseLite` node → `SdfSmoothSubtract` → carves caves (Y below surface only)
   - Biome splatmap → `Image` input node → `CHANNEL_INDICES` → drives material painting on surface voxels
6. Assign one `VoxelBlockyLibrary` with tile types matching splatmap channels (grass, forest floor, rock, ash)

**Why VoxelGeneratorGraph over GDScript:**
- Compiles to native compute shader — orders of magnitude faster than GDScript loops
- Supports authored heightmap input via `Image` nodes — Gaea geography exactly as sculpted
- Visual node graph is inspectable and editable without code
- 3D cave noise layer runs in parallel, not in a GDScript for-loop

**3D density field behavior:**
Positive density = solid voxel; negative = air. The surface is where density crosses zero.
The Gaea heightmap drives the broad terrain shape; a 3D FastNoiseLite node adds cave voids
via `SdfSmoothSubtract` when the voxel is well below the surface. This enables:
- Overhangs (cliff lips where the heightmap surface curves back under itself)
- Cave ceilings (3D noise carves upward into solid rock)
- Arch formations (rare but possible without any special casing)

### VoxelLodTerrain configuration:
- Set `lod_count` to 6–8 levels for 12km world extent
- Set LOD0 distance to ~60m (matches third-person camera view range)
- Use **`VoxelMesherCubes`** — produces blocky stepped terrain consistent with MagicaVoxel buildings
- Use separate `MeshInstance3D` nodes (MagicaVoxel exports) for all buildings — do NOT carve buildings into the terrain

### Mesher choice:
- `VoxelMesherCubes` — all terrain (stepped, blocky faces; same visual language as MagicaVoxel props)
- MagicaVoxel `.glb` exports placed as `MeshInstance3D` on top of terrain for all buildings and props

Do not use `VoxelMesherTransvoxel` — it smooths geometry, which would eliminate the blocky aesthetic.

---

## Tool 3: Characters — Low-Poly Blender Models (Act I onward)

Billboard sprites are not used for characters. The third-person over-shoulder camera is close enough to Roland that a flat sprite's 2D nature becomes apparent. All characters use low-poly Blender models from Act I.

**Target spec — named characters (Roland, Henrietta, Tomlin, companions, major NPCs):**
- 200–500 triangles (low-poly, flat-shaded)
- Rigged skeleton: ~20–30 bones (spine, limbs, head)
- Animations per character: idle, walk, run, attack swing, dodge roll, react/flinch, death
- No texture maps — vertex colors or a single 64×64 color palette texture

**Target spec — background/crowd NPCs:**
- Voxel-block humanoids from MagicaVoxel (8×16 voxels tall) exported as rigid `.glb`
- No rigging required — these are Tier 0 background figures that move between waypoints
- Same pipeline as props

**Blender export workflow:**
1. Model, rig, and animate in Blender
2. File → Export → `.glb` (GLTF Binary)
3. Export settings: include animations, include mesh data, apply modifiers
4. Place in `res://assets/models/`
5. In Godot: drag `.glb` → `AnimationPlayer` auto-populates from Blender animation tracks
6. Add `AnimationTree` + `BlendSpace1D` or `BlendSpace2D` driven by `CharacterBody3D` velocity

**Act I minimum animation set for Roland:**
- `idle` — weight shift, one hand near belt
- `walk` — moderate pace
- `run` — combat/sprint pace
- `attack_light` — fast swing
- `attack_heavy` — slower, wider arc
- `dodge` — directional roll
- `react` — flinch/hit reaction
- `death` — collapse

These 8 clips are sufficient to ship Act I. Combat depth animations (parry, charged attack, finisher) can be added before Act II.

---

## Folder Structure

```
/assets/
  voxel/                ← MagicaVoxel exports (.glb)
    props/
      campfire.glb
      archway.glb
      chest.glb
    buildings/
      iron_chalice_exterior.glb
      archive_entrance.glb
    dungeon/
      cave_wall_section.glb
      stone_column.glb
    crown_pieces/
      iron_pommel.glb
      bronze_ring.glb
      [...]
  models/               ← Blender character exports (.glb) — all characters
    roland.glb
    henrietta.glb
    tomlin.glb
    ashfallen.glb
  portraits/            ← Dialogue UI art (256×320 px painted) — unchanged
    henrietta.png
    dame_calla.png
  audio/
    music/
    sfx/
```

Note: `/assets/sprites/` is no longer needed for character art. Portraits remain the primary 2D character representation and live in `/assets/portraits/`.

---

## Milestone 5 Art Build Order (3D)

Build in this order — prove each pipeline stage before expanding to volume:

1. **Campfire prop** in MagicaVoxel (first asset — small, tests the full prop export pipeline)
2. **Cave wall tile** — one reusable modular wall section
3. **Roland low-poly Blender model** — base mesh only, no rig yet (proves character import pipeline)
4. **Roland rig + idle animation** — skeleton and one-clip AnimationPlayer in Godot
5. **Roland walk + run cycles** — unblocks all scene movement testing
6. **Cave floor and ceiling tiles** — complete the placeholder scene
7. **Archway / doorframe** — first architectural element
8. **Roland attack + dodge animations** — unblocks combat testing
9. **First enemy model** (Ashfallen soldier) — rig + idle + attack animations
10. **Henrietta NPC model** — first named NPC, rig + idle
11. **Iron Chalice chapel interior** — first Act I location with real assets
12. **Aldenholt exteriors** — cobblestone street, market stall, Archive facade

Do not build Act II or III locations until Act I is content-complete.

---

## What NOT to Do

- **Do not use CSGBox/CSGMesh for anything permanent** — Godot CSG nodes are for prototype blocking only, not production scenes
- **Do not ship raw AI-generated 3D models** — they require significant cleanup for game use; use AI for reference and concept only
- **Do not animate Mordvar or the Ashlord** until Game Three — per `design/ART_DIRECTION.md`
- **Do not use 1-meter voxel blocks** — the Minecraft scale is wrong for this game; stay at 8 voxels per meter
- **Do not skip LOD on terrain** — Zylann's VoxelTerrain has built-in LOD; always configure it or performance will suffer at zone scale
