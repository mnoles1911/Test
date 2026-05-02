# Technology Stack — Game One

Reference for every tool, plugin, and software in the pipeline. Covers what each tool does, why it was chosen, and how it connects to everything else.

---

## Engine

| | |
|---|---|
| **Engine** | Godot 4.3 |
| **Language** | GDScript only — no C#, no C++ GDExtension |
| **Target platforms** | Windows, macOS, Linux (Steam) |
| **Render** | Forward+ (required for SDFGI, SSAO, volumetric fog) |
| **Physics** | Godot built-in 3D physics (Jolt backend optional for performance) |

GDScript is the only language. No exceptions. The project prioritizes readable, maintainable code over performance-first solutions. Godot's GDScript runs fast enough for a single-player narrative RPG at this scale.

---

## Voxel Terrain

### Zylann's Voxel Tools (`godot_voxel`)

| | |
|---|---|
| **Plugin** | `godot_voxel` by Zylann |
| **Source** | https://github.com/Voxel-And-Module-Tools/godot_voxel |
| **Godot 4 compatible** | Yes |
| **Cost** | Free, open source (MIT) |

The only voxel terrain system for Godot 4 with production-ready LOD streaming at open-world scale. Powers the entire outdoor world.

**Nodes used:**

| Node | Role |
|---|---|
| `VoxelLodTerrain` | Streaming open-world terrain with automatic LOD (6–8 levels) |
| `VoxelGeneratorGraph` | Visual node-graph terrain generator (compiles to compute shader) |
| `VoxelMesherCubes` | Blocky stepped meshing — hard block faces, no smoothing |
| `VoxelViewer` | One per player — tells the terrain which area to stream |
| `VoxelInstancer` | Scatter foliage and props (trees, rocks, grass) across terrain |

**What is NOT used:**
- `VoxelMesherTransvoxel` — smooths geometry; eliminates the blocky aesthetic. Do not use.
- `VoxelTerrain` (non-LOD variant) — for small finite worlds only; not suitable for 12km extent
- `VoxelGeneratorScript` GDScript subclass — too slow; use VoxelGeneratorGraph instead

**Voxel scale:** 8 voxels per meter (each block = 12.5 cm). Noticeably blocky but finer than Minecraft's 1m blocks. All assets (MagicaVoxel props, building exports) are authored at this scale.

**LOD configuration:**
- `lod_count`: 6–8 levels
- LOD0 distance: ~60m (full detail near player)
- Beyond 60m: progressively lower resolution until horizon
- `STREAMING_SYSTEM_CLIPBOX` mode: required for co-op (multiple VoxelViewers)

---

## World and Terrain Pipeline

This is the most complex part of the stack. Terrain is authored in Gaea, exported as image data, and consumed by a VoxelGeneratorGraph node in Godot.

### Step 1 — Author terrain in Gaea

**Tool:** Gaea (https://quadspinner.com/gaea) — free tier sufficient  
**What it does:** Procedural terrain sculptor. Build the Spine ridge, Greatwood depression, Aldwater valley, and settlement flat zones using Gaea's node graph.

Key Gaea nodes to use:
- `Mountain` / `Ridge` — the Spine of the World (east, ~5000–7000m x)
- `Erosion` — natural weathering on hillsides
- `Clamp` / `Flatten` — forced-flat zones at settlement coordinates (Aldenholt, Caer Brannoch, etc.)
- `Combine` — blend region masks together
- `Output` — export node; set format to **EXR 32-bit single-channel**

**Export two files from Gaea:**
1. **Heightmap** — 32-bit single-channel EXR (grayscale: 0.0 = sea level, 1.0 = max elevation)
2. **Biome splatmap** — 32-bit RGB EXR (R = grassland, G = forest/Greatwood, B = rock/ash/Ashfields)

**Resolution:** 4096×4096 minimum for a 12km world at acceptable detail. 8192×8192 ideal.

---

### Step 2 — Import into Godot

1. Place both EXR files in `res://assets/terrain/`
2. In the Godot Import dock, set both files to **"Keep as Image"** (not Texture2D — you need raw pixel access)
3. They will appear as `Image` resources, accessible in GDScript and in VoxelGeneratorGraph Image nodes

---

### Step 3 — Wire VoxelGeneratorGraph

`VoxelGeneratorGraph` is a **visual node graph** edited in the Godot editor — not a GDScript file. Add it as a child of `VoxelLodTerrain` and wire nodes together in the inspector.

**Graph structure (conceptual):**

```
[InputX] [InputZ]
     │         │
[Image Sample: heightmap.exr]   ← samples pixel at (x/world_scale, z/world_scale)
     │
[Remap: 0–1 → 0–200m]          ← scale pixel value to world height in meters
     │
[SdfPlane: y < height → solid]  ← base surface SDF
     │
     ├── [FastNoiseLite 3D]     ← cave noise layer
     │        │
     │   [SdfSmoothSubtract]    ← carves caves only where voxel is below surface
     │
[OutputSDF]                     ← final density: positive = solid, negative = air

[Image Sample: splatmap.exr]   ← reads RGB channels
[OutputType: CHANNEL_INDICES]  ← assigns voxel material ID (grass/forest/rock/ash)
```

**Key VoxelGeneratorGraph nodes:**
- `InputX`, `InputY`, `InputZ` — current voxel's world coordinates (floats)
- `Image` — samples an imported EXR `Image` resource at UV coordinates
- `Remap` — rescales the 0–1 heightmap value to actual world meters
- `SdfPlane` — converts height to a signed distance field (positive below surface)
- `FastNoiseLite` — 3D noise node; used for cave carving
- `SdfSmoothSubtract` — carves one SDF from another with smooth blend radius
- `OutputSDF` — required output; this value determines solid vs air
- `OutputType` — optional; assigns `CHANNEL_INDICES` for material variation

**Cave noise settings (starting values):**
- Frequency: 0.04–0.06 (larger caves at lower frequency)
- Threshold: cave fires only when `InputY < (surface_y - 8)` — prevents surface holes
- Use `SdfSmoothSubtract` with blend radius ~4 for smooth cave mouths

---

### Step 4 — Configure VoxelLodTerrain

In the Godot scene inspector on the `VoxelLodTerrain` node:

| Property | Value | Notes |
|---|---|---|
| `lod_count` | 7 | Good balance for 12km extent |
| `lod_distance` | 60 | LOD0 full-detail radius in meters |
| `mesher` | `VoxelMesherCubes` | Blocky stepped faces |
| `generator` | VoxelGeneratorGraph child | Assign the graph node |
| `collision_lod_count` | 3 | Physics only needs detail near player |
| `streaming_system` | `STREAMING_SYSTEM_CLIPBOX` | Required for co-op multi-viewer |

---

### Step 5 — Material Painting

`VoxelMesherCubes` reads `CHANNEL_INDICES` from the voxel buffer. Each index maps to a slot in a `VoxelBlockyLibrary`. Create one library entry per biome type:

| Index | Material | Splatmap channel |
|---|---|---|
| 0 | Grassland (green-brown) | R |
| 1 | Forest floor (dark, mossy) | G |
| 2 | Rock / cliff face (grey) | B = 0 |
| 3 | Ash / Ashfields (pale grey-white) | B = 1 |
| 4 | Underground stone (dark grey) | Below surface threshold |

Each material entry in the library is a `StandardMaterial3D` with a small hand-painted 4×4 color tile — no large textures needed at voxel scale.

---

### Step 6 — VoxelInstancer (foliage)

`VoxelInstancer` scatters `MultiMeshInstance3D` items (trees, rocks, grass tufts) across the terrain surface automatically using density maps and slope rules.

- Trees: scatter on forest-index voxels, slope < 30°
- Rocks: scatter on rock-index voxels, any slope
- Grass: scatter on grassland-index voxels, slope < 15°
- Settlement zones: no instancing (forced-flat, cleared)

Configure in the VoxelInstancer inspector — no GDScript required for basic scattering.

---

## Asset Creation Tools

### MagicaVoxel (Props and Buildings)

| | |
|---|---|
| **Tool** | MagicaVoxel (https://www.voxelmade.com/magicavoxel/) |
| **Cost** | Free |
| **Export format** | `.glb` (GLTF Binary) |
| **Use for** | Props, building facades, dungeon tiles, crown pieces, furniture |

**Workflow:** Model → Export `.glb` with vertex colors enabled → Import to Godot → `MeshInstance3D` → set `BaseMaterial3D.vertex_color_use_as_albedo = true`.

**Scale:** 1 MagicaVoxel block = 0.125m in Godot (8 voxels per meter). A human-height doorway = 16 blocks tall.

Buildings are placed as `MeshInstance3D` nodes on the terrain surface — they are NOT carved into the voxel data.

---

### Blender (Characters)

| | |
|---|---|
| **Tool** | Blender (https://www.blender.org/) |
| **Cost** | Free |
| **Export format** | `.glb` (GLTF Binary) with embedded animations |
| **Use for** | All named characters and enemies (Roland, NPCs, Ashfallen, companions) |

**Target spec:** 200–500 triangles, flat-shaded, vertex colors or single 64×64 palette texture, ~25-bone rig.

**Workflow:** Model → Rig → Animate → Export `.glb` → Import to Godot → `AnimationPlayer` auto-populates → add `AnimationTree` + `BlendSpace1D` for movement blending.

**Billboard sprites are not used for characters.** The third-person camera is too close for flat sprites to read correctly.

---

### Aseprite (Portraits)

| | |
|---|---|
| **Tool** | Aseprite (https://www.aseprite.org/) |
| **Cost** | ~$20 |
| **Use for** | Character portrait art for Dialogic dialogue UI (256×320 px) |

Portraits are the only remaining 2D art. They appear in the Dialogic conversation UI as character expressions and are unchanged by the 3D pivot.

---

## Dialogue

### Dialogic 2

| | |
|---|---|
| **Plugin** | Dialogic 2 |
| **Source** | Godot Asset Library |
| **Cost** | Free |
| **Use for** | All narrative dialogue, branching timelines, character portraits, flags |

All story dialogue, NPC conversations (Tier 2 and Tier 3), and quest branches are authored in Dialogic `.dtl` timeline files. Dialogic is the unchanged core of the narrative system — the 3D pivot does not affect it.

**Integration points:**
- `DialogueTrigger3D.gd` — `Area3D` script; press E → `Dialogic.start("timeline_name")`
- `CameraRig.gd` — tweens `SpringArm3D.spring_length` to `dialogue_arm_length` on Dialogic open, reverts on close
- `GameState.gd` — Dialogic conditions read flags; Dialogic `Set Variable` nodes write flags

---

## Audio and TTS

### ElevenLabs (Voice Rendering)

| | |
|---|---|
| **Service** | ElevenLabs (https://elevenlabs.io/) |
| **Cost** | Subscription (credits per character rendered) |
| **Use for** | Roland's observation lines; NPC voiced dialogue for Tier 2+ conversations |

**Pipeline:** Write dialogue draft → `strip_draft.py` extracts spoken lines → `render_bulk.py` sends to ElevenLabs API → `.ogg` files output to `assets/audio/dialogue/{timeline_name}/` → `manifest.json` maps line IDs to file paths → Dialogic plays audio via timeline.

Voice IDs and per-character configuration: `dialogue/CHARACTER_VOICES.md`  
Phonetic respellings for lore proper nouns: `dialogue/PRONUNCIATION.md` (check before every TTS run)

**Pipeline scripts (run from repo root):**
```bash
python3 tools/strip_draft.py dialogue/drafts/act1_scene_sorting_room.md
ELEVENLABS_API_KEY=<key> python3 tools/render_bulk.py dialogue/scripts/act1_scene_sorting_room.txt
```

---

## Water

### Boujie Water Shader

| | |
|---|---|
| **Asset** | Boujie Water Shader (Godot Asset Library #2070) |
| **Godot 4 compatible** | Yes (4.1+) |
| **Cost** | Free |
| **Use for** | All water surfaces — lakes, rivers, coastal inlets |

A LOD ring mesh shader — efficient single draw call even at large scale. Handles animated surface, reflections, and shoreline foam. Applied as a `ShaderMaterial` on a `MeshInstance3D` water surface node.

Physics detection (swimming, river currents) is handled separately via `Area3D` volumes — the visual mesh does not drive physics. See `design/SWIMMING_AND_WATER.md`.

---

## Multiplayer (Co-Op — Phase 10-3D onward)

### Godot ENet

Built-in Godot 4 transport layer (`ENetMultiplayerPeer`). Client-server model: host = peer_id 1, one guest client. `@rpc` decorators for state sync. `MultiplayerSynchronizer` for player and NPC position/animation replication at ~20 Hz.

Terrain sync is free — `VoxelGeneratorGraph` generates deterministically on every client from the same parameters. Nothing to transmit.

### Netfox

| | |
|---|---|
| **Library** | Netfox (https://github.com/foxssake/netfox) |
| **Language** | GDScript |
| **License** | MIT |
| **Cost** | Free |
| **Use for** | Combat rollback netcode (parry timing, hit detection) only |

Standard position sync tolerates moderate latency fine. Parry timing windows (~150–200ms) do not — a missed parry due to network lag feels wrong. Netfox provides input rollback so parry detection is correct regardless of round-trip latency.

Not added until Phase 10-3D. Single-player builds do not include it.

Full co-op architecture: `design/MULTIPLAYER.md`.

---

## Pipeline Tools

### strip_draft.py

Extracts spoken lines from a prose dialogue draft into a clean TTS script. Deterministic — same input always produces same output.

```bash
python3 tools/strip_draft.py dialogue/drafts/act1_scene_sorting_room.md
# writes → dialogue/scripts/act1_scene_sorting_room.txt
```

### render_bulk.py

Sends a TTS script to ElevenLabs and renders each line to `.ogg`. Idempotent — reruns skip lines whose text hash is unchanged. Shows cost estimate before any network call.

```bash
ELEVENLABS_API_KEY=<key> python3 tools/render_bulk.py dialogue/scripts/act1_scene_sorting_room.txt
# writes → assets/audio/dialogue/act1_scene_sorting_room/*.ogg + manifest.json
```

---

## Autoloads (Godot Singletons)

| Autoload | Status | Role |
|---|---|---|
| `GameState.gd` | ✅ Active | All persistent flag and save data |
| `TransitionManager.gd` | ✅ Active | Scene loading, fade transitions, go_back() |
| `SaveNotification.gd` | ✅ Active | Toast overlay for save events |
| `PauseMenu.gd` | ✅ Active | ESC pause overlay |
| `DebugOverlay.gd` | ✅ Active | F1 debug info overlay |
| `FlagScheduler.gd` | ✅ Active | Timed/deferred flag events |
| `InventoryManager.gd` | ✅ Active | Items, equipment, crafting recipes |
| `JournalUI.gd` | ✅ Active | 6-tab overlay (Quests/Map/Items/Crafting/Codex/Skills) |
| `HUDOverlay.gd` | ✅ Active | HP + endurance bars, status label |
| `Settings.gd` | ✅ Active | Display, audio, controls, accessibility settings |
| `MainMenu.gd` | ✅ Active | Main menu UI |
| `Dialogic` | ✅ Active | Dialogue system |
| `BarkManager.gd` | ⚠️ Built, not registered | Spatial bark audio + line selection |
| `WorldClock.gd` | ⚠️ Built, not registered | In-game time, schedule dispatch |
| `EntityRegistry.gd` | 🔲 Not yet built | Spatial entity dictionary by chunk |
| `EntityStreamer.gd` | 🔲 Not yet built | Loads/unloads world entities by proximity |
| `WorldGenerator` | 🔲 Not yet built | VoxelGeneratorGraph node (editor, not code) |
| `FactionManager.gd` | 🔲 Not yet built | Faction disposition wrapper |
| `QuestManager.gd` | 🔲 Not yet built | Quest flag advancement |
| `WeatherManager.gd` | 🔲 Not yet built | Weather state and WorldEnvironment tweening |
| `CompanionManager.gd` | 🔲 Not yet built | Companion HP, state, save serialization |

---

## File Structure Reference

```
/scenes/
  World3D.tscn            ← open world (VoxelLodTerrain + EntityStreamer + Player3D)
  Player3D.tscn           ← character + SpringArm3D camera rig
  interiors/              ← discrete scenes for buildings and dungeon floors
  ui/                     ← Journal.tscn and other UI scenes

/scripts/                 ← all .gd files

/assets/
  terrain/                ← Gaea EXR exports (heightmap + splatmap)
  voxel/                  ← MagicaVoxel exports (.glb): props, buildings, dungeon, crown pieces
  models/                 ← Blender character exports (.glb)
  portraits/              ← Dialogic portrait art (256×320 px .png)
  audio/
    music/
    sfx/
    dialogue/             ← ElevenLabs rendered .ogg + manifest.json per timeline
  npcs/                   ← NPCData .tres resource files (one per character)

/dialogue/
  drafts/                 ← human-readable prose drafts
  scripts/                ← TTS-ready line scripts (output of strip_draft.py)
  CHARACTER_VOICES.md     ← ElevenLabs voice IDs per character
  PRONUNCIATION.md        ← phonetic respellings for lore proper nouns
  STYLE.md                ← line writing rules, mood tags, length targets

/lore/                    ← all narrative canon
/design/                  ← all game systems reference (this folder)
/tools/                   ← pipeline scripts (strip_draft.py, render_bulk.py)
/addons/
  zylann.voxel/           ← Zylann's Voxel Tools plugin
  dialogic/               ← Dialogic 2 plugin
```

---

## What Is Deliberately NOT Used

| Thing | Why not |
|---|---|
| C# | GDScript only — project prioritizes readability |
| VoxelMesherTransvoxel | Smooths geometry — kills the blocky aesthetic |
| CSGBox/CSGMesh | Prototype-only nodes; can't be used with physics properly |
| GridMap for open world | Only for structured interiors; not organic terrain |
| VoxelGeneratorScript (GDScript subclass) | Too slow — VoxelGeneratorGraph compiles to compute shader |
| Billboard sprites for characters | Camera is too close; low-poly Blender models used instead |
| Area3D gravity for river currents | Godot 4.4 bug — CharacterBody3D ignores it; manual velocity addition only |
| Dedicated relay server for co-op | ENet direct connect + Steam Remote Play covers the audience |
| Any paid voxel middleware | Zylann's plugin is free, proven, and open source |
