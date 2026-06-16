# UE5 Tech Stack — Mira-Thal (the canonical "what is the stack now" doc)

**Status:** LIVE / CANONICAL (2026-06-16). This is the single entry point for "what engine, language,
and architecture is this game built on *right now*." If another doc disagrees with this one about the
engine, this one wins. Companion docs (linked throughout) go deeper on each piece.

> **Plain-English orientation (read first).** This game used to be built in **Godot**. It is now being
> rebuilt — "ported" — into **Unreal Engine 5**, because UE5's lighting and rendering reach a look
> Godot couldn't. The old Godot version isn't deleted: it's frozen on a separate branch called
> `busy-cannon` as the project's history ("heritage / legacy"). Everything below describes the **new
> UE5 version**, which is the one we actively work on. Where you see "Core," think *the pure rules-and-
> math of the voxel world, written so it can be tested by itself without the game engine running.*

**Heritage note:** the original Godot build (Godot 4.6.2 + Zylann Voxel Tools) is preserved intact on
the **`busy-cannon`** branch. It is **superseded** for this line of work, **not** deleted. The legacy
tech-stack writeup is `design/TECH_STACK.md` (Godot-framed); keep it for parity/design reference.

---

## 1. Engine, language, rendering (the headline)

| | |
|---|---|
| **Engine** | **Unreal Engine 5.7** — custom **source build** at `D:/UE5/UE_5.7`, GUID-registered (it's our own compiled copy of the engine, not a launcher install; that's why the `.uproject` points at a GUID, not the string "5.7"). |
| **Language** | **C++** only. **No C#. No GDScript.** Blueprints are reserved for designer tuning / UI / VFX wiring, mirroring the old "GDScript + C++ where it counts" discipline. |
| **Rendering** | **Lumen** — dynamic global illumination + reflections (the single biggest visual win over Godot; lights the world in real time, no baking). **Nanite** — used only for a *cold bake* of static, unedited geometry, and arriving in a **later milestone** (M6). **Virtual Shadow Maps** for shadows. |
| **Physics** | **Chaos** (UE5's built-in physics) — voxel collision and falling-rubble clusters. |
| **Voxel scale** | **10 voxels per metre → each cube is 10 cm.** True blocky cubes are core visual identity, non-negotiable. |
| **Target** | Desktop (Windows; Steam later). Upscaling (TSR/DLSS/FSR) is assumed, normal for a Lumen title. |

Why the port at all: Godot's renderer capped the visual ceiling. UE5's Lumen / Nanite / Chaos /
built-in replication let Mira-Thal hit the "photoreal voxel cube + Skyrim atmosphere" target. Full
rationale + the Godot→UE5 mapping table: **`design/UE5_PORT_PLAN.md`**.

---

## 2. The voxel engine is ours (not a plugin)

There is **no third-party voxel backend.** We evaluated the market and nothing met our bar — the one
dedicated cubic UE plugin (Easy Voxels: Cubic) is a stale meshing helper with no collision/multiplayer,
and the mature plugins (Voxel Plugin 2, VoxelWeaver) are all *smooth* terrain, not cubes. So we own a
custom cubic voxel engine in the module **`MiraThalVoxel`**. Full decision record:
**`design/UE5_VOXEL_BACKEND_EVALUATION.md`**.

"Owning the mesher" is a *bounded* job, not a from-scratch engine, because the hard half — the world's
rules and math — was already written and verified as the engine-agnostic Core (see §4).

---

## 3. Module layout (where the code lives)

A "module" in UE5 is just a compilation unit — a folder of C++ that builds into one library. Ours:

| Module | What it is | Plain English |
|---|---|---|
| **`MiraThalVoxel`** | The voxel engine. Splits into two layers: **(a)** the engine-agnostic **Core** (`Public/Core/`, namespace `mira`, pure C++17, **no Unreal headers**) — generation, brickmap, greedy mesher, per-face color, water/gravity math; and **(b)** the **UE layer** (`AVoxelChunkActor`, `AVoxelWorld`, mesh-upload glue) that takes Core's output and shows it in Unreal. | The "brain" (Core, testable on its own) and the "body" (UE actors that render it). |
| **`MiraThalCore`** | Gameplay systems (player, combat, skills, etc.), ported from the Godot gameplay layer as UE C++ classes / subsystems. | The actual game logic that sits on top of the world. |
| **`MiraThalNet`** | Multiplayer / replication helpers (server-authoritative voxel edits + chunk sync). | Co-op networking (later milestone). |

Planned render/bake modules (`MiraThalVoxelRender` for the far-field ray-march, `MiraThalVoxelBake` for
the Nanite cold-bake) are scoped in `design/UE5_VOXEL_MESHER_PLAN.md` for M6–M8.

**The Core/UE split is the load-bearing idea:** Core never imports an engine header, so it compiles and
runs under a plain `clang` compiler with no Unreal involved. That's what makes the headless gate (§5)
possible, and it's why the renderer is swappable without touching the world's rules.

---

## 4. Data model (how the world is stored and drawn)

Read this as a pipeline, left to right. Each stage is a real file in `Public/Core/`:

```
 Brickmap  ──►  Chunk (32³ "slab")  ──►  GreedyMesher  ──►  per-face SOLID COLOR  ──►  AVoxelChunkActor
 (the truth)     (the mesh unit)         (quads)            (baked into vertex color)   (what you see)
```

- **`Brickmap` — the single authoritative CPU store.** A *sparse* grid of **8³ bricks** (a brick = an
  8×8×8 block of voxels). "Sparse" = empty regions cost nothing; only bricks that contain something are
  stored. Every edit, water update, and gravity update mutates the brickmap; the sim, collision, and
  mesher all read from this one source of truth. Each voxel is a 1-byte material id (0 = air).
- **Chunk / "slab" — the mesh unit.** A **32³** block of voxels (`= 4³ bricks`) plus a **1-voxel apron**
  (a one-voxel border copied from neighbours so faces at the chunk seam are computed correctly).
  `BrickmapMeshing` is the bridge: it pulls a slab out of the brickmap and, after an edit, computes
  exactly *which* chunks an edit touched so only those re-mesh.
- **`GreedyMesher` — turns voxels into triangles.** "Greedy meshing" merges adjacent same-material faces
  into big quads instead of drawing a quad per voxel face — far fewer triangles. **Ambient occlusion
  (AO)** — the soft darkening in cube corners/crevices that sells the blocky look — is baked here.
- **Texturing = per-face solid color (NEW, important — see §6).** Not a texture atlas. Each face is one
  flat color, baked into the mesh's **vertex color**. AO rides in the vertex **alpha**.
- **`AVoxelChunkActor` — the renderer.** Holds the finished mesh in a **ProceduralMeshComponent** for now
  (a **RealtimeMeshComponent** swap is planned for perf), builds **Chaos** collision from it, and is lit
  by **Lumen**.
- **`AVoxelWorld` — the manager (built at M2).** Owns the brickmap; generates a region from the
  `HeightmapGenerator`; spawns the per-chunk `AVoxelChunkActor` renderers; and runs the carve loop
  (`CarveAtWorld` / `CarveTestHole`) → re-mesh only the affected chunks → rebuild Chaos collision.

Deeper data-model + rendering-bands detail: **`design/UE5_VOXEL_MESHER_PLAN.md`** and
**`design/UE5_RENDERING_STRATEGY.md`**.

---

## 5. Verification model (how we know it works) — three gates

1. **The clang Core harness — the headless gate.** Because Core has no engine dependency, a standalone
   **clang** build (`ue5/MiraThal/tests/standalone/build.sh`) compiles and runs every Core test by
   itself, in seconds, with no editor open. The pass signal is the literal line **"ALL HARNESSES
   GREEN."** This is the first thing that must pass — generation, meshing, brickmap, color, water, and
   gravity all have a test here, the same safety-net discipline as the Godot headless harness.
2. **The UE build + PIE playtest.** Once Core is green, the full thing builds in Unreal and is checked
   in-editor at each milestone exit (e.g. M2: dig a hole, watch affected chunks re-mesh and collide).
3. **mcp-unreal in-editor checks** (see §7) — Claude Code drives the live editor to spawn/inspect actors,
   run console commands, read the output log, and capture the viewport as part of normal dev.

---

## 6. Texturing decision: per-face SOLID COLOR (supersedes the atlas plan)

**The earlier plan assumed a texture atlas** (a sheet of pixel-art tiles, UV-mapped per voxel face).
**That approach was dropped.** At 10 cm, a voxel face is tiny on screen, and per-face flat color reads
cleaner and lets Lumen do all the lighting. The current model:

- Each voxel **face** is a single **solid color** = `base_color(material)` × `face_shade(direction)`.
- **Per-face directional shading:** the six face directions get six distinct fixed shades — **top
  brightest, bottom darkest** — so cubes read as 3D even before dynamic light hits them.
- The mesher **bakes that color into the mesh's vertex color**; AO is baked into vertex **alpha**.
- The Unreal material **`M_VoxelTerrain`** is dead simple: **VertexColor → BaseColor.** No textures, no
  UVs, no atlas.
- The palette matches the old Godot per-material colors, kept in **`Core/VoxelColor.h`**.

This is documented as the live decision in `design/UE5_RENDERING_STRATEGY.md` (rendering) and
`design/UE5_VOXEL_MESHER_PLAN.md` (mesher). Any older mention of a "triplanar material atlas" / "atlas
UVs" is the superseded plan.

---

## 7. The mcp-unreal live editor bridge (standard part of the workflow)

During M-phase development, **Claude Code talks to the running Unreal editor live** through a bridge
called **`mcp-unreal`**. This is now part of the standard UE5 dev workflow, not a one-off. Two pieces:

- **Remote Control API** (UE's built-in HTTP control, **port 30010**).
- **The MCPUnreal companion plugin** (**port 8090**, built into `ue5/MiraThal/Plugins/MCPUnreal`).

Through it, Claude can: **spawn / inspect actors**, **set properties**, **run console commands**,
**author materials via editor Python**, **read the output log**, and **capture the viewport**. One
practical gotcha: **viewport capture requires the editor to be the FOREGROUND window** (it grabs what's
actually on screen). This bridge is how the in-editor checks in §5 step 3 happen.

---

## 8. Milestone ladder (status as of 2026-06-16)

From `design/UE5_VOXEL_MESHER_PLAN.md`. `✅` = done, `⏳` = next, `—` = planned.

| Milestone | What it delivers | Status |
|---|---|---|
| **M0** | Mesher foundations: chunk coords, greedy mesher, per-face color. | **✅** |
| **M1** | AO + LOD + seams + **first render under Lumen**. Perf baseline ≈ **6.4 ms** GPU (7800 XT, empty Lumen scene). | **✅** |
| **M2** | **Brickmap + generation + carve loop** — multi-chunk generated terrain + live dig with Chaos collision. **Built tonight.** | **✅** |
| **M3** | Water + flora + gravity (wire `FiniteWaterCore` + `VoxelGravity`). | ⏳ |
| **M4** | Streaming + persistence + World Partition. | — |
| **M5** | Multiplayer (server-authoritative edits). | — |
| **M6** | Cold → **Nanite** bake. | — |
| **M7** | Far-field ray-march horizon. | — |
| **M8** | GPU meshing + GPU world generation. | — |

---

## 9. Companion docs

- **`design/UE5_PORT_PLAN.md`** — why we ported, full Godot→UE5 mapping, phase sequencing.
- **`design/UE5_RENDERING_STRATEGY.md`** — Lumen-near / ray-march-far / Nanite-cold bands; per-face color.
- **`design/UE5_VOXEL_BACKEND_EVALUATION.md`** — why we own the mesher (cubic backend market spike).
- **`design/UE5_VOXEL_MESHER_PLAN.md`** — the mesher/brickmap/streaming build plan + M0–M8 detail.
- **`design/UE5_ART_ASSETS.md`** — CC0 sky/water/VFX atmosphere assets for the UE5 look.
- **`design/TECH_STACK.md`** — *legacy* Godot tech stack (heritage reference).
- **`MILESTONES.md`** — UE5 milestone entries are tagged **`[ue5]`**.
