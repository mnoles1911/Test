# Biome Framework

The multi-biome terrain generator for World3D (Mira). Replaces the single
rolling-hills recipe with five blended biomes — flat plains, rolling hills,
deciduous forest, rocky desert, mountains — selected per-column by a
Whittaker-style relief/moisture classifier and blended (parameters, never
finished heights) across organic borders.

**Status:** built + green on the headless `biome` gate; **default OFF**
(`World3DBootstrap.biome_framework_enabled = false`) so the shipped terrain,
the `gen` parity baseline, and the Copper Isles generator are untouched until
the designer flips it on. GPU screenshots captured + reviewed (below).

---

## Architecture / file map

| File | Role |
|---|---|
| `scripts/BiomeProfile.gd` | Pure-DATA Resource — one biome's heightfield + surface + vegetation recipe. `class_name BiomeProfile` (mirrors `VoxelMaterial.gd`; authored as `.tres`). `to_pod_dict()` flattens it for the C++ side. |
| `assets/biomes/*.tres` | The five first-pass profiles (flat_plains, rolling_hills, deciduous_forest, rocky_desert, mountains). |
| `extensions/voxel_gen/src/biome_field.{h,cpp}` | `BiomeFieldCpp` (a `godot::Resource`) — the per-column classifier + parameter blender + biome heightfield. Standalone so the `biome` gate instantiates it directly. |
| `extensions/voxel_gen/src/heightmap_generator_base.{h,cpp}` | Owns one `BiomeFieldCpp`. `set_biome_profiles / set_biome_field_params / set_biome_control_noise` forwarders; the block-fill loop reads per-biome surface materials + flora density when `biome_active()`. |
| `extensions/voxel_gen/src/cubic_heightmap_generator.cpp` | `compute_ground_y` routes to the biome field (offset by sea level) when active; legacy three-layer noise otherwise. |
| `scripts/_dev/CubicHeightmapGeneratorAdapter.gd` | Forwards `set_biome_profiles / set_biome_field_params / set_biome_control_noise` (flattens `Array[BiomeProfile]` → `Array[Dictionary]`). |
| `scripts/_dev/BiomeReference.gd` | Pure-GD parity reference — mirrors every `BiomeFieldCpp` function for the `biome` gate. |
| `scripts/World3DBootstrap.gd` | `=== BIOME FRAMEWORK ===` block: loads the five `.tres`, pushes them + the control noise + field params to the generator. `_wire_biome_framework()` + `_biome_field_ref` cache. |
| `scripts/DebugOverlay.gd` | One-line readout: appends `[<biome>]` (dominant biome under the player) to the coords label when the framework is active. |
| `tools/headless/runner.gd` + `run.ps1` | The `biome` selector. |
| `tools/_dev/shotprobe_local.gd` | `SHOT=biomes` mode — finds a pure (≥0.9 dominant) column per biome, captures eye + 30 m-high PNGs. |

### Worker-thread safety + the legacy fallback

All biome state is value-typed POD (a `std::vector<BiomeProfilePOD>` +
scalars + a `FastNoiseLite` ref) published on the main thread before
streaming, exactly like the ore/disk snapshot convention. With **no profiles
loaded**, `biome_active()` is false and `generate_block_into_buffer` /
`compute_ground_y` take the byte-identical legacy path — the `gen` gate runs
on that path and stays the parity anchor.

---

## The blend math

### Control fields (relief + moisture)

Two very-low-frequency fields drive classification, both sampled from one
`FastNoiseLite` (frequency 1.0; the per-metre multipliers are the only
scaling) at decorrelated coordinate offsets, **domain-warped** by a third
sample so borders meander:

```
warp  = noise(m·warp_freq @ offset)                  // ±1
s     = m + warp · warp_strength                      // warped lookup pos (metres)
relief   = remap01( noise(s · control_freq) )         // [0,1]
moisture = remap01( noise((s + bigOffset) · control_freq) )
```

control_freq ≈ 1/600 m, warp_freq ≈ 1/1250 m, warp_strength 140 m,
blend_margin 0.06. The FBM fields are a bell around 0.5 spanning ~[0.11,0.87]
— the thresholds below were tuned to that distribution (verified by the
histogram), **not** assumed uniform.

### Whittaker classification (the cascade)

```
relief   > 0.62   → mountains
moisture < 0.33   → rocky_desert
relief   < 0.30   → flat_plains
moisture > 0.62   → deciduous_forest
else              → rolling_hills
```

### Soft weights (the border blend)

Per column we compute a smooth **membership** in [0,1] for each kind from the
signed distance of `(relief, moisture)` to that kind's region boundaries,
ramped by `smoothstep` over `±blend_margin`. We keep the ≤3 largest
memberships, sort by descending weight then ascending index (a total order so
GD + C++ never disagree), and normalize to sum 1.0. A triple-boundary column
that collapses to ~0 membership falls back to the hard classifier so no
column is biome-less.

### Blend PARAMETERS, never outputs

Per column, the final heightfield params = `Σ wᵢ × profileᵢ` (scalars lerp;
`detail_slope_only` bool → 0..1 factor thresholded at 0.5). The ground height
is computed **once** from those blended params. Materials / patches / flora
are NOT blended — a single biome is picked by a deterministic **weighted
hash** over the contributors (`hash3(x,7,z, "BIOE")`) so borders dither
organically instead of cutting a hard material line.

### The biome heightfield (`height_from_params`)

Three octaves from the control noise, shaped by the blended params:

- **macro:** `base_amplitude_m × shaped(noise @ base_freq)` where `shaped`
  lerps fBm-billow ↔ ridged `1−|n|` by `ridge_mix`, then applies the
  **flatness** plateau (`lerp(h, smoothstep(h), flatness)` — smoothstep
  compresses the mid-band into flats, steepens the tails so peaks survive),
  then optional **terraces** (snap elevation into `terrace_band_m` bands with
  a smoothstep lip, blended in by `terrace_sharpness`).
- **mid** (3× freq) + **detail** (12× freq), detail suppressed on near-flat
  ground when `detail_slope_only`.

Output is metres of elevation; `compute_ground_y` converts to voxels and adds
the sea-level offset (120 vox = 12 m).

---

## Gate results (`run.ps1 biome`)

```
[BIOME] parity: 2601 columns (1603 border/multi-contributor);
        max errors weight=0.000000000 param=0.000000000 ground_y=0
[BIOME] determinism: PASS — two identical fields agree over 64 probes.
[BIOME] histogram plains    =  8.9% (1300 cells)
[BIOME] histogram hills     = 49.0% (7173 cells)
[BIOME] histogram forest    =  9.3% (1358 cells)
[BIOME] histogram desert    =  6.8% (995 cells)
[BIOME] histogram mountains = 26.1% (3815 cells)
[BIOME] plains flatness: 100.0% of cells within 2 vox
[BIOME] mountains relief: 56.9 m range
[BIOME] desert terrace levels: 3 distinct plateaus
[BIOME] RESULT=PASS
```

| Gate check | Result |
|---|---|
| (1) GD == C++ eps-identical (weights/params/ground-Y/surface pick), incl. 1603 border columns | PASS (all max errors 0.0) |
| (2) weights sum to 1.0, ≤3 contributors, every column non-empty | PASS |
| (3) determinism across two identical fields | PASS |
| (4a) pure plains: ≥95% of neighbours within 2 vox | PASS (100%) |
| (4b) pure mountains: height range ≥35 m | PASS (56.9 m) |
| (4c) pure desert: ≥3 distinct terrace plateaus | PASS (3) |
| (5) histogram: every biome ≥5% | PASS (min desert 6.8%) |

The **`gen` baseline was kept on the legacy no-profiles path** for parity
stability (documented choice); biome coverage lives entirely in the new
`biome` selector. (A stale May-20 `gen` baseline in the user dir was re-baked
at the current 10 vox/m scale — the legacy block-loop is byte-identical.)

---

## Screenshots (real GPU, `SHOT=biomes`)

`_renders/biome_<name>_{eye,high}.png`. Each name's anchor is the first
column found outward from origin whose dominant biome weight ≥ 0.9.

| Biome | Reads as its archetype? |
|---|---|
| **mountains** (`_high`) | **Yes, strongly** — dramatic ridged stone peaks, steep faces, a tarn, green lowlands beyond. The standout. |
| **hills** (`_high`) | **Yes** — rolling green hills at the legacy continuity-anchor amplitude (matches shipped terrain). |
| **forest** (`_high`) | **Yes** — gently rolling green floor strewn with dark dirt leaf-litter patches; moderate relief. |
| **desert** (`_eye`/`_high`) | **Yes** — tan terraced sand strata (the mesa-band look) step down to the water. |
| **plains** (`_high`) | **Flat, confirmed** — but this seed places pure-plains on a low coastal sliver, so the frame is ocean-heavy. Flatness is gate-verified (100% within 2 vox). |

**Visual judgement:** four of five biomes frame cleanly and read as their
archetype; plains is verifiably flat but its pure column lands at the coast
(low-relief plains naturally form near/below sea level in this seed), so the
auto-framed shot shows a lot of water. The terrain shape is correct — this is
a screenshot-framing limitation, not a terrain one.

---

## Follow-ups (logged, NOT built here)

1. **Per-biome distant skirt + far-grass.** The distant skirt mesher
   (`distant_terrain_mesher.cpp`) calls `compute_ground_y`, so it follows the
   new biome heights automatically — but its palette is **elevation-based,
   not biome-based**, so desert/mountains render with a grass-family skirt at
   distance. Acceptable v1; a biome-aware distant palette is the fix.
   `FarGrassManager` approximates "is grass" from the generator's flora hash;
   it does **not** yet gate on the dominant biome's `grass_density`, so a
   desert could show far-grass impostors. Gate impostor emission on
   `dominant_biome().grass_density > 0` (cheap — one `dominant_biome` call per
   chunk) as the follow-up.
2. **Atlas tiles.** rocky_desert reuses **sand (4)** for its top and **stone
   (1)** for canyon walls — there is no dedicated red-sandstone tile yet. Add
   a red-rock / banded-sandstone atlas tile + a `red_sandstone` VoxelMaterial
   and point the desert profile at it.
3. **Snow on mountains** is the generator's existing height-based snow tier
   (`snow_material_id` + `snow_line`), not a biome rule — mountains rely on it
   and don't re-implement snow. If a biome ever needs snow independent of
   elevation, add a `snow_*` field to BiomeProfile.
4. **Coastal-plains framing** of the screenshot probe (cosmetic): the
   `SHOT=biomes` anchor search could prefer the most-inland pure column per
   biome to frame low-relief biomes over land instead of ocean.
5. ~~**`tree_table`** is carried through BiomeProfile but nothing consumes it
   yet — the future trees PR reads it per-biome.~~ **Done (sort of):**
   destructible voxel trees now read per-biome `tree_density` + species size
   ranges off `BiomeProfile` — see `design/TREES.md`. `tree_table` (the
   `{kind, weight}` species list) is still unread; v1 emits one broadleaf
   species per biome. Distant skirt + far-grass still don't render/gate on
   trees (see TREES.md follow-up #4).
6. **Trample / scythe** (vegetation-only call sites) still use
   `FloraMaterial.is_flora()`; per-biome grass density doesn't change that.

---

## Designer acceptance bullets

- [ ] Flip `World3DBootstrap.biome_framework_enabled = true` (Inspector on the
  World3D root, or in the `.tscn`) and walk Mira: the five biomes should
  appear, blended at borders, with no hard material seams.
- [ ] The F-key debug coords line shows the dominant biome under you
  (`[plains] / [hills] / [forest] / [desert] / [mountains]`).
- [ ] Mountains read dramatic; plains read flat; desert shows layered strata;
  forest floor has dirt litter; hills match the old shipped terrain.
- [ ] Tune any profile in `assets/biomes/<name>.tres` (Inspector, heavy
  tooltips) and restart — no code edit needed. Re-run `run.ps1 biome` after a
  threshold/classifier change (it re-checks parity + the histogram).
- [ ] Confirm the follow-up list above is acceptable for v1 (desert atlas
  tile, distant-skirt + far-grass per-biome).
