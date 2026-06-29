# Overnight session handoff — 2026-06-21

Plain-English summary of what I built while you slept, what's running, and your
wake-up checklist. (Companion to `UE5_ROAMING_CLIPMAP.md` and `BAKE_PIPELINE_GUIDE.md`.)

> ## 🔄 UPDATE 2026-06-22 — read this FIRST (it changes the plan below)
>
> A big bug turned up after this handoff was written, plus the approach shifted. The short version:
>
> 1. **The "checkerboard gaps" mystery is solved — it was a mesher bug, now fixed.** The far terrain
>    had a regular grid of holes. The cause: the mesher only ever built the first 32 cells of any
>    tile, so the big baked tiles (up to 96 cells across) came out mostly invisible. The fix is in
>    `Source/MiraThalVoxel/Private/Core/GreedyMesher.cpp` — it now meshes each tile's real size.
>    Live editable chunks are unchanged. **Status: fix written, the editor binary rebuilt, and the
>    headless test harness is GREEN** (a new "oversized slab" case in `tests/standalone/test_mesher.cpp`
>    locks it so it can't come back). See `BAKE_PIPELINE_GUIDE.md` for the full plain-English writeup.
>
> 2. **Consequence: every bake made before the fix is wrong.** The 10 cm bake described below (and the
>    old `L1` / `L2` layers) were baked by the buggy mesher, so they all need re-baking. Don't trust
>    the "10cm layer is done" section below — it predates the fix.
>
> 3. **The active approach now is a 40 cm GEO-MERGED bake.** Rather than fight the 10 cm scale right
>    away, the current plan is a single 40 cm tier baked with `-GeoMerge` (one fused Nanite mesh per
>    region instead of thousands of tiny tiles). It's the cleanest thing to wire up and look at next.
>
> 4. **There's a ready-made wiring script:** `Saved/wire_40cm_crust.py`. Run it through the mcp-unreal
>    bridge (`execute_script`, world `editor`) with the editor open, after the bake finishes and before
>    hitting Play. It points the `MiraCrust_L1` actor at `/Game/VoxelBake/MiraStreamTest_40cm/Manifest`,
>    sinks the crust below the surface so the near 10 cm voxels render on top (`VerticalBiasVoxels = 6`),
>    sets the band to cover from under the player (`InnerChunks = 0`) out to ~2.2 km (`OuterChunks = 700`)
>    with gentle streaming (`MaxOpsPerTick = 3`), and parks the other two crust actors (which still point
>    at the broken pre-fix layers). Tune the values at the top of the script and re-run to iterate on the
>    seam/coverage. The reasons for `Inner = 0` and the sink are written in the script's own comments:
>    geo-merge regions are large (~307 m), so a non-zero inner band would leave a hole under the player.
>
> **Everything from here down was true as of the overnight 2026-06-21 session and is kept for the
> record, but items 1–4 above supersede it where they conflict.**

---

## TL;DR — read this first (everything below is DONE ✅)

1. **The 10cm whole-map bake FINISHED.** ~6.3 hrs, **243,085 tiles**, region-packed into
   **4,336 files** (6.5 GB) at `/Game/VoxelBake/MiraStreamTest_10cm`. Zero out-of-memory
   crashes across all 138 shards once I fixed the shard sizing (see "Memory" below).
2. **Both code features are BUILT, clean, and tested.** C1 geometry-merge + C2 skip-Nanite
   compiled with **0 errors**, the green-gate harness is **ALL HARNESSES GREEN** (incl. the
   geometry-merge math test), and I **smoke-tested C1 headlessly** — a small `-GeoMerge`
   bake fused 25 regions with 0 failures and the correct region-granular manifest span.
3. **Nothing I did changed existing behavior.** Both new features are OFF by default.
4. **What's left for YOU:** wire the new 10cm layer into a crust actor and fly around to
   confirm it looks right (the one thing I can't do headless). See "Still needs YOU" below.

---

## The 10cm layer — done, and how to use it

The bake finished clean: **243,085 tiles → 4,336 region files (6.5 GB)** at
`/Game/VoxelBake/MiraStreamTest_10cm` (with a `Manifest.uasset` index). To see it in game:
open `MiraStreamTest.umap`, pick (or add) a `VoxelNaniteCrust` actor, point its **Manifest**
at `/Game/VoxelBake/MiraStreamTest_10cm/Manifest`, and set its Inner/Outer chunk band for
the tier you want it to cover. Then PIE and fly out — see "Still needs YOU" for the check.

(If you ever need to re-bake it: `.\Rebake-Terrain.bat` → 10cm. It's safe to re-run; it
overwrites. It now uses the corrected memory-safe shard size automatically.)

**Memory — two fixes tonight (this is why the bake restarted a few times):**
1. **Job count.** This machine is 64 GB RAM + a tiny 4 GB Windows pagefile = a ~68 GB
   hard "commit limit." Each bake process needs ~11 GB, so 7 jobs (77 GB) blew the limit
   ("paging file too small"). Capped to 4 + staggered launches.
2. **Shard size (the real one).** The bake splits the map into shards run 4-at-a-time.
   Region-packing holds ALL of a shard's built meshes in memory until that shard's final
   save, so peak RAM scales with *tiles-per-shard*. The old default (6000 tiles/shard) was
   never actually exercised — the 80cm bake only had ~1200 tiles/shard. At 10cm, 4 × 6000
   ran the machine out of memory. I lowered it to **~2000 tiles/shard** (`$SHARD_TILES` in
   `Rebake-Terrain.ps1`), which keeps 4 lanes well under the limit.

**Want faster bakes?** Raise the Windows pagefile to ~64 GB (System → Advanced →
Performance → Virtual memory). Then you can raise `-Jobs` and `$SHARD_TILES` and 10cm drops
from ~6 hrs toward ~3. The pagefile is the single biggest lever and the only thing blocking it.

---

## Build + tests — DONE (recorded here for the log)

I already did this after the bake freed the binary:
- **Rebuilt `MiraThalEditor`** — compiled `VoxelCrustBaker.cpp`, `VoxelCrustBakeCommandlet.cpp`,
  `VoxelNaniteBaker.cpp` and linked `MiraThalVoxelBake.dll` in 53s, **0 errors**.
- **Green gate:** `tests/standalone/build.sh` → **ALL HARNESSES GREEN** (incl. `test_regionmerge`).
- **C1 smoke test:** a headless `-GeoMerge` bake fused 25 regions, `failed=0`, manifest span
  = RegionSize×TileSpan (region-granular, as designed). Cleaned the throwaway test layer after.

So the editor binary on disk now HAS C1 + C2. Nothing for you to build.

---

## C1 — Geometry merge (NEW, written tonight, default OFF)

**The problem it solves:** region *packing* (what tonight's 10cm bake uses) groups many
tiles into one *file*, so it fixes the "file wall" (~270k files → ~4k). But each tile is
still its own mesh *asset*, and Unreal's asset registry is keyed per-asset — so a shipped
10cm map still has ~270k assets, which chokes the cook. Geometry *merge* is the heavier
fix for shipping: it **fuses all tiles in a region into ONE mesh + ONE manifest entry**,
collapsing both file AND asset count by ~64×.

**The elegant part:** the runtime crust streamer needs **zero changes**. A merged region
is just a bigger "tile" — the baker sets the manifest's `TileSpanVoxels` to one region's
width, and the existing streamer bands at region granularity automatically. The pure fuse
math (`Source/MiraThalVoxel/Public/Core/RegionMerge.h`) was already built + harness-tested;
tonight I wired it into the baker (`VoxelCrustBaker.cpp`) behind a flag.

**How to use it** (after building):
```powershell
.\Rebake-Terrain.ps1 -CubeCm 10 -Name MiraStreamTest_10cm_merged -GeoMerge
```
`-GeoMerge` forces region packing on and fuses each region. **Tradeoff:** coarser
streaming — a whole region (e.g. 8×8 tiles) loads/unloads as one unit, so use it for the
FAR/coarse crust tiers, not the near editable voxels. For just *testing* it renders right,
do a tiny ring first (much faster): add `-Jobs 1` and it'll bake the central regions.

**Files touched:** `VoxelCrustBaker.cpp` (accumulate per-region + fuse-and-save pass),
`VoxelCrustBaker.h` (`bGeometryMerge` setting), `VoxelCrustBakeCommandlet.cpp` (`-GeoMerge`
parse), `Rebake-Terrain.ps1` (`-GeoMerge` switch). A subagent static-reviewed the whole
change against signatures, move-semantics, the merge-offset frame, and the off-path — clean.

---

## C2 — Skip Nanite on coarse tiers (coded earlier, default auto)

Nanite's hierarchy build is the per-tile bake bottleneck. Coarse far tiles (few triangles)
don't need sub-pixel LOD, so building them as **plain static meshes** is much faster. The
baker takes `-Nanite=0` (plain) / `-Nanite=1` (Nanite), and the bake tool auto-picks: OFF
for ≥1.6m cubes, ON for finer. Nothing for you to do — it's wired into the menu's presets.

---

## Still needs YOU (editor / PIE — I can't drive these headless)

- **B1 — prune orphan crust tiles:** a handful of baked tiles sit outside the map after the
  bounds fix. Needs the editor + a Python pass (no PIE). I'll do this with you next session.
- **Roaming visual check:** spawn at a few RANDOM points, fly out — confirm the far terrain
  is cubic crust all the way to the coast (not the old smooth vista, now retired), and that
  the crust→live-voxel seam holds with no holes. This is the real proof the 10cm layer works.
- **Material flag:** `M_VoxelTerrainV2` needs **Used with Nanite** ticked in its material
  details (the Python API doesn't persist this one). Renders fine in-editor regardless.

---

## What I did NOT touch (per your direction)

- No water / depth-clip changes.
- No commits (everything is staged in the working tree; you commit when ready).
- Skip-Nanite was wired as the safe auto-preset, not forced on.
