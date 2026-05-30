# extensions/voxel_gen/CLAUDE.md

C++ GDExtension. Used **proactively** for CPU work iterating thousands+/frame — don't wait for a profiler to mandate it.

## Build

```
cd extensions/voxel_gen
python -m SCons platform=windows target=template_debug use_mingw=yes -j8
```

**Close Godot first** (DLL replace fails while Godot has it loaded). Reload Godot after build.

## Layout

| Dir | Contents |
|---|---|
| `src/` | C++ source — one file pair per ported class |
| `bin/` | Built DLL (`libvoxel_gen.windows.template_debug.x86_64.dll`) |
| `godot-cpp/` | Pinned godot-cpp submodule |

## Done

`CubicHeightmapGeneratorCpp`, `CopperIslesHeightmapGeneratorCpp`, `HeightmapGeneratorBase`, `VoxelGravityCpp`, `EmissiveLightCpp` v1, `EmissiveBakedCpp` (Phase J — supersedes v1), `WaterFlowCpp` (settle scan).

All autoloads have a GD fallback for when the DLL is missing.

## Port pattern (mandatory)

godot-cpp can't subclass Zylann classes. Workaround:
- C++ class extends `godot::Resource`.
- GDScript adapter extends `VoxelGeneratorScript` (or whichever Zylann base is needed).
- Adapter forwards every public method to the C++ Resource via Variant call.

## Reusable patterns (PR #241 lessons)

1. **Bulk-read Zylann channels via `get_channel_as_byte_array`** (one Variant call). Per-voxel `Variant::call` from C++ is slower than GDScript-native.
2. **Byte layout is Y-fastest:** `byte_index = (y + x*sy + z*sx*sy) * bytes_per_voxel`.
3. **Return per-voxel results as `PackedInt32Array` streams**, not `Dictionary[Vector3i, int]` — Dict marshalling at scale is invisible-but-real overhead.
4. **Cross-language sort:** pick a total ordering (e.g. `(y, x, z)` lex). Never rely on either language's unstable sort agreeing with the other's.

## Port process (mandatory)

1. Pick a target with a clearly-bounded function surface. Prefer pure-math hot loops over anything touching the SceneTree (worker threads can't).
2. **Parity harness FIRST** as a `@tool` EditorScript in `../scripts/_dev/`. Bit-exact output is the only acceptable gate.
3. POD snapshot infra if C++ needs Resource data from GDScript (mirror `set_ore_materials(Array[Dictionary])`).
4. Land in sub-phases each ending in a green parity harness — never commit a phase that breaks parity, even if you "know" the diff is benign.
5. Adapter forwards every public method the bootstrap calls.

## Headless gates

Each ported class has a selector in `../tools/headless/runner.gd`:
`gen distant gravity emissive baked_light water_flow`

Plus the generic gates: `gate0 codec wmat shader phase7 spike phase2 entity`.

## Next targets

- `WaterFlowManager._flow_chunk` + `_process_connectivity_fill` BFS (only if a future capture spikes — dormant in 2026-05-27 capture).
- Zylann `ShaderMaterialPool::recycle` assertion on F11 LOD-debug toggle path (correctness, not perf).

## NOT worth porting

Zylann internals (mesher, streaming, LOD octree — main-thread only, not external-optimisable), `VoxelEditManager` queue (already cheap), LOD-bake-on-eviction caching (C++ generator already shrunk the motivating cost).

## Receipt

`memory/project_voxel_gen_cpp_port.md` — full port history with commit chain + lessons.
