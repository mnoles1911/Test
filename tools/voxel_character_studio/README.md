# Voxel Character Studio

Procedurally generates **bipedal characters/creatures** (human, goblin, dwarf,
Ashfallen knight) as cubic voxels in a strict **T-pose** at **30 voxels/metre**.
Exports the shared voxel JSON — feed it through `tools/blender/import_voxel_json.py`
→ Blender → **Mixamo auto-rig** → `assets/models/<name>.glb`.

> Characters in this game are **rigged `.glb` meshes, not terrain voxels.** This
> studio replaces the *Nano-Banana → Meshy* step of `design/ASSET_PIPELINE_AI.md`
> — it produces the **T-pose shape only**; rigging + animation stay in the
> existing Blender→Mixamo bridge.

## Open it

```
https://raw.githack.com/mnoles1911/Test/claude/voxel-threejs-rendering-oc4akx/tools/voxel_character_studio/index.html
```

## How it works

`character_builder.js` (pure, worker-safe) assembles a **T-pose** humanoid from
named body-part volumes — head, neck, torso, pelvis, arms, hands, legs, feet —
computed from proportion params × total height. It builds everything for **x ≥ 0
and mirrors to x < 0**, guaranteeing the bilateral symmetry Mixamo's auto-rigger
needs. Arms extend horizontally (±X), legs vertical, palms down, feet forward.

Material zones (skin / cloth / leather / metal / hair / eye / etc.) use character
material ids **40–49** — these are **preview/vertex-bake only** (characters become
meshes, not terrain), so they need **no engine `VoxelMaterial` registration**. The
export **embeds an RGB palette** so Blender colors the mesh directly.

## Controls

- **Species** preset (Human/Goblin/Dwarf/Ashfallen) — sets proportions, feature
  flags, and the colour palette.
- Grouped dials (Proportions, Head/Face, Features) with **🔒 locks** and **🎲
  randomize** (per-group + global).
- **Quick adjust**: Taller/Shorter, Bulkier/Leaner, Bigger/Smaller head, More
  goblin-y, New seed.
- **✨ Fit dials with Claude vision** — paste your Anthropic API key, drop a
  character reference image, Claude sets the dials (`claude-opus-4-8`, strict
  tool use). Key is used in the browser, stored only in localStorage.
- **🧍 Scale** — a 1.8 m human stands beside the character for size reference.

## Export format

```json
{ "format":"mira-thal-voxel-character", "version":1,
  "voxel_size_m":0.0556, "species":"Goblin",
  "palette": { "40":[111,154,74], "46":[124,252,0], ... },   // embedded RGB
  "palette_names": { "40":"skin", "46":"eye", ... },
  "size":[w,h,d], "size_m":[...], "params":{...},
  "voxels":[ {"x":..,"y":..,"z":..,"m":40}, ... ] }
```

## Pipeline → Blender → Mixamo

```bash
tools/blender/run.sh tools/blender/import_voxel_json.py -- \
    char_Goblin_seed5.json --save /tmp/goblin.blend
```
The importer reads the **embedded palette** (no engine wiring). Then in Blender:
optional Remesh to ~2.5–4k tris → export → upload to **Mixamo** (T-pose markers)
→ download rigged `.glb` → `assets/models/<name>.glb` → Godot `CharacterBody3D`
auto-detects Skeleton3D + AnimationPlayer.

## Notes / limits

- At 30 vox/m a 1.8 m character is ~54 voxels tall — features are blocky but
  readable (brow/eye/jaw, hands as claw/mitten silhouettes). Good fidelity heading
  into Remesh + rigging.
- Quadrupeds (wolf/bear) are out of scope (not biped / not Mixamo-auto-riggable).
