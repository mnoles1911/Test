# Voxel Scale Vision — 10cm Re-Architecture

> **Status: APPROVED direction, 2026-06-12.**
> Implementation lives in the R0–R4 PR track. Cross-reference PR descriptions and MILESTONES.md as each piece ships.

---

## What this is

The world is moving from roughly 6 voxels per meter (~16.7cm per voxel) to 10 voxels per meter (10cm per voxel). The reason is simple: 6/m looks like a game. 10/m looks like a place.

The target aesthetic is "Lay of the Land" — a real indie game that builds its entire world out of 10cm voxels and achieves something none of our current reference games (Veloren, Cube World) get close to: individual grass blades, per-petal flowers, dirt that shows its grain when you dig into it, water that has visible depth, and terrain that reads as *land* rather than stacked cubes. Layer on top of that: long view distances (~86m of crisp voxel terrain blending into a ~5km smooth-mesh horizon), dynamic day-to-night lighting, atmospheric god rays, and a sky that reads as genuinely beautiful. That combination — fine destructible micro-world plus sweeping vistas plus dramatic sky — is the visual target for Mira-Thal.

The R0–R4 PR track is the implementation path. R0 and R1 handle the scale migration and terrain pipeline; R2 locks the terrain look; R3 is this doc (art direction and vision); R4 delivers destructible micro-voxel flora. Track progress in MILESTONES.md as PRs ship.

---

## The five reference shots

These images live in `design/inspiration/` — drop them there yourself (see that folder's README). The descriptions below are written so the doc stands alone before the images land.

### ref_01_grass_blades.png — The flora benchmark

Lay of the Land gameplay footage, first-person view on a riverbank. The entire foreground is a dense lawn of individual grass blades built from thin voxel columns, each roughly 10cm wide and 20–30cm tall, close-packed enough to read as a field but with enough variety to look organic rather than tiled. Scattered through the grass: red tulip voxels, light-blue blooms, orange flowers — each one a small cluster of 3–5 voxels at most. In the immediate foreground, a freshly dug patch of brown dirt shows the 10cm voxel grain clearly — you can count the cubes, and it looks right rather than coarse. Behind the grass, teal water catches soft warm light. Shadows fall at a low angle across the whole scene, making the grass and flowers pop.

**This is the benchmark for terrain resolution and destructible flora.** When R4 ships, a screenshot from the same spot in Mira-Thal should be comparable to this image.

### ref_02_waterfall_dig.png — The destructible terrain benchmark

Lay of the Land, looking straight down a player-dug shaft about 4–5 meters deep. A column of teal water pours in from one side — the waterfall is rendered as solid voxel water, white foam and bubble voxels visible at the point of impact. The shaft walls step down in orange-sand voxels at the top, transitioning to darker grey stone toward the bottom. Water is already pooling at the base. The whole scene reads as a consequence of player action — this is what digging into the ground and hitting a water source actually looks like.

**This is the benchmark for destructible terrain and flowing finite water.** Our ledger-based finite water sim (`scripts/FiniteWaterCore.gd`, PR track W) already does the physics; this image defines the look — the voxel grain on cut surfaces, the way water fills rather than teleports, the color transition from sand to stone as you dig deeper.

### ref_03_medieval_tower_vista.png — The built structures benchmark

A shader-grade voxel render (not gameplay footage — a beauty shot). A round stone tower with a conical roof rises from a hillside. Dense broadleaf trees surround it — each tree is a ball of green-tinted leaf voxels over a brown trunk, and there are enough of them to read as a real forest rather than scattered props. A cobblestone path winds down from the tower to a wooden bridge over a teal river in the foreground. In the background: a large volcanic mountain with glowing orange lava streaks on its flanks, and fluffy white clouds sitting low against the horizon. The overall lighting is soft and warm — global illumination fills the shadowed sides of voxels without washing them out.

**This is the benchmark for built structures, midground forest density, and soft GI lighting.** The stone tower is how player-built or world-generated structures should read; the forest density is the tree-population target; the cloud shape is the skybox direction.

### ref_04_vista_volcano.png — The view distance benchmark

A high aerial view capturing kilometers of terrain in a single frame. From left to right: a volcanic mountain with active lava at the far horizon; dense forest; patchwork farmland; a beach; ocean. Flat-bottomed voxel-style clouds hang over the mid-distance. Distant stone towers are visible on the horizon. The terrain reads cleanly at every distance — voxel grain in the foreground, smooth blended mesh at the horizon, nothing abruptly "pops." The sky is a gradient from pale blue at the zenith to a warmer haze toward the horizon, and the whole frame feels like you're seeing the actual scale of the world.

**This is the benchmark for view distance, skybox quality, and distant terrain.** Our `DistantTerrainManager.gd` handles the ~5km smooth-mesh horizon rings; the voxel LOD handles the ~86m crisp ring; this image is what the handoff between them should feel like when it's working.

### ref_05_golden_hour_godrays.png — The dynamic lighting benchmark

Golden hour, late afternoon. A square stone church tower sits slightly left of center against a hazy sun — the sun is visible as a disc, and volumetric god rays beam down through the atmosphere in multiple visible shafts. A river runs in the middle distance, its banks lined with red-flowered plants. A wooden bridge rail crosses the lower-right foreground. On the left, a lantern post — the lamp has a warm glowing flame inside, an emissive accent that reads clearly even against the bright sky. The entire scene is warm orange-gold, with cool blue-grey in the deepest shadows.

**This is the benchmark for dynamic lighting, atmospheric quality, and emissive accents.** The god rays are already in the codebase (`GraphicsManager.light_shafts_enabled`, PR #245) and default OFF — this image is the tuning target when the designer decides to turn them on. The lantern emissive is the kind of accent `EmissiveBakedLightManager.gd` should be delivering for every light source in the world.

---

## Graphics pillars and the systems that own them

Everything in the vision above maps to code that either already exists or is in the active build track. This table exists so future sessions don't rebuild what's already there.

| Visual pillar | Owning system | Current state |
|---|---|---|
| 10cm destructible world | R0/R1/R2 of the re-architecture PR track | **In flight** — see MILESTONES.md |
| Micro-voxel flora (per-blade grass, per-petal flowers) | R4 — real destructible voxel grass + flowers via `VoxelBlockyModelMesh` custom cross-quad meshes (ids 24–26), scattered by the C++ generator on grassland at LOD0 | **v1 LIVE** — see below |
| Sky and day/night cycle | `scripts/DayNightCycle.gd` | **EXISTS** — 4-texture panorama blend, sun + moon `DirectionalLight3D` nodes |
| Global illumination | SDFGI in the `World3D` `WorldEnvironment` node | **EXISTS, enabled** at ULTRA tier |
| God rays / light shafts | `GraphicsManager.light_shafts_enabled` | **EXISTS** (PR #245), default OFF — flip is a designer decision |
| Rain, wet surfaces, atmosphere | `GraphicsManager.rain_visuals_enabled` | **EXISTS** (PR #245), default OFF — same gate |
| Long-distance vistas (~5km horizon) | `scripts/DistantTerrainManager.gd` | **EXISTS** — streaming smooth-mesh horizon rings, ~5km range |
| Night emissives and lanterns | `scripts/EmissiveBakedLightManager.gd` | **EXISTS** — baked 3D-texture floodfill; do NOT use the old `EmissiveLightManager.gd` |
| Underwater look | `scripts/UnderwaterFilter.gd` + `WaterBiomeZone` | **EXISTS** (PR #249 / water track) |

---

## Micro-voxel flora — v1 LIVE (PR R4)

Real, destructible voxel grass and flowers — the signature "Lay of the Land" flora benchmark (ref_01). Flora are **actual voxels**, not multimesh decoration: three CHANNEL_TYPE ids — `grass_blade` (24), `flower_red` (25), `flower_blue` (26) — drawn as cross-quad custom meshes (two intersecting vertical quads), injected at runtime in `World3DBootstrap` right after the water fluid models. The C++ cubic generator scatters them deterministically on grassland surfaces at LOD0 (~35 % grass blades, ~2 % flowers split red/blue). They are **walk-through** (no collision), **destructible** (dig the ground under them and they vanish with it), and behave correctly with the world sim: water flows into and mows them down, gravity/sever ignore them (a tree never connects to ground through a blade, a falling cluster never carries one). Identity funnels through `scripts/FloraMaterial.gd` (`is_flora()`), the grass/flower analogue of `WaterMaterial.is_water_type()`. Gated by the headless `flora` selector.

**Deferred to a later flora PR (NOT in v1):**
- **Trample** — flora bending / flattening as the player or enemies walk through it.
- **Scythe drops + XP** — harvesting flora for an inventory item and routing XP through `SkillManager`.
- **Wind sway** — per-blade vertex animation in the flora material/shader.
- **Biome density maps** — per-region grass/flower density and species (v1 is a single global density on plain grassland).
- **Pixel-art tiles** — v1 uses flat vertex-colour quads (grass green, poppy red, cornflower blue). Proper authored pixel-art atlas tiles are a `DESIGNER_TODO` row, not a code blocker.

---

## What 10cm actually changes about how the game feels

At 6 voxels per meter, Roland is roughly 10–11 voxels tall. At 10/m he is roughly 17 voxels tall. That extra height means:

- A sword is several voxels wide — it reads as a weapon, not a colored stripe.
- A doorway is a real doorway with visible frame thickness.
- When you dig, the resulting hole has visible stepped grain — it looks carved, not erased.
- Grass is per blade. A flower is recognizable as a flower, not a colored pixel on the ground.
- Stone walls show individual block courses. Cobble paths read as cobble.

The world stops being an abstraction of a place and starts being a place.

---

## Hard constraints to keep in mind

These are not design goals — they are fixed facts about the engine and the hardware target. Every implementation decision in the R-track has to work within them.

**LOD0 collision ring:** Zylann Voxel Tools' LOD0 ring (the fully-simulated, collidable voxel zone around the player) caps at roughly 12.8m radius at 10 voxels/meter given the chunk grid. This is not a tunable — it's baked into how Zylann handles chunk count vs. voxel scale.

**Volume cost:** Moving from 6/m to 10/m means roughly 4.6× more voxels in any given cubic meter. The perf budget is **median under 5ms per frame, p99 under 16ms** on the designer's RX 7800 XT. Every system in the R-track has to prove it fits before it ships.

Do not flip the voxel scale and then profile after the fact. Profile during each PR in the track.
