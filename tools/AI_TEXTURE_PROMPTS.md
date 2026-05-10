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
- **File format**: PNG with RGBA (alpha) for `leaves_all`, RGB OK elsewhere
- **Seamless tiling**: required for everything except `log_top`
  - In Midjourney, append `--tile`
  - In DALL-E or Stable Diffusion, "seamlessly tiling" must be in the prompt

## Style prefix

The shared style is anchored to the existing voxel concept art in
`assets/menu_backgrounds/` (campfire cave, forest fight, sailing harbor,
castle feast, battle, fortress night). Painterly medieval voxel —
warm saturated palette, rich internal color variation, no baked
directional lighting on the texture itself.

This **STYLE PREFIX** appears at the top of every prompt below. Paste
the prefix together with the per-material prompt as a single block.

> **STYLE PREFIX:**
> *Seamlessly tiling cubic voxel game block face texture. Painterly
> medieval fantasy art style — rich internal color variation across the
> face, visible material surface grain and texture, warm saturated
> palette. Pure matte albedo with no baked directional lighting and no
> cast shadows. Character: the surface texture quality of a hand-crafted
> medieval RPG voxel world — Minecraft elevated with painterly detail
> and warm material authenticity. 512x512. --tile*

---

## Prompts

### `stone_all.png`
> [STYLE PREFIX] Stone block face texture, warm grey granite with a
> slight brownish undertone (#7A6E63 to #8B7B6B), rough angular surface
> with subtle natural stratification lines running loosely horizontal.
> Slight color temperature variation across the face — warmer at edges,
> cooler at center. Cave wall and cliff character. Not blue-grey —
> warm, ancient, heavy stone.

### `dirt_all.png`
> [STYLE PREFIX] Dirt block face texture, dark rich brown loam (#3A2D1F
> to #4A3828), compact compressed earth with fine soil grain, scattered
> micro-pebbles and faint root fibres. Deep and dark — this is the layer
> under grass, not topsoil. Visible density variation across the face:
> slightly darker patches where moisture is held, slightly lighter where
> dry.

### `grass_top.png`
> [STYLE PREFIX] Grass block top face texture viewed from directly
> above, dense short-cropped grass with vivid color variation from olive
> green (#4A5C28) to bright spring green (#5A7A30). Individual blade
> tips visible, slight directional variation in patches. Saturated and
> lively — not muted or desaturated. Matches the vibrant field greens
> from a sunny medieval outdoor battle scene.

> NOTE: `grass_side.png` and `grass_bottom.png` are auto-built by the
> atlas tool. **Do not generate these.**

### `sand_all.png`
> [STYLE PREFIX] Sand block face texture, pale golden-tan beach sand
> (#C8B580 to #D4C090), fine uniform grain with subtle micro-ripple wind
> patterning. Maritime beach character — the sand of a wave-washed
> shingle shore in a temperate ocean archipelago. Warm and bright, not
> desert sand. Slight luminosity variation across the face from grain
> shadow.

### `gravel_all.png`
> [STYLE PREFIX] Gravel block face texture, mixed grey and warm-brown
> river shingle pebbles (#6B6055 to #7A7A7A), stones ranging from
> pea-sized to fist-sized packed tightly. Wave-scoured shingle beach
> character — irregular stone shapes, slight cool-grey with warm earth
> undertones on individual stones. High color variation across the face;
> each stone reads individually.

### `clay_all.png`
> [STYLE PREFIX] Clay block face texture, smooth blue-grey coastal clay
> (#6B7A88 to #7A8A96), tidal mudflat character — flat compressed
> surface with fine drying-crack network, slight moisture sheen
> suggesting wet intertidal zone. Cool blue-grey, not warm brown. Subtle
> surface texture from compression. Maritime harbor mudflat aesthetic.

### `marble_all.png`
> [STYLE PREFIX] Marble block face texture, weathered white-grey coastal
> stone (#D0C8BC to #E8E0D4) with fine natural grey veining running in
> loose irregular diagonal lines. Surface roughened and pitted from
> centuries of salt wind and wave erosion — not polished interior
> marble, but the bare rock of a sea-battered island pinnacle. Slight
> warm cream cast to the white. This is the material of dramatic ocean
> spires visible from 60km at sea.

### `log_top.png`
> *(Single centered composition. NOT tiling. The atlas builder uses this
> same image for both top and bottom of the log block.)*
>
> Top-down flat texture of a freshly cut coastal pine or oak log end
> face, concentric annual growth rings on honey-brown wood (#8B5E2A),
> fine radial grain lines from center outward, slight heartwood
> darkening at center from deep amber to medium brown. Tightly-packed
> rings suggesting slow coastal growth. Matte albedo, no baked lighting.
> 512×512.

### `log_side.png`
> [STYLE PREFIX] Tree bark side texture for a coastal maritime woodland
> — salt-pine or dwarf-oak bark. Deep vertical furrows with raised
> ridges, dark warm-brown (#3D2510 to #5C3A1A), slightly lighter ridge
> tops worn smooth by weather. Strong vertical grain direction. Rough,
> windswept, old — the bark of a tree that has survived decades of ocean
> storms. Not tropical, not jungle — cold-temperate coastal character.

### `leaves_all.png`
> *(Requires RGBA output with real alpha transparency between leaf
> clusters — let the sky show through.)*
>
> [STYLE PREFIX] Foliage leaf block face texture, dense small rounded
> leaves of dwarf-oak or salt-pine, deep forest green (#2D4A1A to
> #3A5C20) with individual leaf variation from dark emerald to slightly
> lighter olive. Significant pure-black or transparent areas between
> leaf clusters — this block must let sky show through. Dense maritime
> coastal woodland canopy character matching a dark, old-growth island
> forest. Leaves are small and tough — not lush tropical, not sparse
> pine needles. Pure black background between leaf clusters. RGBA with
> alpha transparency.

### `copper_ore_all.png`
> [STYLE PREFIX] Copper ore block face texture, grey stone base
> matching the stone_all texture (#7A6E63) with veins and flecks of
> copper mineral cutting across the face. Copper shows in two states:
> raw orange-bronze (#B87333) where freshly exposed, and oxidized
> blue-green (#4A8A5A) where the surface has weathered. Vein pattern is
> irregular and geological — diagonal and branching, not uniform. This
> is the ore that built the colonial economy of a maritime archipelago.
> Rich, clearly readable mineral against stone.

### `bedrock_all.png`
> [STYLE PREFIX] Bedrock block face texture, near-black dense igneous
> stone (#1E1E24 to #282830), very subtle dark-grey mottling suggesting
> volcanic or deep-sea origin. Almost no color — primarily value
> variation only. Heavy, ancient, impenetrable. Faint texture from
> crystalline grain structure visible only at close inspection. Clearly
> distinct from stone: darker, denser, more uniform. The absolute bottom
> of the world.

---

## Quality checklist (per texture, before saving)

- [ ] **Tiles seamlessly?** Place 4 copies in a 2×2 grid mentally — no
  visible seam at the edges.
- [ ] **No baked lighting?** No bright highlight in any one corner, no
  cast shadow from an implied light source. Even illumination.
- [ ] **Color in the right zone?** Stone is warm grey-brown, not blue;
  leaves are deep emerald, not lime; clay is cool blue-grey, not muddy
  brown.
- [ ] **One distinctive feature isn't dominant?** No single bright pebble
  or weird splotch the eye locks onto — that becomes the obvious
  repetition trigger.
- [ ] **Filename matches exactly?** `gravel_all.png`, not `Gravel.png` or
  `gravel.PNG` — the builder is case-sensitive.

When all 11 source PNGs are in place, run the builder.
