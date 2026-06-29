# Terrain Bake Pipeline — Designer's Usage Guide

How to bake the whole Mira-Thal map into Nanite "crust" terrain at any resolution you like.
Written for the designer (not a programmer): plain English, real examples, and a troubleshooting
list at the bottom. The tools live in the repo root, `"C:/Users/Matt Noles/Test-ue5"`.

> **What is a "bake"?** The live voxel world (the editable 10 cm cubes around the player) is too
> expensive to draw across a whole 5 km × 5 km map. So we pre-cook the *surface shell* of the map
> into cheap, frozen Nanite meshes called the **crust**. Baking is that pre-cook. You run it once
> per resolution; the game then streams the result around the player. See
> `UE5_ROAMING_CLIPMAP.md` for how the crust feeds the game.

> ## ⚠️ Re-bake everything baked before 2026-06-22 (the mesher fix)
>
> A bug in the mesher (the code that turns voxels into a mesh) meant that any baked tile
> bigger than 32 cells across only got its **first 32 cells** turned into geometry — the rest
> of the tile rendered as nothing. On screen that looked like a regular grid of holes
> ("checkerboard gaps") in the far terrain. It hit the fine bakes hardest: a 10 cm tile is 96
> cells across, so only about a third of it showed. (40 cm happened to work by luck because
> its tile is exactly 32 cells.) **This is now fixed** (see the box just below), but the fix is
> in the *baker*, so **every bake made before the fix is wrong and must be re-baked** — that
> means the old `10cm`, `L1` (1.6 m), and `L2` (6.4 m) layers. Re-baking is the only cure;
> there's no way to patch the old files. Just re-run the bake for each tier.

> ## The mesher fix, in one paragraph (background — you don't act on this)
>
> The mesher used to assume every tile was the live-chunk size (32 cells) and only ever meshed
> 32 cells, no matter how big the tile actually was. Baked "crust" tiles are bigger than that
> (up to 96 cells), so they came out partly invisible. The fix makes the mesher mesh the tile's
> *real* size instead of a hardcoded 32. Live editable chunks are unaffected (they really are 32
> cells, so they behave exactly as before). The fix lives in
> `Source/MiraThalVoxel/Private/Core/GreedyMesher.cpp` and is locked in by a test
> (`tests/standalone/test_mesher.cpp`, the "oversized slab" case) so it can never silently
> regress.

---

## TL;DR — bake the whole map

There are two ways. Both do the same thing under the hood.

### 1. The menu (easiest — just pick a number)

Double-click **`Bake-Terrain-Menu.bat`** in the repo root. You get a table:

```
 #   CUBE     ~TILES     ~DISK      ~TIME      NOTES
[1]  10 cm    ~275,000   ~4-6 GB    8-15 hrs   OVER the file wall *
[2]  20 cm     ~70,000   ~1.3 GB    3-4 hrs    PAST the wall (borderline) *
[3]  40 cm     ~17,000   ~300 MB    ~1 hr      heavy but OK
[4]  80 cm      ~5,000   ~150 MB    ~20 min    sweet spot  (RECOMMENDED)
[5]  1.6 m      ~2,000    ~40 MB    ~12 min    coarse / cheap
[6]  custom    (enter your own cube size in cm)
[0]  quit
```

Pick a number. It then asks for:
- a **save name** (press Enter to accept the default `MiraStreamTest_<cube>cm`), and
- **parallel jobs** (press Enter for "auto" — it picks a safe number for your PC).

Then it reminds you to close the editor and runs the bake.

### 2. The one-liner (when you know what you want)

Run **`Rebake-Terrain.bat`** with up to three arguments:

```
Rebake-Terrain.bat  <cubeCm>  [saveName]  [jobs]
```

Examples:

```bat
Rebake-Terrain.bat 80                  :: 80 cm, auto-parallel  (the recommended tier)
Rebake-Terrain.bat 40 MyFine 12        :: 40 cm, named "MyFine", forced to 12 processes
Rebake-Terrain.bat 10 Mira10cm         :: 10 cm whole map, auto-parallel (this takes hours)
```

`cubeCm` defaults to `80` if you omit everything. The save name defaults to
`MiraStreamTest_<cubeCm>cm`. Jobs blank/omitted = auto.

Both scripts are thin wrappers; the real work happens in **`Rebake-Terrain.ps1`**, the engine.

---

## What the knobs mean (in plain English)

| Knob | What it does | Sensible default |
|---|---|---|
| **Cube size** (`-CubeCm`) | The size of each terrain cube in centimetres. Smaller = finer detail = WAY more files and time. The world is 10 voxels per metre, so 10 cm is one voxel; 80 cm is 8 voxels per cube. | **80 cm** for the near tier |
| **Save name** (`-Name`) | Where the result lands: `/Game/VoxelBake/<name>`. Use a clear name per tier so you can point the game at it. | `MiraStreamTest_<cube>cm` |
| **Jobs** (`-Jobs`) | How many headless editor copies run at once. More cores = faster bake. "Auto" picks a safe number from your CPU and RAM. `1` = single slow process. | **auto** (leave blank) |
| **Shard size** (`-ShardTiles`) | How many tiles each parallel job chews through before saving and freeing its memory. This is the **memory lever**: peak RAM per job scales with this number (region-pack and geo-merge hold a whole shard's meshes in memory until the shard saves). Smaller = safer on RAM but slightly more overhead. Default is **2000**. Only raise it if you have lots of RAM (and a big pagefile — see the memory section below). | **2000** (leave it) |
| **Region-packing** (`-Region`) | How many tiles get packed into ONE file. `0` = one file per tile (normal). `8` = pack 8×8 tiles per file — fewer files, used to survive very fine bakes. Auto turns this ON for 10/20 cm. | **auto** (off above 20 cm) |
| **Nanite** (`-Nanite`) | `1` = build Nanite meshes (sub-pixel LOD, best for near/fine detail). `0` = plain static meshes (build much faster, fine for coarse far terrain). Auto turns it OFF at 1.6 m and coarser. | **auto** (on below 1.6 m) |
| **Skirt** (`-Skirt`) | A downward "lip" baked under each tile's edge so you never see cracks/gaps between tiles. Scales with resolution automatically (~4 cubes deep). | **auto** (leave at 0) |
| **Geometry merge** (`-GeoMerge`) | The *shipping* version of region-packing. Region-packing groups tiles into fewer FILES but each is still its own mesh; `-GeoMerge` actually FUSES a region's tiles into ONE mesh + one entry, cutting both file AND asset count ~64×. Tradeoff: a whole region loads/unloads as one unit (coarser streaming), so it's for FAR tiers. Forces region-packing on. | **off** (turn on for the final shipping cook) |

You almost never need to touch Region, Nanite, or Skirt — the script auto-picks good values from
the cube size. Cube size and (optionally) jobs are the only knobs you normally set.

---

## Resolution → tiles / disk / time, and the "file wall"

This is the whole map (5 km × 5 km), with the normal one-file-per-tile layout. The baker
auto-clips to the coastline, so ocean tiles are never produced.

| Cube | Tiles (files) | Disk | Bake (parallel) | Verdict |
|---|---|---|---|---|
| 10 cm | ~275,000 | ~4–6 GB | ~1–2 h on many cores (8–15 h single) | **over the file wall** |
| 20 cm | ~70,000 | ~1.3 GB | ~30–60 min | past the wall (borderline) |
| 40 cm | ~17,000 | ~300 MB | ~15–25 min | heavy but OK |
| 80 cm | ~5,000 | ~150 MB | ~5–10 min | **sweet spot (current near tier)** |
| 1.6 m | ~2,400 | ~45 MB | ~3–5 min | mid tier |
| 6.4 m | ~170 | ~10 MB | <1 min | far tier |

### The "file wall"

The danger with 10 cm and 20 cm is NOT disk space — it's the **number of files**. Hundreds of
thousands of one-file-per-tile assets choke Unreal's asset registry, the cook, and source control.
The disk size stays small; the file *count* is what hurts.

The escape hatch is **region-packing** (the `-Region` knob), which packs many tiles into a few
large files. The menu auto-enables it for 10/20 cm and warns you before proceeding. For everyday
work, stay at 40 cm or coarser and you never hit the wall.

> Rule of thumb: a cube reads well on screen at a distance of about `cube × 500`. So 80 cm cubes
> look crisp out to ~400 m, which is why 80 cm is the near tier. Coarser cubes are fine far away.

---

## IMPORTANT gotchas — read before your first bake

1. **CLOSE the GUI editor first.** The bake launches its OWN hidden headless editor copies. If your
   normal editor is open, the bake can collide with it or produce nothing. Shut the editor down
   completely before you start.

2. **First bake is slow — that's the one-time shader pre-warm.** On a cold cache (or right after a
   code rebuild), the parallel bake runs ONE warm-up process first to compile the Nanite shaders
   into the shared cache. You'll see `pre-warming shader cache...` — this can take a few minutes.
   Later bakes find the cache warm and skip it. This is expected, not a hang.

3. **Don't trust the "exit code" — trust the output.** These headless editor processes exit with a
   non-zero (failure-looking) code on shutdown *even when the bake succeeded.* The script knows this
   and judges success by the actual output: the shard files on disk and the merge log line
   `MergeShards: ... saved=1`. A `SUCCESS` line at the end means it worked, regardless of any scary
   exit numbers.

4. **Don't crank "jobs" too high — it will run out of memory.** Each headless copy peaks around
   6–7 GB of RAM (RHI + Nanite build) for ordinary tile bakes, and **much more** for geo-merge
   (the big fused region meshes are ~1.6M vertices each, so a geo-merge job is RAM-heavy — figure
   roughly **4 parallel jobs max on a 64 GB machine**). The auto setting budgets per job and never
   exceeds (cores − 2). If you force `-Jobs` too high, shards get OOM-killed mid-bake and die
   silently. (Real example: 10 jobs on a 64 GB machine killed 6 shards.) If unsure, leave jobs on
   **auto**. See the **memory reality** section below before trying to push the job count up.

5. **Each process writes its own log.** If something looks wrong, the per-shard logs are here:
   ```
   ue5/MiraThal/Saved/Logs/bake_<name>_shard*.log
   ```
   Plus `bake_<name>_warmup.log` (the pre-warm) and `bake_<name>_merge.log` (the final merge). For a
   single-process bake it's `bake_<name>.log`. Open these to see what actually happened.

---

## What happens during a parallel bake (so the console makes sense)

You don't need this to use the tool, but it explains what you're watching:

1. **Auto-pick jobs** from your cores and RAM (`auto jobs=...`).
2. **Pre-warm** the shader cache with one process, then delete the throwaway (`pre-warming...`).
3. **Batched sharding** — the map is split into many small shards (~6,000 tiles each), and only
   `jobs` of them run at a time. Each shard finishes and frees its memory before the next batch
   starts, so a 275,000-tile bake never piles all that memory up at once.
4. **Merge** — once every shard has written its little text shard-file, one final `-Merge` pass
   stitches them into the real `Manifest.uasset` and deletes the shards.
5. **SUCCESS** line with the tile count and the `/Game/VoxelBake/<name>` path.

(Single-process bakes — `jobs 1` — skip the sharding and merge; that one process writes the
manifest directly.)

---

## The memory reality (why bakes are capped at a few jobs)

This is the single thing most likely to make a big bake fail, so it's worth understanding in plain
English.

**How the bake uses memory.** Region-packing and geo-merge both hold a shard's finished meshes in
memory until that shard saves itself to disk. So the peak memory a single job uses scales with
**how many tiles are in a shard** — that's the `-ShardTiles` knob (default 2000). Run several jobs
at once and you multiply that. Geo-merge is the heaviest case: each fused region mesh is around
**1.6 million vertices**, so a geo-merge job eats a lot of RAM. On a 64 GB machine that works out
to roughly **4 parallel jobs at most** for a geo-merge bake. Going higher gets shards killed.

**The pagefile truth (important — this trips people up).** Windows has a "commit limit" that is your
physical RAM **plus** the pagefile size. If you make the Windows pagefile bigger, you raise that
commit limit, which stops one *particular* crash — the "your system is low on memory / paging file
too small" error — from killing the bake. **But a bigger pagefile does NOT give you more real (fast)
memory.** The pagefile lives on disk and is hundreds of times slower than RAM. So for the heavy
geo-merge bakes, **physical RAM is the real ceiling** on how many jobs you can run — a giant pagefile
will not let you run more geo-merge jobs, it just prevents one specific out-of-commit crash. If you
want more geo-merge jobs, you need more physical RAM, not more pagefile.

**Bottom line:** leave jobs on auto and `-ShardTiles` at 2000 and the bake stays inside the limit.
Only raise either if you genuinely have spare physical RAM.

---

## Where the baked files actually live (the D: drive junction)

The bake can produce gigabytes of files, and the small fast C: SSD doesn't have room to spare. So the
folder Unreal writes the bake into — `ue5/MiraThal/Content/VoxelBake` — is **not really on C:**. It's a
Windows **directory junction** (a kind of invisible shortcut) that quietly redirects everything written
there to **`D:\MiraThalVoxelBake`** on the bigger D: drive. This is completely transparent: Unreal, the
bake scripts, and the editor all see a normal `Content/VoxelBake` folder and never know the difference;
the bytes just land on D: instead of C:. You don't have to do anything — just know that if you go
looking for the actual baked `.uasset` files on disk, they're on D:, not C:.

---

## After baking: wiring the result into the game

The bake produces a folder at **`/Game/VoxelBake/<name>`** containing the tile meshes and a
**`Manifest`** asset (the index of all tiles). To actually see it in-game:

1. Open the map `MiraStreamTest` in the editor.
2. Select (or add) a **`VoxelNaniteCrust`** actor for the tier you baked.
3. Point its **Manifest** property at `/Game/VoxelBake/<name>/Manifest`.
4. Set its **Inner / Outer chunk band** — the distance range (in chunks from the player; 1 chunk =
   3.2 m) over which this tier should stream in. Finer tiers get a near band; coarser tiers get a
   far band. See the clipmap table in `UE5_ROAMING_CLIPMAP.md` for the current live values.
5. Save the level.

The crust streamer is player-relative, so once wired, the tiles follow the player anywhere on the
map. Multiple tiers (e.g. 80 cm near, 1.6 m mid, 6.4 m far) layer together — finer tiers sit on top
of coarser ones via their "sink" ordering (also in `UE5_ROAMING_CLIPMAP.md`).

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Logs full of **"null UStaticMesh"**, every tile fails | The headless run lost `-AllowCommandletRendering`. Building Nanite needs the renderer (RHI), which a plain commandlet skips. | The scripts always pass it — if you're running the commandlet by hand, add `-AllowCommandletRendering`. |
| Shards **die mid-bake / out of memory (OOM)** | Too many jobs for your RAM (each peaks ~6–7 GB). | Lower `-Jobs`, or just leave jobs on **auto** (it caps by RAM). |
| **Nothing got baked / no shard files** | The GUI editor was still open, or you baked the wrong map. | Close the editor completely and re-run. Confirm the map is `MiraStreamTest`. Check `Saved/Logs/bake_<name>_shard*.log`. |
| Bake printed a **non-zero exit code** but everything looks fine | Normal — commandlets exit non-zero on shutdown. | Ignore the exit code. Look for the `SUCCESS` line and `MergeShards: ... saved=1` in the merge log. |
| **MERGE FAILED** at the end | Some/all shards never wrote their shard file (often an earlier OOM or a crash). | Open `Saved/Logs/bake_<name>_merge.log` and the per-shard logs; usually re-run with fewer jobs. |
| 10/20 cm bake makes the project **slow / source control struggles** | The "file wall" — too many one-file-per-tile assets. | Use region-packing (auto-on for 10/20 cm), or bake a coarser tier. Disk size isn't the problem; file count is. |
| First bake **seems stuck** at "pre-warming" | One-time shader compile on a cold cache. | Wait a few minutes — it's compiling, not frozen. Later bakes skip it. |

---

## Quick reference — full commandlet flags (advanced)

The scripts call `UnrealEditor-Cmd.exe ... -run=VoxelCrustBake` under the hood. You normally never
touch this, but for the record the flags are:

| Flag | Meaning |
|---|---|
| `-Map=<path>` | Map to load and bake (the script uses `/Game/Maps/MiraStreamTest`). |
| `-WorldSaveName=<name>` | Output folder name → `/Game/VoxelBake/<name>`. |
| `-Tile=<voxels>` | Tile span in voxels (script computes from cube size; fixed coarse side of 96 = fewest files). |
| `-Stride=<n>` | Voxels per cube (cubeCm ÷ 10). |
| `-Skirt=<voxels>` | Skirt depth (the anti-crack lip under each tile). |
| `-Radius=<n>` | Tile radius from centre (covers the whole half-map; clip trims the overflow). |
| `-MaxTiles=<n>` | Cap on tiles (used only by the 1-tile pre-warm). |
| `-TestRing=<n>` | Bake only a small ring of chunks (test bakes). |
| `-Shards=<N> -Shard=<i>` | Parallel sharding: process `i` bakes every Nth tile. |
| `-Region=<n>` | Region-packing: tiles-per-side packed into one file (0 = off). |
| `-Nanite=<0/1>` | Build Nanite (1) or plain static meshes (0). |
| `-GeoMerge` | Fuse each region's tiles into ONE merged mesh + ONE manifest entry (shipping-scale asset-count reduction). Forces region-packing on; sets the manifest span to the region width so the runtime crust streams it unchanged. |
| `-Merge` | Final pass: combine all shard files into the real `Manifest.uasset`. |
| `-AllowCommandletRendering` | **Required** — gives the headless run a renderer so Nanite can build. |
```
