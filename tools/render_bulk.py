#!/usr/bin/env python3
"""
render_bulk.py — render TTS scripts to audio via ElevenLabs.

WHAT THIS DOES, IN PLAIN ENGLISH
================================
Reads a TTS script (dialogue/scripts/*.txt), looks up each character's
voice settings from dialogue/CHARACTER_VOICES.md, and asks ElevenLabs
to generate audio for every line. Writes one audio file per line into
audio/dialogue/{scene}/ and records what it did in a manifest.json.

The key feature: it's IDEMPOTENT. Run it twice on the same script and
the second run does nothing — every line's text hash is checked against
the manifest, and only changed/missing lines are re-rendered. That's
what makes it safe to leave running while you tweak dialogue.

Cost discipline (per design/TTS_PIPELINE.md §10):
  - Hard cap: $5 per run by default. Configurable with --cost-cap.
  - Estimate is shown BEFORE any network call. You confirm or abort.
  - Every batch appends to audio/dialogue/_spend.log.

Run examples:

  # See what would be rendered, no API calls (use this first):
  python3 tools/render_bulk.py dialogue/scripts/act1_scene_sorting_room.txt --dry-run

  # Generate placeholder zero-byte audio files to test the pipeline
  # without spending any credits or needing an API key:
  python3 tools/render_bulk.py dialogue/scripts/act1_scene_sorting_room.txt --mock

  # Actually render (requires ELEVENLABS_API_KEY env var):
  python3 tools/render_bulk.py dialogue/scripts/act1_scene_sorting_room.txt

  # Render every script that has changes:
  python3 tools/render_bulk.py --all

  # Override the cost cap for a big batch:
  python3 tools/render_bulk.py --all --cost-cap 25.00

NOT YET IMPLEMENTED
===================
  - Bark scripts (dialogue/scripts/barks/...) — the renderer recognizes
    them but skips with a notice. The bark filename layout from
    TTS_PIPELINE.md §5 will be wired in when we start authoring barks.
  - .ogg output. ElevenLabs returns mp3 by default; we save .mp3 and
    let Godot import it. The design doc says .ogg; this is a deliberate
    deviation that should be reconciled later (Godot 4 imports both).

ELEVENLABS API DETAILS
======================
The renderer calls the v1 text-to-speech endpoint:
  POST https://api.elevenlabs.io/v1/text-to-speech/{voice_id}

Required headers:
  xi-api-key: <from ELEVENLABS_API_KEY env var>
  Content-Type: application/json
  Accept: audio/mpeg

Body (matches the render_contract fields in CHARACTER_VOICES.md):
  {
    "text": "...",
    "model_id": "eleven_v3",
    "voice_settings": {
      "stability": 0.40,
      "similarity_boost": 0.78,
      "style": 0.0,
      "use_speaker_boost": true,
      "speed": 1.0
    },
    "seed": 471829   // optional; only sent if locked in the contract
  }

We use only the standard library: urllib for the HTTP call, hashlib for
text hashing, json for the manifest. No pip install needed.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path


# ---------------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------------
REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = REPO_ROOT / "dialogue" / "scripts"
CHARACTER_VOICES_FILE = REPO_ROOT / "dialogue" / "CHARACTER_VOICES.md"
AUDIO_ROOT = REPO_ROOT / "audio" / "dialogue"
SPEND_LOG = AUDIO_ROOT / "_spend.log"

ELEVENLABS_API = "https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"
DEFAULT_COST_CAP_USD = 5.00

# ElevenLabs pricing as of writing (USD per 1k characters). This is a rough
# estimate for the cost cap; actual billing may differ. Update from the
# pricing page when it changes.
APPROX_USD_PER_1K_CHARS = 0.30

# Audio file extension we save. ElevenLabs default is mp3; see file header.
AUDIO_EXT = "mp3"


# ---------------------------------------------------------------------------
# RENDER CONTRACT PARSING
# ---------------------------------------------------------------------------
# CHARACTER_VOICES.md has YAML blocks of the form:
#
#   ```yaml
#   # Render Contract — ROLAND
#   voice_id: TBD
#   model: eleven_v3
#   stability: 0.40
#   ...
#   ```
#
# We parse these without a YAML library because the format is tightly
# constrained: only flat "key: value" lines, with values that are strings,
# numbers, booleans, or null. Anything fancier than that should be
# reconsidered before being added to a render contract.

CONTRACT_HEADER = re.compile(r"^#\s*Render Contract\s*[—-]\s*([A-Z][A-Z ]+)\s*$")


def parse_contract_value(raw: str) -> object:
    """Convert a YAML-ish scalar to a Python value. Strips inline comments."""
    # Strip trailing inline comment ("# something") but not inside quotes.
    if "#" in raw and not (raw.startswith('"') or raw.startswith("'")):
        raw = raw.split("#", 1)[0]
    raw = raw.strip()

    if raw == "" or raw.lower() in {"null", "none", "~"}:
        return None
    if raw.lower() == "true":
        return True
    if raw.lower() == "false":
        return False
    if raw.startswith(("'", '"')) and raw.endswith(raw[0]):
        return raw[1:-1]
    # Try int, then float, then string.
    try:
        return int(raw)
    except ValueError:
        pass
    try:
        return float(raw)
    except ValueError:
        pass
    return raw


def load_render_contracts() -> dict[str, dict]:
    """
    Walk CHARACTER_VOICES.md, find every fenced ```yaml block whose first
    comment is a "Render Contract — NAME" header, and return a dict of
    {NAME: {field: value}}.
    """
    if not CHARACTER_VOICES_FILE.exists():
        sys.exit(f"[FAIL] CHARACTER_VOICES.md not found at {CHARACTER_VOICES_FILE}")

    text = CHARACTER_VOICES_FILE.read_text(encoding="utf-8")
    contracts: dict[str, dict] = {}

    # Find ```yaml ... ``` blocks.
    for block in re.finditer(r"```yaml\s*\n(.*?)\n```", text, re.DOTALL):
        lines = block.group(1).splitlines()
        if not lines:
            continue
        header = CONTRACT_HEADER.match(lines[0].strip())
        if not header:
            continue
        name = header.group(1).strip()
        contract: dict[str, object] = {}
        for line in lines[1:]:
            line = line.rstrip()
            if not line.strip() or line.strip().startswith("#"):
                continue
            if ":" not in line:
                continue
            key, _, raw = line.partition(":")
            contract[key.strip()] = parse_contract_value(raw)
        contracts[name] = contract

    return contracts


# ---------------------------------------------------------------------------
# SCRIPT PARSING
# ---------------------------------------------------------------------------
SCRIPT_LINE = re.compile(r"^([A-Z][A-Z\- ]+):\s*(.+)$")


def parse_script(script_path: Path) -> list[dict]:
    """
    Parse a TTS script into a list of {speaker, text} dicts. Each non-empty
    line in the script that matches "SPEAKER: text" becomes one entry.
    Multi-line utterances (rare in scripts) are joined with a space.
    """
    lines: list[dict] = []
    current: dict | None = None

    for raw in script_path.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip()
        if not line:
            if current:
                lines.append(current)
                current = None
            continue

        m = SCRIPT_LINE.match(line)
        if m:
            if current:
                lines.append(current)
            current = {"speaker": m.group(1).strip(), "text": m.group(2).strip()}
        else:
            # Continuation of the previous utterance (rare).
            if current:
                current["text"] += " " + line.strip()

    if current:
        lines.append(current)

    return lines


# ---------------------------------------------------------------------------
# MANIFEST
# ---------------------------------------------------------------------------
def text_hash(text: str) -> str:
    """SHA-256 over the spoken text. The hash is what makes regen surgical."""
    return "sha256:" + hashlib.sha256(text.encode("utf-8")).hexdigest()


def scene_id_from_script(script_path: Path) -> str:
    """The scene id is just the script's stem (filename without extension)."""
    return script_path.stem


def manifest_path_for(script_path: Path) -> Path:
    return AUDIO_ROOT / scene_id_from_script(script_path) / "manifest.json"


def load_manifest(script_path: Path) -> dict:
    """Load the manifest if it exists, else return an empty skeleton."""
    path = manifest_path_for(script_path)
    if path.exists():
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)

    return {
        "scene_id": scene_id_from_script(script_path),
        "script": str(script_path.relative_to(REPO_ROOT)),
        "draft": str((REPO_ROOT / "dialogue" / "drafts" /
                     (script_path.stem + ".md")).relative_to(REPO_ROOT)),
        "tier": None,  # writer fills this in once known
        "lines": [],
    }


def save_manifest(script_path: Path, manifest: dict) -> None:
    path = manifest_path_for(script_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")


# ---------------------------------------------------------------------------
# RENDER
# ---------------------------------------------------------------------------
def line_index_for(existing_indexes: set[str], next_natural: int) -> tuple[str, int]:
    """
    Return a fresh zero-padded 3-digit line index. Matches TTS_PIPELINE.md
    §5.1: indexes are stable, so we always allocate the lowest unused one.
    """
    idx = next_natural
    while f"{idx:03d}" in existing_indexes:
        idx += 1
    return f"{idx:03d}", idx + 1


def estimated_cost_usd(lines_to_render: list[tuple[dict, str]]) -> float:
    chars = sum(len(text) for _, text in lines_to_render)
    return (chars / 1000.0) * APPROX_USD_PER_1K_CHARS


def call_elevenlabs(text: str, voice_id: str, contract: dict, api_key: str) -> bytes:
    """
    POST to ElevenLabs and return the audio bytes. Raises on non-200.
    """
    url = ELEVENLABS_API.format(voice_id=voice_id)
    body = {
        "text": text,
        "model_id": contract.get("model", "eleven_v3"),
        "voice_settings": {
            "stability": contract.get("stability", 0.5),
            "similarity_boost": contract.get("similarity_boost", 0.75),
            "style": contract.get("style", 0.0),
            "use_speaker_boost": contract.get("use_speaker_boost", True),
            "speed": contract.get("speed", 1.0),
        },
    }
    if contract.get("seed") is not None:
        body["seed"] = contract["seed"]

    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "xi-api-key": api_key,
            "Content-Type": "application/json",
            "Accept": "audio/mpeg",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.read()
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")[:400]
        raise RuntimeError(
            f"ElevenLabs returned {e.code}: {detail}"
        ) from e


def render_script(
    script_path: Path,
    contracts: dict[str, dict],
    api_key: str | None,
    dry_run: bool,
    mock: bool,
    cost_cap: float,
) -> tuple[int, int, float]:
    """
    Render every line in a script that needs it. Returns
    (rendered_count, skipped_count, actual_cost_usd).
    """
    if "/barks/" in str(script_path):
        print(f"[SKIP] {script_path.name}: bark scripts not yet supported.")
        return (0, 0, 0.0)

    lines = parse_script(script_path)
    manifest = load_manifest(script_path)
    by_index = {entry["index"]: entry for entry in manifest["lines"]}
    by_position: dict[int, dict] = {}
    for pos, entry in enumerate(manifest["lines"]):
        by_position[pos] = entry

    pending: list[tuple[dict, str]] = []  # (manifest_entry, text)
    skipped = 0
    next_natural = 1
    existing_indexes = set(by_index.keys())

    audio_dir = AUDIO_ROOT / scene_id_from_script(script_path)

    new_lines: list[dict] = []
    for pos, line in enumerate(lines):
        speaker = line["speaker"]
        text = line["text"]
        h = text_hash(text)

        # Try to match by position first (line order is meaningful), then
        # fall back to any existing entry with the same hash. If neither
        # matches, this is a new line.
        existing = by_position.get(pos)
        if existing and existing.get("speaker") == speaker and existing.get("text_hash") == h:
            audio_path = audio_dir / existing["audio"]
            if audio_path.exists():
                new_lines.append(existing)
                skipped += 1
                continue

        # Need to render. Allocate or reuse the index.
        if existing and existing.get("speaker") == speaker:
            idx = existing["index"]
        else:
            idx, next_natural = line_index_for(existing_indexes, next_natural)
            existing_indexes.add(idx)

        contract = contracts.get(speaker)
        if not contract:
            print(f"[FAIL] {script_path.name} line {idx}: no render contract for "
                  f"speaker {speaker!r}. Add a Render Contract block to "
                  f"dialogue/CHARACTER_VOICES.md.", file=sys.stderr)
            return (0, skipped, 0.0)

        audio_filename = f"{idx}_{speaker.lower()}.{AUDIO_EXT}"
        entry = {
            "index": idx,
            "speaker": speaker,
            "text_hash": h,
            "audio": audio_filename,
            "voice_id": contract.get("voice_id"),
            "model": contract.get("model"),
            "stability": contract.get("stability"),
            "similarity_boost": contract.get("similarity_boost"),
            "style": contract.get("style"),
            "speed": contract.get("speed"),
            "seed": contract.get("seed"),
            "rendered_at": None,
            "approved": False,
        }
        new_lines.append(entry)
        pending.append((entry, text))

    if not pending:
        print(f"[OK]   {script_path.name}: {skipped} lines up to date, nothing to render.")
        return (0, skipped, 0.0)

    estimate = estimated_cost_usd(pending)
    print(f"[PLAN] {script_path.name}: {len(pending)} lines to render "
          f"(~{sum(len(t) for _, t in pending)} chars, est. ${estimate:.2f}). "
          f"Skipping {skipped} unchanged.")

    if estimate > cost_cap:
        print(f"[FAIL] Estimated cost ${estimate:.2f} exceeds cap ${cost_cap:.2f}. "
              f"Re-run with --cost-cap to override.", file=sys.stderr)
        return (0, skipped, 0.0)

    if dry_run:
        for entry, text in pending:
            print(f"  would render {entry['index']}_{entry['speaker'].lower()} "
                  f"({len(text)} chars): {text[:60]!r}{'...' if len(text)>60 else ''}")
        return (0, skipped, 0.0)

    # Validate voice IDs before any network call. In --mock mode we skip
    # this — placeholders don't need real voice IDs.
    if not mock:
        unlocked = sorted({
            entry["speaker"] for entry, _ in pending
            if not entry["voice_id"] or entry["voice_id"] == "TBD"
        })
        if unlocked:
            print(f"[FAIL] {script_path.name}: voice_id is TBD for "
                  f"{', '.join(unlocked)}. Lock a real ElevenLabs voice ID in "
                  f"CHARACTER_VOICES.md before rendering. (Use --mock to "
                  f"generate placeholder files for pipeline testing.)",
                  file=sys.stderr)
            return (0, skipped, 0.0)

    audio_dir.mkdir(parents=True, exist_ok=True)
    rendered = 0
    actual_cost = 0.0

    for entry, text in pending:
        out = audio_dir / entry["audio"]
        if mock:
            # Write a tiny placeholder so downstream tooling has a file to find.
            out.write_bytes(b"")
            audio_bytes = b""
        else:
            if not api_key:
                print("[FAIL] ELEVENLABS_API_KEY env var not set. Either set it, "
                      "or use --mock / --dry-run.", file=sys.stderr)
                return (rendered, skipped, actual_cost)
            try:
                audio_bytes = call_elevenlabs(
                    text, entry["voice_id"], contracts[entry["speaker"]], api_key
                )
            except Exception as e:
                print(f"[FAIL] line {entry['index']}: {e}", file=sys.stderr)
                # Save manifest progress so we can resume.
                manifest["lines"] = new_lines
                save_manifest(script_path, manifest)
                return (rendered, skipped, actual_cost)
            out.write_bytes(audio_bytes)

        entry["rendered_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
        rendered += 1
        actual_cost += (len(text) / 1000.0) * APPROX_USD_PER_1K_CHARS

        # Save manifest after every line so an interrupted run is resumable.
        manifest["lines"] = new_lines
        save_manifest(script_path, manifest)
        print(f"  [OK] {entry['index']}_{entry['speaker'].lower()} "
              f"({len(audio_bytes)} bytes)")

    return (rendered, skipped, actual_cost)


def append_spend_log(line: str) -> None:
    SPEND_LOG.parent.mkdir(parents=True, exist_ok=True)
    with SPEND_LOG.open("a", encoding="utf-8") as f:
        f.write(line + "\n")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main() -> int:
    parser = argparse.ArgumentParser(
        description="Render TTS scripts to audio via ElevenLabs. See "
                    "design/TTS_PIPELINE.md §6 for the bulk pipeline spec."
    )
    parser.add_argument("script", nargs="?", type=Path,
                        help="Path to a script .txt file. Omit with --all.")
    parser.add_argument("--all", action="store_true",
                        help="Render every script in dialogue/scripts/.")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print what would be rendered, no network calls.")
    parser.add_argument("--mock", action="store_true",
                        help="Write zero-byte placeholder audio files instead "
                             "of calling ElevenLabs. Useful for testing the "
                             "pipeline without an API key.")
    parser.add_argument("--cost-cap", type=float, default=DEFAULT_COST_CAP_USD,
                        help=f"Per-run cost cap in USD (default: "
                             f"${DEFAULT_COST_CAP_USD:.2f}).")
    args = parser.parse_args()

    contracts = load_render_contracts()
    if not contracts:
        sys.exit("[FAIL] No render contracts parsed from CHARACTER_VOICES.md.")

    api_key = os.environ.get("ELEVENLABS_API_KEY")

    if args.all:
        scripts = sorted(SCRIPTS_DIR.glob("*.txt"))
    elif args.script:
        # Resolve to an absolute path so relative_to(REPO_ROOT) works
        # regardless of the user's working directory.
        scripts = [args.script.resolve()]
    else:
        parser.print_help()
        return 2

    total_rendered = total_skipped = 0
    total_cost = 0.0
    for script in scripts:
        rendered, skipped, cost = render_script(
            script, contracts, api_key, args.dry_run, args.mock, args.cost_cap,
        )
        total_rendered += rendered
        total_skipped += skipped
        total_cost += cost

    print(f"\n[SUMMARY] rendered {total_rendered}, skipped (cached) "
          f"{total_skipped}, est. cost ${total_cost:.4f}")

    if total_rendered > 0 and not args.dry_run and not args.mock:
        timestamp = dt.datetime.now(dt.timezone.utc).isoformat()
        append_spend_log(
            f"{timestamp}\trendered={total_rendered}\tskipped={total_skipped}"
            f"\tcost_usd={total_cost:.4f}"
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
