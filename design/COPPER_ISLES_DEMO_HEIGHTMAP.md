# Copper Isles — Heightmap Generation Spec
## Target: AI Image Generator (Midjourney / DALL-E / Stable Diffusion)

> Rewritten 2026-05-05 for the 5 km × 5 km / five-large-island layout.
> Companion lore: `lore/copper_isles/GEOGRAPHY.md`
>
> **How to use this file:**
> 1. Paste the **AI Prompt** section directly into your image generator of choice.
> 2. Use the **Full Terrain Description** section as reference if the first result misses something specific — break it up and iterate island by island.
> 3. Once you have a good heightmap image, see **Godot Import Notes** at the bottom.

---

## AI Prompt
### Paste this directly into the image generator

```
Orthographic top-down grayscale heightmap of a rugged ocean archipelago, 5km x 5km area. White = highest elevation, black = deepest ocean. Photorealistic satellite elevation map style, no labels, no text, no color, no contour lines, no roads.

OCEAN: near-black deep water fills most of the image. Five large islands arranged in a loose gentle arc from left (west) to right (east) across the center of the image, with the largest islands in the middle of the chain. Roughly fifteen smaller islands, rock-stacks, and tiny islets scattered loosely around the main chain with no regular pattern.

ISLAND PEAKS: each large island has one or two dramatically jagged bright-white bare rock peaks — sharp marble spires or pinnacles, extremely steep on all sides, rising far above the surrounding forested slopes. These peaks are the visual anchors of the image. The tallest peak (on the fourth island from the left) is a single dominant near-vertical white spire. The second island from the left has twin closely-spaced spires giving a split-peak silhouette.

SLOPES: below the peaks, each island has a dark-gray forested mid-slope. West-facing coasts are sheer near-vertical cliffs — a hard sharp edge where the gray land meets the black ocean. East-facing coasts step down in broad gradual terraces. The second and fourth islands from the left have visibly stepped quarry-cut terracing on their east faces — horizontal scar-steps cut into the slope, giving those sides a staircase profile.

HARBORS: the largest island (center of the chain) has a deep crescent-shaped harbor cove biting into its south coast — a dark U-shaped inlet. Each large island has at least one smaller harbor notch on its south or east coast.

SMALL FEATURES: one low flat island sits north of the center large island — barely visible, low gray shape almost flush with the ocean surface. A loose cluster of tiny barely-above-water rocks appears in the central-west area between islands, nearly indistinguishable from the ocean. Several sharp pinnacle rock-stacks jut from the open water east and south of the main chain.

16-bit grayscale, topographic, overhead orthographic, photorealistic heightmap.
```

---

## Full Terrain Description
*Use this as reference for iteration. If the AI gets a specific island wrong, describe that island alone as a follow-up.*

### Overall Layout

Five large rocky islands in a loose west-to-east arch across the center of the 5 km × 5 km map. The chain bows slightly southward — the middle three islands sit about 400 m south of where a perfectly straight line would put them. The largest islands are in the middle; the two end islands are the smallest of the five.

The entire playable area is open ocean except for the island landmasses and a thin scatter of smaller islets. Most of the water is 25–40 m deep. It reads dark.

Coordinates are (x meters from west edge, z meters from north edge):

| Island | Center position | Footprint | Peak | Peak character |
|---|---|---|---|---|
| 1 — Marrow Holt | (700, 2700) | 1,000 × 700 m | 320 m | Single broad dome |
| 2 — Bryn Mor | (1700, 2400) | 1,200 × 900 m | 480 m | Twin sharp spires |
| 3 — Caer Aelynd | (2700, 2500) | 1,600 × 1,100 m | 420 m | Broad-shouldered massif |
| 4 — Tor Galdoryn | (3700, 2400) | 1,400 × 1,000 m | 580 m | Single dominant spire |
| 5 — Caer Vethryn | (4500, 2700) | 1,100 × 800 m | 380 m | Rounded, weathered, hooded profile |

---

### Per-Island Terrain

**Island 1 — westernmost, smallest of the five**
- Footprint ~1,000 m E-W × 700 m N-S
- Single rounded marble dome at the summit, 320 m. Not a spire — broader and softer than the others.
- West face: modest cliff, 50–80 m vertical drop to the sea over about 40 m horizontal.
- All other coasts: gentle slopes down to sea level over 200–350 m horizontal.
- One small harbor notch in the south coast, ~80 m wide, 4–6 m deep.
- Dense forest from sea level to ~300 m (the treeline), bare dome above.

**Island 2 — second from west, most dramatic silhouette**
- Footprint ~1,200 m E-W × 900 m N-S
- **Twin marble spires** side by side, ~100 m apart, reaching 460 m and 480 m. The split-peak silhouette is the island's signature — this is what sailors recognize from 50+ km out.
- West face: sheer cliff running the full 900 m north-south length. 60–90 m vertical face with almost no slope — drops nearly straight to the water. The cliff face is streaked with vertical copper-oxide staining (important for color rendering but irrelevant to the heightmap shape).
- East face: stepped quarry-scar terracing. The slope has been cut into 4–5 broad horizontal shelves, each roughly 15–20 m tall, from sea level to about 300 m elevation. These are mining cuts, not natural — they read as an unnatural staircase pattern on the east slope.
- North and south coasts: moderate gradients, 100–200 m horizontal from coast to 100 m elevation.
- Small harbor on the west coast, tucked below the cliff.

**Island 3 — center, largest**
- Footprint ~1,600 m E-W × 1,100 m N-S
- Largest land area. The peak (420 m) is a broad-shouldered massif — not a sharp spire but a rounded high plateau with a gentle crown. Less dramatic silhouette than Island 2 or 4, but more imposing in bulk.
- West face: sheer cliffs, 80–100 m vertical over ~30 m horizontal. The full 1,100 m north-south length is cliffed.
- East face: three to four distinct broad terraces stepping down from ~400 m to sea level. Each terrace is ~15–20 m tall with a near-vertical riser and a flat or gently sloping tread 100–150 m wide. These are natural agricultural terraces, eroded over millennia — softer edges than Island 2's quarry cuts.
- **Harbor cove:** a deep crescent U-shape biting into the southeast corner, centered roughly 400 m west of the east coast and 300 m north of the south coast. Cove mouth is ~250 m wide opening to the south; depth into the island ~200 m; water inside the cove 4–10 m deep. This is the most prominent coastal feature of the entire archipelago.
- Secondary harbor notch on the northwest coast.

**Island 4 — second from east, the highest peak**
- Footprint ~1,400 m E-W × 1,000 m N-S
- **The navigation peak.** A single dominant marble spire at 580 m — the tallest landmass in the entire archipelago. Narrower at the summit than any other island's peak; extreme verticality. Sailors set their final approach to the archipelago by lining up this peak.
- All sides are steep. There is almost no gentle terrain on this island.
- West face: essentially the same sheer cliff as other islands, but more dramatic because the summit is so much higher — the visual drop from peak to waterline is the most extreme in the chain.
- East face: heavily stepped from quarrying, similar to Island 2's east face but more extensive — 6–8 broad horizontal cut-shelves running from sea level to ~350 m.
- Small fortified harbor at the base of the south slope — a cut into the cliff, roughly 150 m × 100 m, well-protected.

**Island 5 — easternmost**
- Footprint ~1,100 m E-W × 800 m N-S
- Peak 380 m, but notably softer and more weathered in profile than the other islands. The marble here is older and more eroded — the summit silhouette has a distinctive slightly-hooded or drooping-shoulder quality from certain angles (south-approach).
- West face: cliffs, but lower and less severe than the middle three islands (~40–60 m vertical).
- All other coasts: gradual, forested slopes — the gentlest large island in the chain.
- Dense continuous forest right up to the treeline; the most heavily wooded island.
- Two small harbor notches on the south coast.

---

### Smaller Islands and Features

**Approximate positions and descriptions:**

| Feature | Position (x, z) | Size | Height | Character |
|---|---|---|---|---|
| Archive Isle | (1800, 800) | 600 × 400 m | 45 m max | Low flat wooded island, barely visible |
| Resettlement isle A | (500, 1800) | 350 × 250 m | 60 m | Moderate forested hump |
| Resettlement isle B | (3200, 1600) | 300 × 200 m | 50 m | Rounded hump |
| Resettlement isle C | (4200, 3400) | 400 × 300 m | 70 m | Forested, slightly irregular |
| Cradle (hidden lagoon) | (1200, 3400) | 350 × 250 m | 25 m | Very low, flat, with a south-facing cove notch |
| Lighthouse rock A | (700, 1400) | 120 × 80 m | 40 m | Sharp narrow pinnacle |
| Lighthouse rock B | (4600, 1600) | 100 × 80 m | 35 m | Sharp narrow pinnacle |
| Lighthouse rock C (Lantern Rock) | (4800, 3200) | 150 × 100 m | 55 m | Sharpest pinnacle in the outer waters |
| The Boneyard | (1300, 2800) | ~200 m scatter | 0–2 m | 10–15 tiny rocks barely breaking the surface; near-invisible from distance |
| Scatter rock A | (600, 3500) | 60 × 50 m | 20 m | Bare pinnacle |
| Scatter rock B | (3000, 900) | 50 × 40 m | 15 m | Bare pinnacle |
| Scatter rock C | (4900, 1000) | 70 × 60 m | 18 m | Bare pinnacle |
| Scatter rock D | (2500, 3800) | 80 × 60 m | 12 m | Near-sea-level rock |
| Scatter rock E | (4200, 700) | 60 × 50 m | 14 m | Bare pinnacle |

---

### Bathymetry

| Zone | Depth | Grayscale value (0–255) |
|---|---|---|
| Deep open ocean | −30 to −40 m | 5–20 (near-black) |
| Inter-island channels | −15 to −25 m | 20–40 (very dark gray) |
| Harbor approaches | −4 to −10 m | 40–60 (dark gray) |
| Inside harbor coves | −4 to −8 m | 45–65 |
| The Boneyard shoal | 0 to −2 m | 120–135 (at sea level) |

Sea level = gray value ~128 (50% brightness). Land starts brighter than 128; seabed is darker.

---

### Erosion and Slope Rules
*(tell the AI or apply manually if hand-painting)*

- **West face of every large island = hard edge.** The prevailing westerly weather has carved these into near-vertical cliffs. The gradient in the heightmap should be a sharp near-vertical line — no soft transitions here.
- **East face = gradual terraces.** Soft gradient with distinct flat steps on Islands 2 and 4 (quarry cuts), naturally eroded terraces on Island 3.
- **North and south coasts = moderate gradient**, 100–250 m horizontal from sea level to 100 m elevation.
- **No rivers.** Islands too small for drainage networks.
- **No glacial rounding.** Wrong climate for U-valleys. All erosion is wave, wind, and rain.

---

## Iteration Notes

If the first AI output misses specific features, try these targeted follow-up prompts:

**Peaks too rounded:**
> "The marble peaks should be sharper and more jagged — nearly vertical spires rising above the forested slopes. Add more contrast between the bright white peak and the medium-gray forested slope below. Island 4 (fourth from left) should have a dramatically tall single spire, the tallest point in the image."

**West-face cliffs not reading:**
> "The west-facing coast of each large island should be a hard sharp cliff — an almost vertical drop from the gray land mass to the black ocean. There should be no gradual slope on the west side of any large island."

**Quarry terraces not visible on Islands 2 and 4:**
> "The east face of the second island from the left and the fourth island from the left should show stepped horizontal terracing — like a staircase cut into the hillside, 4–6 broad flat steps from sea level to mid-elevation."

**Harbor cove on Island 3 not deep enough:**
> "The center island should have a large deep crescent harbor bay on its south coast — a clear U-shaped dark indentation biting deep into the south side of the island, about 200m deep and 250m wide at the mouth."

---

## Godot Import Notes
*(when you have a heightmap image you're happy with)*

1. Export from the AI tool as a **PNG at maximum resolution** (or 16-bit grayscale if the tool supports it).
2. Drop into `assets/heightmaps/copper_isles_heightmap.png` (create the directory).
3. Import in Godot with **"Keep as Image"** — not as a texture.
4. Create `scenes/CopperIslesDemo.tscn`, replace `CubicHeightmapGenerator` on the `VoxelLodTerrain` with a `VoxelGeneratorGraph`.
5. Wire the heightmap image into the graph — scale the 0–255 range to the −40 m to +90 m elevation range, add the sea level offset of 48 vox (8 m).
6. Water below sea level fills automatically — the generator emits per-voxel water bytes into `CHANNEL_DATA5` for any column whose ground voxel-Y is below `SEA_LEVEL_VOXELS`. No `add_source_region` call needed (and that API is gone — see `design/SWIMMING_AND_WATER.md` "Voxel Water Architecture").
