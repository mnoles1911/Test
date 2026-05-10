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

## Tiling scale context

At 6 voxels per meter (each voxel face ~16.7 cm), a 10-meter stone wall
repeats the same tile 60 times. The player sees these textures at close
range constantly. Any dominant feature — a single bright pebble, an
obvious vein, a lone crack, an off-color patch — becomes an instantly
visible repeating pattern. Every prompt below asks for **balanced color
distribution with no dominant element**, meaning: spread color variation
across the entire face uniformly, avoid any one shape or tonal region
the eye can lock onto, and ensure no corner or edge artifact that
creates a seam-like band when tiled.

---

## Prompts

Each prompt below is self-contained — copy the full block as written.

---

### `stone_all.png`

> Seamlessly tiling cubic voxel game block face texture, designed to
> tile 60+ times across a stone wall without revealing any repeating
> element. Painterly medieval fantasy art style — warm grey granite with
> a slight brownish undertone (#7A6E63 to #8B7B6B), rough angular
> surface with subtle natural stratification suggestion. Rich internal
> color variation spread uniformly across the entire face: warmer and
> cooler zones scattered throughout with no single patch dominant. Cave
> wall and cliff character — warm, ancient, heavy stone, not blue-grey.
> Balanced color distribution: no single bright spot, dark spot, or
> distinctive crack the eye can lock onto when the texture repeats.
> Multiple fine micro-fracture lines of varying length distributed
> evenly — no single long crack crossing the face. Pure matte albedo
> with no baked directional lighting and no cast shadows. No corner or
> edge artifacts. Character: the surface quality of a hand-crafted
> medieval RPG voxel world — Minecraft elevated with painterly detail
> and warm material authenticity. 512×512. --tile

---

### `dirt_all.png`

> Seamlessly tiling cubic voxel game block face texture, designed to
> tile 60+ times on underground and hillside surfaces without revealing
> a repeating pattern. Painterly medieval fantasy art style — dark rich
> brown loam (#3A2D1F to #4A3828), compact compressed earth with fine
> soil grain spread uniformly across the face. Micro-pebbles and faint
> root fibres distributed with even density across the whole surface —
> no single large stone, root, or feature the eye can lock onto. Deep
> and dark: the layer under grass, not topsoil. Moisture variation
> scattered across the face in small, numerous patches rather than one
> large dark zone. Balanced color distribution: the tonal variation
> between lightest and darkest areas is subtle, spread in many small
> regions, no dominant element. Pure matte albedo with no baked
> directional lighting and no cast shadows. No corner or edge artifacts.
> Character: the surface quality of a hand-crafted medieval RPG voxel
> world — Minecraft elevated with painterly detail and warm material
> authenticity. 512×512. --tile

---

### `grass_top.png`

> Seamlessly tiling cubic voxel game block face texture viewed from
> directly above, designed to tile 60+ times across an open field
> without revealing any repeating blade clump or color patch. Painterly
> medieval fantasy art style — dense short-cropped grass with vivid
> color variation from olive green (#4A5C28) to bright spring green
> (#5A7A30). Blade tips visible but distributed as a uniform carpet of
> fine texture — many small clusters, no single identifiable clump or
> tuft dominant. Color patches small and numerous: the warm and cool
> green zones scattered at fine scale across the whole face. Saturated
> and lively, not muted or desaturated. Matches the vibrant field greens
> of a sunny medieval outdoor scene. Balanced color distribution: no
> bright or dark island the eye can lock onto at tiling scale. Pure
> matte albedo with no baked directional lighting and no cast shadows.
> No corner or edge artifacts. Character: the surface quality of a
> hand-crafted medieval RPG voxel world — Minecraft elevated with
> painterly detail and warm material authenticity. 512×512. --tile

> **NOTE:** `grass_side.png` and `grass_bottom.png` are auto-built by
> the atlas tool. **Do not generate these.**

---

### `sand_all.png`

> Seamlessly tiling cubic voxel game block face texture, designed to
> tile 60+ times on a beach without any ripple or grain cluster becoming
> visible as a repeating element. Painterly medieval fantasy art style —
> pale golden-tan beach sand (#C8B580 to #D4C090), fine uniform grain
> with extremely subtle micro-variation. Maritime beach character: the
> sand of a wave-washed shingle shore in a temperate ocean archipelago.
> Warm and bright, not desert sand. Any wind-patterning is at micro
> scale — no macroscopic ripple band or sweep that becomes obvious when
> tiled. Grain shadow variation scattered uniformly across the face in
> tiny increments: no bright island or dark shadow patch. Balanced color
> distribution: the lightest and darkest tones differ subtly, spread
> uniformly with no dominant feature. Pure matte albedo with no baked
> directional lighting and no cast shadows. No corner or edge artifacts.
> Character: the surface quality of a hand-crafted medieval RPG voxel
> world — Minecraft elevated with painterly detail and warm material
> authenticity. 512×512. --tile

---

### `gravel_all.png`

> Seamlessly tiling cubic voxel game block face texture, designed to
> tile 60+ times on a riverbed or shingle beach without any single stone
> becoming the identifiable repeating anchor. Painterly medieval fantasy
> art style — mixed grey and warm-brown river shingle pebbles (#6B6055
> to #7A7A7A), stones ranging from pea-sized to mid-sized packed
> tightly. Wave-scoured shingle beach character — irregular stone
> shapes, slight cool-grey with warm earth undertones. High overall
> color variation but distributed uniformly: many stones of similar
> visual weight, no single stone dramatically brighter, darker, or
> differently shaped than its neighbors. The eye should see a field of
> pebbles, not one particular pebble. Stone size variety spread evenly
> with no large isolated stone. Pure matte albedo with no baked
> directional lighting and no cast shadows. No corner or edge artifacts.
> Character: the surface quality of a hand-crafted medieval RPG voxel
> world — Minecraft elevated with painterly detail and warm material
> authenticity. 512×512. --tile

---

### `clay_all.png`

> Seamlessly tiling cubic voxel game block face texture, designed to
> tile 60+ times on coastal mudflats without any single crack or damp
> patch becoming an obvious repeating element. Painterly medieval
> fantasy art style — smooth blue-grey coastal clay (#6B7A88 to
> #7A8A96), tidal mudflat character — flat compressed surface. A fine
> drying-crack network distributed uniformly at small scale across the
> whole face: many short, thin, irregular hairline cracks, no single
> long or prominent crack crossing the face. Slight moisture variation
> suggesting wet intertidal zone, scattered in many tiny zones rather
> than one large sheen region. Cool blue-grey, not warm brown. Balanced
> color distribution: no dominant tonal island, the cracking pattern at
> equal visual density across all areas. Pure matte albedo with no baked
> directional lighting and no cast shadows. No corner or edge artifacts.
> Character: the surface quality of a hand-crafted medieval RPG voxel
> world — Minecraft elevated with painterly detail and warm material
> authenticity. 512×512. --tile

---

### `marble_all.png`

> Seamlessly tiling cubic voxel game block face texture, designed to
> tile 60+ times on ocean-spire cliffs without any vein or stain
> becoming an obvious repeating element. Painterly medieval fantasy art
> style — weathered white-grey coastal stone (#D0C8BC to #E8E0D4),
> surface roughened and pitted from centuries of salt wind and wave
> erosion — not polished interior marble, but bare sea-battered rock.
> Slight warm cream cast to the white. Natural grey veining present but
> broken into many short irregular segments scattered across the face:
> no single long continuous diagonal vein crossing the face from edge to
> edge. Pitting and surface texture distributed uniformly. Balanced
> color distribution: the creamy white and grey zones interspersed at
> small scale across the face, no single large pale or dark island. Pure
> matte albedo with no baked directional lighting and no cast shadows.
> No corner or edge artifacts. Character: the surface quality of a
> hand-crafted medieval RPG voxel world — Minecraft elevated with
> painterly detail and warm material authenticity. 512×512. --tile

---

### `log_top.png`

> *(Single centered composition. NOT seamlessly tiling. Used for both
> the top and bottom face of the log block. The circular cut-end fills
> the full 512×512 face.)*
>
> Top-down flat texture of a freshly cut coastal pine or oak log end
> face. Concentric annual growth rings on honey-brown wood (#8B5E2A),
> fine radial grain lines from center outward, slight heartwood
> darkening at center from deep amber to medium brown. Tightly-packed
> rings suggesting slow coastal growth. Circular cross-section fills the
> frame edge to edge. Painterly medieval fantasy art style, warm
> saturated palette. Pure matte albedo with no baked directional
> lighting and no cast shadows. 512×512.

---

### `log_side.png`

> Seamlessly tiling cubic voxel game block face texture, designed to
> tile 60+ times on a forest of upright tree trunks without any furrow
> or ridge crest becoming an obvious repeating band. Painterly medieval
> fantasy art style — tree bark side texture for a coastal maritime
> woodland, salt-pine or dwarf-oak. Deep vertical furrows with raised
> ridges, dark warm-brown (#3D2510 to #5C3A1A), slightly lighter ridge
> tops worn smooth by weather. Strong vertical grain direction. Rough,
> windswept, old — the bark of a tree that has survived decades of ocean
> storms. Furrow depth and ridge width varies subtly along their length
> so no horizontal band repeats visibly when tiled vertically. Balanced
> color distribution: the dark furrow zones and lighter ridge zones
> interspersed at similar visual weight, no single ridge crest
> dramatically brighter than others. Pure matte albedo with no baked
> directional lighting and no cast shadows. No corner or edge artifacts.
> Character: the surface quality of a hand-crafted medieval RPG voxel
> world — Minecraft elevated with painterly detail and warm material
> authenticity. 512×512. --tile

---

### `leaves_all.png`

> *(Requires RGBA output — transparent or pure-black background between
> leaf clusters so sky shows through in the game engine.)*
>
> Seamlessly tiling cubic voxel game block face texture with alpha
> transparency, designed to tile 60+ times in a forest canopy without
> any single leaf cluster or gap becoming the repeating anchor.
> Painterly medieval fantasy art style — dense small rounded leaves of
> dwarf-oak or salt-pine, deep forest green (#2D4A1A to #3A5C20) with
> individual leaf variation from dark emerald to slightly lighter olive.
> Leaf clusters distributed uniformly across the face: many small
> groups of similar size and density, no single large dense cluster and
> no single large isolated transparent gap that repeats visibly. Leaves
> are small and tough — not lush tropical, not sparse pine needles.
> Maritime coastal woodland canopy character. Balanced distribution:
> leaf coverage roughly 55–65% of the face, transparent regions spread
> uniformly throughout. Pure matte albedo with no baked directional
> lighting and no cast shadows. No corner or edge artifacts. RGBA PNG
> with alpha transparency. 512×512. --tile

---

### `copper_ore_all.png`

> Seamlessly tiling cubic voxel game block face texture, designed to
> tile 60+ times on a cave wall without any ore vein or copper fleck
> becoming an obvious repeating element. Painterly medieval fantasy art
> style — grey stone base matching warm grey granite (#7A6E63) with
> veins and flecks of copper mineral scattered across the face. Copper
> in two states: raw orange-bronze (#B87333) where freshly exposed,
> oxidized blue-green (#4A8A5A) where weathered. Ore vein pattern
> broken into multiple short irregular branching segments distributed
> across the face — no single long continuous vein crossing from edge to
> edge. Copper fleck clusters of similar size spread at even density: no
> isolated large copper patch dominant. Stone base texture uniformly
> distributed between ore regions. This is the ore that built the
> colonial economy of a maritime archipelago — rich and readable, but
> the pattern reveals no repeat. Pure matte albedo with no baked
> directional lighting and no cast shadows. No corner or edge artifacts.
> Character: the surface quality of a hand-crafted medieval RPG voxel
> world — Minecraft elevated with painterly detail and warm material
> authenticity. 512×512. --tile

---

### `bedrock_all.png`

> Seamlessly tiling cubic voxel game block face texture, designed to
> tile across the absolute bottom of the world without any mottled patch
> becoming a visible repeating element. Painterly medieval fantasy art
> style — near-black dense igneous stone (#1E1E24 to #282830). Very
> subtle dark-grey mottling suggesting volcanic or deep-sea origin: many
> tiny tonal variations spread uniformly across the face at fine grain,
> no single darker or lighter zone dominant. Almost no color — primarily
> value variation only, with the range between lightest and darkest
> tones very narrow so no region stands out. Heavy, ancient,
> impenetrable. Faint crystalline grain structure at micro scale.
> Clearly distinct from stone: darker, denser, more uniform. Balanced
> distribution: the mottling even and omnipresent rather than
> concentrated. Pure matte albedo with no baked directional lighting and
> no cast shadows. No corner or edge artifacts. Character: the surface
> quality of a hand-crafted medieval RPG voxel world — Minecraft
> elevated with painterly detail and warm material authenticity.
> 512×512. --tile

---

## Quality checklist (per texture, before saving)

- [ ] **Tiles seamlessly?** Place 4 copies in a 2×2 grid — no visible
  seam at any edge.
- [ ] **Tiles at 60× without a visible pattern?** Place 8×8 copies of
  the tile and scan for any repeating element the eye locks onto —
  a single bright pebble, a distinctive crack, an off-color patch.
  If you see it, regenerate.
- [ ] **No dominant feature?** No single stone, vein, gap, or tonal
  island dramatically different from its neighbors.
- [ ] **No baked lighting?** No bright highlight in any one corner, no
  cast shadow from an implied light source. Even illumination across
  the face.
- [ ] **Color in the right zone?** Stone is warm grey-brown, not blue;
  leaves are deep emerald, not lime; clay is cool blue-grey, not muddy
  brown.
- [ ] **Filename matches exactly?** `gravel_all.png`, not `Gravel.png`
  or `gravel.PNG` — the builder is case-sensitive.

When all 11 source PNGs are in place, run the builder.
