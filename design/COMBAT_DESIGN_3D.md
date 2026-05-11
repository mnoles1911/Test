# Combat Design — 3D Voxel

> **Status: DRAFT design spec (what we want).** First-pass scoping document for the real-time 3D combat system. Replaces the M3 turn-based 2D combat scene entirely. References: Hades, Kingdom Come: Deliverance 2 (KCD2), Hyper Light Drifter, Ghost of Tsushima.
>
> **Implementation status:** Voxel Combat v1 shipped May 2026 (spear-only, Goblin enemy, blood VFX, dev arena). Full melee, parry, lock-on, attack-token AI, and other enemy types remain unbuilt. See `design/COMBAT_NEXT_PHASES.md` for the prioritized roadmap and current status of each system below.

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
- **Tap RMB just before incoming attack** → parry. Window is learnable, not punishing.
- **KCD2-style color indicators on the enemy:**
  - **Green flash** on enemy when their attack is parryable
  - **Red flash** when their attack is unblockable (must dodge)
  - **Yellow flash** for a heavy attack (block at stamina cost, or dodge)
- **Base parry window: 300ms (0.3 seconds).** This is approximately twice as forgiving as KCD2 (~150ms) while still requiring attention. The Wider Parry Window skill perk extends this to 345ms (+15%). The Accessibility "Combat Timing Assistance" setting extends to 375ms (+25% on top of base).

### Weapons

- **Melee only for Game One.** Sword as Roland's starting and primary weapon. Other melee types (axe, mace, dagger) may be added if pacing allows.
- No ranged option for Roland. Companions or specific items may have ranged attacks later.

### Health and Endurance

Two-track system modeled on KCD2:

- **HP bar** — Roland's total health. Visible to the player as a bar. Does not regenerate passively mid-combat. Reduced by landed hits.

**Wound HP:** 25% of every point of damage taken in combat becomes **wound HP** — the dark red portion of the HP bar that potions and bandages cannot restore. Only full rest or Boneknit Compound can heal wound HP. The remaining 75% is regular HP, restorable by consumables. Example: a 40-damage hit gives Roland 30 regular HP loss and 10 wound HP loss.

- **Endurance** — a secondary pool that gates how hard Roland can fight. Overall health caps the endurance maximum: a badly wounded Roland has less endurance headroom than a fresh one.
  - **Base pool: 100.** Endurance recovers at **20 points per second** when Roland is not performing a costly action.
  - **Endurance costs per action:**

| Action | Endurance cost |
|---|---|
| Light attack (tap) | 8 |
| Power attack (on release) | 18 |
| Block (per hit absorbed) | 12 |
| Parry (successful) | 5 |
| Dodge roll | 15 |
| Sprint | 8 per second |

  - **Stagger at zero endurance:** Roland cannot dodge or attack for **1.5 seconds**. Movement speed drops to 60% during stagger. Endurance begins recovering immediately from zero.
  - Charging a power attack does NOT drain endurance while held — cost is paid on release only. Aborting the charge costs nothing.
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

### Companions in Combat

Companions (Orion, later Dagna) fight autonomously by default. Roland can issue **simple orders** via a radial/context menu:

- **Engage** — attack the current target
- **Hold position** — stop pursuing, defend in place
- **Retreat** — fall back to Roland's position and stop attacking

Companions are not directly controlled. Between fights (or at camp), Roland can **interact with each companion** to manage their inventory and gear — equip better weapons, restock their consumables, review their loadout.

Friendly fire is off. Roland cannot accidentally hit companions.

### Weapons and Equipment Condition

**Smithing tiers** determine a weapon's base stats at the point of creation or acquisition:

| Tier | Description |
|---|---|
| Common | Standard market quality — baseline damage, no bonuses |
| Quality | Well-made — modest damage and durability improvement |
| Masterwork | Exceptional craft — meaningful stat boost, rare |

Higher smithing skill (from Roland's Crafting progression) unlocks the ability to produce or commission higher tiers.

**Condition / wear:**
- Weapons and armor degrade with use — tracked as a condition percentage.
- A weapon in poor condition loses effective damage and blocking reliability (its "endurance" for blocking wears down faster).
- **Sharpening kits** restore weapon sharpness (damage). **Repair kits** restore armor and blunt weapon integrity.
- Kits are consumables: kept in inventory, applied at camp or between fights.
- A broken weapon (0% condition) still functions but at severe penalty — forces a gear decision mid-run.

### Endurance and the Power Attack Charge

Charging a power attack (holding LMB) does **not** drain endurance while held. Endurance is spent **on release**, when the attack fires. Aborting a charge costs nothing.

This keeps feinting and pressure-testing feels free — the cost is paid when you commit.

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
  3. **Wanderer's Seal** — a consumable vial that creates a manual save when drunk. Limited supply, encourages risk management. (See `design/CRAFTING.md`.)
- No quicksave / quickload. Saves are diegetic.

---

## Tunable Values

These values are locked for implementation but expected to be adjusted during playtesting. Change them in a single constants file rather than scattered through scripts.

| Value | Set | Rationale |
|---|---|---|
| Parry window | 300ms | ~2× KCD2, forgiving but requiring attention |
| Parry window (Wider Parry perk) | 345ms | +15% over base |
| Parry window (accessibility) | 375ms | +25% over base |
| Endurance pool (base) | 100 | Standard RPG pool |
| Endurance recovery rate | 20/sec | Full recovery from zero in 5 seconds |
| Light attack endurance cost | 8 | Can chain ~12 lights before depleting |
| Power attack endurance cost | 18 | Can chain ~5 powers before depleting |
| Block endurance cost (per hit) | 12 | ~8 blocked hits before stagger |
| Parry endurance cost | 5 | Rewards successful parry over blocking |
| Dodge endurance cost | 15 | ~6 consecutive dodges before depletion |
| Sprint endurance cost | 8/sec | ~12 seconds of sprinting from full |
| Stagger duration (0 endurance) | 1.5s | Brief, recoverable |
| Stagger movement speed | 60% | Noticeably slow, not immobilized |
| Wound HP fraction | 25% | 1/4 of all damage is wound HP |

---

## Destructible Terrain in Combat

The world is destructible by default (see `design/3D_VOXEL_MIGRATION.md` → Destructible Terrain). Combat-side implications:

- **Knockback into terrain.** Heavy power attacks that drive an enemy into a wall can chip voxels off on impact. Routes through `VoxelEditManager` async edit queue with a per-impact voxel budget cap (max ~6 voxels). Visual: dust burst + small block ejecta. Not authored, just emergent. Any voxels left unsupported by the chip will subsequently fall via `VoxelGravityManager`.
- **Pit-trapping.** Players who dig pits before a fight and lure enemies in is a real tactic. Embraced as a power moment. Anti-cheese: any enemy stuck > 8 seconds teleport-corrects to the nearest valid nav node with a small VFX.
- **Stale-path tolerance.** When terrain changes, navmesh rebuild is async. AI tolerates stale paths for 1–2 seconds post-edit; enemies will briefly walk into a new wall before re-pathing. Acceptable.
- **Explosives in combat.** Powder Charge and Sapper's Bundle (see `design/ITEM_LIBRARY.md` → Section 4) deal combat damage AND remove voxels in their AOE. Wall-breach attacks are real; throwing one inside a settlement still deals damage but leaves the masonry intact (NoEditZone).
- **Crush damage from falling voxels.** Voxels that lose their support fall via `VoxelGravityManager` and damage anything they hit with `damage = voxel_count × fall_height_m × 0.05` (1.5 m minimum fall). This makes ceiling-collapse a real combat verb: cut the rock above the goblin and the rock kills the goblin. See `design/3D_VOXEL_MIGRATION.md` → "Voxel Gravity" for the full spec.
- **Spell-driven terrain effects** — Game Two onward, when magic-using companions arrive. Earth-school AOE spells dig; fire spells fell trees and ignite. Same `VoxelEditManager` path as explosives; same NoEditZone enforcement.
- **NoEditZones in combat.** Settlements and lore landmarks reject voxel edits regardless of source. Combat damage to enemies and props inside still works normally; only terrain mutation is blocked.

---

## Architectural Implications

These will inform the next code milestones; flagged here so they aren't surprises.

- **NavigationRegion3D + NavigationAgent3D** required for enemy pathfinding. Doesn't exist yet.
- **Chunked navmesh + async rebuild on voxel edits.** Each voxel chunk owns a NavigationRegion3D shard. `VoxelEditManager` signals chunk dirty on edit; rebuild runs on a worker thread with a per-frame budget. AI agents tolerate stale paths for 1–2 seconds after a chunk re-bake.
- **Animation tree per enemy type** — wolves need leap, bears need charge, goblins need swarm flee/attack swap. ~20 unique animation states across the four enemy types.
- **Companion AI** — behavior tree or state machine with three order states (engage / hold / retreat). Companion inventory access requires an interaction UI screen (can reuse/extend JournalUI item tab pattern).
- **Stamina HUD** — new UI element; probably bar under HP, with stamina-cost previews on dodge/sprint/power-attack.
- **Lock-on camera blend** — `SpringArm3D` needs a "look at target" mode that smoothly blends into / out of fixed mode.
- **Save points as world objects** — beds and campfires become interactable nodes that call `GameState.save_game()` directly. Saviour Schnapps becomes an inventory item that triggers save on use.
- **Equipment condition tracking** — `InventoryManager` needs a `condition` field per item (float 0–1), modified by use and restored by sharpening/repair kits. Smithing tier stored as an enum on the item resource.
- **Smithing skill gate** — Crafting progression must expose a `smithing_tier_unlocked` value that the crafting UI checks before showing masterwork recipes.

---

## Out of Scope for First Pass

These are deliberately deferred until the core loop is fun:

- Mounted combat (KCD2 has it; not relevant to Game One)
- Stealth kills (may be relevant for Roland's chase scenes, but not combat)
- Multi-weapon switching mid-combat
- Critical hits / aimed strikes per body part
- Cinematic finishers
- Boss fights with multi-phase mechanics (Game One has no formal boss; the Ashfallen elites are the closest thing in Acts I–II)
