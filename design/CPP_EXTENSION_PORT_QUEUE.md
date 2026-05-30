# C++ GDExtension port queue

Companion to `CLAUDE.md` § C++ GDExtension perf opportunities. CLAUDE.md states the rule + build command + current "done" list; this doc carries the backlog and the migration process.

## Constraint

`godot-cpp` can't subclass Zylann classes (`VoxelGeneratorScript`, `VoxelMesher`, etc.). Port pattern is **C++ extends `godot::Resource`** + a **thin GDScript adapter** that extends the Zylann base and forwards by `Variant` call. Mirror this for every future port.

## Build

```
python -m SCons platform=windows target=template_debug use_mingw=yes -j8
```

Run from `extensions/voxel_gen/`. **Close Godot first** — scons fails on DLL replace if the editor has the .dll loaded.

## Profiler measurement

Use `engine.real_us` from PR #207, not `proc_us`. The latter plateaus across many frames and is unreliable for p99 work.

## Next targets, payoff-vs-effort order

1. **`WaterFlowManager.gd` flow tick (M).** 4 Hz scan over chunks within 20 m, per-voxel byte read/write. Sits in `[PERF]` top-3 already. `WaterByteCodec` is POD → mostly buffer iteration.
2. **`VoxelGravityManager.gd` flood-fill (S-M).** 16 m local BFS for unsupported voxels. Clean port; worth it only if gravity scans surface in PERF.
3. **Generic chunk-bytes scratch helper (S).** Several GD systems each `VoxelBuffer.get_voxel × N` into `PackedByteArray`. A shared C++ "snapshot CHANNEL_TYPE + DATA5 to flat buffer" helper amortises that.

## NOT worth porting

- `VoxelMesherBlocky` — already Zylann C++.
- Chunk streaming / LOD octree — Zylann main-thread work, not optimisable from outside.
- `VoxelEditManager` queue — already cheap; bound by Zylann's `VoxelTool` write path.
- LOD-bake-on-eviction caching — the C++ generator already shrunk the motivating cost.

## Process for any future port

1. Pick a target with a clearly-bounded function surface; prefer pure-math hot loops over anything touching the SceneTree (worker threads can't).
2. **Write the parity harness FIRST** as a `@tool` EditorScript in `scripts/_dev/`. Use `ParityProbe` for math primitives; per-chunk byte diffs for `VoxelBuffer`s. Bit-exact output is the only acceptable gate.
3. POD snapshot infra if C++ needs `Resource` data from GDScript (mirror `set_ore_materials(Array[Dictionary])`).
4. Land in sub-phases each ending in a green parity harness — never commit a phase that breaks parity, even if you "know" the diff is benign.
5. Adapter forwards every public method the bootstrap calls.

See the receipt of the cubic generator port (which still needs to be relocated from `memory/project_voxel_gen_cpp_port.md` if/when that dir exists).
