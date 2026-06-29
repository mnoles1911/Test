# Color / Palette Direction Spec — the cubic voxel world

**Status:** PROPOSED art-direction spec (no code changed by this doc). Companion to
`design/UE5_RENDERING_STRATEGY.md` (per-face solid-color texturing decision) and the live color
system in `Source/MiraThalVoxel/Public/Core/VoxelColor.h`. Engine: UE5.7, Lumen + Nanite, 10cm cubes.

**Who this is for:** the designer (plain English) plus whoever next touches `VoxelColor.h` or the
terrain material. It does **not** edit code. It is the brief for two later, separable jobs:
a CORE retune (the baked palette) and a MATERIAL pass (the variation/grading that needs no re-bake).

**One-line target:** *Skyrim's outdoors* — earthy, desaturated, cold-leaning. Muted greens, cold
greys, brown earth, value/silhouette doing the work instead of vivid hue, and the horizon washing
out with distance. Right now the baked palette is carried over from the old Godot build and is **too
vivid** for that target (see §1). The fix is mostly a gentle desaturation of a handful of base
colors, a slightly gentler face-shade ramp, and — the real lever — **variation added in the material,
not in the bake.**

---

## 0. How the current system works (verified against `VoxelColor.h`, read this first)

So the rest of the doc is unambiguous, here is the live pipeline, confirmed by reading the header:

- **Color is per-MATERIAL × per-FACE-DIRECTION. NOT per-voxel.** Each material id has ONE flat
  `base_color` (e.g. grass = one green). That base is multiplied by a `face_shade` brightness that
  depends only on which of the six directions the face points (top brightest, bottom darkest). The
  result, `shaded_color = base_color × face_shade`, is **baked into the vertex color** (the
  `cr/cg/cb` fields) by the mesher.
- **Why per-voxel color is forbidden:** the greedy mesher merges neighbouring same-material,
  same-direction faces into one big quad. That merge only survives if every merged face is the
  *exact same color*. If color varied per voxel, the merge would break and the chunk's quad count
  would explode. **This is the load-bearing constraint behind this whole doc.** Any "variation" we
  want has to come from somewhere that does NOT make two adjacent same-material faces differ at bake
  time — i.e. it has to come from the **material at shade time** (§3).
- **Face-shade ramp today:** top `1.00`, bottom `0.50`, sides `0.70–0.86` (each side slightly
  different so two side faces are still distinguishable). A cheap fake directional-light / fake-AO
  that makes a bare cube read as 3D before Lumen touches it.
- **AO is separate.** Real ambient occlusion rides in the vertex **alpha**; the UE material
  multiplies albedo × AO at shade time. We do **not** pre-bake AO into the color. (Leave this alone.)
- **The material decodes vertex color as sRGB.** `M_VoxelTerrainV2` takes the stored vertex color and
  runs `Power(2.2)` on it to get linear BaseColor. So a stored byte `v` lands on screen at roughly
  `(v/255)^2.2`. **Every RGB in this doc is an 8-bit sRGB store value** (the number you'd type into
  `VoxelColor.h`), the same convention the file already uses — so you can compare them directly to the
  existing `base_color` entries. The Power(2.2) decode then darkens midtones on screen; that is
  already true of the current values, so a like-for-like swap behaves predictably.

**Mantra for the whole spec:** *neutral-ish base in the bake, variation and time-of-day in the
material/lighting.* Baking is expensive to change (re-crust); the material is free to change.

---

## 1. Assessment of the current palette + recommended muted values

**Verdict: too vivid / too saturated for the Skyrim-grounded target.** The values in `VoxelColor.h`
were transcribed straight from the Godot `color_high` palette, which was authored for a brighter,
more "video-gamey" read. Skyrim's outdoors is deliberately **desaturated and earth-toned** — Bethesda
leans on contrast, silhouette and value (not saturated hue) to guide the eye, with a global warm/cool
grade and lowered saturation that washes midtones and compresses the color range
([Quora: why are Skyrim's colors so dull](https://www.quora.com/Why-are-the-colors-in-Skyrim-so-dull),
[Steam: washed-out colors discussion](https://steamcommunity.com/app/72850/discussions/0/451851477878563024/)).
Sampled Skyrim region palettes back this up numerically: Falkreath (forest) sits on muted olive-greens
and brown-greys like `#5a614d` and `#8a8072`; Winterhold (north) on cold grey-blues like `#54605e` /
`#a4b4bb`
([Falkreath palette](https://www.color-hex.com/color-palette/1016457),
[Winterhold palette](https://www.color-hex.com/color-palette/1016466)).

The biggest offenders in the current file are **grass** (too pure-green), **water** (too saturated a
blue), **snow** (pure `255,255,255` reads as a clipped white card), and the **flora accents**
(fully-saturated flower red/blue, fine as rare accents but currently very loud).

### Recommended base_color retune (CORE change — requires re-bake; see §4)

These are *gentle* moves: pull saturation down, nudge greens toward olive/grey, warm the earth tones
slightly, and break pure white/black. The intent is "same material, read as the same thing, just less
candy." All values are 8-bit sRGB store values, directly swappable for the current entries.

| Material | Current (`VoxelColor.h`) | Recommended | Why |
|---|---|---|---|
| **GRASS** (3) | `97,140,56` | **`92,112,64`** | Pull the pure green toward Falkreath olive (`#5a614d` family). Lower saturation, slightly cooler. This is the single most important change for the Skyrim read. |
| **DIRT** (2) | `107,77,46` | **`92,72,52`** | Slightly desaturated, a touch greyer/cooler brown — wet-earth rather than chocolate. |
| **STONE** (1) | `158,153,140` | **`138,135,128`** | Drop it a step and neutralise the warm tint toward cold Nordic grey. Stone is most of a cliff face; it should read quiet. |
| **SAND** (4) | `224,204,148` | **`198,184,150`** | Desaturate and slightly grey — beach/riverbank, not desert gold. Keeps it clearly lighter than dirt. |
| **SNOW** (13) | `255,255,255` | **`232,236,240`** | Break pure white (which clips and kills form) and cool it very slightly blue. Lumen + sky bounce will brighten it back up; a pure-white store gives the material no headroom to grade. |
| **LEAVES** (11) | `59,92,33` | **`58,80,44`** | Desaturate, push toward muted forest green so canopies don't read neon against muted grass. |
| **WATER** (range) | `51,102,153` | **`58,84,104`** | Cooler, greyer, less saturated. Most of water's color should come from the *material* (Lumen reflection, depth, sky) — the baked albedo just needs to be a quiet cold base, not a bright blue. |

Secondary materials (lower priority, same direction — desaturate, neutralise):

| Material | Current | Recommended | Why |
|---|---|---|---|
| **LOG** (10) | `92,59,26` | **`84,62,42`** | Slightly greyer/less orange bark. |
| **GRAVEL** (7) | `122,122,122` | **`120,118,112`** | A hair warmer-neutral so it isn't pure greyscale. |
| **CLAY** (8) | `122,138,150` | **`118,126,132`** | Pull the blue cast down toward grey. |
| **STONE_DARK** (14) | `102,102,115` | **`96,98,104`** | Neutralise the slight purple. |
| **MARBLE** (9) | `232,224,212` | keep ~`230,226,218` | Already fine; barely touch. |
| **BEDROCK** (6) | `46,46,51` | keep, maybe `52,52,56` | Lift off near-black so it isn't a void under Lumen. |
| **GRASS_BLADE** (24) | `115,158,66` | **`104,128,72`** | Match the new grass direction (keep it a touch brighter than ground grass so blades pop slightly). |
| **FLOWER_RED** (25) | `217,46,41` | keep (accent) | These are *rare accents* — Skyrim lets torch flames / banners pop against the muted field. Leave saturated, that's the point. |
| **FLOWER_BLUE** (26) | `92,133,230` | keep (accent) | Same — rare saturated accent, intentional. |
| **PEBBLE/TWIG** (27/28) | as-is | desaturate to match dirt/stone | Minor; align with their parent material. |

**Note on the ore/copper colors** (`copper_ore`, `iron_ore`): leave them — ores *should* read as a
distinct, slightly-saturated vein against muted rock so the player can spot them. That's gameplay
readability, the same reason flowers stay saturated.

---

## 2. The per-face shade ramp (`face_shade`)

**Current:** top `1.00`, bottom `0.50`, sides `0.70–0.86`. That's a **2:1 top-to-bottom contrast**.

**Verdict: slightly too harsh for a realistic look — recommend gentling it.** A 2:1 baked brightness
spread was great for "make a bare cube read as 3D with zero lighting," but in the UE5 build **Lumen is
now doing the real directional + bounce lighting.** When a strong baked ramp stacks on top of real
Lumen shading, side and bottom faces can read *muddy / crushed*, and the terrain looks like it has a
hard-baked light that fights the actual sun direction (especially noticeable at dawn/dusk when the
real sun is low and warm but the bake still says "top = full bright, straight down").

Recommended **gentler ramp** (still gives form, leaves room for Lumen):

| Face | Current | Recommended | Note |
|---|---|---|---|
| Top (`+Y`) | `1.00` | **`1.00`** | Keep top as the reference. |
| Bottom (`-Y`) | `0.50` | **`0.64`** | Lift the floor — bottoms are rarely seen and Lumen will shadow them anyway; `0.50` over-darkens. |
| `+X` | `0.86` | **`0.88`** | |
| `-X` | `0.76` | **`0.82`** | |
| `+Z` | `0.80` | **`0.85`** | Narrow the side spread so sides read as one material under one sun, not four painted tones. |
| `-Z` | `0.70` | **`0.80`** | |

Net: top-to-bottom contrast goes from **2.0:1 to ~1.56:1**, and the sides bunch into a tighter
`0.80–0.88` band. Keep the four sides *slightly* different (so a corner still reads), just less
shouty. This is a **CORE change → re-bake** (§4). If a re-bake is too costly to do casually, this is
the one CORE tweak that's most worth batching together with the §1 palette retune in a single re-bake.

**Alternative if you want zero re-bake on the ramp:** you *could* flatten the baked ramp toward `1.0`
and instead apply the directional darkening in the material from the face normal (the material knows
the world-space normal). But that's more material complexity for little gain, and the baked ramp is
nearly free; recommendation is to keep the ramp baked, just gentler.

---

## 3. Merge-safe color VARIATION — the key technique (MATERIAL only, no re-bake)

This is the heart of the spec. **Real terrain is not flat per material** — a hillside of "grass" has a
hundred greens in it. But we *cannot* vary color per voxel (it breaks the greedy merge, §0). So all
variation must be added **in the material `M_VoxelTerrainV2`, at shade time**, driven by inputs the
material can read **without changing what the mesher bakes**: world position, world-space normal,
and camera distance. None of these touch the vertex bake or the mesher, so **all of §3 is free —
no re-crust, editor-only, tweak live.**

The base color coming out of the vertex (after the sRGB decode) becomes the *anchor*; the techniques
below nudge it. Think of it as: `final_albedo = decoded_vertex_color  ×/+  (these modifiers)`.

### 3a. World-position macro-noise tint (the #1 variation lever)
Sample a large, soft noise by **world position** (`Absolute World Position` → divide by a big number,
e.g. 1500–4000 cm, to set the blotch scale → into a Noise node or a tiling macro-variation texture).
Use it to **lerp the albedo between two nearby tones of the same material** (e.g. grass between
`92,112,64` and a slightly browner/greyer `84,100,60`). Because it's keyed to **world position**, two
adjacent faces that the mesher merged into one quad still get a smoothly-varying tint across the quad
— the merge is intact, the flatness is gone. This is exactly UE's standard "macro variation to hide
tiling/flatness" trick, just driving color instead of a texture
([Epic: Texturing Material Functions](https://dev.epicgames.com/documentation/en-us/unreal-engine/texturing-material-functions-in-unreal-engine),
[MythicLemon: landscape material functions](https://mythiclemon.com/resources/material-functions.html)).
Keep strength subtle (±8–12% value) — Skyrim's variation is quiet.
**Tip:** sample the macro noise at two scales (one large ~30 m, one medium ~6 m) and multiply, so you
get both big "patches" and finer break-up without an obvious single frequency.

### 3b. Height-based tint (snowline, valley darkening)
Read the **world Z (height)** from `Absolute World Position`. Use it to:
- **Snowline / frost dusting:** above a height threshold, lerp toward the snow tone / desaturate &
  cool the albedo. Soften the threshold with a smoothstep + a little of the 3a noise so the line is
  ragged, not a contour ruler.
- **Valley darkening:** below a threshold, slightly darken and cool (damp, shadowed lowlands). Reads
  as moisture and depth.
This is a global mood control with **one number** (the height), no per-voxel data needed.

### 3c. Slope-based tint (cliff vs grass, exposed rock)
Read the **world-space normal** (the material knows it). `dot(normal, up)` gives slope:
- Near-vertical faces (cliffs) → push toward the **stone/rock** tone and desaturate, even if the
  baked material was dirt/grass. This fakes the "grass on flat ground, bare rock on the steep cut"
  look that sells natural terrain, *without* the generator having to place stone voxels on every
  slope. (It's a tint, so it won't fight the actual material where stone really is.)
- Flat tops → allow the full grass/snow tone.
Blend the transition with a bit of 3a noise so the grass-to-rock edge is broken, not a clean band.

### 3d. Large-scale "biome" breakup
Sample a **very** large-scale noise (hundreds of metres) by world position and use it to bias the
whole grade — e.g. one region leans browner/drier, the next greyer/colder. This is the same node as
3a at a giant scale, lerping a global tint. It keeps a big streamed world from reading as one uniform
green, and it's the cheap stand-in for per-biome palettes until/if biome data is plumbed into the
material. (If the biome system later exposes a per-region value to the material, swap the noise for
that — same wiring.)

### 3e. Distance desaturation + atmospheric tint (sells depth — do NOT skip)
This is what makes Skyrim's vistas read as *deep* rather than flat. Use **`PixelDepth`** (or distance
from camera) to drive, with distance:
- **Desaturate** the albedo (UE `Desaturation` node, lerp amount up with distance) — distant terrain
  loses chroma ([Epic: Utility Material Expressions / Desaturation](https://dev.epicgames.com/documentation/unreal-engine/utility-material-expressions-in-unreal-engine)).
- **Lerp toward a cool atmospheric tint** (a desaturated blue-grey, ~`150,165,180`) so far hills go
  hazy and cold — aerial perspective.
- Optionally drop contrast slightly far away.
Two cautions: (1) UE's **SkyAtmosphere/fog already does aerial perspective for free** — so use this
material trick *lightly*, to reinforce, and tune it against the actual atmosphere so you're not
double-applying haze. (2) This is a per-pixel material cost; keep the math cheap (one desaturate + one
lerp). The payoff — a horizon that recedes — is large for the cost.

### 3f. (Optional) micro value-noise to break the "plastic" flat
A faint high-frequency value noise (world-position keyed, ±3–4%) over everything stops large merged
quads from looking like a single plastic sheet under Lumen. Subtle; mostly matters on big stone/snow
expanses.

**All of §3 is dialed in the material instance** — expose the strengths (macro tint amount, snowline
height, slope sharpness, distance-desat amount, atmosphere color) as **scalar/vector parameters on a
Material Instance** so the designer can tune them live in-editor with sliders, no recompile, no
re-bake.

---

## 4. CORE change vs MATERIAL change — what needs a re-bake

The dividing line is simple and worth stating loudly, because it decides cost:

> **Anything in `VoxelColor.h` is baked into the vertex color at mesh time → changing it requires
> RE-BAKING the crust** (re-running the mesher / re-doing the Nanite cold-bake so the new color lands
> in the vertices). **Anything in the material reads the *already-baked* vertex color and modifies it
> on the GPU per frame → it is FREE: editor-only, no re-bake, tweak live.**

| Change | Where | Re-bake the crust? | Notes |
|---|---|---|---|
| §1 `base_color` retune (grass/dirt/stone/sand/snow/leaves/water…) | `VoxelColor.h` (CORE) | **YES** | Baked into vertex `cr/cg/cb`. Harness-tested (the clang Core gate). Batch all §1 + §2 into one re-bake. |
| §2 `face_shade` ramp change | `VoxelColor.h` (CORE) | **YES** | Also baked into vertex color (it multiplies base at bake time). Do it in the same re-bake as §1. |
| AO behaviour | vertex alpha + material | **N/A** | Don't touch — AO rides in alpha and is multiplied in the material already. |
| §3a macro-noise tint | `M_VoxelTerrainV2` (MATERIAL) | **No** | World-position noise; merge-safe. |
| §3b height tint (snowline/valley) | MATERIAL | **No** | Reads world Z. |
| §3c slope tint (cliff/rock) | MATERIAL | **No** | Reads world normal. |
| §3d biome breakup | MATERIAL | **No** | Giant-scale world-position noise. |
| §3e distance desat / atmosphere | MATERIAL | **No** | Reads PixelDepth. |
| §3f micro value-noise | MATERIAL | **No** | World-position noise. |
| Day/night warm/cool grade (§5) | **Lighting**, not material/bake | **No** | DirectionalLight + SkyAtmosphere; see §5. |

**Practical sequencing recommendation:** do the MATERIAL pass (§3) FIRST — it's free, reversible, and
will get you ~80% of the Skyrim read on its own (especially §3a + §3e). Only after seeing the world
*with* variation, decide whether the baked base colors still need the §1/§2 retune, and if so, do
§1 and §2 together in a **single** re-bake so you only pay the crust cost once. The §1 table is a
strong starting point regardless, but the material variation may make the exact base values matter
less than they look on paper.

**Harness note:** because §1/§2 live in `Core/VoxelColor.h`, any change there must keep the standalone
clang harness green (the "ALL HARNESSES GREEN" gate) before any UE build/re-bake — same as every other
Core edit. The material work (§3) is outside Core and outside the harness entirely.

---

## 5. Coordinating with day/night + atmosphere

The world's time-of-day and weather come from a **sun-driven `DirectionalLight` + `SkyAtmosphere`**
(physically-based Rayleigh/Mie scattering) and `SkyLight`/HDRI ambient, per
`design/UE5_ART_ASSETS.md` (e.g. a dusk "Belfast Sunset" HDRI for golden-hour, a captured-scene
SkyLight for ambient). **That lighting layer is what should do the warm-dawn / cool-night shift —
NOT the baked voxel color.**

The rule that keeps this clean:

> **Keep the baked base palette neutral-ish (slightly cool, never strongly warm or strongly cool) and
> let the lighting tint it per time of day.** A neutral albedo reads correctly under *both* a warm low
> dawn sun and a cool blue night, because the DirectionalLight color + SkyAtmosphere are multiplying
> the warmth/coolness in at render time.

Why this matters concretely:
- If you bake warmth **into** the voxels (e.g. push grass golden to "look like sunset"), it will look
  wrong at every *other* time of day — that grass stays golden at cold blue midnight. **Baked color is
  time-of-day-blind.** Skyrim's own grade is applied globally at render, not painted into each asset,
  which is exactly why it holds up across its day cycle and weather.
- The §1 recommendations are deliberately **neutral-to-slightly-cool** (e.g. snow nudged faintly blue,
  greens pulled toward grey-olive, water a cold base) precisely so the lighting has clean material to
  work with. The warm of dawn comes from the sun's color temperature; the cool of night from the moon
  + sky — both live in the lighting actors, tunable per the day/night cycle.
- **Distance/atmosphere (§3e) should be tuned *against* SkyAtmosphere**, not independently. The sky
  actor already fades the horizon; the material's distance-desat is a light reinforcement on top.
  Tune them in the same sitting so you don't get a double-haze.
- **One time-of-day color knob lives in the material, optionally:** if you want art control beyond what
  the lighting gives (e.g. a faint global warm push at "magic hour"), expose it as a single global
  scalar/vector parameter on the material driven by the day/night controller — but treat that as a
  *grade*, applied uniformly, never as a per-material baked value. Default it to neutral.

**Net coordination summary:** bake = neutral, slightly cool, material-varied for *spatial* richness
(§3); lighting = all *temporal* color (dawn/day/dusk/night/weather) via DirectionalLight +
SkyAtmosphere + SkyLight. Spatial variation and temporal color stay in separate layers and never
fight.

---

## 6. TL;DR for the designer

1. **The current baked colors are too vivid for Skyrim.** §1 gives muted, earth-toned swaps for grass,
   dirt, stone, sand, snow, leaves, water (keep flowers/ores saturated as accents). That's a **CORE
   change → needs a re-bake.**
2. **The face-shade ramp is a bit harsh** (top 1.0 / bottom 0.5). §2 gentles it to ~1.56:1 so it
   stops fighting Lumen. Also CORE → bake it in the *same* re-bake as #1.
3. **The real magic is variation in the MATERIAL** (§3): world-position macro-noise tint, snowline &
   valley height-tint, cliff/rock slope-tint, biome breakup, and distance desaturation/atmosphere.
   All of this is **FREE — no re-bake, editor-only, live sliders.** Do this first.
4. **Re-bake line:** `VoxelColor.h` = baked into voxels = re-bake. Material = free. (§4 table.)
5. **Day/night stays in the lighting, not the voxels** (§5): keep the bake neutral-ish, let the sun +
   SkyAtmosphere do warm-dawn / cool-night. Don't paint time-of-day into the cubes.

---

## Sources

- Skyrim's desaturated, value-driven outdoor direction:
  [Quora — why are Skyrim's colors so dull](https://www.quora.com/Why-are-the-colors-in-Skyrim-so-dull) ·
  [Steam — washed-out colors discussion](https://steamcommunity.com/app/72850/discussions/0/451851477878563024/)
- Sampled Skyrim region palettes (earthy/cold hex values):
  [Falkreath (forest, muted olive/brown)](https://www.color-hex.com/color-palette/1016457) ·
  [Whiterun (warm gold-brown)](https://www.color-hex.com/color-palette/1016465) ·
  [Winterhold (cold grey-blue north)](https://www.color-hex.com/color-palette/1016466)
- UE5 material variation techniques (macro variation, break-up tiling, desaturation, world-position):
  [Epic — Texturing Material Functions](https://dev.epicgames.com/documentation/en-us/unreal-engine/texturing-material-functions-in-unreal-engine) ·
  [Epic — Utility Material Expressions (Desaturation)](https://dev.epicgames.com/documentation/unreal-engine/utility-material-expressions-in-unreal-engine) ·
  [MythicLemon — Landscape Material Functions](https://mythiclemon.com/resources/material-functions.html) ·
  [80.lv — break up tiling in UE5](https://80.lv/articles/how-to-avoid-noticeable-tiling-in-organic-textures-in-ue5)
- Internal: `Source/MiraThalVoxel/Public/Core/VoxelColor.h` (live system),
  `design/UE5_RENDERING_STRATEGY.md` (per-face solid-color decision),
  `design/UE5_ART_ASSETS.md` (SkyAtmosphere / day-night / HDRI atmosphere).
