# voxel_gen — C++ GDExtension for voxel terrain generation

Phase 0 of the GDScript → C++ generator port (see
`/root/.claude/plans/bake-iteration-speed-has-scalable-hellman.md` for the
multi-phase roadmap, or the branch's commit history).

## What's here right now

Phase 0 (spike, throwaway): a `SpikeStoneGenerator` C++ class that fills
chunks with solid stone, plus a GDScript adapter
(`scripts/_dev/SpikeStoneGeneratorAdapter.gd`) that bridges it to Zylann's
`VoxelGeneratorScript`. If the spike scene renders a stone sphere, the
integration works and Phase 1+ can proceed.

## Build prerequisites (Windows)

1. **C++ compiler.** Choose one:
   - **MSVC Build Tools 2019 or newer** (recommended). Download "Build Tools
     for Visual Studio" from Microsoft and install the
     **"Desktop development with C++"** workload. After install, open an
     **"x64 Native Tools Command Prompt for VS"** before running `scons`.
   - **MinGW-w64**. Install via `winget install MartinStorsjo.LLVM-MinGW` or
     download a release from <https://github.com/niXman/mingw-builds-binaries/releases>.
     Add the `bin/` directory to your `PATH`. Pass `use_mingw=yes` to
     `scons`.
2. **Python 3.8+** (already installed: 3.12.10).
3. **SCons 4.x** (already installed via pip 4.10.1; if `scons` is not on
   PATH, invoke as `python -m SCons`).

## Build commands

From the repo root, in an MSVC "x64 Native Tools" prompt or a shell that
has the chosen compiler on PATH:

```sh
cd extensions/voxel_gen
python -m SCons platform=windows target=template_debug -j8
python -m SCons platform=windows target=template_release -j8
```

The first build takes a while because godot-cpp's binding library
(`libgodot-cpp.windows.*.lib`) compiles from scratch. Subsequent builds
only recompile changed files in `src/`.

Output goes to `extensions/voxel_gen/bin/`:
- `libvoxel_gen.windows.template_debug.x86_64.dll` (editor)
- `libvoxel_gen.windows.template_release.x86_64.dll` (exported builds)

Godot loads the right binary automatically via `voxel_gen.gdextension`.

## Verifying Phase 0 spike

1. Build per above (debug variant is enough for editor use).
2. Open the Godot project (4.6.2).
3. Open `scenes/_dev/SpikeStoneTest.tscn`.
4. Press F6 to run the scene.
5. **Expected:** a solid stone sphere around the spawn point; the Output
   panel prints one `SpikeStoneGenerator: filled chunk origin=... size=...
   lod=...` line per streamed chunk.
6. **If you see air instead of stone:** the C++ side is loaded but the
   Adapter hasn't been wired to a `SpikeStoneGenerator` resource. Open the
   scene, select the `VoxelLodTerrain` node, find the
   `SpikeStoneGeneratorAdapter` resource on its `generator` property, and
   confirm its `cpp_impl` slot has a `SpikeStoneGenerator` resource.
7. **If the project fails to launch with a "class not found" error:** the
   binary didn't load. Confirm `bin/libvoxel_gen.windows.template_debug.x86_64.dll`
   exists; if not, the build silently failed — re-run scons and read the
   output.

## Directory layout

```
extensions/voxel_gen/
├── SConstruct                  -- delegates to godot-cpp/SConstruct
├── voxel_gen.gdextension       -- Godot's GDExtension manifest
├── README.md                   -- this file
├── .gitignore                  -- excludes build intermediates
├── src/
│   ├── register_types.h
│   ├── register_types.cpp      -- GDExtension entry + class registration
│   ├── spike_stone_generator.h
│   └── spike_stone_generator.cpp
├── godot-cpp/                  -- submodule pinned to godot-4.6 branch
└── bin/                        -- compiled libraries (gitignored intermediates)
```

## What comes next

This README will be expanded as the port progresses. See the project plan
in `/root/.claude/plans/` for phase definitions and verification gates.
