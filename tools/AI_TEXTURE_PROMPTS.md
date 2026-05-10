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
  - Midjourney: append `--tile` to the prompt
  - All other generators: tiling is specified in the prompt text

---

## Prompts

Each prompt below is fully self-contained — copy the entire block as
written into the main prompt field. The shared style and tiling rules
are repeated in every prompt so each one stands alone.

---

### `stone_all.png`

> Generate a seamlessly tiling cubic voxel game block face texture at
> 512×512 for a painterly medieval fantasy RPG. Pure matte albedo with
> no baked directional lighting, no cast shadows, no specular
> highlights. The texture must tile seamlessly with no visible seams at
> any edge — this game runs at 6 voxels per meter, so a single 10-meter
> wall repeats this tile 60+ times. Color variation must be balanced
> and distributed uniformly at fine scale across the entire face: no
> single element dramatically brighter, darker, or more distinctive
> than its neighbors. No corner or edge artifacts.
>
> Material: warm grey granite block face, slight brownish undertone
> (#7A6E63 to #8B7B6B). Rough angular surface, subtle natural
> stratification suggestion. Cave wall and cliff character — warm,
> ancient, heavy, not blue-grey. Multiple fine micro-fracture lines of
> varying short length distributed evenly — no single long crack
> crossing the face.

---

### `dirt_all.png`

> Generate a seamlessly tiling cubic voxel game block face texture at
> 512×512 for a painterly medieval fantasy RPG. Pure matte albedo with
> no baked directional lighting, no cast shadows, no specular
> highlights. The texture must tile seamlessly with no visible seams at
> any edge — this game runs at 6 voxels per meter, so a single 10-meter
> wall repeats this tile 60+ times. Color variation must be balanced
> and distributed uniformly at fine scale across the entire face: no
> single element dramatically brighter, darker, or more distinctive
> than its neighbors. No corner or edge artifacts.
>
> Material: dark rich brown loam (#3A2D1F to #4A3828). Compact
> compressed earth, fine soil grain. Micro-pebbles and faint root
> fibres at uniform density across the whole surface — no single large
> stone or root. Deep and dark: the layer under grass, not topsoil.
> Moisture variation in many small scattered patches, not one large
> dark zone.

---

### `grass_top.png`

> Generate a seamlessly tiling cubic voxel game block face texture at
> 512×512 for a painterly medieval fantasy RPG. Pure matte albedo with
> no baked directional lighting, no cast shadows, no specular
> highlights. The texture must tile seamlessly with no visible seams at
> any edge — this game runs at 6 voxels per meter, so a 10-meter open
> field repeats this tile 60+ times. Color variation must be balanced
> and distributed uniformly at fine scale across the entire face: no
> single element dramatically brighter, darker, or more distinctive
> than its neighbors. No corner or edge artifacts.
>
> Material: top face of a grass block, viewed from directly above.
> Dense short-cropped grass, vivid color from olive green (#4A5C28) to
> bright spring green (#5A7A30). Blade tips visible as a uniform carpet
> of fine texture — many tiny clusters, no single identifiable tuft.
> Color patches small and numerous, scattered at fine scale. Saturated
> and lively, not muted.

> **NOTE:** `grass_side.png` and `grass_bottom.png` are auto-built by
> the atlas tool. **Do not generate these.**

---

### `sand_all.png`

> Generate a seamlessly tiling cubic voxel game block face texture at
> 512×512 for a painterly medieval fantasy RPG. Pure matte albedo with
> no baked directional lighting, no cast shadows, no specular
> highlights. The texture must tile seamlessly with no visible seams at
> any edge — this game runs at 6 voxels per meter, so a single 10-meter
> beach repeats this tile 60+ times. Color variation must be balanced
> and distributed uniformly at fine scale across the entire face: no
> single element dramatically brighter, darker, or more distinctive
> than its neighbors. No corner or edge artifacts.
>
> Material: pale golden-tan beach sand (#C8B580 to #D4C090). Fine
> uniform grain, extremely subtle micro-variation. Maritime beach
> character — a wave-washed shingle shore in a temperate ocean
> archipelago. Warm and bright, not desert sand. Any wind-patterning at
> micro scale only — no macroscopic ripple band or sweep. Grain shadow
> variation in tiny increments uniformly across the face: no bright
> island or dark shadow patch.

---

### `gravel_all.png`

> Generate a seamlessly tiling cubic voxel game block face texture at
> 512×512 for a painterly medieval fantasy RPG. Pure matte albedo with
> no baked directional lighting, no cast shadows, no specular
> highlights. The texture must tile seamlessly with no visible seams at
> any edge — this game runs at 6 voxels per meter, so a single 10-meter
> riverbed repeats this tile 60+ times. Color variation must be
> balanced and distributed uniformly at fine scale across the entire
> face: no single element dramatically brighter, darker, or more
> distinctive than its neighbors. No corner or edge artifacts.
>
> Material: mixed grey and warm-brown river shingle (#6B6055 to
> #7A7A7A). Stones pea-sized to mid-sized, packed tightly. Wave-scoured
> shingle beach character — irregular stone shapes, slight cool-grey
> with warm earth undertones on individual stones. Many stones of
> similar visual weight: no single stone dramatically brighter, darker,
> or more distinctively shaped than its neighbors. Stone size variety
> spread evenly, no large isolated stone.

---

### `clay_all.png`

> Generate a seamlessly tiling cubic voxel game block face texture at
> 512×512 for a painterly medieval fantasy RPG. Pure matte albedo with
> no baked directional lighting, no cast shadows, no specular
> highlights. The texture must tile seamlessly with no visible seams at
> any edge — this game runs at 6 voxels per meter, so a single 10-meter
> mudflat repeats this tile 60+ times. Color variation must be balanced
> and distributed uniformly at fine scale across the entire face: no
> single element dramatically brighter, darker, or more distinctive
> than its neighbors. No corner or edge artifacts.
>
> Material: smooth blue-grey coastal clay (#6B7A88 to #7A8A96). Tidal
> mudflat character — flat compressed surface. Fine drying-crack
> network distributed uniformly at small scale: many short thin
> irregular hairline cracks, no single long or prominent crack crossing
> the face. Slight moisture variation suggesting wet intertidal zone,
> scattered in many tiny zones, not one large sheen region. Cool
> blue-grey, not warm brown.

---

### `marble_all.png`

> Generate a seamlessly tiling cubic voxel game block face texture at
> 512×512 for a painterly medieval fantasy RPG. Pure matte albedo with
> no baked directional lighting, no cast shadows, no specular
> highlights. The texture must tile seamlessly with no visible seams at
> any edge — this game runs at 6 voxels per meter, so a single 10-meter
> cliff face repeats this tile 60+ times. Color variation must be
> balanced and distributed uniformly at fine scale across the entire
> face: no single element dramatically brighter, darker, or more
> distinctive than its neighbors. No corner or edge artifacts.
>
> Material: weathered white-grey coastal stone (#D0C8BC to #E8E0D4).
> Surface roughened and pitted from centuries of salt wind and wave
> erosion — not polished interior marble, but bare sea-battered rock.
> Slight warm cream cast. Natural grey veining broken into many short
> irregular segments scattered across the face: no single long
> continuous diagonal vein crossing edge to edge. Pitting distributed
> uniformly.

---

### `log_top.png`

> *(Single centered composition. NOT seamlessly tiling. Used for both
> the top and bottom face of the log block. The circular cut-end fills
> the full 512×512 face.)*
>
> Generate a top-down flat texture at 512×512 for a painterly medieval
> fantasy RPG voxel block. Pure matte albedo with no baked directional
> lighting and no cast shadows. The image is the freshly cut end of a
> coastal pine or oak log. Concentric annual growth rings on
> honey-brown wood (#8B5E2A), fine radial grain lines from center
> outward, slight heartwood darkening at center from deep amber to
> medium brown. Tightly-packed rings suggesting slow coastal growth.
> Circular cross-section fills the frame edge to edge.

---

### `log_side.png`

> Generate a seamlessly tiling cubic voxel game block face texture at
> 512×512 for a painterly medieval fantasy RPG. Pure matte albedo with
> no baked directional lighting, no cast shadows, no specular
> highlights. The texture must tile seamlessly with no visible seams at
> any edge — this game runs at 6 voxels per meter, so a single tall
> tree trunk repeats this tile vertically many times. Color variation
> must be balanced and distributed uniformly at fine scale across the
> entire face: no single element dramatically brighter, darker, or more
> distinctive than its neighbors. No corner or edge artifacts.
>
> Material: tree bark for a coastal maritime woodland — salt-pine or
> dwarf-oak. Deep vertical furrows with raised ridges, dark warm-brown
> (#3D2510 to #5C3A1A), slightly lighter ridge tops worn smooth by
> weather. Strong vertical grain direction. Rough, windswept, old —
> decades of ocean storms. Furrow depth and ridge width varies subtly
> along their length so no horizontal band repeats when tiled
> vertically. Dark furrow zones and lighter ridge zones at similar
> visual weight, no single ridge crest dramatically brighter than
> others.

---

### `leaves_all.png`

> *(Requires RGBA output — transparent or pure-black background between
> leaf clusters so sky shows through in the game engine.)*
>
> Generate a seamlessly tiling cubic voxel game block face texture at
> 512×512 with alpha transparency, for a painterly medieval fantasy
> RPG. Pure matte albedo with no baked directional lighting, no cast
> shadows, no specular highlights. The texture must tile seamlessly
> with no visible seams at any edge — this game runs at 6 voxels per
> meter, so a forest canopy repeats this tile 60+ times. Color
> variation must be balanced and distributed uniformly at fine scale
> across the entire face: no single element dramatically brighter,
> darker, or more distinctive than its neighbors. No corner or edge
> artifacts.
>
> Material: dense small rounded leaves of dwarf-oak or salt-pine, deep
> forest green (#2D4A1A to #3A5C20), individual leaf variation from
> dark emerald to slightly lighter olive. Many small leaf clusters of
> similar size and density distributed uniformly — no single large
> dense cluster and no single large isolated transparent gap that
> repeats visibly. Small tough leaves — not lush tropical, not sparse
> pine needles. Maritime coastal woodland canopy character. Leaf
> coverage roughly 55–65% of the face, transparent regions spread
> uniformly throughout. RGBA PNG with alpha transparency.

---

### `copper_ore_all.png`

> Generate a seamlessly tiling cubic voxel game block face texture at
> 512×512 for a painterly medieval fantasy RPG. Pure matte albedo with
> no baked directional lighting, no cast shadows, no specular
> highlights. The texture must tile seamlessly with no visible seams at
> any edge — this game runs at 6 voxels per meter, so a single
> 10-meter cave wall repeats this tile 60+ times. Color variation must
> be balanced and distributed uniformly at fine scale across the entire
> face: no single element dramatically brighter, darker, or more
> distinctive than its neighbors. No corner or edge artifacts.
>
> Material: grey stone base matching warm grey granite (#7A6E63) with
> veins and flecks of copper mineral scattered across the face. Copper
> in two states: raw orange-bronze (#B87333) where freshly exposed,
> oxidized blue-green (#4A8A5A) where weathered. Ore vein pattern
> broken into multiple short irregular branching segments distributed
> across the face — no single long continuous vein crossing edge to
> edge. Copper fleck clusters of similar size at even density: no
> isolated large copper patch dominant.

---

### `bedrock_all.png`

> Generate a seamlessly tiling cubic voxel game block face texture at
> 512×512 for a painterly medieval fantasy RPG. Pure matte albedo with
> no baked directional lighting, no cast shadows, no specular
> highlights. The texture must tile seamlessly with no visible seams at
> any edge — this is the bottom of the world and tiles 60+ times across
> any underground floor. Color variation must be balanced and
> distributed uniformly at fine scale across the entire face: no single
> element dramatically brighter, darker, or more distinctive than its
> neighbors. No corner or edge artifacts.
>
> Material: near-black dense igneous stone (#1E1E24 to #282830). Very
> subtle dark-grey mottling suggesting volcanic or deep-sea origin:
> many tiny tonal variations at fine grain, uniformly distributed, no
> single darker or lighter zone dominant. Almost no color — primarily
> value variation only, range between lightest and darkest tones very
> narrow. Heavy, ancient, impenetrable. Faint crystalline grain
> structure at micro scale only. Clearly distinct from stone: darker,
> denser, more uniform.

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
