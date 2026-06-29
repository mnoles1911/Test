# Roaming Clipmap Spec — the concrete numbers for cubic terrain that follows the player

This is the **build-and-test plan** for terrain across the 5 km × 5 km map as the player roams freely.
It is the concrete companion to `CLIPMAP_ARCHITECTURE.md` (which explains *why* we split near/far) and
`UE5_ROAMING_CLIPMAP.md` (tier config history). Read those for the concepts; read **this** for the
exact cube sizes, region counts, band distances, and the knob values to type into the editor.

Everything here is grounded in the real code:
- Live near voxels: `Source/MiraThalVoxel/Public/VoxelWorld.h` (`StreamRadiusChunks`, the LOD tiers).
- Crust streamer: `Source/MiraThalVoxelBake/Public/VoxelNaniteCrust.h` (`InnerChunks`/`OuterChunks`,
  `MaxOpsPerTick`, `VerticalBiasVoxels`, `MaxLiveComponents`, pooling).
- Bake math: `Source/MiraThalVoxel/Public/Core/NaniteBakeTiling.h` (`MAX_COARSE_SIDE`,
  `which_tiles_in_band`).
- Bake pipeline: `Rebake-Terrain.ps1` (how cube size → stride/tileSpan/region; `-GeoMerge`).
- Current live wiring: `Saved/wire_40cm_crust.py`.

---

## 0. The unit cheat-sheet (memorise these — every number below derives from them)

| Thing | Value |
|---|---|
| Voxel size | **10 cm** (10 voxels / metre) |
| 1 chunk | **32 voxels = 3.2 m** (`coords::CHUNK`) |
| Map span | **5 km × 5 km = 50,000 voxels per side**; half-map = 25,000 vox = 2.5 km |
| Live near radius | `StreamRadiusChunks = 64` chunks = **204.8 m** ("the editable bubble") |
| Bake tile formula | `Stride = CubeCm / 10`, `TileSpan = 96 × Stride` voxels (from `Rebake-Terrain.ps1`) |
| Geo-merge region | `-GeoMerge` fuses an **8 × 8 tile** block into ONE mesh + ONE manifest entry |
| Coarse-grid ceiling | `MAX_COARSE_SIDE = 96` — a tile's `TileSpan/Stride` must be ≤ 96 or the bake refuses it |

The `96` in `TileSpan = 96 × Stride` is deliberate: it makes `coarse_side = TileSpan/Stride = 96`,
sitting right at `MAX_COARSE_SIDE`. That's the **largest tile the baker allows**, which means the
**fewest** files. Don't change it without re-reading `NaniteBakeTiling.h`.

---

## 1. THE TIERS — what resolution lives where

Three layers, near to far. Tier 0 is the live engine; tiers 1+ are baked Nanite crust.

### Tier 0 — Live editable 10 cm voxels (the bubble you can dig)
- **Cube:** 10 cm. **Reach:** `StreamRadiusChunks = 64` → **204.8 m** radius around the player.
- This is NOT baked and NOT Nanite — it's our own voxel mesher rebuilding chunks live as you carve.
- Inside this bubble the world *also* runs its own voxel LOD (`bEnableLOD`, on by default): full 10 cm
  out to `Lod0MaxChunks` (8 chunks ≈ 26 m), then 20/40/80/160/320 cm shells out to the bubble edge.
  That internal LOD is the live engine's business; the crust picks up *beyond* the bubble.

### Tier 1 — 40 cm geo-merged crust (the recommended workhorse far tier)
- **Cube:** 40 cm → `Stride = 4`. **Tile:** `TileSpan = 96 × 4 = 384 vox = 38.4 m`.
- **Geo-merge region:** 8 × 8 tiles = `384 × 8 = 3072 vox = 307.2 m` per fused mesh.
- **Region count for the whole map:** `50,000 / 3072 ≈ 16.3` → a **17 × 17 = ~289 region meshes**
  for the entire 5 km map. (Without geo-merge that same tier is `50,000/384 ≈ 130` → ~**17,000 tiny
  tiles** — the "file wall". Geo-merge is the ~60× asset-count cut.)
- This is the **currently wired and tested** tier (`wire_40cm_crust.py`, layer `MiraStreamTest_40cm`).

### Recommendation: **start with a single 40 cm geo-merged tier (Tier 1 only).**
At ~289 merged meshes for the whole map, with the streamer only resident-ing a band of them, a single
40 cm tier covers the entire far view. 40 cm cubes read as crisp blocky terrain near the seam and as a
clean silhouette at distance (Nanite LODs them down to ~1 triangle/pixel). **Ship this first, tune it
in PIE, and only add a coarser tier if the far horizon proves too heavy or too blocky at the edge.**

### Tier 2 (OPTIONAL, add only if needed) — 1.6 m coarse far tier
- **Cube:** 1.6 m → `Stride = 16`. **Tile:** `96 × 16 = 1536 vox = 153.6 m`. Geo-merge region =
  `1536 × 8 = 12,288 vox = 1228.8 m`.
- **Region count:** `50,000 / 12,288 ≈ 4.07` → a **5 × 5 = ~25 region meshes** for the whole map.
- `Rebake-Terrain.ps1` auto-bakes this **plain (non-Nanite)** at ≥160 cm — a coarse static mesh builds
  far faster and needs no sub-pixel LOD at that range. Coverage: the deep background (~1.2–2.5 km out),
  where 40 cm detail is sub-pixel anyway.

A **6.4 m** tier is possible (`Stride 64`, `coarse_side = 96`, region ≈ 4.9 km → the whole map is ~4
regions) but is almost certainly overkill on a 2.5 km-radius map — the 1.6 m tier already reaches the
map edge. Treat 6.4 m as a "if the silhouette band is still too expensive" lever, not a default.

> **Bottom line on tiers:** one 40 cm geo-merged tier (~289 regions) is the plan. A 1.6 m tier (~25
> regions) is the optional second tier for the deep background. Don't bake all three on day one.

---

## 2. THE BANDS — InnerChunks / OuterChunks per tier (1 chunk = 3.2 m)

The streamer loads tiles whose **chunk distance** from the player falls in `[InnerChunks .. OuterChunks]`
(`which_tiles_in_band` in `NaniteBakeTiling.h`). The band follows the player. Here are the values, and
the reasoning — especially the geo-merge granularity problem.

### Tier 1 (40 cm geo-merged): `InnerChunks = 0`, `OuterChunks = 700`
- **Inner = 0 (cover the region under the player too).** A geo-merge region is **307 m** across. If we
  set Inner to the live radius (64 chunks ≈ 205 m) to "start the crust where the voxels end", the
  region the player is *standing in* would be excluded — punching a **307 m hole under the player's
  feet**, because you can't load half a fused region. So Inner = 0: load the player's own region too.
  This is only safe because of the seam fix (§4): that under-foot crust is **sunk below the surface and
  hidden by the live 10 cm voxels**, so you never see it there. This is exactly what `wire_40cm_crust.py`
  does (`INNER = 0`).
- **Outer = 700 chunks ≈ 2.24 km ("as far as you can see").** This is the band *reach*, not the map. It
  is deliberately band-limited: only the regions whose distance is ≤ 700 chunks load, so we don't try to
  resident all ~289 regions at once (that load-burst froze the editor — see §3). On a 2.5 km-radius map,
  700 chunks reaches the far edge from near the centre and most of the way from the rim.

### Tier 2 (1.6 m, if used): `InnerChunks = 0`, `OuterChunks = 800`
- Same Inner = 0 reasoning, but the granularity is even coarser (1.2 km regions), so Inner *must* be 0.
- Push Outer to the map diagonal (~1100 chunks = ~3.5 km) only if you want guaranteed corner-to-corner
  coverage from any spawn; 800 (~2.56 km) covers the common case. With Tier 1 also resident, Tier 2 just
  needs to fill the deep background, so don't over-reach it.

> **Why not a tight inner band like a classic clipmap?** Because geo-merge made the streaming unit a
> whole 307 m region. Fine-grained "load a small patch right at the seam" is impossible once tiles are
> fused. Inner = 0 + the VerticalBias sink is how we live with that. If you ever want a tight inner band,
> you'd have to bake that tier **without** `-GeoMerge` (small per-tile streaming) — and pay the file-wall
> cost (§5). For the far crust that's a bad trade; for the near editable terrain we don't bake at all.

---

## 3. MEMORY / PERF BUDGET — how many region meshes are resident, and is it safe

**Question: with Inner = 0 and Outer = 700, how many region components sit resident at once?**

A band of radius 700 chunks = 2240 m. Tier 1 regions are 307 m across, so the band square is about
`(2 × 2240 / 307) ≈ 14.6` regions per side → roughly a **15 × 15 ≈ 225 region components** resident at
the band's full extent (capped by the ~289 that exist — near the map centre you can see most of the map).
At Tier 2 (1.6 m, 1.2 km regions) Outer = 800 chunks is only ~`(2 × 2560 / 1229) ≈ 4.2` per side →
~**16–25 region components** — trivially few.

**Is ~225 resident static-mesh components safe?** Yes, and here's the research finding that says so:
- **Nanite draws are cheap.** Each region is one Nanite static mesh; Nanite culls and LODs it to ~1
  triangle/pixel regardless of how dense the baked cubes are. 225 Nanite draws of frozen terrain is not
  the bottleneck.
- **The real limit is component spawn/registration churn**, not the steady-state count. As the player
  roams, regions cross the band edge and the streamer creates/destroys `UStaticMeshComponent`s
  (`PlaceTile`/`ReleaseTile`). Creating and registering a component (and its render proxy) every time is
  the expensive part — and a 307 m region only crosses the edge occasionally, so the churn rate is low.
- **The streamer already caps and pools the churn**, so it's bounded no matter how fast you fly:
  - `MaxOpsPerTick` (wired to **3** for 40 cm) — at most 3 ensure/release ops per tick, so a big region
    swap is spread over frames instead of hitching one.
  - `MaxConcurrentLoads = 8` — caps in-flight async mesh loads so heavy merged meshes feed in steadily
    (this is the knob that previously froze the editor when uncapped).
  - `MaxLiveComponents = 4096` — a safety ceiling far above our ~225; fills **nearest-first** so if you
    ever hit it, the closest regions win and far ones come in as near ones release.
  - **Component pooling** (`MaxPooledComponents = 32`) — released components are hidden and parked on a
    free-list, then reused on the next ensure, so the render proxy isn't destroyed/recreated on every
    roam. This is what keeps a forever-running streamer from churning GC garbage.
  - `bHoldTilesUntilVoxelsReady = true` — a region isn't released until the live voxels that replace it
    are proven meshed (`AreCoveredColumnsReady`), so the swap never flashes a gap.

**Verdict:** ~225 resident Nanite region meshes for the 40 cm far view is safe. The budget lever is not
"how many are resident" but "how fast they spawn", and the streamer's caps + pooling already bound that.
The one VRAM lever to watch is Nanite's streaming pool: the crust bumps
`r.Nanite.Streaming.StreamingPoolSize` to **1024 MB** and `NumInitialRootPages` to **4096** on BeginPlay
(`NaniteStreamingPoolSizeMB` / `NaniteNumInitialRootPages`) so thousands of unique baked cubes don't
thrash the page pool. Verify those against the 5.7 defaults in-engine and never set them below default.

---

## 4. THE SEAM — the 10 cm → 40 cm jump and the VerticalBias sink

Where the editable bubble (10 cm voxels, real surface) overlaps the crust (40 cm, frozen), two terrains
fight for the same pixels. The fix:

- **Sink the crust below the true surface** by `VerticalBiasVoxels`. For 40 cm the current value is
  **`VBIAS = 6` voxels = 60 cm** (`wire_40cm_crust.py`). `PlaceTile` applies it as
  `Oy = (BaseFineY − VerticalBiasVoxels) − APRON×Stride`, pushing the whole region mesh down. Because the
  live voxels sit at the real surface and the crust sits ~60 cm under it, **wherever they overlap the
  crisp 10 cm voxels render on top** and hide the crust. You only ever see the crust beyond the bubble.
- **How much to sink:** enough to clear one 40 cm cube of the seam, plus margin. 6 voxels (60 cm) =
  ~1.5 crust-cubes is a good default. Finer/closer tiers need *less* sink; coarser/farther tiers can
  take *more* (a 1.6 m tier can sink 8–16 voxels without the gap ever being visible at that range).
  Too little → the frozen crust poke-through flickers through the editable cubes; too much → a visible
  lip/step where the bubble edge meets the crust. **This is the #1 thing to tune by eye in PIE.**

**Color / height matching.** The crust and the live voxels share the SAME generator and the SAME palette:
`sample_crust_slab` stores the real surface material id (`top_id_at = resolve_column().top_id`) so the
greedy mesher derives the **same `base_color`/shaded color** the near voxels use — no color seam by
construction. Heights line up because the crust samples the same `height_at` (`compute_ground_y`) on the
same world grid, and `PlaceTile` re-bases positions with the identical `PositionToUE` swap+scale the live
voxels use. The only *intended* mismatch is the 60 cm vertical sink — which is the point. Watch for: at a
**cliff edge**, the coarse 40 cm crust silhouette won't match the 10 cm cliff exactly, so the sink plus
the bake skirt (`DEFAULT_SKIRT_DEPTH_VOXELS`, ~`4×Stride` = 16 vox at 40 cm) need to be deep enough that
the crust doesn't show through *under* an overhang. If you see daylight under a cliff lip, increase the
bake skirt, not the sink.

---

## 5. WHEN TO GEO-MERGE — and when NOT to

- **Far baked tiers → always `-GeoMerge`.** It fuses an 8 × 8 tile block into one mesh + one manifest
  entry, turning ~17,000 tiny 40 cm tiles into ~289 region meshes (and dodging the file wall, where
  Unreal chokes on hundreds of thousands of separate assets). The runtime needs zero changes: the bake
  writes the region width into `TileSpanVoxels` and the streamer treats a merged region as just a *bigger
  tile* (`RegionMerge.h`). Fewer, bigger components = fewer draws, less spawn churn. The cost is
  **coarser streaming** (region-at-a-time, 307 m granularity) — which is exactly what forces Inner = 0
  (§2), and is totally fine for far terrain that needs no patch-level precision.
- **Near editable terrain → never geo-merge (it isn't baked at all).** Tier 0 is live voxels the player
  digs; there's no bake, no tile, nothing to fuse. It re-meshes per-chunk on every edit. Geo-merge is a
  *bake-time* concept and simply doesn't apply.

Rule of thumb: **the closer a tier is to the player, the more it benefits from fine streaming → less
merging; the farther, the more it benefits from few-big-meshes → geo-merge.** Tier 0 = no merge (live).
Tier 1/2 = full geo-merge.

---

## 6. OPEN QUESTIONS / TUNABLES — what to iterate on in PIE

Type these in the editor (or `wire_40cm_crust.py`), fly around, and adjust by eye:

1. **`VerticalBiasVoxels` (the sink).** Start 6 (40 cm). Lower until the crust pokes through the
   editable cubes; raise until you see a step at the bubble edge. Find the gap between. **Highest-value
   knob.**
2. **`OuterChunks` (band reach).** Start 700 (~2.2 km). Lower if the far ring costs too much / load-burst
   stutters on spawn; raise toward ~1100 (map diagonal) if you can see an unloaded edge from a hilltop.
3. **`StreamRadiusChunks` (live bubble size) vs the seam.** 64 chunks (205 m) is the editable reach.
   Bigger bubble = the seam moves farther out (better hidden, more live-voxel cost); smaller = cheaper
   but the crust creeps closer. Tune against frame budget, not looks.
4. **`MaxOpsPerTick` (stream gentleness).** 3 for big merged regions. Raise if regions pop in too slowly
   when sprinting/flying; lower if a region swap hitches a frame.
5. **Tier boundaries — do we even need Tier 2?** Ship 40 cm-only first. Only add the 1.6 m tier if the
   far horizon is too heavy (then Tier 1 Outer shrinks to ~400 chunks and Tier 2 fills beyond) or too
   blocky at the extreme edge. Decide this from PIE perf, not in advance.
6. **Bake skirt depth at cliffs.** If the crust shows daylight under an overhang, deepen the bake skirt
   (`-Skirt`, default ~`4×Stride`) rather than over-sinking the whole tier.
7. **Nanite streaming pool sizing.** Confirm `NaniteStreamingPoolSizeMB` (1024) and
   `NaniteNumInitialRootPages` (4096) against the real 5.7 in-engine defaults; raise if far tiles
   flicker/pop (page thrash), leave alone if VRAM is tight and it looks stable.

---

## 7. The one-page summary

| Tier | Cube | Tile | Geo-merge region | Regions (whole map) | Inner | Outer | Sink | Status |
|---|---|---|---|---|---|---|---|---|
| 0 Live voxels | 10 cm | — (live) | — | — | — | radius 64 ch (205 m) | — | shipped, editable |
| 1 **40 cm crust** | 40 cm | 38.4 m | 307 m (8×8) | **~289** | **0** | **700 ch (~2.2 km)** | **6 vox** | **wired + tested** |
| 2 1.6 m crust (opt) | 1.6 m | 153.6 m | 1.23 km (8×8) | ~25 | 0 | 800 ch (~2.6 km) | 8–16 vox | optional, plain mesh |

**The plan:** Live 10 cm bubble (205 m) for digging → one 40 cm geo-merged crust (~289 regions, ~225
resident in-band) for the far view, sunk 60 cm to hide the seam → optional 1.6 m tier only if the deep
background proves too heavy. Streaming churn is bounded by the streamer's caps + pooling, so the resident
count is safe. Tune the sink and the band reach by eye in PIE.
