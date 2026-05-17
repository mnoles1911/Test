# Weather V2 — atmospheric defaults + elevation-dependent states

**Status:** plan, 2026-05-15. Successor to `design/WEATHER_AND_ENVIRONMENT.md`. Build on top of the existing `WeatherManager` autoload (1167 lines) — this is an additive upgrade, not a rewrite.

## Goals

1. **Each weather state has a complete default fingerprint** — fog tint + density, sky colors, wind, particle density, wet-terrain sheen, ambient audio, ambient brightness — so flipping states changes the world's whole atmosphere, not just a hood-mounted particle puff.
2. **Elevation modifies the state** — a windy gusty zone on high ridges, a snow-and-wind alpine zone at extreme altitude, both layered on top of whatever the schedule rolled. Roland's base-camp at Y=185 sees rain; the peak at Y=300 sees blizzard at the same time.
3. **Zero-snap transitions** — the existing 30 s tween system stays. Every new knob participates in the tween.

## What survives unchanged from current WeatherManager

- The trigger-priority pipeline: `set_weather_override` (story) > proximity WeatherZone stack > scheduled hourly roll.
- `STATE_TICK_INTERVAL_S = 0.1` (10 Hz heavy update).
- Wind direction drift (3°/s turn rate, 90 s target resample) and snapshot-based blend origins so mid-transition target changes don't snap.
- `weather_state_changed` + `weather_intensity_changed` signals.
- Lightning during HEAVY_RAIN.
- Save/load via GameState.

## Base state catalog (extended from current 6 → 8)

The current `STATE_PROFILES` dict carries `fog_color`, `fog_density`, `ambient_dim`, `wind_strength`, `particle_density`, `ambient_audio`. We extend each profile with **new tunable knobs** so a state expresses its whole atmosphere:

| New knob | Type | Purpose |
|---|---|---|
| `sky_top_color` | Color | Top of the procedural sky gradient |
| `sky_horizon_color` | Color | Horizon band |
| `sun_energy` | float | DirectionalLight3D energy multiplier (clouds dim the sun) |
| `sun_color` | Color | Slight tint shift (rain reads cooler, fog reads pearly) |
| `wetness` | 0..1 | Drives wet-terrain `material_override` darkness + roughness drop + spec sheen |
| `rain_density` | int | Particle count (already present in `particle_density`; rename for clarity) |
| `snow_density` | int | Snow particle count (separate so SNOW + LIGHT_RAIN can coexist in transitions) |
| `gust_intensity` | 0..1 | Multiplier on wind audio low-pass + particle slant variance |

Then add ONE new schedulable state to the existing six:

### 1. `CLEAR`
Bright sky. Fog density 0 (haze only). Sun at full energy. No particles. Wind gentle (0.4). Wetness drops to 0. Ambient audio: birds/light wind bed (optional asset).

### 2. `OVERCAST`
Cooler sky tint (gray-blue). Fog density up (~0.012). Sun energy 0.7. Wind moderate (1.0). Wetness 0 still. Ambient: `wind_med.ogg`.

### 3. `LIGHT_RAIN`
Sky desaturates further. Fog up (~0.022). Sun energy 0.55. Wind 1.5. Wetness 0.4 (mild sheen on stone). Rain density ~1500. Ambient: `rain_light.ogg`.

### 4. `HEAVY_RAIN`
Slate sky. Fog 0.045. Sun energy 0.3. Wind 3.0. Wetness 0.85. Rain density ~6000. Lightning armed. Ambient: `rain_heavy.ogg`.

### 5. `FOG`
Pearl-grey sky. Fog 0.09 (very dense). Sun energy 0.5 (diffuse). Wind 0.2. Wetness 0.2 (dew). Ambient: `wind_low.ogg`.

### 6. `SNOW`
Cool blue-white sky. Fog 0.035. Sun energy 0.65. Wind 1.2. Wetness 0 (snow ≠ wet). Snow density ~2500. Ambient: `wind_low.ogg`.

### 7. **NEW: `WINDY`**
Used as a base state for prairie / coastal scenes — full clear sky but persistent gust. Sky like CLEAR; wind 2.8 (felt in particle slant + water waves + cape-flap audio); gust_intensity 0.7 (audio low-pass swells). No rain, no snow. Ambient: `wind_med.ogg` + new `wind_gust.ogg` overlay if available, else `wind_med.ogg` louder.

## Elevation modifier layer (the new bit)

Layer applied **after** the trigger-priority pipeline resolves the active state, **before** profile values are tweened. Computes one of three altitude zones based on the player's current Y, then mixes the base state's profile with a modifier profile.

### Detection (cheap, per-tick at 10 Hz, not per-frame)

```
sea_level_y = WaterFlowManager.get_sea_level_voxel_y() / 6.0  # voxels → meters
player_y_m  = player.global_position.y
altitude_m  = player_y_m - sea_level_y
```

Then classify:

| Zone | Altitude above sea level | Slope check |
|---|---|---|
| `LOWLAND` | < 60 m | — |
| `RIDGE` | 60–110 m | Optional: 3-of-4 horizontal neighbors at terrain_y < player_y − 8 m (reuses the T1 cliff-threshold infra) |
| `ALPINE` | ≥ 110 m | — |

Thresholds tuned to Mira's current generator (sea level Y=125, terrain peaks around Y=300). **All four thresholds (RIDGE start/end, ALPINE start/end) are `@export var` on WeatherManager** so the designer can re-tune from the Inspector without code edits — expect to revisit during playtest, especially for Copper Isles which has a different elevation profile.

The slope check is **optional** for v1. Altitude-only is enough to ship; ridge detection becomes a polish pass once the visual reads naturally.

### Modifier profiles (added on top of the resolved base profile)

**LOWLAND:** no modifier (zero overlay). Base state values pass through.

**RIDGE:**
- `wind_strength_bonus`: +1.5 (added to base) — so CLEAR (0.4) on a ridge feels like 1.9; OVERCAST (1.0) like 2.5.
- `gust_intensity`: 0.6 (audio low-pass swell + 2× particle slant variance).
- `fog_density_bonus`: +0.005 (thin atmospheric haze at altitude).
- No precipitation type change.

**ALPINE:**
- `wind_strength_bonus`: +3.0 (very strong).
- `gust_intensity`: 0.9.
- `fog_density_bonus`: +0.020.
- **Precipitation override:** if base state is LIGHT_RAIN, HEAVY_RAIN, OVERCAST, or FOG → swap to SNOW visuals (rain particles off, snow particles on, ambient bed swaps to `wind_low.ogg` over `rain_*`). CLEAR and existing SNOW pass through unchanged.
- `sun_energy_multiplier`: 0.85 (high overcast at altitude even in CLEAR).

The modifier is interpolated between zones with a soft band:

- 50–60 m: lerp LOWLAND ↔ RIDGE
- 100–110 m: lerp RIDGE ↔ ALPINE

This avoids hard "you crossed a line, suddenly snowing" pops as Roland climbs.

### Why a modifier instead of new states?

A new "ALPINE_BLIZZARD" state would force authoring 8 × N combinations (CLEAR alpine, OVERCAST alpine, LIGHT_RAIN alpine, ...). A modifier layer means: roll the base state from the schedule once, then transparently amplify by altitude. Roland can leave the alpine zone in 60 seconds and the world calmly fades back to the rolled state.

Also lets us add new modifier types later (e.g. proximity to lava: hot+dry, proximity to swamp: humid+miasmic-fog) without rewriting the state machine.

## Save/load

Save: existing keys + `_last_altitude_zone` (string). On load, recompute altitude zone immediately so the resume frame's atmosphere is correct without waiting for the next tick.

## Implementation phases

### Phase A — Profile extension (no new behavior, just more knobs)
- Add `sky_top_color`, `sky_horizon_color`, `sun_energy`, `sun_color`, `wetness`, `snow_density`, `gust_intensity` to all 6 existing `STATE_PROFILES` entries.
- Add `_live_*` mirror fields for each.
- Extend `_snapshot_blend_origins` + `_process_inner` interpolation.
- Wire `sky_top_color` / `sky_horizon_color` into `DayNightCycle.set_sky_override(top, horizon)`.
- Wire `sun_energy` + `sun_color` into the sun DirectionalLight3D (DayNightCycle owns it).
- Wire `gust_intensity` into ambient audio volume modulation (existing `_ambient_player`) + a future low-pass filter bus.
- Acceptance: visuals still match current state at neutral CLEAR; cycling states through F1 → COMMANDS → WEATHER... reads richer (sky tints visibly, sun dims under cloud).

### Phase B — Add `WINDY` state
- Add enum entry + STATE_NAMES + STATE_PROFILES.
- Add to `DEFAULT_RANDOM_DISTRIBUTION` (WINDY 0.08).
- Author `mira_temperate.tres` to include WINDY in the random pool.
- Acceptance: force WINDY via debug menu → strong wind drift, no particles, normal sky.

### Phase C — Elevation modifier layer
- Add `_altitude_zone` enum + `_compute_altitude_zone()` called from `_process_inner`.
- Add `MODIFIER_PROFILES` dict + soft-band interpolation.
- Add `_modifier_wind_bonus`, `_modifier_fog_bonus`, `_modifier_sun_mul`, `_modifier_gust`, `_modifier_precip_override` live fields.
- Resolve final live values = base lerped values × modifier.
- Add `@export var enable_altitude_modifier: bool = true` so dev scenes can opt out.
- Acceptance: spawn at Roland's Y=185 in a HEAVY_RAIN, fly straight up to Y=300, observe rain particles fade out + snow particles spool up + wind strength climb. Walk back down: reverse.

### Phase D — Ridge slope detection (optional polish)
- Add 4-neighbor sample using `VoxelTool.get_voxel` (worker-thread safe via the same pattern bake controller uses) every 1 s, not 10 Hz.
- If 3-of-4 neighbors > 8 m below the player → mark `is_on_ridge = true`.
- Apply a sub-modifier only when both `RIDGE altitude` AND `is_on_ridge` true: +0.5 wind_strength bonus, +0.2 gust_intensity.
- Acceptance: standing on a ridge line in CLEAR feels visibly windier than standing in a saddle 30 m away.

### Phase E — Verification + Settings hook
- Update F1 debug overlay's WEATHER menu to show: `Active: HEAVY_RAIN`, `Altitude zone: RIDGE`, `Modifier: +1.5 wind, +0.005 fog`.
- Add to Settings: a "Storm intensity" slider (0–2× multiplier on `gust_intensity` and particle density) for players who want milder atmospheric effects.
- Acceptance: docs in `design/WEATHER_AND_ENVIRONMENT.md` updated to point at this file; `design/CLAUDE.md` "maintenance" table mentions the new states.

## Open knobs to tune in playtest

- ALPINE threshold height (110 m may be too low for Copper Isles peaks at 800 m).
- Ridge slope detection minimum drop (currently 8 m; might want 12 m to avoid false positives on rolling foothills).
- `WINDY` weight in `DEFAULT_RANDOM_DISTRIBUTION` (0.08 may dominate playtime; tune down if "always windy" is annoying).
- Whether ALPINE should also force overcast sky tint even on CLEAR base (proposal: yes, half-mix with OVERCAST sky_top_color).

## What this is NOT

- Not a weather *generator* (using temperature/humidity/pressure cells). The trigger pipeline + weighted random + authored sequence stays — modeling continental weather fronts is way out of scope.
- Not biome-aware. Wired only by altitude in v1. Biome integration arrives with `set_location_profile` (already exists) — Ashfields profile would weight SANDSTORM, etc.
- Not weather-radar-on-the-map. Players experience weather where they stand; no overhead map indicator.

## References

- `scripts/WeatherManager.gd` — existing autoload, structure to extend.
- `scripts/WaterFlowManager.gd` — `get_sea_level_voxel_y()` for the altitude baseline.
- `extensions/voxel_gen/src/heightmap_generator_base.cpp` — T1 cliff slope threshold infra (reusable for ridge detection).
- `design/WEATHER_AND_ENVIRONMENT.md` — superseded once Phase A lands; cross-link.
- Industry reference: Minecraft snow-line uses biome × Y-level thresholds (Windswept Hills 120±8, Old Growth Pine Taiga 200±8); our altitude-modifier model is simpler but conceptually similar.
- Red Dead 2 / Witcher 3 use authored biome × time-of-day weather pools; our hourly weighted roll + profile system already matches that pattern.
