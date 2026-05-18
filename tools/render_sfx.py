#!/usr/bin/env python3
"""
render_sfx.py — render the SFX prompt tables to audio via ElevenLabs.

WHAT THIS DOES, IN PLAIN ENGLISH
================================
Reads design/SFX_PROMPTS.md, finds every sound-effect row (the tables whose
header is `id | prompt | dur | infl | loop | var | bus`), and asks the
ElevenLabs *Sound Effects* API to generate several candidate versions of
each one. It writes the candidates into a review folder, one subfolder per
SFX id, so you can listen and pick the keeper(s) by hand:

    <OUT>/02_combat/cmb_longsword_parry/cmb_longsword_parry_v01.mp3
                                        cmb_longsword_parry_v02.mp3
                                        ...

Every key detail from the doc is respected on each API call:
  - text             ← the prompt cell, verbatim
  - duration_seconds ← the `dur` cell  ("auto" => omitted, ElevenLabs decides;
                        a number => clamped to the API's 0.5–22 s range)
  - prompt_influence ← the `infl` cell (0.0–1.0)
  - loop             ← the `loop` cell (Y => loop:true, seamless generation)

It is IDEMPOTENT and COST-CAPPED, exactly like render_bulk.py:
  - Each row hashes (prompt, dur, infl, loop, versions). If the hash is
    unchanged and the candidate files already exist, the row is skipped.
    So a re-run only renders new/changed rows — safe to leave running.
  - A CREDIT estimate (vs your monthly plan) is printed BEFORE any network
    call. You confirm, or it aborts. A hard --credit-cap (default 20000
    credits) aborts before spending over. The estimate uses CREDITS_PER_
    SECOND / MIN_CREDITS_PER_GEN — calibrate them from your dashboard after
    the first small batch (ElevenLabs bills SFX by duration, in credits).
  - --dry-run shows the plan with no API calls.
  - --mock writes tiny placeholder files (no API key, no spend) so you can
    test parsing / folders / idempotency.

stdlib only — no `pip install`, same as the rest of tools/.

DEFAULT OUTPUT LOCATION
=======================
Defaults to the Windows review folder you asked for:

    C:\\Users\\Matt Noles\\Desktop\\SFX

Override with --out PATH or the SFX_OUT_DIR env var. The folder is created
if missing. (This script is meant to run on your Windows machine where your
ElevenLabs key lives; it's cross-platform but the default path is Windows.)

RUN EXAMPLES
============
  # 1. Sanity-check parsing — list every row, no calls, no key needed:
  python3 tools/render_sfx.py --list

  # 2. See the spend plan for all of Phase 1, no calls:
  python3 tools/render_sfx.py --phase 1 --dry-run

  # 3. Test the whole pipeline with zero-byte placeholders (no spend):
  python3 tools/render_sfx.py --category 02 --mock

  # 4. Render one category for real (needs the key):
  set ELEVENLABS_API_KEY=sk-...        (Windows: setx, or set for the session)
  python3 tools/render_sfx.py --category 02

  # 5. Render everything in the doc, bigger cap, skip the confirm prompt:
  python3 tools/render_sfx.py --credit-cap 90000 --yes

  # 6. Re-render just one id after you tweaked its prompt in the doc:
  python3 tools/render_sfx.py --id cmb_bear_rear_roar --force

  # 7. Label every output folder with keep-count/loop (no API, no cost):
  python3 tools/render_sfx.py --annotate

USEFUL FLAGS
============
  --phase N          only rows in Phase N (Phase 1 = the whole current doc)
  --category NN      only rows whose id maps to category NN (01,02,03,07,08,09)
  --id NAME          only that one id (repeatable)
  --versions N       force exactly N candidates per row (default: var + 2)
  --limit N          stop after N rows (handy for a first taste)
  --out PATH         output root (default: the Desktop\\SFX path above)
  --credit-cap N     abort if est. exceeds this many credits (default 20000;
                     --cost-cap is a deprecated alias)
  --plan-credits N   monthly allowance for the % display (default 131000)
  --yes              don't ask for confirmation before spending
  --force            re-render even if the row hash is unchanged
  --dry-run          plan only, no API calls
  --mock             placeholder files, no API calls, no key required
  --annotate         write 0_KEEP-<N> / 0_LOOP_KEEP-1 label files + index
                     into the output folders, then exit (no API, no cost)

ELEVENLABS API
==============
  POST https://api.elevenlabs.io/v1/sound-generation
  headers: xi-api-key, Content-Type: application/json, Accept: audio/mpeg
  body:    {"text", "duration_seconds"?, "prompt_influence", "loop"}
  returns: audio/mpeg (mp3). Godot 4 imports mp3 natively — we save .mp3
           here, same deliberate deviation as render_bulk.py. Convert the
           approved keepers to mono .ogg when you move them into the repo:
             ffmpeg -i in.mp3 -ac 1 -ar 44100 -c:a libvorbis out.ogg
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

# --------------------------------------------------------------------------
# Constants
# --------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent
PROMPTS_DOC = REPO_ROOT / "design" / "SFX_PROMPTS.md"

DEFAULT_OUT = r"C:\Users\Matt Noles\Desktop\SFX"

API_URL = "https://api.elevenlabs.io/v1/sound-generation"
API_TIMEOUT_S = 120
API_RETRIES = 3            # network-error retries with exponential backoff

DUR_MIN, DUR_MAX = 0.5, 22.0   # ElevenLabs Sound Effects duration bounds

# Cost discipline — ElevenLabs bills Sound Effects in CREDITS, by the
# duration of audio generated, with a per-generation minimum. These two
# constants are best-effort estimates; ElevenLabs pricing varies by plan and
# changes over time. CALIBRATE them: run a small batch (e.g. --category 09),
# read your credit balance before/after, and set these to the measured
# values. The PLAN line is an estimate, not a contract — your dashboard
# shows the exact credit cost before each generation.
CREDITS_PER_SECOND = 11        # CALIBRATED from the 44-gen Water batch:
                               # ~1,697 credits / 156 s audio ≈ 10.9, rounded
                               # up to 11 for a slightly conservative estimate.
MIN_CREDITS_PER_GEN = 5        # CALIBRATED: no real per-gen floor — 35 short
                               # clips would have cost >3,500 at a 100 floor
                               # but the whole batch was ~1,697, so ~linear.
AUTO_DURATION_ASSUMED_S = 5    # only used to price "auto" rows (none today)
PLAN_CREDITS_DEFAULT = 131000  # your Creator monthly allowance (display only)

DEFAULT_CREDIT_CAP = 20000     # abort a run estimated above this many credits
EXTRA_VERSIONS = 2         # candidates rendered = var + EXTRA_VERSIONS
MIN_VERSIONS = 3


def gen_credits(duration_s):
    """Estimated credits for one generation of the given duration."""
    secs = AUTO_DURATION_ASSUMED_S if duration_s is None else duration_s
    return max(MIN_CREDITS_PER_GEN, int(round(CREDITS_PER_SECOND * secs)))


# id-prefix -> review subfolder. Extend as later phases/categories land.
FOLDER_RULES = [
    (("step_", "jumpland", "jump_", "land_", "armor_", "climb_", "vault_",
      "water_wade", "water_entry", "roland_"), "01_locomotion"),
    (("cmb_",), "02_combat"),
    (("fire_", "camp_"), "09_fire_camp"),
    (("wx_",), "07_weather"),
    (("water_",), "08_water"),
]

# id-prefix -> category number (for --category filtering).
CATEGORY_RULES = [
    (("step_", "jumpland", "jump_", "land_", "armor_", "climb_", "vault_",
      "water_wade", "water_entry", "roland_"), "01"),
    (("cmb_",), "02"),          # impacts + enemies live in cmb_* too
    (("fire_", "camp_"), "09"),
    (("wx_",), "07"),
    (("water_",), "08"),
]

EXPECTED_HEADER = ["id", "prompt", "dur", "infl", "loop", "var", "bus"]


# --------------------------------------------------------------------------
# Parsing
# --------------------------------------------------------------------------

class Row:
    __slots__ = ("id", "prompt", "dur", "infl", "loop", "var", "bus",
                 "section")

    def __init__(self, d, section):
        self.id = d["id"]
        self.prompt = d["prompt"]
        self.dur = d["dur"]            # str: "auto" or a number
        self.infl = float(d["infl"])
        self.loop = d["loop"].strip().upper().startswith("Y")
        self.var = int(re.sub(r"[^0-9]", "", d["var"]) or "1")
        self.bus = d["bus"]
        self.section = section

    def duration_value(self):
        """Return float seconds clamped to API bounds, or None for 'auto'."""
        v = self.dur.strip().lower()
        if v in ("auto", "", "-"):
            return None
        try:
            f = float(v)
        except ValueError:
            return None
        return max(DUR_MIN, min(DUR_MAX, f))

    def versions(self, override):
        if override is not None:
            return max(1, override)
        return max(MIN_VERSIONS, self.var + EXTRA_VERSIONS)

    def folder(self):
        for prefixes, name in FOLDER_RULES:
            if self.id.startswith(prefixes):
                return name
        return "_misc"

    def category(self):
        for prefixes, num in CATEGORY_RULES:
            if self.id.startswith(prefixes):
                return num
        return "00"

    def hash(self, versions):
        h = hashlib.sha256()
        h.update("␟".join([
            self.id, self.prompt, str(self.dur), f"{self.infl:.3f}",
            "L" if self.loop else "N", str(versions),
        ]).encode("utf-8"))
        return h.hexdigest()


def _split_md_row(line):
    # "| a | b | c |" -> ["a","b","c"]  (prompts contain no '|')
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    return cells


def parse_prompts(doc_path):
    """Parse only the tables whose header matches EXPECTED_HEADER."""
    if not doc_path.exists():
        sys.exit(f"ERROR: {doc_path} not found. Pull the branch first.")

    rows = []
    section = "?"
    in_table = False
    header_idx = None
    lines = doc_path.read_text(encoding="utf-8").splitlines()

    for ln in lines:
        s = ln.strip()

        m = re.match(r"^#{1,6}\s+(.*)$", s)
        if m:
            section = m.group(1).strip()
            in_table = False
            header_idx = None
            continue

        if s.startswith("|"):
            cells = _split_md_row(s)
            # header?
            norm = [c.lower() for c in cells]
            if norm == EXPECTED_HEADER:
                in_table = True
                header_idx = {k: i for i, k in enumerate(norm)}
                continue
            # separator row like |---|---|
            if set("".join(cells)) <= set("-: "):
                continue
            if in_table and header_idx is not None:
                if len(cells) < len(EXPECTED_HEADER):
                    continue
                d = {k: cells[i] for k, i in header_idx.items()}
                if not d["id"] or d["id"].lower() == "id":
                    continue
                try:
                    rows.append(Row(d, section))
                except Exception as e:  # noqa: BLE001
                    print(f"  ! skipped malformed row {d.get('id')!r}: {e}")
        else:
            in_table = False
            header_idx = None

    return rows


# --------------------------------------------------------------------------
# Manifest
# --------------------------------------------------------------------------

def load_manifest(out_root):
    p = out_root / "_manifest.json"
    if p.exists():
        try:
            return json.loads(p.read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001
            return {}
    return {}


def save_manifest(out_root, manifest):
    p = out_root / "_manifest.json"
    p.write_text(json.dumps(manifest, indent=2, sort_keys=True),
                 encoding="utf-8")


def _keep_action(row):
    if row.loop:
        return "CHECK SEAM, then keep 1 (continuous loop)"
    if row.var >= 2:
        return f"keep {row.var} variants (engine random-picks)"
    return "pick 1 best"


def write_annotations(rows, out_root):
    """Stamp keep-count/loop labels into the review folders.

    Purely additive: creates `0_*` label/index files so you can see, in
    Windows Explorer, how many takes to keep and which are loops — without
    opening the doc. No API calls, no cost, safe to run anytime.
    """
    out_root.mkdir(parents=True, exist_ok=True)
    by_folder = {}
    top = [f"{'category/id':<46}{'loop':<6}{'keep':<6}action",
           "-" * 78]
    for r in sorted(rows, key=lambda x: (x.folder(), x.id)):
        action = _keep_action(r)
        id_dir = out_root / r.folder() / r.id
        id_dir.mkdir(parents=True, exist_ok=True)
        for old in list(id_dir.glob("0_KEEP-*.txt")) + \
                list(id_dir.glob("0_LOOP*.txt")):
            old.unlink()
        marker = f"0_{'LOOP_' if r.loop else ''}KEEP-{r.var}.txt"
        (id_dir / marker).write_text(
            f"{r.id}\n"
            f"loop : {'YES - check the seam first' if r.loop else 'no'}\n"
            f"keep : {r.var}\n"
            f"what : {action}\n", encoding="utf-8")
        line = f"{r.id:<40}{'Y' if r.loop else 'n':<6}{r.var:<6}{action}"
        by_folder.setdefault(r.folder(), []).append(line)
        top.append(f"{r.folder() + '/' + r.id:<46}"
                   f"{'Y' if r.loop else 'n':<6}{r.var:<6}{action}")
    for folder, lines in by_folder.items():
        (out_root / folder / "0_INDEX.txt").write_text(
            f"{'id':<40}{'loop':<6}{'keep':<6}action\n" + "-" * 70 + "\n"
            + "\n".join(lines) + "\n", encoding="utf-8")
    (out_root / "0_KEEP_INDEX.txt").write_text(
        "\n".join(top) + "\n", encoding="utf-8")
    return len(rows), len(by_folder)


def append_spend_log(out_root, line_count, est_credits):
    log = out_root / "_spend.log"
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with log.open("a", encoding="utf-8") as f:
        f.write(f"{stamp}\t{line_count} generations\t"
                f"~{est_credits} credits (est)\n")


# --------------------------------------------------------------------------
# ElevenLabs call
# --------------------------------------------------------------------------

def render_one(api_key, row, duration, mp3_path):
    body = {
        "text": row.prompt,
        "prompt_influence": round(row.infl, 3),
        "loop": bool(row.loop),
    }
    if duration is not None:
        body["duration_seconds"] = round(duration, 2)

    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(API_URL, data=data, method="POST")
    req.add_header("xi-api-key", api_key)
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "audio/mpeg")

    last_err = None
    for attempt in range(1, API_RETRIES + 1):
        try:
            with urllib.request.urlopen(req, timeout=API_TIMEOUT_S) as resp:
                audio = resp.read()
            mp3_path.parent.mkdir(parents=True, exist_ok=True)
            mp3_path.write_bytes(audio)
            return True, None
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")[:500]
            return False, f"HTTP {e.code}: {detail}"
        except (urllib.error.URLError, TimeoutError) as e:
            last_err = str(e)
            if attempt < API_RETRIES:
                time.sleep(2 ** attempt)
    return False, f"network error after {API_RETRIES} tries: {last_err}"


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(
        description="Render SFX_PROMPTS.md to ElevenLabs candidate audio.")
    ap.add_argument("--out", default=os.environ.get("SFX_OUT_DIR",
                                                    DEFAULT_OUT))
    ap.add_argument("--phase", type=int, default=None)
    ap.add_argument("--category", action="append", default=[],
                    help="category number, e.g. 02 (repeatable)")
    ap.add_argument("--id", action="append", default=[],
                    help="single id (repeatable)")
    ap.add_argument("--versions", type=int, default=None)
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--credit-cap", type=int, default=DEFAULT_CREDIT_CAP,
                    help="abort if the run's estimate exceeds this many "
                         "ElevenLabs credits (default 20000)")
    ap.add_argument("--cost-cap", type=int, dest="credit_cap",
                    help="deprecated alias for --credit-cap (credits)")
    ap.add_argument("--plan-credits", type=int,
                    default=PLAN_CREDITS_DEFAULT,
                    help="your monthly credit allowance, for the %% display")
    ap.add_argument("--yes", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--mock", action="store_true")
    ap.add_argument("--list", action="store_true",
                    help="print parsed rows and exit (no calls)")
    ap.add_argument("--annotate", action="store_true",
                    help="write keep-count/loop label files into the output "
                         "folders and exit (no API, no cost)")
    args = ap.parse_args()

    rows = parse_prompts(PROMPTS_DOC)
    if not rows:
        sys.exit("ERROR: no SFX rows parsed. Doc schema may have changed.")

    # Filters
    if args.category:
        want = {c.zfill(2) for c in args.category}
        rows = [r for r in rows if r.category() in want]
    if args.id:
        want_ids = set(args.id)
        rows = [r for r in rows if r.id in want_ids]
    # The current doc IS Phase 1; --phase>1 yields nothing until later phases
    # are appended with explicit Phase markers.
    if args.phase is not None and args.phase != 1:
        rows = []

    if args.list:
        for r in rows:
            d = r.duration_value()
            ds = "auto" if d is None else f"{d:g}s"
            print(f"{r.category()}  {r.id:<32} v{r.versions(args.versions)} "
                  f"{ds:<6} infl={r.infl:g} loop={'Y' if r.loop else 'N'}")
        print(f"\n{len(rows)} rows.")
        return

    if args.annotate:
        n, f = write_annotations(rows, Path(args.out))
        print(f"Annotated {n} ids across {f} folders in {Path(args.out)}")
        print("  - each id folder: a 0_KEEP-<N>.txt (or 0_LOOP_KEEP-1.txt)")
        print("  - each category folder: 0_INDEX.txt")
        print("  - output root: 0_KEEP_INDEX.txt")
        print("No API calls, no cost.")
        return

    if args.limit is not None:
        rows = rows[:args.limit]
    if not rows:
        sys.exit("Nothing to do after filters.")

    out_root = Path(args.out)
    # Load manifest in mock too, so --mock can exercise idempotency/regen.
    manifest = load_manifest(out_root) if out_root.exists() else {}

    # Build the plan (respect idempotency)
    plan = []          # list of (row, versions, [missing_indices])
    skipped = 0
    for r in rows:
        v = r.versions(args.versions)
        h = r.hash(v)
        folder = out_root / r.folder() / r.id
        existing = manifest.get(r.id, {})
        files_ok = all((folder / f"{r.id}_v{i:02d}.mp3").exists()
                       for i in range(1, v + 1))
        stale = existing.get("hash") != h   # prompt/params changed in the doc
        if not args.force and not stale and files_ok:
            skipped += 1
            continue
        if args.force or stale:
            # Force, or the prompt/params changed: the old takes are from a
            # different prompt — supersede ALL versions of this row.
            missing = list(range(1, v + 1))
        else:
            # Same prompt, interrupted run: only fill the missing takes.
            missing = [i for i in range(1, v + 1)
                       if not (folder / f"{r.id}_v{i:02d}.mp3").exists()]
        plan.append((r, v, h, missing))

    total_gens = sum(len(m) for _, _, _, m in plan)
    est = sum(len(m) * gen_credits(r.duration_value())
              for r, _, _, m in plan)
    pct = (100.0 * est / args.plan_credits) if args.plan_credits else 0.0

    print("=" * 64)
    print(f"SFX render plan  ({PROMPTS_DOC.relative_to(REPO_ROOT)})")
    print(f"  rows in scope     : {len(rows)}")
    print(f"  up-to-date (skip) : {skipped}")
    print(f"  rows to render    : {len(plan)}")
    print(f"  generations       : {total_gens}")
    print(f"  est. credits      : ~{est:,}  (cap {args.credit_cap:,})")
    print(f"  ~ {pct:.1f}% of a {args.plan_credits:,}-credit monthly plan")
    print(f"  (ESTIMATE - {CREDITS_PER_SECOND} cr/s, {MIN_CREDITS_PER_GEN} "
          f"min/gen; calibrate from your dashboard)")
    print(f"  output root       : {out_root}")
    print(f"  mode              : "
          f"{'DRY-RUN' if args.dry_run else 'MOCK' if args.mock else 'LIVE'}")
    print("=" * 64)
    for r, v, _, m in plan[:40]:
        print(f"  {r.id:<34} {len(m)}/{v} gen  "
              f"loop={'Y' if r.loop else 'N'}")
    if len(plan) > 40:
        print(f"  ... and {len(plan) - 40} more rows")

    if args.dry_run:
        print("\nDRY-RUN: no API calls made.")
        return

    if not args.mock and est > args.credit_cap:
        sys.exit(f"\nABORT: estimate ~{est:,} credits exceeds cap "
                 f"{args.credit_cap:,}. Narrow with --category/--id/"
                 f"--limit, or raise --credit-cap.")

    api_key = os.environ.get("ELEVENLABS_API_KEY")
    if not args.mock and not api_key:
        sys.exit("\nERROR: ELEVENLABS_API_KEY not set (use --mock to test).")

    if not args.yes and not args.mock:
        ans = input(f"\nRender {total_gens} generations "
                    f"(~{est:,} credits est)? [y/N] ").strip().lower()
        if ans != "y":
            sys.exit("Aborted.")

    out_root.mkdir(parents=True, exist_ok=True)
    done_gens = 0
    done_credits = 0
    for r, v, h, missing in plan:
        folder = out_root / r.folder() / r.id
        duration = r.duration_value()
        for i in missing:
            mp3 = folder / f"{r.id}_v{i:02d}.mp3"
            if args.mock:
                mp3.parent.mkdir(parents=True, exist_ok=True)
                mp3.write_bytes(b"")
                ok, err = True, None
            else:
                ok, err = render_one(api_key, r, duration, mp3)
            done_gens += 1
            if ok:
                done_credits += gen_credits(duration)
            tag = "ok " if ok else "ERR"
            print(f"[{done_gens}/{total_gens}] {tag} {r.id}_v{i:02d}"
                  + ("" if ok else f"  -- {err}"))
            if not ok:
                # don't burn the whole run on one bad row; move on
                continue
        manifest[r.id] = {
            "hash": h,
            "versions": v,
            "prompt": r.prompt,
            "duration": "auto" if duration is None else duration,
            "prompt_influence": r.infl,
            "loop": r.loop,
            "folder": str(Path(r.folder()) / r.id),
            "rendered_utc": datetime.now(timezone.utc).strftime(
                "%Y-%m-%dT%H:%M:%SZ"),
        }
        save_manifest(out_root, manifest)

    save_manifest(out_root, manifest)
    if not args.mock:
        append_spend_log(out_root, done_gens, done_credits)

    print("\nDone.")
    print(f"  rendered : {done_gens} files")
    print(f"  review   : {out_root}  (one subfolder per id; pick keepers,")
    print(f"             convert with ffmpeg, drop into assets/audio/sfx/)")


if __name__ == "__main__":
    main()
