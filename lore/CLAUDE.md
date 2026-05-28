# lore/CLAUDE.md

Narrative canon for Mira-Thal (third age). **`INDEX.md` is the designer-facing directory map** — read it first; this file is the Claude-Code-facing pointer.

## Rules

- **Lore wins when lore vs design conflict.**
- **Check `INDEX.md` before adding a new file** to avoid duplication / orphans.
- Names + proper nouns added to lore MUST also land in `../dialogue/PRONUNCIATION.md` if they'll be voiced.

## Quick map

| Topic | Start with |
|---|---|
| World atlas + geography | `WORLD.md`, `WORLD_GEOGRAPHY.md`, `MAP_GENERATION_GUIDE.md` |
| Roland's story | `BACKSTORY_ROLAND.md`, `GAME1_PART1.md`, `GAME1_PART2.md` |
| Other characters | `CHARACTERS_COMPANIONS.md`, `CHARACTERS_NPCS.md`, `BACKSTORY_*.md` (per character) |
| Peoples + cultures | `PEOPLES.md` |
| Factions + guilds | `GUILDS_*.md` |
| Timeline + past events | `HISTORY_*.md` |
| Side content | `SIDE_QUESTS_GAME1.md`, `SIDE_QUESTS_GAME2.md` |
| Per-act level layouts | `LEVEL_LAYOUTS_ACT*.md` |
| Individual locations (25+ entries) | `locations/` subdir |
| Copper Isles specifics | `copper_isles/` subdir |
| Quick alphabetical reference | `REFERENCE.md` |

## Maintenance

- New location → `locations/` + update `WORLD_GEOGRAPHY.md` + `MAP_GENERATION_GUIDE.md` + `INDEX.md`.
- New character → backstory file + appropriate `CHARACTERS_*.md` index + `REFERENCE.md` cross-ref.
- New faction → `GUILDS_*.md` if guild-shaped, else `PEOPLES.md` or a new dedicated file (see INDEX first).
- New voiced character → add to `../dialogue/CHARACTER_VOICES.md` + `../dialogue/PRONUNCIATION.md` for any new proper nouns.

## When lore changes affect code

- A new faction → may need `design/FACTION_SYSTEM.md` updates + `FactionManager` data.
- A new location with NoEditZone rules → mention in `design/3D_VOXEL_MIGRATION.md`.
- New voiced character → `design/TTS_PIPELINE.md` voice ID assignment.
