shader_type spatial;

// flora_sway.gdshader — gentle wind sway for micro-voxel flora.
//
// WHAT THIS IS, in plain English:
//   The grass blades and flowers in the world (both the REAL destructible
//   voxel flora drawn at LOD0, and the GPU-instanced "impostor" far-grass
//   that fills the LOD1/LOD2 rings) should sway in the wind — swaying grass
//   is core to the Lay-of-the-Land look (VISION_VOXEL_10CM.md ref_01).
//
//   This single shader does two jobs so BOTH layers look identical:
//     1. Draws a flat, double-sided, vertex-colour blade (matching the
//        StandardMaterial3D the real flora used before sway was added —
//        unshaded-ish flat green with the same vertex tint).
//     2. Animates the blade with a gentle sine sway in the vertex stage,
//        driven by the TIME builtin and the blade's world-XZ position so
//        neighbouring blades are out of phase (a field ripples, it doesn't
//        move as one slab).
//
// WHY a shared shader for both layers:
//   The far-grass impostor must look like the near grass it replaces, or
//   the LOD seam this whole feature exists to hide just becomes a
//   "swaying vs not" seam instead. One shader, applied to both materials,
//   guarantees they match — same colour response, same sway curve.
//
// IMPORTANT (PATTERNS_AND_GOTCHAS):
//   * Uses ONLY the TIME builtin for animation — TIME needs no shader
//     globals declared in [shader_globals], so this adds nothing to
//     project.godot. (The repo rule forbids RenderingServer global-param
//     add/get; we don't touch globals at all here.)
//   * cull_disabled draws both faces of the cross-quad (the real flora's
//     StandardMaterial3D used CULL_DISABLED; we match it).
//
// Tunables are uniforms so the designer can dial them in the editor /
// inspector without recompiling. The defaults reproduce a calm breeze.

render_mode cull_disabled, diffuse_lambert, specular_disabled;

// Peak horizontal sway of the blade TOP, in WORLD metres. The base never
// moves (it's rooted in the ground); the sway scales up toward the tip so
// the blade bends rather than slides. Honoured in world metres for BOTH
// layers regardless of their model-space units (see the MODEL_MATRIX
// scale recovery in vertex()).
uniform float sway_amplitude_m : hint_range(0.0, 0.5) = 0.035;
// Sway speed (radians/second of the primary sine). Lower = lazier breeze.
uniform float sway_speed : hint_range(0.0, 8.0) = 1.6;
// How quickly the sway phase changes across the ground (1/metre). Larger
// values = neighbouring blades more out of phase = finer ripple.
uniform float sway_spatial_freq : hint_range(0.0, 2.0) = 0.35;
// Roughness for the lit path (flora reads matte). Metallic is always 0.
uniform float flora_roughness : hint_range(0.0, 1.0) = 1.0;

// The blade's full local height, in the SAME model-space units the mesh
// is built in, used to normalise the bend weight to a clean 0..1 along
// the blade. Set per layer at injection:
//   * real LOD0 flora (Zylann cube-local voxel units): 0.92 (the
//     FloraMeshBuilder tip clamp — just under one voxel).
//   * far-grass impostor (world metres): the blade height_m (~0.25).
uniform float blade_local_height : hint_range(0.01, 4.0) = 0.92;

void vertex() {
	// --- Blade-local height (the gotcha this whole rewrite fixes) -------
	// VERTEX.y is NOT a clean 0..1 here. Zylann BAKES each blocky flora
	// model into the chunk mesh at the voxel's position, so a blade sitting
	// at chunk-local voxel y=27 has VERTEX.y ~= 27..28. The old code used
	// weight = VERTEX.y^2, which at that altitude is ~750 — it flung blade
	// tips ~6 m sideways (the "close grass flying everywhere" bug,
	// 2026-06-12). fract() recovers the blade-local height: blades are
	// rooted on integer voxel boundaries, so fract(VERTEX.y) is 0 at the
	// base and rises to the tip. For the world-space impostor (VERTEX.y =
	// 0..~0.25, well under 1) fract() is a no-op. Normalising by
	// blade_local_height gives a clean 0..1 the bend weight squares.
	float t_h = clamp(fract(VERTEX.y) / max(blade_local_height, 0.001), 0.0, 1.0);
	float weight = t_h * t_h;  // squared: base planted, bend biased to the tip

	// World-XZ of this blade's origin → spatial phase so the field ripples
	// instead of moving as one slab. MODEL_MATRIX[3].xyz is the instance/
	// chunk origin (works for MeshInstance and MultiMesh alike).
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = (origin.x + origin.z) * sway_spatial_freq;

	// Two summed sines read as a natural, non-repeating breeze; the Z axis
	// is phase-shifted so the tip traces a gentle ellipse, not a flat
	// back-and-forth.
	float tm = TIME * sway_speed;
	float swing_x = sin(tm + phase) + 0.4 * sin(tm * 2.3 + phase * 1.7);
	float swing_z = cos(tm * 0.85 + phase * 1.3);

	// Convert the WORLD-metre amplitude into THIS mesh's model space so the
	// two layers (voxel-unit blocky flora at terrain scale 0.1, metre-space
	// impostor at scale 1.0) sway by the same world distance. The length of
	// a MODEL_MATRIX basis column is the model->world scale of that axis.
	float m2w = max(length(MODEL_MATRIX[0].xyz), 0.0001);
	float amp_model = sway_amplitude_m / m2w;

	VERTEX.x += swing_x * weight * amp_model;
	VERTEX.z += swing_z * weight * amp_model * 0.6;
}

void fragment() {
	// Flat vertex-colour albedo — matches the StandardMaterial3D the real
	// flora used (vertex_color_use_as_albedo = true). The cross-quad bakes
	// the grass-green / poppy-red / cornflower-blue tint into COLOR.
	ALBEDO = COLOR.rgb;
	ROUGHNESS = flora_roughness;
	METALLIC = 0.0;
	// Keep any future alpha-textured version crisp; v1 is opaque flat colour
	// so ALPHA stays 1 and no scissor fires.
	ALPHA = COLOR.a;
}
