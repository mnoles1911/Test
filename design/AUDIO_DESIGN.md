# Audio Design

How sound and music work in Game One — what the player hears, why it matters, and how it is implemented.

> Cross-reference: `design/MUSIC_PROMPTS.md` for the full Suno music prompt portfolio.
> `design/SFX_LIBRARY.md` for the master sound-effects inventory (~1,930 entries across 19 categories, incl. weapon-class matrix and magic).
> `design/CONVERSATION_SYSTEM.md` for TTS voice generation and mixing.
> `design/NPC_SYSTEM.md` for bark trigger timing and cooldowns.
> `design/REST_AND_CAMP.md` for camp atmosphere audio.
> `design/COMBAT_DESIGN_3D.md` for combat hit feedback and timing audio cues.

---

## Design Philosophy

**Sound tells the truth when visuals lie.** At voxel resolution, fine detail is limited. A weapon impact communicates weight through audio that the mesh cannot convey. A distant sound implies a world beyond the render distance. Audio earns its keep by doing what the art cannot.

**Silence is a tool.** Not every scene needs underscore. A quiet moment after a difficult fight, a campfire with only the crackle and wind, a long walk with Roland's footsteps and nothing else — these are designed beats, not audio gaps. Silence makes the music matter more when it enters.

**The music knows where it is, not what you are doing.** Music responds to location — entering a city, descending into a dungeon, reaching the open road — not to player actions like attacking or opening a menu. Combat audio is carried by SFX and environmental design. The score does not swell when you swing a sword.

**Diegetic audio first.** When Roland sits by a fire, the fire makes noise. When an NPC speaks, they speak in the world. The TTS pipeline (see `design/CONVERSATION_SYSTEM.md` → TTS Implementation) is integrated into the world — voices come from NPC positions, not from a speaker attached to the camera.

---

## Music System

### Location-Based Layers

Music is organized into **location themes** — not an adaptive combat system. Each major location type has its own theme. Music transitions happen at scene or zone boundaries.

| Location type | Music character | Example |
|---|---|---|
| **Open road / wilderness** | Sparse, acoustic. Solo string or woodwind. Long phrases, room to breathe. | Roland crossing the eastern plains in Act III |
| **Town / settlement** | Warmer, layered. Lute and light percussion. Background energy without urgency. | Aldenholt market |
| **Archive / library / interior** | Low, ambient texture. Almost non-music — a tonal hum, distant bells, quiet room resonance. | The Archive interior |
| **Underground / dungeon** | Minimal and uneasy. Low strings, irregular percussion. Wider intervals. | The Underway passages |
| **Ashfields / ash waste** | Sparse dissonance. Wind and drone. Melody fragments that do not resolve. | Act IV approach |
| **Combat** | No dedicated music. Combat takes place in the world — the existing location theme continues, or drops to ambient. The sound design of the fight carries the tension. | Any fight scene |
| **Camp** | Gentle and safe. Quieter than the travel theme. The sound of rest. | Any campfire scene |
| **Story moments** | Composer-scored, unique cues. Specific to a scene or reveal. Used sparingly — one or two per act. | Henrietta's death; the first Crown piece found |

### Transition Rules

- Location theme fades out over 3–4 seconds when a zone boundary is crossed.
- New location theme fades in over 4–5 seconds after a brief silence gap (~1 second).
- No hard cuts. No sudden swells.
- **Dialogue:** Music ducks (volume reduction) during Dialogic timelines. Does not stop. The world is still there while Roland talks.
- **Rest:** At camp, the active location theme crossfades to the camp theme when the camp menu opens.

### No Dynamic Combat Music

This is a deliberate choice. Adaptive combat music (music that intensifies when enemies detect you) is common in RPGs and trains the player to treat music as a threat indicator. We do not want that. In this game, the music is not the player's radar. Tension in combat comes from SFX, AI telegraphing, and player skill — not a musical intensity layer.

If a specific story beat requires a combat music moment (a boss-equivalent story fight, a desperate last-stand scene), that is a unique authored cue, not a dynamic system.

---

## Sound Effects

### Combat SFX

Every weapon action has audio feedback. The SFX carry the weight that the voxel geometry cannot.

| Action | Audio goal |
|---|---|
| **Light attack** | Quick, sharp edge sound. Not heavy. Communicates speed. |
| **Power attack wind-up** | Roland's breath changes, posture shift sound. Signals commitment. |
| **Power attack land** | Solid impact. Weight. Slightly lower pitched than light attack. |
| **Block (hold)** | A resonant clang with slight scrape. Sustained for as long as block is held. |
| **Parry (tap)** | Sharper ring than the block — a clean deflection. Higher pitch. Immediately satisfying. |
| **Parry window flash (green)** | A brief, soft chime — barely audible, but learnable as a timing cue. Not a UI sound. A real-world resonance from the opponent's stance. |
| **Unblockable (red flash)** | A low thud or growl — not a UI beep. Something in the enemy's stance. |
| **Miss (swing through air)** | Air displacement sound — whoosh with Roland's effort. Communicates the commitment cost of a missed swing. |
| **Roland hit** | Sharp intake of breath, impact sound. Scales with damage amount (glancing = light; heavy = harder). |
| **Roland low HP** | Roland's breathing becomes audible — labored, not theatrical. No heartbeat bass drum. |
| **Enemy death** | Grounded, not theatrical. The sound of something stopping. |

### Environment SFX

Ambient sound layered by location:

- **Campfire:** Crackle, occasional pop. Wind-affected (more flutter when outdoors).
- **Cave/underground:** Distant drips, low resonance, occasional stone shift. No music.
- **Outdoors daytime:** Wind in grass/trees, distant bird calls, insect ambience.
- **Outdoors nighttime:** Wind, crickets, distant owl. Slightly lower overall volume than day.
- **Town/settlement:** Crowd murmur, distant carts, dogs, a bell. Not loud — background.
- **Rain/weather:** See `design/WEATHER_AND_ENVIRONMENT.md` for the full weather audio spec.

### Interaction SFX

Small, clear, satisfying:

| Interaction | Sound |
|---|---|
| Item pickup | Brief cloth/object rustle — not a coin jingle or UI chime |
| Door open | Weight-appropriate creak — a heavy Archive door sounds different than a shack door |
| Container open | Latch click, lid movement |
| Investigation point examined | A subtle intake of breath — Roland noticing something |
| Journal opened | Leather flex, page turn |
| Quick slot item used | Small specific sound per item category (pouring, tearing cloth, glass clink) |
| Save / Wanderer's Seal used | A specific quiet sound: a small bottle emptied, a brief resonance. Manual saves feel weighted. |

### UI SFX

Minimal. Menu navigation uses a single soft click for selection changes and a slightly different click for confirmation. Errors (attempting something not available) use a neutral low thud — not an error buzzer.

No fanfare. No "level up" sound. When a skill tier advances, the notification is a single quiet tone — heard once, not celebrated.

---

## Dialogue and Voice

### TTS Voice Pipeline

All voiced NPC lines go through the ElevenLabs TTS pipeline (see `tools/render_bulk.py` and `tools/README.md`). Each character has a locked voice profile with specific parameters. Calibration clips are required before any bulk generation.

**Voice source positions:** Character voices play from the NPC's world position. Roland's internal monologue and his voiced investigation observations play from the player position with slight spatial processing — they feel internal but are placed in the world.

**Mixing:** Dialogue voices are on a dedicated audio bus with slight room processing applied per environment (dry for outdoor, a touch of reverb for interiors/caves). The player can adjust voice volume independently in Settings.

### Bark Audio

Bark lines (Tier 1 and ambient Tier 2 barks) play from the NPC's AudioStreamPlayer3D. Cooldown enforcement is handled by `BarkManager.gd` — the audio system does not need its own cooldown logic.

For bark file naming, folder structure, and voice ID conventions: `design/CONVERSATION_SYSTEM.md` → TTS Implementation.

---

## Audio Buses

Recommended Godot audio bus layout:

```
Master
├── Music          — location themes, story cues
├── SFX            — all in-world sounds
│   ├── Combat     — attack, impact, block sounds (useful for separate combat mix)
│   └── Ambient    — fire, wind, crowd, environment loops
├── Voice          — NPC dialogue and Roland observations
│   ├── NPC        — spatial 3D voices
│   └── Roland     — player-position monologue
└── UI             — menu sounds, journal sounds, bark overlay ticks
```

The player can adjust **Music**, **Voice**, and **SFX** volume independently in Settings. The UI bus is not exposed to player settings — it scales with Master.

---

## Audio File Conventions

- All audio files: `.ogg` format (Godot-native, small file size, good quality)
- Music: stereo, 44.1 kHz
- SFX: mono (spatialized in-engine via AudioStreamPlayer3D), 44.1 kHz
- Voice: mono, 24 kHz minimum (ElevenLabs default output is acceptable)
- Folder structure:
  ```
  assets/audio/
  ├── music/            — location themes and story cues
  ├── sfx/
  │   ├── combat/       — weapon and impact sounds
  │   ├── environment/  — fire, wind, ambient loops
  │   └── interaction/  — doors, items, investigation
  ├── voice/
  │   ├── barks/        — by npc_id/trigger_variant.ogg
  │   └── scenes/       — voiced timeline lines, by scene/line_id.ogg
  └── ui/               — menu interaction sounds
  ```

---

## GDScript Notes

### AudioStreamPlayer3D for NPC barks

```gdscript
# In NPC.gd — bark audio is attached to the NPC node:
@onready var bark_audio: AudioStreamPlayer3D = $BarkAudioPlayer

func play_bark_audio(file_path: String) -> void:
    var stream: AudioStream = load(file_path)
    if stream:
        bark_audio.stream = stream
        bark_audio.play()
```

### Music transition via TransitionManager hook

```gdscript
# Music should crossfade when scenes change.
# Attach a MusicPlayer autoload that listens for TransitionManager's scene_changed signal:
func _on_scene_changed(new_scene_id: String) -> void:
    var theme_path: String = SCENE_THEMES.get(new_scene_id, "")
    if theme_path != current_theme:
        _crossfade_to(theme_path)
```

### Roland low HP audio state

```gdscript
# In PlayerStats.gd — emit a signal when HP crosses a threshold:
signal hp_threshold_changed(threshold: String)  # "critical", "low", "normal"

func _check_hp_thresholds() -> void:
    var ratio: float = current_hp / max_hp
    if ratio < 0.1:
        emit_signal("hp_threshold_changed", "critical")
    elif ratio < 0.3:
        emit_signal("hp_threshold_changed", "low")
    else:
        emit_signal("hp_threshold_changed", "normal")
# AudioManager listens and adjusts Roland's breathing layer accordingly.
```
