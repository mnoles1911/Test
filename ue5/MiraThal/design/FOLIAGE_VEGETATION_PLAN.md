# Foliage & Vegetation Plan — UE5.7 cubic voxel world

**Status:** PLAN / research doc, 2026-06-22. No engine code written. This is the design
intent + sequencing for grass, flowers, ground detail, and trees in the UE5 (`ue5/MiraThal`)
port. It reads the current code, carries the *intent* from the legacy Godot build, and lands
on a UE5.7-native tiered plan that keeps the **true-cube blocky identity** non-negotiable.

Engine context (from root `CLAUDE.md`): UE5.7 custom source build, Lumen + Nanite + VSM +
Chaos, our own cubic voxel engine `MiraThalVoxel` at **10 voxels/metre = 10 cm cubes**, 5 km
roaming streamed map, Skyrim-grounded atmosphere.

> **Plain-English one-liner:** today the world grows real, mineable cube-grass right around
> you but the lawn stops in a hard circle a few metres out. This plan keeps that near grass,
> adds a cheap "fake" grass carpet that fills the gap out to ~50 m, makes it all sway in the
> weather wind, and builds trees out of cubes (logs + leaves) the same way Minecraft does —
> so they chop and fall like everything else.

---

## 1. Current state — what flora exists and how it's drawn today

### 1.1 The five "flora" voxel ids (the near layer already shipped)

Source of truth: `Source/MiraThalVoxel/Public/Core/MaterialIds.h`. Flora and surface detail
occupy one contiguous **pass-through** id block `24..28`:

| id | name | predicate | colour (`VoxelColor.h`) |
|----|------|-----------|-------------------------|
| 24 | `GRASS_BLADE` | `is_flora` | `(115,158,66)` grass-green |
| 25 | `FLOWER_RED`  | `is_flora` | `(217,46,41)` poppy red |
| 26 | `FLOWER_BLUE` | `is_flora` | `(92,133,230)` cornflower blue |
| 27 | `PEBBLE`      | `is_surface_detail` | (grey, terrain palette) |
| 28 | `TWIG`        | `is_surface_detail` | (brown, terrain palette) |

`mat::is_passthrough(24..28)` is THE exclusion predicate: gravity, the sever BFS, and the
finite-water sim all treat these as air. Trees are **separate** — `LOG (10)` and
`LEAVES (11)` are solid terrain ids, not pass-through (see §3).

### 1.2 How near flora is meshed and drawn — `Core/FloraMesher.h`

It is rendered as **small per-voxel billboard geometry**, not cube faces. The greedy mesher
skips ids `24..28` (they route to `FaceClass::Flora` and emit no cube faces); `append_flora()`
then sweeps the inner chunk `[0..31]` and, for each flora/detail voxel, emits:

- **Grass blade (24) + flowers (25,26):** a **billboard CROSS** — two double-sided vertical
  quads crossing through the cell, full voxel height (0.1 m tall at this scale), half-width
  0.4 voxel. `emit_cross()`.
- **Pebble (27) + twig (28):** a flat double-sided **ground quad** lying just above the cell
  floor (pebble 0.6×0.6, twig 0.8×0.3 voxels). `emit_ground_quad()`.

Determinism: a per-cell `hash3(x,y,z)` (Knuth/Murmur mix) drives a small XZ jitter (±0.1
voxel) and a full-range yaw, so the field doesn't look stamped but **never flickers** between
frames and is **seam-safe** (same local coords → same jitter). Colour is the flat
`base_color(id)` knocked down ×0.95 (no directional `face_shade` — a cross faces every way).

UV: a placeholder **flora atlas** (32-col, 16 px tiles) routes each id to a tile; the real
sprite sheet + material is authored UE-side. The material is expected to be **alpha-scissor,
no back-face cull** (the mesher emits both windings so depth passes from any angle).

### 1.3 How it streams today — `Private/VoxelChunkActor.cpp`

- The generator emits a flora voxel per surface column via `Col.flora_id` (placed at
  `ground_y + 1`); see §5.1.
- `BuildMeshBuffers()` calls `greedy_mesh()` then `append_water_surface()` then
  `append_flora()` for the **near band only**. The `FaceClass::Flora` section gets its own
  material (`CachedFloraMat` / `FloraMat`), bound at section index `== FaceClass::Flora`.
- **LOD chunks carry NO flora.** `VoxelChunkActor.cpp` comment: *"LOD chunks carry no
  water/flora (the downsample drops those channels), so the mid/far bands mesh solids only;
  the near band still gets water + flora."* This is the **bald-ring problem**, ported intact
  from Godot.

### 1.4 What does NOT exist yet in UE5 (gaps this plan fills)

- **No mid/far grass.** The voxel flora stops at the near band edge (one LOD0 ring of chunks).
  Past that = bare terrain. The legacy Godot `FarGrassManager` impostor layer was **not
  ported**.
- **No wind/sway.** The Godot `flora_sway.gdshader` was **not ported**; the UE flora material
  is static. (And even in Godot, sway was zeroed in the final pass to match the solid-column
  near grass — see §4.)
- **No trees in UE5 yet.** Legacy `design/TREES.md` describes generator-emitted `log`/`leaves`
  voxel trees on an 8 m lattice, biome-density-driven — but that pass is **Godot-only**; the
  UE5 `HeightmapGenerator.h` carries the `TREE_LOG`/`TREE_LEAVES` aliases and tree knobs but
  the UE tree scatter is not confirmed wired in this port.
- **No biome-coupled density** confirmed wired in UE flora (the Godot biome path drove it).

### 1.5 Legacy design intent we are porting (Godot `busy-cannon`, for parity)

- `scripts/FarGrassManager.gd` — GPU-instanced (MultiMesh) far-grass impostor ring, ~12.8–51.2
  m, pooled chunk nodes, **replays the generator's exact flora `hash3`** so far blades sit
  where the real grass will appear → invisible handoff. ~30k blade budget, 2 chunk-builds/frame,
  nearest-first fill, `cast_shadow` OFF. This is the template for our MID tier (§2).
- `assets/shaders/flora_sway.gdshader` — vertex sway driven by `TIME` + world-XZ phase, world-
  metre amplitude, `fract(VERTEX.y)` to recover blade-local height. Template for §4 wind.
- `design/TREES.md` — "trees are just voxels" (log+leaves), fell as one cluster through the
  existing sever/gravity systems. Template for §3.

---

## 2. The tiered plan: NEAR / MID / FAR

The core idea (Skyrim-anchored): grass is dense and interactive close up, becomes cheap
instanced cards mid-range, and fades into atmospheric suggestion far out — exactly how
Skyrim's `fGrassStartFadeDistance` / `fGrassFadeRange` and DynDOLOD grass-LOD billboards work
([STEP Grass LOD Guide](https://stepmodifications.org/wiki/SkyrimSE:Grass_LOD_Guide),
[DynDOLOD Grass LOD](https://dyndolod.info/Help/Grass-LOD)). We keep three tiers, all keyed to
the existing chunk stream radius so distances are tunable, not hardcoded.

| Tier | Range (proposed) | What it is | Cost model | Interactive? |
|------|------------------|-----------|-----------|--------------|
| **NEAR** | 0 → ~12.8 m (LOD0 chunk band) | The **existing** destructible voxel cross/quad flora (`append_flora`) | Already in the chunk mesh — free incremental | YES — mine, trample, severs as pass-through |
| **MID** | ~12.8 → ~50 m | **GPU-instanced cube-grass cards** placed by replaying the generator hash; wind sway via WPO | One ISM/HISM per tile, pooled; dither-fade at edges | No (cosmetic) |
| **FAR** | ~50 m → fog | Either **cheap impostor cards** or **nothing** (atmospheric) — start with nothing, add a sparse impostor band only if the seam reads badly | Sparse instanced billboards OR omitted | No |

### 2.1 Distances & transitions

- Anchor MID's **inner radius to the live NEAR band edge** (where `append_flora` stops), the
  same way `FarGrassManager.inner_radius_m = 12.8` sat exactly at the Godot LOD0 cap. Read it
  from the chunk streamer's near-radius rather than hardcoding, so a stream-radius retune moves
  the seam automatically.
- **Overlap, don't gap.** MID starts *at* the NEAR edge. Because MID positions are derived from
  the **same deterministic hash** as NEAR (§5), when the player walks forward a NEAR cube-blade
  pops in exactly where the MID card stood → the field never "rebuilds itself." This continuity
  is the whole point of the legacy `FarGrassManager` and we keep it.
- **Edge fades, not hard cuts.** MID cards fade with `PerInstanceFadeAmount` (set Start/End Cull
  Distance on the ISM) so they dissolve instead of popping
  ([Epic: smooth apparition with dithering](https://dev.epicgames.com/community/learning/tutorials/oLqa/unreal-engine-smooth-apparition-of-instances-with-dithering)).
  Use `DitherTemporalAA` so TSR resolves the dither cleanly. Skyrim does the same with its
  fade-range INI knobs; we expose ours as material/component params.
- **Match the look across the seam.** The MID card mesh must be the **same blocky cube-blade**
  (a 1-voxel-thick, ~3-voxel-tall green box column) as NEAR — the legacy build learned this the
  hard way (a swaying card next to a static cube is a *worse* seam than a bald ring). One mesh,
  one tint, one wind model across NEAR↔MID.

### 2.2 Why not just extend the voxel mesher outward?

Because the LOD downsample drops the flora channel, and meshing real cross-quads for every
grass voxel out to 50 m would be millions of tiny double-sided quads re-uploaded on the game
thread — and the **game thread is already the bottleneck** (`UE5_NANITE_CRUST_PERF.md`: live
column meshing collapses FPS to 2–3 during streaming churn). MID *must* be a separate,
GPU-instanced, non-remeshing layer. Same conclusion the Godot build reached.

---

## 3. Trees — recommendation: **voxel-built blocky trees (with an optional far impostor)**

**Recommendation: stay with generator-emitted cube trees** (`LOG`=10, `LEAVES`=11 solid
voxels), exactly as `design/TREES.md` describes — NOT SpeedTree/static-mesh trees.

### 3.1 Why voxel-built, not static-mesh

- **Aesthetic lock.** The whole project's identity is true 10 cm cubes. A smooth Nanite/
  SpeedTree tree planted on a cube hillside breaks that instantly. Minecraft-style cube trees
  are the correct fit, and they read as Skyrim's silhouette density at distance without the
  realism mismatch.
- **Everything-for-free.** Because logs/leaves are **ordinary solid voxels** (outside the
  `is_passthrough` 24..28 range), trees already:
  - **mine** (a log is a normal voxel with a yield item),
  - **fell** via the existing **sever BFS** (cut the trunk, the connected crown floods and
    drops as ONE cluster through `VoxelGravity`),
  - **float** if a felled cluster lands in water (finite-water buoyancy),
  - are **deterministic** (no per-chunk RNG → save/reload/regen identical).

  No tree-fall code, no physics props, no per-tree actors. This is a massive scope win.
- **Streams with terrain by construction.** A tree is just voxels in the terrain buffer, so it
  streams, LODs, and bakes (Nanite crust) with the chunk it lives in — zero extra streaming
  system.
- **Static-mesh trees would fight Nanite anyway.** UE5.7 Nanite foliage explicitly does **not**
  recommend WPO wind and does **not** love masked leaf cards (overdraw); the supported path is
  Nanite *skinning* with a bone rig + the Dynamic Wind plugin — heavy machinery aimed at
  realistic trees we don't want
  ([Nanite Foliage docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/nanite-foliage),
  [StraySpark Nanite foliage guide](https://www.strayspark.studio/blog/nanite-foliage-ue5-complete-guide)).
  Cube trees sidestep all of it.

### 3.2 The shape/placement math (port from `design/TREES.md`)

- **8 m anchor lattice** (`tree_lattice_voxels = 80`): one candidate tree per 80×80-voxel cell.
- `resolve_tree(lattice_x, lattice_z)` — pure deterministic function: jittered trunk position,
  spawn-free disc near world origin, biome pick → `tree_density` existence roll, ground gate
  (trunk on grass top, above sea level), species params (height, trunk radius, canopy radius)
  from independent hash salts.
- **Chunk-spanning correctness:** the block-fill loop scans every lattice cell whose canopy
  could *reach* this block (window widened by `tree_max_reach_voxels()`), so a canopy whose
  trunk is in a neighbour chunk is still stamped → **seam-safe** (two adjacent chunks emit
  identical voxels for a shared tree). This is the same property the flora hash gives grass.
- **Air-only write:** trees only overwrite AIR, never carve ground/water/flora.
- Per-biome density (`deciduous_forest` dense ~1/6 m, `rolling_hills` sparse, desert/mountains
  none) lives in biome profiles — designer-tunable, no code edit.

### 3.3 Far trees — the one gap

A forest canopy can't be drawn by the smooth/Nanite far crust (it bakes terrain, not the
per-tree leaf voxels), so a distant forest's canopy **pops in** at the LOD→crust boundary
(logged in `TREES.md` follow-up #4). **Fix (later phase):** a sparse **tree-impostor** layer —
one camera-facing billboard card per distant tree anchor, same MID-tier instancing tech, baked
from the cube-tree silhouette. Treat as FAR-tier polish, not MVP.

### 3.4 Hybrid option (explicitly NOT recommended for v1)

A hybrid "voxel trunk + Nanite-card canopy" is possible but throws away the sever/gravity
free-win and reintroduces the masked-card overdraw + LOD-pop problems. Skip it.

---

## 4. WIND — animate grass & trees, driven by a global wind param the weather system gusts

### 4.1 The mechanism: World Position Offset (WPO) on the MID/NEAR grass material

For the **non-Nanite instanced grass cards** (MID) and the **near voxel flora** (if we choose
to animate it), wind is a **vertex shader World Position Offset** — the classic UE grass
approach (`SimpleGrassWind`, `RotateAboutAxis`, summed sines):
[Yelzkizi UE5 wind setup](https://yelzkizi.org/wind-in-unreal-engine-5-winddirectionalsource-foliage-wind-niagara-forces-cloth-and-groom-hair-setup/).
Port the legacy `flora_sway` model directly into a UE material:

- **Bend weight from blade-local height.** Recover height-along-blade with `fract(localZ/up)`
  (legacy used `fract(VERTEX.y)`), square it so the **base is planted and the tip bends** —
  never slides the whole blade. Critical: a voxel blade baked at chunk-local y=27 has a raw
  vertex height ~27, so you MUST take the local fraction or tips fling metres sideways (the
  documented "grass flying everywhere" bug).
- **Spatial phase from world XZ** so the field *ripples* instead of moving as one slab
  (`phase = (worldX + worldZ) * spatialFreq`), two summed sines for a natural non-repeating
  breeze, Z axis phase-shifted so the tip traces an ellipse.
- **Amplitude in world metres**, converted into the instance's model space via the model
  matrix basis length, so NEAR (voxel-unit) and MID (metre-unit) blades sway the **same world
  distance** — keeping the seam invisible.

### 4.2 Keeping the cubic look while it sways

The blade is a **solid cube column**, not a thin reed. A solid box with a planted base bending
only at the top reads as a *blocky* sway (the cube leans), which is the right Minecraft-meets-
Skyrim language. **Tunable amplitude** lets the designer dial it from "stiff" to "breezy"; the
legacy build even ran amplitude = 0 to keep near/far identical, which is a valid default. The
identity rule: NEAR and MID use the **same** wind material/params so they sway as one field.

### 4.3 Driving it from a global wind param (weather coupling)

- **One global wind vector + strength + gust.** Expose a project-wide wind state. Two clean
  options in UE:
  1. **`WindDirectionalSource` actor** — painted/SpeedTree foliage samples it automatically;
     it has Strength, Speed, and Min/Max Gust knobs out of the box
     ([Yelzkizi wind setup](https://yelzkizi.org/wind-in-unreal-engine-5-winddirectionalsource-foliage-wind-niagara-forces-cloth-and-groom-hair-setup/)).
     Simple, but our custom grass material would need to read it via a material node.
  2. **A Material Parameter Collection (MPC)** `MPC_Wind` holding `WindDir` (vector),
     `WindStrength` (scalar), `GustPhase`/`GustAmount` (scalar). The grass + tree-impostor
     materials read the MPC; **one C++/Blueprint writer** (the weather system) sets it each
     tick. **Recommended** — it's the cleanest bridge to our own materials and gives the
     weather system one place to push wind.
- **The weather system gusts it.** `WEATHER_V2_PLAN.md` already defines per-state
  `wind_strength` (CLEAR 0.4 → HEAVY_RAIN 3.0 → WINDY 2.8) and a `gust_intensity` knob, plus a
  wind-direction drift (3°/s, 90 s resample) and an **altitude modifier** (RIDGE +1.5,
  ALPINE +3.0 wind). The MID/NEAR grass and the tree-impostors all read `MPC_Wind`, so when a
  storm rolls in or the player climbs a ridge, the **whole vegetation field leans harder and
  gusts** — for free, no per-system wiring. The day/night actor (`MiraDayNightCycle`) does the
  *lighting* coupling (§6); the weather system does the *wind* coupling. They are orthogonal.
- **Gusts** = add a low-frequency noise term to `WindStrength` keyed off `gust_intensity` so the
  field surges and settles rather than blowing at a constant rate (matches `WindDirectionalSource`'s
  Min/Max Gust semantics).

### 4.4 Trees and wind

Cube trees are **solid terrain voxels in the chunk mesh** — they can't trivially get per-vertex
WPO without the trunk base also sliding. Options, cheapest first:
1. **No tree sway (v1).** A still cube canopy is perfectly acceptable Minecraft language;
   ship MVP without it. Leaves can shimmer slightly via a subtle material panning if desired.
2. **Canopy-only WPO** later: drive WPO only on `LEAVES`-tinted vertices (identify by vertex
   colour / material id), masking trunk vertices to zero, weighted by height above ground — a
   gentle top-of-canopy rustle. This needs the leaves to be a distinguishable material section.
3. The **tree-impostor** FAR cards (§3.3) can sway as ordinary instanced cards reading `MPC_Wind`.

Recommendation: ship trees static, add canopy rustle as polish.

---

## 5. Placement — density by biome/slope/height/material, deterministic, seam-safe, streamed

### 5.1 Deterministic placement (already the model — keep it)

The generator already decides flora per surface column and writes a `flora_id` at `ground_y+1`
(`VoxelChunkActor.cpp`, `HeightmapGenerator::ColumnResult.flora_id`). The decision is a pure
hash of world `(x,z)` + seed, biome params, and surface gates — **no RNG state**, so two chunks
streaming the same column, a save/reload, or a regen all reproduce the identical scatter. This
is the seam-safety guarantee and it's the same hash MID must replay.

Placement gates (carry from the Godot/biome model):
- **Material gate:** grass blades/flowers only where the surface voxel is `GRASS (3)`; never on
  sand/snow/stone tops. (Trees additionally require a grass top — `TREES.md` rule.)
- **Height gate:** above sea level, below the snow line. (Snow-covered tops → no live grass; see
  §6 snow-cover.)
- **Slope gate:** the generator already has cliff/slope sampling (`cliff_slope_*`); steep faces
  read as cliff material and reject flora. Cliffs stay bare → matches Skyrim's bare rock faces.
- **Biome density:** the biome profile drives grass density + a **sparse-clump** model (legacy:
  a ~1.6 m clump cell exists ~18% of the time; inside it grass is dense, outside only rare
  strays). This gives natural meadow patches instead of a uniform lawn, and the same clump math
  must be mirrored in the MID hash so patches line up across the seam.

### 5.2 MID placement = replay the generator hash on a coarse lattice

This is the legacy `FarGrassManager` algorithm, ported to UE ISM:

- Divide the XZ plane around the player into fixed **impostor tiles** (e.g. 8 m). Keep a **ring**
  of tiles whose centres fall in `[NEAR_edge, FAR_edge]` live; pool + reuse the ISM components
  for tiles that leave the ring (never destroy/recreate).
- For each live tile, sample candidate columns on a **coarse voxel stride** (legacy stride 3 =
  0.3 m, snapped to a world-global lattice so seams don't drop/double a column). For each
  candidate, run the **identical** `flora_id` hash + biome/clump/material/height gates the
  generator uses, query `get_ground_voxel_y_at(x,z)` for the surface Y, and add an ISM instance
  one voxel above ground with a small deterministic yaw/scale jitter.
- Budget: legacy sized ~30k blades over the 12.8–51.2 m band at stride 3 (caps at 40k). On UE,
  watch the **ISM instance-count ceiling** — UE5 ISM degrades past ~10k instances per component
  and `AddInstance` is slow ([ISM perf forum](https://forums.unrealengine.com/t/what-happened-to-the-instanced-static-mesh-performance-in-ue5/2107140)).
  Mitigations: (a) keep per-tile instance counts modest (a few thousand) so each component stays
  small; (b) build a tile's transforms into an array and submit **once** via
  `AddInstances`/`BatchUpdateInstancesTransforms`, never one `AddInstance` per blade; (c) disable
  per-instance collision and distance fields on the grass card (huge cost saver, per
  [Cesium procedural foliage](https://cesium.com/learn/unreal/unreal-procedural-foliage/));
  (d) `cast_shadow` OFF on MID/FAR grass (40k tiny shadow casters at distance = invisible cost,
  legacy lesson).

### 5.3 Streaming without hitching — the hard-won lesson

`UE5_NANITE_CRUST_PERF.md` is explicit: **the game thread is the bottleneck**; burst-spawning
thousands of components in one frame is exactly what tanks FPS to 2–3. UE's own Landscape Grass
system defends against this with `grass.MaxCreatePerFrame` (one HISM/frame by default) and
amortizes spawning over frames
([Landscape Grass analysis](https://wh0.is/posts/a-look-under-the-hood-at-unreal-engine-landscape-grass-en)).
Apply the same discipline, mirroring the legacy `builds_per_frame = 2`:

- **Pool + amortize.** A fixed pool of ISM components; build only **N tiles per frame** (start
  N=2), nearest-first, draining a queue — a fast sprint fills the ring over a few frames instead
  of hitching once.
- **Tie to the chunk streamer.** Drive MID tile add/remove off the **same player-chunk-crossing
  signal** the voxel stream uses, so grass and terrain load/unload together and you never have
  grass without ground or vice-versa.
- **Never per-blade actors.** Everything is instanced; one component owns thousands of blades in
  one draw call (per [Foliage Mode docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/foliage-mode-in-unreal-engine)).
- **Off-thread candidate generation (optional).** The hash + ground-Y sampling per candidate is
  pure and worker-safe (the generator height function already is). Compute a tile's transform
  array on a worker thread, then do only the cheap `AddInstances` upload on the game thread —
  keeps the per-tile game-thread cost to the upload alone.

### 5.4 Should MID use UE Foliage/Landscape-Grass, HISM, or custom?

- **UE Landscape Grass / Foliage Mode** assume a UE `Landscape` actor — we don't have one (our
  ground is a custom voxel mesh), so the auto grass-map path doesn't apply.
- **HISM** adds hierarchical culling but more overhead per update; for a per-tile ring that's
  already distance-gated, **plain ISM per tile is simpler and matches the legacy MultiMesh
  model** — recommend ISM, revisit HISM only if culling cost shows up.
- **Custom ring manager** (the `FarGrassManager` port) wraps the pooled ISMs + the deterministic
  replay + the per-frame budget. This is the recommended structure: a `UFarGrassManager` /
  `AVegetationStreamer` that follows the player, owns the ISM pool, and reads the same generator
  snapshot the chunk streamer uses.

---

## 6. Lighting / weather coupling, and keeping the blocky identity

### 6.1 Day/night lighting (follows `MiraDayNightCycle`)

Flora and tree leaves are lit by the **same Lumen sun + sky** the day/night actor drives
(`Source/MiraThalCore/Public/Sky/MiraDayNightCycle.h` rotates/colours/dims the sun, raises a
moonlight floor, drifts fog, keeps the SkyLight in sync). Because the grass/leaf materials are
ordinary lit surfaces, they get day/night colour-temperature shifts (warm dawn → neutral noon →
cool blue night) **for free** — no per-foliage code. Keep the grass material **matte**
(`roughness ~1`, `metallic 0`) so it reads like the terrain top faces and doesn't glare; the
legacy flora knocked colour ×0.95 for exactly this reason.

### 6.2 Weather coupling (wind §4 + the visual modifiers below)

- **Wind/gust** — already covered: grass + tree-impostors read `MPC_Wind`, which the weather
  system gusts per-state and per-altitude (§4.3).
- **Snow-cover.** When weather/altitude says "snowing" (`WEATHER_V2` ALPINE precip override,
  snow-line height), the grass should be **hidden or whitened**, not poking green blades through
  snow. Two options: (a) **height/snow-line gate** in placement (no grass above the snow line —
  cheapest, already a gate in §5.1); (b) a **snow-amount material param** (driven by an
  `MPC_Weather` `SnowCover` scalar) that lerps the blade tint toward white and shortens it as
  snow accumulates — a nicer transition. Recommend (a) for MVP, (b) as polish.
- **Wetness.** `WEATHER_V2` defines a `wetness` 0..1 per state. Feed it (via `MPC_Weather`) into
  the grass/leaf material to **drop roughness + add a slight spec sheen** when raining, matching
  the wet-terrain treatment so vegetation doesn't stay bone-dry in a downpour.

### 6.3 Keeping the blocky identity (the non-negotiable)

- Grass is a **cube column / cross of quads**, never a smooth reed; trees are **cube logs + cube
  leaves**, never a SpeedTree mesh.
- MID cards are the **same cube-blade** as NEAR, same tint, same wind — no smooth-vs-blocky seam.
- No Nanite-skinned realistic foliage, no masked leaf cards pretending to be geometric leaves.
- Colours come from the existing flat `base_color` palette (sRGB-encoded primaries), keeping the
  vivid, readable, stylized look consistent with the terrain.

---

## 7. Phased rollout (MVP → mid+wind → trees → far)

Each phase is independently shippable and gated; flip features on only when they read right.
Risk/effort are relative.

### Phase F0 — NEAR polish + flora material/atlas (MVP, lowest risk)
**Goal:** the already-built voxel flora looks finished under Lumen.
- Author the real **flora atlas** PNG + the **alpha-scissor, two-sided, matte** UE flora
  material (the mesher's placeholder UVs already route ids to tiles).
- Confirm flora streams correctly with the live near band; verify day/night lighting on it.
- **Effort:** S. **Risk:** Low. **Depends on:** nothing (geometry exists).

### Phase F1 — WIND on near flora (low effort, high visual payoff)
**Goal:** the near grass sways with the weather wind, blocky.
- Port `flora_sway` into the UE flora material as WPO; add `MPC_Wind` (`WindDir`, `WindStrength`,
  `Gust`); have the weather system (or a stub) write `MPC_Wind` each tick.
- Tunable amplitude (default conservative). Verify base-planted/tip-bend with the `fract`
  local-height recovery (avoid the "flying grass" bug).
- **Effort:** S–M. **Risk:** Low–Med (vertex-height recovery is the one gotcha).

### Phase F2 — MID instanced grass ring + wind (the bald-ring fix, the big one)
**Goal:** the lawn continues to ~50 m with no bald ring, seamless handoff.
- Build `AVegetationStreamer`: pooled ISM ring following the player, tied to the chunk-stream
  crossing signal, **N tiles/frame** budget, nearest-first.
- Replay the generator's exact flora hash + biome/clump/material/height/slope gates per candidate
  on a coarse stride; submit transforms via `AddInstances` (batched), collision/dist-fields OFF,
  shadows OFF.
- Same cube-blade mesh + same `MPC_Wind` material as NEAR → invisible seam. Dither-fade the outer
  edge (`PerInstanceFadeAmount`).
- **Effort:** M–L. **Risk:** Med (ISM instance-count ceiling, per-frame budget tuning, seam
  continuity). Mitigations in §5.2–5.3.

### Phase F3 — TREES (voxel-built, port `TREES.md` to UE generator)
**Goal:** Minecraft-style cube forests that chop, fell, and float for free.
- Wire `resolve_tree` + the chunk-spanning tree pass into the UE `HeightmapGenerator` (the
  knobs/aliases already exist), gated to the biome path; per-biome density via biome profiles.
- Verify on a headless determinism/seam/density gate (the Godot `trees` selector is the spec).
- Verify fell-as-one-cluster through the existing sever/gravity, and float-on-water.
- **Effort:** M (mostly porting a proven, spec'd system). **Risk:** Med (generator integration +
  seam correctness; the headless gate de-risks it).

### Phase F4 — FAR (tree-impostor band + optional far-grass fade) (polish)
**Goal:** no canopy pop-in at the LOD/crust boundary; far field reads atmospheric.
- Sparse **tree-impostor** billboard cards (one per distant tree anchor) using the F2 instancing
  tech, swaying via `MPC_Wind`; baked from the cube-tree silhouette.
- Decide FAR grass: likely **omit** (atmospheric) unless the MID outer fade reads as a seam — if
  so, a sparse far-grass card band past 50 m.
- Snow-cover/wetness material params (`MPC_Weather`) as the §6.2 polish option.
- **Effort:** M. **Risk:** Low–Med (impostor baking + matching silhouette).

### Sequencing notes
- F0 → F1 → F2 is the critical path to "the meadow looks alive and continuous." F3 (trees) is
  parallel-izable (different subsystem). F4 is pure polish.
- Default-OFF discipline (root `CLAUDE.md`): new visual layers ship **gated OFF** until the
  designer flips them — *except* a seam-fix layer over an already-ON feature (the legacy
  far-grass was the one approved default-ON exception, because a bald ring is worse than the
  fix). F2 is the analogous candidate for default-ON once it reads right.

---

## 8. Open questions for the designer

1. **FAR grass: omit or impostor?** Start with nothing past ~50 m and only add far-grass cards if
   the MID fade looks like a seam? (Recommended: omit first.)
2. **Near-flora sway amplitude** — visible breeze, or near-static blocky stiffness (legacy ran 0)?
3. **Tree wind** — ship static cube canopies (recommended MVP), or invest in canopy-only rustle now?
4. **Snow-cover** — hard height gate (no grass above snow line) vs material whitening transition?
5. **MID default-ON?** — flip F2 on by default once seamless (seam-fix exception), or keep gated?

---

## 9. Sources

- [UE5.7/5.8 Nanite Foliage docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/nanite-foliage) — WPO not recommended for Nanite; skinning is the supported wind path; masked leaf cards discouraged (overdraw).
- [StraySpark — Nanite Foliage complete guide](https://www.strayspark.studio/blog/nanite-foliage-ue5-complete-guide) — masked ≈ 2× cost; hybrid Nanite-trunk / card-leaves workflow; thin geometry caveats.
- [StraySpark — UE5.7 Nanite foliage + procedural placement](https://www.strayspark.studio/blog/ue5-nanite-foliage-procedural-placement-performance) — open-world placement perf.
- [Cesium — procedurally spawning foliage in UE](https://cesium.com/learn/unreal/unreal-procedural-foliage/) — ISM vs actor foliage; disable collision/distance fields on grass; amortize spawning over frames.
- [Landscape Grass source analysis](https://wh0.is/posts/a-look-under-the-hood-at-unreal-engine-landscape-grass-en) — `grass.MaxCreatePerFrame`, one HISM/frame default, streaming HISM model.
- [ISM performance in UE5 (forum)](https://forums.unrealengine.com/t/what-happened-to-the-instanced-static-mesh-performance-in-ue5/2107140) — ISM degrades past ~10k instances; `AddInstance` slow; batch updates.
- [Epic — smooth apparition of instances with dithering](https://dev.epicgames.com/community/learning/tutorials/oLqa/unreal-engine-smooth-apparition-of-instances-with-dithering) — `PerInstanceFadeAmount` + `DitherTemporalAA` fade.
- [Foliage Mode docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/foliage-mode-in-unreal-engine) — instancing batches to single draw calls; HISM rendering.
- [Yelzkizi — UE5 wind setup (WindDirectionalSource, foliage)](https://yelzkizi.org/wind-in-unreal-engine-5-winddirectionalsource-foliage-wind-niagara-forces-cloth-and-groom-hair-setup/) — `WindDirectionalSource` Strength/Speed/Gust; `SimpleGrassWind`/`RotateAboutAxis`/sine WPO.
- [Impostor Baker plugin docs](https://dev.epicgames.com/documentation/unreal-engine/impostor-baker-plugin-in-unreal-engine) — billboard/impostor LOD as the last level for distant foliage.
- [STEP — Skyrim SE Grass LOD Guide](https://stepmodifications.org/wiki/SkyrimSE:Grass_LOD_Guide) & [DynDOLOD Grass LOD](https://dyndolod.info/Help/Grass-LOD) — Skyrim grass density/fade-distance/billboard-LOD model we anchor to.

### Internal references (current code + intent)
- `Source/MiraThalVoxel/Public/Core/MaterialIds.h` — flora ids 24..28, `is_passthrough`.
- `Source/MiraThalVoxel/Public/Core/FloraMesher.h` — `append_flora`, cross/ground-quad, hash3 jitter.
- `Source/MiraThalVoxel/Public/Core/VoxelColor.h` — flora `base_color` palette.
- `Source/MiraThalVoxel/Private/VoxelChunkActor.cpp` — flora meshing/streaming, LOD-drops-flora.
- `Source/MiraThalVoxel/Public/Core/HeightmapGenerator.h` — `flora_id`, tree knobs, biome/slope.
- `Source/MiraThalCore/Public/Sky/MiraDayNightCycle.h` — day/night lighting the flora follows.
- `design/UE5_NANITE_CRUST_PERF.md` — game-thread-is-the-bottleneck; amortize, never burst-spawn.
- `../../design/WEATHER_V2_PLAN.md` — per-state `wind_strength`/`gust_intensity`/`wetness` + altitude wind modifier (drives `MPC_Wind`/`MPC_Weather`).
- `../../design/TREES.md` (legacy) — voxel `log`/`leaves` trees, 8 m lattice, fell-as-cluster.
- `../../scripts/FarGrassManager.gd` + `../../assets/shaders/flora_sway.gdshader` (legacy) — MID-ring + wind templates to port.
```
