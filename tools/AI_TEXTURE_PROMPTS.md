# AI Texture Prompts — Default Pack (16x16 Pixel Art)

Use these prompts to generate the source images for the default voxel
texture pack. Each prompt produces one face texture. Save the output
to the **exact filename** indicated under each prompt into:

    assets/voxels/texture_packs/default/source/

After generating all the textures, run from the repo root:

    python tools/build_texture_atlas.py default

That nearest-neighbour-downscales the source PNGs to 16x16 each,
packs them into `atlas.png`, and writes the manifest the game loads.

## Pick your generator FIRST

**The pipeline is pixel-art-only by design** (NEAREST downscale,
`filter_nearest_mipmap_anisotropic` sampling in-engine). Source PNGs
MUST be pixel art on a clean grid — flat blocks of solid colour on an
N×N lattice — or NEAREST downscale samples 1 source pixel per output
tile pixel and produces noise that looks nothing like the source.

The atlas builder prints a `WARN: <name> looks like PHOTO input` line
for any source whose intra-cell variance suggests a photo / painterly
output. If you see those warnings, the source is wrong for the
pipeline (not the build) — regenerate it with a tool below.

**Recommended generators, in order of how reliably they produce
correct input:**

1. **Retrodiffusion** (`retrodiffusion.ai`) or **PixelLab.ai** —
   **strongly recommended.** Pixel-art-specific diffusion services
   that output real pixel art directly at 16x16 / 32x32 / 64x64. No
   pixel-grid gymnastics, no "30% of generations come back as photo
   mush". Worth the per-image cost for asset work this exacting.
2. **Aseprite or Pixilart by hand** — if you want a truly authored
   look or a critical material (e.g. boss-arena floor). Paint
   directly at 16x16 PNG, drop in `source/`, the builder will pass
   it through unchanged (no resize when src size already matches
   target).
3. **Gemini Nano Banana** with the SYSTEM PROMPT below — **fallback
   only.** NB is a general-purpose diffusion model trained on photos
   and paintings, not pixel art. Asked for "pixel art," it returns
   *fake pixel art*: soft anti-aliased imagery with gradients
   between pixels and a ghost-grid that drifts. Sometimes the prompt
   discipline below produces something close enough that NEAREST
   recovers a useable tile; often it doesn't. Expect 3-5 regens per
   material and accept some materials will never land cleanly. Use
   only when the dedicated tools are unavailable.
4. **DALL-E 3 / Midjourney v6** — same caveat as NB; sometimes
   cleaner pixel grids, sometimes worse. Try if NB keeps failing.

## Generation settings

- **Output size**: 1024x1024 minimum (most modern generators) or
  512x512 (older). The size must be an **integer multiple of 16** so
  each output pixel maps to an exact NxN block of source pixels —
  1024 → each tile pixel is 64x64 source pixels, 512 → 32x32. Any
  resolution that isn't 16x integer (e.g. 900x900) will produce
  fractional-block sampling and grid drift.
- **File format**: PNG. RGB is fine for everything — for `leaves_all`,
  the atlas builder color-keys the white background to alpha at build
  time, so you don't need an RGBA-capable generator.
- **Seamless tiling**: required for everything except `log_top`.
  Tiling is requested in the per-material prompts below.

## Migration note (2026-05-27)

The 15 source PNGs currently committed in `source/` were generated
with Nano Banana before this doc made the pixel-art-only requirement
clear. 5 of them flag as PHOTO input when the builder runs:
`grass_top`, `gravel_all`, `log_side`, `leaves_all`, `copper_ore_all`.
The other 10 happened to land closer to pixel-art-on-grid and read
acceptably after NEAREST. Plan to regenerate the flagged five with a
pixel-art-specific tool (Retrodiffusion or PixelLab.ai). Until then
those five appear as noise in-game.

## How to use these prompts

This file is split into two parts:

1. **SYSTEM PROMPT** — paste once into the system / style / context
   field of your image generator. Carries all the shared style,
   pixel-grid rules, tiling rules, and game context.
2. **Per-material prompts** — short, pure-descriptive blocks. Paste
   one into the main prompt field for each texture you generate.

### Why split

When the system instructions and the per-material details were
combined into one prompt, Gemini Nano Banana 2's recitation filter
rejected every prompt. The filter trips when one prompt block stacks
too many specific signals at once (named genre + hex codes + heavy
negations + imperative voice + game-asset framing). Splitting the
load — system field carries the meta, main prompt carries pure visual
description — is what actually works in practice. This pairing has
been tested working with Gemini Nano Banana 2.

If your generator has no separate system field, paste the SYSTEM
PROMPT first then the per-material prompt as one continuous block.

---

## Why the pipeline rejects photo input

The atlas builder NEAREST-downscales 1024 -> 16 by **sampling one
source pixel per output tile pixel** and throwing away the other 4095
(at 1024/16=64 ratio). Two regimes:

1. **Pixel-art input** — each 64x64 source region is already a flat
   block of one colour. NEAREST samples ONE pixel from that block;
   any pixel in the block is the same colour, so the output is
   mathematically pixel-perfect.
2. **Photo input** — each 64x64 source region contains hundreds of
   distinct colours. NEAREST samples one essentially-arbitrary pixel
   from each region. The output tile is 16 unrelated pixels —
   visually noise.

The pipeline cannot fix photo input by changing the downscale algorithm
without changing the entire art direction. LANCZOS (which averages all
source pixels per output tile) would produce blurry-but-recognisable
mini-photo tiles — that would shift the look from
Minecraft/Terraria/Stardew (crisp pixel art) to something more like
Conquest/Faithful (high-res photo texture pack). The project bible
calls for pixel art; the builder enforces it.

**Cheap quality check before saving an AI generation:** zoom in on the
1024x1024 output. Each visual "pixel" should be a flat 64x64 block of
one solid colour with hard edges. If you see gradients within a
block, soft edges between blocks, or the grid drifting off the 64-px
lattice, regenerate (or accept the WARN at build time and plan to
redo with a pixel-art-specific tool).

---

## SYSTEM PROMPT

*Paste this once into the system / style / context field.*

> You are generating seamlessly tiling 16x16 pixel art block face
> textures for a medieval fantasy voxel RPG. Output size: 1024x1024,
> rendered as a 64x nearest-neighbor upscale of an underlying 16x16
> pixel-art tile.
>
> Pixel grid rule: The image must read as exactly 16x16 large square
> pixels arranged in a 16x16 grid. Each pixel is a flat 64x64 block of
> solid uniform color. No gradients between pixels, no anti-aliasing,
> no soft edges, no blur, no dithering across pixel boundaries.
> Adjacent pixels meet at hard square edges. The pixel grid must be
> axis-aligned: every pixel boundary falls on multiples of 64px.
>
> Palette rule: Limited 6 to 10 color palette per tile. Solid flat
> colors only. No color ramps, no smooth shading, no painted
> highlights, no soft shadows. Variation comes from placing different
> palette colors in adjacent pixels, never from blending.
>
> Style: 16-bit era pixel art block tile, the surface quality of a
> hand-pixeled SNES or PC RPG world. Minecraft-style face textures
> done as crisp pixel art rather than painterly. Warm saturated
> palette, readable material identity at small size, pure matte
> albedo. No baked directional lighting anywhere on the face, no
> cast shadows, no specular highlights.
>
> Tiling requirement: Every texture must tile seamlessly with no
> visible seams at any edge. This game runs at 6 voxels per meter
> (each voxel face is about 16.7 cm), so a single 10-meter stone
> wall repeats the tile 60+ times. Any dominant feature (a single
> bright pixel, a long crack, an off-color pixel) becomes a visible
> repeating grid the player cannot unsee. Detail must be balanced
> and distributed uniformly: no single pixel dramatically brighter,
> darker, or more distinctive than its neighbors. No corner or edge
> pixels that create banding when tiled. The leftmost column and
> rightmost column should look like they could sit next to each
> other; same for the top and bottom rows.

---

## Per-material prompts

*Paste one of these into the main prompt field for each generation.
Each is short, pure descriptive imagery — the kind of prompt the
recitation filter accepts.*

---

### `stone_all.png`

> A 16x16 pixel art tile of warm grey granite stone, rendered at
> 1024x1024 as a 64x upscale with hard square pixels. Designed to
> repeat invisibly across a cliff face. Warm grey palette of 6 tones
> from dark charcoal to pale highlight, with subtle brownish
> undertones. Many short 1 to 2 pixel micro-fractures scattered
> uniformly across the tile, all of similar weight, no single long
> crack standing out. Flat matte even lighting throughout. Tiles
> seamlessly with no edge seams.

---

### `stone_dark_all.png`

**SAVE AS EXACTLY:** `stone_dark_all.png` — NOT `dark_stone_all.png`,
NOT `dark_ore_all.png`. This material is a darker variant of stone
(Tier 3 jitter inside the stone band), not an ore. The slot in
`ATLAS_LAYOUT` is `stone_dark_all`; any other filename is silently
ignored by the builder.

*(Sibling of `stone_all`. The Tier 3 generator rule mixes this in
as ~17% darker patches inside the stone band so cliff faces and
underground walls show three-tone variety — plain stone, dark
stone, rare marble — rather than uniform grey.)*

> A 16x16 pixel art tile of cool dark grey basalt stone, rendered
> at 1024x1024 as a 64x upscale with hard square pixels. Designed to
> repeat invisibly across a deep cave wall. Approximately 80 percent
> of the pixels are a single uniform deep charcoal grey base color
> with subtle cool blue-grey undertones — this dominant color fills
> the tile as the natural rock surface, the heavy dense character
> of dark volcanic rock. Approximately 12 percent of the pixels are
> slightly darker near-black charcoal forming irregular natural
> rock noise — these darker pixels appear in random scattered
> clusters of 2 to 4 pixels each, never as isolated single pixels
> and never as alternating pairs. Approximately 8 percent of the
> pixels are slightly lighter cool grey crystalline mineral specks,
> placed as 1 to 2 pixel highlights at scattered positions. Most of
> any given row should be the dominant base charcoal, with variation
> appearing only at the cluster and speck positions. Flat matte even
> lighting throughout. Tiles seamlessly with no edge seams.

---

### `dirt_all.png`

> A 16x16 pixel art tile of dark rich brown loam soil, rendered at
> 1024x1024 as a 64x upscale with hard square pixels. Designed to
> repeat invisibly across an underground wall. Deep warm brown
> palette of 6 tones, the layer found under grass rather than
> topsoil. Tiny scattered micro-pebbles and faint root flecks at
> uniform density, each occupying 1 to 2 pixels. Flat matte even
> lighting throughout. Tiles seamlessly with no edge seams.

---

### `grass_top.png`

> A 16x16 pixel art tile of dense short-cropped grass viewed from
> directly above, rendered at 1024x1024 as a 64x upscale with hard
> square pixels. Designed to repeat invisibly across an open field.
> Vivid saturated green palette of 5 to 7 tones from olive green to
> bright spring green, distributed in many tiny clusters of similar
> size each occupying 1 to 2 pixels. Flat top-down view, matte even
> lighting throughout. Tiles seamlessly with no edge seams.

> **NOTE:** `grass_side.png` and `grass_bottom.png` are auto-built
> by the atlas tool. **Do not generate these.**

---

### `sand_all.png`

> A 16x16 pixel art tile of fine pale golden beach sand, rendered
> at 1024x1024 as a 64x upscale with hard square pixels. Designed to
> repeat invisibly across a beach surface. Warm tan and cream
> palette of 5 tones, soft golden highlights blending into pale
> warm beige across the pixel grid. Single-pixel grain variation
> uniformly distributed. Flat top-down view, matte even lighting
> throughout. Tiles seamlessly with no edge seams.

---

### `gravel_all.png`

> A 16x16 pixel art tile of mixed grey and warm-brown river shingle
> pebbles, rendered at 1024x1024 as a 64x upscale with hard square
> pixels. Designed to repeat invisibly across a riverbed surface.
> Cool grey palette with warm earth-tone undertones, 7 tones total.
> Small pebbles each occupying a 1 to 2 pixel cluster, packed
> tightly with hard-edged pixel boundaries between adjacent stones,
> all of similar visual weight. Flat top-down view, matte even
> lighting throughout. Tiles seamlessly with no edge seams.

---

### `clay_all.png`

> A 16x16 pixel art tile of smooth blue-grey coastal clay, rendered
> at 1024x1024 as a 64x upscale with hard square pixels. Designed to
> repeat invisibly across a tidal mudflat surface. Cool blue-grey
> palette of 5 tones with subtle moisture variation. Many short 1
> to 2 pixel hairline crack lines scattered uniformly, all of
> similar weight. Flat top-down view, matte even lighting
> throughout. Tiles seamlessly with no edge seams.

---

### `marble_all.png`

> A 16x16 pixel art tile of weathered white-grey coastal marble,
> rendered at 1024x1024 as a 64x upscale with hard square pixels.
> Designed to repeat invisibly across a sea-battered cliff face.
> Pale cream and soft grey palette of 6 tones with subtle warm
> undertones. Natural grey vein lines broken into short irregular
> 1 to 3 pixel segments scattered uniformly across the tile. Flat
> matte even lighting throughout. Tiles seamlessly with no edge
> seams.

---

### `snow_all.png`

*(Tier 2 mountain-cap material. The generator overrides the top
voxel of non-cliff columns above the snow line — typically the
upper 500 m of peaks. Should read as bright but not pure white so
it has internal variation under sunlight; cliff faces still poke
through as bare stone.)*

> A 16x16 pixel art tile of fresh dry mountain snow viewed from
> directly above, rendered at 1024x1024 as a 64x upscale with hard
> square pixels. Designed to repeat invisibly across a high alpine
> peak. Approximately 85 percent of the pixels are a single uniform
> bright cool white base color — this dominant color fills the tile
> as undisturbed powdery snow, the soft granular texture of recently
> fallen snow rather than packed ice or slush. Approximately 10
> percent of the pixels are pale blue-grey shadow pockets between
> snow drifts, appearing in random scattered clusters of 2 to 3
> pixels each, never as isolated single pixels and never as
> alternating pairs. Approximately 5 percent of the pixels are
> brighter near-pure-white sparkle highlights as single 1 pixel
> glints at scattered positions across the tile. Most of any given
> row should be the dominant base white, with variation appearing
> only at the shadow-pocket and sparkle positions. Flat top-down
> view, matte even lighting throughout. Tiles seamlessly with no
> edge seams.

---

### `log_top.png`

*(Used for the top and bottom face of the log block. Must tile
seamlessly — a wide tree trunk or horizontal beam spans multiple
adjacent blocks, each showing this face. Do NOT generate a
circular log-slice illustration with a white background. The grain
must fill the entire square tile to all four corners.)*

> A 16x16 pixel art tile of wood end-grain filling the full square
> tile corner to corner, rendered at 1024x1024 as a 64x upscale with
> hard square pixels. Designed to repeat invisibly across the top
> of a multi-block tree trunk or timber beam. Curved annual growth
> lines flowing gently across the entire tile in 1 to 2 pixel arcs
> that reach all four edges. Warm honey-brown palette of 6 tones
> from lighter sapwood to slightly richer areas. No circular
> silhouette, no white or empty corners — the grain covers the
> full square. Flat top-down view, matte even lighting throughout.
> Tiles seamlessly with no edge seams.

---

### `log_side.png`

> A 16x16 pixel art tile of weathered tree bark, rendered at
> 1024x1024 as a 64x upscale with hard square pixels. Designed to
> repeat invisibly up a tall tree trunk. Vertical 1 to 2 pixel
> furrow columns alternating with raised ridges across the tile.
> Dark warm brown palette of 6 tones with slightly lighter ridge
> tops worn smooth by weather. Strong vertical grain direction,
> with furrow widths varying subtly along their length so no
> horizontal band stands out when stacked. Flat matte even lighting
> throughout. Tiles seamlessly with no edge seams.

---

### `leaves_all.png`

*(Generate with a pure white background between leaves. The atlas
builder color-keys white to alpha automatically — you don't need
an RGBA-capable generator.)*

> A 16x16 pixel art tile of dense small rounded forest leaves on a
> pure white background, rendered at 1024x1024 as a 64x upscale with
> hard square pixels. Designed to repeat invisibly across a forest
> canopy. Many small leaf clusters each occupying 1 to 3 pixels,
> spread evenly across the tile with white gap pixels between
> clusters. Deep emerald and forest green palette of 5 tones from
> dark emerald to lighter olive. Roughly 60 percent leaf-pixel
> coverage with white gap pixels uniformly distributed. Flat
> top-down view, matte even lighting throughout. Tiles seamlessly
> with no edge seams.

---

### `copper_ore_all.png`

> A 16x16 pixel art tile of grey stone with veins and flecks of
> copper mineral, rendered at 1024x1024 as a 64x upscale with hard
> square pixels. Designed to repeat invisibly across a cave wall.
> Warm grey stone palette of 4 tones forming the base, with
> scattered raw orange-bronze copper pixels and oxidized blue-green
> patina pixels distributed across the tile. Ore veins broken into
> short irregular 1 to 2 pixel branching segments scattered
> uniformly. Flat matte even lighting throughout. Tiles seamlessly
> with no edge seams.

---

### `iron_ore_all.png`

*(Sibling of `copper_ore_all`. The Tier 4 generator places iron
veins in the shallow band (-50 to 100 m) and copper higher up
(0 to 250 m), so the player digs into one or the other depending
on altitude. Keep the visual clearly distinct from copper — iron's
silvery / rust-red palette vs copper's orange-bronze / green
patina — so the player can tell them apart at a glance
underground.)*

> A 16x16 pixel art tile of grey stone with embedded iron mineral
> deposits, rendered at 1024x1024 as a 64x upscale with hard square
> pixels. Designed to repeat invisibly across a cave wall.
> Approximately 75 percent of the pixels are a single uniform
> medium cool grey base color — this dominant color fills the tile
> as the natural rock surface, like the base color of Minecraft
> stone. Approximately 15 percent of the pixels are slightly darker
> cool grey forming irregular natural rock noise — these darker
> pixels appear in random scattered clusters of 2 to 4 pixels each,
> never as isolated single pixels and never as alternating pairs.
> Approximately 5 percent of the pixels are bright silvery-white
> iron flecks, placed in short irregular vein segments of 1 to 2
> pixels. Approximately 5 percent of the pixels are dark rust-red
> oxidized iron, also in short 1 to 2 pixel vein segments. Most of
> any given row should be the dominant base grey, with variation
> appearing only at the cluster and vein positions. Flat matte even
> lighting throughout. Tiles seamlessly with no edge seams.

---

### `bedrock_all.png`

> A 16x16 pixel art tile of near-black dense igneous stone,
> rendered at 1024x1024 as a 64x upscale with hard square pixels.
> Designed to repeat invisibly across an underground floor. Heavy
> ancient dark surface with very subtle dark-grey mottling. Tight
> 4-tone palette across a narrow contrast range, almost no color
> variation, primarily value variation only. Faint single-pixel
> crystalline specks at uniform density, all of similar weight.
> Flat top-down view, matte even lighting throughout. Tiles
> seamlessly with no edge seams.

---

## Quality checklist (per texture, before saving)

- [ ] **Pixel grid honored?** Zoom in on the 1024x1024 output. Each
  visual "pixel" should be a flat 64x64 block of one solid color
  with hard edges (or 32x32 at 512px output). If you see gradients
  within a pixel block, soft edges between blocks, or the grid
  drifting off the lattice, regenerate. (Some softness is fine —
  the NEAREST downscale will clean it up — but heavy mush means the
  AI ignored the grid rule.)
- [ ] **Tiles seamlessly?** Place 4 copies of the 1024px source in a
  2x2 grid — no visible seam at any edge.
- [ ] **Tiles at 60x without a visible pattern?** Place 8x8 copies
  and scan for any pixel the eye locks onto. If you see a single
  bright pixel, a distinctive vein segment, or an off-color cluster,
  regenerate.
- [ ] **No dominant feature?** No single pixel dramatically
  different from its neighbors.
- [ ] **Limited palette?** 4 to 10 distinct colors per tile. If you
  see dozens of shades, the AI fell back to painterly mode —
  regenerate.
- [ ] **No baked lighting?** No bright highlight in any one corner,
  no cast shadow from an implied light source.
- [ ] **Color in the right zone?** Stone is warm grey-brown, not
  blue; leaves are deep emerald, not lime; clay is cool blue-grey,
  not muddy brown.
- [ ] **Filename matches exactly?** `gravel_all.png`, not
  `Gravel.png` or `gravel.PNG` — the builder is case-sensitive.

When all 15 source PNGs are in place (16 atlas slots minus the
auto-built `grass_side`), run the builder, then reload Godot and
re-run `tools/build_blocky_library.gd` to bake the library against
the new atlas.
