# tools/blender/

Blender bridge for the voxel studios. **Blender is optional** — the studios
already export game-ready voxel JSON for the Godot importer. Use Blender when
the deliverable is a *render*, a *mesh* (`.glb` decorative prop), or to voxelize
an *authored* mesh into the same schema.

## Files

| File | What |
|---|---|
| `import_voxel_json.py` | Import a Voxel Studio export (`{x,y,z,m}` + palette) into Blender as a single welded surface mesh (internal faces culled), one material per id, colored from the palette. Add-on + Scripting + headless CLI. |
| `run.sh` | Run any Python script inside **headless** Blender (`blender --background --python …`). |
| `voxel_character_template.blend` | Existing character template (unrelated to the studios). |

## Import a studio export

**Interactive (add-on):** Edit → Preferences → Add-ons → *Install…* →
`import_voxel_json.py` → enable. Then **File → Import → Voxel Studio JSON**.

**Scripting tab:** open `import_voxel_json.py`, press *Run*, then
`import_voxel_json("/path/tree.json")`.

**Headless / batch:**
```bash
tools/blender/run.sh tools/blender/import_voxel_json.py -- \
    exports/tree_oak.json --render /tmp/oak.png --turntable 8 --save /tmp/oak.blend
```
Flags after `--`: `--render <png>` (beauty render; with `--turntable N` writes
N frames around the asset), `--save <blend>`, `--scale <m>` (override
`voxel_size_m`).

Axes: studios are **+Y up**; Blender is **+Z up**, so the importer maps studio
`(x,y,z) → Blender (x, z, y)`. Voxels are placed at `voxel_size_m` (0.1 m) so the
model is real-world scale.

## Headless Blender for ad-hoc tasks

`run.sh` runs *any* Blender Python script headlessly, so it doubles as the way to
have Claude drive Blender for a modelling/automation task:
```bash
tools/blender/run.sh /tmp/scratch_task.py -- <args>
```
Claude writes the script, runs it via `run.sh`, and you get the `.blend`/render
out. **Requires Blender installed** (`blender` on PATH, or `BLENDER=/path/...`).
In a cloud session where Blender isn't present, Claude can install it on request
(it's a few hundred MB) — otherwise run these locally.

## Round-trip into the existing asset bridge

Once a generated asset is a Blender mesh, it can ride your existing
`design/ASSET_PIPELINE_AI.md` bridge (Remesh / vertex-bake / export `.glb`) for
non-destructible decorative scenery — same as authored/AI meshes.
