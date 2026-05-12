# Perk Library — Game One

Authoritative reference for every perk in the 12-skill progression system.
**300 perks total** — 25 per skill, one perk per milestone (L4, L8, …, L100).
Some perks share an `exclusive_group` so picking one locks the other(s).

- **Source of truth**: this document.
- **Data files**: `assets/skills/perks/{skill}/{perk_id}.tres`
- **Active perk scripts**: `scripts/skills/perks/{skill}/{perk_id}.gd` (subset, `is_active = true`)
- **Generator**: `tools/generate_perks.py` — re-run after editing the SPECS table to regenerate every `.tres` and active `.gd` stub.

When tuning a value, edit `tools/generate_perks.py`'s SPECS table and re-run the generator. Hand-edits to individual `.tres` files are fine for one-off tweaks during play-testing but will be overwritten if the generator runs again.

## Perk schema

Each row of the SPECS table maps to these `PerkData` fields:

| Field | Notes |
|---|---|
| `perk_id` | Unique across all perks. Convention: `{skill_short}_{name}`. |
| `display_name` | Player-facing label in the perk picker. |
| `description` | One-line player-facing description (must fit in ~80 chars). |
| `effect_type` | `damage_mult`, `yield_bonus`, `stamina_regen`, `damage_taken`, etc. |
| `effect_value` | Float. Multipliers are deltas (e.g. `0.10` = +10%). |
| `effect_target` | `sword`, `all`, `ore`, `potion`, etc. Read by the system that applies it. |
| `condition` | `""` = always; `on_power_attack`, `target_full_hp`, `low_hp_50`, etc. |
| `exclusive_group` | `""` = standalone; non-empty = exclusive choice. |
| `is_active` | `true` if a sibling `.gd` overrides hooks. |
| `level_required` | Computed: `(milestone_index + 1) × 4`. |
| `milestone_index` | Computed: position in SPECS list. |

## Per-skill summary

Every skill has 25 perks across the 25 milestones. Below is the count of
active vs passive perks per skill, plus a one-line theme.

| Skill | Active | Passive | Theme |
|---|---|---|---|
| Sword | 11 | 14 | Parries, rhythm, combat focus |
| Throwables | 8 | 17 | Range, AoE, retrieval, sticky kills |
| Bow | 8 | 17 | Headshots, focus-time, status arrows |
| Mining | 5 | 20 | Veins, ore yield, fall safety |
| Felling | 6 | 19 | Wood yield, axe combat, sapling drops |
| Excavation | 10 | 15 | Disks, buried treasure, traps, water finding |
| Demolition | 7 | 18 | AoE shaping, chain explosions, debris control |
| Lockpicking | 9 | 16 | Tier ladders, treasure detection, retry economy |
| Alchemy | 5 | 20 | Yield, potion power, taster mechanics |
| Smithing | 4 | 21 | Quality procs, repair, signature items |
| Vitality | 2 | 23 | HP / endurance / environmental resilience |
| Speech | 10 | 15 | Charm / intimidate / persuade, trade margins, faction |

(See `tools/generate_perks.py` SPECS table for the full perk list.)

## Authoring conventions

1. **Stay descriptive, not numerical, in `display_name`** — "First Blood",
   "Quick Hands", "Master Miner". The numbers live in the description.
2. **Description format** — single sentence, ends with a period.
   Multipliers expressed as percentages ("+10%"), durations in seconds.
3. **Effect targets are namespaces**, not item IDs unless the perk truly
   only fires on one item. Use `"sword"`, `"explosives"`, `"ore"`, etc.
4. **Conditions** are short tokens the perk system reads — keep the
   vocabulary tight. Add new tokens only when a new gameplay system
   genuinely needs one.
5. **Exclusive groups** scoped per skill. Two perks sharing a group key
   should be roughly equal-power; the choice should be a flavor choice,
   not a strict upgrade ladder.

## Maintenance

Update this doc when:

- A new perk is added or removed.
- An `effect_type` token is added (so other systems know to handle it).
- An exclusive group changes.
- An active perk's authoritative hook lands in scripts/skills/perks/{skill}/{perk_id}.gd (mark "Implemented" in the table).
