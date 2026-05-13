# AI Texture Prompts — Default Pack (16x16 Pixel Art)

Use these prompts to generate the source images for the default voxel
texture pack. Each prompt produces one face texture. Save the output
to the **exact filename** indicated under each prompt into:

    assets/voxels/texture_packs/default/source/

After generating all the textures, run from the repo root:

    python tools/build_texture_atlas.py default

That nearest-neighbour-downscales the source PNGs to 16x16 each,
packs them into `atlas.png`, and writes the manifest the game loads.

## Generation settings

- **Output size**: 512x512 (the builder downscales to 16x16 for the
  atlas). The 512 figure is **not arbitrary** — it is 16 x 32, which
  means every 32x32 block of pixels in the source becomes a single
  pixel after NEAREST downscale. The whole prompt strategy hinges on
  that 32x upscale being clean.
- **File format**: PNG. RGB is fine for everything — for `leaves_all`,
  the atlas builder color-keys the white background to alpha at build
  time, so you don't need an RGBA-capable generator.
- **Seamless tiling**: required for everything except `log_top`.
  Tiling is requested in the per-material prompts below.

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

## Will Nano Banana actually output pixel art?

**Honest answer: not reliably on its own.** Diffusion image models
(Gemini Nano Banana 2, DALL-E, Midjourney, Stable Diffusion in default
modes) are trained on photographs and digital paintings, not pixel
art. Asked for "pixel art," they typically produce *fake pixel art* —
soft, anti-aliased imagery with gradients between pixels, a
ghost-pixel grid that drifts across the image, occasional sub-pixel
detail. Looks pixel-ish at thumbnail size; falls apart on close
inspection.

**Why our pipeline still gets crisp pixels out of it:**

1. The builder downscales 512 -> 16 using **nearest-neighbour**, not
   LANCZOS. That collapses 32x32 source pixels into a single output
   pixel — picking one source pixel, throwing away the other 1023.
   Any sub-pixel softness, anti-aliasing, or drift in the source is
   simply discarded. The output is mathematically pixel-perfect even
   if the input was mush.
2. The in-game atlas material uses `TEXTURE_FILTER_NEAREST`
   (`tools/build_blocky_library.gd:135`), so the GPU never blurs the
   16 px tile when sampling it onto a voxel face. The pixels stay
   crisp at any draw size.

**What we're really asking the AI to do** is be a *color and
composition machine*. The prompt asks for a 16x16 image upscaled to
512x512 with clean square pixels and a limited palette — the AI tries
to honor that, fails to honor it perfectly, but gets close enough
that the nearest-neighbour downscale recovers a clean 16 px image
with the right colors and the right large-scale shapes (vein
direction, leaf-cluster spacing, sand-grain density). It's a
denoising-by-downsampling trick: the AI provides intent, the
downscale enforces the grid.

**Recommended generators**, in order of how reliably they produce
clean pixel input:

1. **Gemini Nano Banana 2** with the SYSTEM PROMPT below — works
   well enough for our 15 source images and is already wired into
   the rest of the asset pipeline (`design/ASSET_PIPELINE_AI.md`).
   Expect 1-3 regenerations per material to get a usable result.
2. **DALL-E 3 / Midjourney v6** — similar quality, sometimes
   cleaner pixel grids, sometimes worse. Worth a shot if Gemini
   keeps producing mush on a specific material.
3. **Aseprite or Pixilart by hand** — if you want a truly authored
   look. Make 16x16 PNGs directly, name them per the layout below,
   set the builder's NEAREST downscale will leave them untouched
   (no resize happens when input size already matches target).
4. **Retrodiffusion / PixelLab.ai** — dedicated pixel-art diffusion
   services. They produce real pixel art at the target resolution
   directly. Output is usually 32x32 or 64x64; the NEAREST downscale
   to 16 will still work but you lose some detail. Recommended only
   if Gemini keeps failing on a particular material.

**Cheap quality check before saving:** the AI output will look "soft"
at 512x512. That's fine — what matters is what falls out of the
downscale. The builder prints `[atlas]` summary at the end of every
run, and you can sanity-check by zooming in on `atlas.png` afterward
to see if each 16x16 tile reads as the material you wanted. If a tile
looks like grey noise rather than stone-with-cracks, that prompt
needs another roll.

---

## SYSTEM PROMPT

*Paste this once into the system / style / context field.*

> You are generating seamlessly tiling 16x16 pixel art block face
> textures for a medieval fantasy voxel RPG. Output size: 512x512,
> rendered as a 32x nearest-neighbor upscale of an underlying 16x16
> pixel-art tile.
>
> Pixel grid rule: The image must read as exactly 16x16 large square
> pixels arranged in a 16x16 grid. Each pixel is a flat 32x32 block of
> solid uniform color. No gradients between pixels, no anti-aliasing,
> no soft edges, no blur, no dithering across pixel boundaries.
> Adjacent pixels meet at hard square edges. The pixel grid must be
> axis-aligned: every pixel boundary falls on multiples of 32px.
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
> 512x512 as a 32x upscale with hard square pixels. Designed to
> repeat invisibly across a cliff face. Warm grey palette of 6 tones
> from dark charcoal to pale highlight, with subtle brownish
> undertones. Many short 1 to 2 pixel micro-fractures scattered
> uniformly across the tile, all of similar weight, no single long
> crack standing out. Flat matte even lighting throughout. Tiles
> seamlessly with no edge seams.

---

### `stone_dark_all.png`

*(Sibling of `stone_all`. The Tier 3 generator rule mixes this in
as ~17% darker patches inside the stone band so cliff faces and
underground walls show three-tone variety — plain stone, dark
stone, rare marble — rather than uniform grey.)*

> A 16x16 pixel art tile of cool dark grey basalt stone, rendered
> at 512x512 as a 32x upscale with hard square pixels. Designed to
> repeat invisibly across a deep cave wall. Deep charcoal grey
> palette of 6 tones with subtle cool blue-grey undertones, the
> heavy dense character of dark volcanic rock that contrasts
> visibly against ordinary warm granite. Many short 1 to 2 pixel
> micro-fractures and tiny scattered mineral specks at uniform
> density, all of similar weight. Flat matte even lighting
> throughout. Tiles seamlessly with no edge seams.

---

### `dirt_all.png`

> A 16x16 pixel art tile of dark rich brown loam soil, rendered at
> 512x512 as a 32x upscale with hard square pixels. Designed to
> repeat invisibly across an underground wall. Deep warm brown
> palette of 6 tones, the layer found under grass rather than
> topsoil. Tiny scattered micro-pebbles and faint root flecks at
> uniform density, each occupying 1 to 2 pixels. Flat matte even
> lighting throughout. Tiles seamlessly with no edge seams.

---

### `grass_top.png`

> A 16x16 pixel art tile of dense short-cropped grass viewed from
> directly above, rendered at 512x512 as a 32x upscale with hard
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
> at 512x512 as a 32x upscale with hard square pixels. Designed to
> repeat invisibly across a beach surface. Warm tan and cream
> palette of 5 tones, soft golden highlights blending into pale
> warm beige across the pixel grid. Single-pixel grain variation
> uniformly distributed. Flat top-down view, matte even lighting
> throughout. Tiles seamlessly with no edge seams.

---

### `gravel_all.png`

> A 16x16 pixel art tile of mixed grey and warm-brown river shingle
> pebbles, rendered at 512x512 as a 32x upscale with hard square
> pixels. Designed to repeat invisibly across a riverbed surface.
> Cool grey palette with warm earth-tone undertones, 7 tones total.
> Small pebbles each occupying a 1 to 2 pixel cluster, packed
> tightly with hard-edged pixel boundaries between adjacent stones,
> all of similar visual weight. Flat top-down view, matte even
> lighting throughout. Tiles seamlessly with no edge seams.

---

### `clay_all.png`

> A 16x16 pixel art tile of smooth blue-grey coastal clay, rendered
> at 512x512 as a 32x upscale with hard square pixels. Designed to
> repeat invisibly across a tidal mudflat surface. Cool blue-grey
> palette of 5 tones with subtle moisture variation. Many short 1
> to 2 pixel hairline crack lines scattered uniformly, all of
> similar weight. Flat top-down view, matte even lighting
> throughout. Tiles seamlessly with no edge seams.

---

### `marble_all.png`

> A 16x16 pixel art tile of weathered white-grey coastal marble,
> rendered at 512x512 as a 32x upscale with hard square pixels.
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
> directly above, rendered at 512x512 as a 32x upscale with hard
> square pixels. Designed to repeat invisibly across a high alpine
> peak. Cool white palette of 4 tones with very subtle pale blue
> and faint warm cream undertones from low-angle light. Tiny
> single-pixel sparkle highlights and faint single-pixel shadow
> pockets scattered uniformly, all of similar weight. Flat top-down
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
> tile corner to corner, rendered at 512x512 as a 32x upscale with
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
> 512x512 as a 32x upscale with hard square pixels. Designed to
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
> pure white background, rendered at 512x512 as a 32x upscale with
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
> copper mineral, rendered at 512x512 as a 32x upscale with hard
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

> A 16x16 pixel art tile of grey stone with veins and flecks of
> iron mineral, rendered at 512x512 as a 32x upscale with hard
> square pixels. Designed to repeat invisibly across a cave wall.
> The stone base is an irregular natural-looking mottle of 4 cool
> grey tones, with each grey tone forming small organic clusters of
> 2 to 5 pixels at random positions across the tile. The stone
> base must NOT be a checkerboard pattern, must NOT alternate two
> tones every pixel, must NOT form any regular two-tone grid — a
> checkerboard would read as a transparency-grid artifact rather
> than as natural rock and is a failure. Adjacent stone pixels are
> usually the same tone; tone changes happen at the boundaries
> between clusters, not at every pixel. On top of that mottled
> stone base, place scattered raw silvery-grey iron pixels and
> dark rust-red oxidized iron pixels as ore. Ore veins broken into
> short irregular 1 to 2 pixel branching segments scattered
> uniformly across the tile. Flat matte even lighting throughout.
> Tiles seamlessly with no edge seams.

---

### `bedrock_all.png`

> A 16x16 pixel art tile of near-black dense igneous stone,
> rendered at 512x512 as a 32x upscale with hard square pixels.
> Designed to repeat invisibly across an underground floor. Heavy
> ancient dark surface with very subtle dark-grey mottling. Tight
> 4-tone palette across a narrow contrast range, almost no color
> variation, primarily value variation only. Faint single-pixel
> crystalline specks at uniform density, all of similar weight.
> Flat top-down view, matte even lighting throughout. Tiles
> seamlessly with no edge seams.

---

## Quality checklist (per texture, before saving)

- [ ] **Pixel grid honored?** Zoom in on the 512x512 output. Each
  visual "pixel" should be a flat 32x32 block of one solid color
  with hard edges. If you see gradients within a pixel block, soft
  edges between blocks, or the grid drifting off the 32px lattice,
  regenerate. (Some softness is fine — the NEAREST downscale will
  clean it up — but heavy mush means the AI ignored the grid rule.)
- [ ] **Tiles seamlessly?** Place 4 copies of the 512px source in a
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
