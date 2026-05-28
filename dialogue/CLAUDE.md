# dialogue/CLAUDE.md

Dialogic 2 timelines + writing references.

## Layout

| File / dir | Purpose |
|---|---|
| `*.dtl` | Dialogic timeline files — one per conversation or quest beat |
| `drafts/` | Pre-Dialogic draft scripts (plain prose / screenplay-format) |
| `scripts/` | Authored dialogue script files (text source-of-truth before they become `.dtl`) |
| `scripts/barks/` | Bark variant pools (one-line ambient barks per NPC × trigger) |
| `CHARACTER_VOICES.md` | Voice acting reference — tone, register, regional inflection per character |
| `PRONUNCIATION.md` | IPA-style guide for proper nouns (place names, character names, factions) |
| `STYLE.md` | Project-wide style + voice conventions |

## Rules

- **New voiced character** → add an entry to `CHARACTER_VOICES.md` + voice ID to `../design/TTS_PIPELINE.md`.
- **New proper noun** (place, character, faction, item, spell) → add to `PRONUNCIATION.md` so TTS pronounces it correctly.
- **Dialogic timelines** must use the autoload check before invocation:
  ```gdscript
  if get_node_or_null("/root/Dialogic"):
      Dialogic.start("timeline_name")
  ```
- **Speech checks** are dispatched via Dialogic Signal events `speech_check:DC:success:fail` and handled by `SpeechCheckBroker` (autoload). KCD2-style visible-but-greyed-when-failing modal.
- **Disposition / faction** propagate into Dialogic via `GameState` flags set by `NPC._start_dialogue` — `active_npc`, `active_npc_disposition`, `active_npc_faction`. Use these in timeline conditions.

## Wiring

- `NPC.gd` triggers dialogue when player is in `InteractArea` + presses E.
- `BarkManager` fires barks from `scripts/barks/*` via `BarkManager.fire(npc_id, trigger_id, world_pos)`.
- Player choice → Dialogic signal → `SpeechCheckBroker` → result feeds back into `SkillManager.dispatch("on_speech_check", {...})`.

## Authoring flow

1. Draft prose in `drafts/`.
2. Convert to authored script in `scripts/` (decision points marked).
3. Convert to Dialogic timeline (`.dtl`) — usually drag into Dialogic editor.
4. Assign to the relevant `NPCData` resource's `dialogue_timeline` field (or to a `NPCScheduleEntry.dialogue_override`).
5. If voiced → `tools/render_voice.py` + update `design/TTS_PIPELINE.md`.

## When dialogue + design conflict

- **Lore wins** for canon (what the character would say / has lived through).
- **Design wins** for mechanical wiring (what skill check + DC + reward fires).
- When in doubt, write the line that makes the scene work and flag the design mismatch in `DESIGNER_TODO.md`.
