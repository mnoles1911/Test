# Bark Library

Reusable bark patterns for any character, in any region, in any situation. Lore-agnostic.

> **Bark = Tier 1 dialogue per `design/CONVERSATION_SYSTEM.md`.** A short voiced or text line that fires in-world, does not pause the game, does not take over the camera, and does not lock player input. Barks are the connective tissue between scripted scenes — they make the world feel inhabited.

> **Authoring rules:** all bark scripts must conform to `dialogue/STYLE.md`. Place the production scripts under `dialogue/scripts/barks/{category}/{character}.txt`.

---

## Why a Library

Barks are the highest-volume dialogue in the game. A single companion may have 200+ bark lines across the full trilogy. Without a library, writers reinvent categories per character and important triggers get missed.

The library is a **checklist**: when assigning bark content to a new character, walk every category and decide whether they need lines for it. Empty categories are fine. Forgotten categories are not.

---

## Bark Authoring Rules

These rules apply to every category below.

1. **Length cap.** A bark is one or two short sentences. If it doesn't fit in 4 seconds of voiced audio, it is not a bark — it is a Tier 2 conversation.
2. **Variant pools.** Every bark trigger has 3–5 variant lines. The system picks one at random. A single line repeated breaks immersion within minutes.
3. **Cooldowns.** No bark trigger fires more than once per 30–60 seconds, even if the conditions repeat. Stack-up is the most common bark failure.
4. **Tag economy.** One tag per bark line, max. Trust the line.
5. **Punctuation over tags.** Use `...` for breath, `--` for cut-off, ALL CAPS for emphasis (per STYLE.md).
6. **Voice or text fallback.** Barks should be voiced for player and major companions. NPCs may use text-only barks if voice budget is constrained.
7. **Subtitle policy.** Voiced barks always include a text overlay for accessibility.

---

## Category 1 — Combat Barks

Triggered by combat state. The most volume-heavy bark category.

| Trigger | Frequency rules | Length | Tag suggestions |
|---|---|---|---|
| Combat engaged (first sight of enemy) | Once per encounter | Short | `[determined]` `[shouting]` `[fearful]` |
| Striking blow / hit landed | 1 in 4 hits | Very short | `[shouting]` `[fast]` |
| Heavy blow / critical landed | 1 in 3 crits | Short | `[shouting]` `[determined]` |
| Taking damage (light) | 1 in 5 hits | Very short | `[gasp]` `[fast]` |
| Taking damage (heavy) | Always | Short | `[shouting]` `[fearful]` `[gasp]` |
| Low HP / critical state | Once when crossing threshold, then 60s cooldown | Short | `[out of breath]` `[fearful]` |
| Ally down / companion in trouble | Always | Short | `[shouting]` `[fearful]` `[determined]` |
| Stealth — spotting enemy first (undetected) | Once per encounter | Whisper | `[whispering]` `[serious tone]` |
| Stealth — detected by enemy | Always | Short | `[shouting]` `[surprised]` |
| Stealth — lost line of sight (enemy giving up) | Once per de-aggro | Short | `[quietly]` |
| Killing blow / kill confirmation | 1 in 4 kills | Very short | `[determined]` `[matter-of-fact]` |
| Out of resources (no stamina/mana/ammo) | Once when first triggered, 30s cooldown | Short | `[frustrated]` |
| Combat won / encounter ended | Always | Short | `[out of breath]` `[tired]` `[determined]` |
| Combat retreat / fleeing | Once per encounter | Short | `[out of breath]` `[fearful]` |

### Authoring template (combat engagement)

```
{SPEAKER}: [determined] Three of them.
{SPEAKER}: [serious tone] Stay close.
{SPEAKER}: [out of breath] They saw us.
{SPEAKER}: [fast] Weapons.
{SPEAKER}: [quietly] Here we go.
```

A pool of 5 lines. The system picks one. Variation is what keeps combat feeling alive.

---

## Category 2 — Exploration & Movement Barks

Triggered by location, traversal, or environmental state.

| Trigger | Frequency rules | Length | Tag suggestions |
|---|---|---|---|
| Entering a new region (first time) | Once per region | Medium | `[awe]` `[curious]` `[reflective]` |
| Entering a new region (returning) | Once per session, if 30+ mins since last visit | Short | `[wistful]` `[matter-of-fact]` |
| Spotting a point of interest (vista, ruin, landmark) | Once per object | Short | `[awe]` `[curious]` |
| Discovering loot / treasure container | 1 in 3 containers | Very short | `[lighthearted]` `[surprised]` |
| Discovering rare loot | Always | Short | `[surprised]` `[curious]` |
| Investigation point — generic environmental | 1 in 2 investigations | Short | `[curious]` `[reflective]` |
| Investigation point — story-significant | Always | Medium | `[reflective]` `[serious tone]` |
| Locked or impassable obstacle | Once per obstacle, 60s cooldown | Short | `[frustrated]` |
| Lockpicking / interaction success | 1 in 4 successes | Very short | `[matter-of-fact]` `[lighthearted]` |
| Long travel / fatigue | Triggered after N minutes traveling | Short | `[tired]` `[out of breath]` |
| Backtracking (returning to known area) | Once per session per area | Short | `[matter-of-fact]` |
| Dead end / wrong direction | Once per dead-end, 60s cooldown | Short | `[frustrated]` `[quietly]` |

### Authoring template (entering a new region)

```
{SPEAKER}: [awe] {LOCATION_NAME}. Smaller than the maps suggested.
{SPEAKER}: [reflective] I have read about this place. It is different in person.
{SPEAKER}: [curious] So this is {LOCATION_NAME}.
{SPEAKER}: [quietly] We made it.
{SPEAKER}: [matter-of-fact] {LOCATION_NAME}. Finally.
```

Variation in tone matters as much as variation in words. The "awed" line, the "curious" line, the "tired" line each give the player a different read of the character's relationship to the place.

---

## Category 3 — Reactive & Contextual Barks

Triggered by environmental conditions or world-state changes.

| Trigger | Frequency rules | Length | Tag suggestions |
|---|---|---|---|
| Weather change (rain start, storm, snow) | Once per weather change, 5 min cooldown | Short | `[shivering]` `[matter-of-fact]` `[wistful]` |
| Time of day (dawn, dusk, deep night) | Once per transition, scene-dependent | Short | `[reflective]` `[wistful]` `[tired]` |
| Faction territory entered | Once per territory transition | Short | `[serious tone]` `[curious]` |
| Hostile territory / dangerous area | Once on entry, 5 min cooldown | Short | `[serious tone]` `[whispering]` |
| Friendly / safe area | Once on entry per session | Short | `[lighthearted]` `[reflective]` |
| NPC nearby reacts to player | NPC-driven, see NPC dialogue library | Very short | `[matter-of-fact]` `[curious]` |
| Approaching a story-relevant location | Once per story beat unlock | Medium | `[serious tone]` `[reflective]` |
| Weather-triggered comfort/discomfort | After 30s in weather state | Short | `[shivering]` `[tired]` |

### Authoring template (entering hostile territory)

```
{SPEAKER}: [serious tone] We are in their lands now.
{SPEAKER}: [whispering] Quiet from here.
{SPEAKER}: [quietly] I do not want to be the one they noticed first.
```

Hostile territory barks should feel like advice, not melodrama. One per zone entry, then silence.

---

## Category 4 — Idle & Ambient Barks

Triggered by player inactivity or time-based pacing.

| Trigger | Frequency rules | Length | Tag suggestions |
|---|---|---|---|
| Long idle (player standing still) | After 60s idle, 90s cooldown | Short | `[muttering]` `[lighthearted]` `[matter-of-fact]` |
| Ambient atmospheric (occasional flavor) | Random, 5–10 min between fires | Short | `[wistful]` `[reflective]` |
| Companion-to-companion paired banter | Trigger + cooldown system, see Category 5 | Medium | varies |
| "Should we be doing something" reminder | After 3+ minutes idle near a quest objective | Short | `[curious]` `[matter-of-fact]` |

### Authoring template (long idle)

```
{SPEAKER}: [lighthearted] Are we waiting for something specific.
{SPEAKER}: [matter-of-fact] When you are ready.
{SPEAKER}: [muttering] I could use the rest, I suppose.
{SPEAKER}: [curious] Did you see something I missed.
```

Idle barks should be patient, not nagging. The player paused for a reason.

---

## Category 5 — Companion Banter (Paired)

Two companions speaking to each other while the player walks. The player is the audience, not the participant.

**Structure:** Companion A speaks. Companion B responds. Optionally Companion C interjects. The exchange is 2–4 lines total.

**Trigger conditions:**
- Both speakers present in the active party
- Both speakers above a minimum relationship threshold (or below, for hostile banter)
- Cooldown: no banter line within last 5 minutes
- Location appropriate (no banter during stealth, combat, or scripted scenes)

**Frequency:** Roughly one banter exchange per 10 minutes of party travel.

**Length:** 8–15 seconds of total audio across all speakers.

| Banter type | When |
|---|---|
| Casual / character-of-character | Always available, default pool |
| Region-specific | When in a specific region or location type |
| Story-state reactive | Triggered by recent quest events / flag changes |
| Relationship banter (warm) | Above relationship threshold |
| Relationship banter (cold/hostile) | Below relationship threshold |
| Skill or expertise lens | Triggered by environmental cue matching speaker's expertise |
| Disagreement banter | Triggered by recent player choice the companions react to differently |

### Authoring template (casual character-of-character)

```
{COMPANION_A}: [curious] You have not slept in two days.
{COMPANION_B}: [tired] I have noticed.
{COMPANION_A}: [quietly] Is there a reason, or is it general.
{COMPANION_B}: [reflective] General.
```

The point of paired banter is character revealed through small exchanges, not exposition. Plot-irrelevant is often plot-best.

### Authoring template (skill-lens reactive)

```
{COMPANION_A}: [matter-of-fact] This wall is older than the building it is part of.
{COMPANION_B}: [curious] You can tell that.
{COMPANION_A}: [matter-of-fact] The mortar is wrong. Everything else was built around it.
```

Where Companion A's expertise is relevant. The banter reveals character through their professional eye.

---

## File and Volume Targets

For a 30-hour RPG with five major companions:

| Category | Lines per main character | Lines per companion | Lines per minor NPC |
|---|---|---|---|
| Combat | 80–120 | 60–100 | 0–10 |
| Exploration / movement | 60–80 | 40–60 | 0 |
| Reactive / contextual | 40–60 | 30–50 | 0 |
| Idle / ambient | 30–40 | 20–30 | 0–5 |
| Banter (per pair) | n/a | 60–100 per pairing | n/a |

These are floors for an immersive feel, not ceilings. Hades shipped with thousands of bark lines for a single companion across two characters' relationships. Volume is the texture of the world.

---

## File Layout

```
dialogue/
└── scripts/
    └── barks/
        ├── combat/
        │   ├── {character_a}.txt
        │   └── {character_b}.txt
        ├── exploration/
        ├── reactive/
        ├── idle/
        └── banter/
            └── {character_a}_x_{character_b}.txt
```

Each file is a flat TTS-ready script per `dialogue/STYLE.md`, organized by trigger ID:

```
# Trigger: COMBAT_ENGAGE
{SPEAKER}: [determined] Three of them.
{SPEAKER}: [serious tone] Stay close.
{SPEAKER}: [out of breath] They saw us.

# Trigger: COMBAT_LOW_HP
{SPEAKER}: [out of breath] I cannot hold much more.
{SPEAKER}: [fearful] I am hurt.
```

Trigger IDs are the contract between the bark library and the game's bark trigger system in Godot. Match them exactly.

---

## Cross-References

- `dialogue/STYLE.md` — TTS formatting and tag rules
- `design/CONVERSATION_SYSTEM.md` — tier definitions; barks are Tier 1
- `design/NPC_DIALOGUE_LIBRARY.md` — companion/NPC structured conversations (Tier 2)
