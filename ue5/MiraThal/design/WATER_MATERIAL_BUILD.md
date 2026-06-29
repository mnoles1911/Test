# Water Material Build Spec — `M_VoxelWaterSLW` (Single Layer Water)

**Status:** BUILD-READY (2026-06-22). Companion + fallback to the automated builder
`ue5/MiraThal/Saved/build_water_material.py`. This is the **node-by-node hand-build** of the same
material, plus the exact Material + project settings and the Material-Instance parameter table.
Implements `design/WATER_RENDERING_PLAN.md` against the UE5.7 engine at `D:/UE5/UE_5.7`.

> **Plain-English orientation.** The Python script builds this material for you in one shot. This doc
> is the paper version: if a single node in the script misbehaves, open the material and rebuild *that
> part* by hand from the steps here. It also holds the **parameter table** you tune in a Material
> Instance. Nothing here touches the water simulation or the mesh — it is pure rendering.

---

## 0. What the mesh already hands the material (do NOT change these)

The water mesher + GPU upload already feed two custom channels. The material **reads** them; the C++ is
done. Verified in source:

| Data | Lives in | Material reads it as | Source (cited) |
|---|---|---|---|
| **Flow direction** `(flow_x, flow_z)` | **UV1** (TexCoord index **1**) | `TextureCoordinate` node, Coordinate Index **1** | `MiraVoxelMesh.cpp:59` — `UV1.Add(FVector2D(V.flow_x, V.flow_z));` |
| **Foam** `0..1` (0 = open water, 1 = shoreline edge) | **Vertex Color ALPHA** | `VertexColor` node → **A** pin | `WaterSurfaceMesher.h` `emit_water_quad` sets `mv.ao = foam_v`; `MiraVoxelMesh.cpp:65,75` pack that `ao` into `FColor` alpha (`AoA`) |
| Per-cell tile UV | UV0 (TexCoord index 0) | `TextureCoordinate` node, index 0 | `MiraVoxelMesh.cpp:51` |
| Flat fallback albedo `{51,102,153}` | Vertex Color RGB | ignored — we use ShallowColor/DeepColor params | `WaterSurfaceMesher.h` `wcol = base_color(WATER_FULL)` |

> Still / vertical / settled cells carry flow `(0,0)` → no scroll. Foam is only written on the **top**
> quad's corners; side quads carry foam `0`.

---

## 1. Material-level settings (set these FIRST, on the material itself)

These are **editor properties on the `UMaterial`**, not graph nodes. In the Details panel of the
material (verified property + enum names against `Engine/Public/Materials/Material.h` and
`Engine/Classes/Engine/EngineTypes.h`):

| Material setting | Value | Engine property / enum | Why |
|---|---|---|---|
| **Shading Model** | **Single Layer Water** | `shading_model` = `MSM_SingleLayerWater` | The whole approach |
| **Blend Mode** | **Opaque** | `blend_mode` = `BLEND_Opaque` | SLW is an opaque custom pass; cleanest under Lumen |
| **Two Sided** | **ON** | `two_sided` = `true` | No holes when camera dips to water level (open sides) |
| **Used with Water** | **ON** | `used_with_water` (usage flag) | Some SLW/water paths require it; harmless |
| **Refraction Method** | **Pixel Normal Offset** | `refraction_method` = `RM_PixelNormalOffset` | Correct for big flat water; no off-screen smear |

> **Substrate note:** MiraThal is an *existing* project upgraded to 5.7, so it stays on the **legacy
> (non-Substrate)** material path — this is the classic SLW shading-model node graph, which is what you
> get by default. (UE5.7 only defaults Substrate ON for *new* projects.) Do not opt into Substrate for
> water v1. See `WATER_RENDERING_PLAN.md` §2.4.

---

## 2. Project settings to confirm (one-time, not per-material)

These belong to the atmosphere/Lumen pass but the water needs them to read right (cite
`ATMOSPHERE_LIGHTING_SPEC.md`):

- **Reflection Method = Lumen**, **GI = Lumen** (Project Settings → Rendering). Lumen supplies the
  water's reflected sky/terrain.
- **Auto-exposure LOCKED, Manual, Min = Max EV100 = 11** on the unbound PostProcessVolume. Tune all
  water brightness to this anchor; never move exposure to fix water.
- **Known Lumen constraint (designed around, not a bug):** Lumen forces **mirror** reflections on SLW —
  the Roughness input does **not** blur the reflection. So ripple must come from the **normal map**
  (§6), not from roughness. This is the correct lever for flat cube-top water anyway.

---

## 3. Node graph overview (left → right)

```
 SceneDepthWithoutWater ─┐
                         ├─(Subtract)─(Divide by DepthFadeDistance)─(Saturate)= depth01
 PixelDepth ─────────────┘                                              │
                                                                        ├──► Lerp(Shallow,Deep) = waterColor
 VertexColor.A ──(× FoamAmount)= foamMask ──────────────────────────────┤
                                                                        └─► Lerp(waterColor,FoamColor,foamMask) ─► BASE COLOR

 TexCoord0 ─(× NormalTiling)─┬─ Panner A  (Speed = UV1flow × FlowSpeed) ─► WaterNormal sample A ─┐
                            └─(×1.7)─ Panner B (ambient speed) ─────────► WaterNormal sample B ─┴─ BlendAngleCorrectedNormals ─ FlattenNormal(WaveStrength) = N
                                                                                                                                   │
 N ─► NORMAL input ;  N ─► Fresnel.Normal                                                                                          │
 Fresnel(FresnelExponent) ─ Lerp(ReflectionMin,ReflectionMax) = reflStrength ─(× Specular)─► SPECULAR                              │
 RefractionScale (≈1.04) ─────────────────────────────────────────────────────────────────────► REFRACTION (PNO uses N)          │
 WaterOpacity ─► OPACITY ;  Roughness ─► ROUGHNESS                                                                                 │

 ScatteringColor ─► SLW.ScatteringCoefficients
 AbsorptionColor ─► SLW.AbsorptionCoefficients
 PhaseG ─────────► SLW.PhaseG
 (1.0 + CausticStrength) ─► SLW.ColorScaleBehindWater
```

---

## 4. Hand-build steps (do in order)

1. **Create** the material at `/Game/Voxel/Materials/M_VoxelWaterSLW`. Apply the §1 settings.
2. **Depth (the "how deep is the water here" value):**
   - Add `SceneDepthWithoutWater` (NOT `SceneDepth` — SLW is opaque, plain SceneDepth reads the water
     surface itself). Add `PixelDepth`.
   - `Subtract`: A = SceneDepthWithoutWater, B = PixelDepth.
   - `Divide` that by the **DepthFadeDistance** scalar param, then `Saturate` → call it **depth01**
     (0 at the shoreline, 1 in deep water).
3. **Base color:** `Lerp` A = **ShallowColor**, B = **DeepColor**, Alpha = depth01.
4. **Normals + flow (the ripple):**
   - `TextureCoordinate` index **0** → `Multiply` by **NormalTiling** = scaled UVs.
   - `TextureCoordinate` index **1** (this is the FLOW vector) → `Multiply` by **FlowSpeed** = flow
     speed vector.
   - `Panner` **A**: Coordinate = scaled UVs, Speed = flow speed vector. (Rivers scroll downstream.)
   - `Panner` **B**: Coordinate = scaled UVs × 1.7 (a different frequency so the two octaves never form
     a checkerboard), Speed = a small **AmbientRippleSpeed** vector (so STILL ponds still shimmer).
   - Two `WaterNormal` `TextureSampleParameter2D` nodes (same parameter name → shared in the MI),
     Sampler Type = **Normal**. UVs = Panner A and Panner B respectively. Default texture = engine
     `FlatNormal` so it compiles calm; swap to a real CC0 water normal in the MI.
   - `BlendAngleCorrectedNormals` (material function) to blend the two normal samples.
   - `FlattenNormal` (material function), Flatness = **WaveStrength** scalar (0 = flat … 1 = choppy).
   - Wire result → **Normal** input.
5. **Refraction (PNO):** wire the **RefractionScale** scalar (≈1.04) → **Refraction** input. With Pixel
   Normal Offset, the normal above does the distortion; the pin just takes the amount (1.0 = none).
   **No normal map = no refraction**, so this rides on step 4.
6. **Reflection (Fresnel):** `Fresnel` node, ExponentIn = **FresnelExponent**, Normal = the rippled
   normal from step 4. `Lerp` A = **ReflectionMin** (straight-on), B = **ReflectionMax** (grazing cap),
   Alpha = Fresnel → **reflStrength**.
7. **PBR pins:**
   - **Opacity** ← **WaterOpacity** (SLW: low = see far/clear, high = opaque).
   - **Roughness** ← **Roughness** (keep low ~0.04 for a sharp sun glint; remember Lumen ignores it for
     reflection blur, but it still affects the sun specular highlight).
   - **Specular** ← **Specular** × reflStrength.
8. **Foam:** `VertexColor` → **A** pin (foam mask), `Multiply` by **FoamAmount**. `Lerp` A = the step-3
   water color, B = **FoamColor**, Alpha = foam mask. Wire result → **Base Color** (replaces the direct
   step-3 wire).
9. **SLW volume output:** add `SingleLayerWaterMaterialOutput`. Wire **ScatteringColor** →
   ScatteringCoefficients, **AbsorptionColor** → AbsorptionCoefficients, **PhaseG** → PhaseG.
   `Add` 1.0 + **CausticStrength** → ColorScaleBehindWater (default 0 → 1.0 = no change).
10. **Apply / Save.** Confirm it compiles with no errors.

---

## 5. Material-Instance parameter table (tune these; defaults = Skyrim-grounded, EV100 = 11)

Create **`MI_VoxelWaterSLW`** (right-click the material → Create Material Instance) and tune here.
Defaults are deliberately calm + cool (Nordic), calibrated to the locked exposure.

### Group 01 — Color
| Parameter | Type | Default | Tuning range | What it does |
|---|---|---|---|---|
| `ShallowColor` | Vector (RGB) | (0.05, 0.22, 0.27) | teal→green | Water tint at the shoreline / shallow |
| `DeepColor` | Vector (RGB) | (0.01, 0.05, 0.09) | dark blue→near-black | Water tint in deep water |
| `DepthFadeDistance` | Scalar | 250.0 cm | 100–800 | How many cm of depth to reach DeepColor (smaller = tighter gradient) |
| `WaterOpacity` | Scalar | 0.6 | 0.3–0.9 | SLW opacity; lower = see deeper, higher = murkier |

### Group 02 — SLW Volume
| Parameter | Type | Default | Tuning range | What it does |
|---|---|---|---|---|
| `ScatteringColor` | Vector | (0.04, 0.09, 0.11) | raise for milkier water | Per-channel scattering (thicker = more glow) |
| `AbsorptionColor` | Vector | (0.30, 0.07, 0.04) | red-heavy | Per-channel absorption; red absorbs fastest → blue-green deep tint |
| `PhaseG` | Scalar | 0.3 | -0.3 … 0.7 | Forward(+)/back(-) light scatter |

### Group 03 — Reflection
| Parameter | Type | Default | Tuning range | What it does |
|---|---|---|---|---|
| `FresnelExponent` | Scalar | 5.0 | 2–8 | How fast reflection ramps toward grazing angles |
| `ReflectionMin` | Scalar | 0.02 | 0–0.1 | Straight-on reflectivity |
| `ReflectionMax` | Scalar | 0.85 | 0.5–1.0 | Grazing-angle cap (stops blow-out) |
| `Roughness` | Scalar | 0.04 | 0.01–0.3 | Sun-glint sharpness (Lumen ignores it for reflection blur) |
| `Specular` | Scalar | 1.0 | 0.5–1.0 | Master specular level |

### Group 04 — Normals / Flow / Refraction
| Parameter | Type | Default | Tuning range | What it does |
|---|---|---|---|---|
| `WaterNormal` | Texture | `FlatNormal` (placeholder) | — | **Swap to a real CC0 water normal** (Poly Haven `rocky_terrain_02` nor_gl) |
| `NormalTiling` | Scalar | 0.05 | 0.01–0.2 | Ripple size (smaller = bigger ripples) |
| `FlowSpeed` | Scalar | 0.03 | 0.0–0.2 | How fast ripples scroll along the sim flow |
| `AmbientRippleSpeed` | Scalar | 0.01 | 0.0–0.05 | Shimmer speed for STILL water (flow = 0) |
| `WaveStrength` | Scalar | 0.5 | 0.0–1.0 | 0 = mirror-flat, 1 = choppy (wire to weather MPC later) |
| `RefractionScale` | Scalar | 1.04 | 1.0–1.08 | PNO refraction amount (1.0 = none; keep tiny) |

### Group 05 — Foam
| Parameter | Type | Default | Tuning range | What it does |
|---|---|---|---|---|
| `FoamColor` | Vector | (0.85, 0.90, 0.95) | white-ish | Shoreline foam color |
| `FoamAmount` | Scalar | 1.0 | 0.0–1.0 | Master foam intensity (0 = no foam) |

### Group 06 — Caustics
| Parameter | Type | Default | Tuning range | What it does |
|---|---|---|---|---|
| `CausticStrength` | Scalar | 0.0 | 0.0–1.0 | Lakebed dapple via ColorScaleBehindWater (0 = off). Plug a panning caustic texture here for real dapple |

---

## 6. Assigning + verifying (manual, after the asset exists)

1. **Assign:** the water section currently binds the placeholder `M_VoxelWater`
   (`VoxelChunkActor.cpp` `SetMaterial(FaceClass::Water, WaterMat)`). Point that slot at
   `MI_VoxelWaterSLW` (recommended — tune live), or repoint whatever `M_VoxelWater` resolves to.
2. **Verify in PIE:**
   - Water reads depth-tinted (shallow teal → deep dark-blue), reflective (mirror sky), and the surface
     shimmers; rivers' ripples scroll downstream, ponds shimmer gently in place.
   - Shorelines show a thin bright foam band. (If foam is missing, confirm the section is the **Water**
     section — only it writes foam to vertex alpha.)
   - Refraction only appears once a real `WaterNormal` is plugged (PNO needs a normal map).
3. **If reflection looks like a perfect mirror:** that is Lumen's forced behavior (§2). Raise
   `WaveStrength` / lower `NormalTiling` so the normal breaks it up.

---

## 7. Sources

UE5.7 docs: [Single Layer Water Shading Model](https://dev.epicgames.com/documentation/en-us/unreal-engine/single-layer-water-shading-model-in-unreal-engine),
[Refraction Using Pixel Normal Offset](https://dev.epicgames.com/documentation/unreal-engine/refraction-using-pixel-normal-offset-in-unreal-engine),
[Depth Material Expressions](https://dev.epicgames.com/documentation/en-us/unreal-engine/depth-material-expressions-in-unreal-engine),
[unreal.MaterialEditingLibrary (Python API)](https://dev.epicgames.com/documentation/en-us/unreal-engine/python-api/class/MaterialEditingLibrary).
Community: [WoLD SLW pool water](https://www.worldofleveldesign.com/categories/ue5/single-layer-water-pool-still.php),
[80.lv stylized water (SceneDepthWithoutWater, foam)](https://80.lv/articles/how-to-build-stylized-water-shader-design-implementation-for-nimue),
[SLW forces mirror under Lumen](https://forums.unrealengine.com/t/single-layer-water-material-does-not-seem-to-support-ue5-lumen-reflections/244571).
Engine headers verified at `D:/UE5/UE_5.7`: `MaterialEditingLibrary.h`,
`Material.h` (blend_mode / shading_model / two_sided / used_with_water / refraction_method),
`EngineTypes.h` (`MSM_SingleLayerWater`, `RM_PixelNormalOffset`),
`SceneTypes.h` (`MP_BaseColor`/`MP_Opacity`/`MP_Refraction`/…),
`MaterialExpressionSingleLayerWaterMaterialOutput.h`, `MaterialExpressionSceneDepthWithoutWater.h`,
`MaterialExpressionFresnel.h`, `MaterialExpressionPanner.h`.
Project-internal: `Source/MiraThalVoxel/Private/MiraVoxelMesh.cpp` (UV1 flow + vertex-alpha foam),
`Source/MiraThalVoxel/Public/Core/WaterSurfaceMesher.h` (foam/flow per vertex),
`design/WATER_RENDERING_PLAN.md`, `design/ATMOSPHERE_LIGHTING_SPEC.md`.
