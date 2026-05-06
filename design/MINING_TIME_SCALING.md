# Mining Time Scaling

How long it takes the player to break voxels with a manual tool
(pickaxe / shovel / axe), as a function of:

1. **The voxel material** — each `VoxelMaterial.tres` carries a
   `mining_time_seconds` baseline.
2. **The carve volume** — the player cycles 1×1×1 / 2×2×2 / 3×3×3 with
   the scroll wheel while a manual tool (pickaxe / shovel / axe) is
   equipped.

This document is the canonical reference for both. The formula and
material tables below are what `EditToolHandler._tick_held_action`
implements at runtime.

---

## The formula

```
swing_seconds = material.mining_time_seconds × (N³ / 8) × tool_multiplier
```

where `N` is the carve volume side length (1, 2, or 3) and
`tool_multiplier` is **1.0** when the equipped manual tool is in the
material's `allowed_tools` list (the "preferred tools"), or
**`WRONG_TOOL_SPEED_MULTIPLIER` = 3.0** otherwise.

Empty `allowed_tools` (bedrock) means **no tool can mine the
material** — the swing is blocked entirely, the multiplier doesn't
apply.

The 2×2×2 carve is calibrated as the **baseline** (multiplier = 1.0)
because it's the most common volume — fast enough to feel responsive,
big enough to make visible holes. The other volumes scale around it:

| Volume `N` | Voxels removed | Time multiplier |
|---|---|---|
| 1×1×1 | 1 | **0.125×** (1/8) |
| 2×2×2 | 8 | **1.000×** (8/8 — baseline) |
| 3×3×3 | 27 | **3.375×** (27/8) |

The intent is **risk/reward**: 1×1×1 is fast for precision picking
(carving stairs into a cliff, freeing a single ore vein), 3×3×3 is
slow but high-throughput for bulk volume work (mining out a chamber).
The 2×2×2 default is what feels "normal."

---

## Current materials

The pilot four with their preferred-tool baselines (assumes the
right tool is equipped — multiply each cell by 3 if the player
swings with the wrong manual tool, see "Tool mismatch" below):

| Material | `mining_time_seconds` | 1×1×1 | 2×2×2 | 3×3×3 | Preferred tool |
|---|---|---|---|---|---|
| **sand** | 0.2 s | 0.025 s | 0.20 s | 0.675 s | iron_shovel |
| **dirt** | 0.3 s | 0.038 s | 0.30 s | 1.013 s | iron_shovel |
| **grass** | 0.3 s | 0.038 s | 0.30 s | 1.013 s | iron_shovel |
| **stone** | 0.8 s | 0.100 s | 0.80 s | 2.700 s | iron_pickaxe |
| **bedrock** | — | — | — | — | unbreakable (`allowed_tools` empty) |
| **water** | — | — | — | — | not minable (LIQUID; flow only) |

`mining_time_seconds` lives in each `assets/voxels/materials/*.tres`
file — designers tune values directly in the inspector.

## Tool mismatch (3× penalty)

`allowed_tools` is the list of PREFERRED manual tools for the
material. Equipping a tool from the list mines at the per-material
baseline (1.0× — table above). Equipping any other manual tool
still works but mines at **3× the baseline**, simulating that the
tool is wrong for the job:

| Tool ↓ \ Material → | sand / dirt / grass | stone | bedrock |
|---|---|---|---|
| **iron_shovel** | 1.0× ✓ preferred | **3.0× slow** | blocked |
| **iron_pickaxe** | **3.0× slow** | 1.0× ✓ preferred | blocked |
| **iron_axe** | 3.0× slow | 3.0× slow | blocked |

So a shovel on a stone wall takes ~2.4 s for a 2×2×2 swing
(0.8 × 1.0 × 3 = 2.4) instead of the pickaxe's 0.8 s. A pickaxe
on a grass tile takes ~0.9 s instead of the shovel's 0.3 s. The
player can always make progress with whatever they have, just
slowly when the match is wrong.

Bedrock's `allowed_tools` is empty (`[]`), which is the canonical
"no tool can mine" signal — the swing is blocked entirely, the
multiplier doesn't apply.

When wood materials (logs, planks) land, their preferred tool will
be `iron_axe`. Until then, the axe is always wrong-tool against
existing materials and incurs the 3× penalty in every direction.

The penalty multiplier is `EditToolHandler.WRONG_TOOL_SPEED_MULTIPLIER`
(currently 3.0). Tune there if the gradient feels too punishing or
too generous.

---

## Adding a new material

When you create a new `VoxelMaterial.tres`, you only set
`mining_time_seconds` — the volume scaling is automatic.

**Pick the value as the time you want a 2×2×2 (8-voxel) swing to take.**
Don't think in per-voxel terms; think "how long should one normal
swing feel against this material?"

Suggested baseline ranges by toughness tier:

| Tier | Example materials | `mining_time_seconds` |
|---|---|---|
| Soft / loose | sand, snow, leaves, fresh ash | 0.15 – 0.25 s |
| Earth | dirt, grass, clay, mud | 0.25 – 0.40 s |
| Soft stone | sandstone, chalk, pumice | 0.50 – 0.70 s |
| Hard stone | granite, basalt (current "stone") | 0.70 – 1.00 s |
| Soft wood | pine, fresh log | 0.50 – 0.80 s |
| Hard wood | oak, ironwood | 1.00 – 2.00 s |
| Iron ore | unrefined iron ore | 1.50 – 2.00 s |
| Steel ore | unrefined steel ore | 2.50 – 3.50 s |
| Adamant ore | the lore's hardest material | 4.50 – 6.00 s |

These are 2×2×2 baselines. The 1×1×1 and 3×3×3 swings derive from
them automatically:

| Material baseline | 1×1×1 swing | 3×3×3 swing |
|---|---|---|
| 0.20 s | 0.025 s | 0.675 s |
| 0.30 s | 0.038 s | 1.013 s |
| 0.50 s | 0.063 s | 1.688 s |
| 0.80 s | 0.100 s | 2.700 s |
| 1.00 s | 0.125 s | 3.375 s |
| 1.50 s | 0.188 s | 5.063 s |
| 2.00 s | 0.250 s | 6.750 s |
| 3.00 s | 0.375 s | 10.125 s |
| 5.00 s | 0.625 s | 16.875 s |

**Sanity-check rule**: a 3×3×3 swing on the toughest mineable
material in the game shouldn't exceed ~20 s. Anything beyond that
makes a held LMB feel broken. If the lore wants something tougher
(adamant), gate it behind a higher tool tier so the *effective*
time at endgame stays tractable.

### Tool tier scaling (planned, not yet wired)

When tool tiers land (Common / Quality / Masterwork — see
`design/INVENTORY_AND_EQUIPMENT_SYSTEM.md`), they will divide the
material's swing time by a tool-tier multiplier:

| Tool tier | Multiplier | Effective stone (3×3×3) |
|---|---|---|
| Common | 1.0× | 2.70 s |
| Quality | 0.7× | 1.89 s |
| Masterwork | 0.5× | 1.35 s |

This pass is hooked into `EditToolHandler._tick_held_action` after
the volume scaling — keep the tool tier multiplier as a single
multiplicative factor so the table above stays a clean reference.

### Crafting skill XP (already wired)

`EditToolHandler` awards XP per successful swing regardless of
volume:

| Tool | Sub-skill | XP / swing |
|---|---|---|
| `iron_pickaxe` | mining | 5 |
| `iron_axe` | felling | 8 |
| `iron_shovel` | excavation | 2 |

XP does NOT scale with volume — a 1-voxel swing and a 27-voxel swing
both grant the flat tool-specific value. Designers may want to revisit
this if endgame skill grinding becomes too easy at 3×3×3, but for now
it keeps the system simple and rewards the intent of the swing
(harvest one resource event = one XP grant).

---

## Cross-references

- `scripts/EditToolHandler.gd` → `_tick_held_action` — runtime
  implementation. Volume multiplier applied as
  `mine_secs = material.mining_time_seconds * (N³) / 8.0`.
- `scripts/EditToolHandler.gd` → `_compute_carve_box` and
  `MiningAnchor` enum — the carve-box positioning helper that
  handles both DEPTH_BIASED (default — bias the box into the
  terrain along the surface normal so a 3×3×3 against a wall is 27
  terrain voxels, no air slab) and CENTERED (symmetric box, aim
  point in the middle).
- `scripts/Settings.gd` → `mining_volume_anchor` field — player's
  chosen anchor mode, set via the SETTINGS overlay's MINING ANCHOR
  cycling button. Persisted in `user://settings.json`.
- `scripts/VoxelMaterial.gd` — `mining_time_seconds` field with the
  per-material baseline.
- `design/3D_VOXEL_MIGRATION.md` → "Voxel Material System" — how
  materials are authored as `.tres` resources and registered.
- `design/SKILLS_AND_PROGRESSION.md` → Crafting → Mining sub-skill —
  XP grants per swing.
