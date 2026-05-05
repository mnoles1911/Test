# Copper Isles Demo Level — Heightmap Generation Spec

> **Purpose:** Paste-ready text for generating a heightmap of the Copper Isles archipelago — the first Game One playable demo level. Companion to `lore/locations/COPPER_ISLES.md` (which has the full lore and visual identity).
>
> **Tool-agnostic.** Works as a prompt for AI heightmap generators (Midjourney/Stable-Diffusion topographic-prompt workflows), as a brief for Gaea / World Creator / World Machine authoring, or as a hand-painting reference in Krita / Photoshop.

---

## Output specification

| Field | Value |
|---|---|
| **Format** | 16-bit single-channel grayscale PNG, OR 32-bit single-channel EXR (preferred for Godot import) |
| **Resolution** | **3000 × 3000 px** (1 m per pixel — matches the playable area exactly), OR 1500 × 1500 px (2 m per pixel) for faster iteration |
| **Coverage** | 3,000 m × 3,000 m of world space — one pixel = one square meter |
| **Vertical range** | **−40 m to +90 m** elevation (130 m total). Map this to the full 0–65535 grayscale range. |
| **Sea level** | Mid-gray, **value = 20165 / 65535 ≈ 30.8%** brightness. Anything brighter is land; anything darker is seabed. |
| **Tiling** | None — single non-tiling image, hard edges OK at map borders |
| **Companion splatmap (optional)** | Same resolution, RGB. R = sand/beach, G = grass/terrace, B = exposed rock/cliff. Black = water. |

### Sea-level math

The Godot voxel world uses 6 voxels per meter and `sea_level_voxels = 48` (Y = 8 m world space).

To convert grayscale to elevation:
```
elevation_m = (gray / 65535) * 130 - 40
elevation_voxels = elevation_m * 6
ground_y_voxels = sea_level_voxels + elevation_voxels  # = 48 + elevation_m * 6
```

So 30.8% gray = 0 m above sea = Y = 48 vox = exact shoreline.

---

## Map layout (use this as the spatial brief)

Coordinates given as (x_meters_from_west_edge, z_meters_from_north_edge), with the **+X axis pointing east** and **+Z axis pointing south**. The 3 km × 3 km map runs from (0, 0) at the northwest corner to (3000, 3000) at the southeast corner.

### Land features (bright in heightmap)

**Main Island ("Copper Isles Port")** — the centerpiece
- Bounding box: roughly (1100, 1100) to (2200, 1900) — **1,100 m E-W × 800 m N-S**
- Highest point: **Watcher's Hill at (1700, 1500), elevation +85 m**
- Western cliffs run from (1100, 1150) to (1100, 1850) — sheer drop, +60 to +90 m crest, falling to sea level within 30 m horizontal (so the gradient is intentionally near-vertical — the heightmap should pin a hard edge here)
- Central spine ridge: a curved north-south crest line passing through (1500, 1200), (1600, 1500), (1700, 1800), holding +60 to +85 m
- Eastern terraces step down lee-side: roughly +50 m at (1900, 1500), +30 m at (2000, 1500), +15 m at (2100, 1500), +5 m at (2200, 1500). Render as broad flat steps with abrupt risers, not a smooth slope.
- **The Port harbor** (sheltered inlet, south-southeast corner): a crescent bite roughly centered at (2050, 1850), opening to the south. Mouth ~250 m wide, depth into the island ~200 m. Inside the harbor: −4 to −10 m. Outside the harbor mouth, water is the standard inner-shelf depth.
- **Salt Road ferry mole** (artificial breakwater): a narrow strip of land/stone ~180 m long extending from (2100, 1900) southeast to roughly (2230, 2030). Width ~20 m. Elevation +3 m above sea (just above wave-wash).

**Archive Isle ("Maesha's Reach")** — second-largest, north-northwest
- Bounding box: roughly (700, 350) to (1300, 750) — **600 m E-W × 400 m N-S**
- Highest point: a single rounded hill at **(1000, 550), +45 m**
- Western cliff runs (700, 400) to (700, 700) — 30 m vertical face
- East, north, south coasts gentler — gradient over 40–80 m horizontal from sea to +20 m

**Lantern Rock** — sea-stack, southeast
- Centered at **(2700, 2400)**, footprint ~150 m E-W × 100 m N-S
- Sharp pinnacle: rises from sea level to **+55 m** within ~50 m horizontal — extreme gradient, almost columnar
- Surrounded on all sides by deeper water (−8 to −12 m)

**Cradle Isle** — safe-house island, southwest
- Bounding box: roughly (300, 2200) to (650, 2450) — **350 m E-W × 250 m N-S**
- Maximum elevation **+25 m**, broad and low. Crest near center at (475, 2325).
- **The hidden lagoon:** a roughly 80 m × 60 m water-filled cove biting into the south face of the island, centered at (475, 2440). Lagoon water depth: −5 m. Two rock spurs partially overlap the cove mouth from a south-approach view — model these as two short land projections at (440, 2460)→(450, 2475) and (510, 2460)→(500, 2475), both rising to +6 to +10 m.

**The Hollow Sisters** — twin islets, northeast
- Sister 1 centered at **(2350, 450)**, footprint ~200 m × 150 m, max elevation **+38 m**, jagged cliff edges on three sides (north, east, west)
- Sister 2 centered at **(2600, 500)**, footprint ~200 m × 150 m, max elevation **+34 m**, similar profile
- Narrow ~40 m channel between them, water depth −6 m

### Minor land features (smaller bright spots)

- **The Boneyard** (charted shoal, central-west): a field of low rocky spires roughly between (900, 1400) and (1050, 1700). Most spires sit at sea level ±0.5 m (so they break water at low tide and hide at high). Treat them as a scatter of ~10–15 small bright dots in a loose elliptical cluster.
- **The Cup** (reef tidepool, east): centered at (2500, 1700), ~80 m diameter, a circular ring of just-above-water rock enclosing a shallow pool (interior at −1 m, ring at +1 m).
- **Sandbar islets** (transient, central): two or three low elongated bars between (1400, 2200) and (1700, 2400), elevation +0.5 to +2 m.
- **Bare granite stacks** (bird-rocks): scatter five to seven small spots elsewhere in the open water, each 10–30 m across at the waterline, rising sharply to +5 to +15 m. Sample positions: (500, 800), (2900, 1200), (250, 1500), (2800, 2800), (1400, 200), (3000-edge cluster), (200, 2700).

### Bathymetry (dark in heightmap)

- **Inner shelf** (most of the playable water): **−2 to −8 m**. White-sand bottom in the lore — render as the lightest of the dark range (gray value ~28%).
- **Deep Channel** (between Main Island and Archive Isle): **−12 to −18 m**. A clearly-defined trough running roughly from (1300, 800) southeast through (1600, 1100) curving south to (1500, 1900) — between the two large islands. Width ~400–500 m at its widest. Floor of the channel sits at the deep end of the range.
- **Approach Channel** (south of Main Island, between Lantern Rock and Cradle Isle): **−6 to −10 m**, running roughly (700, 2500) east to (2600, 2500). Width ~600 m.
- **Outer shelf edge** (south map edge): the southern ~300 m of the map drops to **−25 to −40 m**. Not a vertical cliff — a gradient over ~150 m horizontal from the inner shelf depth down to the deep value. The drop should follow a curved line, not a straight one — bow it slightly northward in the central third of the south edge.
- **North map edge:** stays shallow at **−4 to −10 m**, the shelf continuing toward the off-map Mira mainland.

### Special instruction: cliffs are sharp, not smoothed

The western cliffs of the Main Island, the western cliff of Archive Isle, and Lantern Rock's pinnacle should be **near-vertical** in the heightmap — gradient steeper than 1:1 in places. Most generative tools will want to smooth these; resist. Voxel cliffs with sharp risers are an art-direction goal, not an artifact to fix.

---

## Climate / erosion notes

- **Prevailing wind: from the southwest.** West-facing surfaces should read as eroded (cliffed, jagged). East-facing surfaces should read as gentler (rounded, terraced). Already baked into the layout above — keep it that way.
- **No rivers.** The islands are too small to develop drainage networks. A few small seasonal gullies on the Main Island's east side are fine but not required.
- **No glacial features.** Wrong climate.

---

## Paste-ready prompt (for AI heightmap generators)

> **Use this when the tool wants a single descriptive prompt** (Midjourney with `--ar 1:1 --style raw`, Stable Diffusion topographic models, ChatGPT image-gen for terrain, etc.).

```
Top-down topographic heightmap of a small temperate-ocean archipelago, 3km × 3km area, sea level at 30% gray brightness, land brighter, seabed darker, vertical range −40m to +90m mapped to full 16-bit grayscale.

ONE LARGE ISLAND in the center-east: 1100m × 800m footprint, north-south spine ridge cresting at 85m elevation at the ridge's center-south point, sheer 60-90m cliffs along the entire WEST coast (near-vertical gradient), broad stepped agricultural terraces dropping in 3-4 distinct flat tiers down the EAST side from 50m to 5m, and a sheltered crescent harbor biting into the southeast corner with calm 4-10m deep water inside.

ONE MEDIUM ISLAND to the north-northwest: 600m × 400m footprint, low rounded central hill at 45m, a 30m sea-cliff on its west side, gentle pebble-beach coasts on the other three sides.

ONE SHARP SEA-STACK at the southeast: small 150m × 100m footprint rising to a near-vertical 55m pinnacle, surrounded by 8-12m deep water on all sides.

ONE LOW BROAD ISLAND at the southwest: 350m × 250m footprint, maximum elevation only 25m, with a small 80m × 60m hidden cove biting into its south face — the cove mouth half-masked by two small rock spurs.

TWIN ISLETS at the northeast: 200m × 150m each, jagged cliffs on north/east/west faces, peaks at 38m and 34m, a narrow 40m channel between them.

A SCATTER OF SMALL FEATURES: a cluster of low rocky spires breaking the surface in the central-west (the Boneyard, ~15 dots near sea level); a small circular reef ring on the east; two or three low transient sandbars in the central south; five to seven isolated bird-rock granite stacks scattered through the open water.

BATHYMETRY: most of the inter-island water sits at 2-8m depth (shallow shelf, light gray). One curved DEEP CHANNEL of 12-18m depth runs between the large island and the medium island. A wide shallower channel runs east-west across the southern third. The southern 300m of the map drops smoothly to 25-40m depth (the shelf edge).

Style: clean topographic heightmap, no labels, no compass rose, no text, 16-bit smooth grayscale, hard cliff edges where specified, gentle curves elsewhere. Looks like a USGS bathymetric chart converted to grayscale.
```

---

## If using Gaea (recommended pipeline)

The original Gaea pipeline (deferred for Mira authoring per `design/ART_PIPELINE.md`) is appropriate to bring back for this demo because the area is small enough to author by hand:

1. **Canvas:** 3000 × 3000 m, build resolution 3000 × 3000 (1 m / px). Sea level set at 30.8% gray.
2. **Base layer:** flat plate at sea level.
3. **Per-island authoring:** drop a `Mountain` node positioned via `Combine` for each island, scaled to the bounding boxes above. For the Main Island, use a `Ridge` node oriented north-south for the spine, then `Terrace` for the eastern step-down (3 terraces, height 50m / 30m / 15m). For Lantern Rock, use a thin tall `Pinnacle` shape.
4. **Cliffs:** apply `Erosion` only to the *east* side of each island (use a directional mask). Leave west sides sharp — `Erosion` will smooth them and you don't want that.
5. **Bathymetry:** subtract a soft `Gradient` from the southern edge for the shelf drop. Carve the Deep Channel with a hand-painted `Mask` over a `Subtract` node.
6. **Boneyard:** a `Splatter` node of small high-frequency bumps, masked to the central-west area, height clamped to ±0.5 m around sea level.
7. **Output:** Format = EXR 32-bit single-channel. Filename = `copper_isles_demo_heightmap.exr`. Drop into `assets/heightmaps/` (create directory).
8. **Splatmap (separate output):** RGB image, R/G/B channels masked by elevation bands (R = below +5 m on land = beach; G = +5 to +60 m = grass/terrace; B = above +60 m or steep slope = rock).

---

## Godot import notes (when the EXR is ready)

This will land before the Gaea pipeline returns for full Mira, so it's worth scaffolding once:

- Place `copper_isles_demo_heightmap.exr` in `assets/heightmaps/`.
- Import with **"Keep as Image"** mode — not as a texture.
- New scene `scenes/CopperIslesDemo.tscn` based on `World3D.tscn`.
- Replace `CubicHeightmapGenerator` on the `VoxelLodTerrain` node with a `VoxelGeneratorGraph` resource. Wire:
  - `Image` input node loading the heightmap → multiply by 130 → subtract 40 → this is `elevation_m` → multiply by 6 → add 48 → this is `ground_y_voxels` → drives a `HeightmapShape` SDF.
  - Material: above `ground_y_voxels - 1` = grass (or sand if `ground_y_voxels ≤ sea_level_voxels + 6`); next 3 voxels down = dirt; below = stone. (Same banding rule as `CubicHeightmapGenerator`.)
- Sea level remains `sea_level_voxels = 48` (Y = 8 m).
- Add a single `WaterFlowManager.add_source_region(aabb, level=8)` call in `_ready` covering the entire playable AABB at Y=8 — this populates the ocean in one shot and the existing water sim handles flow into the harbor, the lagoon, the Boneyard tidepools, etc.
- Wrap each settlement (the Port, the Archive, the safe-house, the lighthouse) in a `NoEditZone` Area3D in the scene tree — the buildings themselves will be MagicaVoxel `.glb` exports placed on the surface in a follow-up pass.

---

## Validation checklist after import

- [ ] Sea level reads correctly — water fills to Y = 48 vox everywhere except where blocked by land
- [ ] Watcher's Hill summit reads at ~Y = 558 vox (48 sea level + 85 m × 6 vox/m)
- [ ] Western cliffs of the Main Island are visibly sheer when standing at the cliff base
- [ ] The Deep Channel between the Main Island and Archive Isle is navigable (water column ≥ 12 m everywhere along its length)
- [ ] Cradle Isle's hidden lagoon is invisible from the south-approach view until you're inside the spurs
- [ ] The Boneyard breaks the water at low tide-equivalent and is hidden at high (handle via WaterFlowManager source level if a tide system lands; otherwise pick one and live with it for the demo)
- [ ] Outer shelf edge at the south map border drops noticeably as the player swims/sails south
