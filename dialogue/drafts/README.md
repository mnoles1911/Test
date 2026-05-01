# Dialogue Drafts

This directory holds the **prose drafts** of dialogue scenes — the design source-of-truth.

A draft includes:
- Character voice notes specific to the scene (if voice deviates from baseline in `CHARACTER_VOICES.md`)
- Stage directions, blocking, scene atmosphere
- Subtext and emotional intent in italics or parentheticals
- Any line-by-line designer commentary

A draft is **not** suitable for TTS. Generate the matching `scripts/*.txt` from it (per `STYLE.md` § 7.10), and revise the draft first if the scene needs to change. Never edit the script for narrative reasons.

## Naming

Match the script filename, but with `.md` extension:

```
drafts/act1_scene_sorting_room.md  ↔  scripts/act1_scene_sorting_room.txt
drafts/act1_scene_forty_minutes.md ↔  scripts/act1_scene_forty_minutes.txt
```

## When to draft

Draft for: cut scenes, major story beats, character introductions, scenes with strong subtext.

Skip drafts for: combat barks, ambient overhears, simple branching responses. For those, write straight to `scripts/` — the prose layer adds no value when the line is one beat long.