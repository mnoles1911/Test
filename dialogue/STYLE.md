# Dialogue Style & Formatting Rules

This file is the canonical style guide for ALL written dialogue scripts intended for the text-to-speech (TTS) pipeline. Any new dialogue file generated for voice production must conform to these rules. The TTS model uses natural language processing — it reads inline tags as performance direction.

Scripts that violate these rules produce broken audio (the model will speak the stage directions out loud).

---

## 1. Script Formatting Rules

### Speaker ID
- Use the speaker's **first name only**, ALL CAPS, followed by a colon. No titles, no surnames.
  - `ROLAND:` ✓
  - `Roland Ashford:` ✗
  - `DAME CALLA:` ✗ — use `CALLA:`
- The speaker ID is for **visual assignment only** during voice prep. It is deleted from the line before generation. Do not embed performance information in the speaker tag.

### Clean Text
- Strip ALL stage directions and prose subtext from the spoken line.
- If a stage direction describes a SOUND the voice itself can produce (a sigh, a chuckle, a tone shift), convert it into a `[tag]`.
- If a stage direction describes a physical action, environmental event, or abstract emotional state with no auditory signature, **delete it entirely**. Movement, lighting, props, and scene action belong in scene-layout files (`lore/LEVEL_LAYOUTS_ACT*.md`), not dialogue scripts.

### Punctuation
- `...` — pauses (mid-line breath, hesitation, trailing off)
- `--` — interruptions (line cuts off, or another speaker cuts in)
- `ALL CAPS` on a single word or short phrase — heavy emphasis on that word
- Standard sentence punctuation otherwise. Do not use em dashes (`—`) for pauses; use `...`.

---

## 2. The Universe of Available Tags

The TTS model does not have a hard-coded tag list — it interprets natural language — but it performs best when constrained to these proven categories. Use only tags from the lists below.

### Emotional States
`[happy]` `[sad]` `[angry]` `[excited]` `[nervous]` `[frustrated]` `[surprised]` `[fearful]` `[calm]` `[curious]` `[appalled]` `[resigned]` `[wistful]` `[sorrowful]` `[mischievous]` `[determined]` `[awe]`

### Delivery Style
`[whispering]` `[shouting]` `[quietly]` `[loudly]` `[slowly]` `[fast]` `[rushed]` `[softly]` `[muttering]` `[stuttering]` `[conversational tone]` `[dramatic tone]` `[reflective]` `[serious tone]` `[matter-of-fact]` `[lighthearted]` `[sarcastic tone]` `[deadpan]` `[authoritative]` `[dismissive]` `[flirty]` `[condescending]`

### Physical States
`[out of breath]` `[yawning]` `[shivering]` `[muffled]` `[tired]` `[hollow voice]`

### Human Reactions (Non-Verbal)
`[laughs]` `[sighs]` `[gasp]` `[gulps]` `[crying]` `[clears throat]` `[pauses]` `[hesitates]` `[light chuckle]` `[giggle]`

### Archetypes & Accents
`[heroic tone]` `[villainous]` `[childlike]` `[old man voice]` `[British accent]` `[Southern accent]`

---

## 3. Tags That Are NOT Available

The model cannot generate external environmental sounds or abstract concepts that do not have an auditory signature. Do not write tags in any of the following categories.

### Environmental SFX — DO NOT USE
- `[gunshot]` `[explosion]` `[rain falling]` `[door creaking]` `[footsteps]` `[wind]` `[fire crackling]`
- Environmental SFX are added in the audio engine SFX tab, not the script.

### Abstract Concepts — DO NOT USE
- `[existential dread]` `[thinking about lunch]` `[remembers the past]` `[realizing the truth]` `[adjacent]`
- These have no specific auditory signature. Convert to a delivery tag the model can interpret: `[reflective]`, `[quietly]`, `[hesitates]`.

### Complex Directions — DO NOT USE
- `[walks across the room while talking]` `[turns to face her]` `[picks up the document]`
- The model controls the voice only, not spatial movement. Stage business belongs in scene-layout files.

---

## 4. Raw Script Example

```
ROLAND: [tired] I'm trying to finish it. [pauses] I think she believed someone needed to finish what she'd started.

TOMLIN: [quietly] She taught me to catalogue. [sighs] She had strong opinions about that.
```

---

## 5. Authoring Workflow

When writing a new scene for voice:

1. Draft the prose script first if needed for review (with subtext, stage directions, character notes). Keep this in a separate working file or scene-layout doc — NOT in the TTS-ready file.
2. Strip the draft to a clean voice script following the rules above. Save the clean version under `dialogue/scripts/` with the naming convention `act{N}_scene{N}_{slug}.txt`.
3. Character notes (voice description, accent, manner) live in `dialogue/CHARACTER_VOICES.md`, not embedded in scripts.
4. Use `[tag]` sparingly — one or two per line at most. Over-tagging causes the model to overact. Trust the words to carry the performance.
5. When in doubt, prefer a delivery tag (`[quietly]`, `[matter-of-fact]`) over an emotional state tag (`[sad]`, `[angry]`). Emotion tags push the model toward melodrama.

---

## 6. File Layout

```
dialogue/
├── STYLE.md                    ← this file
├── CHARACTER_VOICES.md         ← per-character voice notes
├── scripts/                    ← TTS-ready clean scripts
│   ├── act1_scene_sorting_room.txt
│   └── act1_scene_forty_minutes.txt
└── *.dtl                       ← Dialogic timeline files (in-game, separate pipeline)
```

The `.dtl` files in this directory are Dialogic 2 timeline files used by the Godot runtime — they are a different pipeline. Voice scripts in `scripts/` feed the TTS generator; the resulting audio is then referenced from the `.dtl` timelines.
