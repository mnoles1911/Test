# addons/CLAUDE.md

Third-party Godot addons. **Do NOT edit anything in here directly** — manage via the Godot Asset Library / upstream releases.

## What's in here

- **`dialogic/`** — Dialogic 2 plugin. Powers all in-game dialogue (timelines in `../dialogue/*.dtl`, character definitions in `../dialogue/CHARACTER_VOICES.md`).

## Why we don't edit

- Local edits get overwritten on the next plugin update from the Asset Library.
- Local edits make upstream bug reports impossible to act on.
- Project-specific behavior belongs in `../scripts/` (signals into Dialogic, wrappers, etc.), not as fork-style edits inside the plugin.

## Updating

1. Backup-mention the version (Dialogic 2.x) in a commit message.
2. Use Godot's AssetLib panel to update.
3. Run `World3D.tscn` + `scenes/_dev/CombatTest.tscn` + an NPC dialogue trigger to smoke-test.
4. If anything breaks, check `../design/DIALOGIC_SETUP.md` for the expected wiring.

## How code interacts with Dialogic

- Always guard `Dialogic.start(...)` calls behind `if get_node_or_null("/root/Dialogic"):` so dev scenes that don't load the autoload don't crash.
- Speech checks dispatch via Dialogic Signal events `speech_check:DC:success:fail` → handled by `SpeechCheckBroker` autoload.
- See `../dialogue/CLAUDE.md` for the authoring flow (drafts → scripts → .dtl).
