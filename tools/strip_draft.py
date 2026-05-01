#!/usr/bin/env python3
"""
strip_draft.py — turn a dialogue draft (.md) into a TTS-ready script (.txt).

WHAT THIS DOES, IN PLAIN ENGLISH
================================
A "draft" lives in dialogue/drafts/*.md. It is written for humans: it has
scene headers, voice notes, stage directions, designer notes, and the
spoken dialogue interleaved with parentheticals. The TTS model would
choke on most of that — it would literally read the stage directions
out loud.

This script reads a draft, finds the "## Script (Prose)" section,
extracts only what the characters actually speak, and writes a clean
TTS script (dialogue/scripts/*.txt) in the format defined by
dialogue/STYLE.md.

It is a DETERMINISTIC TRANSFORM. The same draft must always produce
the same script. It does NOT invent performance tags like [nervous]
or [calm] — those are the writer's job during a quick review pass
after stripping. This script only converts what is explicitly in the
draft (a "(quietly)" parenthetical → "[quietly]" tag, etc.).

Run it like this:

    python3 tools/strip_draft.py dialogue/drafts/act1_scene_sorting_room.md

That writes dialogue/scripts/act1_scene_sorting_room.txt next to the existing
script (overwriting it). Add --check to compare without writing, or
--all to strip every .md in dialogue/drafts/.

If the draft has problems the script can't fix automatically (an unknown
tag, too many tags on one line, a proper noun missing from the
pronunciation glossary), it prints warnings and refuses to write. Fix
the draft and re-run.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------------
# These constants stay in sync with dialogue/STYLE.md and
# dialogue/PRONUNCIATION.md by convention. If you change those files, update
# this list — there is no automatic sync.

# The full set of approved tags from STYLE.md §2. Any [tag] in a script
# must appear in this set, otherwise the model produces broken audio.
APPROVED_TAGS: set[str] = {
    # Emotional states
    "happy", "sad", "angry", "excited", "nervous", "frustrated", "surprised",
    "fearful", "calm", "curious", "appalled", "resigned", "wistful",
    "sorrowful", "mischievous", "determined", "awe",
    # Delivery style
    "whispering", "shouting", "quietly", "loudly", "slowly", "fast", "rushed",
    "softly", "muttering", "stuttering", "conversational tone", "dramatic tone",
    "reflective", "serious tone", "matter-of-fact", "lighthearted",
    "sarcastic tone", "deadpan", "authoritative", "dismissive", "flirty",
    "condescending",
    # Physical states
    "out of breath", "yawning", "shivering", "muffled", "tired", "hollow voice",
    # Human reactions
    "laughs", "sighs", "gasp", "gulps", "crying", "clears throat", "pauses",
    "hesitates", "light chuckle", "giggle",
    # Archetypes & accents
    "heroic tone", "villainous", "childlike", "old man voice", "British accent",
    "Southern accent",
}

# Words that, if they appear inside a parenthetical, mean "the line pauses
# here." We map all of them to the [pauses] tag.
PAUSE_KEYWORDS: set[str] = {
    "beat", "pause", "after a moment", "long pause", "silence", "moment",
}

# Honorifics to strip from speaker headers so "DAME CALLA" becomes "CALLA",
# matching STYLE.md §1 ("first name only, ALL CAPS, no titles").
HONORIFICS: set[str] = {
    "DAME", "SIR", "SER", "LORD", "LADY", "QUEEN", "KING", "PRINCE",
    "PRINCESS", "DESPOT", "MASTER", "MISTRESS", "DOCTOR", "DR",
}

# Words we drop entirely from a speaker header — annotations like "(cont.)"
# that mean "the same speaker is continuing".
SPEAKER_ANNOTATIONS: set[str] = {"CONT", "CONT.", "(CONT.)"}

# Project paths. We assume the script is run from the repo root.
REPO_ROOT = Path(__file__).resolve().parent.parent
DRAFTS_DIR = REPO_ROOT / "dialogue" / "drafts"
SCRIPTS_DIR = REPO_ROOT / "dialogue" / "scripts"
PRONUNCIATION_FILE = REPO_ROOT / "dialogue" / "PRONUNCIATION.md"


# ---------------------------------------------------------------------------
# PRONUNCIATION GLOSSARY
# ---------------------------------------------------------------------------
def load_pronunciation_map() -> dict[str, str]:
    """
    Parse dialogue/PRONUNCIATION.md and return a dict mapping
    canonical spelling → TTS spelling. We skip rows where the two are
    identical (PRONUNCIATION.md uses those rows as "lands clean — no
    respelling needed" markers).
    """
    if not PRONUNCIATION_FILE.exists():
        return {}

    mapping: dict[str, str] = {}
    for line in PRONUNCIATION_FILE.read_text(encoding="utf-8").splitlines():
        # Glossary rows are markdown table rows: | Canonical | TTS spelling | Notes |
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < 2:
            continue
        canonical, tts = cells[0], cells[1]
        # Skip header rows and separator rows.
        if canonical in {"Canonical", "---"} or canonical.startswith("---"):
            continue
        if not canonical or not tts:
            continue
        # Skip "lands clean" rows (canonical == TTS spelling).
        if canonical == tts:
            continue
        mapping[canonical] = tts
    return mapping


# ---------------------------------------------------------------------------
# DRAFT PARSING
# ---------------------------------------------------------------------------
# Regex bestiary, with comments because regexes are inherently terrible to
# read. Each one is anchored to a specific shape that appears in our drafts.

# A speaker header in a draft: "**TOMLIN**" or "**ROLAND** *(cont.)*".
# We match the bolded all-caps name and ignore anything italicized after.
SPEAKER_HEADER = re.compile(r"^\*\*([A-Z][A-Z \.()]*)\*\*\s*(.*)$")

# An italicized parenthetical on its own line: "*(quietly)*" or
# "*(she looks at the document without picking it up.)*".
ITALIC_PAREN_LINE = re.compile(r"^\*\((.+)\)\*\s*$")

# An inline italicized parenthetical inside a prose line:
# "*(beat)*" appearing between sentences. Same shape, different position.
INLINE_ITALIC_PAREN = re.compile(r"\*\(([^)]+)\)\*")

# A plain (non-italic) parenthetical on its own line:
# "(Tomlin doesn't answer. He is very still.)" — these are stage directions
# we drop entirely.
PLAIN_PAREN_LINE = re.compile(r"^\(.+\)\s*$")


def normalize_speaker(raw: str) -> str:
    """
    Turn a draft speaker header like "DAME CALLA" or "ROLAND" or
    "ROLAND (CONT.)" into the canonical form per STYLE.md §1: the
    speaker's first non-honorific name, ALL CAPS, no annotations.
    """
    # Drop annotations like "(CONT.)" that some drafts include in the
    # bold speaker line itself.
    words = [w for w in raw.replace("(", " ").replace(")", " ").split()
             if w.upper() not in SPEAKER_ANNOTATIONS]

    # Drop honorifics until we hit the actual name.
    while words and words[0].upper() in HONORIFICS:
        words.pop(0)

    if not words:
        return ""

    # First name only. STYLE.md §1: no surnames either.
    return words[0].upper().rstrip(".")


def parenthetical_to_tag(content: str) -> str | None:
    """
    Decide what to do with the contents of a parenthetical. Returns:
      - a "[tag]" string if the content maps to an approved tag,
      - None if the parenthetical has no auditory signature and should be dropped.

    The rule is conservative on purpose: only match clean cases. Anything
    that looks like a physical action ("she looks at the document",
    "produces a folded document") gets dropped, which is what STYLE.md
    §3 requires.
    """
    text = content.strip().lower()

    # Strip leading qualifiers like "very", "still", "after a", which
    # often precede a real tag word.
    leading_qualifiers = ("very ", "still ", "again ", "now ", "then ")
    for q in leading_qualifiers:
        if text.startswith(q):
            text = text[len(q):]

    # Pause-family parentheticals → [pauses].
    if any(kw in text for kw in PAUSE_KEYWORDS):
        return "[pauses]"

    # Direct match on an approved tag word or short phrase.
    if text in APPROVED_TAGS:
        return f"[{text}]"

    # Single-word parentheticals that aren't approved tags but might be
    # close synonyms. We don't auto-substitute (the writer should pick a
    # tag from the allowlist deliberately) — we drop and warn. This is
    # the "tag the deviation, not the baseline" rule from STYLE.md §7.1.
    if " " not in text and text.isalpha():
        return None

    # Multi-word parenthetical describing physical action — drop silently.
    return None


# ---------------------------------------------------------------------------
# CORE TRANSFORM
# ---------------------------------------------------------------------------
class StripWarning(Exception):
    """Raised when the script should refuse to emit a file. Caller prints
    the message and exits non-zero."""


def find_script_section(draft_lines: list[str]) -> tuple[int, int]:
    """
    Return (start_index, end_index) bounding the "## Script (Prose)" section
    of the draft. Everything outside this range is metadata we ignore.
    """
    start = end = -1
    for i, line in enumerate(draft_lines):
        if line.strip().startswith("## Script"):
            start = i + 1
        elif start != -1 and line.strip().startswith("## "):
            end = i
            break
    if start == -1:
        raise StripWarning(
            "No '## Script (Prose)' section found in draft. The stripper "
            "expects drafts to follow the layout in dialogue/drafts/README.md."
        )
    if end == -1:
        end = len(draft_lines)
    return start, end


def strip_draft(draft_path: Path, pronunciation: dict[str, str]) -> tuple[str, list[str]]:
    """
    The main transform. Returns (script_text, warnings). If warnings is
    non-empty, the caller should print them and refuse to write the script
    unless the user passed --force.
    """
    warnings: list[str] = []
    draft_lines = draft_path.read_text(encoding="utf-8").splitlines()
    start, end = find_script_section(draft_lines)

    # Walk the script section, accumulating utterances per speaker.
    # Each utterance is a (speaker, list_of_text_chunks) tuple.
    utterances: list[tuple[str, list[str]]] = []
    current_speaker: str | None = None
    current_chunks: list[str] = []
    pending_tag: str | None = None  # set by a parenthetical line

    def flush() -> None:
        if current_speaker and current_chunks:
            utterances.append((current_speaker, list(current_chunks)))
        current_chunks.clear()

    for raw_line in draft_lines[start:end]:
        line = raw_line.rstrip()

        # Blank line — within a speaker block, this signals a new
        # utterance (the writer's paragraph break is a beat). Flush
        # accumulated chunks and keep the same speaker for the next
        # paragraph. pending_tag is preserved across the gap so a
        # tag-only line followed by a paragraph break still lands.
        if not line:
            if current_chunks:
                utterances.append((current_speaker or "", list(current_chunks)))
                current_chunks.clear()
            continue

        # Markdown horizontal rules separate sections inside the script
        # block (e.g. between scene movements). Skip them.
        if line.lstrip().rstrip("- \t") == "":
            continue

        # Speaker header: "**TOMLIN**" / "**ROLAND** *(cont.)*".
        m = SPEAKER_HEADER.match(line)
        if m:
            flush()
            current_speaker = normalize_speaker(m.group(1))
            # A pending mid-utterance tag from the prior speaker is dropped
            # — it was end-of-utterance stage business, not delivery.
            pending_tag = None
            continue

        # Italicized parenthetical alone on a line: either a tag candidate
        # ("*(quietly)*") or a stage direction ("*(she sets it down.)*").
        # We always queue it as pending_tag. If the SAME speaker continues
        # with prose, the tag attaches to that prose. If a speaker change
        # happens first, the tag is dropped (between-utterance silence).
        m = ITALIC_PAREN_LINE.match(line)
        if m:
            tag = parenthetical_to_tag(m.group(1))
            if tag:
                pending_tag = tag if not pending_tag else pending_tag + " " + tag
            continue

        # Plain (non-italic) parenthetical alone — always stage direction.
        if PLAIN_PAREN_LINE.match(line):
            continue

        # Anything else is prose. Process inline parentheticals, strip
        # markdown emphasis, normalize em-dashes, prepend any pending tag.
        prose = process_inline(line, pending_tag)
        if prose:
            current_chunks.append(prose)
            pending_tag = None

    flush()

    # Now serialize utterances into the final script form.
    # STYLE.md §1: "SPEAKER: text" with one utterance per blank-separated block.
    output_blocks: list[str] = []
    for speaker, chunks in utterances:
        text = " ".join(chunks)
        text = collapse_whitespace(text)
        text = apply_pronunciation(text, pronunciation, warnings)
        text = normalize_punctuation(text)
        if not text.strip():
            continue
        validate_tags(speaker, text, warnings)
        output_blocks.append(f"{speaker}: {text}")

    script_text = "\n\n".join(output_blocks) + "\n"
    return script_text, warnings


def process_inline(line: str, leading_tag: str | None) -> str:
    """
    Process a prose line:
      1. Convert inline italicized parentheticals to tags or drop them.
      2. Strip markdown emphasis around words (e.g. *Territorial Surveys*).
      3. Convert em-dashes: end-of-line → "--" (cut-off), mid-line → "...".
      4. Prepend any leading_tag from a previous tag-only line.
    """
    def replace_paren(match: re.Match[str]) -> str:
        tag = parenthetical_to_tag(match.group(1))
        return tag if tag else ""

    text = INLINE_ITALIC_PAREN.sub(replace_paren, line)

    # Strip markdown emphasis: "*Territorial Surveys*" → "Territorial Surveys",
    # "**bold**" → "bold". Only single-word-or-phrase emphasis; do not touch
    # asterisks that mark scene breaks (those are caught by the horizontal
    # rule check upstream).
    text = re.sub(r"\*\*([^*]+)\*\*", r"\1", text)
    text = re.sub(r"(?<!\*)\*([^*\n]+)\*(?!\*)", r"\1", text)

    # Em-dash handling. STYLE.md §1: "..." for pauses, "--" for cut-offs.
    # Heuristic: if an em-dash sits at end of the raw line (often signaling
    # the speaker is interrupted by the next speaker), emit "--". Otherwise
    # it's a mid-thought pause → "...".
    text = text.rstrip()
    if text.endswith("—"):
        text = text[:-1].rstrip() + "--"
    text = re.sub(r"\s*—\s*", "... ", text)

    text = text.strip()

    if leading_tag and text:
        text = f"{leading_tag} {text}"
    return text


def collapse_whitespace(text: str) -> str:
    """Collapse runs of whitespace to single spaces, except inside tags."""
    # Protect tag content from whitespace normalization.
    return re.sub(r"\s+", " ", text).strip()


def normalize_punctuation(text: str) -> str:
    """
    Final punctuation tidy-up after chunks are joined. Em-dashes were
    already handled per-line in process_inline (where end-of-line vs
    mid-line position matters). Here we just clean up double spaces and
    accidental "... ." sequences.
    """
    text = re.sub(r"\.\.\.\s*\.", "...", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def apply_pronunciation(text: str, pronunciation: dict[str, str],
                        warnings: list[str]) -> str:
    """
    Substitute every canonical proper noun with its TTS respelling, per
    PRONUNCIATION.md. We use whole-word boundaries so partial matches
    don't fire.
    """
    for canonical, tts in pronunciation.items():
        # Word boundaries don't handle non-ASCII characters reliably in
        # Python's re, so we use a permissive boundary: not preceded or
        # followed by another letter.
        pattern = re.compile(
            r"(?<![A-Za-zÀ-ÿ])" + re.escape(canonical) + r"(?![A-Za-zÀ-ÿ])"
        )
        text = pattern.sub(tts, text)
    return text


def validate_tags(speaker: str, text: str, warnings: list[str]) -> None:
    """
    Find every [tag] in the line and check it against APPROVED_TAGS.
    Also enforce the "max two tags per line" rule from STYLE.md §7.1.
    """
    tags_found = re.findall(r"\[([^\]]+)\]", text)
    if len(tags_found) > 2:
        warnings.append(
            f"{speaker}: line has {len(tags_found)} tags (max 2 per line). "
            f"Trim during the writer review pass: {text!r}"
        )
    for tag in tags_found:
        if tag not in APPROVED_TAGS:
            warnings.append(
                f"{speaker}: unknown tag [{tag}] (not in STYLE.md §2 allowlist). "
                f"Either pick an approved tag or extend the allowlist deliberately."
            )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def script_path_for(draft_path: Path) -> Path:
    """
    Map a draft path to its corresponding TTS script path. Per
    dialogue/drafts/README.md, names match exactly except for the extension.
    """
    return SCRIPTS_DIR / (draft_path.stem + ".txt")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Strip a dialogue draft (.md) into a TTS script (.txt). "
                    "See design/TTS_PIPELINE.md §4 for the transform spec."
    )
    parser.add_argument(
        "draft", nargs="?", type=Path,
        help="Path to a draft .md file. Omit with --all to process every draft."
    )
    parser.add_argument(
        "--all", action="store_true",
        help="Strip every .md in dialogue/drafts/ (skips README.md)."
    )
    parser.add_argument(
        "--check", action="store_true",
        help="Do not write. Print the stripped script to stdout and "
             "diff against the existing scripts/*.txt if it exists."
    )
    parser.add_argument(
        "--force", action="store_true",
        help="Write the script even if warnings were produced."
    )
    args = parser.parse_args()

    pronunciation = load_pronunciation_map()

    if args.all:
        drafts = sorted(p for p in DRAFTS_DIR.glob("*.md") if p.name != "README.md")
    elif args.draft:
        drafts = [args.draft]
    else:
        parser.print_help()
        return 2

    exit_code = 0
    for draft in drafts:
        try:
            script_text, warnings = strip_draft(draft, pronunciation)
        except StripWarning as e:
            print(f"[FAIL] {draft}: {e}", file=sys.stderr)
            exit_code = 1
            continue

        if warnings:
            print(f"[WARN] {draft} produced {len(warnings)} warnings:",
                  file=sys.stderr)
            for w in warnings:
                print(f"  - {w}", file=sys.stderr)

        if args.check:
            print(f"--- {draft.name} ---")
            print(script_text)
            existing = script_path_for(draft)
            if existing.exists():
                diff = simple_diff(existing.read_text(encoding="utf-8"), script_text)
                if diff:
                    print(f"--- diff vs {existing.name} ---")
                    print(diff)
            continue

        if warnings and not args.force:
            print(f"[SKIP] {draft}: refusing to write due to warnings. "
                  f"Re-run with --force to override.", file=sys.stderr)
            exit_code = 1
            continue

        out = script_path_for(draft)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(script_text, encoding="utf-8")
        print(f"[OK]   {draft.name} -> {out.relative_to(REPO_ROOT)}")

    return exit_code


def simple_diff(a: str, b: str) -> str:
    """
    Tiny line-by-line diff for --check mode. Not a real diff; just shows
    which lines differ. Good enough to spot whether the stripper output
    matches an existing hand-stripped script.
    """
    a_lines = a.splitlines()
    b_lines = b.splitlines()
    out: list[str] = []
    for i, (la, lb) in enumerate(zip(a_lines, b_lines)):
        if la != lb:
            out.append(f"L{i+1}- {la}")
            out.append(f"L{i+1}+ {lb}")
    if len(a_lines) != len(b_lines):
        out.append(f"(line counts differ: existing={len(a_lines)}, "
                   f"stripped={len(b_lines)})")
    return "\n".join(out)


if __name__ == "__main__":
    sys.exit(main())
