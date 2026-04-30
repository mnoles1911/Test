# Art Pipeline — Mira-Thal: Game One
## Voxel + low-poly 3D workflow reference

> This document covers HOW to make the art. For WHAT it should look like, see `design/ART_DIRECTION.md`. For the full technical migration plan, see `design/3D_VOXEL_MIGRATION.md`.

---

## Confirmed Approach

**3D voxel in Godot 4.3.**

- **Terrain and caves**: Zylann's Voxel Tools plugin (`godot_voxel`) — smooth terrain via Transvoxel, blocky structures via Cubes mesher
- **Props and buildings**: MagicaVoxel (free) → export `.glb` → Godot `MeshInstance3D`
- **Characters**: Option A — billboard sprites (Aseprite + `Sprite3D`), or Option B — low-poly Blender models (`.glb` + `AnimationPlayer`)
- **Lighting**: real 3D — `OmniLight3D`, `DirectionalLight3D`, `WorldEnvironment` with SSAO and fog

---

## Tools

| Tool | Role | Cost |
|---|---|---|
| **MagicaVoxel** | Props, buildings, dungeon tiles | Free |
| **Blender** | Character models, rigging, animation | Free |
| **Aseprite** | Billboard sprite sheets (characters, Option A), portrait art | ~$20 |
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

### Scene setup for terrain:
```
World3D (Node3D)
├── VoxelTerrain          ← the terrain node
│   └── VoxelGeneratorScript  ← GDScript that defines the terrain shape
├── Player3D (instance)
├── OmniLight3D (campfire)
└── WorldEnvironment
```

### Simple terrain generator (starting point):

```gdscript
# CaveGenerator.gd — attach to VoxelTerrain as its generator
extends VoxelGeneratorScript

func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
    var size: int = out_buffer.get_size_x()
    for z in range(size):
        for x in range(size):
            for y in range(size):
                var wy: int = origin_in_voxels.y + y
                # Floor at y=0, ceiling at y=12
                if wy <= 0:
                    out_buffer.set_voxel(1, x, y, z, 0)  # solid rock
                elif wy >= 12:
                    out_buffer.set_voxel(1, x, y, z, 0)  # ceiling
                else:
                    out_buffer.set_voxel(0, x, y, z, 0)  # air
```

### Mesher choice per context:
- `VoxelMesherTransvoxel` — smooth terrain (outdoor hillsides, cave floors, cliff edges)
- `VoxelMesherCubes` — blocky structures (buildings, dungeon walls, constructed architecture)

Use Cubes mesher for anything that was built by hands (stone walls, towers). Use Transvoxel for anything that was shaped by nature (hillsides, cave ceilings, riverbeds).

---

## Tool 3: Characters — Two Options

### Option A: Billboard Sprites (Faster, Start Here)

Draw characters in Aseprite exactly as before (pixel art, 32×48 px per frame, 4 directions). Display as `Sprite3D` in Godot with `billboard = BILLBOARD_ENABLED` so they always face the camera.

This is the approach used by many voxel indie games to avoid the cost of 3D character modeling.

**Aseprite workflow:** Same as before — walk cycle, idle, interact, 4 directions.
**Godot setup:**
```gdscript
# In Player3D.tscn: add Sprite3D as child of CharacterBody3D
var sprite: Sprite3D = $Sprite3D
sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
sprite.texture = preload("res://assets/sprites/roland_spritesheet.png")
# Drive frame changes from animation state
```

**When to transition to Option B:** When Act I is content-complete and the game needs combat animations, companion positioning in 3D space, and cutscene staging.

### Option B: Low-Poly Blender Models

**Target spec:**
- 200–500 triangles per character (low-poly, flat-shaded)
- Rigged skeleton: ~20–30 bones (spine, limbs, head)
- Animations: walk, idle, attack, block, react (one .glb per character with all animations as tracks)
- No texture maps — use vertex colors or a single 64×64 color palette texture

**Blender export workflow:**
1. Model, rig, and animate in Blender
2. File → Export → `.glb` (GLTF Binary)
3. Export settings: include animations, include mesh data, apply modifiers
4. Place in `res://assets/models/`
5. In Godot: drag `.glb` → `AnimationPlayer` auto-populates from Blender animation tracks
6. Add `AnimationTree` + `BlendSpace2D` (same logic as 2D workflow, driven by CharacterBody3D velocity)

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
  models/               ← Blender character exports (.glb)
    roland.glb
    henrietta.glb
    ashfallen.glb
  sprites/              ← If using billboard Option A
    roland_spritesheet.png
    henrietta_spritesheet.png
  portraits/            ← Dialogue UI art (256×320 px painted)
    henrietta.png
    dame_calla.png
  audio/
    music/
    sfx/
```

---

## Milestone 5 Art Build Order (3D)

Build in this order — prove the pipeline before committing to volume:

1. **Campfire prop** in MagicaVoxel (first asset — small, tests the full export pipeline)
2. **Cave wall section** — one reusable wall tile
3. **Roland billboard sprite** — walk cycle down only (proves character pipeline)
4. **Roland all 4 directions** — complete the billboard set
5. **Cave ceiling and floor tiles** — complete the cave scene
6. **Archway** — first architectural element
7. **Iron Chalice chapel interior** — Act I critical path location
8. **Henrietta billboard sprite** — first NPC
9. **Ashfallen enemy sprite/model** — first enemy
10. **Aldenholt exteriors** — cobblestone street, market stall, Archive facade

Do not build Act II or III locations until Act I is content-complete.

---

## What NOT to Do

- **Do not use CSGBox/CSGMesh for anything permanent** — Godot CSG nodes are for prototype blocking only, not production scenes
- **Do not ship raw AI-generated 3D models** — they require significant cleanup for game use; use AI for reference and concept only
- **Do not animate Mordvar or the Ashlord** until Game Three — per `design/ART_DIRECTION.md`
- **Do not use 1-meter voxel blocks** — the Minecraft scale is wrong for this game; stay at 8 voxels per meter
- **Do not skip LOD on terrain** — Zylann's VoxelTerrain has built-in LOD; always configure it or performance will suffer at zone scale
