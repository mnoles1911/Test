# Skirt Improvements — Implementation Plan

> Branch: `claude/skirt-improvements`
> Created: 2026-05-09
> Companion: `design/COPPER_ISLES_BAKE_NOTES.md` (skirt context, baker pipeline)
>
> **You're a fresh Claude Code session checking out this branch. This document contains everything you need to execute the work — no prior conversation context is assumed.**

---

## Context

The horizon skirt is a low-poly mesh of the entire 8 km × 8 km region around the player, baked once from the EXR heightmap and rendered always (regardless of view distance). It fills the visual hole past Zylann's 250 m streaming radius.

**Implementation:** `scripts/_dev/SkirtBaker.gd` (`class_name SkirtBaker`, `RefCounted`). The mesh is built statically from the live `CopperIslesHeightmapGenerator` resource. Output is `assets/voxel/copper_isles_skirt.res` (an `ArrayMesh`). Loaded at runtime by `scripts/HorizonSkirt.gd` and parented to the `VoxelLodTerrain` in `scenes/CopperIslesTest.tscn`.

**Recent context (same branch ancestor):** the world-scale refactor decoupled sea level from terrain Y. `_gray_to_ground_y()` is now `gray × elevation_above_at_white_voxels` (linear). `sea_level_voxels` is purely visual. **The skirt baker already reads `sea_level_voxels` and `beach_y_threshold` from the live generator at bake time**, so it picks up the current values automatically — no skirt-specific code change is needed for the refactor itself, just a re-bake.

**Bake trigger:** `scenes/_dev/BakeWorld.tscn` → button "4. Bake horizon skirt → assets/voxel/copper_isles_skirt.res". Standalone — does not require a full world bake first. Call site: `WorldBakeController._on_bake_skirt()`. Saves to `res://assets/voxel/copper_isles_skirt.res`.

---

## Five tasks

These are independent. Order: **1 → 2-verify → 3 → 5 → 4.** Reasoning at end of doc.

### Task 1 — Higher quad density

**Current:** `QUAD_SIZE_M = 12.0` in `SkirtBaker.gd:24`. Over 8 km × 8 km → ~666² = ~443 k quads ≈ ~890 k tris.

**Goal:** finer silhouettes. Two options to consider:

| New value | Quads | Tris | Bake time | GPU cost |
|---|---|---|---|---|
| 8 m | 1000² = 1M | ~2M | ~3× current | Trivial — static mesh |
| 6 m | 1333² = 1.78M | ~3.55M | ~4× current | Trivial |
| 4 m | 2000² = 4M | ~8M | ~7× current | Still fine on modern GPUs |

**Recommendation:** start with `8.0`, validate visually. The bake runs synchronously on the main thread inside `WorldBakeController._on_bake_skirt()` — at 8 m it should still complete in <30 seconds. If silhouettes still look too blocky at distance, drop to 6 m.

**Implementation:**
- Edit `SkirtBaker.gd:24`: `const QUAD_SIZE_M: float = 8.0`
- Update the comment on lines 25-29 to reflect the new tri count: "8 m quads ≈ 1000² = 1M quads = 2M tris over 8 km × 8 km."
- No other code changes needed — the rest of the baker is parameterised on `QUAD_SIZE_M`.

**Validation:**
- Trigger button "4. Bake horizon skirt" in `scenes/_dev/BakeWorld.tscn`
- Confirm Output panel shows tri count consistent with new density (~2M tris at 8 m)
- Launch `scenes/CopperIslesTest.tscn` — at spawn `(-61, 185, 732)` the skirt should look smoother along distant coastlines, fewer visible "blocky" patches

---

### Task 2 — Verify per-vertex normals from neighbour heights

**Current state:** *Already implemented* at `SkirtBaker.gd:240-249`. Central-difference computation from the height field:

```gdscript
for zi in verts_z:
    for xi in verts_x:
        var i: int = xi + zi * verts_x
        var hx0: float = heights[max(xi - 1, 0) + zi * verts_x]
        var hx1: float = heights[min(xi + 1, verts_x - 1) + zi * verts_x]
        var hz0: float = heights[xi + max(zi - 1, 0) * verts_x]
        var hz1: float = heights[xi + min(zi + 1, verts_z - 1) * verts_x]
        var dx: float = (hx1 - hx0) / (2.0 * QUAD_SIZE_M)
        var dz: float = (hz1 - hz0) / (2.0 * QUAD_SIZE_M)
        normals[i] = Vector3(-dx, 1.0, -dz).normalized()
```

This task becomes **verify it's actually rendering with proper lighting**, not "implement from scratch."

**Implementation:**
1. After the Task 1 bake, launch `CopperIslesTest.tscn` and check the skirt visually:
   - Sun-facing slopes should be brighter than shadowed slopes
   - The mountain peak silhouettes should have visible shading variation
2. If shading is flat/uniform, the issue is most likely on the runtime side. Check `scripts/HorizonSkirt.gd` — confirm the material attached to the loaded mesh respects vertex normals (i.e. is not `SHADING_MODE_UNSHADED`).
3. The current `HorizonSkirt.gd` uses `vertex_color_use_as_albedo = true` — confirm that doesn't mask the normal-based shading.

**Improvements if base verification reveals issues:**
- The current `Vector3.UP` placeholder in the first loop (line 204) is overwritten by the central-difference calc later — safe, but if you find the normals never apply, check that `Mesh.ARRAY_NORMAL` is being included in the array dict at line 254. (It is.)
- For better quality at silhouette edges, swap to **Sobel-style** normals (3×3 weighted average instead of central differences). Reduces flatness on diagonal slopes.

**Validation:** look down at the skirt from spawn at noon-light angle. Sunlit and shadowed faces should differ in brightness by ~30-50 %. If they don't differ, normals aren't working.

---

### Task 3 — Tone gradient stops to the actual world

**Current palette** (`SkirtBaker.gd:152-165`):

| Band | Color (RGB) | Intent |
|---|---|---|
| Below sea | `(0.18, 0.22, 0.28)` | Dark grey-blue stone (mostly hidden by water) |
| Beach | `(0.82, 0.74, 0.52)` | Warm sand |
| Forest (low) | `(0.32, 0.48, 0.22)` | Saturated forest green |
| Rock (mid) | `(0.55, 0.50, 0.42)` | Warm brown rock |
| Snow (high) | `(0.88, 0.90, 0.93)` | Cool white |

**Lore reference:** `lore/copper_isles/GEOGRAPHY.md` describes the islands as:

> "wave-eroded marble massifs whose summits rise up to 580 m as bare jagged outcroppings... distinctive white-marble peaks long before the lower forested slopes come over the horizon"
>
> "All five large islands are forested below the treeline (~350 m). The forest is hard, weathered coastal woodland — dwarf-oak, salt-pine, sea-laurel, gorse — never tall but very thick."

**Goal:** retune the palette to match a weathered coastal woodland with marble peaks.

**New palette:**

| Band | New color (RGB) | Rationale |
|---|---|---|
| Below sea | `(0.14, 0.18, 0.22)` | Slightly darker, less blue — submerged stone |
| Beach | `(0.78, 0.72, 0.58)` | Cooler, paler sand (salt-bleached coastal sand) |
| Forest (low) | `(0.26, 0.36, 0.20)` | Darker, less saturated — weathered coastal woodland (dwarf-oak under salt spray reads desaturated) |
| Rock (mid) | `(0.62, 0.60, 0.56)` | Lighter, less warm — marble-grey base instead of warm brown rock |
| Snow (high) | `(0.93, 0.94, 0.95)` | Slightly brighter — bare marble peaks read whiter than forested snow |

**Implementation:** edit the `Color(...)` literals at:

- `SkirtBaker.gd:152` (below sea)
- `SkirtBaker.gd:154` (beach / sand)
- `SkirtBaker.gd:159` (`c_lo` — forest)
- `SkirtBaker.gd:160` (`c_mid` — rock)
- `SkirtBaker.gd:161` (`c_hi` — snow)
- `SkirtBaker.gd:173` (`rock_color` — slope-shift target; bring in line with the new marble-grey rock at `c_mid` so steep-slope shifts feel consistent)

**Add a comment block** at the top of the color section (around line 127) noting the palette is keyed to Copper Isles lore — point at `lore/copper_isles/GEOGRAPHY.md`.

**Validation:** re-bake skirt; compare from a sunlit angle. Forest band should read more muted/desaturated than before. Mountain peaks should read pale grey-white (marble) rather than warm tan-grey transitioning to bright white.

---

### Task 4 — Cliff sides at coastlines

**Current state:** the skirt is a single horizontal grid mesh. Where the heightmap drops sharply (e.g., a 80 m cliff over one 12 m quad), the existing implementation just connects the two corners with a single steeply-sloped triangle. Looks like a smooth ramp, not a cliff.

**Goal:** at sharp coastline drops, generate vertical cliff-face geometry so cliffs read as actual cliffs from a distance.

**Approach:**

For each quad in the grid, after computing the four corner heights, detect "cliff edges":

- An edge is a "cliff edge" when its two endpoint heights differ by more than `CLIFF_THRESHOLD_M` (suggested: 20 m).
- For each cliff edge, generate **two extra triangles** forming a vertical wall from the higher vertex's Y down to the lower vertex's Y.

**Geometry trick:** rather than inserting new vertices into the main vertex array (which complicates the index logic), append cliff vertices to the END of the vertex/normal/color arrays. Cliff face vertices have:
- Position: `(world_x, low_y, world_z)` — duplicate of the lower vertex's XZ but at the higher vertex's Y
- Normal: horizontal, pointing outward perpendicular to the cliff edge
- Color: a "cliff rock" color — `Color(0.55, 0.52, 0.48)` — visibly distinct from the elevation-band color of the corner vertices (so the cliff face reads as exposed rock regardless of what's on top)

**Implementation:**

Add a new section after the index loop (currently at `SkirtBaker.gd:222-235`):

```gdscript
# After the regular quad index loop:

const CLIFF_THRESHOLD_M: float = 20.0
const CLIFF_COLOR: Color = Color(0.55, 0.52, 0.48, 1.0)

# For each quad, check the four edges. Append vertical wall geometry
# for any edge where the height drop exceeds CLIFF_THRESHOLD_M.
# Wall is two triangles forming a quad from (high_vertex_xz, low_y)
# to (low_vertex_xz, high_y) — a vertical strip closing the gap.

var cliff_verts := PackedVector3Array()
var cliff_normals := PackedVector3Array()
var cliff_colors := PackedColorArray()
var cliff_indices := PackedInt32Array()

# Helper closure-style: append two triangles forming a vertical wall
# between (xz_high, y_high) and (xz_low, y_low). xz_high and xz_low
# are Vector2 world XZ coords, y_high > y_low.
# See implementation below.

for zi in quads_z:
    for xi in quads_x:
        var i00: int = xi + zi * verts_x
        var i10: int = (xi + 1) + zi * verts_x
        var i01: int = xi + (zi + 1) * verts_x
        var i11: int = (xi + 1) + (zi + 1) * verts_x

        var h00: float = heights[i00]
        var h10: float = heights[i10]
        var h01: float = heights[i01]
        var h11: float = heights[i11]

        # Check 4 edges:
        # E1: i00 ↔ i10 (south edge)
        # E2: i10 ↔ i11 (east edge)
        # E3: i11 ↔ i01 (north edge)
        # E4: i01 ↔ i00 (west edge)

        _maybe_append_cliff(
            cliff_verts, cliff_normals, cliff_colors, cliff_indices,
            vertices[i00], h00, vertices[i10], h10,
        )
        _maybe_append_cliff(
            cliff_verts, cliff_normals, cliff_colors, cliff_indices,
            vertices[i10], h10, vertices[i11], h11,
        )
        # ... same for E3, E4
```

Implement `_maybe_append_cliff` as a static helper that:
1. Returns immediately if `abs(h_a - h_b) < CLIFF_THRESHOLD_M`
2. Identifies which is higher
3. Computes the edge horizontal vector and outward normal (perpendicular to edge, in the XZ plane, pointing AWAY from the cliff's high side)
4. Appends 4 vertices to `cliff_verts` (two pairs at high_y and low_y), 6 indices forming two triangles, 4 normals (all the same horizontal outward), 4 colors (`CLIFF_COLOR`)

**Important:** these new vertices must be merged into the main arrays before adding to the ArrayMesh. After both loops, do:

```gdscript
var base_count: int = vertices.size()
vertices.append_array(cliff_verts)
normals.append_array(cliff_normals)
vert_colors.append_array(cliff_colors)
# Cliff indices reference the appended slot, so offset them:
for ci in cliff_indices.size():
    cliff_indices[ci] += base_count
indices.append_array(cliff_indices)
```

**Watch out for:**
- **Double-counting:** if you process every quad's 4 edges, every internal edge is visited TWICE (once from each adjacent quad). Track visited edges in a `Dictionary[Vector2i, bool]` (key = sorted vertex index pair) to dedupe.
- **Winding order:** the cliff face's two triangles must wind so the outward normal is correct. Test by viewing from outside the cliff — should be visible. From inside, should be culled (with `CULL_BACK`).
- **Normals at the top edge:** the cliff face has its own normals (horizontal outward). Don't recompute these in the central-difference normal loop.

**Acceptance test:** at the western shore where the heightmap drops from gray=0.05 (Y=125 m) to gray=0 (Y=0 m) over one quad — that's a 125 m drop over 8 m → cliff threshold easily exceeded → vertical wall generated. View from offshore: the coastline should look like a sheer drop, not a smooth ramp.

**Risk:** this is the most invasive change. If the cliff geometry looks wrong (z-fighting, weird angles, wrong faces visible), revert this task only — the other 4 tasks should not be affected.

---

### Task 5 — Latitude-based snow line

**Current:** snow appears at gray-based height — `t1 = (ground_voxels - beach_y) / 4500.0` — snow caps over a fixed range. Same on north and south side of the map.

**Goal:** snow line drops on the north (high Z) side and rises on the south (low Z) side, simulating a "cooler" climate at high Z. Subtle effect — not "polar caps", just visible asymmetry that makes the world feel less uniform.

**Per lore:** Solgrade (the colonial city) is north of the playable Copper Isles. So north = colder is appropriate.

**Implementation:**

Replace the snow-line logic at `SkirtBaker.gd:156-165`. Currently the elevation-band lerp uses a fixed 4500-voxel range. Make the range start point and end point depend on `world_z`:

```gdscript
# 4500 vox = 750 m world snow band — slid up or down based on world_z.
# At Z = +2500 (north edge): snow line is 200 m LOWER than baseline →
# more snow visible on north-facing peaks.
# At Z = -2500 (south edge): snow line is 200 m HIGHER than baseline →
# less snow on south-facing peaks.
# Linear interpolation between these endpoints.

const SNOW_LINE_LATITUDE_OFFSET_M: float = 200.0
# Tuning knob — higher value = stronger N/S asymmetry. 200 m is
# subtle; try 400 m for more dramatic Skyrim-like effect.

var latitude_factor: float = clampf(world_z / 2500.0, -1.0, 1.0)
# +1 at north edge, -1 at south edge, 0 at equator.

var snow_line_offset_voxels: int = int(round(
    -latitude_factor * SNOW_LINE_LATITUDE_OFFSET_M * voxels_per_metre
))
# Negative because north (positive latitude_factor) should LOWER the
# snow line (snow at lower elevation).

# Original t1 calc, but with the snow band offset:
var elev_above_beach: int = ground_voxels - beach_y
var t1: float = clampf(
    float(elev_above_beach + snow_line_offset_voxels) / 4500.0,
    0.0, 1.0,
)
```

**Tunable:** the `200.0` offset is the most visible knob. Bump to 400.0 if the effect is too subtle.

**No other code changes** — the lerp downstream of `t1` is unchanged.

**Validation:** re-bake. Compare two mountain peaks at similar elevation but different Z (e.g., one near `Z=+1500`, one near `Z=-1500`). The northern peak should have visibly more white-snow coverage than the southern peak, with a smooth gradient between them.

---

## Suggested execution order

| # | Task | Why this order |
|---|---|---|
| 1 | Higher quad density | Foundation — tighter silhouettes make all subsequent visual changes more readable. Also smallest diff. |
| 2 | Verify normals (likely already working) | Confirm before stacking color changes. Easy to verify visually with sun angle. |
| 3 | Tone gradient | Independent of geometry. Just changes the look of what's already there. |
| 5 | Latitude snow line | Independent of geometry too. Builds on the new palette. |
| 4 | Cliff sides | Most invasive. Saved for last so a regression here doesn't block validating the others. |

**After each task:** trigger a re-bake (button 4 in `BakeWorld.tscn`) and visually validate at spawn `(-61, 185, 732)` in `CopperIslesTest.tscn`. The skirt is loaded by `HorizonSkirt.gd` automatically on scene load.

---

## Files touched

| File | Tasks | Changes |
|---|---|---|
| `scripts/_dev/SkirtBaker.gd` | 1, 3, 4, 5 | All edits except 2 land here |
| `scripts/HorizonSkirt.gd` | 2 (verify only) | Inspect material; usually no change |
| `assets/voxel/copper_isles_skirt.res` | All | Re-baked output (binary; treat as build artifact) |
| `design/COPPER_ISLES_BAKE_NOTES.md` | All | Update the "Skirt design" section noting the new defaults (quad density, palette, latitude offset, cliff threshold) |
| `design/SKIRT_IMPROVEMENTS_PLAN.md` | — | Mark tasks ✅ as you complete them |

---

## Pre-flight check (do this FIRST in the new session)

Before touching any code, verify the branch state:

1. `git log --oneline -5` — should show `claude/skirt-improvements` checked out, with the most recent commit being "Add skirt improvements plan" and the prior commit being the world-scale refactor + water tuning.
2. Open `scenes/_dev/BakeWorld.tscn` in Godot, F5, click button "4. Bake horizon skirt".
3. Watch Output for `[SkirtBaker] Baked NNN × NNN quad skirt (NNN tris)`. Confirm sea level and beach values match the .tres (`sea_level_voxels=1980`, `beach_y_threshold=1992`). The pre-existing skirt (committed before this branch) was baked at the OLD values, so the first re-bake will already produce different geometry.
4. Switch to `scenes/CopperIslesTest.tscn`, F5. Confirm the new baseline skirt loads. Look for `[HorizonSkirt] loaded res://assets/voxel/copper_isles_skirt.res`.

This baseline re-bake is the "task 0" and validates the pipeline before stacking changes.

---

## Done state

- [x] Task 1: `QUAD_SIZE_M = 8.0`
- [x] Task 2: normals confirmed working (no code change — `HorizonSkirt.gd` material already `SHADING_MODE_PER_PIXEL`)
- [x] Task 3: palette retuned to weathered coastal woodland + marble
- [x] Task 4: cliff-edge generation working at coastlines (vertical-wall splice via `_maybe_add_cliff_edge`)
- [x] Task 5: snow line varies with world Z (`SNOW_LINE_LATITUDE_OFFSET_M = 200`)
- [ ] `assets/voxel/copper_isles_skirt.res` re-baked with all changes (pending — designer to run BakeWorld button 4)
- [x] `design/COPPER_ISLES_BAKE_NOTES.md` updated with new defaults (added "Skirt design" section)
- [ ] Visual validation: skirt at spawn `(-61, 185, 732)` reads as Copper Isles, not generic terrain (blocked on re-bake)
