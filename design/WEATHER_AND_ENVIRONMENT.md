# Weather & Environment Design

How the world's conditions change over time and affect gameplay, atmosphere, and navigation.

> Cross-reference: `design/NPC_SYSTEM.md` for WorldClock time-of-day periods.
> `design/AUDIO_DESIGN.md` for weather audio layers and ambient sound.
> `design/REST_AND_CAMP.md` for how weather affects camp and rest.
> `design/ART_DIRECTION.md` for palette and shader direction per environment.
> `design/ART_PIPELINE.md` for WorldEnvironment settings in Godot.

---

## Implementation status (2026-05-04)

The visual core is live in `scripts/WeatherManager.gd` (autoload). Six-state
machine with 30 s transitions; three trigger sources (story override /
proximity zone / scheduled random) resolved by priority.

**Shipping:** state machine + tween, fog override via `DayNightCycle.set_fog_override`,
ambient dim, wind to water shader (with gradual 3°/s direction drift independent
of state changes), rain + snow `GPUParticles3D` (camera-following, particle
amount tweens with state), `RainOverlay` `CanvasLayer` mood tint,
wet-terrain `material_override` specular sheen, directional lightning
(`OmniLight3D` flash + 3D spatial thunder with realistic distance delay),
`WeatherLocationProfile` resource for per-region authoring (aldenholt.tres
seeded), `WeatherZone` `Area3D` proximity stack, save/load round-trip,
debug overlay submenu with one button per state + FORCE LIGHTNING +
CLEAR OVERRIDE + live state/wind readouts.

**Deferred (per design decision — visual-only system):**
- Gameplay hazards (footstep sound coupling, enemy detection-range
  modifiers, combat consequences). Hooks public; future PR can add.
- Snow ground accumulation. Particles fall but voxels don't whiten —
  needs a per-face wetness/snow channel and shader work.
- Region-boundary auto-swap of location profile. v1 ships one global
  profile; call `WeatherManager.set_location_profile(profile)` to swap.
- Interior weather isolation. `InteriorDetector` not yet present; v1
  treats every scene as exterior.
- Sun-pulse during lightning (would conflict with `DayNightCycle`'s
  per-frame sun-energy write). Defer until `DayNightCycle` gains a
  sun-energy override hook.

---

## Design Philosophy

**Weather is atmosphere, not obstacle.** Rain does not cancel quests. Fog does not make enemies invisible. Snow does not freeze Roland solid. Weather communicates the world's mood, frames the emotional register of a scene, and adds texture to traversal. It is not a survival mechanic.

**The world has weather. It is not random.** Weather is authored per act and per location, not procedurally generated. Act I has a specific feel — late autumn, overcast, with occasional rain. The Ashfields are permanently ashen and hazy. The Spine road in Act III is cold and clear. The player experiences a designed progression, not a roll of the die each morning.

**Weather reacts to story when it matters.** A scene of revelation during a storm is not coincidence — it is authorship. Weather can be tied to specific story beats via FlagScheduler or scripted scene triggers. The rest of the time it follows a default cycle.

---

## Time of Day System

WorldClock drives time of day. Each in-game hour corresponds to a `TimeOfDayPeriod`:

| Period | Hours | Description |
|---|---|---|
| DAWN | 5–7 | Sun rising, mist, cool light. NPCs begin morning activities. |
| MORNING | 7–12 | Full day activity. Clear, warm-toned light. |
| AFTERNOON | 12–17 | Peak activity. Slightly warmer, more saturated. |
| DUSK | 17–19 | Golden hour. NPCs transitioning to evening activities. |
| EVENING | 19–22 | Fires lit, indoor activities, darker shadows. |
| NIGHT | 22–5 | Dark. NPC movement minimal; guards on patrol. |

WorldClock emits `time_of_day_changed(new_period)` when a period boundary is crossed. Subscribers:
- **DirectionalLight3D** — color and angle update
- **WorldEnvironment** — fog density, ambient light level, sky color
- **NPC schedules** — `update_schedule(hour)` called on all `scheduled_npcs` group members
- **Music system** — some location themes have day/night variants
- **Weather system** — probability weights shift by period (rain more likely at dawn/dusk)

---

## Weather States

Six weather states for outdoor zones. Interior scenes are always unaffected by outdoor weather.

| State | Visual | Audio | Gameplay effect |
|---|---|---|---|
| **Clear** | Full sky visibility, sharp shadows | Ambient wind, birdsong | None |
| **Overcast** | Flat grey sky, softer shadows | Heavier wind, fewer birds | Visibility unchanged |
| **Light Rain** | Rain particle effect, wet surfaces | Rain layer, reduced ambient | Minor: Roland's footstep sounds change |
| **Heavy Rain** | Denser rain particles, darker sky | Heavy rain, thunder (distant) | Detection range for enemies reduced by 20% |
| **Fog** | Reduced view distance, diffuse light | Muted ambient, dripping | Vision range for both Roland and enemies reduced |
| **Snow** | Snow particles, white ground cover | Muffled ambient, wind | Footstep sounds change; NPC outdoor activity reduced |

**Ash haze** — a special state for the Ashfields (Act IV). Not rain or snow — a permanent low-visibility condition from airborne volcanic ash. Slightly reduced sight lines, a grey-orange cast to all lighting, ambient sound of wind through ash.

---

## Weather Scheduling

Weather is driven by a simple authored sequence per act/location, advanced by WorldClock day changes.

**Example — Act I (Aldenholt region):**

```
Day 1: Overcast
Day 2: Light Rain (dawn–morning), then Clear
Day 3: Clear
Day 4: Overcast
Day 5+: Default cycle (weighted toward Overcast/Clear in late autumn)
```

This authored sequence applies for the first few days. After that, a weighted random selection runs each WorldClock day change — biased toward the location's "default" weather character.

**Location weather characters:**

| Location | Default | Variation |
|---|---|---|
| Aldenholt / Spine road approach | Overcast, cool | Rain 2–3 days per week (in-game) |
| Caer Brannoch | Wet, coastal | Heavy rain 1 day per week |
| Solgrade | Clear, dry | Light rain rare |
| Vosskara frontier | Gusty, variable | Fog at dawn common |
| Aelorin Greatwood | Misty, calm | Always filtered light; no heavy rain |
| Underway / Caves | N/A (no weather) | — |
| Ashfields | Ash haze (permanent) | Visibility varies by wind state |

---

## Weather and Story Beats

Specific scenes can override the weather cycle with a scripted state:

```gdscript
WeatherManager.set_weather_override("heavy_rain", duration_hours)
```

The override holds for the specified in-game hours (WorldClock hours), then returns to the scheduled state.

**Authored beat examples:**
- The night chase through Aldenholt (Act I) — always heavy rain. Noise cover. Atmosphere.
- Arriving at Lirien-Thal for the Aelorin audience — always the Greatwood misty-calm state. The Aelorin do not receive guests during storms.
- The Ashfields approach (Act IV) — ash haze intensifies as Roland nears Drûn-Khazad.

---

## Environmental Hazards

Weather and environment create minor gameplay texture — not survival threats.

**Rain:**
- Heavy rain reduces enemy vision range and hearing range slightly. Roland can use this tactically: an enemy with a 12m vision range in clear conditions may not spot Roland at 10m during heavy rain.
- No direct damage to Roland from rain.

**Fog:**
- Reduces both Roland and enemy detection distances symmetrically. More dangerous than rain, not less — enemies are also harder to spot.
- Orion's bark lines include fog-specific observations about navigation and exit identification.

**Night:**
- Reduces vision range for enemies (they rely more on hearing). Roland's vision is not mechanically limited — the player can see, but must be careful about sound (sprinting is loud).
- Torches and lanterns: Roland can carry a torch (equips to off-hand slot, cannot block while holding). Increases local light radius, slightly increases Roland's visibility to enemies. Design tradeoff.

**Snow:**
- NPC outdoor patrol frequency drops (fewer enemies on the road).
- No movement penalty for Roland.

---

## Godot Implementation

### WorldEnvironment settings per state

The `WorldEnvironment` node in each outdoor scene uses a `Environment` resource. Weather states swap or blend between preset Environment resources:

```gdscript
# WeatherManager.gd (new autoload):
func _apply_weather_state(state: String) -> void:
    var target_env: Environment = WEATHER_ENVIRONMENTS[state]
    # Tween fog density, ambient light, sky color to target values over 30 seconds
    _tween_to_environment(target_env, 30.0)
```

Weather transitions are slow (30+ seconds) — not instant cuts. The sky darkens gradually as clouds roll in.

### Rain particles

Rain is a `GPUParticles3D` node positioned above the player (follows the camera rig, not a fixed world position). Light rain uses a sparse particle count; heavy rain uses a dense count. The particle system is inactive during Clear/Overcast states to save performance.

### Footstep sound variant

The player's footstep audio switches to a "wet" variant when the active weather state is Light Rain or heavier:

```gdscript
# In Player3D.gd footstep handler:
func _get_footstep_sound() -> String:
    var base: String = "res://assets/audio/sfx/footsteps/"
    if WeatherManager.current_state in ["light_rain", "heavy_rain", "snow"]:
        return base + surface_type + "_wet.ogg"
    return base + surface_type + ".ogg"
```

### Interior zone weather isolation

Interior scenes (`World = separate .tscn file`) do not have a `WeatherManager`. Rain sounds from outside can be heard (a looping ambient layer that plays when the indoor scene is loaded and the outdoor weather state is rain), but no particles, no fog, no lighting change.

### Water surface coupling

The custom water shader (`assets/shaders/water.gdshader`) reads two uniforms — `wind_dir` (Vector2 in world XZ) and `wind_strength` (0–5) — that bias wave direction and scale wave amplitude. `WaterVolume.gd` exposes `wind_direction` (Vector3 XZ) and `wind_strength` `@exports`, plus a `set_wind(direction: Vector3, strength: float)` method for programmatic updates.

When `WeatherManager` lands, on every weather state change (or every `WorldClock` tick during smoothed transitions) it iterates every Area3D in the `water_volume` group and calls `set_wind(weather.wind_direction, weather.wind_strength)` on each. Strength conventions:

| Weather | wind_strength |
|---|---|
| Clear (calm) | 0.5 |
| Breeze | 1.0 |
| Rain | 2.0 |
| Storm / blizzard | 3.5 |
| Lethal storm (scripted) | 5.0 |

Smoothing (lerping wind values over a few seconds rather than snapping at state change boundaries) is `WeatherManager`'s responsibility, not `WaterVolume`'s. `WaterVolume.set_wind` snaps; the manager calls it on every interpolation step.

Until `WeatherManager` ships, designers tune wind values per body via the inspector. See `design/SWIMMING_AND_WATER.md` → "Wind & Weather Coupling" for the full WaterVolume API.

---

## GDScript Notes

### WeatherManager autoload

```gdscript
# WeatherManager.gd — add to Autoloads
var current_state: String = "clear"
var override_state: String = ""
var override_hours_remaining: float = 0.0

func set_weather_override(state: String, hours: float) -> void:
    override_state = state
    override_hours_remaining = hours
    _apply_weather_state(state)

func _on_hour_advanced(new_hour: int) -> void:
    if override_hours_remaining > 0.0:
        override_hours_remaining -= 1.0
        if override_hours_remaining <= 0.0:
            override_state = ""
            _apply_scheduled_weather()
    else:
        _apply_scheduled_weather()
```

### Time-of-day lighting via WorldClock signal

```gdscript
# LightingManager.gd — or directly in World3D.tscn's script:
func _on_time_of_day_changed(new_period: WorldClock.TimePeriod) -> void:
    var config: Dictionary = LIGHTING_CONFIGS[new_period]
    sun_light.light_color = config.sun_color
    sun_light.light_energy = config.sun_energy
    sun_light.rotation_degrees.x = config.sun_angle
    world_env.environment.ambient_light_energy = config.ambient_energy
    # Tween all values over ~5 minutes of in-game time for smooth transitions
```
