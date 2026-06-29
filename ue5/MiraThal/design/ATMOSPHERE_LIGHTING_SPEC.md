# Atmosphere & Lighting Spec — the Skyrim-grounded outdoor mood for the voxel world

**Status:** PLAN / TURNKEY EDITOR SETUP (2026-06-22). Companion to `design/UE5_RENDERING_STRATEGY.md`
(bands + per-face color), `design/UE5_ART_ASSETS.md` (the CC0 sky/water/VFX assets), `design/UE5_TECH_STACK.md`
(stack), and `design/UE5_VOXEL_MATERIAL_SETUP.md` (the exposure-lock + sRGB-decode gotchas).

> **Plain-English orientation (read first).** This document is a "place these actors, set these numbers"
> recipe for the look of the open world — the sky, the sun and moon, the haze in the distance, and the
> overall colour mood. It is written so a later editor session is *checklist work*, not guesswork. The
> target feel is **Skyrim's outdoors**: a cool, slightly-grey Nordic sky, warm low sun, soft distance
> haze, and that grounded "real weather" honesty (overcast reads heavy and quiet; a clear morning reads
> crisp and golden). We are NOT going for the candy-bright look of a stylised builder game — the 10 cm
> cubes should read like real terrain that Lumen happens to be lighting.

> **Two hard project constraints this spec must respect (do not violate):**
>
> 1. **Auto-exposure must be LOCKED.** The voxel terrain is per-face flat colour baked into vertex
>    colour. Auto-exposure keys on the bright sky and crushes the cubes to near-black — verified in
>    `UE5_VOXEL_MATERIAL_SETUP.md`. We run **fixed/manual exposure** so the cubes always read the same.
> 2. **The terrain material decodes vertex colour as sRGB via a Power-2.2 node** (`M_VoxelTerrainV2`).
>    That decode is calibrated against a specific brightness range. If we move exposure or sky intensity
>    wildly, the palette shifts. So once exposure is locked at the value below, treat it as a fixed
>    anchor and tune the *sky/sun* to it — not the other way around.

The cubes themselves already carry a baked **per-face directional shade** (top face = 1.00 brightest,
bottom = 0.50 darkest, sides 0.70–0.86 — from `Core/VoxelColor.h`). That means cubes read as 3D *before*
any dynamic light. Our job here is to layer real lighting and atmosphere *on top* of that, so the world
gets time-of-day, GI bounce, soft shadows, and distance — without fighting the baked shade.

---

## 0. The actor stack at a glance (place these in `MiraStreamTest.umap`)

`MiraStreamTest.umap` is the default play map (`EditorStartupMap`, per `UE5_TECH_STACK.md` §8). It already
ships a locked-exposure PostProcessVolume and a template sky from the M2 beauty-shot tuning. This spec
**replaces those starter values with the calibrated set below** and adds the moon + day/night wiring.

| # | Actor | Mobility | Driven by day/night controller? | Role |
|---|---|---|---|---|
| 1 | **SkyAtmosphere** | (component) | Mostly static; controller may nudge Mie for overcast | Physically-based sky colour + horizon glow + aerial perspective |
| 2 | **DirectionalLight — Sun** | **Movable** | **YES** — rotation, intensity, colour over the day | Key light; casts the long Skyrim shadows |
| 3 | **DirectionalLight — Moon** | **Movable** | **YES** — rotation + on/off + intensity at night | Cool night key light; "atmosphere sun light" handoff |
| 4 | **SkyLight** | **Movable**, **Real-Time Capture ON** | **YES** — recapture cadence (it auto-tracks sky) | Ambient fill + sky reflections; the thing that keeps shadow-side cubes from going black |
| 5 | **ExponentialHeightFog** | (component) | **YES (subtle)** — scattering colour + density over the day | Distance haze, depth, the Nordic murk; volumetric god-rays |
| 6 | **VolumetricCloud** | (component) | Indirectly (lit by sun/moon automatically) | Sky interest + cloud shadows; worth it for the mood (see §6) |
| 7 | **PostProcessVolume** (unbound) | (volume) | **NO** — static anchor | **Locked exposure** + colour grade (the Skyrim mood) |

> **Single-controller principle (important).** Per Epic's day/night best practice, sun + moon + sky +
> skylight + fog should be driven by **one** controller so they never fight each other
> ([Day Sequence plugin docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/day-sequence-time-of-day-plugin-for-unreal-engine)).
> We are hand-rolling that controller in C++ (§2). The PostProcessVolume is deliberately **outside** the
> controller — exposure and grade are a fixed anchor, not animated.

---

## 1. Each actor — recommended starting values (Skyrim-grounded)

These are **starting** values calibrated to the locked exposure in §3. All numbers are a defensible
Skyrim-outdoor starting point; expect to nudge ±20% in a beauty-shot pass. Where a value is "the
controller drives this," the number listed is the **noon / clear-day** key value.

### 1.1 SkyAtmosphere

Physically-based Rayleigh (blue sky) + Mie (haze/glow) scattering, sun-driven. Mostly leave at defaults —
the power is in how it reacts to the sun angle the controller sets.

| Property | Value | Why |
|---|---|---|
| Rayleigh Scattering Scale | **0.033** (default) | The blue of the daytime sky |
| Mie Scattering Scale | **0.003** (clear) → **up to ~0.01–0.02 for overcast** | Haze around the sun; the controller/weather raises this for the grey diffuse Nordic overcast look ([worldofleveldesign overcast](https://www.worldofleveldesign.com/categories/ue4/overcast-lighting-sky-atmosphere.php)) |
| Mie Absorption Scale | **0.0004** (default) | |
| Aerial Perspective (on the component) | **ON** | This is the distance-haze tint on far terrain — a big part of the "5 km looks huge" feel |
| Sky Atmosphere affects Height Fog | **ON** (project setting "Support Sky Atmosphere Affecting Height Fog") | Lets the fog inherit sky colour instead of a flat grey — must be checked in Project Settings ([3dart](https://www.3dart.it/en/create-sky-atmosphere-fog-in-ue5/)) |

> The DirectionalLight Sun (1.2) must have **Atmosphere Sun Light = ON** so SkyAtmosphere knows which
> light is the sun and colours the sky/horizon from its angle ([Sky Atmosphere docs](https://dev.epicgames.com/documentation/unreal-engine/sky-atmosphere-component-in-unreal-engine)).

### 1.2 DirectionalLight — Sun

| Property | Value | Why |
|---|---|---|
| **Mobility** | **Movable** | The controller rotates it every frame |
| **Atmosphere Sun Light** | **ON**, Index **0** | Marks this as *the* sun for SkyAtmosphere + clouds |
| Intensity | **~6–10 lux** at noon (start **8**) | Matches the M2 beauty-shot value; calibrated to the locked exposure |
| Light Colour (noon) | **slightly warm white** ~ (1.0, 0.96, 0.90) | Skyrim daylight is faintly warm, not pure white |
| Light Colour (dawn/dusk) | **warm orange/gold** ~ (1.0, 0.74, 0.50) | Golden-hour — controller lerps colour by sun pitch |
| Temperature (alt to colour) | Use Temperature ~**5500K** noon → **3200K** dusk if you prefer Kelvin | Same effect via colour temperature |
| **Cast Shadows** | ON | The long Skyrim shadows are the whole mood |
| **Dynamic Shadow Distance MovableLight** | **very high, e.g. 50,000–150,000 cm** | Open world needs shadows way out; default is too short ([sky/fog open-world guide](https://dev.epicgames.com/documentation/en-us/unreal-engine/environmental-light-with-fog-clouds-sky-and-atmosphere-in-unreal-engine)) |
| Source Angle | **~0.5–1.0°** | Soft penumbra; slightly softer than default for a less harsh sun |
| Cast Cloud Shadows | ON | Moving cloud shadows across the terrain — strong Nordic-outdoor cue |
| Pitch (noon start) | **−45°** | The M2 afternoon angle; controller overrides this live |
| Yaw | **−35°** start | Controller overrides |

### 1.3 DirectionalLight — Moon

A second movable directional light for the night half of the cycle. It is the night key light and takes
over "Atmosphere Sun Light" duty after the real sun dips below the horizon.

| Property | Value | Why |
|---|---|---|
| **Mobility** | **Movable** | Controller rotates it (opposite the sun) |
| **Atmosphere Sun Light** | **ON, Index 1** (the engine supports a second atmosphere light = the moon) | So the night sky/horizon is moon-lit, not black |
| Intensity | **~0.1–0.3 lux** | Moonlight is ~1/400,000 of sun, but for *playable* night use a small but visible value; controller fades it in only at night |
| Light Colour | **cool blue** ~ (0.55, 0.65, 1.0) | The classic cold moonlight; sells "night" against the warm interiors/torches |
| Cast Shadows | ON (soft) | Faint moon shadows |
| Source Angle | **~1.5°** | Softer than the sun |

> Controller logic: when sun pitch goes below the horizon, **fade sun intensity to 0** and **fade moon
> intensity up**; the moon is rotated to roughly the anti-sun position. Only one needs to be the active
> shadow-caster at a time to save cost.

### 1.4 SkyLight (Real-Time Capture)

This is the ambient/indirect light + sky reflections. It is the single thing that keeps the shadow-side
of cubes from crushing to black, and it makes Lumen's sky bounce correct.

| Property | Value | Why |
|---|---|---|
| **Mobility** | **Movable** | Required for real-time capture |
| **Source Type** | **SLS Captured Scene** | Captures the live SkyAtmosphere — auto-tracks time of day |
| **Real Time Capture** | **ON** | The sky relights ambient as the sun moves — no manual recapture needed; this is the modern day/night path ([Sky Lights docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/sky-lights-in-unreal-engine)) |
| Intensity Scale | **1.0** | Calibrated to exposure; raise slightly (1.0→1.5) for overcast fill |
| Lower Hemisphere Is Solid | **ON** (colour ≈ dark ground tone) | Stops light leaking up from below the terrain |
| Cast Shadows | ON | Sky-occlusion contact shadows in cube crevices |

> **Why Real-Time Capture, not HDRIs here:** the CC0 HDRIs in `UE5_ART_ASSETS.md` (Kloofendal /
> Kloppenheim / Belfast) are still valuable, but for a *moving* sun the cleanest path is Real-Time
> Capture so the SkyLight always matches the current sky. Keep the HDRIs as **per-weather-state cubemap
> overrides** (clear / overcast / dusk) for when the weather machine wants a specific art-directed
> ambient that the procedural sky can't hit — see §5.

### 1.5 ExponentialHeightFog

The distance haze. This is where a lot of the "Skyrim depth / Nordic murk" lives. Subtle by default,
heavier in overcast/fog weather states.

| Property | Value (clear day) | Why |
|---|---|---|
| **Fog Density** | **0.02** | Light haze; the controller/weather raises to ~0.05–0.2 for fog/overcast |
| **Fog Height Falloff** | **0.2** | How fast fog thins with altitude; lower = thicker valleys (good for Nordic valley fog) |
| Fog Inscattering Colour | **set toward black / let sky drive it** | With "Sky Atmosphere Affecting Height Fog" ON, set inscatter dark so fog inherits real sky colour instead of a flat grey ([sky/fog setup](https://www.3dart.it/en/create-sky-atmosphere-fog-in-ue5/)) |
| Directional Inscattering Colour | **dark / near-black** | Same reason; avoids a fake bright halo |
| **Volumetric Fog** | **ON** | Enables real god-rays + light shafts through the fog — a signature Skyrim-morning look |
| Volumetric Fog Scattering Distribution | **~0.4** | Slight forward scatter for sun shafts |
| Volumetric Fog Albedo | **cool grey-white** | The murk colour |
| Start Distance | **~0** (or small) | Haze starts near to read on near cubes too |

### 1.6 VolumetricCloud — *worth it for the mood: YES*

Clouds matter for the Nordic feel (big skies, drifting cloud shadows). The built-in is cheap enough and
needs no downloads.

| Property | Value | Why |
|---|---|---|
| Material | **`m_SimpleVolumetricCloud_Inst`** (Engine/EngineSky/VolumetricClouds) | The default; zero authoring ([Volumetric Cloud docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-cloud-component-in-unreal-engine)) |
| Layer Bottom Altitude | **~5 km** | Default; clouds sit above the playable 5 km terrain |
| Layer Height | **~10 km** | Default thickness |
| View Sample Count Scale | **lower it (e.g. 0.5–0.7)** if perf bites | Clouds are a known cost; this is the perf knob |
| Coverage (via material instance / MPC) | **~0.4 clear → ~0.8 overcast** | Drive from the weather machine for clear↔overcast |

> Clouds are lit automatically by the sun/moon directional lights — no extra wiring. Enable **Cast Cloud
> Shadows** on the Sun (1.2) to get the moving cloud shadows on terrain.

---

## 2. How it ties into the day/night controller (40-min day / 20-min night)

A separate **C++ controller** (being built; call it `AMiraSkyController` or similar) owns the cycle. This
spec defines the contract: **what the controller drives vs what stays static.** The 60-minute full cycle
= **40 min day + 20 min night** (day is 2× night — keep the world bright and explorable most of the time,
Skyrim-style).

### What the controller DRIVES every tick (or on a timer)

1. **Sun rotation** — pitch/yaw from a normalized time-of-day `t` (0..1). Day spans the above-horizon
   arc over 40 min; night the below-horizon arc over 20 min. (Day/night being unequal just means the
   sun moves *faster* across the night arc.)
2. **Sun intensity + colour** — lerp intensity up from dawn, full at noon, down to 0 at dusk; lerp colour
   warm-gold at low angles → faint-warm-white at noon (1.2 table).
3. **Moon rotation + intensity** — anti-sun position; fade moon intensity in only while the sun is below
   the horizon; hand off "atmosphere sun light" active role.
4. **SkyLight** — with **Real-Time Capture ON it self-updates**, so the controller does *not* need to
   recapture manually. (If RTC is ever turned off for perf, the controller would call a recapture every
   N seconds — but the default plan is RTC-on, no manual recapture.)
5. **ExponentialHeightFog (subtle)** — slightly raise density + cool the scattering colour at dawn/dusk
   and at night (heavier valley murk in the cool hours); back to light haze at midday.
6. **(Optional) SkyAtmosphere Mie** — nudge up at dawn for that thick golden-hour horizon glow.

### What stays STATIC (controller never touches)

- **PostProcessVolume exposure + colour grade** (§3, §4). This is the fixed anchor that keeps the cubes
  reading consistently. Do **not** animate exposure with time of day — that's exactly the wash-out the
  lock exists to prevent. (A *very* gentle grade shift for night could be added later via a second
  blendable PPV, but v1 keeps one static grade.)
- **SkyAtmosphere base scattering scales** (except the optional Mie nudge).
- **VolumetricCloud altitude/height** (only coverage moves, and that's the weather machine, not the
  day/night clock).
- **Lumen cvars** (§3) — project-level, set once.

### Weather sits ON TOP (separate state machine — out of scope here)

Per `UE5_ART_ASSETS.md` §3, the six-state weather machine (Clear/Cloudy/Fog/Rain/Snow/Storm) is a
*separate* layer that sets **target** values (cloud coverage, fog density, fog colour, Mie, wetness, wind)
and lerps over ~20–30 s. The day/night controller and the weather machine both write some of the same
actors (fog, clouds) — resolve by having **weather set the targets** and **day/night apply a time-of-day
multiplier on top**, so e.g. "overcast at dusk" = overcast fog density × dusk cool-shift. Keep that
arbitration in the controller so the two systems don't stomp each other.

---

## 3. Lumen settings + the auto-exposure lock

### 3.1 Auto-exposure LOCK (do this first — it's the load-bearing one)

On the **unbound PostProcessVolume** (Infinite Extent / Unbound = ON, so it covers the whole map):

| Setting | Value | Why |
|---|---|---|
| **Exposure → Metering Mode** | **Manual** | Single fixed exposure, immune to scene luminance ([Auto Exposure docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/auto-exposure-in-unreal-engine)) |
| **Min EV100** | **11** | Locks the low end |
| **Max EV100** | **11** | Min == Max ⇒ auto-exposure fully disabled ([Lost Crow: disable auto-exposure](https://lostcrowdev.com/disable-auto-exposure/)) |
| Exposure Compensation | **0** (tune ±0.5 to taste) | Global brightness trim if the cubes read a hair dark/bright |
| Apply Physical Camera Exposure | OFF | We're not simulating a camera here |

> This matches `UE5_VOXEL_MATERIAL_SETUP.md` exactly (Min/Max EV100 both ≈ 11). It is the single thing
> that makes the per-face flat-colour cubes read correctly instead of crushing to black. **Set this
> before tuning anything else** — every other number is calibrated to it.
>
> Belt-and-suspenders: you can also set `r.DefaultFeature.AutoExposure = 0` in `DefaultEngine.ini` so the
> engine default is off even before the PPV loads. The PPV Manual lock is the authoritative one.

### 3.2 Lumen — large-world settings

The 5 km streamed voxel world is exactly the "large open world" case Lumen's defaults are NOT tuned for
(defaults assume indoor). Set these once at project level (Project Settings → Rendering, or cvars in
`DefaultEngine.ini` / a scalability ini). Values below are a defensible open-world starting point; the
Lumen budget for this game is **4–7 ms** per `UE5_RENDERING_STRATEGY.md` §5.

| Setting / CVar | Value | Why |
|---|---|---|
| **Global Illumination Method** | **Lumen** | The whole reason for the UE5 port |
| **Reflection Method** | **Lumen** | Sky + water reflections |
| **Lumen Scene — Software vs Hardware RT** | **Software (Mesh Distance Fields)** as the recommended-tier default; **Hardware RT** as a high-end toggle | `UE5_RENDERING_STRATEGY.md` tiers: Recommended = Software Lumen; High-end = Hardware Lumen |
| `r.LumenScene.SurfaceCache.ResolutionScale` | **0.5–0.7** (start **0.6**) | "Halving this is often the single biggest frame-cost win in an open world" ([StraySpark open-world Lumen](https://www.strayspark.studio/blog/lumen-optimization-large-open-worlds-ue5-2026)) |
| `r.Lumen.ScreenProbeGather.DownsampleFactor` | **12–16** | Fewer traces per pixel; big open-world saver |
| `r.Lumen.ScreenTrace.MaxRoughnessToTrace` | **0.4** | Limits screen-space reflection traces |
| `r.Lumen.Reflections.MaxRoughnessToTrace` | **0.35** | Rough surfaces fall back to cheaper final gather |
| `r.Lumen.Reflections.DownsampleFactor` | **2** | "Often saves 1–2 ms" ([Lumen perf guide](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-performance-guide-for-unreal-engine)) |
| `r.LumenScene.RadianceCache.NumProbesToTraceBudget` | **64** | Caps probe updates/frame |
| **Final Gather Quality** (Post Process Lumen GI) | **1.0** default, drop to **0.5–0.75** if GI cost spikes | Quality vs cost lever |
| **Max Trace Distance** (Lumen GI in PPV) | **large, e.g. 200 m+** | The world is open; let GI/reflections reach |
| **Lumen Scene Detail** (PPV) | **default → lower if distant chunks over-cost** | Distant Lumen detail |
| **Far Field** (`r.LumenScene.FarField = 1` on high-end / HWRT) | **ON for HWRT tier** | Extends GI/reflections cheaply past the ray-tracing radius — good for the 5 km horizon |

> **Voxel-specific note:** because cubes are dense mesh distance fields, the **Software Lumen** path
> (mesh SDF) is a natural fit and is the recommended-tier default. When the cold→Nanite bake (M6) lands,
> the Nanite static chunks feed Lumen Scene the same way — no Lumen retune needed at that point.

> **Auto-exposure interaction with Lumen:** Lumen's internal lighting is unaffected by the manual
> exposure (exposure is a post step), so locking exposure does NOT dim GI — it only fixes how the final
> image is mapped to screen. Good: we get full Lumen bounce *and* stable cube colours.

---

## 4. Colour grading / tone — the Skyrim mood (static, in the PostProcessVolume)

Do colour grading **last**, after lighting reads right ([medium: realistic lighting](https://medium.com/@tmaurodot/crafting-realistic-lighting-and-atmosphere-in-unreal-engine-5327f3cce8d8)).
The Skyrim outdoor signature is: **slightly desaturated, cool shadows, warm highlights, gentle contrast,
atmospheric distance.** All of this goes on the **unbound PostProcessVolume**, static (not animated by
the day/night controller in v1).

| PPV setting | Value | Why (Skyrim mood) |
|---|---|---|
| **Global Saturation** | **~0.88–0.92** | Slightly desaturated — Skyrim is never candy-coloured; pulls the flat cube palette toward "real terrain" |
| **Shadows → Colour (tint)** | **cool blue-grey**, e.g. saturation toward (0.9, 0.95, 1.05) | Cool shadows = the Nordic signature |
| **Highlights → Colour (tint)** | **faint warm**, e.g. (1.05, 1.0, 0.95) | Warm light vs cool shadow = the classic split that reads "outdoor daylight" |
| **Global Contrast** | **~1.05–1.1** | Gentle S-curve; not crushed (overcast wants *low* contrast — see weather note) |
| **Global Gamma** | **~1.0** (nudge 0.95 to deepen shadows) | |
| **White Balance / Temp** | **slightly cool, ~6800–7000K** for the base grade | Overall cool cast; the *sun* re-warms the lit side |
| **Tint** | **0 → faint green-grey** | Optional Nordic moss undertone |
| **Bloom Intensity** | **low, ~0.4–0.6** | Subtle; a soft sky bloom, not a glow-fest |
| **Vignette Intensity** | **~0.3** | Gentle framing; grounds the over-shoulder camera |
| **Film grain** | **0–0.1** | Optional faint grain for a less "clean CG" look |
| **Tone curve / ACES** | leave default (filmic) | UE's default tonemapper already reads cinematic |

> **Overcast vs clear is mostly a weather-machine job, not the static grade:** clear = the grade above +
> warm low sun + light haze. Overcast = the weather machine **raises Mie scattering (1.1) for diffuse
> sky**, **raises fog density + SkyLight fill**, and **lowers contrast** (overcast removes hard shadows;
> the mood goes "melancholy, quiet, desolate" — exactly the Skyrim overcast read
> ([worldofleveldesign overcast](https://www.worldofleveldesign.com/categories/ue4/overcast-lighting-sky-atmosphere.php))).
> Keep the *base* grade neutral-cool so both states sit on top of it cleanly.

> **Distance haze** is delivered by **SkyAtmosphere Aerial Perspective (1.1) + ExponentialHeightFog
> (1.5)**, not by the grade. The grade just makes sure the hazed-out distance reads cool and atmospheric
> rather than washed grey.

---

## 5. CC0 sky assets — what to use, what's still needed

From `design/UE5_ART_ASSETS.md` (all CC0, ship-safe, verified 2026-06-16):

### Use now (per-weather-state SkyLight cubemap overrides)

| Asset | CC0 source | Use here |
|---|---|---|
| **Kloofendal 48d Partly Cloudy (Pure Sky)** 4K EXR | [polyhaven](https://polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky) | Clear / partly-cloudy day ambient + reflection |
| **Kloppenheim 06** 4K HDR | [polyhaven](https://polyhaven.com/a/kloppenheim_06) | Overcast / soft-light state (low-contrast, diffuse) |
| **Belfast Sunset (Pure Sky)** 4K EXR | [polyhaven](https://polyhaven.com/a/belfast_sunset_puresky) | Dusk / golden-hour (Skyrim sunset mood) |
| **Kenney Particle Pack** + **Smoke Particles** | [kenney.nl](https://www.kenney.nl/assets/particle-pack) | Niagara weather VFX (rain splash, snow, storm haze) — for the weather layer, not this spec |

**Import settings** (from `UE5_ART_ASSETS.md` §2d): HDRIs → Texture Group **HDRI**, Compression **HDR**,
**sRGB OFF**. Assign to a SkyLight via **Source Type = Specified Cubemap** for the override states.

> **How the HDRIs fit the moving-sun plan:** the *default* SkyLight runs **Real-Time Capture** (§1.4) so
> ambient tracks the live procedural sky as the sun moves — the HDRIs are NOT the everyday sky. They are
> **art-directed overrides** the weather machine can blend to when it wants a specific look the procedural
> sky can't hit (a heavy diffuse overcast, a dramatic dust-gold dusk). v1 can ship on Real-Time Capture
> alone; the HDRIs are a quality upgrade for specific weather states.

### Still needed / gaps

- **No dedicated moon/night-sky HDRI or star cubemap is earmarked.** For night, v1 relies on the
  procedural SkyAtmosphere (moon as atmosphere-sun-light, index 1) + the moon directional light. If we
  want a **starfield**, that's a missing asset — grab a CC0 night-sky HDRI (Poly Haven has CC0 night
  skies) or a CC0 star cubemap, or author stars as a panner in the sky material. **Action: source one CC0
  night-sky HDRI** if designer wants visible stars.
- **Cloud noise textures:** not needed — the built-in `m_SimpleVolumetricCloud_Inst` covers v1. Only
  needed if we author a custom cloud material later.
- Everything else (sky, fog, GI, clouds) is **procedural UE5 — zero downloads** per `UE5_ART_ASSETS.md`.

---

## 6. First 30 minutes in the editor — checklist

Open `MiraStreamTest.umap`. Do these in order; each builds on the last.

1. **(5 min) Lock exposure FIRST.** Select the unbound PostProcessVolume → Exposure → Metering Mode =
   **Manual**, Min EV100 = **11**, Max EV100 = **11**. Confirm the cubes stop crushing to black. *Nothing
   else will look right until this is done.*
2. **(3 min) Sun.** Place / confirm **DirectionalLight (Movable)**, **Atmosphere Sun Light = ON (index
   0)**, intensity **8**, colour faint-warm white, pitch **−45°**, **Cast Shadows ON**, Dynamic Shadow
   Distance **~100,000**. Confirm long shadows across the cubes.
3. **(3 min) SkyAtmosphere.** Confirm present; **Aerial Perspective ON**. In Project Settings confirm
   **"Support Sky Atmosphere Affecting Height Fog" = ON**.
4. **(3 min) SkyLight.** **Movable**, **Real-Time Capture ON**, SLS Captured Scene, Lower Hemisphere Is
   Solid ON. Confirm shadow-side cubes get soft sky fill (no longer black).
5. **(4 min) ExponentialHeightFog.** Density **0.02**, Height Falloff **0.2**, inscatter colour → dark
   (let sky drive it), **Volumetric Fog ON**. Confirm distance haze + a faint god-ray through the sun.
6. **(3 min) VolumetricCloud.** Confirm present with `m_SimpleVolumetricCloud_Inst`; on the Sun enable
   **Cast Cloud Shadows**. Watch a cloud shadow drift over the terrain.
7. **(3 min) Moon.** Place a second **DirectionalLight (Movable)**, **Atmosphere Sun Light ON (index 1)**,
   cool-blue colour, intensity **0.2**, pitch it below/opposite the sun. (The controller will animate it;
   for now just confirm it exists and reads cool.)
8. **(4 min) Lumen + grade sanity.** Confirm GI Method = Lumen, Reflection = Lumen. Set the open-world
   cvars (§3.2) in `DefaultEngine.ini`. Then on the PPV apply the §4 grade: Saturation **0.9**, cool
   shadow tint, faint-warm highlights, contrast **~1.07**, bloom **0.5**, vignette **0.3**.
9. **(2 min) Hook check (if the controller exists yet).** Press Play and watch one accelerated cycle:
   sun arcs and warms toward dusk, SkyLight ambient tracks it (Real-Time Capture), moon fades in at
   night, fog cools. Confirm **exposure never changes** (cubes stay readable) — that proves the lock
   survived the controller.

> If anything reads washed-out or black after step 8, the cause is almost always (a) exposure not
> actually locked, or (b) sky/sun intensity drifted away from the EV100-11 anchor. Re-anchor to step 1.

---

## 7. Sources

- [Sky Atmosphere Component — UE5 docs](https://dev.epicgames.com/documentation/unreal-engine/sky-atmosphere-component-in-unreal-engine)
- [Sky Lights in Unreal Engine — UE5 docs (Real-Time Capture)](https://dev.epicgames.com/documentation/en-us/unreal-engine/sky-lights-in-unreal-engine)
- [Environmental Light with Fog, Clouds, Sky and Atmosphere — UE5.7 docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/environmental-light-with-fog-clouds-sky-and-atmosphere-in-unreal-engine)
- [Volumetric Cloud Component — UE5 docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-cloud-component-in-unreal-engine)
- [Auto Exposure in Unreal Engine — UE5 docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/auto-exposure-in-unreal-engine)
- [3 Ways to Disable Auto Exposure (Eye Adaptation) in UE5 — Lost Crow Dev](https://lostcrowdev.com/disable-auto-exposure/)
- [Lumen GI & Reflections — UE5 docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-global-illumination-and-reflections-in-unreal-engine)
- [Lumen Performance Guide — UE5 docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-performance-guide-for-unreal-engine)
- [Lumen Optimization for Large Open Worlds in UE5 (2026) — StraySpark](https://www.strayspark.studio/blog/lumen-optimization-large-open-worlds-ue5-2026)
- [Create Sky Atmosphere & Fog in UE5 — 3DArt](https://www.3dart.it/en/create-sky-atmosphere-fog-in-ue5/)
- [Create Overcast Day Lighting with Sky Atmosphere — World of Level Design](https://www.worldofleveldesign.com/categories/ue4/overcast-lighting-sky-atmosphere.php)
- [Crafting Realistic Lighting and Atmosphere in Unreal Engine — Thomas Mauro (Medium)](https://medium.com/@tmaurodot/crafting-realistic-lighting-and-atmosphere-in-unreal-engine-5327f3cce8d8)
- [Day Sequence Time of Day Plugin — UE5 docs (single-controller principle)](https://dev.epicgames.com/documentation/en-us/unreal-engine/day-sequence-time-of-day-plugin-for-unreal-engine)
- Project-internal: `design/UE5_VOXEL_MATERIAL_SETUP.md` (exposure lock + sRGB-2.2 decode), `design/UE5_RENDERING_STRATEGY.md` (Lumen budget + bands), `design/UE5_ART_ASSETS.md` (CC0 assets), `Source/MiraThalVoxel/Public/Core/VoxelColor.h` (per-face shade values).
