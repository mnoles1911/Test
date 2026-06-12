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

// NEUTRAL brightness / anti-bloom dial on the C++ vertex-baked palette.
// History (2026-05-26): the raw palette rendered too bright in two
// failure modes —
//   (a) MSAA + bloom at hill-silhouette pixels made the bright skirt
//       ghost through occluding hills.
//   (b) at LOD1+, partial-fill water voxels exposed the skirt below as
//       a grey-tile grid on the water surface near shore.
// so this uniform was multiplied against the palette to darken it. It
// USED to also carry a green HUE bias (0.70, 0.85, 0.55) to fudge the
// hand-guessed palette toward the grass-top atlas colour — that was a
// colour-CORRECTOR, and it was the second compounding guess that left the
// skirt looking pale/washed (2026-06-12 distant-skirt colour fix).
//
// It is now PURELY a uniform darken (a single grey value per channel): the
// palette itself is sampled from the real atlas tiles (see
// DistantTerrainMesher / World3DBootstrap.configure_distant_palette), and
// the bootstrap PRE-DIVIDES each palette colour by this same 0.80 so the
// final rendered ALBEDO == the true atlas tile mean (colour * 0.80 / 0.80).
// The 0.80 still does its anti-bloom job (the on-disk palette is the tile
// mean / 0.80, slightly brighter, and this brings it back to the mean) but
// it no longer shifts hue. Keep it GREY: bump all three channels together
// if the heightmesh disappears into shadow, bump down if hill-silhouette
// bloom bleed returns. Do NOT re-introduce a per-channel hue here.
uniform vec3 albedo_tint : source_color = vec3(0.80, 0.80, 0.80);

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
