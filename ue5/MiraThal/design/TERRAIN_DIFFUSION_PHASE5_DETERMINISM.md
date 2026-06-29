# TerrainDiffusion Phase 5 — Determinism, Saves & Multiplayer Parity (design)

**Status:** DESIGN ONLY (2026-06-28). No code written. Implements Phase 5 of
`TERRAIN_DIFFUSION_RUNTIME_PLAN.md` ("Determinism & saves / multiplayer parity"). Read that master
plan first; this doc is the concrete build sheet for that paragraph.

> Plain-English: AI terrain is generated on each player's own graphics card. The problem: two
> different graphics cards (AMD vs NVIDIA vs Intel, or even different drivers) do floating-point math
> *slightly* differently, so the AI model produces *almost*-identical-but-not-bit-identical heightmaps.
> In single-player that's invisible. In multiplayer it's a disaster: my mountain is 0.3 cm taller than
> yours, our voxel worlds diverge, and we desync. The fix has two parts: (1) the **server** runs the
> AI once and sends the small coarse heightmap to everyone (so everyone builds from the *same* numbers),
> and (2) we **snap the AI's float output to whole millimetres/metres as integers** before it enters the
> voxel pipeline, so any tiny float wobble collapses to the exact same integer height. Everything below
> that point is already integer math, so it stays identical for free. Saves just store the seed + region
> + which model version made the terrain — never the heightmap itself.

---

## 0. Why per-client GPU inference is NOT safe for parity

- **Floating-point is not associative across hardware.** Different GPUs/drivers reorder reductions, use
  different fused-multiply-add behaviour, different fast-math, different DML kernel selections. ONNX
  Runtime + DirectML makes **no cross-vendor bit-exactness guarantee.** Even the same vendor across
  driver versions can differ.
- Our own Gate-1 parity test only asserts **`max-abs-err < tol`** against the Python golden (master
  plan Gate 1) — i.e. *approximately* equal, explicitly NOT bit-equal. That tolerance is fine for
  "does it look right," fatal for "do two machines agree to the bit."
- A heightmap that differs by even 1 ULP, once amplified through the 30 m→10 cm detail bridge and the
  voxel quantization, can flip a voxel boundary → different collision, different carve results →
  **multiplayer desync.** So: **never rely on per-client inference matching.** (Master plan top-risk
  #6.)

**The contrast that makes the fix easy:** everything *downstream* of the model is already deterministic.
The detail synthesis (`mira::tdiff::DetailBridge`, `Core/Tdiff/DetailBridge.h`) is **integer-hashed** —
its randomness comes from `mira::noise` integer hashes:
`hash_u64()` (SplitMix64, `Core/Noise.h:53`) and `lattice_value()` (`Core/Noise.h:63`) which mix
`int64` lattice coords + seed through integer multipliers. `PortableRng.h` (PCG64) is likewise integer.
**Same (seed, x, z) → same height on every machine, today.** The ONLY non-deterministic link in the
chain is the GPU float output of the 3 UNets. Fix that one link and the whole chain is parity-safe.

---

## 1. The fix in one diagram

```
 [SERVER ONLY]
   seed + region + model-version
        │
        ▼
   AI inference (GPU, ORT-DML)  ── floats, vendor-specific ──┐
        │                                                     │  NOT replicated (would desync)
        ▼                                                     │
   FCoarseDem (float [0,1], 64×64-ish)                        │
        │                                                     │
        ▼   ◀── QUANTIZATION POINT (the parity firewall) ─────┘
   int16 metre-quantized coarse DEM  ──── replicated to all clients ────▶ [EVERY CLIENT]
        │                                                                       │
        ▼                                                                       ▼
   (identical integers on server + all clients)                    same int16 coarse DEM
        │                                                                       │
        ▼                                                                       ▼
   ImageHeightmap (dequantized identically) ────────────────────────── ImageHeightmap (identical)
        │                                                                       │
        ▼                                                                       ▼
   DetailBridge (integer-hashed, deterministic) ──────────────────── DetailBridge (identical)
        │                                                                       │
        ▼                                                                       ▼
   compute_ground_y (HeightmapGenerator.cpp:377) ────────────────── compute_ground_y (identical)
        │                                                                       │
        ▼                                                                       ▼
   voxels, cliffs, water, carve, collision ──── bit-identical across all machines ────
```

Two mechanisms, both required:
1. **Server-authoritative DEM replication** — only the server runs the AI; clients receive the result.
   (Removes the *cross-client* divergence.)
2. **int16-metre quantization at the model→pipeline boundary** — collapses residual float wobble to
   integers *before* anything reads it. (Makes the replicated payload exact AND keeps single-player /
   re-generation reproducible even if the same machine's GPU drifts between runs/driver updates.)

---

## 2. Quantization point (the parity firewall)

**Where:** at the *exit* of the coarse-DEM provider, immediately after `FCoarseDem` is produced and
**before** `BuildHeightmapFromCoarse(...)` (`DiffusionDemService.h:125`). This is the single chokepoint
every consumer is downstream of — the same architectural logic as the `compute_ground_y` height-source
seam (`HeightmapGenerator.cpp:377`).

**What:** quantize each normalized elevation to a fixed integer grid, then dequantize deterministically.

- `FCoarseDem.Cells` are normalized floats in `[0,1]` (`DiffusionDemService.h:42-49`).
- Convert to **absolute metres** via the service's vertical mapping
  (`VerticalScaleVoxels=7000`, `VerticalBaseVoxels=120` at 10 vox/m → ~700 m range,
  `DiffusionDemService.h:159-160`), then store as **int16 metres** (or int16 decimetres for finer
  resolution — see below).
- **Resolution choice:** at 30 m/px the AI is macro-only; metre precision in the *coarse* DEM is
  plenty (the detail bridge synthesizes everything finer). int16 metres covers ±32 km of elevation —
  vastly more than needed. If a finer coarse step is ever wanted, use int16 **decimetres** (±3.2 km).
  **Default: int16 metres**, `CoarseQuantStepMetres = 1.0`.
- Quantize with a **fixed rounding rule** (round-half-to-even or round-half-up — pick one and freeze
  it; it must be identical in C++ everywhere). Integer math only: `q = (int16)floor(metres / step + 0.5)`.
- Dequantize identically on every machine: `metres = q * step`. From here `ImageHeightmap` stores the
  dequantized float, but since every machine started from the **same int16**, they get the **same
  float** — bit-identical, because `int*float` of the same operands is deterministic in IEEE-754.

> Why this kills the wobble: two GPUs might emit `0.41732` vs `0.41729`. Both → `292.something m` →
> both round to int16 `293`. From `293` onward, every machine is identical. The float diff is
> *quantized away* below the voxel-relevant resolution.

**Knobs + defaults**
| Knob | Default | Meaning |
|---|---|---|
| `CoarseQuantStepMetres` | `1.0` | int16 quantization step for the coarse DEM. |
| `CoarseQuantRounding` | `HalfUp` | Frozen rounding rule (must match on all builds). |
| `bQuantizeCoarseDem` | `true` | Master switch (off only for golden-parity debugging). |

---

## 3. Server-authoritative DEM replication

### Authority model
- **Only the server runs AI inference.** Clients NEVER run the UNets for gameplay terrain (they may
  still own the renderer-side detail bridge — that's deterministic and CPU-side).
- The server resolves a region via `FDiffusionDemService` (Phase 4 path), quantizes (§2), and the
  result becomes the authoritative coarse DEM for that `FRegionKey`.
- Clients request/receive the int16 coarse DEM and feed it into their *own*
  `BuildHeightmapFromCoarse` → identical `ImageHeightmap` → identical voxels.

### Replication payload
Replicate the **quantized coarse DEM**, not the upsampled heightmap and definitely not voxels.

```
struct FReplicatedCoarseDem      // the wire format
{
    int64   Seed;                // 8 B
    int32   RegionMinX, MinZ;    // 8 B  (world voxels — matches FRegionKey, DiffusionDemService.h:129)
    int32   RegionMaxX, MaxZ;    // 8 B
    uint32  ModelVersionHash;    // 4 B  (see §5; rejects mismatched weights)
    int16   CoarseW, CoarseH;    // 4 B
    TArray<int16> Cells;         // 2 B × W×H, quantized metres, row-major (z-major)
};
```

**Size:** for a 64×64 coarse grid (the golden reference shape, `DiffusionDemService.h:107-113`):
`64×64×2 B = 8 KB` + ~40 B header ≈ **8 KB per region**. Even a generous 256×256 region is **128 KB**.
Tiles are small *because the AI is 30 m/px* — this is the whole reason replication is cheap (master
plan Phase 5: "tiles are small at 30 m/px"). A few resident regions = tens of KB on the wire.

### Transport
- **Do NOT use property replication** (UPROPERTY/`DOREPLIFETIME`) for this — there is no replication
  in the voxel module today (confirmed: no `DOREPLIFETIME`/`GetLifetimeReplicatedProps` anywhere) and
  per-region blobs are bursty, not per-frame state.
- Use a **reliable RPC / custom bunch** or a `FastArraySerializer`-backed list keyed by `FRegionKey`,
  sent on demand:
  - Client enters/approaches a region with no resident DEM → sends a `ServerRequestRegionDem(Seed,
    RegionRect)` reliable RPC.
  - Server replies `ClientReceiveRegionDem(FReplicatedCoarseDem)` (reliable; compress with the
    existing RLE path if useful — `Core/RegionFormat.h` already does varint+RLE+CRC32, reuse the
    encoder for the int16 array).
  - Late-joiners pull their start region the same way during load.
- **Compression:** int16 grids of smooth terrain RLE/delta-compress well; expect 8 KB → 2–4 KB.
  Optional; payload is already small.

**Knobs + defaults**
| Knob | Default | Meaning |
|---|---|---|
| `bServerAuthoritativeDem` | `true` | Clients never infer; always pull from server. |
| `bCompressDemPayload` | `true` | RLE-compress the int16 array (reuse RegionFormat). |
| `DemReplicationReliable` | `true` | Use reliable transport (terrain must arrive). |
| `MaxDemReplicationKBPerSec` | `256` | Throttle to avoid bunch saturation on join. |

---

## 4. Saves: store seed + region + model-version only

**Principle (already the world's save model):** the save stores *what regenerates the terrain*, plus a
delta log of player edits — never the terrain itself. `RegionFormat.h` / `WorldEditPersistence` already
do this for voxels: "Save the world as what the seed generator would produce, PLUS a log of every voxel
the player ever changed. Untouched terrain is never written to disk" (`Core/RegionFormat.h:1`).

For AI terrain, the save's *generation header* gains exactly three identity fields (the seed already
exists as `AVoxelWorld::Seed`):
- `DiffusionSeed` (already on `FGenParams`, `VoxelGenParams.h:~53`),
- region origin (`DiffusionRegionOriginX/Z`, already on `FGenParams`),
- **`ModelVersionHash`** (NEW — §5).

That's it. No heightmaps, no voxels for untouched terrain. On load, the same seed+region+model-version
regenerates bit-identical terrain (because of §2's quantization), and the edit delta log replays on top.

**Save-compatibility rule:** if a save's `ModelVersionHash` no longer matches the installed model, the
terrain *would* regenerate differently — see §5 for how the fingerprint catches this and invalidates
stale bakes/caches rather than silently corrupting a save.

---

## 5. Extend `FingerprintGenParams` with a model-version hash

`FingerprintGenParams` (`VoxelGenParams.h:150`) is the FNV-1a fingerprint that identifies a generation
configuration; it already hashes the diffusion identity:

```cpp
if (P.bDiffusionAI) {                                   // VoxelGenParams.h:~180
    FingerprintMix(Hash, (uint64)P.DiffusionSeed);
    FingerprintMixDouble(Hash, P.DiffusionRegionOriginX);
    FingerprintMixDouble(Hash, P.DiffusionRegionOriginZ);
}
```

**Add the model-version hash into this block** so that changing the model weights (e.g. the §7-Phase-4
quantized base model, or any re-export) changes the fingerprint → invalidates every stale Nanite bake,
disk tile, and replicated DEM keyed by it:

```cpp
if (P.bDiffusionAI) {
    FingerprintMix(Hash, (uint64)P.DiffusionSeed);
    FingerprintMixDouble(Hash, P.DiffusionRegionOriginX);
    FingerprintMixDouble(Hash, P.DiffusionRegionOriginZ);
    FingerprintMix(Hash, (uint64)P.DiffusionModelVersion);   // NEW
}
```

- `DiffusionModelVersion` is a new `uint64` on `FGenParams` (set by `SnapshotGenParams`,
  `VoxelGenParams.h:206`), sourced from a hash of the three .onnx files' content (compute once at
  model load in `FNNEUNetRunner`, e.g. CRC/SHA of the weight bytes, folded to u64) plus the
  quantization knobs (`CoarseQuantStepMetres`, `CoarseQuantRounding`) — because changing quantization
  *also* changes the output.
- This is the same fingerprint that gates the Nanite cold-bake validity (the bake and runtime share
  the `compute_ground_y` path, master plan §"Why this approach"). So a model swap correctly forces a
  rebake instead of mixing old-model crust with new-model streaming.

**Knobs + defaults**
| Knob | Default | Meaning |
|---|---|---|
| `DiffusionModelVersion` | hash of 3 onnx + quant knobs | Identity of the weights+quantization that made the terrain. |
| `bRejectStaleModelSaves` | `true` | On load, warn + offer regenerate if save's model-version ≠ installed. |

---

## 6. Disk tile cache keyed by fingerprint

Persist resolved coarse DEMs to disk so the server (and single-player) skip re-inference across
sessions, AND so the cache self-invalidates on model change.

- **Key:** the `FingerprintGenParams` value (now including model-version) + `FRegionKey`. Filename e.g.
  `Saved/DiffusionDem/<fingerprint16hex>/r_<minX>_<minZ>.dem`.
- **Payload:** the int16 quantized coarse DEM (§2/§3 format) + a small header (CoarseW/H, model-version,
  CRC32). Reuse `Core/RegionFormat.h`'s varint+RLE+CRC32 encoder for the int16 array.
- **Invalidation is automatic:** change the model or quantization → fingerprint changes → new directory
  → old tiles are ignored (and can be GC'd). No stale-data bug possible.
- **Lookup order at resolve time:** (1) RAM cache (`FDiffusionDemService::Cache`,
  `DiffusionDemService.h:157`) → (2) disk tile cache → (3) run inference (server only) → write back to
  disk + RAM. Clients: (1) RAM → (2) disk → (3) request from server (never infer).

**Knobs + defaults**
| Knob | Default | Meaning |
|---|---|---|
| `bDiskTileCacheEnabled` | `true` | Persist + reuse coarse DEMs across sessions. |
| `DiskTileCacheMaxMB` | `256` | LRU-evict whole fingerprint dirs over this (tiles are KB; 256 MB = thousands). |
| `DiskTileCacheDir` | `Saved/DiffusionDem` | Root. |

---

## 7. Multiplayer parity test plan

The goal: prove two different machines (ideally two different GPU vendors) produce **bit-identical**
voxel worlds for the same seed/region/model-version.

### 7a. Headless determinism (no GPU, no network) — the cheap gate
- Extend the standalone clang harness (`tests/standalone/`, alongside `test_tdiff_*.cpp`):
  - **`test_tdiff_quantize.cpp`** — feed a coarse float DEM with deliberate ±epsilon perturbations
    (simulating GPU wobble); assert the int16-quantized output is identical across perturbations
    within `CoarseQuantStepMetres`. Proves §2 collapses wobble.
  - **`test_tdiff_dequant_pipeline.cpp`** — from a fixed int16 DEM, run `BuildHeightmapFromCoarse` +
    `DetailBridge::sample_height_voxels` for many columns; assert byte-identical heights across two
    builds/compilers. Proves the downstream chain is deterministic (it already is — integer-hashed).
  - Run on Windows AND (if available) a second toolchain to catch any accidental float-order
    dependence in our own C++.

### 7b. Cross-vendor inference divergence measurement (informational, not a gate)
- On two machines (RX 7800 XT + an NVIDIA/Intel box), run the Gate-1/latency commandlet for the same
  seed/region; dump the **raw float** coarse DEMs and diff them. Expect small but nonzero max-abs-err.
  This *documents the problem* (justifies §3) — it is NOT expected to pass bit-equality.

### 7c. Cross-vendor PARITY gate (the real test)
- Same two machines. Server (machine A) infers + quantizes + replicates. Client (machine B) receives.
- Both write a **world fingerprint**: hash of the int16 coarse DEM + a hash of N sampled
  `compute_ground_y` columns across the region (reuse the FNV mixers from `VoxelGenParams.h`).
- **PASS iff the fingerprints are bit-identical.** This proves replication + quantization deliver
  parity end-to-end through the voxel seam.
- Add a **carve-replay sub-test:** both machines apply the same scripted edit sequence (via the
  existing edit gateway / `WorldEditStore`); assert the resulting region delta logs
  (`WorldEditPersistence`) are byte-identical. Proves gameplay edits stay in sync on top of identical
  terrain.

### 7d. Save round-trip gate
- Save on machine A (seed+region+model-version+edit log only — §4). Load on machine B. Assert the
  loaded world fingerprint (7c) matches. Then bump the model version and assert
  `bRejectStaleModelSaves` triggers the regenerate path rather than silently diverging.

---

## 8. Ordered implementation checklist

1. **Add the quantization firewall** (§2): int16-metre quantize/dequantize at the `FCoarseDem` exit,
   before `BuildHeightmapFromCoarse` (`DiffusionDemService.h:125`). Freeze the rounding rule. Add
   `bQuantizeCoarseDem`, `CoarseQuantStepMetres`, `CoarseQuantRounding`.
2. **Add `DiffusionModelVersion`** to `FGenParams` (`VoxelGenParams.h`), set in `SnapshotGenParams`,
   sourced from a content hash of the 3 .onnx files (computed in `FNNEUNetRunner` at load) + quant
   knobs.
3. **Extend `FingerprintGenParams`** (`VoxelGenParams.h:150`) to mix `DiffusionModelVersion` into the
   `bDiffusionAI` block.
4. **Build the disk tile cache** (§6): fingerprint+region keyed, int16 payload, RLE via
   `Core/RegionFormat.h`; wire the RAM→disk→infer lookup order into the Phase-4 request path.
5. **Add server-authoritative replication** (§3): `FReplicatedCoarseDem` wire format, request/reply
   reliable RPCs (or FastArraySerializer), client-never-infers gate (`bServerAuthoritativeDem`).
   (First replication in the voxel module — none exists today.)
6. **Wire saves** (§4): persist seed+region+model-version in the generation header; on load, compare
   model-version (`bRejectStaleModelSaves`).
7. **Headless determinism tests** (§7a) — gate before any GPU/network work.
8. **Cross-vendor measurement + parity + carve-replay + save round-trip** gates (§7b-d).

## 9. Verification plan
- **Green gate first:** §7a headless tests pass in the clang harness ("ALL HARNESSES GREEN") before
  touching engine replication.
- **Single-player regression:** with `bQuantizeCoarseDem=true`, terrain still matches the Python
  golden within the existing Gate-1 tolerance (quantization must not visibly change macro shape —
  metre steps are far below the 30 m/px AI resolution).
- **MP parity:** §7c cross-vendor fingerprint equality is the hard PASS/FAIL. Run it on RX 7800 XT vs
  a second vendor box via the mcp-unreal bridge; CLAUDE reads the dumped fingerprints to confirm.
- **Model-swap safety:** bump weights → fingerprint changes → stale bakes/tiles/saves invalidate
  (rebake forced, `bRejectStaleModelSaves` fires) — confirm no old-model/new-model mixing.
- Designer drives the two PIE sessions; CLAUDE diagnoses from the fingerprint dumps and
  `Saved/MiraThalPerf.csv` (per the headless-workflow memory entry).
