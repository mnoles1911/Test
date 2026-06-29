# TerrainDiffusion — Phase 7: Shipping / Packaging the AI height source

**Status:** DESIGN / RESEARCH ONLY (no code in this doc). Written 2026-06-28.
Companion: `design/TERRAIN_DIFFUSION_RUNTIME_PLAN.md` (Phases 5–7), `design/TERRAIN_DIFFUSION_PHASE6_RDG.md`.

> Plain-English: Gate 1 has PASSED — all three diffusion UNets run on the AMD RX 7800 XT through
> NNE's ONNX Runtime + DirectML backend, and match the PyTorch "golden" outputs to ~1e-5. But the
> way we load them **today only works inside the editor**: we read the raw `.onnx` bytes off disk and
> hand them to `UNNEModelData->Init("onnx", bytes)`. A **cooked, shipped game has no `.onnx` files on
> disk and no editor importer** — so before we can ship, the model has to become a real packaged
> *asset* the game can load like any other. This doc is the checklist + decisions to get there.

---

## 0. The one load-bearing fact that forces this whole phase

The current runner loads models from **loose `.onnx` file bytes**:

- `Source/MiraThalTerrainAI/Private/NNEUNetRunner.cpp:57` — `LoadWholeFile64()` reads the whole
  `.onnx` off disk (TArray64 because `base_model.onnx` is ~1.9 GB, past the 2 GB TArray32 ceiling).
- `NNEUNetRunner.cpp:120-137` — reads bytes → `NewObject<UNNEModelData>()` → `ModelData->Init("onnx", FileBytes)`.
- The path comes from a **filesystem directory** (`OnnxDir`), defaulting to `D:/terrain-diffusion/onnx*`
  (`TdiffGate1Commandlet.cpp:31`, `DiffusionCoarseProvider.h:38`).

This is the **editor/commandlet path**, and the header already calls it out:
`NNEUNetRunner.h:14-17` — *"In a cooked standalone game you would instead ship a pre-imported
UNNEModelData asset, because Init's file bytes are editor-only."* `Init("onnx", …)` relies on the
NNE **editor importer** to parse/optimize ONNX; that importer is **not in a cooked build**, and the
loose `.onnx` files are **not in the package**. Ship requires the asset path.

---

## 1. Two load paths, side by side (the core decision)

| | **A. Runtime bytes (today)** | **B. Cooked `UNNEModelData` asset (ship)** |
|---|---|---|
| Source | loose `.onnx` on disk (`OnnxDir`) | `/Game/AI/Terrain/*.uasset` |
| Build it via | `NewObject<UNNEModelData>()` + `Init("onnx", bytes)` | `LoadObject`/`TSoftObjectPtr.LoadSynchronous()` |
| Needs | NNE editor importer + DDC | nothing editor-only; data is cooked-in |
| Works in cooked game? | **No** (importer absent, files absent) | **Yes** |
| Works headless/commandlet? | **Yes** (what Gate 1 uses) | Yes (asset must be cooked/in editor) |
| Optimized-model cache | DDC (recompiled first run) | **cooked into the asset** at cook time (faster cold start) |

**Decision: ship path B; keep path A behind `WITH_EDITOR` for the Gate-1 commandlet and offline
parity work.** They are not mutually exclusive — the runner should support **both**, choosing by
build config. The commandlet (`TdiffGate1Commandlet`) and `golden` parity loop stay on A forever
(they want arbitrary `.onnx` from `D:/terrain-diffusion/...` without re-importing).

### Decision points
- **D1.** Does NNE 5.7 cook the *optimized/DirectML-specialized* model into `UNNEModelData`, or only
  the raw ONNX (re-optimized on first run from a packaged DDC)? → verify by inspecting a cooked
  `.uasset` size + first-run timing on a clean machine (see §7 checklist). Drives cold-start budget.
- **D2.** One asset per UNet (3 assets) vs a bundled container? → **3 assets** (matches `EUNetModel`
  Coarse/Base/Decoder, matches `GetModelStem()` stems, lets us stream/evict Base independently).

---

## 2. Importing the 3 ONNX as cooked assets

Goal: `coarse_model.onnx` / `base_model.onnx` / `decoder_model.onnx`  →
`/Game/AI/Terrain/coarse_model.uasset` / `base_model.uasset` / `decoder_model.uasset`.

Two ways to produce the `UNNEModelData` assets (pick one, automate it):

1. **Editor drag-drop import** — drag each `.onnx` into the Content Browser under
   `Content/AI/Terrain/`. The NNERuntimeORT plugin registers a `UNNEModelData` factory; the importer
   parses ONNX and stores it as the asset's payload. Simple, but manual and easy to forget to re-do
   when the model changes.
2. **Scripted import (preferred, reproducible)** — a small editor commandlet / Python that calls the
   asset import on all three and saves them. This is the *cook-prep* step and belongs in a script
   next to `Scripts/Rebake-Terrain.ps1` (call it e.g. `Import-DiffusionModels.ps1`). Re-runnable, and
   it's where the **fingerprint** (§5) gets recomputed and written.

> NOTE — `base_model.onnx` is ~1.9 GB. The import must use 64-bit-safe IO (the runtime path already
> does, `LoadWholeFile64`); confirm the editor importer doesn't choke on >2 GB. If it does, that
> alone forces the §6 mitigation (smaller/quantized base) *before* ship, not after.

### Checklist — asset import
- [ ] Create `Content/AI/Terrain/` folder.
- [ ] Import all 3 `.onnx` → `UNNEModelData` assets (scripted).
- [ ] Confirm each asset opens and reports the expected input/output tensor descs
      (matches `TdiffUNetRunner.h:90-93`: Coarse 7 in, Base 3 in, Decoder 2 in; 1 out each).
- [ ] Re-run the **Gate-1 parity check against the imported asset** (not the loose `.onnx`) to prove
      the asset round-trips bit-for-bit-equivalent to the file (within the existing 5e-3 tol).
- [ ] Commit assets via Git LFS or the project's large-asset store (2.2 GB — do NOT commit raw).

---

## 3. What changes in `NNEUNetRunner` for a cooked build

The runner already isolates loading into `LoadModel()` (`NNEUNetRunner.cpp:108`). Only **step 1–2**
(get a `UNNEModelData`) changes; steps 3–4 (runtime → `CreateModelGPU` → instance) and all of `Run()`
stay **identical** — that's the win of the current structure.

Proposed shape (design intent, not final code):

- Add a **`UNNEModelData*` source abstraction** with two implementations selected at compile time:
  - **Editor / commandlet (`#if WITH_EDITOR`)**: current `LoadWholeFile64` + `Init("onnx", bytes)`
    keyed off `OnnxDir`/`GetOnnxPath()` (`NNEUNetRunner.cpp:89-92`). Unchanged.
  - **Cooked (`#else`)**: resolve a `TSoftObjectPtr<UNNEModelData>` per `EUNetModel`,
    `LoadSynchronous()` (or async pre-load at subsystem init), use the returned `UNNEModelData*`.
- Replace the constructor's single `OnnxDir` string with a **model-source descriptor**: in editor it
  carries `OnnxDir`; in cooked it carries 3 soft refs (e.g. `/Game/AI/Terrain/coarse_model.coarse_model`).
  `FNNEUNetRunner(const FString& InOnnxDir)` (`NNEUNetRunner.h:70`) gains a second ctor / a config struct.
- The soft refs themselves should live as `UPROPERTY(TSoftObjectPtr<UNNEModelData>)` on a config
  object (a `UDataAsset` or the DEM subsystem's settings) so the cooker sees them and **pulls the
  assets into the package** (an un-referenced asset is cooked out — see §4).

### Checklist — runner changes
- [ ] Introduce model-source descriptor (editor: dir; cooked: 3 soft refs).
- [ ] `#if WITH_EDITOR` keeps the byte path; `#else` uses `LoadObject`/soft-ref load.
- [ ] Hold a `UPROPERTY`/`TStrongObjectPtr` on the loaded `UNNEModelData` so GC can't evict mid-run
      (the byte path already roots it via `TStrongObjectPtr`, `NNEUNetRunner.cpp:131` — keep that).
- [ ] `DiffusionCoarseProvider::Make()` / `Config.OnnxDir` (`DiffusionCoarseProvider.cpp:271-276`)
      gains the cooked-mode branch feeding soft refs instead of a dir.
- [ ] CPU fallback (`NNERuntimeORTCpu`, `NNEUNetRunner.cpp:177`) works the same against an asset —
      keep it as the no-DirectML safety net for shipped machines.

---

## 4. Cook / package settings + NNE plugin packaging

- **Plugins ship enabled.** `MiraThal.uproject:70-78` already enables `NNERuntimeORT` and
  `NNERuntimeRDG`. Confirm both are `"Enabled": true` for the **packaged target** (not editor-only)
  and that their runtime modules are not stripped.
- **Runtime DLLs in the package.** ORT-DML needs `onnxruntime.dll` **and**
  `Engine/Binaries/Win64/DML/x64/DirectML.dll` (per the runtime plan, line 32). Verify the staging
  step copies the DML dir into the packaged `Binaries/Win64/DML/`. Missing `DirectML.dll` → silent
  fall to CPU (or load failure) on the player's machine. This is the #1 thing to check on a clean box.
- **Assets get cooked.** Add `/Game/AI/Terrain` to **Additional Asset Directories to Cook**
  (Project Settings → Packaging) OR keep the soft refs `UPROPERTY` on a referenced object so they're
  pulled in by the reference graph. Belt-and-suspenders: do both, then confirm in the cook log.
- **DDC / model optimization.** If NNE re-optimizes on first run (D1), ensure the optimized payload
  is either cooked in or the first-run cost is hidden (warm it at load / behind the new-game screen).
- **Target platforms.** Phase 7 of the plan also calls for **cross-vendor validation (NVIDIA/Intel)**
  — DirectML is vendor-agnostic on DX12, but validate ORT-DML actually picks the right device on an
  NVIDIA and an Intel GPU before claiming support. (RDG path is the *other* answer to vendor spread —
  see the Phase 6 doc.)

### Checklist — packaging
- [ ] `NNERuntimeORT` + `NNERuntimeRDG` enabled for the **packaged** build, modules not stripped.
- [ ] `onnxruntime.dll` + `DML/x64/DirectML.dll` present in staged `Binaries/Win64/`.
- [ ] `/Game/AI/Terrain/*` confirmed in the cook log (3 assets, expected sizes).
- [ ] Launch packaged build on a **clean machine with no editor/DDC**; terrain generates; log shows
      `backend=NNE ORT DirectML (GPU)` (the verdict format from `GATE1_HOWTO.md:41`), not CPU fallback.
- [ ] Repeat on NVIDIA + Intel GPU (cross-vendor gate).

---

## 5. Model-weights LICENSE blocker (do this FIRST — it can kill the feature)

The weights come from **github.com/xandergos/terrain-diffusion** (the runtime plan names this repo's
`onnx/export.py` as the source of the 3 UNets). **We are redistributing those trained weights inside a
commercial game.** That is a *redistribution + commercial-use* question, and it is **blocking**:

- **Confirm the repo's LICENSE** (code license AND any separate model-weights/dataset license — they
  are often different; many diffusion checkpoints are non-commercial / research-only even when the
  code is MIT). Check for: commercial use allowed, redistribution allowed, attribution required,
  share-alike, and any restriction inherited from the **training data**.
- **If commercial redistribution is NOT clearly granted → fallback = retrain our own weights** on
  permissibly-licensed terrain/DEM data (this is exactly the Phase-7 fallback in the runtime plan,
  line 103, and risk #7, line 115). Retrain is expensive and on the critical path, so this must be
  resolved early, not at ship.
- Keep the answer in writing (link + license text snapshot) in this repo; it gates the milestone.

### Checklist — license
- [ ] Locate + read repo code license.
- [ ] Locate + read weights/checkpoint license (separate file? model card? HF repo card?).
- [ ] Trace training-data license restrictions that flow through to the weights.
- [ ] Get explicit "commercial redistribution OK" or trigger the retrain fallback.
- [ ] If attribution required, add it to the game's credits/licenses screen.

**Decision point D3:** ship third-party weights vs retrain. Default: ship **only** if the license is
unambiguously commercial-redistribution-OK; otherwise schedule retrain before any release.

---

## 6. The ~2.2 GB ONNX footprint (esp. Base 1.9 GB) + mitigation

Total ONNX is ~2.2 GB, dominated by **`base_model.onnx` ≈ 1.9 GB** (called out at `NNEUNetRunner.cpp:54`
and `GATE1_HOWTO.md:53`). That is a large slice of a download/install and of VRAM (the plan budgets a
~2 GB model ceiling, runtime plan line 90 / risk #4). Mitigations, cheapest first:

1. **fp16 weights** — if the model runs fp16 on DirectML (the op-coverage audit, runtime plan Phase 1
   step 3, was to "lock fp32 vs fp16"), fp16 weights ~halve Base to ~0.95 GB with usually-tolerable
   accuracy loss. Re-run Gate-1 parity at the new precision. **Lowest effort, do this first.**
2. **Quantize (int8 / int4 weight-only)** — ONNX Runtime quantization can shrink Base 2–4×. Needs a
   calibration pass + a parity re-check (tolerance may need to widen past 5e-3 — acceptable since the
   AI only provides macro shape ≥30 m and we synthesize sub-30 m detail anyway). DirectML must support
   the quantized ops on AMD — verify in the op audit.
3. **Prune / distill a smaller Base** — structured pruning or training a smaller student. Highest
   effort; overlaps with the §5 retrain fallback (if we're retraining anyway, train smaller).
4. **Ship a smaller Base outright** — if a lower-capacity base checkpoint exists or we train one, the
   macro-only role tolerates a weaker base better than a full-detail image generator would.

**Decision point D4:** target package budget for the 3 models. Recommend **fp16 first** (1: cheap,
reversible), measure, then quantize Base (2) only if still over budget. Pruning/distill (3/4) is a
retrain-scope item — fold into §5 if the license forces a retrain regardless.

### Checklist — footprint
- [ ] Lock inference precision (fp32 vs fp16) from the op audit; re-run Gate-1 parity at chosen precision.
- [ ] Measure on-disk + VRAM for each model at chosen precision.
- [ ] If over budget: quantize Base, re-parity (widen tol if needed), confirm DirectML/AMD op support.
- [ ] Confirm Base fits the ~2 GB VRAM ceiling alongside Lumen/Nanite (`stat GPU`, plan Phase 4).

---

## 7. Model-version FINGERPRINT scheme (folds into `FingerprintGenParams`)

Why: saves store **seed + region + model-version only** (runtime plan Phase 5, line 96) and the
Nanite crust bake is invalidated by a fingerprint mismatch. If we silently swap the weights (a new
checkpoint, fp16, or quantized Base), terrain SHAPE can change — old saves/bakes must be flagged
stale. So the **model identity must be hashed into the fingerprint**.

Current state: `FingerprintGenParams()` (`VoxelGenParams.h:150`) already mixes the diffusion identity
when `bDiffusionAI` is set — `DiffusionSeed`, `DiffusionRegionOriginX/Z` (`VoxelGenParams.h:189-194`).
**It does NOT yet mix a model-version.** That's the gap.

Proposed scheme:
1. **At cook-prep (the §2 import script):** hash the 3 `.onnx` payloads — `FNV-1a`/`xxhash`/`SHA` over
   the concatenated bytes of coarse+base+decoder → a single **64-bit `ModelVersionId`** (fold the SHA
   down to 64 bits to match the existing FNV-1a u64 fingerprint in `VoxelGenParams.h:152`). Hashing the
   *bytes* means precision changes, quantization, and retrains all produce a new id automatically.
2. **Bake the id into the build:** write `ModelVersionId` to a cooked config (a `UDataAsset` field next
   to the soft refs, or a generated header constant). The runner asserts the loaded asset's id matches
   at startup (catches an asset/version mismatch in a patch).
3. **Add `DiffusionModelVersion` to `FGenParams`** and mix it inside the existing
   `if (P.bDiffusionAI)` block in `FingerprintGenParams()` (`VoxelGenParams.h:189`) — one more
   `FingerprintMix(Hash, ModelVersionId)`. Procedural/EXR fingerprints stay byte-identical (the block
   is diffusion-only — that invariant is explicitly preserved, `VoxelGenParams.h:184-188`).

Result: a weights change → new `ModelVersionId` → new gen fingerprint → old crust bakes flagged stale,
saves know which model produced their terrain. Exactly the Phase-5 intent.

### Checklist — fingerprint
- [ ] Cook-prep script hashes the 3 `.onnx` → 64-bit `ModelVersionId`; writes it to a cooked config.
- [ ] Add `DiffusionModelVersion` to `FGenParams`; mix it in the `bDiffusionAI` block (`VoxelGenParams.h:189`).
- [ ] Runner asserts loaded-asset id == build id at startup.
- [ ] Verify: change a weight → fingerprint changes → bake manifest flags stale; revert → matches again.

---

## 8. Ordered SHIP checklist (top-to-bottom gate)

1. [ ] **License cleared** (§5) — commercial redistribution OK, or retrain fallback scheduled. *(Blocking. Do first.)*
2. [ ] **Precision/footprint locked** (§6) — fp16/quantize decided; Base under disk + VRAM budget.
3. [ ] **Assets imported** (§2) — 3 `UNNEModelData` in `/Game/AI/Terrain/`, parity-checked vs loose ONNX.
4. [ ] **Runner cooked path** (§3) — soft-ref load behind `#else`; editor byte path kept for Gate 1.
5. [ ] **Fingerprint** (§7) — `ModelVersionId` hashed, in `FGenParams`, mixed into the fingerprint.
6. [ ] **Packaging** (§4) — plugins enabled for packaged target; `onnxruntime.dll` + `DirectML.dll` staged; assets in cook log.
7. [ ] **Clean-machine launch** — packaged build generates terrain on GPU (no DDC, no editor); log says DirectML, not CPU.
8. [ ] **Cross-vendor** — same on NVIDIA + Intel (or document DirectML-only support + CPU fallback behavior).
9. [ ] **Determinism/saves** (Phase 5) — save stores seed+region+model-version; reload reproduces; MP uses server-authoritative DEM (plan line 95).

### Key decision points recap
- **D1** optimized-model cook vs first-run re-optimize (cold-start budget).
- **D2** 3 assets (chosen) vs bundle.
- **D3** ship third-party weights vs retrain (license-driven, blocking).
- **D4** precision/quantization target for the 2.2 GB footprint.

---

## Critical files (this phase touches / references)
- `Source/MiraThalTerrainAI/Private/NNEUNetRunner.cpp` — `LoadWholeFile64` (:57), `Init("onnx",…)` (:137),
  `LoadModel` (:108), DirectML/CPU runtime selection (:141/:177). The cooked path edits land in `LoadModel`.
- `Source/MiraThalTerrainAI/Public/NNEUNetRunner.h:14-17,70` — ctor + the editor-vs-cooked note already written.
- `Source/MiraThalTerrainAI/Public/TdiffUNetRunner.h:38-43,90-93,133` — `EUNetModel`, model I/O contract, `GetModelStem`.
- `Source/MiraThalTerrainAI/Public/DiffusionCoarseProvider.h` + `.cpp:271` — `Config.OnnxDir` / `Make()` (gains cooked branch).
- `Source/MiraThalVoxel/Public/VoxelGenParams.h:150-197` — `FingerprintGenParams`; the `bDiffusionAI` block (:189) gets `ModelVersionId`.
- `MiraThal.uproject:48-78` — module descriptor + NNE plugin enables (confirm packaged-target shipping).
- `Source/MiraThalTerrainAI/Private/GATE1_HOWTO.md` — the commandlet (path A) that stays editor-only; reuse for asset-parity re-check.
- NEW (scripts): `Scripts/Import-DiffusionModels.ps1` — import + hash + write `ModelVersionId` (cook-prep).
</content>
</invoke>
