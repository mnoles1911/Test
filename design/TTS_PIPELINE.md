# TTS Pipeline

How written dialogue becomes shipped audio. Covers AI-assisted drafting, the deterministic stripping transform, the render orchestration (bulk vs. craft), the filename + manifest contract, and the handoff into Dialogic 2 timelines.

> Companion docs:
> - `design/CONVERSATION_SYSTEM.md` — the four-tier model that drives pipeline choice.
> - `dialogue/STYLE.md` — script formatting and tag rules.
> - `dialogue/CHARACTER_VOICES.md` — render contracts (voice IDs + settings) per character.
> - `dialogue/PRONUNCIATION.md` — phonetic respellings for proper nouns.
> - `design/BARK_LIBRARY.md` — Tier 1 categories, trigger IDs, file layout.

---

## 1. Two Pipelines, Not One

The four-tier conversation model produces wildly different production characteristics. Treating all dialogue with one pipeline is wrong for both ends:

| Pipeline | Tier coverage | Volume | Render cost per line | Iteration model |
|---|---|---|---|---|
| **Bulk** | Tier 1 barks, most Tier 2 vendor/info exchanges | Thousands of lines | Cheap, deterministic, batched | One pass; regenerate by hash diff |
| **Craft** | Tier 3 story beats, Tier 4 illustrated keyframes | Dozens of lines | Whatever the take requires | Many takes per line; the writer picks one |

**Heuristic.** If the line has no name in the player's memory after the credits, it goes through the bulk pipeline. If the line is one the player will quote at someone, it goes through the craft pipeline.

The two pipelines share the *artifacts* (drafts, scripts, render contracts, pronunciation glossary) and diverge at the *render step*.

---

## 2. The Authoring Flow (Both Pipelines)

```
  beat outline / lore  ─┐
                        ├──►  AI-assisted prose draft  ──►  human revision
  CHARACTER_VOICES.md ──┘            (drafts/*.md)             (drafts/*.md)
                                                                    │
                                                                    ▼
                                                       deterministic stripper
                                                                    │
                                                                    ▼
                                                            TTS script
                                                          (scripts/*.txt)
                                                                    │
                                                                    ▼
                                                ┌───────────────────┴───────────────┐
                                                ▼                                   ▼
                                         Bulk render                          Craft render
                                       (API, batched)                    (UI, one line at a time)
                                                │                                   │
                                                └───────────────────┬───────────────┘
                                                                    ▼
                                                          audio/dialogue/*.ogg
                                                          + manifest.json
                                                                    │
                                                                    ▼
                                                        Dialogic .dtl voiceline refs
                                                              (or bark trigger map)
```

**Two-stage authoring is mandatory** (per `STYLE.md` §7.10): every voiced scene has a `drafts/*.md` (intent) and a `scripts/*.txt` (artifact). Revise the draft, regenerate the script. Never edit the script for narrative reasons.

---

## 3. AI-Assisted Drafting — Prompt Templates

The draft is for humans: subtext, blocking, designer notes. The AI's job is to produce a draft that matches `STYLE.md §7.8` ("read it aloud") on the first pass — concrete, spoken, no literary writing — so the human revision is shaping, not rewriting.

Three templates, one per writing context. Each is a Claude prompt; paste verbatim, fill the brackets, paste the relevant lore/character files alongside.

### 3.1 Tier 3 / 4 — Story Beat or Illustrated Keyframe

```
You are drafting a {TIER 3 story beat | TIER 4 illustrated keyframe} for
Game One: a 3D voxel narrative RPG. Output a prose draft in the format
of dialogue/drafts/act1_scene_sorting_room.md.

Scene: {short title}
Act / location: {act, scene, location}
Characters: {speakers, in order of importance}
Story function: {what changes by end — flag set, info delivered, choice made}
Required flags / preconditions: {existing GameState flags this depends on}
Beat outline:
  1. {beat one}
  2. {beat two}
  3. {beat three}
  4. {dramatic pivot — the line everything turns on}
  5. {resolution beat}

Voice references (paste verbatim):
  - dialogue/CHARACTER_VOICES.md sections for: {speakers}
  - relevant lore files: {paths}
  - if the scene uses lore proper nouns, paste dialogue/PRONUNCIATION.md

Output requirements:
  - Markdown, with: scene header, scene-specific voice notes, setting,
    prose script (with stage directions and parentheticals), designer notes.
  - Subtext belongs in the parentheticals, not in the dialogue itself.
  - No line longer than two breaths. No literary writing — this will be
    spoken aloud.
  - One identifiable pivot line where the scene's emotional weight lands.
  - The character's baseline tone (per CHARACTER_VOICES.md) is the default.
    Only deviate when the scene earns it.

Do not produce the TTS script. The stripping step is separate and
deterministic — your output is the prose draft only.
```

**Why this shape:** the pivot line is a forcing function. If the AI cannot identify a single line where the scene turns, the scene does not have a turn yet, and the draft will read as exposition. Reject and re-prompt.

### 3.2 Tier 2 — Standard Conversation (Branching)

```
You are drafting a Tier 2 standard conversation for Game One. This is a
branching dialogue tree with player choices. Output the prose draft as
markdown, then a flowchart of the branches.

Conversation: {short title}
NPC(s): {names}
Where: {location}
Player's apparent goal: {what Roland is trying to do}
NPC's apparent goal: {what the NPC is trying to do — may be opaque}
Information / item / flag at stake: {what changes hands}
Required flags / preconditions: {GameState dependencies}
Branches the player can take:
  - {APPROACH_A}: {one-line description, e.g. "Honest — tell Tomlin Henrietta is dead"}
  - {APPROACH_B}: {one-line description}
  - {APPROACH_C}: {one-line description}
Outcome on success: {flag(s) set}
Outcome on failure: {flag(s) set, dialog routes back to opener or exit}

Voice references: {as above}

Output requirements:
  - One opener (the line the NPC delivers first, regardless of branch).
  - One block per approach, showing 3–6 lines of NPC + Roland exchange
    leading to a success or failure resolution.
  - Roland's branching response options are TEXT — they will not be voiced
    (per the Roland Voicing Policy in design/CONVERSATION_SYSTEM.md).
    Mark Roland's branching options with: [PLAYER CHOICE] in the draft.
    Mark fixed Roland lines (committed responses, narration) without it.
  - Every NPC line is voiced. Tag sparingly (one per line, max).
  - End with a summary table: branch → outcome → flags.
```

**Why this shape:** the [PLAYER CHOICE] marker is the contract that drives the stripper to skip those lines when generating the TTS script. Roland's branch options never go to audio.

### 3.3 Tier 1 — Bark Pool

```
You are writing a bark pool for Game One — Tier 1 dialogue per
design/BARK_LIBRARY.md. Output a TTS-ready script directly (skip the
prose draft step — barks are too short to benefit).

Speaker: {character first name}
Category: {combat | exploration | reactive | idle | banter}
Trigger ID: {e.g. COMBAT_ENGAGE, REGION_ENTER_NEW, IDLE_LONG}
Pool size: {3–5 variants}
Cooldown / frequency rule: {from BARK_LIBRARY.md table}
Length cap: {very short | short | medium per BARK_LIBRARY.md}

Voice reference: {paste CHARACTER_VOICES.md section}
Tag budget: 0 or 1 tag per line. Trust the words.

Output: lines in dialogue/STYLE.md format, with a header comment of the
trigger ID. Example:

  # Trigger: COMBAT_ENGAGE
  ROLAND: [determined] Three of them.
  ROLAND: [serious tone] Stay close.
  ROLAND: [out of breath] They saw us.
  ROLAND: [fast] Weapons.
  ROLAND: [quietly] Here we go.

Variation rule: across the pool, vary tone as much as wording. The
"determined" line, the "tired" line, and the "matter-of-fact" line each
give the player a different read of the character.
```

**Why this shape:** for one-breath lines, prose drafting adds no value. Skip straight to the production artifact.

---

## 4. The Stripper — Draft → Script

The stripping step is **deterministic**, not creative. It is a transform, not a rewrite. The same draft must always produce the same script.

### 4.1 Transform rules (in order)

1. **Extract spoken text only.** Drop scene headers, setting blocks, designer notes, parentheticals, italicized stage directions.
2. **Normalize speaker labels.** First name only, ALL CAPS, colon. (`**TOMLIN**` → `TOMLIN:`)
3. **Convert sound-bearing parentheticals to tags.** `(quietly)` → `[quietly]`, `(after a moment)` → `[pauses]`, `(sighs)` → `[sighs]`. Drop everything else.
4. **Apply pronunciation glossary.** For every proper noun in `PRONUNCIATION.md`, replace canonical with TTS spelling. (`Drûn-Khazad` → `droon kah-ZAHD`.)
5. **Punctuation pass.** `—` (em dash) → `...` for pauses, `--` for cut-offs. `(beat)` between lines → `[pauses]` on the prior line. Standalone `...` retained.
6. **Tag economy pass.** Reject any line with more than two tags. Reject any tag not in the `STYLE.md §2` allowlist. Print the line and the offending tag for human resolution — do not auto-fix.
7. **Strip [PLAYER CHOICE] lines** (Tier 2 only). Roland's branching options never reach audio.
8. **Validate.** Every line conforms to `STYLE.md §1`. Every speaker has a voice ID in `CHARACTER_VOICES.md`. Every proper noun is in `PRONUNCIATION.md` or flagged.

### 4.2 Implementation

This is a small Python script (~100 lines) under `tools/strip_draft.py`. Build it when needed; it is not Milestone 5-3D blocking. Until built, the transform is performed by hand using the rules above.

---

## 5. Filename Contract

The contract is the binding between scripts, audio, and Dialogic timelines. Every layer agrees on the same per-line ID.

### 5.1 Cut-scene scripts (Tier 2/3/4)

```
dialogue/scripts/act{N}_scene_{slug}.txt
```

Each non-empty, non-comment line is a numbered audio line. The line index is:
- Zero-padded, three digits, starting at `001`.
- Stable across edits within a scene's lifecycle. Inserting a new line does NOT renumber existing lines — assign the next free index and let the manifest record line order.

The manifest (next section) is what ties indices to playback order and to the audio.

### 5.2 Bark scripts (Tier 1)

```
dialogue/scripts/barks/{category}/{character}.txt
```

Categories per `BARK_LIBRARY.md`: `combat`, `exploration`, `reactive`, `idle`, `banter`. Trigger blocks within each file:

```
# Trigger: COMBAT_ENGAGE
ROLAND: [determined] Three of them.
ROLAND: [serious tone] Stay close.
```

Each line within a trigger block gets a per-trigger index (`01`, `02`, …) — the bark system picks one at random at runtime.

### 5.3 Audio output

```
audio/dialogue/
├── _calibration/
│   ├── roland.ogg
│   ├── tomlin.ogg
│   └── calla.ogg
├── act{N}_scene_{slug}/
│   ├── manifest.json
│   ├── 001_tomlin.ogg
│   ├── 002_roland.ogg
│   └── 003_tomlin.ogg
└── barks/
    └── {category}/
        └── {character}/
            └── {TRIGGER_ID}_{NN}.ogg
```

Naming rules:
- Cut-scene files: `{line_index}_{speaker_lowercase}.ogg`.
- Bark files: `{TRIGGER_ID}_{variant_index}.ogg`.
- Format: OGG Vorbis, mono, 22050 Hz or 44100 Hz, normalized to −16 LUFS (matches Godot's import defaults; tweak only if mixed audio falls outside the −18 to −14 LUFS band).

### 5.4 Manifest (per scene)

`audio/dialogue/act{N}_scene_{slug}/manifest.json` is the bridge between source text and audio. One file per cut scene; barks use a flat per-character manifest at `audio/dialogue/barks/{character}.json`.

Cut-scene manifest shape:

```json
{
  "scene_id": "act1_scene_sorting_room",
  "script": "dialogue/scripts/act1_scene_sorting_room.txt",
  "draft":  "dialogue/drafts/act1_scene_sorting_room.md",
  "tier": 3,
  "lines": [
    {
      "index": "001",
      "speaker": "TOMLIN",
      "text_hash": "sha256:abcdef…",
      "audio": "001_tomlin.ogg",
      "voice_id": "elabs_voice_uuid_for_tomlin",
      "model": "eleven_v3",
      "stability": 0.32,
      "similarity_boost": 0.80,
      "style": 0.0,
      "speed": 1.0,
      "seed": 471829,
      "rendered_at": "2026-05-12T14:08:11Z",
      "approved": true
    },
    { "index": "002", "speaker": "ROLAND", "...": "..." }
  ]
}
```

**The text hash is the regeneration trigger.** Re-stripping the script recomputes hashes; lines whose hash changed are queued for rerender. Lines whose hash is identical are skipped — the existing audio is reused. This is what lets you tweak one Tomlin line in a 60-line scene without re-rendering Roland's takes.

`approved: true` means a human listened to this take and signed off. Until then, the line will be regenerated on every batch run if `seed` is `null`. Once approved, the seed is locked into the manifest and the audio is stable.

---

## 6. Bulk Pipeline (Tier 1, most Tier 2)

API-driven, deterministic, cheap. Designed to render a 200-line bark pool in one pass and never look at the takes individually.

### 6.1 Loop

```
for each script file in dialogue/scripts/:
    parse lines and trigger blocks
    compute text hash per line
    load manifest (or create empty)
    for each line whose hash differs from manifest, or which is missing audio:
        load render contract from CHARACTER_VOICES.md for the speaker
        POST to ElevenLabs /v1/text-to-speech/{voice_id}
            body: text, model, voice_settings, seed (if locked)
        save audio to audio/dialogue/.../{line_index}_{speaker}.ogg
        update manifest with new hash + render metadata + rendered_at
    write manifest
```

A small Python script (`tools/render_bulk.py`) wraps this. Key properties:
- **Idempotent.** Running it twice in a row does nothing on the second run.
- **Resumable.** If interrupted mid-batch, the next run picks up where it left off.
- **Cost-aware.** Print a token count + estimated cost before any network call. Refuse to run if estimate exceeds a per-run cap (default $5). The cap exists to catch loops where the same line keeps re-rendering due to a hashing bug.

### 6.2 What goes through bulk

- **All Tier 1 barks** — automatically.
- **Tier 2 lines marked `bulk: true`** — flag in the script header. Default for vendor exchanges, info-gathering NPCs, scenes whose lines do not need individual judgment.

### 6.3 What does NOT go through bulk

- Anything tier 3 or 4.
- Tier 2 scenes where the draft includes the marker `# craft-render: true` in the script header. Use this for any scene whose dramatic weight earns multi-take iteration even if it is technically Tier 2.

---

## 7. Craft Pipeline (Tier 3 + Tier 4)

Hand-curated. The writer drives ElevenLabs from the web UI, generates many takes per line, picks one. The artifacts are the same — the same script, the same manifest — but a human is in every loop.

### 7.1 Loop

```
for each line in scripts/act{N}_scene_{slug}.txt:
    open ElevenLabs UI
    select voice from CHARACTER_VOICES.md render contract
    paste line text
    apply pronunciation glossary substitutions
    generate 3–8 takes
    audition against the calibration clip
    when a take lands:
        download as ogg
        rename to {line_index}_{speaker}.ogg
        place in audio/dialogue/act{N}_scene_{slug}/
        record the take's seed in manifest.json (lines[i].seed)
        set lines[i].approved = true
```

`tools/craft_render_helper.py` (when built) automates everything around the human take selection: pulling the line text, copying the render settings to the clipboard, watching the downloads folder for the new ogg, and updating the manifest. The human only does the listen-and-pick.

### 7.2 What craft buys you

- Multiple takes per line at the same render contract — the model is non-deterministic at most temperatures, so two takes with the same settings vary in delivery. The writer picks the one that matches scene intent.
- The chunking discipline in `STYLE.md §7.4` — pre-roll a throwaway warm-up, generate in 30–60s blocks, breathing room baked in via `...`.
- Per-take seed locking so the chosen take can be reproduced if the audio is ever lost.

### 7.3 What craft costs you

A Tier 3 scene takes 1–2 hours of render time on top of the 2 hours of authoring noted in `CONVERSATION_SYSTEM.md`. Budget for this. Schedule cut-scene rendering after a writing session, not before — your ear is fresher and you'll catch off-takes faster.

---

## 8. Handoff Into Dialogic

Dialogic 2 timelines (`.dtl` files) reference audio per voiceline event. The contract:

```
Henrietta: "Don't come inside. Stay at the door." [voice="audio/dialogue/act1_scene_archive_henrietta/001_henrietta.ogg"]
```

(Exact Dialogic syntax: see `design/DIALOGIC_SETUP.md`. The voiceline event is `[voice path]` in their text format.)

Rules:
- One Dialogic line corresponds to one manifest line. Indices match.
- The `.dtl` file is **generated from the script + manifest**, not hand-edited for audio refs. A small Godot tool (`tools/dtl_audio_link.gd`) walks the manifest and writes the voice attribute into the matching Dialogic line. Run it whenever the manifest changes.
- Roland's branching player choices have no `[voice]` attribute (per the Roland Voicing Policy). The tool skips them automatically because they have no manifest entry.

For barks, the `.dtl` mechanism is bypassed — the bark trigger system in Godot picks an audio file at random from `audio/dialogue/barks/{category}/{character}/{TRIGGER_ID}_*.ogg` and plays it through the character's spatial AudioStreamPlayer3D.

---

## 9. Iteration Model

The five things that can change after first render, and what each one costs:

| Change | What rerenders | Cost |
|---|---|---|
| One word in one line | That one line | One API call (bulk) or one craft session |
| Whole scene rewritten | Every line whose hash changed | Most lines, one batch |
| Character's voice ID swapped | Every line by that character, project-wide | Game-scale rerender — avoid |
| Character's stability/seed changed (within ±0.05) | Nothing automatic. Manual flag of which lines to retake. | Surgical |
| Pronunciation glossary entry added | Every line containing that proper noun | Targeted batch — manageable |

The hash-based manifest is what makes the first row cheap. Without it, every edit triggers a scene-wide rerender.

---

## 10. Cost Discipline

Rough envelope for a 30-hour Game One:

| Tier | Lines | Avg. duration | Render cost |
|---|---|---|---|
| Tier 1 barks | 3,000–5,000 | 2–4s | Bulk, cheap |
| Tier 2 standard | 1,500–2,500 | 4–8s | Mostly bulk |
| Tier 3 story beats | 200–400 | 4–10s | Craft |
| Tier 4 keyframes | 30–60 | 6–15s | Craft, multi-take |

Rules:
1. **No batch over $5 without an explicit override.** The cap catches bugs before they catch you.
2. **Tier 4 lines get unlimited takes.** That's the whole point of Tier 4.
3. **Tier 1 lines get one take each.** That's the whole point of Tier 1.
4. **Track total spend in a top-level `audio/dialogue/_spend.log`.** Each batch appends date, line count, character count, cost. Audit monthly.

If total spend approaches the budget cap, the lever is **lower the bark count**, not lower quality on Tier 3/4. The barks are the elastic line.

---

## 11. What This Pipeline Does Not Do

- **Music and ambient SFX.** Different pipeline, different tooling. `[fire crackling]` belongs in the audio engine SFX tab, never in a script (per `STYLE.md §3`).
- **Real-time TTS at runtime.** All audio is pre-rendered. The game never calls ElevenLabs at runtime. Bandwidth, latency, cost, and consistency all argue against it; the manifest model assumes everything ships baked.
- **Localization.** English only for now. When a second language is added, it gets its own `dialogue/scripts/{lang}/` tree, its own manifest, its own render contracts. The pipeline structure survives; the artifacts duplicate.
- **Voice cloning of real people.** Use ElevenLabs' library voices or commissioned synthetic voices only. Never clone an actor without a contract that explicitly permits TTS use.

---

## 12. Build Order

The pipeline does not need to exist all at once. Build it in this order, against milestones:

1. **Now (Milestone 4-3D).** Manual two-stage authoring per `STYLE.md`. No tooling. The two existing scenes (`act1_scene_sorting_room`, `act1_scene_forty_minutes`) are the test bed. Render those by hand in the ElevenLabs UI to validate the render contracts in `CHARACTER_VOICES.md`.
2. **Milestone 5-3D start.** Build `tools/strip_draft.py` (deterministic stripper) and the manifest schema. No bulk renderer yet.
3. **Milestone 5-3D mid.** Build `tools/render_bulk.py` (idempotent batch renderer) and start writing bark pools per `BARK_LIBRARY.md`.
4. **Milestone 6.** Build `tools/dtl_audio_link.gd` (Godot tool that injects audio paths into Dialogic timelines).
5. **Milestone 6+.** Build `tools/craft_render_helper.py` (UI workflow assistant) only if the friction of doing it by hand exceeds the cost of writing the tool. It may not.

Each tool is small (~100 lines). Treat them as scripts, not infrastructure.
