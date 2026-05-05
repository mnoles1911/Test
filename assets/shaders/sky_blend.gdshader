// sky_blend.gdshader
// Sky shader that cross-fades between two equirectangular panorama
// textures (the "from" and "to" anchors flanking the current time of day).
// DayNightCycle.gd writes the texture uniforms and the blend factor every
// frame based on WorldClock's hour-of-day.
//
// In plain English:
//   The world has four "anchor" sky paintings — dawn, noon, dusk, night.
//   At any moment we're between two of them (e.g. 06:30 is between night
//   and dawn). DayNightCycle decides which two and how far between, then
//   this shader samples both panoramas and mixes them together per pixel
//   of the sky background.
//
//   Equirectangular projection means the source images are 2:1 rectangles
//   that wrap around the world like an unrolled cylinder — Midjourney can
//   produce these directly with the "--ar 2:1" + "equirectangular panorama"
//   prompt. We convert the per-pixel view direction (EYEDIR) to a UV
//   coordinate on that rectangle so each direction in the sky maps to
//   the correct pixel in the painting.
//
// The sun and moon you see in the sky are NOT in this shader — they're
// 3D sphere meshes (SunMesh / MoonMesh in World3D.tscn) positioned in
// front of the sky by DayNightCycle each frame. So the panoramas should
// be painted with NO sun or moon visible.

shader_type sky;

uniform sampler2D texture_from : source_color, filter_linear;
uniform sampler2D texture_to   : source_color, filter_linear;
uniform float blend : hint_range(0.0, 1.0) = 0.0;

// Convert a unit-length view direction into equirectangular UV coords.
//   u = atan2(z, x) / (2*PI) + 0.5   →  longitude, 0..1 around the horizon
//   v = acos(y) / PI                 →  latitude, 0 at zenith → 1 at nadir
// Godot's EYEDIR is the world-space direction from the camera through
// each rendered sky pixel; it's already normalized by the sky pipeline.
vec2 equirect_uv(vec3 dir) {
	float u = atan(dir.z, dir.x) / (2.0 * 3.14159265) + 0.5;
	float v = acos(clamp(dir.y, -1.0, 1.0)) / 3.14159265;
	return vec2(u, v);
}

void sky() {
	vec2 uv = equirect_uv(EYEDIR);
	vec3 col_from = texture(texture_from, uv).rgb;
	vec3 col_to   = texture(texture_to,   uv).rgb;
	COLOR = mix(col_from, col_to, blend);
}
