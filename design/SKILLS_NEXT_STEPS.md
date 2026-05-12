# Skill System — Next Steps

> Roadmap for unfinished skill / perk work on top of PR #201 (`claude/skill-system` → `main`, draft). See `design/SKILLS_AND_PROGRESSION.md` for what's already live and `design/PERK_LIBRARY.md` for the 300-perk reference.

## Status snapshot (2026-05-12)

| Slice | Status | Notes |
|---|---|---|
| 12 skills, 1–100 cap, Skyrim XP curve | ✅ live | `SkillManager.add_xp` is the single entry point |
| 300 perks (25 per skill) | ✅ live | `assets/skills/perks/{skill}/*.tres` + 85 active `.gd` |
| JournalUI Skills tab | ✅ live | Grid view, perk ladder, Legendary confirm |
| FactionManager + Trainers | ✅ live | 6 trainer NPCs, faction-gated at disposition ≥ 75 |
| Speech checks (KCD2 visible-greyed) | ✅ live | `SpeechCheckBroker` + Dialogic signal handler |
| Active perk hooks (85 files) | ✅ wired | Many depend on gameplay systems that don't exist yet |
| Lockpicking minigame | ⏳ partial | `LockObject3D` + `LockData` exist; `LockpickingUI` referenced but the polished radial dial is pending |
| Alchemy / Smithing minigames | ⏳ stub | `AlchemyStation.gd` / `SmithingForge.gd` fire XP on `craft()`; no UI yet |
| Parry mechanic | ❌ design-only | `CombatXPRouter.report_parry_success` exists; Player3D has no parry button |
| Fall-damage Vitality XP | ❌ design-only | Player3D has no fall-damage branch |
| CharacterRecord persistence | ❌ pending | Skill state lives on GameState; MP-6 migrates |

---

## 1. Wire dormant gameplay systems that active perks already reference

Many of the 85 active perks set well-named `ctx` flags expecting a future system to read them. The perks compile and run; the **effects** light up when each backing system lands. Roughly grouped by system:

### Parry mechanic
**Perks unlocked:** `sword_riposte` (in-flight already — the perk has `_parry_window_open_until` state, awaits `on_parry` dispatch)

**Work:** add a parry input to `Player3D` (likely tied to a new `parry` Input Map action). On press, open a 300 ms window during which incoming melee damage is fully blocked AND triggers `CombatXPRouter.report_parry_success(attacker)`. The router already dispatches `on_parry` to `SkillManager`. See `design/COMBAT_DESIGN_3D.md` for the design spec.

**~150 lines** in Player3D + Enemy3D melee path.

### Stagger / DoT / fear / x-ray status effects
**Perks already mutating ctx for these:** `sword_disarming_strike` (stagger), `sword_bleed` (DoT bleed), `sword_dread_blade` (fear AoE), `bow_bleed_arrows` / `bow_fire_arrows` (DoT), `bow_third_eye` (x-ray outline), `demo_concussion` (stun AoE), `throw_marked_target` (+20% damage debuff).

**Work:** add `Enemy3D.apply_status(name, duration)` and `Enemy3D.apply_dot(type, dps, duration)`. Status system is a small `Dictionary` on `Enemy3D` ticked in `_physics_process`; DoT system needs visual feedback (blood drips for bleed already exist; flame VFX for burn).

**~300 lines** across Enemy3D + a new `StatusVFX.gd` autoload (or extension of BloodVFX).

### Voxel-break ctx enrichment (near_water, on_tree_break, on_corpse)
**Perks already gated on these flags:** `dig_clay_finder` / `dig_gravel_finder` (`near_water`), `fell_branch_break` / `fell_select_cut` / `fell_evergreen` (`on_tree_break`), `dig_grave_robber` / `dig_field_medic` / `dig_quickburial` (`on_corpse`).

**Work:** enrich the ctx dispatched from `EditToolHandler.gd` after a voxel break. Add `near_water` (query `WaterFlowManager.is_position_in_water` within 3 m), `on_tree_break` (detect that the just-broken voxel was the last wood in a contiguous column), `on_corpse` (raycast for nearby `corpse` group bodies).

**~100 lines** in EditToolHandler + small helpers.

### Vision overlays (vein-sense, hidden caches, terrain-eye)
**Perks announcing themselves on pick:** `mine_vein_sense`, `mine_ore_sense`, `fell_tree_sense`, `dig_terrain_eye`, `dig_water_finder`, `dig_no_traps`, `demo_blast_eyes`, `lock_thief_eye`, `lock_hidden_caches`, `lock_keen_eye`, `alch_keen_nose`, `alch_recipe_eye`, `smith_recipe_eye`.

**Work:** an outline-through-walls shader pass, an in-world overlay queryable per object kind, and a minimap. All three are sizable subsystems — pickaxe-vein highlight is the cheapest start (sample ore voxels within 8 m of the player when pickaxe is drawn, spawn a thin transparent voxel overlay).

**Substantial.** Defer until there's player-testing demand.

### Active abilities that need a button
**Perks:** `alch_poisoner` (apply blade poison from inventory), `alch_taster` (taste unknown ingredient), `lock_decoy` (drop fake pick), `speech_calm` (reduce enemy aggression), `speech_diplomat` (pick a faction for +10 disposition), `speech_inspire` (companion buff).

**Work:** these need an "active abilities" UI / hotkey slot. Currently no slot for them in HUDOverlay. Likely a sub-tab in JournalUI or a new quick-bar.

**Substantial.** Defer until the design specifies the active-ability surface.

---

## 2. Build the three crafting minigames (already scaffolded)

### Lockpicking — polished radial dial
- `LockObject3D` + `LockData` exist; `LockpickingUI.gd` is referenced (`class_name LockpickingUI`) but the actual UI implementation isn't in the codebase yet.
- Per `design/LOCKPICKING.md`: resonance pick radial dial system, 4 lock tiers (Easy/Medium/Hard/Very Hard), pick consumption on snap.
- **Tier-1 silver_pick auto-open is already wired** in `LockObject3D._try_perk_auto_open` (consults `PerkQuery.has_flag("lock", "tier_1")`).
- `lock_perfect_pick` daily auto-open is also wired — `LockObject3D` dispatches `on_lock_opened` with `first_per_day=true` before opening, and the perk's `_used_today` state gates it.

**Work:** implement `LockpickingUI` as a programmatic CanvasLayer with manual `_input` dispatch (per CLAUDE.md), tier-aware sweet spot arc, pick durability decay.

### Alchemy — recipe combine UI
- `scripts/minigames/AlchemyStation.gd` exposes `craft(recipe_id, consumed_ingredients)` that fires Alchemy XP and adds the produced potion to inventory. **Already callable.**
- 12 potions live in `InventoryManager.ITEM_REGISTRY` (representative sample); the full 40 from `design/ITEM_LIBRARY.md` need adding.
- 4 herbs (kingsfoil, silverleaf, emberbloom, nightshade) live in the registry as crafting mats.

**Work:** scene `scenes/crafting/AlchemyStation.tscn` (cauldron prop + UI), a recipe table mapping `{ingredient_set} → potion_id`, the combine UI itself. `alch_recipe_eye` perk consults `PerkQuery.has_flag("alchemy", "while_craft")` to highlight matching recipes.

### Smithing — three-strike rhythm
- `scripts/minigames/SmithingForge.gd` exposes `craft(item_id, tier, consumed_ingredients)` that fires Smithing XP scaled by tier (`XP_PER_CRAFT_BASE × tier`).
- 10 smithed items in the registry (iron/silver/ashsteel weapons + armor sample).

**Work:** scene `scenes/crafting/SmithingForge.tscn` (forge + anvil), recipe table, three-strike rhythm timing UI, quality roll (modulated by `smith_runed` and `smith_legendary_form` perks consulted via `PerkQuery`). The "perfect rhythm" condition is what `smith_legendary_form` reads to upgrade an item by one tier.

---

## 3. Save / load + CharacterRecord migration (MP-6 dependency)

**Current state:** skill state lives on `GameState` (`_skill_levels`, `_skill_xp_progress`, `_owned_perks`, `_perk_points_unspent`, `_legendary_resets`, `_faction_dispositions`, `_trainer_visits`). All wired through `SkillManager`'s public API. Save/load via existing GameState serialization.

**Why it works for single-player today:** skill state IS the player's per-character state. There's only one player.

**Why it needs to move for MP:** when multiple guests connect with their own characters, each one's skill state must travel with them. The MP plan calls for `CharacterRecord` to own per-character state (skills, perks, inventory, equipment, gold, factions). See `design/MP_NEXT_STEPS.md` → MP-6.

**Migration plan:**
- `SkillManager`'s public API (`add_xp`, `get_level`, `pick_perk`, `make_legendary`, etc.) stays unchanged.
- Internal storage swaps from `GameState._skill_levels` etc. to `CharacterStore.local_record.skill_levels` etc.
- Save triggers move from GameState save to CharacterRecord save (different file on disk, per Steam ID).
- A one-shot loader at MP-6 land time reads any existing GameState save, copies the 7 skill-related dictionaries into a new CharacterRecord, and clears them from GameState.

The skill PR (#201) explicitly notes this is a transitional state. Don't break the API.

---

## 4. ITEM_REGISTRY catalog completion

`InventoryManager.ITEM_REGISTRY` got a 26-item representative sample with the skill PR (12 potions + 10 smithables + 4 herbs). The full catalog per `design/ITEM_LIBRARY.md`:

- **40 potions** total — 12 added, **28 missing**
- **40 smithable items** total — 10 added, **30 missing**
- **15 craftable lockpicks / consumables** — partial
- **30 assembly items** (carpentry + tools) — none added yet

**Work:** mechanical — copy each row from `design/ITEM_LIBRARY.md` into the ITEM_REGISTRY dict. Recipes get added to AlchemyStation / SmithingForge recipe tables in parallel.

---

## 5. Perk balance pass

The 300 perks were authored to feel coherent within each skill tree, not to be balanced against each other across trees. Most multipliers are placeholders (10%, 15%, 25%, 50% — round numbers picked for clarity).

**Work:** play through a single skill tree to 100, log which perks felt overpowered / underwhelming / never-fired. Tune via `tools/generate_perks.py` SPECS table; re-run the generator. No code changes required for pure number tweaks.

**Defer** until there's enough gameplay to playtest. Premature balancing wastes effort.

---

## 6. Test infrastructure

No `scenes/_dev/SkillTest.tscn` exists yet. The skill system is currently exercised only through normal gameplay (mining/felling fires XP, JournalUI Skills tab renders, etc).

**Proposed:** a flat dev arena with:
- A local Player3D
- 12 dev cheats (F1-F12) granting one level per skill (single key press → +1 level in the matching skill)
- A trainer NPC stub bound to F11 to open the training modal
- A speech-check button bound to F12 to open the modal at DC 40
- A perk-budget cheat (F10) granting +10 perk points
- A Legendary trigger (F9) setting the focused skill to 100

Lets the system be exercised end-to-end without grinding 430k XP per skill.

**~250 lines** in a single `scripts/_dev/SkillTest.gd` + scene stub.

---

## Recommended order

1. **Test scene first.** `scenes/_dev/SkillTest.tscn` is cheap to build and unlocks debugging everything else.
2. **Parry mechanic.** Single skill (Sword) gets meaningfully more alive once Riposte fires. Small scope.
3. **Voxel-break ctx enrichment.** Lights up ~8 active perks across Excavation / Felling / Mining for ~100 lines of EditToolHandler work.
4. **Lockpicking UI.** Tier-1 auto-open is already wired; the manual minigame is the only missing piece for the rest of the lockpicking perks to feel meaningful.
5. **Alchemy + Smithing UIs.** Once recipes + UI exist, the 9 crafting perks (4 Smithing + 5 Alchemy active) come online.
6. **Status / DoT system.** Roughly the same effort as ITEM_REGISTRY completion; unlocks ~10 combat perks across all three combat trees.
7. **CharacterRecord migration.** Coordinate with MP-6 (see `design/MP_NEXT_STEPS.md`).
8. **Vision overlays and minimap.** Sizeable. Defer.

---

## Cross-references

- `design/SKILLS_AND_PROGRESSION.md` — what's live + the v1 status section
- `design/PERK_LIBRARY.md` — authoritative 300-perk reference (auto-generated header from `tools/generate_perks.py`)
- `design/FACTION_SYSTEM.md` — disposition scale + trainer gate
- `dialogue/STYLE.md` § 8 — Speech-check authoring conventions
- `design/MP_NEXT_STEPS.md` → MP-6 — CharacterRecord migration target
- `CLAUDE.md` → "Critical GDScript patterns" — `SkillManager.add_xp` rule
