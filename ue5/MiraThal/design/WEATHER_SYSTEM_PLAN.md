# Weather System Plan — the Skyrim-grounded weather layer on top of the day/night cycle

**Status:** PLAN / RESEARCH (2026-06-22). Companion to `design/ATMOSPHERE_LIGHTING_SPEC.md` (the actor
stack + locked exposure), `Source/MiraThalCore/Sky/MiraDayNightCycle.{h,cpp}` (the real-time day/night
controller this layers on top of), `design/UE5_ART_ASSETS.md` (the CC0 sky/VFX assets), and
`design/UE5_RENDERING_STRATEGY.md` (Lumen budget).

> **Plain-English orientation (read first).** This document is the blueprint for *weather* — the slow
> drift between a crisp clear morning, a grey overcast afternoon, valley fog, rain, snow, and the
> occasional thunderstorm or blizzard. It is a **design + sequencing plan**, not engine code: it says
> what to build, in what order, how the pieces talk to the already-built day/night system, and where the
> performance landmines are. The look target is **Skyrim's weather honesty**: overcast reads heavy,
> quiet and desaturated; rain darkens and wets the world; snow whites-out the tops of things; a blizzard
> is genuinely oppressive. We are **not** doing cartoon weather.
>
> **The one big idea — weather is a MODIFIER, not a second director.** A real-time day/night controller
> (`AMiraDayNightCycle`) already owns the sun arc, the sun colour, the moon, the SkyLight fill, and the
> base fog. Weather must **never** fight it. Weather's job is to push a small set of **multipliers and
> offsets** (dim the sun to 35%, raise fog density ×4, push cloud coverage to 0.85, set wetness to 1.0)
> that the day/night controller reads and applies *on top of* its time-of-day curves. "Overcast at dusk"
> = the dusk gold curve, dimmed and flattened by the overcast modifier. One director, one weather knob-box.

---

## 0. How this sits on top of the day/night controller (the key architectural decision)

`AMiraDayNightCycle::ApplyLighting()` (read it — `MiraDayNightCycle.cpp` lines 184–282) runs every tick
and does exactly this:

1. Computes sun **elevation/azimuth** from the 40/20 clock.
2. Looks up **sun intensity** (curve or `FallbackSunIntensity`) → `SunComp->SetIntensity()`.
3. Looks up **sun colour/temperature** → `SetTemperature()`/`SetLightColor()`.
4. Fades the **moon** in below the horizon → `MoonComp->SetIntensity()`.
5. Looks up **SkyLight intensity** → `CachedSkyLight->SetIntensity()`.
6. Looks up **fog colour + density** → `SetFogInscatteringColor()` / `SetFogDensity()`.

Notice: **every one of those is a final scalar/colour the controller computes then pushes to a setter.**
That is the perfect injection point. We do **not** add a second actor that also writes those setters
(that's the "two systems stomping each other" failure the atmosphere spec warns about, §2 "Weather sits
ON TOP"). Instead:

**Weather publishes a small struct of modifiers; the day/night controller reads it at the end of its
math and applies it before the setter.** The day/night controller stays the *only* thing that calls
`SetIntensity`/`SetFogDensity`/etc. Weather just changes *what numbers it pushes*.

### The clean interface — `FMiraWeatherModifiers`

A plain value struct (the "knob box") that the weather director fills in and the day/night controller
reads. Proposed fields (all are *current, already-blended* values — the director does the lerping):

```
struct FMiraWeatherModifiers
{
    // --- Light coupling (multiply/offset the day/night curve OUTPUTS) ---
    float SunIntensityMult     = 1.0f;  // overcast 0.4, rain 0.3, storm 0.15  (× the curve's lux)
    float SunColorTempOffsetK  = 0.0f;  // overcast/storm push +600..+1200K cooler (added to Kelvin)
    float SkyLightIntensityMult= 1.0f;  // overcast 1.3 (sky fills more), storm 0.8
    float ShadowSharpnessMult  = 1.0f;  // overcast 0.0..0.3 → soften/kill hard shadows (drives sun SourceAngle)

    // --- Fog coupling ---
    float FogDensityMult       = 1.0f;  // mist 8.0, rain 3.0, blizzard 12.0  (× the curve's density)
    FLinearColor FogColorTint  = White; // multiplied onto the day/night fog colour (grey-out for overcast)

    // --- Sky / clouds (the weather-owned actors) ---
    float CloudCoverage        = 0.4f;  // clear 0.3 → overcast/storm 0.9   (→ cloud material MPC)
    float CloudDensityMult     = 1.0f;  // thicker, darker cloud bottoms in storms

    // --- Surfaces (read by terrain/water/foliage materials via the weather MPC) ---
    float Wetness              = 0.0f;  // 0 dry → 1 soaked (roughness/specular/darken)
    float SnowLevel            = 0.0f;  // 0 none → 1 full white-out on up-facing faces

    // --- Wind (shared vector; drives clouds, particles, later foliage) ---
    FVector WindVector         = ZeroVector; // direction × strength
    float   WindStrength       = 0.0f;       // 0 calm → 1 gale (convenience scalar)

    // --- Particles (read by the camera-follow Niagara system) ---
    float RainRate01           = 0.0f;  // 0..1 → Niagara spawn rate
    float SnowRate01           = 0.0f;  // 0..1 → Niagara spawn rate
};
```

### Who owns what (the contract)

| Field | Weather director SETS (the target, then lerps) | Day/Night controller APPLIES |
|---|---|---|
| `SunIntensityMult` | yes | `SetIntensity(curveLux * Mult)` |
| `SunColorTempOffsetK` | yes | `SetTemperature(curveK + Offset)` |
| `SkyLightIntensityMult` | yes | `SetIntensity(curveSky * Mult)` |
| `ShadowSharpnessMult` | yes | `SetSourceAngle(baseAngle / Mult)` or lower `DynamicShadowDistance` |
| `FogDensityMult` / `FogColorTint` | yes | `SetFogDensity(curveDensity * Mult)` / `colour * Tint` |
| `CloudCoverage` / `CloudDensityMult` | yes | (weather writes the cloud MPC directly — day/night doesn't touch clouds) |
| `Wetness` / `SnowLevel` / `Wind*` | yes | (weather writes the **weather MPC** directly — materials read it) |
| `RainRate01` / `SnowRate01` | yes | (weather drives the Niagara system directly) |

**Implementation shape (smallest viable):** add a single soft pointer on `AMiraDayNightCycle` to a
weather provider (or a `FMiraWeatherModifiers` member the weather actor writes each tick *before*
day/night ticks). In `ApplyLighting()`, fold the modifiers in at the three existing setter sites:

```
SunComp->SetIntensity(FMath::Max(0.f, SunIntensity * Weather.SunIntensityMult));
...
SunComp->SetTemperature(FMath::Clamp(Kelvin + Weather.SunColorTempOffsetK, 1700.f, 12000.f));
...
CachedSkyLight->SetIntensity(FMath::Max(0.f, SkyIntensity * Weather.SkyLightIntensityMult));
...
CachedFog->SetFogDensity(FMath::Max(0.f, FogDensity * Weather.FogDensityMult));
CachedFog->SetFogInscatteringColor(FogColor * Weather.FogColorTint);
```

That's ~6 lines of edit to a file that already exists, plus a new weather actor that owns the struct and
the state machine. **Tick order matters:** the weather actor must update `Weather` *before* the day/night
actor reads it. Enforce with a tick prerequisite (`AddTickPrerequisiteActor`) or have the day/night actor
pull `GetCurrentModifiers()` from the weather actor at the top of its own tick. The default-empty struct
(all mults = 1.0, all rates = 0) means **a level with no weather actor behaves exactly as today** — safe
by default, matching the day/night controller's own "drop-in and it just works" philosophy.

> **Why multipliers/offsets and not absolute writes:** if weather wrote absolute sun lux, it would have
> to re-implement the whole time-of-day curve to know what "overcast at 3pm" means. By multiplying the
> curve's *output*, weather stays a thin modifier: "overcast = 0.4× whatever the sun would be right now."
> Dawn overcast, noon overcast, and dusk overcast all read correctly for free. This is exactly the
> arbitration `ATMOSPHERE_LIGHTING_SPEC.md` §2 asks for ("weather set the targets, day/night apply a
> time-of-day multiplier on top").

---

## 1. The weather STATE MACHINE

### 1.1 States (the seven the project already committed to)

Per `ATMOSPHERE_LIGHTING_SPEC.md` §2 and `UE5_ART_ASSETS.md` §3a, the canonical set is six "named"
states; we split Storm into Storm(rain) and Blizzard(snow) because their *particle + light* profiles
differ, giving seven leaf states the director picks from:

| State | One-line mood (Skyrim anchor) |
|---|---|
| **Clear** | Crisp, blue, long warm shadows. The "good morning in the tundra" read. |
| **Cloudy** | Partly cloudy — drifting cloud shadows, sun still wins. The default pleasant sky. |
| **Overcast** | Flat grey lid, no hard shadows, quiet/melancholy. "Desolate" Nordic overcast. |
| **Rain** | Overcast + falling rain, wet darkened world, dimmer cooler light. |
| **Snow** | Overcast-ish + falling snow, white accumulation on tops, muffled. |
| **Fog / Mist** | Thick valley murk, short sight, god-rays if the sun pokes through. Dawn signature. |
| **Storm** | Rain + wind + lightning/thunder, dark, oppressive. |
| **Blizzard** | Snow + gale + near-whiteout, the worst-visibility state. |

> **MVP can ship with fewer leaves** (Clear / Cloudy / Overcast / Rain / Snow / Fog) and add
> Storm/Blizzard as the "lightning + heavy particle" upgrade in a later phase — see §6.

### 1.2 How the director picks the next state

Two layered mechanisms, simplest-first:

**(a) Weighted random walk with biome/season weighting (the default runtime behaviour).**
Each biome+season has a **weight table** over the states (a `UDataTable` row or a `UDataAsset`, designer-
editable, plain numbers). The director, on a timer (every **8–20 in-game minutes**, jittered), rolls the
next state from the *allowed transitions* of the current one, weighted by the biome/season table. This is
the standard Markov-chain approach weather systems use and keeps it believable (you don't snap Clear →
Blizzard; you go Clear → Cloudy → Overcast → Snow → Blizzard).

Example weight intent (Nordic tundra, winter): Snow 0.30, Overcast 0.25, Blizzard 0.12, Cloudy 0.15,
Fog 0.10, Clear 0.08. Same biome, summer: Clear 0.35, Cloudy 0.30, Rain 0.15, Overcast 0.12, Fog 0.05,
Storm 0.03. The **designer never touches code** — they edit the weight table.

**(b) A transition matrix (allowed edges) so changes stay plausible.** Not every state can follow every
state. Encode an adjacency table:

```
Clear     → Clear, Cloudy, Fog
Cloudy    → Clear, Cloudy, Overcast, Rain(low), Fog
Overcast  → Cloudy, Overcast, Rain, Snow, Fog
Rain      → Overcast, Rain, Storm, Cloudy
Snow      → Overcast, Snow, Blizzard, Cloudy
Fog       → Fog, Cloudy, Clear, Overcast
Storm     → Rain, Overcast            (storms blow over to rain, then clear up)
Blizzard  → Snow, Overcast
```

The next state = weighted-random pick **from the current state's allowed set**, weights from the biome/
season table. Rain vs Snow is gated by a **temperature/altitude check** (cold biome or high elevation →
snow path; temperate → rain path), so you never get rain in a frozen biome.

**(c) Designer override / scripting (escape hatch).** A Blueprint-callable
`SetWeather(EState, BlendSeconds)` and `ForceWeatherSequence([...])` so cinematics and quest beats can
script weather ("the siege happens in a storm"). When a scripted weather is active, the random walk
pauses until released. This mirrors how the day/night controller exposes `SetTimeOfDay()` for the same
"let the designer drive" reason.

### 1.3 Transitions / blending

- On a state change, the director sets **target** values for every `FMiraWeatherModifiers` field and
  **lerps the live struct toward them over ~20–30 s** (matches the Godot 30 s tweens called out in
  `UE5_ART_ASSETS.md` §3a, and the atmosphere spec's "lerps over ~20–30 s"). Slow blends are what make
  weather feel like *weather* and not a light switch.
- **Different fields can blend at different rates.** Cloud coverage and fog can take the full 30 s;
  particle spawn rate should ramp a touch faster (rain "arrives") but still over several seconds; wetness
  should *lag* (ground takes time to soak, and longer to dry — asymmetric: wet up over ~15 s, dry down
  over ~60 s, which reads very naturally).
- Hold a minimum dwell time per state (don't re-roll for at least one timer period) so weather doesn't
  flicker.

---

## 2. Per-state drive table — what each state pushes into the knob box

All numbers are **defensible Skyrim-grounded starting points**, calibrated to the locked-exposure /
EV100-11 anchor from `ATMOSPHERE_LIGHTING_SPEC.md` §3.1. Tune ±20% in a beauty pass. "Sun mult" multiplies
the day/night sun-lux curve; "Sky mult" multiplies the SkyLight curve; "Fog mult" multiplies the fog
density curve.

| State | Cloud coverage | Cloud density | Fog mult | Fog tint | Sun mult | Sun K offset | Sky mult | Shadow sharp | Wetness | Snow | Wind | Rain rate | Snow rate | Niagara FX |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **Clear** | 0.25 | 1.0 | 1.0 | white | 1.0 | 0 | 1.0 | 1.0 | 0 | 0 | 0.1 | 0 | 0 | none |
| **Cloudy** | 0.55 | 1.0 | 1.2 | very faint grey | 0.85 | +200 | 1.1 | 0.8 | 0 | 0 | 0.3 | 0 | 0 | none (cloud shadows) |
| **Overcast** | 0.90 | 1.2 | 2.5 | grey (0.8,0.82,0.85) | 0.40 | +900 | 1.35 | 0.15 | 0.1 | 0 | 0.35 | 0 | 0 | none |
| **Rain** | 0.92 | 1.4 | 3.0 | cool grey | 0.30 | +1000 | 1.2 | 0.1 | 1.0 | 0 | 0.5 | 0.65 | 0 | rain streaks + splashes |
| **Snow** | 0.85 | 1.2 | 3.5 | bright grey-white | 0.55 | +400 | 1.4 | 0.2 | 0.15 | 1.0 | 0.4 | 0 | 0.7 | snow flakes |
| **Fog / Mist** | 0.60 | 1.0 | 8.0 | sky-driven (let SkyAtmosphere colour it) | 0.7 | +300 | 1.15 | 0.5 | 0.2 | 0 | 0.15 | 0 | 0 | optional ground-wisp Niagara |
| **Storm** | 0.95 | 1.7 | 4.0 | dark cool grey (0.5,0.52,0.58) | 0.15 | +1200 | 0.9 | 0.0 | 1.0 | 0 | 0.9 | 1.0 | 0 | heavy rain + lightning + splashes |
| **Blizzard** | 0.90 | 1.5 | 12.0 | near-white | 0.30 | +600 | 1.3 | 0.0 | 0.2 | 1.0 | 1.0 | 0 | 1.0 | dense snow + whiteout haze |

Reading the table the way the systems consume it:

- **Cloud coverage / density** → written into the **cloud Material Parameter Collection** (the
  `m_SimpleVolumetricCloud_Inst` exposes a `Coverage` scalar; runtime control is via an MPC or a dynamic
  material instance — confirmed by Epic's Volumetric Cloud docs and `UE5_ART_ASSETS.md` §3a). Clouds are
  lit automatically by the day/night sun, so we touch *only* coverage/density, never cloud colour.
- **Fog mult / tint** → fold into the day/night fog setters (§0). Mist's "8.0×" turns the gentle 0.02
  base haze into a real pea-souper; Blizzard's 12.0× plus a near-white tint is the whiteout.
- **Sun mult / K offset / Sky mult / Shadow sharp** → the light-coupling fields. The Skyrim overcast
  read = **sun down to 0.40, +900K cooler, skylight up to 1.35×, shadows softened to near-nothing** —
  precisely the "diffuse, flat, no hard shadows, melancholy" look the overcast references describe.
  Storm crushes the sun to 0.15 and kills shadows entirely (`ShadowSharpnessMult = 0`).
- **Wetness / Snow** → the **weather MPC**, read by the terrain/water/foliage materials (§5).
- **Wind** → the shared wind vector (§3), feeding clouds, particles, and later foliage.
- **Rain/Snow rate** → the camera-follow Niagara system spawn rates (§4).

> **Why overcast *raises* the SkyLight while *dropping* the sun:** on a real overcast day the whole sky
> becomes one big soft light source — directional contrast collapses, ambient rises. Pushing sun↓ +
> skylight↑ + shadow-softness↑ is the physically-honest move and is exactly what the UE overcast guides
> recommend (reduce directional intensity, lean on SkyLight for soft diffuse fill, desaturate/cool in
> post). The static post-process grade stays put (it's the locked anchor); overcast mood comes from the
> *light balance shift*, not from animating the grade.

---

## 3. Wind — the shared vector that ties it together

Wind is a **single global value** every weather-reactive system reads, so clouds, rain slant, snow drift,
and (later) grass all agree. Standard UE5 pattern (verified): a Blueprint/actor captures a
`WindDirectionalSource` actor's rotation+strength each tick and writes it into a **Material Parameter
Collection** (`MPC_Wind`: a `WindVector` vector param + `WindStrength` scalar). The weather director
*sets* the WindDirectionalSource strength/rotation per state (from the table above), and:

- **Foliage (later):** painted foliage and any WPO wind material samples the `WindDirectionalSource`
  automatically; custom voxel-grass/flora materials read `MPC_Wind` for sway. This is the hook the Godot
  build's `flora_sway` shader already proved out — we re-implement it reading the shared vector.
- **Particles:** feed `WindVector` into the Niagara rain/snow as a **Vector Force** (plus a small
  **Curl Noise** for turbulence) so rain slants and snow swirls with the same wind everything else uses.
- **Clouds:** the cloud material already pans on a wind input; drive its pan speed/direction from
  `WindStrength`/`WindVector` so a storm's clouds visibly race.

Wind strength per state is in the §2 table (Clear 0.1 → Storm/Blizzard 1.0). MVP can ship wind as
*just the cloud pan + particle slant*; foliage coupling is a later, cheap add because it's the same vector.

---

## 4. Particles — camera-following Niagara rain/snow

### 4.1 Architecture (the standard, performance-flat pattern)

One Niagara system **attached to the player camera / pawn** (not scattered across the map), spawning into
a **Box location module sized to a volume above and ahead of the camera** so particles only ever exist
where they're visible. This is the community-standard pattern and matches the Godot camera-following
`GPUParticles3D` already shipping (`UE5_ART_ASSETS.md` §3c). Because the spawn volume is camera-relative,
**cost is flat regardless of the 5 km world size** — that's the whole point.

- **GPU sprite emitters** (not CPU) — snow especially needs thousands of cheap particles. GPU emitters
  keep the count affordable.
- **Rain** = stretched/ribbon sprites for vertical streak motion, slanted by the wind Vector Force.
- **Snow** = soft round sprites, slow fall + lateral drift (Curl Noise + light wind), bigger spawn count,
  longer lifetime.
- **Spawn rate driven by the weather struct** (`RainRate01` / `SnowRate01`): 0 in Clear, lerped up to
  heavy in Storm/Blizzard over the transition. One system, all precipitation states; the director just
  moves the rate.
- **Camera-relative caveat (known gotcha):** in editor *Simulate* mode the system can't read the camera
  location and particles spawn at world origin — it only behaves correctly in PIE/runtime. Note this so
  nobody "fixes" a non-bug.

### 4.2 Interaction with the voxel terrain

- **Collision (rain splashes):** enable Niagara **GPU depth-buffer collision** (cheap, screen-space) so
  raindrops **die on contact and spawn a tiny splash sub-emitter** (a Kenney splash sprite). Depth-buffer
  collision is approximate but free-ish and reads great for rain on the cube tops. *Analytical* collision
  (plane/box) is the alternative if depth-buffer artifacts on thin geometry; for a dense voxel field the
  depth-buffer path is the right default.
- **Splash on water:** the same depth collision lands rain on the water surface; spawn a ripple-ring
  splash there (slightly different sub-emitter / bigger ring). The water material can also receive a
  rain-ripple normal driven by `RainRate01` from the weather MPC (cheap, no particles needed for the
  micro-ripple — particles are just the hero splashes).
- **No voxel writes.** Particles never touch the brickmap. Splashes are pure VFX. Snow that *accumulates*
  is a **material effect** (§5), not a particle that sticks and not a voxel edit. This keeps weather
  entirely off the authoritative voxel store (consistent with the project's "voxel writes through the
  single edit gateway only" rule — weather is not an edit source).

### 4.3 Performance budget

- Keep total live particles bounded by the camera volume; community guidance is to think in **hundreds,
  not unbounded thousands**, per emitter, and cull aggressively with the bounding volume. Snow's higher
  count is offset by cheap round sprites and GPU sim.
- Add a **`Precipitation Camera Fade Distance`**-style fade so particles fade out near the far edge of
  the spawn volume instead of popping.
- Splash sub-emitters are the cost risk in heavy rain — cap their spawn (e.g. only N splashes/frame) and
  use a short-lived flipbook so they don't accumulate.
- Tie particle **scalability** to the engine scalability buckets so low-end drops rain count first.

---

## 5. Voxel-world coupling — wetness & snow as MATERIAL effects (no voxel writes)

This is the phased, optional polish layer. **Everything here is material-side**, reading two scalars from
the **weather MPC** (`Wetness`, `SnowLevel`) — *zero* changes to the brickmap, the mesher, or the
per-face vertex-colour pipeline. The terrain material (`M_VoxelTerrainV2`) gains a small "weather
response" sub-graph that respects the existing sRGB-Power-2.2 decode and the locked exposure.

### 5.1 Wetness (rain darkening + sheen)

Standard UE wet-surface response, gated by the `Wetness` scalar (0..1):

- **Darken albedo** slightly (wet surfaces are darker) — multiply the decoded vertex colour toward ~0.7×
  as wetness rises.
- **Drop roughness** (wet = shinier) and **bump specular** so Lumen reflections sharpen after rain — the
  signature "the world got glossy" read. This is the same wetness lerp the Godot wet-terrain sheen used
  (`UE5_ART_ASSETS.md` §3, "lerp roughness/specular by a wetness scalar in an MPC").
- **Puddles (later, optional):** mask puddles into concavities. Cheapest honest route on voxel terrain is
  a **world-down / low-slope mask** (flat up-facing faces hold water) combined with a noise mask, blended
  to a flat low-roughness "water" response. Full distance-field/heightmap puddles (the Naughty-Dog-style
  technique) are overkill for cubes; the slope+noise puddle mask is the right altitude here. UE5.5+'s
  material-layer system can keep this cheap (wet/dry as layers, ~40% fewer instructions per community
  reports) if instruction count becomes a concern.

### 5.2 Snow accumulation (white-out on up-facing faces)

The classic top-down snow material, gated by `SnowLevel`:

- **World-up dot mask:** `saturate(dot(WorldNormal, SnowDirection))` where SnowDirection ≈ world-up.
  Up-facing cube faces get snow, sides/undersides don't — the standard approach (dot of surface normal
  vs. up, saturated). For our voxels this is *extra clean*: cube faces are axis-aligned, so the top face
  is a perfect 1.0 and sides are 0.0 — snow lands crisply on tops with no fuzzy transition, exactly the
  blocky read we want.
- **`SnowLevel` raises the threshold over time:** as it climbs 0→1, snow first dusts the flattest tops,
  then creeps onto near-flat faces (lower the dot threshold). A little noise breaks up the line so it's
  not a perfect cut.
- **Snow look:** near-white albedo, high roughness, faint sparkle (optional). Because the snow is a
  material *tint over* the existing per-face colour, it costs nothing in the voxel data and melts away
  instantly when `SnowLevel` drops (weather clears → snow recedes). No accumulation history, no voxel
  writes — purely the MPC scalar.
- **Phasing:** snow *particles* (falling) can ship before snow *accumulation* (material). Accumulation is
  the upgrade that makes a blizzard leave a white world behind it.

> **Why material-side and not voxel writes:** writing snow into voxels would mean editing the brickmap
> (mesher re-bake, collision changes, the single-edit-gateway), be slow, and not melt cleanly. A material
> tint keyed on world-up + an MPC scalar gives 90% of the look for ~1% of the cost and zero data risk.
> This is the same instinct as the Godot build deferring "snow accumulate logic" to a surface channel.

---

## 6. Lightning & thunder (Storm state polish)

A Storm-only sub-feature, cheap and high-impact:

- **Lightning flash = a brief spike on a light + a screen-space flash.** On a random timer during Storm
  (every 5–20 s, jittered), pulse a short, bright flash. Cleanest: a dedicated **lightning Directional
  light** (or a temporary boost to the SkyLight / a fullscreen flash material) ramped up for ~0.1–0.25 s
  with a quick falloff, optionally double-flickered. Do **not** spike the day/night sun — keep the flash
  on a separate light so it doesn't fight the controller's sun curve.
- **Lightning bolt VFX (optional):** a Niagara **dynamic beam** with curl noise for the jagged bolt,
  spawned at a random sky position (the community lightning-beam pattern). MVP can skip the visible bolt
  and ship just the flash — the flash alone reads as lightning.
- **Thunder = delayed audio.** Play a thunder cue **after a randomized delay** (1–6 s) following the
  flash, to fake distance (light before sound). Vary the cue + delay for near/far strikes. This is pure
  Blueprint/audio, no rendering cost.
- **Coupling:** lightning only runs while the director's state is Storm (and optionally Blizzard for a
  rarer thunder-snow). Frequency is a designer scalar on the storm state.

---

## 7. Phased rollout (MVP → polish), with effort & risk

The guiding principle: **ship the state-machine + light/cloud/fog blending first** (that alone makes the
world feel alive), then layer particles, then surfaces, then lightning. Each phase is independently
shippable and default-OFF until the designer approves (consistent with the project's "new visual layers
default OFF" rule from the Godot CLAUDE.md, e.g. `rain_visuals_enabled`).

### Phase W1 — MVP: the weather director + atmosphere blending  *(low risk, high payoff)*
- `AMiraWeatherDirector` actor: the state machine (§1), the `FMiraWeatherModifiers` knob box, the
  weighted random walk + biome/season weight table, `SetWeather()` override, 20–30 s blending.
- Wire the **6-line injection** into `AMiraDayNightCycle::ApplyLighting()` (§0) — sun mult, K offset,
  sky mult, fog mult/tint.
- Drive **cloud coverage/density** via the cloud MPC (clear↔overcast). This is the most visible single
  win.
- **Effort:** medium (one new actor + tiny day/night edit + one MPC). **Risk:** low — no new rendering
  tech, all parameter-driving. **Proves:** "the sky changes and the light changes with it, cleanly, with
  the day/night cycle still in charge."

### Phase W2 — Precipitation particles  *(low–medium risk)*
- Camera-follow Niagara rain + snow (§4), spawn rate from the struct, wind slant.
- Rain splash sub-emitter via GPU depth collision; water splash variant.
- Shared **`MPC_Wind`** + WindDirectionalSource driver (§3) — used here first for particle slant.
- **Effort:** medium. **Risk:** medium — Niagara perf tuning + the Simulate-mode camera gotcha. **Default
  OFF** until perf-checked on the streamed world (mirrors `rain_visuals_enabled = false`).

### Phase W3 — Wet & snow surface response  *(medium risk — touches the terrain material)*
- Wetness sub-graph (darken/roughness/specular) in `M_VoxelTerrainV2`, gated by `Wetness` MPC scalar.
- Snow accumulation (world-up dot mask) gated by `SnowLevel`.
- Water-surface rain ripple + wetness coupling.
- **Effort:** medium. **Risk:** medium — must respect the sRGB-2.2 decode + locked exposure so the
  palette doesn't shift (the §0 calibration constraint). Validate against the EV100-11 anchor. **Proves:**
  "rain leaves the world wet and glossy; snow whitens the tops; both melt away as weather clears."

### Phase W4 — Storm/Blizzard + lightning/thunder  *(low risk, additive)*
- Split Storm/Blizzard leaves into the state machine; lightning flash + delayed thunder (§6); optional
  Niagara bolt; whiteout fog for blizzard.
- Foliage wind coupling (later, once foliage exists) reading the same `MPC_Wind`.
- **Effort:** low–medium. **Risk:** low — flash is a separate light, thunder is audio. **Default OFF /
  designer-gated** (matches the legacy `light_shafts_enabled`-style gating).

### Phase W5 (optional) — Fog/Mist polish + god-rays
- Heavy volumetric-fog mist state with light shafts (the day/night controller already enables Volumetric
  Fog; weather just cranks density + tunes scattering). Ground-wisp Niagara for low mist. This leans on
  the existing volumetric fog, so it's mostly tuning. **Risk:** low; **cost watch:** volumetric fog
  resolution scales with the Shadow scalability bucket — heavy mist + storm shadows is the one place to
  profile.

### Effort/risk summary

| Phase | What | Effort | Risk | Default |
|---|---|---|---|---|
| W1 | Director + light/cloud/fog blend | Medium | Low | can be ON (it's just nicer sky) |
| W2 | Niagara rain/snow particles | Medium | Medium (perf) | OFF until perf-checked |
| W3 | Wet/snow materials | Medium | Medium (palette/exposure) | OFF |
| W4 | Storm/lightning/thunder | Low–Med | Low | OFF |
| W5 | Mist/god-ray polish | Low | Low (fog cost watch) | OFF |

---

## 8. Performance notes for the streamed 5 km world (consolidated)

- **Particles are camera-volume-bounded → flat cost** regardless of world size (§4.3). This is the single
  most important perf decision and it's free if we follow the camera-follow pattern.
- **Volumetric Cloud is a known cost** — drive only coverage/density at runtime; keep `View Sample Count
  Scale` low (0.5–0.7 per the atmosphere spec §1.6) and prefer **fake cloud shadows over real cloud
  shadows** in heavy-weather states to claw back frame time.
- **Volumetric Fog cost is dominated by volume-texture resolution** (set by the Shadow scalability
  bucket) and by shadow-casting lights in the fog (~3× for a volumetric-shadowed light). Heavy mist +
  storm is the profiling hotspot; a far **Fog Start Distance** can cut fog cost 50%+.
- **Lumen interaction:** overcast/storm *reduce* directional contrast and lean on the SkyLight — the
  SkyLight already updates via Real-Time Capture (day/night §1.4), so weather changing cloud coverage
  flows into GI automatically with no extra recapture. No Lumen retune needed for weather.
- **Material weather response is near-free** (a couple of lerps + a dot product per pixel) and adds **no
  voxel/data cost** — that's the entire reason §5 is material-side.
- **Blending is CPU-trivial** (lerping ~15 scalars per tick in one actor). The state machine has no
  per-frame cost worth measuring.

---

## 9. Open questions / designer decisions

1. **Random vs. scripted balance:** default to the weighted random walk, or have story beats drive most
   weather? (Plan supports both; default is random with a scripting override.)
2. **Season system:** does the game have seasons yet? The weight tables are season-aware, but if there's
   no calendar yet, ship with a single per-biome table and add the season axis later.
3. **Snow accumulation persistence:** material-tint snow melts the instant weather clears. Is that
   acceptable (cheap, clean) or does the designer want lingering snow (needs a slow-decaying `SnowLevel`
   that outlives the snow state — easy: just lag the dry-down like wetness)?
4. **Night-sky / stars during clear weather** is an atmosphere-spec gap (no CC0 night HDRI sourced yet) —
   weather doesn't need it, but Clear nights will look bare until that asset lands.
5. **Audio:** thunder + rain/wind ambience loops are called for (the Godot build had a weather audio
   envelope, PR #245). Source CC0 weather SFX when W2/W4 land.

---

## 10. Sources

UE5 docs / Epic:
- [Volumetric Cloud Component — UE5.7 docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-cloud-component-in-unreal-engine)
- [Volumetric Cloud Material — UE5.7 docs](https://dev.epicgames.com/documentation/unreal-engine/volumetric-cloud-material-in-unreal-engine)
- [Volumetric Fog — UE5 docs (cost = volume-texture resolution; ~1–3 ms)](https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-fog-in-unreal-engine)
- [Exponential Height Fog — UE5 docs (Fog Start Distance perf)](https://dev.epicgames.com/documentation/unreal-engine/exponential-height-fog-in-unreal-engine)
- [Environmental Light with Fog, Clouds, Sky and Atmosphere — UE5.7 docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/environmental-light-with-fog-clouds-sky-and-atmosphere-in-unreal-engine)
- [Sky Lights in Unreal Engine — UE5.7 docs (Real-Time Capture, overcast fill)](https://dev.epicgames.com/documentation/en-us/unreal-engine/sky-lights-in-unreal-engine)
- [Using Material Parameter Collections — UE5 docs](https://dev.epicgames.com/documentation/unreal-engine/using-material-parameter-collections-in-unreal-engine)
- [Measuring Performance in Niagara — UE5 docs (particle-count guidance)](https://dev.epicgames.com/documentation/unreal-engine/measuring-performance-in-niagara)
- [Day Sequence Time of Day Plugin — UE5 docs (single-controller principle)](https://dev.epicgames.com/documentation/en-us/unreal-engine/day-sequence-time-of-day-plugin-for-unreal-engine)

Community / tutorials:
- [Create Rain in UE5 with Niagara — Epic Community (camera-area spawn)](https://dev.epicgames.com/community/learning/tutorials/GPjd/create-rain-in-unreal-engine-5-with-niagara-quick-and-easy-tutorial)
- [UE5 Rain and Thunder Tutorial — Epic Community (open-world, thunder)](https://dev.epicgames.com/community/learning/tutorials/5nKZ/unreal-engine-5-rain-and-thunder-tutorial)
- [UE5.4 Snow Particle System with Niagara — YouTube](https://www.youtube.com/watch?v=-VYXrpR4Gug)
- [Lightning in UE5 Niagara (dynamic beam + curl noise) — CGHOW](https://cghow.com/lightning-in-ue5-niagara-tutorial/)
- [Create Overcast Day Lighting with Sky Atmosphere — World of Level Design](https://www.worldofleveldesign.com/categories/ue4/overcast-lighting-sky-atmosphere.php)
- [Real-Time Snow Shader for UE5 (world-up dot mask) — Kai Mallari](https://mkai.format.com/real-time-snow-shader-ue5)
- [Setting Up a Detailed Snow Shader in UE5 — 80.lv](https://80.lv/articles/setting-up-a-detailed-snow-shader-in-unreal-engine-5)
- [Up-vector based snow/moss material — Epic forums (dot product approach)](https://forums.unrealengine.com/t/up-vector-based-snow-moss-material-how-to/308798)
- [Dynamic Wetness Setup for Entire Scene — Epic forums](https://forums.unrealengine.com/t/dynamic-wetness-setup-for-entire-scene/1310186)
- [How Naughty Dog does puddles (UE4/UE5) — YouTube](https://www.youtube.com/watch?v=TwPYqOQLStk)
- [UE5 Wind Setup: WindDirectionalSource → MPC → foliage/Niagara — yelzkizi](https://yelzkizi.org/wind-in-unreal-engine-5-winddirectionalsource-foliage-wind-niagara-forces-cloth-and-groom-hair-setup/)
- [Global Wind System Overview — Brushify (WindDirectionalSource → MPC pattern)](https://www.brushify.io/post/wind-system)
- [Mastering Fog: four levels of fog in Unreal — Magnopus](https://www.magnopus.com/blog/mastering-fog-four-levels-of-fog-in-unreal-engine)
- [Crafting the open world of NTE with UE5 (open-world weather perf) — Epic](https://www.unrealengine.com/developer-interviews/crafting-the-urban-open-world-of-nte-neverness-to-everness-with-ue5-across-pc-playstation-5-and-mobile)

Project-internal:
- `Source/MiraThalCore/Sky/MiraDayNightCycle.{h,cpp}` (the controller this layers on; the `ApplyLighting()`
  setter sites are the injection points)
- `design/ATMOSPHERE_LIGHTING_SPEC.md` (actor stack, locked exposure, §2 arbitration intent)
- `design/UE5_ART_ASSETS.md` §3 (CC0 sky/VFX assets; the six-state machine + camera-follow Niagara intent)
- `design/UE5_RENDERING_STRATEGY.md` (Lumen budget 4–7 ms), `design/UE5_VOXEL_MATERIAL_SETUP.md` (sRGB-2.2
  decode + exposure lock the weather materials must respect)
</content>
</invoke>
