# Accessibility & Settings Design

The settings available to the player and the accessibility features built into Game One.

> Cross-reference: `design/INPUT_AND_CONTROLS.md` for the full control scheme and remapping.
> `design/HUD_AND_UI.md` for the pause menu and settings entry point.
> `design/AUDIO_DESIGN.md` for the audio bus layout and volume controls.

---

## Design Philosophy

**Settings are not an afterthought.** The settings screen is where the player configures the game to work for them. Options that seem minor — subtitle size, contrast, hold-vs-toggle — are significant to specific players. These options cost little to implement and mean a great deal.

**Accessibility and options are the same thing.** We do not separate "accessibility settings" into a buried submenu. All settings that adjust how the game works for different needs sit alongside the standard settings. A player who needs larger text and a player who wants a different key bind are both adjusting the game to work for them. The UI treats both the same.

**Defaults are for the modal player.** The default settings should work well for most players with no changes. Options exist to serve players whose needs differ from the default. The defaults are not the correct answer — they are the starting point.

---

## Settings Categories

Settings are organized into four tabs in the Settings screen (accessed from the Pause Menu or Main Menu):

1. **Display**
2. **Audio**
3. **Controls**
4. **Accessibility**

---

## Display Settings

| Setting | Default | Options | Notes |
|---|---|---|---|
| **Resolution** | Native | System display resolutions | Godot's standard resolution list |
| **Display mode** | Windowed | Windowed / Borderless / Fullscreen | |
| **VSync** | On | On / Off / Adaptive | |
| **Target FPS** | 60 | 30 / 60 / 120 / Unlimited | Capped options; Unlimited for high-refresh displays |
| **Render scale** | 100% | 50% / 75% / 100% | Reduces internal render resolution; useful for performance on lower-end hardware |
| **Shadow quality** | Medium | Low / Medium / High | Adjusts `DirectionalLight3D` shadow map resolution |
| **SSAO** | On | On / Off | Screen-space ambient occlusion; significant visual impact and performance cost |
| **Fog density** | Normal | Off / Low / Normal | Affects the WorldEnvironment fog. Off is useful for players with vestibular or depth-perception differences. |
| **Motion blur** | Off | Off / Low / High | Off by default — many players find it uncomfortable |
| **Brightness** | 50 | 0–100 slider | Adjusts `WorldEnvironment` exposure |
| **Gamma** | 50 | 0–100 slider | Post-process gamma correction |
| **Field of View** | 75° | 60°–100° | SpringArm3D camera FOV; wider FOV shows more world but may cause discomfort at extremes |
| **View distance** | 600m | 200m / 400m / 600m / 1km / 1.5km / 2km | LOD streaming horizon for the procedural voxel terrain. Higher = more world visible at distance, more GPU + memory cost. |
| **Edit detail radius** | 64m | 32m / 64m / 96m / 128m / 192m / 256m | How far out player-edited terrain chunks render at LOD0 (full block precision). Beyond this distance, edited chunks render from a cached LOD-baked mesh — still visible (e.g. your house from across the valley) but without per-block detail. Mandatory floor of 32m for collision safety; cannot go below. Higher = sharper distant edits, more GPU cost when many edits exist. |

### Notes on the Voxel Sliders

**View distance** is the standard "render distance" knob — it bounds how far procedural terrain streams. Hardware-bound. On low-end machines, drop to 400m. On high-end, push to 1.5km or 2km if you want long-sightline vistas.

**Edit detail radius** is the destructible-terrain analog. It only affects chunks that have actual player edits — for a player who hasn't done much terraforming, the setting is invisible. For a player who has built a small house and dug a few mines, it controls whether those structures stay crisp from far away or render in chunky LOD.

The 32m floor is hardcoded — it's the safety boundary where collision and rendering must agree. Edit detail radius can never go below this; the slider's lower stop is 32m. View distance has no lower-bound dependency on edit detail radius; the two sliders are independent.

---

## Audio Settings

| Setting | Default | Options | Notes |
|---|---|---|---|
| **Master volume** | 80 | 0–100 slider | Controls Godot's Master audio bus |
| **Music volume** | 70 | 0–100 slider | Controls Music audio bus |
| **SFX volume** | 80 | 0–100 slider | Controls SFX audio bus |
| **Voice volume** | 90 | 0–100 slider | Controls Voice audio bus (NPC dialogue + Roland observations) |
| **UI sounds** | 60 | 0–100 slider | Controls UI audio bus |
| **Mute when unfocused** | On | On / Off | Mutes Master when the window loses focus |

Audio settings write directly to Godot's AudioServer bus volume. They persist in the settings file.

---

## Controls Settings

| Setting | Default | Description |
|---|---|---|
| **Keybindings** | See `design/INPUT_AND_CONTROLS.md` | Full remap UI — every action listed, click to rebind |
| **Controller vibration** | On | Enables/disables controller rumble (haptic feedback) |
| **Controller stick deadzone** | 0.15 | 0.05–0.35 slider; higher values prevent drift on worn controllers |
| **Mouse sensitivity** | 50 | 0–100 slider; affects camera rotation and menu navigation speed |
| **Invert Y (controller)** | Off | Inverts right stick vertical axis for camera tilt |

### Keybinding UI

Every action from `design/INPUT_AND_CONTROLS.md` appears in the keybinding list. The player clicks an action and then presses the desired key or button. Conflicts are flagged (the UI shows which action currently uses that input) but not automatically resolved — the player decides.

**Reset to defaults** button at the bottom of the Controls tab restores all bindings to their defaults.

---

## Accessibility Settings

| Setting | Default | Options | Notes |
|---|---|---|---|
| **Subtitles** | On | On / Off | Subtitles for all voiced dialogue and important barks |
| **Subtitle size** | Medium | Small / Medium / Large / Extra Large | Scales subtitle text size |
| **Subtitle background** | Semi-transparent | Off / Semi-transparent / Solid | Improves readability against bright backgrounds |
| **Subtitle speaker name** | On | On / Off | Shows character name before each subtitle line |
| **Parry flash style** | Color | Color / Shape / Color+Shape | The parry timing flash (green/red/yellow) can add a shape cue for colorblind players |
| **High contrast HUD** | Off | Off / On | Increases contrast on HP/Endurance bars and quick slot indicators |
| **HUD scale** | 100% | 75% / 100% / 125% / 150% | Scales all HUD elements |
| **Hold vs toggle — sprint** | Hold | Hold / Toggle | Toggle sprint means one press to start, one to stop |
| **Hold vs toggle — block** | Hold | Hold / Toggle | Toggle block stays active until pressed again |
| **Auto-block** | Off | Off / On | Bannerlord-style passive blocking — any RMB hold blocks any direction at full effectiveness. Removes the directional read requirement. |
| **Direction input mode** | Mouse | Mouse / WASD modifier | How attack direction is selected — mouse flick (default) vs WASD held + LMB |
| **Screen shake** | Normal | Off / Reduced / Normal | Camera shake on large hits and explosions; Off for vestibular sensitivity |
| **Vignette on low HP** | On | On / Off | The screen-edge darkening at low HP; Off removes it |
| **Combat timing assistance** | Off | Off / Lenient | Lenient: parry and power attack charge windows are 25% wider. Does not affect other systems. |
| **Reduce particle effects** | Off | Off / On | Reduces rain density, fire particles; useful for performance or photosensitivity |

### Notes on Specific Settings

**Parry flash style:** The three flash colors (green = parryable, yellow = blockable at cost, red = unblockable) are distinguishable to most players. For deuteranopia (red-green colorblindness), the green/red distinction is the problem. Shape+Color mode adds: triangle for parryable, square for block, X for dodge-only. These appear as an overlay on the enemy — subtle enough not to dominate the screen, clear enough to be usable.

**Combat timing assistance:** This setting acknowledges that some players will find the parry timing deeply frustrating without it. Widening the window by 25% does not trivialize combat — Ashfallen are still dangerous — but it lowers the floor. It is not labeled "Easy Mode." It is a timing adjustment.

**Subtitles default on.** This is the accessible default. Turning subtitles off is an explicit choice the player makes, not the starting state. Voiced content should never be the *only* way to receive information — subtitles are required for all plot-relevant voice lines.

---

## Settings Persistence

Settings are stored in `user://settings.cfg` via Godot's `ConfigFile` class. They load on startup and apply before the main menu displays. If the file is missing or corrupted, defaults apply and the file is rewritten.

Settings that affect Godot engine properties (resolution, VSync, MSAA, audio bus volumes) are applied immediately when changed. Settings that affect gameplay logic (parry window, hold/toggle behavior) are applied on the next relevant interaction.

---

## GDScript Notes

### Settings.gd autoload (existing)

`Settings.gd` is already an autoload (from Milestone 4 infrastructure). It should be extended to cover the full settings list above. Key additions:

```gdscript
# Settings.gd additions:

# Accessibility flags read by other systems:
func get_parry_window_multiplier() -> float:
    return 1.25 if get_value("accessibility", "combat_timing_assistance") else 1.0

func get_hud_scale() -> float:
    return get_value("accessibility", "hud_scale", 1.0)

func get_parry_flash_style() -> String:
    return get_value("accessibility", "parry_flash_style", "color")

# CombatHandler.gd reads parry window:
var parry_window: float = BASE_PARRY_WINDOW * Settings.get_parry_window_multiplier()

# HUD nodes read scale on ready:
func _ready() -> void:
    scale = Vector2.ONE * Settings.get_hud_scale()
```

### Hold/toggle sprint

```gdscript
# Player3D.gd — respects sprint hold/toggle setting:
var _sprint_toggled: bool = false

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("sprint"):
        if Settings.get_value("controls", "sprint_mode") == "toggle":
            _sprint_toggled = not _sprint_toggled
        # Hold mode is handled by Input.is_action_pressed("sprint") in _physics_process

func _is_sprinting() -> bool:
    if Settings.get_value("controls", "sprint_mode") == "toggle":
        return _sprint_toggled
    return Input.is_action_pressed("sprint")
```

### Subtitle display

```gdscript
# SubtitleManager.gd (or handled by Dialogic for dialogue; separate for barks):
func show_subtitle(speaker: String, text: String) -> void:
    if not Settings.get_value("accessibility", "subtitles_enabled", true):
        return
    var show_name: bool = Settings.get_value("accessibility", "subtitle_speaker_name", true)
    var display_text: String = ("[b]%s:[/b] %s" % [speaker, text]) if show_name else text
    subtitle_label.text = display_text
    subtitle_label.add_theme_font_size_override("font_size", _get_subtitle_size())
```
