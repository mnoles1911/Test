// sky_blend.gdshader
// Sky shader: cross-fades two equirectangular panorama textures (the
// "from" and "to" time-of-day anchors) AND draws a procedural animated
// cloud layer on top.
//
// In plain English:
//   PART 1 — panoramas. The world has four "anchor" sky paintings —
//   dawn, noon, dusk, night. At any moment we're between two of them
//   (e.g. 06:30 is between night and dawn). DayNightCycle.gd decides
//   which two and how far between, then this shader samples both
//   panoramas and mixes them per sky pixel.
//
//   PART 2 — clouds (Phase H). On top of that painted sky we draw
//   moving clouds, generated with maths (no texture needed). They:
//     - drift slowly on their own using the built-in TIME clock,
//     - are lit by the sun (Godot hands the sky shader the scene's
//       main DirectionalLight as LIGHT0) — so they glow at noon, turn
//       orange at dusk, and go dark blue at night with zero extra
//       wiring,
//     - thicken or thin with the `cloud_coverage` uniform, which
//       WeatherManager drives through DayNightCycle.set_cloud_coverage()
//       (clear sky -> low coverage, overcast/storm -> high).
//
//   Equirectangular projection: the panorama source images are 2:1
//   rectangles that wrap around the world like an unrolled cylinder.
//
// The sun and moon discs are NOT in this shader — they're 3D sphere
// meshes (SunMesh / MoonMesh) positioned by DayNightCycle. Paint the
// panoramas with no sun or moon visible.

shader_type sky;

// --- Panorama cross-fade (DayNightCycle writes these every frame) ---
uniform sampler2D texture_from : source_color, filter_linear;
uniform sampler2D texture_to   : source_color, filter_linear;
uniform float blend : hint_range(0.0, 1.0) = 0.0;

// --- Volumetric cloud layer (Phase H) ---
// cloud_coverage: 0 = clear sky (a few wisps), 1 = fully overcast.
// WeatherManager drives this via DayNightCycle.set_cloud_coverage().
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.4;
// Overall opacity of the cloud layer once a pixel IS cloud.
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.92;
// Noise frequency — bigger = smaller, busier clouds.
uniform float cloud_scale = 0.8;
// Drift speed across the sky.
uniform float cloud_scroll_speed = 0.006;
// Edge softness of the coverage cut — bigger = fluffier, fuzzier edges.
uniform float cloud_softness : hint_range(0.01, 0.5) = 0.20;
// Cloud colours. Lit = sun-facing puff tops; shadow = undersides;
// night = colour when the sun has set (LIGHT0 energy ~ 0).
uniform vec3 cloud_lit_color : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shadow_color : source_color = vec3(0.46, 0.51, 0.62);
uniform vec3 cloud_night_color : source_color = vec3(0.05, 0.07, 0.13);

// Convert a unit-length view direction into equirectangular UV coords.
//   u = atan2(z, x) / (2*PI) + 0.5   ->  longitude, 0..1 around horizon
//   v = acos(y) / PI                 ->  latitude, 0 zenith -> 1 nadir
vec2 equirect_uv(vec3 dir) {
	float u = atan(dir.z, dir.x) / (2.0 * 3.14159265) + 0.5;
	float v = acos(clamp(dir.y, -1.0, 1.0)) / 3.14159265;
	return vec2(u, v);
}

// --- Asset-free noise (hash-based value noise + fbm) -----------------
// Same family as underwater_fog.gdshader's noise: no texture lookup,
// no tiling at any reasonable scroll speed.
float cloud_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float cloud_value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = cloud_hash(i);
	float b = cloud_hash(i + vec2(1.0, 0.0));
	float c = cloud_hash(i + vec2(0.0, 1.0));
	float d = cloud_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Five octaves of value noise — peaks just under 1.0.
float cloud_fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		total += cloud_value_noise(p) * amp;
		p *= 2.0;
		amp *= 0.5;
	}
	return total;
}

void sky() {
	// --- Panorama cross-fade ---
	vec2 uv = equirect_uv(EYEDIR);
	vec3 sky_col = mix(
		texture(texture_from, uv).rgb,
		texture(texture_to, uv).rgb,
		blend);

	// --- Cloud layer ---
	// Only the sky above the horizon gets clouds.
	float up = EYEDIR.y;
	if (up > 0.01) {
		// Project the view ray onto a flat horizontal cloud layer.
		// Dividing the horizontal direction by the vertical component
		// gives a 2D coordinate that naturally foreshortens clouds
		// toward the horizon, like a real cloud ceiling.
		vec2 plane = EYEDIR.xz / up;
		vec2 cuv = plane * cloud_scale
			+ vec2(TIME * cloud_scroll_speed, TIME * cloud_scroll_speed * 0.6);

		float density = cloud_fbm(cuv);

		// Coverage: higher coverage lowers the threshold so more of the
		// noise field counts as cloud.
		float lo = mix(0.95, 0.12, cloud_coverage);
		float cloud = smoothstep(lo, lo + cloud_softness, density);

		// Cheap lighting: sample the noise again offset TOWARD the sun.
		// A sun-facing cloud edge has less cloud in the sunward
		// direction, so (here - sunward) is positive there -> lit.
		float lit = 0.6;
		float day = 0.0;
		if (LIGHT0_ENABLED) {
			vec2 sunward = -normalize(LIGHT0_DIRECTION.xz + vec2(0.0001));
			float sun_density = cloud_fbm(cuv + sunward * 0.10);
			lit = clamp((density - sun_density) * 3.2 + 0.55, 0.0, 1.0);
			// Day factor from sun energy (DayNightCycle ramps it 0..2.2).
			day = clamp(LIGHT0_ENERGY * 0.5, 0.0, 1.0);
		}

		vec3 day_cloud = mix(cloud_shadow_color, cloud_lit_color, lit);
		// Tint the lit tops with the sun colour — warm at dawn/dusk.
		if (LIGHT0_ENABLED) {
			day_cloud *= mix(vec3(1.0), LIGHT0_COLOR, 0.5 * lit);
		}
		// Fade to the night colour as the sun sets.
		vec3 cloud_rgb = mix(cloud_night_color, day_cloud, day);

		// Fade clouds out near the horizon so the flat layer's
		// stretching never smears into an ugly band.
		float horizon_fade = smoothstep(0.02, 0.32, up);
		float alpha = cloud * cloud_opacity * horizon_fade;
		sky_col = mix(sky_col, cloud_rgb, alpha);
	}

	COLOR = sky_col;
}
