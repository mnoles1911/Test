# UE5 Roaming Voxel LOD Clipmap + Parallel Bake — architecture & handoff

Supersedes the far-render half of `UE5_NANITE_CRUST_PERF.md`. Written after the 2026-06-20/21
session that replaced the origin-centred Nanite crust with a **player-relative, whole-map LOD
clipmap**, added a **parallel bake pipeline**, and fixed several streaming-perf bugs. Read alongside
`UE5_WORLD_STREAMING_PLAN.md` and the memory notes `project_ue5_far_render_systems` /
`project_ue5_nanite_bake_plan`.

> **Status in one line:** roaming clipmap is BUILT + wired + saved into `MiraStreamTest.umap`; perf
> is good (45 FPS, worst-load 25 ms). The **smooth vista was retired** to fix a far z-fight — that
> last fix is **saved but not yet eyeball-verified by the designer** (cubic-vs-void at distance).

---

## 1. The problem this solves

The world is a **bounded 5 km × 5 km map** (±2500 m from the voxel origin; beyond the coast is
future open ocean — no terrain). The player **spawns at random points and roams freely**, so terrain
detail must **follow the player anywhere**, not just near the map centre.

Two kinds of terrain exist:
- **Live voxels** (10 cm) — generated on the fly in a small bubble around the player, *editable*
  (dig). Expensive → small radius.
- **Cold-baked crust** (Nanite static meshes) — pre-baked surface shell, cheap to draw, but
  *frozen in place*. The fix for "detail everywhere" is to **bake the crust for the WHOLE map at
  several resolutions (mips)** and let the existing player-relative streamer pick the right mip by
  distance. Detail then follows the player because the tiles exist everywhere.

The old design baked fine rings only around the **origin**, so roaming away from centre lost detail.

---

## 2. The clipmap (current live config in MiraStreamTest.umap)

| Tier | Source manifest | Cube | Band (chunks → m) | Sink (VerticalBiasVoxels) | Tiles at spawn |
|---|---|---|---|---|---|
| Live voxels | — (generated) | 10 cm | StreamRadiusChunks **14** (~45 m) editable bubble | 0 | — |
| Crust near | `/Game/VoxelBake/MiraStreamTest_80cm/Manifest` | 80 cm | Inner 12 → Outer 130 (38–416 m) | 3 | ~134 |
| Crust mid | `/Game/VoxelBake/MiraStreamTest_L1/Manifest` (1.6 m) | 1.6 m | 130 → 300 (416–960 m) | 8 | ~299 |
| Crust far | `/Game/VoxelBake/MiraStreamTest_L2/Manifest` (6.4 m) | 6.4 m | 300 → 2200 (960 m → map edge from anywhere) | 16 | ~133 |
| Smooth vista | `MiraFarVista` (AVoxelFarHeightmesh) | — | **RETIRED** (build-on-play off, hidden, mesh cleared) | (was 24) | 0 |

- 1 chunk = 3.2 m. Bands are CHUNKS-from-the-player (the crust streamer is already player-relative —
  it loads tiles whose nearest covered chunk is in `[InnerChunks..OuterChunks]`).
- The mips are **whole-map** bakes (80cm: 3896 tiles, 1.6m: 2390, 6.4m: 169 in-manifest), so the
  right tiles exist wherever you stand. The 6.4m `OuterChunks=2200` (~7 km) guarantees the whole map
  shows even from a far corner.
- **Sink ordering** (finer wins on top, no z-fight): live(0) > 80cm(3) > 1.6m(8) > 6.4m(16). The
  vista was sunk 24 but at coarse range the 6.4m crust's margin over it was too thin → the vista won
  most far pixels (the "scattered single cubes over smooth terrain" bug). **Retiring the vista** is
  the fix; the 566 contiguous crust tiles then own the far view. **VERIFY this looks cubic, not void.**
- The 3 crust actors are `MiraCrust_80cm` (was `VoxelNaniteCrust_0`, repointed), `MiraCrust_L1`,
  `MiraCrust_L2`. `MaxOpsPerTick=24`, `bHoldTilesUntilVoxelsReady=false` on all.

### How to retune
Resolution↔distance should keep cube size ≈ constant screen-size: a cube of size `D/500` reads well
at distance `D`. To add a finer near tier (e.g. 40 cm) or change a band, set the crust actor's
Manifest + Inner/Outer + sink, then `save_level`. To re-bake a tier at a different resolution, use the
bake tools below.

---

## 3. Parallel bake pipeline (10 cm-in-1-2h path)

The bake's bottleneck is the **serial** Nanite mesh-build + package-save (STEP B); sampling/meshing
(STEP A) is already parallel across worker threads. So real speedup comes from **multiple processes**.

**C++ (`MiraThalVoxelBake`):**
- `FBakeSettings.ShardIndex/ShardCount`. In `BakeWorldCrust`, each process bakes only tiles where
  `flatIndex % ShardCount == ShardIndex` (even load balance), writes its tiles to the shared folder,
  and emits a **text manifest-shard** at `Saved/BakeShards/<name>_shard<i>.txt` (8 ints/line:
  `tileX tileZ minVX minVZ maxVX maxVZ baseFineY stride`; mesh path is derived from the tile key).
- `VoxelCrustBaker::MergeShards(name)` combines the shards into the real `Manifest.uasset`, deletes
  the shards. `ShardCount<=1` = single process writes the manifest directly (unchanged path).
- Commandlet `-run=VoxelCrustBake` gained `-Shards=N -Shard=i` and `-Merge`.

**CRITICAL gotcha:** the headless commandlet must pass **`-AllowCommandletRendering`** or every tile
fails with "null UStaticMesh" — building Nanite needs the RHI, which a plain commandlet skips. The
first parallel bake on a cold DDC pays a ~5-min shader compile; later runs are fast.

**Commandlets exit non-zero on shutdown even on success** — judge success by OUTPUT (shard files /
the `MergeShards: ... saved=1` log line), never the process exit code. The `.ps1` already does this.

### The bake tools (repo root)
- **`Bake-Terrain-Menu.bat`** — interactive: pick 10/20/40/80cm/1.6m/custom → pick parallel jobs
  (blank = auto = cores−2) → bakes. Has the file-wall warnings baked in.
- **`Rebake-Terrain.bat <cubeCm> [name] [jobs]`** — one-liner wrapper.
- **`Rebake-Terrain.ps1`** — the engine: derives stride/tileSpan/radius/skirt from cube size, fans
  out N hidden processes (`-Shards`), waits, runs `-Merge`. Per-shard logs in
  `Saved/Logs/bake_<name>_shard*.log`. **Close the GUI editor first** (the bake launches its own
  instances). Coarse_side is fixed at 96 (fewest files); skirt defaults to ~4 cubes deep.

### Resolution economics (whole 5 km map, one-uasset-per-tile)
| Cube | Tiles (files) | Disk | Bake (parallel) | Verdict |
|---|---|---|---|---|
| 10 cm | ~275,000 | ~4–6 GB | ~1–2 h on many cores | **over the file wall** |
| 20 cm | ~70,000 | ~1.3 GB | ~30–60 min | past the wall (borderline) |
| 40 cm | ~17,000 | ~300 MB | ~15–25 min | heavy but OK |
| 80 cm | ~5,000 | ~150 MB | ~5–10 min | **sweet spot (current near tier)** |
| 1.6 m | ~2,400 | ~45 MB | ~3–5 min | mid tier |
| 6.4 m | ~170 | ~10 MB | <1 min | far tier |

The **"file wall"** is the killer for 10/20 cm: 1-file-per-tile × hundreds of thousands of files
strains the asset registry, cook, and source control. Disk size is NOT the limit; file COUNT is.
Shell thickness barely matters (top-surface area dominates). The escape hatch is **region-packing**
(below). The bake map-clips to the coast, so out-of-map tiles are never produced (see §5).

---

## 4. Streaming-perf fixes this session (all built)

- **Hero altitude-gate** (`HeroMaxAltitudeMeters=40`, `VoxelWorld`). The hero pass *synchronously*
  gens + LOD0-meshes the column under the player — great on the ground, but a frame-spiking waste
  when flying high (the diagnosed ~390 ms uninstrumented stall). It now skips when the focus is >Nm
  above the surface. New CSV column **`heroMs`** times the pass (mirrors genMs/meshMs/evictMs).
- **Eviction catch-up** (`EvictCatchupMultiplier=8`, `VoxelWorld`). Base `MaxEvictOpsPerTick=8` keeps
  pace with walking but not sprint/fly/teleport → out-of-range columns piled up unbounded ("distant
  square that never unloads"). When the backlog > 4× base, teardown scales up to 8× base (bounded).
  Safe: those columns are already beyond the keep radius, not pending a re-mesh.
- **Map-bounds clip** (`NaniteBakeTiling.h` + baker): out-of-map columns sample as air, fully-out
  tiles are skipped → clean coastline, no "floating square slabs over the ocean" (see §5).

### Perf-measurement gotcha (cost me real time)
The editor **throttles PIE to exactly 3 FPS / 333 ms when its window is NOT focused** (the
bridge/headless control path leaves it unfocused). That fake 333 ms looks identical to a real stall.
`Slate.bAllowThrottling 0` did NOT fix it; `EditorPerformanceSettings.bThrottleCPUWhenNotForeground`
is not Python-exposed. **To measure real perf you must focus the editor window** (designer confirmed
45 FPS / 25 ms worst-load focused). Don't trust perf numbers from background-driven PIE.

---

## 5. Bounded-map correctness (the floating-squares bug)

Outside the 5 km map the generator returns a flat base height, so an over-wide bake produced flat
slabs floating over the (future) ocean — a 4-tile-deep grid around the coast. Fixed at the SOURCE:
`sample_crust_slab` takes `mapHalfExtentVox` (= `MapSpanMeters * 5`, i.e. 2500 m × 10 vox/m); columns
outside the square become air, fully-out tiles are skipped, edge-straddling tiles mesh only their
in-map part (clean coast). Wired through `SampleAndMeshCrustTile` from `World->MapSpanMeters`. Harness
test green. Verified in PIE: no floating squares from any position.

---

## 6. State — verified vs not

**Verified:** parallel bake works (4-proc smoke → merged manifest); map-clip kills floating squares;
hero gate works (`heroMs=0` at altitude); roaming streaming works (teleported to 2 corners, all 3
tiers re-streamed there, settled, 0 errors); perf good (45 FPS / 25 ms focused); near terrain cubic.

**NOT yet verified (needs a focused PIE pass by the designer):**
1. **Far view is cubic, not void, after retiring the vista.** Crust loaded 566 contiguous tiles so
   it *should* be cubic; confirm. If void → far-tile placement/coverage bug, re-enable vista + dig.
2. **Eviction catch-up** under fast roaming (built, not runtime-tested).
3. **Seam transitions** between tiers (cracks/pops/z-fight) while roaming.
4. The 40 cm whole-map scale-test bake (running headless at time of writing) — confirm it completes
   + the parallel system holds at ~17k tiles before trusting it for 10 cm.

---

## 7. Remaining work / backlog

- **Verify the vista-retire** (above) — the gating item for "roaming clipmap done".
- **Region-packing** (the path to practical 10/20 cm): pack many tiles into a few large Nanite
  assets (e.g. one mesh per 250–500 m region → ~100 files for the whole map) to dodge the file wall.
  Render perf is unaffected (Nanite); cost is resident memory + coarser streaming + less granular
  iteration + a baker/manifest/runtime-streamer change. Only needed for sub-40 cm.
- **Skip Nanite for coarse far tiles** (bake speedup): coarse tiles (6.4 m, seabed) have few
  triangles — build them as regular static meshes (much faster than the Nanite build, the serial
  bottleneck). Pairs with parallel bake. (Designer deferred; note kept.)
- **Water-depth clip** (further bake speedup, deferred): given a global water level + visible depth,
  skip fine tiles for deep-underwater terrain (mirrors the map-clip). Big win on island maps.
- **Material:** `M_VoxelTerrainV2` needs the persistent **bUsedWithNanite** usage flag saved (renders
  fine in-editor via auto-enable; matters for cooked builds). UI fix: open material → Usage → toggle
  "Used with Nanite" → Ctrl+S (the Python usage-flag API doesn't persist it).
- **Orphan tile cleanup before commit:** several folders have stale Tile_*.uasset from re-bakes not
  referenced by their manifest (e.g. MiraStreamTest_L2 has 441 assets, 169 in-manifest). Prune the
  unreferenced ones. Needs the editor to read manifests (or binary parse).
- **Commit decision:** code (8 files, +273/−21, harness-green, builds) is solid. `Content/VoxelBake/`
  (~hundreds of MB of .uasset) + `MiraStreamTest.umap` are the asset payload — plain git vs LFS.

## 8. Key file anchors
- Clipmap streamer + sink/band: `VoxelNaniteCrust.cpp::Tick`, actors in `MiraStreamTest.umap`.
- Tiling + map-clip math: `Core/NaniteBakeTiling.h` (`sample_crust_slab`, `mapHalfExtentVox`).
- Baker + sharding + merge: `VoxelCrustBaker.cpp` (`BakeWorldCrust`, `MergeShards`).
- Headless entry: `VoxelCrustBakeCommandlet.cpp` (`-Shards/-Shard/-Merge`).
- Hero gate / eviction catch-up / heroMs: `VoxelWorld.cpp` (hero pass ~1759, evict ~2112, CSV ~3420).
- Bake tools: repo-root `Bake-Terrain-Menu.bat`, `Rebake-Terrain.bat`, `Rebake-Terrain.ps1`.
