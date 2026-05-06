# assets/voxel/

Voxel-related shipped resources.

## Files

- `copper_isles_generator.tres` — `VoxelGeneratorScript` resource pointing
  at `scripts/CopperIslesHeightmapGenerator.gd`. Reads the EXR heightmap on
  first chunk generation. Used by both `scenes/CopperIslesTest.tscn` (the
  scale-iteration test scene) and `scenes/_dev/BakeWorld.tscn` (the
  world-bake dev tool).

- `copper_isles_baseline.sqlite` *(produced by the bake tool — see below)*
  — read-only baseline voxel cache. Shipped in the PCK. Every player gets
  the same Copper Isles terrain; the runtime two-tier stream layers each
  save slot's edits on top of this baseline.

## Bake workflow

1. Open `scenes/_dev/BakeWorld.tscn` and press F6 to run.
2. Click **Run Diagnostics** to probe Zylann APIs once. Copy the output
   into `design/COPPER_ISLES_BAKE_NOTES.md` so the team has a record.
3. Click **Bake 1 km central** for a quick validation pass (~2-5 min).
   Verify the resulting `user://baked_baseline.sqlite` is between 80 MB
   and 200 MB. If the size is wildly off, the vertical-extent cap or
   the EXR sampling is misconfigured — see Phase A1 in
   `~/.claude/plans/make-plan-to-implement-buzzing-frost.md`.
4. Click **Bake full 5 km** for the production pass (~30-90 min).
5. Click **Copy bake DB → assets/voxel/copper_isles_baseline.sqlite**
   when satisfied with the result. The DB lands in this directory and
   gets committed to git.

## Export presets

The baseline `.sqlite` is large (1-4 GB). Make sure
`export_presets.cfg` includes `*.sqlite` in the export filter for any
release build, or the baseline won't make it into the PCK and the game
will fall back to slow runtime generation.

## Re-baking

When the heightmap or the generator's material bands change, the
baseline DB is invalidated. Delete `assets/voxel/copper_isles_baseline.sqlite`
+ `user://baked_baseline.sqlite` and re-run the bake tool.
