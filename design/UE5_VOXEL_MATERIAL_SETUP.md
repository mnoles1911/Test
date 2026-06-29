# UE5 Voxel Material & Scene Setup (M2)

How the generated voxel terrain is made to look right under Lumen. Plain-English
notes so the look is reproducible (the scene tuning below is editor/level state,
not baked into C++).

## Per-face solid color (no texture atlas)

At 10 cm, each voxel face is one flat color, shaded per direction. The Core
mesher (`Core/VoxelColor.h`) bakes `base_color(material) × face_shade(direction)`
into each vertex's RGB; ambient occlusion rides in vertex **alpha**. So the
material is trivial: vertex color → BaseColor.

## The sRGB gotcha (important)

`base_color()` values are transcribed from the Godot palette as **sRGB** bytes
(grass = 97,140,56 = a proper green). But `ProceduralMeshComponent` vertex colors
reach the material's **VertexColor** node as **linear** (byte/255), so a saturated
sRGB green used directly as a linear albedo desaturates to **tan/khaki**.

**Fix (canonical material `M_VoxelTerrainV2`):** decode sRGB→linear in the material —
`VertexColor.RGB → Power(const_exponent = 2.2) → BaseColor`, and `VertexColor.A →
AmbientOcclusion`, Roughness ≈ 0.9. (Use the Power node's `const_exponent`
property, NOT a connected "Exp" pin — the pin name differs and silently no-ops.)
A future cleaner option: pre-bake the palette to linear in `VoxelColor.h` so a
plain VertexColor→BaseColor material is correct and no decode node is needed.

- `M_VoxelTerrainV2` — terrain (sRGB-decoded vertex color). **Canonical.**
- `M_VoxelWater` — translucent blue (upgrade to Single Layer Water later).
- `M_VoxelFlora` — two-sided vertex color (cross-quad blades/flowers).
- (`M_VoxelTerrain*` earlier variants are superseded; safe to delete when the
  editor isn't referencing them — never `delete_asset` an in-use material from
  Python, it pops a modal that hangs the headless editor.)

## Scene/lighting setup for the beauty shot

Auto-exposure keys on the bright sky and crushes the terrain to near-black. Lock it:
- Unbound **PostProcessVolume** → `Exposure`: Min/Max EV100 both ≈ **11** (locked
  daylight). Without this the colors read dark/washed regardless of material.
- **DirectionalLight**: afternoon angle (pitch ≈ −45, yaw ≈ −35), intensity ≈ 8.
- Keep the template `SkyAtmosphere` + `SkyLight` + `ExponentialHeightFog` +
  `VolumetricCloud` (Lumen GI/reflections do the rest).

## Terrain shape knobs (AVoxelWorld, live-tunable, no rebuild)

The legacy generator swings ±75 m (spires). Gentle rolling grassland:
`MacroRangeVoxels ≈ 80`, `MacroFrequency ≈ 0.0025`, `MidAmplitudeVoxels ≈ 10`,
`HeightOffsetVoxels ≈ 138` (above beach 74 / sea 120 → green grass + valley lakes).
Biome-path parity (Whittaker profiles) is the proper long-term terrain source.
