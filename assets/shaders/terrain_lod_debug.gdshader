shader_type spatial;
render_mode unshaded, cull_back;

// Debug-only LOD band shader. Renders every voxel surface as a flat
// colour based on world-space distance from the player, so the LOD
// rings (0–21 m green / 21–42 m yellow / 42–84 m orange / 84–168 m
// red / beyond purple) are dead-obvious in the world.
//
// Distance bands are CALIBRATED to lod_distance=128 voxels at the
// world scale of 1/6 m/voxel = 21.33 m per LOD ring. Each ring
// doubles. If you change `terrain.lod_distance` you'll need to
// recompute these.
//
// Toggled by World3DBootstrap.gd swapping `terrain.material` between
// null (per-cube atlas materials drive rendering) and this debug
// material. Per the CLAUDE.md gotcha: setting `terrain.material`
// overrides every per-cube `material_override_0` — exactly what we
// want for a global debug.

// GLOBAL uniform — written via RenderingServer.global_shader_parameter_set
// from World3DBootstrap.gd. Using a global instead of a regular uniform
// because Zylann's VoxelLodTerrain duplicates `terrain.material` per
// chunk under the hood, so per-frame writes to the cached ShaderMaterial
// don't propagate to the GPU copies. Globals bypass that entirely.
global uniform vec3 player_world_pos;

// Threshold radii in METRES. With lod_distance = 128 vox and world
// scale 1/6 m/vox, each LOD ring ends at:
//   LOD0 → 21.33 m
//   LOD1 → 42.67 m
//   LOD2 → 85.33 m
//   LOD3 → 170.67 m
uniform float lod0_end = 21.33;
uniform float lod1_end = 42.67;
uniform float lod2_end = 85.33;
uniform float lod3_end = 170.67;

// Per-LOD colours. Picked for max distinctness on a typical sky/
// grass background — green is unmistakable, red and purple stand
// out at distance, orange is between.
const vec3 COL_LOD0 = vec3(0.20, 1.00, 0.30);   // green
const vec3 COL_LOD1 = vec3(1.00, 0.95, 0.10);   // yellow
const vec3 COL_LOD2 = vec3(1.00, 0.55, 0.10);   // orange
const vec3 COL_LOD3 = vec3(1.00, 0.20, 0.20);   // red
const vec3 COL_BEYOND = vec3(0.55, 0.20, 0.90); // purple

// Faint dark gridlines at LOD boundaries so the transitions are
// obvious even when adjacent voxels happen to be on the same band
// (you'd see a thin dark line at exactly 21 m / 42 m / 84 m).
const float BOUNDARY_THICKNESS_M = 0.5;

varying vec3 v_world_pos;

void vertex() {
	// MODEL_MATRIX already folds in the terrain Node3D's 1/6 scale,
	// so this comes out in metres without any further conversion.
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = distance(v_world_pos, player_world_pos);

	vec3 col;
	if (d < lod0_end) {
		col = COL_LOD0;
	} else if (d < lod1_end) {
		col = COL_LOD1;
	} else if (d < lod2_end) {
		col = COL_LOD2;
	} else if (d < lod3_end) {
		col = COL_LOD3;
	} else {
		col = COL_BEYOND;
	}

	// Darken right at each LOD ring boundary so the rings are
	// always visible. ±0.5 m band around each threshold.
	float boundary_dim = 1.0;
	float t = BOUNDARY_THICKNESS_M;
	if (abs(d - lod0_end) < t || abs(d - lod1_end) < t || abs(d - lod2_end) < t || abs(d - lod3_end) < t) {
		boundary_dim = 0.3;
	}

	ALBEDO = col * boundary_dim;
}
