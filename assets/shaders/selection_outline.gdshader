// selection_outline.gdshader — edge-only wireframe outline on the
// targeted voxel BoxMesh. Replaces the v1 translucent emissive fill
// in EditToolHandler._build_aim_outline (designer feedback 2026-05-27:
// wanted "outline-style" like Minecraft, not a solid cyan cube).
//
// HOW IT WORKS:
//   Each BoxMesh face has UV.x/UV.y in [0, 1] across the face. Edge
//   distance per fragment is min(u, v, 1-u, 1-v) — that's the distance
//   to the NEAREST of the four face edges. Below outline_thickness =
//   opaque edge colour; above = fully transparent. Same shader runs
//   on all 6 faces; result is the 12 edges of the cube rendered as a
//   bright thin frame, transparent elsewhere.
//
//   No vertex tangents needed (water-safe — global bake_tangents stays
//   off; same constraint as the rest of the project, see
//   design/GRAPHICS_PASS_2026-05-19.md Phase C SHELVED note).
//
// Render config:
//   unshaded         — colour is uniform; lighting would muddy it.
//   cull_disabled    — player sees the outline from inside the box too
//                       (e.g. they're standing on the voxel they're
//                       targeting from underneath).
//   blend_mix        — standard alpha blend so we can fade edges.
//   depth_draw_never — the outline never writes depth; nothing should
//                       z-test against it. Combined with no_depth_test
//                       below, this makes it always visible through
//                       terrain (same as the v1 BoxMesh translucent
//                       fill's effective behaviour).
//   no_depth_test    — outline always renders on top, so it's visible
//                       even when the targeted voxel is occluded by
//                       a closer foreground voxel (helps when mining
//                       a voxel partially hidden by terrain it sits
//                       behind).

shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, depth_test_disabled;

uniform vec3 outline_color : source_color = vec3(0.30, 1.00, 1.00);
uniform float outline_thickness : hint_range(0.005, 0.25) = 0.04;
uniform float outline_emission : hint_range(0.0, 8.0) = 2.5;

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float edge_dist = min(min(u, v), min(1.0 - u, 1.0 - v));
	// Hard cutoff above the band, smooth ramp inside for a soft AA.
	if (edge_dist > outline_thickness) {
		ALPHA = 0.0;
	} else {
		float t = 1.0 - smoothstep(outline_thickness * 0.5, outline_thickness, edge_dist);
		ALBEDO = outline_color;
		EMISSION = outline_color * outline_emission;
		ALPHA = clamp(t, 0.0, 1.0);
	}
}
