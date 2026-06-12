# Mining Time Scaling

How long it takes the player to break voxels with a manual tool
(pickaxe / shovel / axe), as a function of:

1. **The voxel material** — each `VoxelMaterial.tres` carries a
   `mining_time_seconds` baseline.
2. **The carve volume** — the player cycles three named presets
   (**Small** 1³ / **Medium** 3³ / **Full** N³, N = `swing_carve_voxels_per_side`,
   today 5) with the scroll wheel while a manual tool (pickaxe / shovel /
   axe) is equipped.

This document is the canonical reference for both. The formula and
material tables below are what `EditToolHandler._tick_held_action`
implements at runtime.

---

## The formula

```
per_voxel_seconds[v] = v.material.mining_time_seconds × tool_multiplier(v)
baseline_voxels      = BASELINE_VOLUME_M3 × VoxelScale.VOXELS_PER_METER³
swing_seconds        = max(per_voxel_seconds across all voxels in carve box)
                       × (voxel_count / baseline_voxels)
```

where `voxel_count` is `N³` (N = the carve volume side length, currently
1 / 3 / 5 for Small / Medium / Full) and `tool_multiplier(v)` is **1.0**
when the equipped manual tool is in that voxel's material's
`allowed_tools` list (the "preferred tools"), or
**`WRONG_TOOL_SPEED_MULTIPLIER` = 3.0** otherwise.

### Why the baseline is a physical VOLUME, not a voxel count (2026-06-12)

The multiplier used to be a literal `N³ / 8` — i.e. "8 voxels = one
normal swing". That `8` was authored back at **6 voxels per metre**,
where 8 voxels is a physical hole of `8 / 6³ = 8/216 ≈ 0.037 m³`.

When the project moved to **10 vox/m**, that raw `8` silently became
wrong: the *same physical hole* now contains `0.037 × 10³ ≈ 37` voxels,
so dividing by `8` made every swing ~4.6× too slow (digging the same
real-world chunk counted 4.6× more voxels). The anchor had drifted
because it was stored as a voxel COUNT instead of a physical SIZE.

The fix anchors on **physical volume** and re-derives the voxel count at
the live scale every run:

```
const BASELINE_VOLUME_M3 := 8.0 / 216.0   # the historic anchor:
                                          # 8 voxels at 6 vox/m, 216 vox/m³
baseline_voxels := BASELINE_VOLUME_M3 × VoxelScale.VOXELS_PER_METER³
                # = 8   at 6 vox/m   (unchanged from the original feel)
                # ≈ 37  at 10 vox/m  (today)
```

A "normal swing" is now defined by a **fixed real-world hole size**
(~0.037 m³), so it feels identical at any grid scale, and the formula
**can never silently break again** at a future scale flip — the `scale`
and `mining` headless selectors enforce it.

The constant `BASELINE_VOLUME_M3` and the math live in
`EditToolHandler` (`_tick_held_action`). The XP/skill plumbing,
material tables, and tool-mismatch rules below are unchanged.

The swing time is set by the **slowest material in the carve box**,
not by whichever material happens to be under the aim crosshair.
This means:

- A 3×3×3 box with even one stone voxel takes as long as a pure-stone
  3×3×3 (assuming the equipped tool is preferred for stone).
- The shovel-on-stone or pickaxe-on-grass penalty applies when ANY
  voxel in the box is the wrong-tool material — even if 26 of 27
  voxels are the preferred type.
- The HUD `mining_material_label` shows the slowest material's
  display name (e.g. "STONE" for a grass + stone carve), so the
  player sees what's gating the swing.

Empty `allowed_tools` on any voxel in the box (bedrock) **blocks the
entire swing** — the multiplier doesn't apply, the swing accumulator
stays at zero. Same effect as VoxelEditManager rejecting the carve
for crossing the bedrock floor.

Air voxels (mat_id = 0) contribute nothing to the max — they're skipped.
A box that's entirely air bails immediately (no swing, no progress).

The **baseline** (multiplier = 1.0) is one `baseline_voxels`-sized bite
— a fixed ~0.037 m³ physical hole (`≈ 37` voxels at today's 10 vox/m).
The three presets scale around it (values at 10 vox/m):

| Preset | Side `N` | Voxels removed | Time multiplier |
|---|---|---|---|
| **Small**  | 1 | 1   | **≈ 0.027×** (1 / 37 — fast precision pick) |
| **Medium** | 3 | 27  | **≈ 0.73×**  (27 / 37 — the everyday dig) |
| **Full**   | 5 | 125 | **≈ 3.375×** (125 / 37 — slow bulk dig) |

The **Full = 5³ multiplier (≈ 3.375×) is deliberately identical to what
the old 3³ default felt like at 6 vox/m** (27 / 8 = 3.375) — the physical
bite is the same size, so the feel carries over across the scale flip.

The intent is **risk/reward**: **Small** is fast for precision picking
(carving stairs into a cliff, freeing a single ore vein), **Full** is
slow but high-throughput for bulk volume work (mining out a chamber).
**Medium** is the responsive everyday default the tool boots into.

`Full`'s side length is the `swing_carve_voxels_per_side` export
(default 5), kept as an export so a future better tool tier can raise
the maximum bite without touching the preset code.

---

## Current materials

The pilot four. `mining_time_seconds` is now the **per-voxel** time
(the time the slowest single voxel contributes); the actual swing time
is `per_voxel × multiplier` where the multiplier comes from the preset
table above (Small ≈ 0.027× / Medium ≈ 0.73× / Full ≈ 3.375× at today's
10 vox/m). Assumes the right tool is equipped — multiply by 3 for a
wrong-tool swing (see "Tool mismatch" below):

| Material | `mining_time_seconds` (per voxel) | Small (1³) | Medium (3³) | Full (5³) | Preferred tool |
|---|---|---|---|---|---|
| **sand** | 0.2 s | 0.005 s | 0.146 s | 0.675 s | iron_shovel |
| **dirt** | 0.3 s | 0.008 s | 0.219 s | 1.013 s | iron_shovel |
| **grass** | 0.3 s | 0.008 s | 0.219 s | 1.013 s | iron_shovel |
| **stone** | 0.8 s | 0.022 s | 0.584 s | 2.700 s | iron_pickaxe |
| **bedrock** | — | — | — | — | unbreakable (`allowed_tools` empty) |
| **water** | — | — | — | — | not minable (LIQUID; flow only) |

(Full-swing seconds = `per_voxel × 125 / 37`. They match the old 3³
defaults exactly because Full is the same physical bite the old default
was.) `mining_time_seconds` lives in each `assets/voxels/materials/*.tres`
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

So a shovel on a stone wall has a per-voxel time of ~2.4 s
(0.8 × 3) instead of the pickaxe's 0.8 s — every preset is 3× slower.
A pickaxe on a grass tile is 0.9 s/voxel instead of the shovel's
0.3 s. The player can always make progress with whatever they have,
just slowly when the match is wrong.

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

**`mining_time_seconds` is the PER-VOXEL time.** The swing time then
scales by the preset multiplier (Small ≈ 0.027× / Medium ≈ 0.73× /
Full ≈ 3.375× at 10 vox/m). A handy way to pick the value: the number
you set is almost exactly the **Medium-swing time ÷ 0.73**, or simpler,
just note that a **Full** swing on this material lands at `value × 3.375`
— the same it would have been as a 3³ default before the rescale.

Suggested per-voxel ranges by toughness tier (these are the same
numbers as before — the field still means "how tough is this material",
only the volume multiplier around it changed):

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

These are per-voxel values. The Small / Medium / Full swing times
derive from them automatically (at today's 10 vox/m):

| Per-voxel value | Small (1³) | Medium (3³) | Full (5³) |
|---|---|---|---|
| 0.20 s | 0.005 s | 0.146 s | 0.675 s |
| 0.30 s | 0.008 s | 0.219 s | 1.013 s |
| 0.50 s | 0.014 s | 0.365 s | 1.688 s |
| 0.80 s | 0.022 s | 0.584 s | 2.700 s |
| 1.00 s | 0.027 s | 0.730 s | 3.375 s |
| 1.50 s | 0.041 s | 1.095 s | 5.063 s |
| 2.00 s | 0.054 s | 1.459 s | 6.750 s |
| 3.00 s | 0.081 s | 2.189 s | 10.125 s |
| 5.00 s | 0.135 s | 3.649 s | 16.875 s |

**Sanity-check rule**: a **Full** swing on the toughest mineable
material in the game shouldn't exceed ~20 s. Anything beyond that
makes a held LMB feel broken. If the lore wants something tougher
(adamant), gate it behind a higher tool tier so the *effective*
time at endgame stays tractable.

### Tool tier scaling (planned, not yet wired)

When tool tiers land (Common / Quality / Masterwork — see
`design/INVENTORY_AND_EQUIPMENT_SYSTEM.md`), they will divide the
material's swing time by a tool-tier multiplier:

| Tool tier | Multiplier | Effective stone (Full 5³) |
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

XP does NOT scale with volume — a Small (1-voxel) swing and a Full
(125-voxel) swing both grant the flat tool-specific value. Designers
may want to revisit this if endgame skill grinding becomes too easy at
Full, but for now it keeps the system simple and rewards the intent of
the swing (harvest one resource event = one XP grant).

---

## Cross-references

- `scripts/EditToolHandler.gd` → `_tick_held_action` — runtime
  implementation. Calls `_compute_mixed_volume_mine_secs` to find the
  slowest per-voxel time across the carve box, then multiplies by
  `voxel_count / baseline_voxels` (the physical-volume anchor:
  `baseline_voxels = BASELINE_VOLUME_M3 × VOXELS_PER_METER³`) to get the
  final swing time. The `mining` headless selector pins this math.
- `scripts/EditToolHandler.gd` → `_compute_mixed_volume_mine_secs`
  — slowest-wins scan over the carve box. Reads up to 27 voxels per
  held tick (3×3×3 worst case), per-voxel computes `mining_time_seconds
  × tool_multiplier`, returns the max plus the slowest voxel's
  material (for the HUD label) plus a `blocked` flag if any voxel
  is unmineable.
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
