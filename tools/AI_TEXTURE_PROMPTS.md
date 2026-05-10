# AI Texture Prompts — Default Pack

Use these prompts to generate the source images for the default voxel
texture pack. Each prompt produces one face texture. Save the output to
the **exact filename** indicated under each prompt into:

    assets/voxels/texture_packs/default/source/

After generating all the textures, run from the repo root:

    python tools/build_texture_atlas.py default

That packs the source PNGs into `atlas.png` and writes a manifest the
game can load.

## Generation settings

- **Output size**: 512×512 (the builder downscales to 32×32 for the atlas)
- **File format**: PNG. RGB is fine for everything — for `leaves_all`,
  the atlas builder color-keys the white background to alpha at build
  time, so you don't need a generator that outputs true RGBA.
- **Seamless tiling**: required for everything except `log_top`. Tiling
  is requested in the per-material prompts below.

## How to use these prompts

This file is split into two parts:

1. **SYSTEM PROMPT** — paste once into the system / style / context
   field of your image generator. Carries all the shared style, tiling
   rules, and game context.
2. **Per-material prompts** — short, pure-descriptive blocks. Paste one
   into the main prompt field for each texture you generate.

### Why split

When the system instructions and the per-material details were combined
into one prompt, Gemini Nano Banana 2's recitation filter rejected
every prompt. The filter trips when one prompt block stacks too many
specific signals at once (named genre + hex codes + heavy negations +
imperative voice + game-asset framing). Splitting the load — system
field carries the meta, main prompt carries pure visual description —
is what actually works in practice. This pairing has been tested
working with Gemini Nano Banana 2.

If your generator has no separate system field, paste the SYSTEM
PROMPT first then the per-material prompt as one continuous block.

---

## SYSTEM PROMPT

*Paste this once into the system / style / context field.*

> You are generating seamlessly tiling cubic voxel game block face
> textures for a painterly medieval fantasy RPG. Output size: 512×512.
>
> Art style: Painterly medieval fantasy. Rich internal color variation
> spread uniformly across the face. Visible material surface grain and
> texture. Warm saturated palette. Pure matte albedo — no baked
> directional lighting anywhere on the face, no cast shadows, no
> specular highlights. Character: the surface quality of a hand-crafted
> medieval RPG voxel world — Minecraft elevated with painterly detail
> and warm material authenticity.
>
> Tiling requirement: Every texture must tile seamlessly with no
> visible seams at any edge. This game runs at 6 voxels per meter —
> each voxel face is ~16.7 cm — so a single 10-meter stone wall repeats
> the tile 60+ times. Any dominant feature (a single bright pebble, a
> long crack, an off-color patch, a tonal island) becomes a visible
> repeating grid the player cannot unsee. Color variation must be
> balanced and distributed uniformly at fine scale across the entire
> face: no single element dramatically brighter, darker, or more
> distinctive than its neighbors. No corner or edge artifacts that
> create banding when tiled.

---

## Per-material prompts

*Paste one of these into the main prompt field for each generation.
Each is short, pure descriptive imagery — the kind of prompt the
recitation filter accepts.*

---

### `stone_all.png`

> A square seamless tileable texture of warm grey granite stone,
> designed to repeat invisibly across a cliff face. Rough angular
> surface spread evenly across the whole face with balanced color
> across all areas. Warm grey tones with subtle brownish undertones,
> ancient heavy stone character. Many fine short micro-fractures
> scattered uniformly across the surface, all of similar weight, with
> no single long crack standing out. Flat view, matte even lighting
> throughout. Hand-painted painterly art style. Tiles seamlessly with
> no edge seams.

---

### `dirt_all.png`

> A square seamless tileable texture of dark rich brown loam soil,
> designed to repeat invisibly across an underground wall. Compact
> compressed earth with fine soil grain spread evenly across the whole
> surface with balanced color across all areas. Deep dark warm brown
> tones, the layer found under grass rather than topsoil. Tiny
> scattered micro-pebbles and faint root fibres at uniform density,
> all of similar size. Flat view, matte even lighting throughout.
> Hand-painted painterly art style. Tiles seamlessly with no edge
> seams.

---

### `grass_top.png`

> A square seamless tileable texture of dense short-cropped grass
> viewed from directly above, designed to repeat invisibly across an
> open field. Uniform carpet of fine grass blade tips spread evenly
> across the whole surface with balanced color across all areas.
> Vivid saturated green tones, olive green blending softly into bright
> spring green in many tiny clusters of similar size. Flat top-down
> view, matte even lighting throughout. Hand-painted painterly art
> style. Tiles seamlessly with no edge seams.

> **NOTE:** `grass_side.png` and `grass_bottom.png` are auto-built by
> the atlas tool. **Do not generate these.**

---

### `sand_all.png`

> A square seamless tileable texture of fine pale golden beach sand,
> designed to repeat invisibly across a beach surface. Uniform fine
> grain spread evenly across the whole surface with balanced color
> across all areas. Warm bright tan and cream tones, soft golden
> highlights blending into pale warm beige. Flat top-down view, matte
> even lighting throughout. Hand-painted painterly art style. Tiles
> seamlessly with no edge seams.

---

### `gravel_all.png`

> A square seamless tileable texture of mixed grey and warm-brown
> river shingle pebbles, designed to repeat invisibly across a
> riverbed surface. Small to mid-sized pebbles packed tightly and
> spread evenly across the whole surface with balanced color across
> all areas. Cool grey stones with warm earth-tone undertones,
> irregular pebble shapes all of similar visual weight. Flat top-down
> view, matte even lighting throughout. Hand-painted painterly art
> style. Tiles seamlessly with no edge seams.

---

### `clay_all.png`

> A square seamless tileable texture of smooth blue-grey coastal clay,
> designed to repeat invisibly across a tidal mudflat surface. Flat
> compressed surface with a fine drying-crack network spread evenly
> across the whole surface with balanced color across all areas. Cool
> blue-grey tones with subtle moisture variation. Many short thin
> irregular hairline cracks scattered uniformly, all of similar
> weight. Flat top-down view, matte even lighting throughout.
> Hand-painted painterly art style. Tiles seamlessly with no edge
> seams.

---

### `marble_all.png`

> A square seamless tileable texture of weathered white-grey coastal
> marble, designed to repeat invisibly across a sea-battered cliff
> face. Roughened pitted surface spread evenly across the whole face
> with balanced color across all areas. Pale cream and soft grey tones
> with subtle warm undertones, the bare rock of an ocean pinnacle
> rather than polished interior marble. Natural grey veining broken
> into many short irregular segments scattered uniformly. Flat view,
> matte even lighting throughout. Hand-painted painterly art style.
> Tiles seamlessly with no edge seams.

---

### `log_top.png`

*(Used for the top and bottom face of the log block. Must tile
seamlessly -- a wide tree trunk or horizontal beam spans multiple
adjacent blocks, each showing this face. Do NOT generate a circular
log-slice illustration with a white background. The grain must fill
the entire square face to all four corners.)*

> A square seamless tileable texture of wood end-grain filling the
> full square face corner to corner, designed to repeat invisibly
> across the top of a multi-block tree trunk or timber beam. Curved
> annual growth lines flowing gently across the entire face, reaching
> all four edges, warm honey-brown tones with subtle variation from
> lighter sapwood to slightly richer areas. No circular silhouette,
> no white or empty corners -- the grain covers the full square. Many
> softly curved grain lines spread evenly across the whole surface
> with balanced color across all areas. Flat top-down view, matte
> even lighting throughout. Hand-painted painterly art style. Tiles
> seamlessly with no edge seams.

---

### `log_side.png`

> A square seamless tileable texture of weathered tree bark, designed
> to repeat invisibly up a tall tree trunk. Deep vertical furrows with
> raised ridges spread evenly across the whole face with balanced
> color across all areas. Dark warm brown tones with slightly lighter
> ridge tops worn smooth by weather, strong vertical grain direction.
> Furrow depth and ridge width vary subtly along their length so no
> horizontal band stands out when stacked. Flat view, matte even
> lighting throughout. Hand-painted painterly art style. Tiles
> seamlessly with no edge seams.

---

### `leaves_all.png`

*(Generate with a pure white background between leaves. The atlas
builder color-keys white to alpha automatically — you don't need an
RGBA-capable generator.)*

> A square seamless tileable texture of dense small rounded forest
> leaves on a pure white background, designed to repeat invisibly
> across a forest canopy. Many small leaf clusters of similar size and
> density spread evenly across the whole surface with balanced color
> across all areas. Deep emerald and forest green tones with individual
> leaf variation from dark emerald to lighter olive, leaves small and
> tough rather than lush tropical or sparse pine needles. Roughly 60
> percent leaf coverage with white gaps spread uniformly between
> clusters. Flat top-down view, matte even lighting throughout.
> Hand-painted painterly art style. Tiles seamlessly with no edge
> seams.

---

### `copper_ore_all.png`

> A square seamless tileable texture of grey stone with veins and
> flecks of copper mineral, designed to repeat invisibly across a
> cave wall. Stone base with scattered copper deposits spread evenly
> across the whole face with balanced color across all areas. Warm
> grey stone tones with raw orange-bronze copper and oxidized
> blue-green patina mineral. Ore veins broken into many short
> irregular branching segments scattered uniformly across the face,
> with copper fleck clusters of similar size at even density. Flat
> view, matte even lighting throughout. Hand-painted painterly art
> style. Tiles seamlessly with no edge seams.

---

### `bedrock_all.png`

> A square seamless tileable texture of near-black dense igneous
> stone, designed to repeat invisibly across an underground floor.
> Heavy ancient dark surface with very subtle dark-grey mottling
> spread evenly across the whole face with balanced color across all
> areas. Almost no color variation, primarily value variation only
> with a very narrow contrast range. Faint crystalline grain structure
> at micro scale only, all of similar weight. Flat top-down view,
> matte even lighting throughout. Hand-painted painterly art style.
> Tiles seamlessly with no edge seams.

---

## Quality checklist (per texture, before saving)

- [ ] **Tiles seamlessly?** Place 4 copies in a 2×2 grid — no visible
  seam at any edge.
- [ ] **Tiles at 60× without a visible pattern?** Place 8×8 copies and
  scan for any element the eye locks onto — a single bright pebble, a
  distinctive crack, an off-color patch. If you see it, regenerate.
- [ ] **No dominant feature?** No single stone, vein, gap, or tonal
  island dramatically different from its neighbors.
- [ ] **No baked lighting?** No bright highlight in any one corner, no
  cast shadow from an implied light source. Even illumination.
- [ ] **Color in the right zone?** Stone is warm grey-brown, not blue;
  leaves are deep emerald, not lime; clay is cool blue-grey, not muddy
  brown.
- [ ] **Filename matches exactly?** `gravel_all.png`, not `Gravel.png`
  or `gravel.PNG` — the builder is case-sensitive.

When all 11 source PNGs are in place, run the builder.
