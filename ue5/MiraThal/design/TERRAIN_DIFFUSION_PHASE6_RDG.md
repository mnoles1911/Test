# TerrainDiffusion — Phase 6: the optional vendor-agnostic RDG inference path

**Status:** DESIGN / RESEARCH ONLY (no code in this doc). Written 2026-06-28.
Companion: `design/TERRAIN_DIFFUSION_RUNTIME_PLAN.md` (Phase 6, line 98), `design/TERRAIN_DIFFUSION_PHASE7_SHIPPING.md`.

> Plain-English: Gate 1 proved the AI runs on the AMD card via **ORT + DirectML** (NNE's
> ONNX-Runtime backend). UE5 *also* ships a second NNE backend — **NNERuntimeRDG** — that runs the
> network as the engine's own render-graph compute passes (HLSL), so it can be **scheduled in the same
> frame** as Lumen/Nanite instead of on a separate GPU queue. That sounds attractive for hiding
> inference cost in the frame. But on **this AMD card RDG was rejected** during the Gate-1 work, and
> its op set is too thin for full diffusion UNets. This doc records *why*, what the override does and
> why it's dangerous, and a concrete go/no-go: **keep ORT-DML by default; only consider RDG for the
> cheapest net or a future detail/erosion compute pass.**

---

## 1. Why NNERuntimeRDGHlsl was rejected on the RX 7800 XT

During Gate-1 bring-up, the RDG/HLSL runtime (`NNERuntimeRDGHlsl`) **refused to create the models on
this card**. The log said, in effect:

> *"current hardware is incompatible — wave ops / native 16-bit not supported; bypass via
> `NNE_FORCE_HARDWARE_SUPPORTS_HLSL`."*

What that means:
- The RDG HLSL backend's shaders require **wave/subgroup intrinsics** (`WaveActiveSum` and friends)
  and **native 16-bit types** (`float16`) to hit its expected performance/correctness profile.
- NNE runs a **hardware-support gate** at model-create time and **declared this card unsupported**, so
  it bailed rather than run something slow/incorrect.
- This is a **capability gate, not a "no GPU"** error — the RX 7800 XT (RDNA3) does have wave ops in
  general, but the gate checks the specific caps NNE's RDG path was validated against under our RHI
  setup, and that check failed here.

Separately, an observation from the same session that shapes the recommendation:
- **ORT-DML ran on its own D3D12 queue.** RHI reported D3D12 = "no"; DML reported D3D12 = "yes". I.e.
  DirectML created/used a **separate D3D12 device/queue** from the engine's RHI. That's exactly why
  RDG is *theoretically* nicer (shared graph) — but also why ORT-DML "just worked" without RHI caps.

**Conclusion:** RDG is gated off on the dev/target AMD card today, for a real reason. ORT-DML is the
path that passed Gate 1, and it sidesteps the caps gate entirely by living on its own queue.

---

## 2. `NNE_FORCE_HARDWARE_SUPPORTS_HLSL` — what it does, and its risks

- **What it does:** forces NNE's hardware-support check to return *true* for the RDG HLSL path,
  bypassing the wave-op / native-16-bit gate so the runtime will **attempt** to create + run the model
  anyway.
- **What it does NOT do:** it does **not add the missing capabilities**. It only silences the gate. If
  the shaders genuinely need a cap the driver/RHI doesn't expose the way NNE expects, you get one of:
  - wrong numbers (silent — the worst outcome for a deterministic terrain pipeline; breaks parity),
  - a much slower fallback path,
  - a shader compile / dispatch failure or GPU hang.
- **Risks, ranked:**
  1. **Silent numerical divergence** → terrain shape differs from the golden / from other machines →
     breaks the parity oracle and (per Phase 5) multiplayer/save determinism. Catastrophic for a
     feature whose entire correctness story is "matches the Python golden."
  2. **Instability** on the player's varied hardware (the override would have to ship globally, on
     cards we never tested) → crashes/hangs in the field.
  3. **Maintenance trap** — it masks the real "is this card supported?" signal, so we'd lose the
     honest capability check that currently routes us to ORT-DML cleanly.

**Stance:** acceptable **only** as a local experiment to *measure* RDG perf on this card during a
spike — never as a shipped default, never on by default. If RDG is ever pursued, it must pass the gate
*honestly* (correct caps) or be limited to ops/shaders that don't need the gated intrinsics.

---

## 3. RDG's limited op set vs what the diffusion UNets need

NNERuntimeRDG implements a **subset** of ONNX ops as hand-written RDG compute shaders. Diffusion UNets
are **not** a friendly subset:

- **Attention** (self/cross-attention blocks) — multi-op (matmul + softmax + reshapes/transposes),
  often the first thing missing or unoptimized in a from-scratch op library.
- **GroupNorm** (the diffusion UNet's normalization of choice) — needs reductions across channels
  (precisely the **wave-op reductions** the hardware gate is about).
- Plus the long tail: dynamic shapes (our models export with dynamic axes — `TdiffUNetRunner.h:106-113`),
  various conv configs, activations, broadcasts.

By contrast **ORT-DML covers the full ONNX op set** through DirectML's mature operator library — which
is exactly why the runtime plan chose it as the primary path ("broad ONNX op coverage, runs on AMD via
DX12", plan line 33) and why all 3 UNets passed Gate 1 on it. **Any op RDG lacks forces a CPU/host
roundtrip or fails outright**, killing both the perf and the frame-alignment argument.

**Implication:** running the *full* Coarse/Base/Decoder UNets on RDG is not realistic without
substantial op work AND clearing the caps gate. The only viable RDG targets are **small, op-simple**
workloads (§4).

---

## 4. When RDG is actually worth it

The single real advantage of RDG over ORT-DML is **frame-aligned co-scheduling**: RDG inference is
just more passes in the engine's render graph, so it shares the RHI D3D12 queue with Lumen/Nanite and
can be budgeted/interleaved per frame. ORT-DML runs on a **separate D3D12 queue** (observed in Gate 1),
which means:

- **Pro (ORT-DML):** inference doesn't stall the render graph; runs concurrently; simplest path.
- **Con (ORT-DML):** that separate queue **contends for the same GPU** with Lumen/Nanite with no
  in-frame budget control — if inference and rendering collide you get hitches, and you can only
  manage it coarsely (run inference off-frame, throttle in-flight count — plan Phase 4).
- **Pro (RDG):** if contention is a *measured* shipping problem, RDG lets us put inference *in* the
  frame graph and co-schedule it (e.g. fit it in GPU bubbles, hard per-frame budget).

So RDG is worth considering **only if** ORT-DML's separate-queue contention with Lumen/Nanite proves to
be a real, measured frame-time problem that off-frame scheduling + VRAM/eviction (Phase 4) can't fix —
**and** the workload is op-simple enough to fit RDG's op set and clear the caps gate. That points at
two candidates, not the whole pipeline:

1. **The cheapest net** — the **Coarse** model (smallest, lowest-res "lay of the land",
   `TdiffUNetRunner.h:40`). If any UNet could be ported to RDG ops, it's this one. Base (1.9 GB,
   attention-heavy) and Decoder are poor fits.
2. **The detail / erosion compute** — the sub-30 m detail bridge and optional hydraulic/thermal
   **erosion** (runtime plan Phase 3, line 86) are **our own** compute, not ONNX. Writing those as
   native `.usf` RDG passes (the plan already floats a `/MiraVoxel` `.usf` compute pass in
   `MiraThalVoxelRender`) gives the frame-alignment benefit **without** NNE's op-set or caps-gate
   problems at all. This is the strongest RDG use — and it isn't really "NNE RDG", it's just RDG.

---

## 5. Recommendation

**Default: keep ORT-DML (DirectML) as the production inference path.** It passed Gate 1 on the target
AMD card, covers the full op set, sidesteps the RDG caps gate via its own D3D12 queue, and is the
Phase-1/primary path in the runtime plan. Do **not** ship `NNE_FORCE_HARDWARE_SUPPORTS_HLSL`.

**Consider RDG only as a narrow, later optimization**, in this order of likelihood-to-pay-off:
1. **Detail/erosion as hand-written RDG `.usf` compute** (not NNE) — best ROI, no op-set/caps issues,
   real frame-alignment. Pursue this first if/when erosion is built (Phase 3).
2. **Coarse UNet on NNERuntimeRDG** — only if Coarse's ops are all RDG-supported *and* the caps gate
   can be cleared honestly *and* §6 go/no-go criteria are met.
3. **Base/Decoder on RDG** — **no**, not realistic (size + attention + GroupNorm + caps gate).

---

## 6. Go / No-Go criteria (concrete)

Pursue an RDG inference port **only if ALL of these are true** (else stay on ORT-DML):

- [ ] **G1 — There is a measured problem.** `stat GPU` / RHI timing shows ORT-DML's separate queue
      causing real frame hitches against Lumen/Nanite that **off-frame scheduling + in-flight throttle +
      VRAM eviction (Phase 4) do not fix.** No measured contention → no RDG. (Don't optimize on a guess.)
- [ ] **G2 — The caps gate passes honestly.** `NNERuntimeRDGHlsl` creates the target model on the AMD
      card **without** `NNE_FORCE_HARDWARE_SUPPORTS_HLSL` (or the required wave-op/fp16 caps are
      confirmed correct on it and our target spread). Forcing the gate is never a ship answer.
- [ ] **G3 — Op coverage is complete for the chosen workload.** Every op in the target net/compute is
      RDG-supported (no CPU roundtrips). For UNets, audit attention + GroupNorm specifically.
- [ ] **G4 — Parity holds.** RDG output matches the Python golden within the Gate-1 tolerance
      (`GATE1_HOWTO.md`, 5e-3 max-abs) — same oracle as ORT-DML. Any divergence = no-go (breaks Phase-5
      determinism).
- [ ] **G5 — Cross-vendor not regressed.** RDG must not make NVIDIA/Intel worse than the ORT-DML
      baseline (RDG's whole pitch is vendor-agnostic — prove it).

**Cheapest valid scope wins:** if G1 is true but a full-UNet port can't meet G2–G4, fall back to RDG
**only** for the detail/erosion `.usf` compute (§4.2), which faces none of the NNE op-set/caps issues.

**No-go default:** if G1 is false (no measured contention), **stop here** — ship ORT-DML, revisit only
if a real perf wall appears post-launch.

---

## Critical files / references
- `design/TERRAIN_DIFFUSION_RUNTIME_PLAN.md:33-34` (ORT-DML primary; RDG limited-op later), `:89-91`
  (Phase 4 perf/scheduling vs Lumen/Nanite), `:98-100` (Phase 6 RDG), `:86` (erosion as a `.usf` compute).
- `MiraThal.uproject:74-78` — `NNERuntimeRDG` enabled "for a later optimization phase; ORT+DirectML is the Phase-1 path."
- `Source/MiraThalTerrainAI/Private/NNEUNetRunner.cpp:141` (ORT-DML create path), `:177` (CPU fallback) —
  the RDG path would be a *third* runtime selected by name (`NNERuntimeRDGHlsl`) alongside these.
- `Source/MiraThalTerrainAI/Public/TdiffUNetRunner.h:40-43` (`EUNetModel` — Coarse is the only RDG candidate),
  `:106-113` (dynamic axes — another RDG friction point).
- `Source/MiraThalTerrainAI/Private/GATE1_HOWTO.md` — the parity oracle + tolerance RDG must also satisfy (G4).
- `Source/MiraThalTerrainAI/MiraThalTerrainAI.Build.cs:39-41` — `RenderCore`/`RHI`/`Renderer` already
  depped in "for when we add the RDG path later"; the erosion `.usf` would live in `MiraThalVoxelRender`.
</content>
