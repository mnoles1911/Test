# Combat Design — 3D Voxel

> **Status: DRAFT.** First-pass scoping document for the real-time 3D combat system. Replaces the M3 turn-based 2D combat scene entirely. References: Hades, Kingdom Come: Deliverance 2 (KCD2), Hyper Light Drifter, Ghost of Tsushima.

---

## Design Pillars

1. **Real-time, in-world.** Combat happens in the same scene the player walks through — no separate `Combat.tscn`, no turn rounds. Walking near hostiles puts you in danger.
2. **Skill over stats.** Player improvement matters more than character level. Combat depth comes from timing, positioning, and reading enemies.
3. **One vs. many, but not Dynasty Warriors.** Roland (with optional companions) facing a handful to a dozen enemies. Each enemy is a real threat — even a single goblin can land a hit if Roland is careless.
4. **Tactile commitment.** Attacks have wind-up, follow-through, and recovery. You commit to a swing. KCD2's deliberate weight, not Devil May Cry's fluid combos.

---

## Confirmed Mechanics

### Movement in Combat

- **Dodge / roll** — short directional burst with i-frames. Resource cost (stamina). Slightly weaker than KCD2's dodge — Roland is a tired traveller, not a martial artist.
- **Sprint** — sustained run, depletes stamina. Cannot attack while sprinting; must stop or transition into charge attack.
- **Lock-on** — toggleable. When locked, camera adjusts to keep target framed; movement strafes around target. Default off — Roland faces movement direction otherwise.

### Attacking — Length-of-Click Power System

Inspired by charged attacks in Souls/Sekiro but expressed through click duration rather than a separate button.

- **Tap LMB** → **fast attack** (light damage, short recovery, can chain quickly)
- **Hold LMB** → **charging power attack** (visual tell on Roland's stance)
- **Release LMB** when charged → **power attack** (heavy damage, slow recovery, breaks blocks)

**Combos chain by click pattern:**
- `tap → tap → tap` — light combo (3 quick swings)
- `tap → tap → hold/release` — light-light-heavy (combo finisher)
- `hold/release → tap` — power opener into a recovery jab
- Pure power-power chains are limited by stamina

Each click in a combo has a **timing window** to chain. Click outside the window starts a fresh combo. This is the system's depth.

### Blocking and Parrying — RMB

- **Hold RMB** → block stance. Reduces damage from incoming attacks. Costs stamina per hit absorbed.
- **Tap RMB just before incoming attack** → parry. Window is narrow.
- **KCD2-style color indicators on the enemy:**
  - **Green flash** on enemy when their attack is parryable
  - **Red flash** when their attack is unblockable (must dodge)
  - **Yellow flash** for a heavy attack (block at stamina cost, or dodge)
- The window for the green parry is brief — KCD2 difficulty curve, not Sekiro's looseness.

### Weapons

- **Melee only for Game One.** Sword as Roland's starting and primary weapon. Other melee types (axe, mace, dagger) may be added if pacing allows.
- No ranged option for Roland. Companions or specific items may have ranged attacks later.

### Health and Endurance

Two-track system modeled on KCD2:

- **HP bar** — Roland's total health. Visible to the player as a bar. Does not regenerate passively mid-combat. Reduced by landed hits.
- **Endurance** — a secondary pool that gates how hard Roland can fight. Overall health caps the endurance maximum: a badly wounded Roland has less endurance headroom than a fresh one.
  - Attacks, blocks, sprints, and dodges drain endurance.
  - Endurance recovers when Roland is not acting (brief pause between swings, backing off from a fight).
  - Running out of endurance does not kill Roland — it makes him slow and unable to dodge, which then gets him killed.
- **No visible enemy health bars.** Read enemy condition from behavior and appearance: limping gait, staggered recovery, blood, slowed swings. Enemies react visibly when close to death — don't just change a number.

### Enemy Detection and Encounter Framing

Enemies are placed in the open world the player walks through — no arena spawning, no separate scene.

**Spawn and despawn:**
- Enemies spawn via **quest triggers** (scripted placement when the player reaches a location or completes an event) or **proximity algorithms** (recurring patrol/roam groups that repopulate areas over time).
- When the player travels far enough away, out-of-range enemies despawn quietly. They respawn when the player re-enters the area, unless a quest flag has cleared the location.

**Detection values per enemy type:**
Each enemy type has tunable values that govern when combat begins and ends:

| Value | Description |
|---|---|
| `vision_range` | Distance at which enemy spots Roland (line-of-sight check) |
| `hearing_range` | Distance at which running/fighting sound alerts the enemy |
| `alert_threshold` | How many alert "ticks" before enemy commits to attacking |
| `disengage_distance` | Distance Roland must put between himself and the enemy before the enemy gives up |
| `disengage_time` | Seconds enemy must fail to close the gap before disengaging |

Wolves have high vision and hearing; bears low hearing but wide vision; goblins medium-range but large groups trigger group alert.

**Fleeing:**
- Roland can break combat by running far enough, fast enough.
- Enemies pursue until `disengage_distance` and `disengage_time` are both satisfied.
- Sprinting costs stamina — sustained flight has a cost.

### Consumables

Roland has dedicated **consumable slots** (not buried in an inventory menu — accessed mid-combat via a quick slot bar).

Confirmed consumable categories:
- **Bandages / healing herbs** — restore HP. Require a cast animation (vulnerable window during use). Cannot be chugged instantly.
- **Potions** — more powerful HP or endurance restoration; rarer and crafted.
- **Throwables** — bombs, oil flasks, smoke grenades. Used mid-combat. Small aiming reticle, short throw arc. Each type has distinct tactical use (fire damage, slippery surface, vision obscure).
- **Saviour Schnapps** (save item) — doubles as the diegetic quicksave mechanic. Consuming one creates a manual save. Limited supply. The save-and-drink animation is the same as a potion.

### Progression — KCD2 Model

Roland gains levels and skill unlocks through **in-game action**, not XP grind:

- **Train to improve.** Using a sword improves sword skill. Running improves stamina recovery. Crafting improves crafting proficiency. The system tracks what you actually do.
- **Skill trees** span four domains: **Combat** (attack patterns, parry window, power attack modifiers), **Vitality** (max HP, endurance pool, wound recovery speed), **Crafting** (potion effectiveness, smithing tiers, throwable crafting), **Exploration / Speech** (deferred, not Game One priority).
- No mandatory level gates on story progression — skill improves how effectively Roland fights, not whether he can enter a zone.
- Enemies do not scale with Roland. A goblin is always a goblin — as Roland improves, goblins become reliably manageable.

### Enemy Roster (Game One)

| Enemy | Tier | Behavior | Damage | Defense | Notes |
|---|---|---|---|---|---|
| **Goblin** | weak / numerous | aggressive, swarms, low HP | low | unarmored | Cannon fodder. 6–10 in a typical encounter. |
| **Ashfallen** | elite / heavy | slow, deliberate, well-armored dark knight | high | heavy armor (block more than chip damage) | Telegraphed power attacks. The signature Game One enemy. 1–3 per encounter. |
| **Wolf** | fast / agile | leap-attack, dodge-rolls, flanks | medium | unarmored | The dodgers. They evade Roland's swings — must be cornered or anticipated. Pack of 3–5. |
| **Bear** | slow / heavy / unarmored | charge attacks, claw swipes, bite | very high (claw + teeth) | unarmored but high HP | Mini-boss tier. Usually solo. |

**Encounter scale:** up to ~12 enemies on screen at maximum (with companions present). Typical encounter: 4–8.

### Death and Saves — KCD2 model

- Death returns Roland to **the last savepoint**.
- Savepoint sources:
  1. **Level checkpoints** — fixed save points placed by the designer (typically rest spots, before bosses, after major story beats).
  2. **Sleeping in a bed** — manual save when the player chooses to rest at a campfire, inn, or safe location.
  3. **Saviour Schnapps equivalent** — a consumable potion that creates a manual save when drunk. Limited supply, encourages risk management.
- No quicksave / quickload. Saves are diegetic.

---

## TODO — Open Design Questions

The following are the remaining open questions. Everything else has been confirmed above.

### Stamina
- **TODO:** Does charging a power attack drain endurance while held, or only on release?
- **TODO:** Endurance recovery rate and hard cap — numbers TBD when implementing.

### Companions
- **TODO:** Are companions (Orion, Dagna once they join) fully autonomous AI, player-commandable (hold / engage / retreat), or direct-control swap?
  - Lean toward player-commandable (two or three simple orders), but not yet confirmed.

### Weapons
- **TODO:** Are weapons upgradeable per KCD2 (sharpening, smithing tiers) or fixed stat blocks?
  - Progression system implies smithing upgrades, but the exact crafting depth is unconfirmed.

---

## Architectural Implications

These will inform the next code milestones; flagged here so they aren't surprises.

- **NavigationRegion3D + NavigationAgent3D** required for enemy pathfinding. Doesn't exist yet.
- **Animation tree per enemy type** — wolves need leap, bears need charge, goblins need swarm flee/attack swap. ~20 unique animation states across the four enemy types.
- **Companion AI** — needs a behavior tree or state machine even if minimally directable.
- **Stamina HUD** — new UI element; probably bar under HP, with stamina-cost previews on dodge/sprint/power-attack.
- **Lock-on camera blend** — `SpringArm3D` needs a "look at target" mode that smoothly blends into / out of fixed mode.
- **Save points as world objects** — beds and campfires become interactable nodes that call `GameState.save_game()` directly. Saviour Schnapps becomes an inventory item that triggers save on use.

---

## Out of Scope for First Pass

These are deliberately deferred until the core loop is fun:

- Mounted combat (KCD2 has it; not relevant to Game One)
- Stealth kills (may be relevant for Roland's chase scenes, but not combat)
- Multi-weapon switching mid-combat
- Critical hits / aimed strikes per body part
- Cinematic finishers
- Boss fights with multi-phase mechanics (Game One has no formal boss; the Ashfallen elites are the closest thing in Acts I–II)
