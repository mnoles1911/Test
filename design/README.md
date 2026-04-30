# Design Directory — Mira-Thal: Game One

## What this directory is

Game implementation reference. How the world's lore translates into Godot 4 systems, mechanics, and visual production.

**This is not where the world lives.** The world lives in `/lore`.

---

## The split

```
/lore/    →  Canonical narrative. Story, characters, geography, history.
              The source of truth for "what's true in Mira-Thal."
              Start here: /lore/INDEX.md

/design/  →  Game implementation. Combat systems, dialogue mechanics,
              save architecture, art direction, scene structure.
              The source of truth for "how we build it in Godot."
```

When the two conflict, lore wins. Design adapts.

---

## Files in this directory

### `MILESTONE_ROADMAP.md`
Phases 4–7 of development: what to build, in what order, and why. Each phase has a
goal, deliverables list, and key decisions to make before building. Reference this
when planning the next chunk of work. Phases 1–3 are complete and documented in
`CLAUDE.md` → Milestone history.

### `SYSTEMS_DESIGN.md`
How combat, dialogue, exploration, faction tracking, and save systems work mechanically. Reference this when implementing any game system. Aligned with the lore's companion roster, faction map, and quest structure.

### `ART_DIRECTION.md`
Palette rules, pixel resolution, location visual identity, character design briefs, animation priority list, and Godot lighting/shader implementation notes. Reference this when building any scene or asset.

### `CAMERA_AND_PERSPECTIVE.md`
Why the "3/4 isometric" look is a pixel art style, not a Godot camera transform. Read this before touching Camera2D.

### `DIALOGIC_SETUP.md`
Step-by-step Dialogic 2 installation and character setup. Troubleshooting table. Read this before touching dialogue.

### `LESSONS_LEARNED.md`
Running log of bugs encountered and fixes confirmed. Concise table format. Updated whenever a fix is confirmed in production.

---

## What used to be here

Earlier versions of this directory contained `WORLD_OVERVIEW.md`, `CHARACTER_BIBLE.md`, and `GAME_ONE_QUESTS.md`. These have been deleted because the `/lore` directory now contains far more thorough, canonical versions of the same content. Maintaining two copies would guarantee drift.

If you find yourself wanting to look something up about the world, characters, or plot — go to `/lore`, not here.

---

## How design and lore stay in sync

When lore changes (a character's surname is corrected, a location moves, a quest path is revised):

1. The change is made in the relevant `/lore` file
2. `lore/INDEX.md` is updated if scope changed
3. Implementation docs in `/design` are reviewed for stale references
4. `CLAUDE.md` (project root) is updated if the change affects canonical naming or current milestone

The reverse is rare but happens: when implementation reveals that a design assumption does not fit the lore, the lore is the authority and the design adapts.

---

## CLAUDE.md (project root)

The root-level `CLAUDE.md` points Claude Code at both `/lore` and `/design`, locks in canonical naming, and tracks current milestone state. Update it when:

- A new lore file is added or renamed
- A milestone is completed
- A new canonical naming contradiction is discovered

That file is the orientation document Claude Code reads at the start of every session. Keep it accurate and it does most of the heavy lifting in keeping the project coherent across years of work.
