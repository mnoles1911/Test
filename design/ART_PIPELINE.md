# Art Pipeline — Mira-Thal: Game One
## Voxel + low-poly 3D workflow reference

> This document covers HOW to make the art. For WHAT it should look like, see `design/ART_DIRECTION.md`. For the full technical migration plan, see `design/3D_VOXEL_MIGRATION.md`.

---

## Confirmed Approach

**3D voxel open world in Godot 4.6.2.**

- **Terrain**: Zylann's Voxel Tools plugin (`godot_voxel`) — `VoxelLodTerrain` with `VoxelMesherCubes` (blocky stepped terrain, LOD streaming). The procedural `VoxelGeneratorGraph` (Gaea EXR + 3D cave noise) produces the **baseline only**. Player edits live as deltas in `VoxelStreamSQLite` per save slot. **Editable / destructible by default** — non-destructible regions are the exception, declared via `NoEditZone` Area3D volumes. Canonical spec: `design/3D_VOXEL_MIGRATION.md` → "Destructible Terrain".
- **Buildings and structures**: MagicaVoxel (free) → export `.glb` → Godot `MeshInstance3D` for all narratively load-bearing props (settlements, dungeon entrances, lore landmarks). These sit on top of the voxel surface, not carved into it, and are wrapped in NoEditZones.
- **Player-built structures**: hybrid — schematic props (crafted wall section / door / roof / fence — placed as `MeshInstance3D` with metadata) for the bulk, plus per-voxel placement for detailing. Both persist in the save (`placed_schematics.json` for schematics; `voxel_deltas.sqlite` for per-voxel edits).
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
| **Godot 4.6.2** | Scene assembly, rendering, logic | Free |
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
- **Player-placeable building schematics** (wall section, door panel, roof tile, window frame, fence segment, gate). One `.glb` per schematic, plus a `.tres` `SchematicData` file in `assets/voxel/schematics/` listing material cost, weight, snap behavior, and category for the player crafting menu

### MagicaVoxel export workflow:
1. Model in MagicaVoxel at the chosen voxel scale (1 voxel = ~0.125m in Godot)
2. File → Export → `.glb` (preferred) or `.obj`
3. Export settings: **Enable vertex colors** (no texture atlas needed for solid voxel art)
4. Place in `res://assets/voxel/` folder with descriptive name
5. In Godot: drag `.glb` into scene → automatically becomes `MeshInstance3D`
6. Set material to `BaseMaterial3D` with `vertex_color_use_as_albedo = true`

### Voxel block size convention:
- All props use **1 voxel ≈ 0.167 metres** (6 voxels per meter — locked 2026-05-03)
- A 1.8 m human-height doorway = ~11 voxels tall (or 12 for headroom)
- A standard wall section ≈ 6 voxels wide × 12 voxels tall
- This matches the terrain voxel scale so props align to terrain edges

---

## Tool 2: Zylann's Voxel Tools — Terrain

**Plugin repo:** https://github.com/Zylann/godot_voxel
**Official docs:** https://voxel-tools.readthedocs.io/en/latest/getting_the_module/

This plugin is **NOT in Godot's Asset Library** — it ships native (C++) binaries that the Asset Library doesn't distribute. Two editions exist; we use **GDExtension** because it's a drop-in addon for the standard Godot editor (no custom engine build needed).

### Installation in Godot 4.6.2 (GDExtension edition):
1. Go to https://github.com/Zylann/godot_voxel/releases and download the latest release asset labeled "GDExtension" matching your platform (Windows / macOS / Linux). Requires Godot 4.4.1+; we're on 4.6.2 stable, so any current release works.
2. Extract the ZIP — you should get a folder named `zylann.voxel`.
3. Move that folder into your project's `addons/` directory so the path becomes `addons/zylann.voxel/`.
4. Restart Godot. The plugin auto-detects on launch.
5. Project Settings → Plugins → confirm "Voxel Tools" is enabled. (Some releases enable automatically; others require this manual toggle.)
6. Verify by adding a `VoxelLodTerrain` node to a test scene — if the node type appears in the Add Node dialog, the plugin is live.

**Do NOT use the Module edition** — that's a fully recompiled Godot editor that replaces your Godot install. Heavier setup, same runtime features as GDExtension. Stick with GDExtension.

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

### WorldGenerator — current implementation vs. v1 plan

> **CURRENT (2026-05-03):** The active baseline generator is `CubicHeightmapGenerator`, a GDScript `VoxelGeneratorScript` subclass at `scripts/CubicHeightmapGenerator.gd`. It writes `CHANNEL_COLOR` per voxel via macro + mid + detail noise layers + per-voxel colour jitter. Live-tunable in the Inspector via `@export_range` sliders + `Preset` enum. This was a deliberate divergence from the original Gaea + VoxelGeneratorGraph plan — quicker to iterate, doesn't require external Gaea authoring, and works directly with `VoxelMesherCubes`. The Gaea pipeline below remains the v1 Mira plan (authored geography for the 12 km × 10 km playable map) and is the document of record for that work. Current generator is "good enough" for the destructible-voxel core to land.

**Original v1 Gaea pipeline (deferred — return for v1 Mira authoring):**

`VoxelGeneratorGraph` is a built-in node in Zylann's plugin you wire visually in the
Godot editor — it compiles to a SIMD/compute shader and runs significantly faster than a
GDScript subclass could.

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
- Set mandatory LOD0 radius to 32m (collision + interaction floor — never below this)
- Default edit-detail radius: 64m (player-configurable 32m–256m via Settings — see `design/ACCESSIBILITY_AND_SETTINGS.md`)
- Default view distance: 600m (player-configurable 200m–2km)
- Use **`VoxelMesherCubes`** — produces blocky stepped terrain consistent with MagicaVoxel buildings
- Attach **`VoxelStreamSQLite`** to the terrain — edit deltas persist to `user://saves/slot_{N}/voxel_deltas.sqlite`
- Use separate `MeshInstance3D` nodes (MagicaVoxel exports) for all narratively load-bearing buildings — do NOT carve buildings into the terrain. These props sit inside `NoEditZone` Area3D volumes that buffer the structure ~50–100m in all directions.

### Edit rendering — LOD0-clamped + LOD-baked at distance

Edited chunks within the player's edit-detail radius render at LOD0 (full block precision). When an edited chunk leaves that radius, `VoxelEditManager` generates a one-time LOD1/LOD2 mesh from the edited voxel state and caches it under `user://saves/slot_{N}/mesh_cache/`. Subsequent renders at distance use the cached mesh, so player-built structures stay visible (chunky) from far away. Cache is regeneratable; excluded from save backups.

### NoEditZones — protected geometry

Major narrative structures and settlements are wrapped in Area3D volumes added to the `no_edit_zone` group. The `VoxelEditManager` autoload queries `NoEditZoneRegistry` before any `VoxelTool.do_*` write. Writes inside a NoEditZone are silently rejected. When authoring a settlement scene, drop the building props (MagicaVoxel `.glb`) on the surface and parent them under a single `NoEditZone` Area3D with a buffer of 50–100m. Place a Roland bark trigger `"This place doesn't yield to me."` for player attempts.

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
- **Do not use 1-meter voxel blocks** — the Minecraft scale is wrong for this game; stay at the locked 6 voxels per meter
- **Do not skip LOD on terrain** — Zylann's VoxelTerrain has built-in LOD; always configure it or performance will suffer at zone scale
