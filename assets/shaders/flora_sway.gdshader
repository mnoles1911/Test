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

// Peak horizontal sway of the blade TOP, in world metres. The base never
// moves (it's rooted in the ground); the sway scales up toward the tip so
// the blade bends rather than slides.
uniform float sway_amplitude_m : hint_range(0.0, 0.5) = 0.06;
// Sway speed (radians/second of the primary sine). Lower = lazier breeze.
uniform float sway_speed : hint_range(0.0, 8.0) = 1.6;
// How quickly the sway phase changes across the ground (1/metre). Larger
// values = neighbouring blades more out of phase = finer ripple.
uniform float sway_spatial_freq : hint_range(0.0, 2.0) = 0.35;
// Roughness for the lit path (flora reads matte). Metallic is always 0.
uniform float flora_roughness : hint_range(0.0, 1.0) = 1.0;

// The fraction of blade height used as the "sway weight" reference. The
// blade's own local height (model-space Y, 0 at root) drives the weight;
// we read it from the vertex before the model transform. Cross-quad flora
// is built rooted at y=0 with the tip at the top, so VERTEX.y in model
// space is a clean 0..h height — perfect as the bend weight.

void vertex() {
	// Blade-local height as the bend weight: 0 at the rooted base, growing
	// toward the tip. squaring biases the bend to the top third so the
	// base stays planted (a real blade hinges near the ground).
	float local_h = max(VERTEX.y, 0.0);
	float weight = local_h * local_h;

	// World-XZ of this blade's origin, used as the spatial phase so the
	// whole field doesn't move in lockstep. MODEL_MATRIX[3].xyz is the
	// instance/world origin — works for BOTH a normal MeshInstance and a
	// MultiMesh instance (each instance carries its own MODEL_MATRIX).
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = (origin.x + origin.z) * sway_spatial_freq;

	// Two summed sines on slightly different rates read as a natural,
	// non-repeating breeze rather than a metronome. The second axis (Z)
	// uses a phase-shifted copy so the blade traces a gentle ellipse, not
	// a flat back-and-forth.
	float t = TIME * sway_speed;
	float swing_x = sin(t + phase) + 0.4 * sin(t * 2.3 + phase * 1.7);
	float swing_z = cos(t * 0.85 + phase * 1.3);

	// Apply in MODEL space (before MODELVIEW) so the bend is in world XZ
	// regardless of camera. weight ties it to height; amplitude caps it.
	VERTEX.x += swing_x * weight * sway_amplitude_m;
	VERTEX.z += swing_z * weight * sway_amplitude_m * 0.6;
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
