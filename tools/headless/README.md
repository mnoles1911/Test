# Headless Godot harness

Reversed the "no headless setup" rule on 2026-05-18 (native-fluid water pivot). Hybrid harness for **data / logic / parity** checks only — no GPU, no shaders, no rasterization. Anything visual (shader look, F-key debug views, perf via `engine.real_us`) still needs the designer running the editor.

## Run

```
<Godot_v4.6.2…_console.exe> --headless --path <proj> --script res://tools/headless/runner.gd -- <selector>
```

Use the **`_console.exe`** build — the plain `win64.exe` is GUI-subsystem and won't pipe stdout.

Exit code 0 = pass.

`tools/headless/run.ps1` wraps the invocation for Windows.

## Selectors

| Selector | What it verifies |
|---|---|
| `gate0` | Zylann fluid API probe (the runtime guarantees the native-fluid pivot depends on) |
| `codec` | `WaterByteCodec` parity — shares the in-editor `@tool` lib so File → Run still works |
| `wmat` | `WaterMaterial.gd` contracts |
| `phase2` | Library injection contracts |
| `phase7` | Save round-trip contracts |
| `gen` | C++ generator parity harness — writes a baseline file, then re-runs and bit-exact verifies |
| `finite` | `FiniteWaterCore` finite-water sim gates: conservation invariant, levelness, 18-voxel reach, evaporation, ocean absorption, determinism |
| `finite_world` | End-to-end finite-water gate in the real World3D scene (pour, settle, audit voxels vs ledger) |
| `sever` | Tree-sever upward-follow BFS gates (SeverFollowLib) |
| `shader` | Shader compile + the foam removal contract |
| `spike` | Does `VoxelLodTerrain` stream headless? (Yes — confirmed by this selector) |
| `scale` | `VoxelScale.gd` contract: internal consistency + all refactored-script constants mirror it + World3D.tscn transform matches (PR R0) |
| `flora` | R4 micro-voxel flora: `FloraMaterial.is_flora` id classification, water-displaces-flora (FiniteWaterCore), gravity/sever flora exclusion (GD ref + C++ parity), generator scatter determinism + no-flora-at-LOD>0 |
| `mining` | `EditToolHandler` carve math: physical-volume swing-time anchor (`BASELINE_VOLUME_M3`, scale-proof), Small/Medium/Full preset → size mapping, `_compute_carve_box` exact N³ bounds + DEPTH_BIASED into-terrain bias |

## Scope

**In scope:** parity bit-exactness, save contracts, API probes, anything that only touches data structures + GDScript logic.

**Out of scope:** anything that needs the renderer running. Shader output, F-key debug overlays, particle system behaviour, performance numbers from `Profiler.real_us`. Those still need the editor.

Use the harness for parity / contract checks on every change. Keep the in-editor loop for visuals.
