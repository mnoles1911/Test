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
├── CHARACTER_VOICES.md         ← per-character voice notes (casting reference)
├── PRONUNCIATION.md            ← phonetic respellings for proper nouns
├── drafts/                     ← prose drafts (subtext, stage directions, design intent)
│   ├── README.md
│   └── act1_scene_*.md
├── scripts/                    ← TTS-ready clean scripts (build output)
│   └── act1_scene_*.txt
└── *.dtl                       ← Dialogic timeline files (in-game, separate pipeline)
```

The `.dtl` files in this directory are Dialogic 2 timeline files used by the Godot runtime — they are a different pipeline. Voice scripts in `scripts/` feed the TTS generator; the resulting audio is then referenced from the `.dtl` timelines.

Two-stage authoring is mandatory: every `scripts/*.txt` has a corresponding `drafts/*.md`. The draft is the source of truth for what the scene means; the script is the production artifact. When a scene needs revision, edit the draft and regenerate the script — never edit the script for narrative reasons. It drifts from intent.

---

## 7. Authoring Patterns

These are craft notes for getting good performances out of the v3 model. Skim them before writing a new scene.

### 7.1 Tag the deviation, not the baseline

A character's default voice belongs in `CHARACTER_VOICES.md`, not in every line. Roland's baseline is calm; if every Roland line is tagged `[calm]`, the model overacts on it and the tag stops meaning anything. **Untagged is a tone.** Tag only when the voice changes from baseline — `[tired]` when he drops, `[quietly]` when he gets dangerous, `[light chuckle]` when he breaks.

Rule of thumb: if you're tagging more than once or twice per line, you're probably doing punctuation's job with tags.

### 7.2 Punctuation does more work than tags

`...` and `--` are read natively by the model and inflect the surrounding words. A `[pauses]` tag inserts a measured gap; ellipses produce a natural breath.

- Drama and hesitation → `...`
- Interruption → `--` on the cut-off line, plus `[rushed]` or `[fast]` on the interrupter so they actually land on top
- Emphasis → ALL CAPS on the single word that carries it ("the WRONG price"), not the whole sentence

### 7.3 Build a calibration clip per character

Before batch-generating any scene, render a 30-second calibration clip per character: one line of each baseline mood plus one line of an extreme. Lock the voice/seed when it lands and save the clip as a reference. Compare every future generation against it — drift becomes obvious before it accumulates across hours of playable content.

This is the single highest-leverage habit for keeping a 30-hour RPG sounding consistent.

### 7.4 Cut-scene structure

Cut scenes have rhythms NPC barks don't:

- **Pre-roll line.** Generate a throwaway warm-up line per voice and discard it. The model often clips the first 200ms or rushes the opening sentence.
- **Chunk at beats.** Generate in 30–60 second blocks broken at natural emotional beats (a `[pauses]`, a topic shift). Stitch later. Long single-pass generations drift in tone.
- **Breathing room.** A 90-second scene needs 15–20 seconds of silence baked in via `...` and beat lines. New writers fill all 90 seconds with words. The Calla chapel scene works because half its weight is what isn't said.

### 7.5 Mind the proper nouns

Lore words like *Drûn-Khazad*, *Aelthurion*, *Khorumzad* — the model will guess pronunciations and they will be wrong. Use the phonetic respellings in `PRONUNCIATION.md` inside script files. Keep canonical spelling in lore files only. Catch this once per term, not once per scene.

### 7.6 Match tag to scene acoustics

`[whispering]` mixed under music will be inaudible at game volume. `[shouting]` in a tight indoor scene reads as broken voice acting. Tag delivery to the **room** the player will hear it in, not just the dramatic intent. The chapel scene is intimate stone interior — `[softly]` and `[quietly]` carry; `[shouting]` would never appear here. The Night Chase opener legitimately uses `[out of breath]` and `[fearful]`.

### 7.7 Different game modes need different tag densities

| Context | Tag density | Notes |
|---|---|---|
| Cut scenes | 1–2 per line | Where the prose-draft-then-strip workflow earns its keep |
| NPC dialogue trees | 1 per line max | Branching → keep tags surgical so each branch sounds consistent |
| Combat barks | 1 strong tag | "[shouting] Behind you!" — single emotion, single delivery, ultra-short |
| Ambient overhears | bare lines, rarely tagged | Long ambient lines with tags overact and break immersion |

### 7.8 Read it aloud before generating

Before generating a scene, read the stripped script aloud yourself, ignoring tags. If a line feels wrong in your mouth, the model will produce something wrong too — usually a line that's overwritten or has subtext smuggled into the words. The model is unforgiving of literary writing; spoken language is shorter and more concrete. You'll catch ~80% of generation problems at the page before spending compute.

### 7.9 Build a reaction library once

Generate a small pool of generic reactions per major character — `[laughs]`, `[sighs]`, an "ah" of pain, a small acknowledgment. Cache them. They get reused across hundreds of moments and avoid one-token reaction generations (which the model handles poorly anyway). Equivalent to a Foley library, but for voice.

### 7.10 The two-stage workflow (mandatory)

For each major dialogue beat:

1. Write the **prose draft** in `drafts/` with full subtext, stage directions, character voice. This is for the team and future-you, not the model.
2. Strip to the **TTS script** in `scripts/` following sections 1–4 of this file.
3. Keep both. Drafts are the design source-of-truth; scripts are the build artifact.
4. Revise drafts first, then regenerate scripts. Never edit a script for narrative reasons.
