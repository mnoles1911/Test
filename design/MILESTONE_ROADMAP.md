# Milestone Roadmap — Game One Development

Phases 1–3 are complete. This document covers the planned next four phases of development,
their goals, and build order rationale.

> For completed milestone details, see `CLAUDE.md` → Milestone history.
> For system design specifications, see `SYSTEMS_DESIGN.md`.
> For art direction and asset specs, see `ART_DIRECTION.md`.
> For level-by-level scene specs, see `lore/LEVEL_LAYOUTS_ACT*.md`.

---

## Phase 4 — Scene Infrastructure & Aldenholt Act I

**Goal:** The first real playable sequence, end-to-end. Act I of Game One becomes playable
from the night chase through Aldenholt to Roland acquiring the pommel.

**Why now:** Everything else builds on scene transitions. You cannot have a game without them.
Building Act I also produces a working template — zone structure, connected rooms, flag
setting — that every subsequent zone reuses.

### Deliverables

- **`scripts/TransitionManager.gd`** — Autoload singleton. Fade-to-black on scene change,
  player spawn position preserved via `GameState.player_position`. Called by any trigger
  that changes zones.

- **Act I scenes** (Aldenholt, 5 scenes — see `lore/LEVEL_LAYOUTS_ACT1.md` for full spec):
  1. `scenes/act1/NightChase.tscn` — Opening linear chase through alleyways to the Archive
  2. `scenes/act1/Archive.tscn` — Interior: entrance hall + restricted section + Tomlin
  3. `scenes/act1/HenriettaQuarters.tscn` — Searched room, environmental storytelling
  4. `scenes/act1/IronChaliceChapel.tscn` — Dark chapel, the pommel, Dame Calla
  5. `scenes/act1/AldenHolt_Hub.tscn` — The street between locations (re-entrant hub)

- **`GameState.gd` first real flags:**
  - `henrietta_dead: bool`
  - `pommel_piece_1_acquired: bool`
  - `aldric_vane_name_logged: bool`
  - `tomlin_helped: bool`

- **Roland's journal** — Basic UI panel showing active notes. Not a full system yet.
  Populated from GameState flags. Written in Roland's voice.

- **First branching Dialogic dialogue** — Tomlin. Requires `henrietta_dead == true` to
  unlock the key persuasion option. Establishes the pattern for all future flag-gated dialogue.

### Key decisions to make before building
- Journal: panel overlay (pause-style) or a dedicated journal scene?
- Alleyway chase: implied threat (no pursuer entity) or a visible enemy that triggers
  game-over if it catches the player?
- Hub structure: one Aldenholt street scene the player walks between, or individual
  room-to-room transitions for each location?

---

## Phase 5 — Sprite & Tile Art Pipeline

**Goal:** Establish a repeatable pixel art production workflow. Replace placeholder geometry
with real sprites in at least one complete scene. Prove the technical pipeline before
expanding it to all zones.

**Why now:** The mechanics are proven. Building 8 more zones on colored rectangles makes
all testing artificial. Real sprites also make lighting behave correctly — normal maps
on stone walls are what produce the campfire-knight visual quality from `ART_DIRECTION.md`.

### Deliverables

- **Aseprite** as the official sprite tool (see `ART_DIRECTION.md` for specs)

- **Roland walk cycle** — 8 directions, 32×48 pixels native. The single most-used asset
  in the game. Every hour spent on this pays off across every scene.

- **Roland idle animation** — Weight shift, one hand near belt. Per `ART_DIRECTION.md`.

- **Cave/dungeon tile set (16×16)** — Just the tiles needed for the Aldenholt night-chase
  and Archive scenes:
  - Cobblestone floor (2-3 variants)
  - Stone wall (interior and exterior face)
  - Torch sconce (animated, warm light)
  - Heavy iron door (open/closed states)
  - Archive shelving / stacks

- **Campfire prop sprite** — Replacing the orange Polygon2D placeholder. Animated: 4-frame
  flicker cycle.

- **Normal map workflow** — Export sprite + normal map from Aseprite. Assign normal map
  to Sprite2D in Godot alongside main texture. Verify campfire PointLight2D rakes across
  stone texture. This is what creates depth in the lighting.

- **Portrait: Roland** — 64×80 pixels native. Used by Dialogic for dialogue panels.

### Priority order within the phase
1. Roland walk cycle (unblocks all scene testing)
2. Cave tile set (unblocks Act I scene building)
3. Campfire sprite (small, high-visual-payoff)
4. Normal maps on tile set (lighting depth)
5. Roland portrait (unblocks dialogue)

---

## Phase 6 — Combat Depth & Enemy Framework

**Goal:** Upgrade the combat prototype (Milestone 3) into a real system. Roland's full
move set. A reusable enemy template. The Ashfallen soldier as the first real enemy type.

**Why now:** Act I has at least one combat encounter. Any scene beyond the opening chase
will need real combat. The prototype proved the timing mechanic — now expand it into a
framework that can hold multiple enemy types and Roland's three core abilities.

### Deliverables

- **Roland's full combat move set:**
  - Attack (timing bar — already built in prototype)
  - Block (timing window — already built)
  - Analyze — unique to Roland. Reveals an enemy's weakness pattern. No timing window:
    a single-turn observation that makes subsequent attacks more effective. Information
    as combat resource, consistent with the design philosophy.

- **Enemy data structure** — A reusable dictionary or resource that defines:
  - HP, attack damage, block window timing
  - Telegraph phrase (what prints before the enemy attacks)
  - Weak point (revealed by Analyze)
  - Whether enemy hesitates when player has relevant companion (Dagna's seismic analysis,
    Orion's tactical reading)

- **Ashfallen soldier** — First real enemy using the template. Per `SYSTEMS_DESIGN.md`:
  fights with familiar tactics, slight hesitation mechanic (recognition pressure).

- **Item menu** — Currently locked/placeholder in prototype. Decide: leave locked for now,
  or stub one consumable (healing herb from the Aldenholt market).

### Decision before building
- Multi-party combat or Roland-only for Act I? Companions join mid-game. Act I is
  Roland alone. Build the system for one party member first, design it to expand.

---

## Phase 7 — Dialogue System Depth (Information as Currency)

**Goal:** The game's core design distinction: dialogue options that unlock based on what
Roland knows. First real implementation of the "listening mechanic" and flag-gated paths.

**Why now:** Acts I and II are almost entirely driven by dialogue and investigation. Combat
is secondary. The Tomlin scene (Phase 4) is a first step — Phase 7 makes this the game's
primary mode of play.

### Deliverables

- **Dialogic condition nodes wired to GameState flags** — Any flag set in any scene
  can gate dialogue options in any subsequent scene. Established pattern for the whole game.

- **Companion comment framework** — Brief portrait + 1-2 line interjection during NPC
  dialogue. Each companion observes through their lens (per `SYSTEMS_DESIGN.md`):
  - Dagna: structural details, old construction
  - Orion: exits, signs of recent traffic
  (Roland-only for Phase 7 since companions join in Act II+)

- **Roland's journal as playable UI** — Full panel, not just a flag dump:
  - Active quests (current state, last known information)
  - People (brief notes on everyone met, updates as Roland learns more)
  - The Crown (piece locations known, acquired)
  - Written in Roland's voice — partial, sometimes wrong

- **First full branching scene** — Tomlin (Act I) fully implemented with all branches:
  - `henrietta_dead = false`: limited options, cannot convince him
  - `henrietta_dead = true`: key branch available — "the only way to find who killed her
    is to know what she was researching"
  - If player has already spoken to Tomlin once and left: his dialogue acknowledges the
    return, not a fresh conversation

- **The listening mechanic prototype** — One scene (Yaromir, Act II Vosskara) where
  the best outcome is gated behind NOT pressing the negotiation option on first meeting.
  See `SYSTEMS_DESIGN.md` for the design specification.

---

## Sequence Summary

| Phase | Focus | Depends on |
|---|---|---|
| 4 | Scene transitions, Act I scenes, first flags | Milestones 1–3 |
| 5 | Art pipeline, Roland sprites, cave tile set | Phase 4 (scenes exist to put sprites into) |
| 6 | Combat depth, enemy template, Ashfallen | Milestone 3 prototype |
| 7 | Branching dialogue, journal UI, listening mechanic | Phase 4 (flags exist to condition on) |

Phases 5 and 6 can run in parallel if an artist is working on sprites while code work
continues. Phases 4 and 7 are sequential — flags must exist before they can be conditioned on.

---

## What Comes After Phase 7

Phase 8 onward: Act II zone construction, real companion join moments (Orion at Caer
Brannoch, Dagna in the Underway), multi-party combat. Each act will have its own phase.
The infrastructure built in Phases 4–7 is the foundation for everything.
