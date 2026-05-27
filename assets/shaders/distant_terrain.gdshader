shader_type spatial;

// distant_terrain.gdshader — material for the streaming distant-terrain
// heightmesh (DistantTerrainMesher / DistantTerrainManager). Replaces the
// plain StandardMaterial3D that the retired HorizonSkirt used.
//
// - Vertex-colour albedo: DistantTerrainMesher bakes the elevation /
//   slope / jitter palette into ARRAY_COLOR.
// - Matte + double-sided, matching the near terrain (terrain_voxel.gd-
//   shader is specular_disabled / roughness 0.85) so the blocky->smooth
//   handoff shows no shading seam.
// - Environment fog applies automatically (no fog_disabled render mode)
//   so the heightmesh fades into aerial perspective like everything else.
// - `fade_factor` + an ordered 4x4 Bayer dither drive the LOD-swap
//   cross-fade: DistantTerrainManager lerps fade_factor 0<->1 on a chunk
//   while its old / new LOD mesh swaps, so the swap reads as a smooth
//   dissolve, not a hard pop. fade_factor = 1.0 (the default) keeps every
//   pixel — a no-op for chunks that are not mid-swap.

render_mode cull_disabled, specular_disabled;

// LOD-swap cross-fade. 1.0 = fully visible; 0.0 = fully discarded.
uniform float fade_factor : hint_range(0.0, 1.0) = 1.0;

// Matte terrain — matches terrain_voxel.gdshader.
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.85;

// Per-channel darkening factor on the C++ vertex-baked palette. The
// raw palette renders too bright in two failure modes (2026-05-26):
//   (a) MSAA + bloom at hill-silhouette pixels makes the bright skirt
//       ghost through occluding hills.
//   (b) at LOD1+, partial-fill water voxels expose the skirt below as
//       a grey-tile grid on the water surface near shore.
// Multiplied against the baked palette to (a) kill the hill-silhouette
// MSAA/bloom ghosting from the old too-bright skirt, (b) bias the
// palette slightly green so the distant terrain visually matches the
// near grass-top + dirt-side atlas colour at the blocky→smooth handoff.
// Tunable live in the Inspector — bump up if the heightmesh disappears
// into shadow, bump down if hill-silhouette bleed returns.
uniform vec3 albedo_tint : source_color = vec3(0.70, 0.85, 0.55);

// Ordered 4x4 Bayer matrix — a stable, shimmer-free dither pattern.
const float BAYER_4X4[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

void fragment() {
	// LOD-swap dither: discard pixels whose Bayer threshold has not yet
	// been reached by the fade level. At fade_factor = 1.0 the largest
	// threshold (15.5/16) is still below 1.0, so nothing is discarded.
	int bx = int(mod(FRAGCOORD.x, 4.0));
	int by = int(mod(FRAGCOORD.y, 4.0));
	float threshold = (BAYER_4X4[bx + by * 4] + 0.5) / 16.0;
	if (threshold >= fade_factor) {
		discard;
	}
	ALBEDO = COLOR.rgb * albedo_tint;
	ROUGHNESS = surface_roughness;
	METALLIC = 0.0;
}
