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

**Scope:** data/logic/parity only — dummy renderer, no GPU, no shaders execute. Visuals still need the designer running the editor.

## Pipeline scripts

| Tool | Purpose |
|---|---|
| `render_sfx.py` | ElevenLabs SFX generation (~9 cr/s + 20 cr/gen). Prompts in `SFX_PROMPTS.md` |
| `render_voice.py` (if present) | NPC TTS via voice IDs from `design/TTS_PIPELINE.md` |
| `build_texture_atlas.py` | Pack voxel textures into 1024² atlas. Includes `_warn_if_not_pixel_art` heuristic (NB/DALL-E output is photo-style; nearest-downscale samples random pixels → noise) |
| `_analyze_capture.py` | Parse F3 profiler capture JSON; surface top spike attribution |
| `probe_zylann_blocky.gd` (Godot EditorScript) | Probe Zylann classes for `get_property_list()` + `get_method_list()` before guessing the API |
| `voxel_tree_studio/` (forked ez-tree, browser) | Realistic trees → **cubic voxels** → game-ready JSON. ez-tree skeleton (`vendor/ez-tree/`, MIT fork w/ skeleton hook) → `tree_voxelizer.js` (6-connected rasterizer + adjacency foliage + connectivity check) → InstancedMesh preview + export. Rich palette ids 24–28 (collapse to 10/11 optional). Plant types: tree/bush/fern/grass/groundcover/vine + space-colonization mode. Open via githack URL. |
| `voxel_rock_studio/` (browser) | SDF voxel **rocks**. `rock_voxelizer.js` (superquadric + FBM + Worley faceting + scrape planes + flat bottom; materials by noise/strata; moss on top) → worker → InstancedMesh + export. Existing stone ids 1/7/9/12/14/15 + moss 32. **Claude vision** dial-fit (`claude_vision.js`, browser Messages API call, strict tool use, `claude-opus-4-8`). Importer (`scripts/_dev/VoxelTreeImporter.gd`) accepts tree + rock formats. |
| `voxel_studio_common/` | Shared: `noise.js` (simplex/Worley/FBM), `voxel_core.js` (packing, 6-connected connectivity, normalize, unpackKey), `claude_vision.js`, `scale_figure.js`. |
| `blender/import_voxel_json.py` | Import a studio JSON export into Blender as a welded surface mesh (face-culled, palette materials). Add-on + Scripting + headless CLI (`--render`/`--turntable`/`--save`). Pure `build_surface()` is bpy-free + unit-tested. Studio +Y up → Blender +Z up. |
| `blender/run.sh` | Headless Blender runner (`blender --background --python …`) — also the way to drive Blender for ad-hoc modelling tasks. Needs Blender installed. |
| `aigen/` (Python CLIs) | AI asset generation. `gemini_image.py` (Gemini 2.5 Flash Image / Nano Banana, REST, `GEMINI_API_KEY`), `fal_image_to_3d.py` (fal.ai image→`.glb`, queue API, `FAL_KEY`, default `fal-ai/trellis`), `asset_pipeline.py` (chains both). All support `--dry-run`. Mirrors the concept-image→AI-3D steps of `design/ASSET_PIPELINE_AI.md`. |
| `devtools/` (Playwright) | **Browser self-verification.** `browse_shot.mjs` screenshots a URL + reports console errors (exit 1 on error); `verify.sh` serves the repo locally and shoots a studio (tests actual files); `verify_all.sh` is the regression sweep — 12 studio modes, nonzero exit on any console error. Lets Claude *see* the studios. Setup: `npm i playwright && npx playwright install chromium` (`node_modules/` git-ignored). |

## When adding a tool

1. Drop the script here.
2. Document a one-line "what + when" entry in `README.md` for designer reference.
3. Add to the table above for Claude reference.
4. If a new headless selector lands, register in `runner.gd` + `run.ps1`'s `ValidateSet`.

## Environment

- `ELEVENLABS_API_KEY` env var required for `render_sfx.py` / `render_voice.py`.
- Python 3.10+ + `pip install -r tools/requirements.txt` (if present).
- SCons for the C++ extension build (see `../extensions/voxel_gen/CLAUDE.md`).
