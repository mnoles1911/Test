# UE5 World Streaming, LOD, Nanite & Persistence — Production Plan

**Status:** PLAN (2026-06-16). The production architecture for roaming the full **5 km × 5 km** world at
**10 cm voxels**, with long view distances, vistas from high points, on-disk caching, and Nanite. This
is the umbrella plan that M4 (streaming/persistence), M6 (Nanite), M7 (far-field), and M8 (GPU) all
serve. Companion: `design/UE5_GPU_PHASES.md` (M6/M7/M8 detail), `design/UE5_HEIGHTMAP_IMPORT.md`
(the EXR source), `design/UE5_TECH_STACK.md` (the stack).

Plain-English framing for the non-programmer: the world is enormous, so we never hold all of it in memory
or on the GPU at once. Instead we keep a **small, detailed bubble around the player**, **medium detail a
bit further out**, and a **cheap painted silhouette for the far mountains** — and we swap between them as
you move. The trick that makes the whole thing affordable is in §1.

---

## 0. The problem, in numbers

| Quantity | Value | Why it matters |
|---|---|---|
| World footprint | 5 km × 5 km | the design target |
| Voxel size | 10 cm (10 vox/m) | the look; non-negotiable |
| Horizontal columns | 50,000 × 50,000 = **2.5 billion** | can't be resident, can't be meshed, can't all be on disk as voxels |
| Vertical (typical) | ~120–2300 voxels (12–230 m) | columns are tall too |
| Full naïve voxel storage | **~5 TB+** at 2 bytes/voxel if fully dense | obviously impossible — must stay sparse + derived |
| The EXR itself | 8192² float = **268 MB on disk** | this is the whole map's *shape*, already tiny |

The entire problem is the gap between "2.5 billion potential voxels" and "a few hundred MB we can
actually afford." Everything below is about never paying for voxels we don't need.

---

## 1. Core principle: the world = EXR (read-only base) + a thin edit journal

**The unedited terrain is 100% derivable from the EXR.** Generation is deterministic: given the EXR + the
seed, `HeightmapGenerator` produces the exact same voxels every time for any column (`compute_ground_y` →
banding → water → flora). So we **never store the unedited world** — we regenerate any chunk on demand.

What we DO store is only what generation *can't* reproduce: **the player's edits.** Digging a tunnel,
placing a block, a settled water pool — those are a sparse **edit journal** (a.k.a. delta store): a small
list of "at voxel V, the value is now X" entries, keyed by region. A player who has dug ten thousand
voxels has stored ten thousand entries — kilobytes — against a 2.5-billion-voxel world.

```
 final voxel(V) = edit_journal.get(V)  if present
                  else generate(V)  from EXR + seed
```

This is the Minecraft "seed + changes" model, except our "seed" is a **hand-authored Gaea heightmap**
instead of noise. It collapses the storage problem from terabytes to "268 MB EXR + a few MB of edits."

**Authoritative vs. rebuildable — the distinction that drives all of §7:**
- **Authoritative (must persist, never auto-delete):** the EXR, the seed, the edit journal.
- **Rebuildable cache (safe to evict/regenerate):** generated voxel bricks, meshed geometry, Nanite
  bakes, the far heightmesh. All of these can be thrown away and rebuilt from the authoritative data.

---

## 2. The five representation tiers (near → horizon)

A voxel is expensive; a far mountain silhouette is cheap. We render each distance band with the cheapest
representation that still looks right. Distances are tuning starting points, not final.

| Tier | Range (approx) | Representation | Editable? | Collision? | Built by |
|---|---|---|---|---|---|
| **T0 — Near** | 0–80 m | full **10 cm voxel mesh** (greedy mesher, per-face color, PMC→RealtimeMesh) | **yes** | **yes (Chaos)** | M2 ✅ + M4 streaming ✅ |
| **T1 — Mid voxel LOD** | 80–300 m | **downsampled voxel mesh** (20/40/80 cm) via `LodDownsample` + `SeamSkirt` | no | optional | M4 LOD (new) |
| **T2 — Nanite cold-bake** | 80 m–~1 km, *static only* | unedited chunks baked to **Nanite** static meshes | no | from baked mesh | M6 (new) |
| **T3 — Far heightmesh** | 0.3–5 km+ | one coarse **mesh of the whole EXR**, biome-coloured (the vista) | no | no | M4/M6 (new) |
| **T4 — GPU ray-march** | optional, far voxel detail | screen-space march over a GPU brick mirror | no | no | M7 (new) |

**T2 vs T1 is a choice, not both-always:** a chunk in the mid band is rendered EITHER as a cheap
downsampled voxel mesh (T1) OR, if it's been static long enough to be worth baking, as a Nanite mesh
(T2). T2 wins where it's stable; T1 covers freshly-streamed or recently-edited mid terrain. See §5.

**T3 is the key to vistas.** Tiers 0–2 only ever cover ~1 km. Standing on a peak and seeing the whole
5 km map is the job of **T3: a single low-resolution mesh built directly from the EXR** (e.g. downsample
8192² → 1024² or 2048² → a 2–8 M-triangle Nanite mesh), draped with the biome/altitude palette. It's
trivially cheap (it's just the image as a heightfield), always resident, and gives the full-map
silhouette behind everything. The near/mid voxel tiers render ON TOP of it; where they exist they hide
it, and beyond them it IS the horizon. This is what makes "long view distances and vistas from high
points" actually work without streaming voxels to the horizon.

---

## 3. Streaming architecture (paging the near/mid tiers around the player)

The near + mid voxel tiers (T0/T1) are **paged in around the player and evicted behind**. We already have
the column-paging skeleton (M4: `FillChunkColumn`/`MeshChunkColumn`, ring load + evict, one-column fill
skirt for seamless borders). Production hardening:

1. **Streaming source = the player (and the camera for spectators).** UE **World Partition** with a
   **runtime hash grid** drives cell load/unload; the voxel world registers a `UWorldPartitionStreamingSource`
   that follows the pawn. Our `AVoxelWorld` becomes the manager that World Partition asks to (un)load
   voxel cells, instead of a single monolithic actor.
2. **Async generation + meshing OFF the game thread.** Generating a column (EXR sample + banding) and
   greedy-meshing it are pure CPU and touch only Core data — perfect for worker threads
   (`UE::Tasks` / `FAsyncTask`). The game thread only does the final **mesh upload + actor swap**, budgeted
   per frame (`Core/MeshBudget.h` already models a per-frame triangle/chunk budget). This keeps streaming
   off the hitch path.
3. **Ring + hysteresis (have it):** load radius R, evict at R+padding so a column straddling the edge
   doesn't thrash. Nearest-first fill (have it). Production adds **priority by view direction** (load what
   you're looking at first) and **a hard per-frame upload cap**.
4. **Distance → tier selection** per column: pick T0/T1/T2 from camera distance + edited-state, with
   hysteresis bands so a column doesn't flip LOD every frame at a boundary.
5. **Predictive prefetch:** generate the ring slightly ahead of the player's velocity so high-speed
   traversal (mounts, vehicles) doesn't outrun the streamer (the Godot build hit exactly this — "LOD
   outrun fixed", PR#240).

---

## 4. LOD system (mid voxel detail without the cost)

`Core/LodDownsample.h` and `Core/SeamSkirt.h` already exist (ported from the Godot LOD work). Production
LOD:

- **Mip the voxels, not the mesh.** A LOD-1 chunk merges each 2×2×2 voxel block into one 20 cm voxel
  (majority/priority material), LOD-2 → 40 cm, LOD-3 → 80 cm. `LodDownsample` does this reduction; the
  same greedy mesher then meshes the coarser grid → far fewer triangles.
- **Seams between LOD levels** (a fine chunk next to a coarse one) crack visibly. `SeamSkirt` drops a thin
  vertical "skirt" at the boundary to hide the gap — cheaper and more robust than stitching. (The Godot
  build proved skirts beat stitching for this.)
- **LOD selection** is per chunk-column by distance, with the hysteresis bands from §3.4.
- **Collision only on T0.** Mid/far LODs are visual; the player only physically interacts with the near
  full-detail band, so Chaos cooking cost stays bounded.

---

## 5. Nanite cold-bake (T2 — make static mid terrain nearly free)

Nanite shines on **dense, static** geometry — exactly what unedited mid-distance terrain is.

- **Bake trigger:** a chunk (or **super-chunk**, e.g. 4×4 chunks, for better Nanite batch size) that has
  been resident and **unedited for N seconds** becomes a bake candidate. Editing it invalidates the bake.
- **Build:** feed the chunk's greedy-mesh (vertex/index/colors) into a Nanite-enabled `UStaticMesh`
  (`NaniteSettings.bEnabled = true`, built via `FStaticMeshRenderData`/`UStaticMesh::Build`), swap the
  live PMC/RealtimeMesh actor for a `UStaticMeshComponent`. Vertex color carries through Nanite, so the
  material (`M_VoxelTerrainV2`) is unchanged.
- **Invalidation:** any edit in a baked chunk → drop the Nanite mesh, fall back to the live voxel mesh,
  re-bake later once it's static again. The edit journal (§1) is the invalidation key.
- **Disk-cache the bakes** (§7): a Nanite bake is expensive to build but rebuildable, so cache it keyed
  by (region, content hash) and reuse across sessions.
- **Detail:** see `design/UE5_GPU_PHASES.md` §M6.

---

## 6. Far tier & vistas (T3 heightmesh, optional T4 ray-march)

**T3 — the EXR heightmesh (do this; it's the cheapest big win):**
- At load, downsample the 8192² EXR to a manageable grid (1024²–2048²) and build **one Nanite static mesh
  heightfield** of the entire 5 km, coloured by the **same biome/altitude palette** the voxels use (so the
  far silhouette matches the near cubes in hue). 2048² ≈ 8 M tris, trivial for Nanite.
- It's **always resident** (a few hundred MB at most, often less), needs **no streaming**, and provides
  the full-map vista from any high point. Near/mid voxels draw on top; the heightmesh is the horizon.
- Cosmetic cubey-ness at the transition is hidden by distance + fog; an optional dither/ morph blends the
  voxel band into the heightmesh.

**T4 — GPU ray-march (optional, later):** for *voxel-accurate* far detail (caves, overhangs visible at
distance) march the GPU brick mirror in HLSL. The CPU oracle `Brickmap::raycast_solid` is the parity
spec (pinned by `test_raymarch`). This is M7 and is **optional polish** — T3 already delivers vistas.
Detail: `design/UE5_GPU_PHASES.md` §M7.

**Atmosphere does real work here:** Sky Atmosphere + Exponential Height Fog + aerial perspective make the
far heightmesh read as distance rather than a flat backdrop, and hide the T2→T3 seam. (See the art-assets
plan for the sky/fog/weather stack.)

---

## 7. Persistence & caching to disk

Two completely separate stores with opposite rules (§1):

### 7a. Authoritative — the edit journal (must never be lost)
- **What:** every player modification (carve, place, settled finite-water final state if we choose to
  persist pools), as sparse `(voxel, newValue)` entries.
- **Format:** region files — **`Core/RegionFormat.h` already defines a region container** (ported from the
  Godot region streaming). Partition the world into **region tiles** (e.g. 512×512 voxels = 51.2 m, or
  aligned to World Partition cells); each region file holds the edit deltas for its tile. Only regions the
  player has actually touched ever get a file.
- **Write path:** edits append to an in-memory per-region delta map; flushed to disk on a timer / on region
  unload / on save. Crash-safe: write-to-temp + atomic rename, or a small WAL.
- **Load path:** when a region streams in, generate from the EXR, then **replay its delta file on top**.
- **Size:** proportional to how much the player digs, not world size. Bounded and tiny.

### 7b. Rebuildable cache — generated voxels, meshes, Nanite bakes, heightmesh
- **Why:** regenerating a column from the EXR every time it streams in costs CPU; re-baking Nanite costs
  more. Cache the expensive results to disk so revisits and restarts are fast.
- **What:** (a) generated **brick data** per chunk (post-generation, pre-edit); (b) **Nanite bakes**;
  (c) the **far heightmesh**. All keyed by a **cache key = hash(EXR content + seed + generator version +
  LOD)**. If any input changes, the key changes and stale cache is ignored (auto-invalidation).
- **Eviction:** an **LRU budget on disk** (e.g. cap the cache at N GB) — evict least-recently-used regions;
  they regenerate on next visit. Because it's a cache, eviction is always safe.
- **Important separation:** the cache stores *generated* (pre-edit) data; the **edit journal is applied
  after** loading from cache. Never bake edits into the rebuildable cache, or you can't tell base from
  player change — and a generator-version bump would corrupt edits.

### 7c. What we deliberately do NOT persist
- The unedited world (derived from EXR).
- Live water-sim ledger mid-flow (it re-settles; only persist final pools if design wants permanent
  player-made lakes — a decision, see §12).
- Anything in the GPU mirror (rebuilt from CPU each session).

---

## 8. Threading & frame budget (where the hitches hide)

- **Worker threads:** generation, LOD downsample, greedy meshing, Nanite mesh build, region file
  read/write, cache compression — all off the game thread (Core is engine-free and thread-safe per chunk).
- **Game thread only:** RHI mesh upload, actor spawn/swap, collision cook registration — all **budgeted
  per frame** via `Core/MeshBudget.h` (cap triangles/chunks uploaded per frame; queue the rest).
- **One writer for the brickmap** (the authoritative store) or per-region locks — readers (mesher) take a
  snapshot/slab so they never block the writer.
- **Determinism preserved:** the finite-water sim and generation are deterministic; threading must not
  reorder within a region (process a region's active cells in the fixed (y,x,z) order the parity gates
  assert).

---

## 9. Memory budgets (starting targets, to be measured)

| Pool | Target | Notes |
|---|---|---|
| Resident CPU bricks (T0+T1 ring) | ≤ ~1–2 GB | sparse; bounded by ring radius, evict beyond |
| GPU voxel meshes (T0/T1) | ≤ ~1–2 GB VRAM | RealtimeMesh; greedy + LOD keep tris down |
| Nanite bakes (T2) resident | streamed by Nanite | Nanite handles its own residency |
| Far heightmesh (T3) | ≤ ~few hundred MB | always resident, one mesh |
| Edit journal (RAM) | ≤ tens of MB | sparse deltas for loaded regions |
| Disk cache | LRU-capped, e.g. 5–20 GB | rebuildable; user-tunable |

The load-bearing rule: **resident cost scales with view radius, not world size.** A 5 km world and a 50 km
world cost the same to stand in.

---

## 10. What already exists vs. what's new

**Already built (lean on these):**
- `Brickmap` sparse store + `raycast_solid` oracle (M7 spec, `test_raymarch`).
- Greedy mesher + per-face color + AO; `BrickmapMeshing` slab extraction + affected-chunks.
- `LodDownsample`, `SeamSkirt`, `MeshBudget`, `BandPolicy` (LOD/seam/budget Core, ported from Godot).
- `RegionFormat` (region file container — the persistence substrate).
- `HeightmapGenerator` + EXR `ImageHeightmap` (deterministic base; EXR sampling is a plain bilinear lookup,
  GPU-portable).
- M4 column streaming (ring load/evict, fill skirt, focus follow); M3 carve + finite water.

**New for production:**
- World Partition integration + streaming-source-follows-player; async gen/mesh task graph.
- Distance→tier selection with hysteresis; LOD mesh path wired (downsample→mesh→skirt).
- Nanite cold-bake module (`MiraThalVoxelBake`) + invalidation.
- EXR far heightmesh builder (T3).
- Edit-journal region store (write/replay/flush, atomic) + rebuildable disk cache (key + LRU).
- GPU brick mirror + ray-march (T4, optional) — `MiraThalVoxelRender`.

---

## 11. Phased build plan (mapped to milestones)

Ordered for earliest playable payoff, lowest risk first. Each phase ends green on the clang harness for
its Core parts + a build/PIE check for the UE parts.

1. **P1 — Async streaming hardening (M4):** move gen/mesh to worker threads; per-frame upload budget;
   World Partition streaming source follows the pawn; predictive prefetch. *Payoff: smooth roaming of a
   large region without hitches.*
2. **P2 — Edit journal persistence (M4):** region delta store on `RegionFormat`; generate-then-replay on
   load; atomic flush. *Payoff: your digs survive reload; foundation for the disk cache.*
3. **P3 — Voxel LOD (M4):** wire `LodDownsample` + `SeamSkirt` into the mid band; distance tier selection.
   *Payoff: mid-distance terrain at a fraction of the triangles → bigger view distance.*
4. **P4 — Far heightmesh (T3):** build the whole-map Nanite heightmesh from the EXR, biome-coloured.
   *Payoff: real vistas from high points — the headline visual ask.*
5. **P5 — Rebuildable disk cache:** cache generated bricks + meshes keyed by EXR/seed/version, LRU-capped.
   *Payoff: fast restarts and revisits.*
6. **P6 — Nanite cold-bake (M6):** bake static mid chunks to Nanite; invalidate on edit; cache bakes.
   *Payoff: dense static terrain at Nanite cost.*
7. **P7 — GPU ray-march far detail (M7, optional):** brick mirror + HLSL DDA gated by `test_raymarch`.
   *Payoff: voxel-accurate far detail; polish.*
8. **P8 — GPU meshing/generation (M8):** move greedy mesh + column gen to compute. *Payoff: streaming no
   longer CPU-bound; supports faster traversal / bigger rings.*

(M5 multiplayer stays last by direction; when it lands, the edit journal IS the replication payload —
server owns the authoritative deltas, clients receive region delta streams via `NetVoxelCodec`.)

---

## 12. Open decisions for the designer

1. **Vista fidelity:** is the EXR heightmesh (T3) enough for the horizon, or do you want voxel-accurate
   far detail (T4 GPU ray-march)? T3 first regardless; T4 is later polish.
2. **Permanent player lakes:** should settled finite-water pools persist to the edit journal (player can
   build a reservoir that's there on reload), or is water always transient until it touches a source?
3. **Edit durability scope:** do edits persist forever (single big world save) or per-save-slot? Affects
   where region files live.
4. **Disk-cache budget:** default cap (5 GB? 20 GB?) and where it lives (project Saved/ vs user dir).
5. **Traversal speed:** top movement speed (walk vs mount vs vehicle/flight) sets the prefetch radius and
   whether P8 GPU meshing is required sooner.
6. **Altitude scaling of the import:** your EXR uses 0–0.31 of its range (peaks ~219 m at altitude 700).
   Lock a final vertical scale so the heightmesh, voxels, and gameplay all agree on "how tall is a
   mountain."

---

## TL;DR
The world is **the EXR + a thin edit journal**, never 2.5 billion voxels. Render it in **tiers** — live
voxels near, downsampled/Nanite voxels mid, a single **EXR heightmesh for the vista**, optional GPU
ray-march for far detail. **Stream** the near/mid tiers around the player on worker threads with a
per-frame upload budget. **Persist** only edits (authoritative region deltas); **cache** the expensive
rebuildable results (bricks, meshes, bakes) to disk with an LRU budget and a content-hash key. Cost scales
with **view radius, not world size**, which is what makes a 5 km 10 cm world shippable.
