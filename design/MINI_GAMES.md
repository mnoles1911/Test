# Mini-Games Design

Skill-based activities that exist inside the world as real things Roland participates in — not detours into a separate UI dimension.

> Cross-reference: `design/LOCKPICKING.md` — lockpicking is a mini-game and documented there in full.
> `design/CRAFTING.md` — smithing forge phase lives here.
> `design/SKILLS_AND_PROGRESSION.md` — which sub-skills feed into each activity.
> `design/ECONOMY_AND_VENDORS.md` — prize money, faction rep rewards, and gambling stakes.
> `design/INPUT_AND_CONTROLS.md` — no mini-game may introduce a control verb not in the master Input Map.

---

## Design Philosophy

**Mini-games are not mode switches.** Roland doesn't walk into a locked room and enter "fishing mode." The world continues around him. The weather blows. NPCs react. Time passes. A competition can be interrupted if a fight breaks out. A fish can be spooked by a thunderclap. The overlay is thin; the world is always present underneath.

**Reuse existing systems.** The strongest activities use verbs Roland already knows: hold to draw, release to throw, the endurance bar, weather wind, the voxel edit tool, the over-shoulder camera. A player who has learned the game is not asked to learn a foreign control scheme. A player who has improved Roland's skills should feel that advantage here.

**Skill determines forgiveness and ceiling, not permission.** Roland can attempt anything. His sub-skill level reduces wobble, expands timing windows, unlocks harder competition brackets, and reveals NPC tells — but never locks the door.

**Stakes make it matter.** Every activity has a reason to engage: coin, named items, faction reputation with the NPC or guild running the event, companion banter, or lore. A player who ignores all mini-games misses a texture of the world, not a progression requirement.

---

## Smithing — Forge Phase

> The planning and recipe layer is in `design/CRAFTING.md`. This covers the physical forge moment.

### What it looks like

Roland stands at the anvil, tongs in one hand. A hot voxel ingot sits on the face — glowing orange-white at first, cooling through red to dark grey as heat drains. The camera pulls to a tight over-the-shoulder framing, anvil filling the lower half of the screen.

### The loop

Four phases, each with a distinct verb:

| Phase | Verb | Mechanic |
|---|---|---|
| Rough shape | Hammer | Pendulum arc — strike at the peak for full force |
| Edge | Hammer (lighter strokes) | Narrower arc window, more passes required |
| Temper | Quench | Hold in the water barrel until a colour ring hits the right band (straw → blue → grey — pull at straw for hard edge, blue for flexible blade) |
| Polish | Grindstone | Hold speed steady inside a moving tolerance band |

A **heat gauge** runs throughout. Each hammer strike costs heat. Reheat at the forge between phases — but every reheat pass adds a subtle orange scale texture to the final item (visible on the model). A master smith reheats once; a hasty one four times.

### Visual feedback

The voxel ingot deforms between phases: blocky rectangle → rough blade silhouette → finished form. Quality of timing across all phases determines the item's condition tier at output. A perfect run produces one tier above Roland's current Smithing skill ceiling (matching the Crafting mastery intent option).

### Skill integration

Smithing sub-skill (under Crafting domain) widens arc windows, slows heat drain, and unlocks the temper colour band. A Novice Roland will overshoot arcs and pull from the quench too early. A Veteran's windows are twice as wide and the heat drain is slow enough to do two phases per heat.

---

## Fishing

### What it looks like

Roland stands at a river bank, dock, or sea cliff. Third-person camera shifts behind and slightly above — a relaxed framing that shows the water surface and the float. The water shader's sine-sum vertex displacement is live; the float bobs on real geometry.

### The loop

**Cast:** a simple power arc meter — tap quickly for short casts, hold for distance. Cast accuracy affects where the bait lands relative to visible fish shadow clusters in shallow water.

**Wait:** the float drifts gently. No time limit. Weather affects visibility: fog obscures fish shadows; rain makes the surface busy and harder to read. Rare night fish glow faintly through the water (a faint emissive shimmer under the mesh surface) before they strike.

**Strike:** when the float dips, a **tug-of-war bar** appears — fish pulling left, Roland pulling right. The player holds the button in short bursts; holding too long risks snapping the line (a tension spike indicator climbs when held too long). Different fish fight differently:

| Fish type | Fight pattern |
|---|---|
| River trout | Erratic — changes direction every 0.5–1 s |
| Eel | Slow, constant pull — line tension climbs steadily |
| Deep sea bass | Surges in intervals — calm then sudden hard pull |
| Copper Isles sea bream | Two-phase: fights hard, tires, then a final burst at the surface |

**Land:** when the bar reaches Roland's side, the fish leaps from the water as a small physics object (similar to VoxelDrop), lands in Roland's keep-net beside him.

### Stakes

Fish yield food items (meals via Crafting) and rare fish are unique alchemical ingredients. A large catch can be sold to the harbourmaster faction for coin and rep. Companion Orion refuses to bait his own hook and will comment if Roland is taking too long.

---

## Tavern Dice — "Bones"

### What it looks like

A low tavern table, two candles, a worn felt surface. Roland and an NPC sit across from each other. Five wooden dice (small RigidBody3Ds, natural pine texture) roll across the felt with real physics — they bounce, collide, settle. The camera drops to a table-level angle for the roll, then rises to an over-the-shoulder read for the hold phase.

### The loop

Push-your-luck with a betting layer.

1. Both players place a wager (coin) before play.
2. Roland rolls all five dice. He locks any he wants to keep.
3. Up to two re-rolls. Locked dice stay.
4. Both players reveal hands simultaneously. Best hand wins the pot.

**Hand ranking** (ascending): pair → two pair → three of a kind → straight → full house → four of a kind → five of a kind.

**The tell layer:** NPCs have observable bark reactions and idle animations that hint at hand quality — a successful merchant who drew well goes quiet and still; a drunk guard who's bluffing over-reaches for his cup. Reading these tells is not required to play, but a player with high Charisma unlocks a "Read" action during the hold phase that surfaces one bit of honest information about the opponent's best remaining die.

### Stakes and faction rep

Winning earns coin and a small disposition bonus with the NPC's affiliated faction. Losing has no penalty beyond coin. Roland has unique loss barks for each companion present. A named NPC (the tavern's house player) holds a weekly high-stakes game — winning it yields a unique item or a letter of introduction to a locked faction contact.

---

## Tavern Cards — "The Fold"

### What it looks like

A hand of five hand-drawn parchment cards dealt face-down, revealed one at a time. Card art is flat 2D ink illustration — no voxels — which reads clearly at arm's length on a candlelit table. Each suit maps to a faction:

| Suit | Faction | Art motif |
|---|---|---|
| Shield | Knights of the Realm | Heraldic crest |
| Coin | Merchant guilds | Balance scales |
| Crow | Shadow bands | Feather and wax seal |
| Root | Wildfolk / druids | Twisted oak branch |

### The loop

Five-card trick-taking, two players. Each round, one player leads a card. The other must follow suit if able; if not, any card. High card of the led suit takes the trick. Play five rounds; most tricks wins.

**The Fold bluff:** once per game each player may play one card face-down. The opponent sees "a card was played" but not which one. It resolves at trick end. Bluffing a high Crow card when you actually played a low Shield is a viable play; getting caught means your opponent reads you more easily next hand.

**Faction rep by trick:** winning a trick with a Crow card earns a small Shadow faction disposition gain regardless of Roland's standing with them — the guilds notice who wins at their game. Winning the match with an all-Shield hand impresses the Realm Knights if one is present at the table.

### Unlocking The Fold

The card game is not immediately available everywhere. Roland must learn the rules from an NPC in Act I (a brief dialogue event in the first major tavern). After that, any tavern NPC flagged as a card player will offer a game.

---

## Axe Throwing Competition

### What it looks like

A market square or festival ground. A row of three timber targets at 10 m, 20 m, and 30 m — each a thick wooden roundel on a post, scored rings burned into the face. The camera shifts to a slight zoom, similar to the combat lock-on framing. The crowd of voxel NPCs flanks the lane. A festival banner (MagicaVoxel prop) stretches overhead.

### The loop

Three rounds, one throw per round. Before each throw:

- A **breathing circle** expands and contracts (inhale/exhale cycle, ~2 s period).
- The player throws on button release — releasing at the circle's smallest point (exhale) lands a bullseye; releasing on expansion adds angular error.
- **Wind drift** (fed from WeatherManager's current wind vector) pushes the axe laterally. A wind indicator on the HUD shows direction and strength. Players must aim off-centre to compensate.

**Distance rounds** add a small fall-off arc — the axe drops slightly at 30 m. Nothing the player needs to calculate; the visual arc of the throw makes it readable.

**Trick round** (final bracket only): a target swings on a rope, 1 m pendulum arc. The breathing circle becomes the secondary challenge; timing both the swing and the breath simultaneously is the skill test.

### Skill integration

Roland's Melee sub-skill (Thrown Weapons node under Combat domain) reduces circle wobble. A Novice Roland has a circle that never fully closes; a Master's circle briefly hits zero wobble, giving a clean bullseye window every breath. Competition brackets are unlocked by winning lower ones — Novice / Journeyman / Master — so there's always a harder challenge available.

### Stakes

First place: a named axe (unique item, faction-flavoured). Second/third: coin. Factional rep with the guild or lord running the event. Companion Dagna competes in the same bracket if the player brings her along and will beat Roland if his skill is below hers.

---

## Archery Competition

### What it looks like

An open field or castle practice range. Roland uses his actual equipped bow — the same weapon, the same draw mechanic (hold to draw, release to fire), the same aim reticle. No separate control scheme. The competition adds structure and scoring on top of the tool Roland already knows.

### Formats

**Stationary bracket:** targets at 30 m, 60 m, and 90 m. Standard scoring rings. At 90 m the target sits at the edge of the terrain view distance — atmospheric fog softens it. Wind drift applies.

**Moving target bracket:** a straw dummy on a track, crossing the lane at walking pace, then jogging pace in later rounds. Leads the target, same as hunting.

**Bird bracket:** clay birds (MagicaVoxel props) launched from a catapult at angles — low crossing, high lob, quartering away. The same problem as shooting an airborne enemy. Three birds per round, two hits to qualify.

**Blind round** (Master bracket only): HUD reticle removed. No aim assist. Roland must shoot by instinct — the draw sound and the arrow's physical arc are the only feedback. This is deliberately hard. Winning it is a genuine achievement.

### Streak multiplier

Consecutive hits earn a multiplier on the score (×1 → ×2 → ×3, resets on miss). Encourages confidence and punishes the safe play of deliberately missing easy shots to reset nerves.

### Stakes

Named bow or quiver item. Huntsman's Guild faction rep. Unlocks a hunting contract board at the range (side quests — specific rare animals Roland must track and take cleanly, no combat damage).

---

## Herbalism / Foraging Puzzle

### What it looks like

In forest or wetland zones, rare plants shimmer faintly — a barely-visible particle aura at rest. No map marker. Roland must notice them while exploring. The camera stays third-person; no UI overlay appears until Roland enters crouch-approach range.

### The loop

Rare plants have a **startle radius** — a soft invisible sphere around them. If Roland moves too fast within it, or if his shadow crosses it (sun angle matters — DayNightCycle shadow direction is live), the plant "closes" and the yield drops to common quality. Reopening a closed plant takes 10 in-game minutes.

**Slow approach:** Roland crouches and walks to the plant. The aura narrows as he closes. A faint audio cue (like a sustained note) pitches up as he approaches correctly.

**Harvest:** a brief hold-button action (same verb as gathering any world item, just longer — ~4 s for rare yield vs. ~0.5 s for common). During the hold, wind (WeatherManager) blows particles toward or away from the plant — if Roland is upwind, the plant may startle anyway. Approaching from downwind is the right play.

**Yield:** careful harvest → rare alchemical variant (unique ingredient not otherwise obtainable). Quick grab → common herb. The difference is meaningful: the rare variant may be the only source for a specific potion recipe.

### Skill integration

Herbalism sub-skill (under Exploration domain) reveals plant locations within a wider radius on approach, slows the startle trigger, and eventually allows Roland to "sense" closed plants and know how long until they reopen. High Herbalism also silences Roland's footsteps enough that a light jog doesn't startle a plant.

---

## Arm Wrestling

### What it looks like

Roland sits across from an NPC at a tavern table. Two voxel hands locked — a simple MeshInstance3D prop, no full body animation needed. A **force bar** sits between them, centred at rest. The camera drops low, across the table, so both faces are in frame — the NPC's expressions and bark reactions are the social layer.

### The loop

The player presses and holds (or taps rapidly, configurable) to push the bar toward the opponent's side. The opponent pushes back on a timer curve — slow build, then periodic surges.

**The surge:** a visible muscle-twitch particle on the NPC's forearm and a grunt bark telegraph an incoming surge ~0.5 s ahead. If Roland matches the surge (releases hold, then re-presses at the moment of surge) he cancels and gains momentum. If he's already at full hold when the surge hits, the surge wins that exchange.

**Endurance cost:** the hold draws from Roland's actual endurance bar (same bar as sprinting and combat). A player who sprinted across the map and sat down immediately will start at a disadvantage. The game doesn't tell you this — Roland just gets winded faster. Resting before a match (the Rest system) fully restores endurance.

**Strength sub-skill** under the Combat domain reduces the opponent's surge frequency and increases Roland's base push rate.

### Stakes

Coin. A named NPC champion in each major settlement — the blacksmith's lead apprentice, a retired soldier, the harbour master's second. Beating the champion earns a local reputation bark from nearby NPCs for the rest of the act. Orion will immediately challenge Roland if Roland wins, and Orion is stronger than he looks.

---

## Voxel Sculpture Contest

### What it looks like

A town square event. A block of soft sandstone (fast mining time, roughly 2 m × 2 m × 2 m) sits on a stone plinth. A silhouette reference hangs on a board beside it — a recognisable shape: a horse, an eagle, a ship. Roland uses his pickaxe. The camera stays third-person; the standard voxel edit tools are live.

### The loop

90 seconds. Carve away from the block toward the target silhouette. A score overlay compares Roland's current shape to the reference silhouette using a simple voxel-count overlap — percentage match visible as a bar at the edge of the screen, no more distracting than the compass. It updates every 5 seconds, not in real time, so you can't just chase the number.

The contest is **asymmetric**: a player who has spent hours in build mode and understands the tools will produce something recognisable. A player who has never carved will produce something memorable for different reasons. Both are valid; the contest is never gated on the result.

**Judge:** an NPC scores the result on two axes — shape accuracy (bar match) and cleanliness (number of floating single voxels). A rough but accurate shape beats a smooth blob.

### Stakes

First place: Sculptor's Mark — a craftable resource used to add decorative detail to player-built structures (Build Mode). Lore flavor: the stonecutters' guild uses this exact contest to identify apprentice talent; Roland's certificate opens a new dialogue branch with their master. Companion reactions: Dagna tries and produces something that is technically a horse if you squint.

---

## Summary Table

| Activity | Where | Core verb reused | Primary skill | Stakes |
|---|---|---|---|---|
| Smithing forge | Anvil (any smith) | — | Crafting / Smithing | Item condition tier |
| Fishing | Rivers, docks, sea cliffs | — | Exploration / Fishing | Food, alchemical ingredients, coin |
| Bones (dice) | Taverns | — | Charisma (tell-read) | Coin, faction disposition |
| The Fold (cards) | Taverns | — | Charisma | Coin, Crow/Shield rep |
| Axe throwing | Festival grounds | Throw (ThrowableHandler) | Combat / Thrown | Named axe, faction rep |
| Archery | Practice range, festivals | Draw + release (combat bow) | Combat / Ranged | Named bow, Huntsman quests |
| Herbalism | Forest / wetland zones | Crouch + hold-gather | Exploration / Herbalism | Rare alchemical ingredients |
| Arm wrestling | Taverns | Hold (endurance draw) | Combat / Strength | Coin, settlement reputation |
| Sculpture contest | Town square events | Pickaxe (voxel edit) | Build Mode literacy | Sculptor's Mark crafting resource |
