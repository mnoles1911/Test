# tools/

Small Python scripts that implement the TTS pipeline described in
`design/TTS_PIPELINE.md`. Standard library only — no `pip install` needed.

| Script | What it does | Spec section |
|---|---|---|
| `strip_draft.py` | Turns a dialogue draft (`.md`) into a TTS-ready script (`.txt`). Deterministic. | TTS_PIPELINE §4 |
| `render_bulk.py` | Renders TTS scripts to audio via ElevenLabs. Idempotent, hash-aware, cost-capped. | TTS_PIPELINE §6 |
| `render_sfx.py` | Renders the SFX prompt tables to ElevenLabs Sound Effects candidates for manual review. Idempotent, hash-aware, cost-capped. | SFX_PROMPTS.md |
| `voxel_tree_studio/` | Fork of ez-tree (MIT) that renders realistic trees as **cubic voxels** + exports game-ready JSON. Species presets, full dials, locks/randomizers, reference overlay, 6-connected (choppable) output. | `voxel_tree_studio/README.md` |
| `voxel_rock_studio/` | SDF voxel **rock** generator (boulders/slabs/cliffs/spires/pebbles/piles). Uses existing stone materials + moss. Reference overlay + **Claude vision** dial-fit (browser API call). Shares `voxel_studio_common/`. | `voxel_rock_studio/README.md` |
| `voxel_studio_common/` | Shared voxel-studio math: `noise.js` (simplex/Worley/FBM), `voxel_core.js` (packing, 6-connected connectivity, map→typed-array normalize), `claude_vision.js` (browser Messages API), `scale_figure.js` (1.8 m human). | — |

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

## render_sfx.py

Reads `design/SFX_PROMPTS.md`, finds every sound-effect row (the
`id | prompt | dur | infl | loop | var | bus` tables), and asks the
ElevenLabs **Sound Effects** API (`POST /v1/sound-generation`) to generate
several candidate versions per id into a review folder — one subfolder per
id — so the keepers can be chosen by hand.

Every doc detail is honored per call: `text` = prompt, `duration_seconds`
= `dur` (`auto` => omitted; numbers clamped to the API's 0.5–22 s),
`prompt_influence` = `infl`, `loop` = `loop` (Y => seamless `loop:true`).
Candidates per row = `var + 2` (min 3) unless `--versions N` overrides.

Same discipline as `render_bulk.py`: idempotent (per-row hash of
prompt+params+versions; re-runs only do new/changed rows), a **credit**
estimate (vs your monthly plan) shown before any call, hard `--credit-cap`
(default 20000 credits), `--dry-run`, `--mock` (placeholder files, no key,
no spend — exercises folders + manifest + regen logic).

### Usage

```bash
# Sanity-check parsing — list every row, no calls, no key:
python3 tools/render_sfx.py --list

# Spend plan for all of Phase 1, no calls:
python3 tools/render_sfx.py --phase 1 --dry-run

# Test the full pipeline with placeholders (no spend, no key):
python3 tools/render_sfx.py --category 02 --mock

# Render one category for real (needs ELEVENLABS_API_KEY):
python3 tools/render_sfx.py --category 02

# Re-render one id after editing its prompt in the doc:
python3 tools/render_sfx.py --id cmb_bear_rear_roar --force

# Label folders with keep-count / loop flag (no API, no cost):
python3 tools/render_sfx.py --annotate
```

### Folder labels (`--annotate`)

So you don't have to cross-reference the doc while curating, `--annotate`
stamps the keep plan into the output folders (no API, no cost, safe anytime):

- each id folder gets a self-describing marker visible in Explorer:
  `0_KEEP-5.txt` (keep 5 variants), `0_LOOP_KEEP-1.txt` (it's a loop —
  check the seam, keep 1). The `0_` prefix sorts it to the top.
- each category folder gets `0_INDEX.txt`; the output root gets
  `0_KEEP_INDEX.txt` — the whole keep plan at a glance.

Rule: **loop → keep 1 (seamless check first); `var` ≥ 2 → keep that many
distinct variants (engine random-picks); `var` 1 → pick 1 best.** Run it
with the same filter you rendered (`--annotate --category 08`) or bare
`--annotate` to label everything.

### Output

Defaults to `C:\Users\Matt Noles\Desktop\SFX` (override `--out` or
`SFX_OUT_DIR`). Layout: `<OUT>/<category>/<id>/<id>_vNN.mp3`, plus
`_manifest.json` (idempotency/audit) and `_spend.log` (append-only,
live runs only). ElevenLabs returns mp3 (Godot imports it). Convert the
approved keepers to repo format when moving them in:
`ffmpeg -i in.mp3 -ac 1 -ar 44100 -c:a libvorbis out.ogg`, then drop into
`assets/audio/sfx/...` and flip the entry to EXISTING in `SFX_LIBRARY.md`.

### Cost discipline

ElevenLabs bills Sound Effects in **credits, by audio duration**. The PLAN
line estimates credits via `CREDITS_PER_SECOND` (≈40) and
`MIN_CREDITS_PER_GEN` (≈100) and shows them as a **% of your monthly plan**
(`--plan-credits`, default 131000). These constants are estimates —
**calibrate them**: note your credit balance, run a small batch
(`--category 09` ≈ 9k credits), check the delta, set the constants to the
measured values. Over `--credit-cap` (default 20000) aborts before any
network call; a confirm prompt guards live runs unless `--yes`. For scale:
all of Phase 1 (~844 generations) is ≈ a full month of a 131k plan, so
batch by `--category` and measure as you go. `--limit`/`--id` keep test
batches tiny while validating prompt style.

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
