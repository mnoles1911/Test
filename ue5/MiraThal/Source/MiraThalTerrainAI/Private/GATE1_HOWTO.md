# Gate 1 — how to run the NNE terrain-diffusion inference check

**What it proves:** the three exported diffusion UNets load and run on the **local GPU via
NNE’s ONNX Runtime + DirectML** backend (AMD RX 7800 XT, no CUDA), and that their outputs
match the fixed-seed (12345) golden recording within tolerance. This is the green light
before any orchestration is built on top of the runner.

It runs as a **commandlet** (`UTdiffGate1Commandlet`), invoked headless through
`UnrealEditor-Cmd.exe` — exactly like `Rebake-Terrain.ps1` invokes `-run=VoxelCrustBake`.
UE strips the `Commandlet` suffix, so the switch is **`-run=TdiffGate1`**.

> **Prerequisite:** the parent must **build the editor first** (this doc does not build).
> The `NNERuntimeORT` plugin is already enabled in `MiraThal.uproject`, and the engine build
> at `D:\UE5\UE_5.7` ships `onnxruntime.dll` + `DML\x64\DirectML.dll`.

## Command (PowerShell)

```powershell
$UECmd = "D:\UE5\UE_5.7\Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
$Proj  = "C:\Users\Matt Noles\Test-ue5\ue5\MiraThal\MiraThal.uproject"

& $UECmd "$Proj" -run=TdiffGate1 `
    -OnnxDir="D:/terrain-diffusion/onnx_export" `
    -GoldenDir="D:/terrain-diffusion/golden" `
    -Tolerance=5e-3 `
    -unattended -nopause -nosplash -stdout -FullStdOutLogOutput
```

All three switches are **optional** — they default to the paths shown above and a tolerance
of `5e-3`. Minimal form:

```powershell
& $UECmd "$Proj" -run=TdiffGate1 -unattended -nopause -nosplash -stdout
```

## Reading the result

Look for the `LogMiraTerrainNNE` lines. Each model prints one verdict line, e.g.:

```
LogMiraTerrainNNE: [Gate1] coarse_model: backend=NNE ORT DirectML (GPU)  elems=24576  max|diff|=1.2e-04  mean|diff|=8e-06  tol=0.005  => PASS
...
LogMiraTerrainNNE: ================ Gate 1 result: PASS  (3 passed, 0 failed) ================
```

- `backend=` tells you whether it ran on **DirectML (GPU)** or fell back to **CPU**.
- The commandlet **exit code is 0 on PASS, 1 on any FAIL**, so a wrapper script can branch on
  `$LASTEXITCODE`.

## Notes / gotchas

- **First run is slow.** NNE optimizes each ONNX for the runtime and caches it in the DDC, so
  the first `-run=TdiffGate1` pays a one-time compile cost (and `base_model.onnx` is ~1.9 GB).
  Subsequent runs are fast.
- **GPU vs CPU fallback.** If DirectML can’t be created, the runner automatically falls back to
  the `NNERuntimeORTCpu` runtime and says so in the log. Numbers stay correct; only speed drops.
- **Tolerance.** DirectML’s fp arithmetic diverges slightly from PyTorch’s; `5e-3` (max abs
  diff) absorbs that. Tighten with `-Tolerance=` if you want a stricter gate.
- **Paths use forward slashes** inside the switch values — `FPaths::Combine` normalizes them.
