# tools/CLAUDE.md

Pipeline scripts + headless test harness. **Read `README.md` (this dir) for the per-tool quick reference.** This file is the Claude-Code-facing index.

## Headless test harness

`tools/headless/` — Godot SceneTree script running data/parity checks without a GPU.

```
tools/headless/run.ps1 <selector>
```

Runs Godot's **`_console.exe`** (plain win64 exe is GUI-subsystem and won't pipe stdout) with `tools/headless/runner.gd`. Exit 0 = pass.

### Selectors

| Selector | What it checks |
|---|---|
| `gate0` | Zylann fluid API probe (ClassDB reflection) |
| `codec` | `WaterByteCodec` bit-exact parity |
| `wmat` | `WaterMaterial` contract (per-level fluid id projection) |
| `shader` | `water.gdshader` parse + compile + foam-removed verification |
| `phase7` | Legacy-save + MP byte contract |
| `phase2` | Library has 8 native fluid models at ids 16-23 |
| `spike` | `VoxelLodTerrain` streams headless? (yes) |
| `gen` | C++ generator parity (baseline-then-verify) |
| `distant` | `DistantTerrainMesher` heightmesh parity vs baseline |
| `gravity` | `VoxelGravityCpp.analyze_bubble` parity vs reference |
| `emissive` | `EmissiveLightCpp.scan_region` parity vs reference |
| `baked_light` | `EmissiveBakedCpp.bake_light_volume` parity (BFS with wall blocking) |
| `water_flow` | `WaterFlowCpp.scan_settle_region` parity (incl. W2 source-gate cases) |
| `finite` | `FiniteWaterCore` — conservation / levelness / reach / evaporation / ocean-absorption / determinism |
| `finite_world` | End-to-end: pours 216 units into the REAL World3D scene, audits actual voxels vs the ledger |
| `sever` | `SeverFollowLib.continue_bfs` — tree-sever upward follow (merge / top + side aborts / water exclusion) |
| `entity` | `EntityRegistry` save/load + chunk-index parity (66 checks) |
| `scale` | `VoxelScale.gd` single-source-of-truth contract: internal consistency, all refactored script constants mirror VoxelScale, World3D.tscn VoxelLodTerrain transform matches `VOXEL_SIZE_M` (PR R0) |

**Scope:** data/logic/parity only — dummy renderer, no GPU, no shaders execute. Visuals still need the designer running the editor.

## Pipeline scripts

| Tool | Purpose |
|---|---|
| `render_sfx.py` | ElevenLabs SFX generation (~9 cr/s + 20 cr/gen). Prompts in `SFX_PROMPTS.md` |
| `render_voice.py` (if present) | NPC TTS via voice IDs from `design/TTS_PIPELINE.md` |
| `build_texture_atlas.py` | Pack voxel textures into 1024² atlas. Includes `_warn_if_not_pixel_art` heuristic (NB/DALL-E output is photo-style; nearest-downscale samples random pixels → noise) |
| `_analyze_capture.py` | Parse F3 profiler capture JSON; surface top spike attribution |
| `probe_zylann_blocky.gd` (Godot EditorScript) | Probe Zylann classes for `get_property_list()` + `get_method_list()` before guessing the API |

## When adding a tool

1. Drop the script here.
2. Document a one-line "what + when" entry in `README.md` for designer reference.
3. Add to the table above for Claude reference.
4. If a new headless selector lands, register in `runner.gd` + `run.ps1`'s `ValidateSet`.

## Environment

- `ELEVENLABS_API_KEY` env var required for `render_sfx.py` / `render_voice.py`.
- Python 3.10+ + `pip install -r tools/requirements.txt` (if present).
- SCons for the C++ extension build (see `../extensions/voxel_gen/CLAUDE.md`).
