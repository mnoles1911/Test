# tools/

Small Python scripts that implement the TTS pipeline described in
`design/TTS_PIPELINE.md`. Standard library only — no `pip install` needed.

| Script | What it does | Spec section |
|---|---|---|
| `strip_draft.py` | Turns a dialogue draft (`.md`) into a TTS-ready script (`.txt`). Deterministic. | TTS_PIPELINE §4 |
| `render_bulk.py` | Renders TTS scripts to audio via ElevenLabs. Idempotent, hash-aware, cost-capped. | TTS_PIPELINE §6 |

---

## strip_draft.py

Read a draft, find the `## Script (Prose)` section, drop stage directions
and designer notes, convert sound-bearing parentheticals like `*(quietly)*`
to `[quietly]` tags, normalize em-dashes, apply pronunciation glossary
substitutions, validate against the STYLE.md tag allowlist, and write a
clean script under `dialogue/scripts/`.

Performance tags like `[nervous]` or `[matter-of-fact]` are NOT
auto-invented. Those are the writer's review pass after stripping —
"tag the deviation, not the baseline" per `STYLE.md §7.1`.

### Usage

```bash
# Strip one draft and write the matching script (overwrites existing).
python3 tools/strip_draft.py dialogue/drafts/act1_scene_sorting_room.md

# Print to stdout and diff against the existing script — no write.
python3 tools/strip_draft.py --check dialogue/drafts/act1_scene_sorting_room.md

# Process every draft in dialogue/drafts/.
python3 tools/strip_draft.py --all

# Write even if warnings were produced (use sparingly).
python3 tools/strip_draft.py path/to/draft.md --force
```

### Warnings

If the stripper finds an unknown tag, more than two tags on a line, or a
draft that doesn't match the expected layout, it prints warnings and
refuses to write the file. Re-run with `--force` to override (after fixing
the draft, ideally).

---

## render_bulk.py

Read a TTS script, look up each speaker's voice settings from
`dialogue/CHARACTER_VOICES.md`, and render every line to audio via the
ElevenLabs API. Output goes to `audio/dialogue/{scene}/`, with a
`manifest.json` tracking what was rendered with which settings.

The renderer is **idempotent**: running it twice on the same script does
nothing on the second run unless line text changed. Each line's text is
SHA-256 hashed; only changed or missing lines are re-rendered.

### Usage

```bash
# See what WOULD be rendered, no API calls (use this first).
python3 tools/render_bulk.py dialogue/scripts/act1_scene_sorting_room.txt --dry-run

# Generate placeholder zero-byte audio files to test the pipeline
# (manifest, filenames, regen logic) without spending credits.
python3 tools/render_bulk.py dialogue/scripts/act1_scene_sorting_room.txt --mock

# Actually render — needs ELEVENLABS_API_KEY env var and locked voice IDs.
export ELEVENLABS_API_KEY=sk-...
python3 tools/render_bulk.py dialogue/scripts/act1_scene_sorting_room.txt

# Render every changed line across all scripts.
python3 tools/render_bulk.py --all

# Override the default $5 per-run cost cap.
python3 tools/render_bulk.py --all --cost-cap 25.00
```

### Before you can really render

Voice IDs in `dialogue/CHARACTER_VOICES.md` start as `TBD`. Until they're
filled in with real ElevenLabs voice IDs, only `--dry-run` and `--mock`
will work. The locking workflow:

1. Audition voices in the ElevenLabs library against the calibration
   script (per `dialogue/STYLE.md §7.3`).
2. When a voice lands, copy its UUID-style ID into the `voice_id:`
   field of that character's Render Contract block.
3. Re-render once and listen. Adjust `stability` / `similarity_boost`
   in the contract until the take matches the calibration clip.
4. Lock the seed by recording it in the contract. From then on, any
   re-render of that line produces the same take.

### Cost discipline

- Default cap: **$5.00 per run**. Hitting it aborts before any network call.
- Estimate is shown before any render starts (PLAN line).
- Every successful batch appends to `audio/dialogue/_spend.log`
  with timestamp, line count, and estimated cost.
- The estimate is rough — based on character count × `$0.30 / 1k chars`.
  Update the constant in `render_bulk.py` if ElevenLabs pricing changes.

### What's saved where

```
audio/dialogue/
├── _spend.log                              ← append-only audit (gitignored)
├── _calibration/                           ← reference clips per character
└── act1_scene_sorting_room/
    ├── manifest.json                       ← committed (audit trail)
    ├── 001_tomlin.mp3                      ← gitignored (rebuildable)
    ├── 002_roland.mp3
    └── ...
```

### Format note

ElevenLabs returns MP3 by default. Files are saved as `.mp3` even though
`design/TTS_PIPELINE.md §5.3` references `.ogg`. Godot 4 imports MP3
natively — this is a deliberate deviation that should be reconciled when
the doc is next edited. To switch to OGG/Opus output later, change
`AUDIO_EXT` in `render_bulk.py` and pass an `output_format` query param
on the API call.

---

## Build order

Per `design/TTS_PIPELINE.md §12`:

1. ✅ `strip_draft.py` — built.
2. ✅ `render_bulk.py` — built.
3. ⏳ `dtl_audio_link.gd` — Godot tool to inject manifest audio paths
   into Dialogic timelines. Not yet built; deferred to Milestone 6.
4. ⏳ `craft_render_helper.py` — UI workflow assistant for Tier 3/4
   craft renders. Build only if hand-driving the ElevenLabs UI proves
   too friction-heavy to skip.
