// selection_outline.gdshader — v2 (2026-05-27 same-day rework).
//
// V1 used UV-based edge detection: min(u, v, 1-u, 1-v) inside fragment().
// Failed because BoxMesh's per-face UV mapping isn't consistent across
// all six faces (designer-reported: the back-top-right edge of the cube
// disappeared while the other 11 rendered). The shared edges between two
// faces with mismatched/flipped UVs collapsed.
//
// V2 uses OBJECT-SPACE edge detection driven by `mesh_half_size` (the
// MeshInstance3D's BoxMesh size / 2, pushed as a uniform from
// EditToolHandler each frame to track carve_volume_size). For each
// fragment, compute distance from the local vertex position to each of
// the 6 cube faces; an EDGE of the cube is where the fragment is within
// `outline_thickness` of TWO or more faces. Works on all 12 edges
// regardless of UV layout.

shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, depth_test_disabled;

uniform vec3 outline_color : source_color = vec3(0.30, 1.00, 1.00);
// Outline thickness in WORLD UNITS — matched to the mesh's actual size
// (designer wants the wireframe ~3% of voxel edge length). EditToolHandler
// can re-push this if the voxel scale changes.
uniform float outline_thickness : hint_range(0.005, 0.5) = 0.025;
uniform float outline_emission : hint_range(0.0, 8.0) = 2.5;
// Half-extents of the BoxMesh in its own local space (so a 1m³ box →
// half_size = (0.5, 0.5, 0.5)). EditToolHandler updates each frame as
// the voxel volume size changes via scroll wheel.
uniform vec3 mesh_half_size = vec3(0.5);

varying vec3 v_local_pos;


void vertex() {
	// Pass the LOCAL-space (a.k.a. model-space, pre-MODEL_MATRIX) vertex
	// position to the fragment shader. Godot's `VERTEX` here is mesh-local
	// before the model transform.
	v_local_pos = VERTEX;
}


void fragment() {
	// Distance from this fragment to each of the 6 cube faces. The cube
	// is axis-aligned in its own local space; faces sit at ±mesh_half_size
	// on each axis. Distance to nearest face on each axis = half - |pos|.
	vec3 d = mesh_half_size - abs(v_local_pos);

	// A cube EDGE is where the fragment is near (within outline_thickness)
	// of TWO faces simultaneously. A CORNER is where it's near all three.
	// Either qualifies as "on the wireframe."
	int near_count = 0;
	if (d.x < outline_thickness) near_count += 1;
	if (d.y < outline_thickness) near_count += 1;
	if (d.z < outline_thickness) near_count += 1;

	if (near_count < 2) {
		ALPHA = 0.0;
	} else {
		// AA: pick the SECOND-smallest distance to a face as the effective
		// edge-distance, then fade with a small smoothstep so the line has
		// soft anti-aliased edges instead of a hard binary boundary.
		// Sort d ascending and grab the middle element.
		float a = min(d.x, min(d.y, d.z));
		float c = max(d.x, max(d.y, d.z));
		float b = d.x + d.y + d.z - a - c;
		float edge_d = b;  // the "second-smallest" face-distance
		float t = 1.0 - smoothstep(outline_thickness * 0.5, outline_thickness, edge_d);
		ALBEDO = outline_color;
		EMISSION = outline_color * outline_emission;
		ALPHA = clamp(t, 0.0, 1.0);
	}
}
