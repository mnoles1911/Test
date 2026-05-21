// sky_blend.gdshader
// The world's sky. Three layers, drawn back-to-front:
//   1. Panorama cross-fade  — two equirectangular time-of-day paintings
//      mixed by DayNightCycle (dawn / noon / dusk / night anchors).
//   2. Night sky (Phase K)  — procedural stars, aurora and nebula that
//      fade in as the sun sets and out as it rises.
//   3. Cloud layer (Phase H) — procedural moving clouds lit by the sun.
//
// In plain English:
//   PANORAMA. Four painted sky images (dawn/noon/dusk/night). At any
//   moment we're between two of them; DayNightCycle picks which two and
//   how far, and this shader mixes them per sky pixel.
//
//   NIGHT SKY. On top of the painted sky, at night only, we draw stars
//   (sparse twinkling points), an aurora (slow green curtains in the
//   upper sky) and a faint nebula tint. All procedural — no textures.
//   They scale by a "night factor" derived from the sun's energy, so
//   they appear at dusk and vanish at dawn with zero extra wiring.
//
//   CLOUDS. Moving clouds drawn last (so they sit in front of stars):
//   asset-free noise projected onto a flat ceiling, drifting via TIME,
//   lit by the sun through the sky shader's built-in LIGHT0. Coverage
//   is driven by WeatherManager through DayNightCycle.set_cloud_coverage().
//
//   Equirectangular projection: the panorama source images are 2:1
//   rectangles wrapping the world like an unrolled cylinder.
//
// The sun and moon discs are NOT in this shader — they're 3D sphere
// meshes (SunMesh / MoonMesh) positioned by DayNightCycle. Paint the
// panoramas with no sun, moon, or stars (the stars are procedural now).

shader_type sky;

// --- Panorama cross-fade (DayNightCycle writes these every frame) ---
uniform sampler2D texture_from : source_color, filter_linear;
uniform sampler2D texture_to   : source_color, filter_linear;
uniform float blend : hint_range(0.0, 1.0) = 0.0;

// --- Volumetric cloud layer (Phase H) ---
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.4;
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.92;
uniform float cloud_scale = 0.8;
uniform float cloud_scroll_speed = 0.006;
uniform float cloud_softness : hint_range(0.01, 0.5) = 0.20;
uniform vec3 cloud_lit_color : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shadow_color : source_color = vec3(0.46, 0.51, 0.62);
uniform vec3 cloud_night_color : source_color = vec3(0.05, 0.07, 0.13);

// --- Night sky (Phase K) ---
// Stars: density 0 = empty sky, 1 = dense field. Brightness scales the
// star glow. Stars twinkle on their own via TIME.
uniform float star_density : hint_range(0.0, 1.0) = 0.5;
uniform float star_brightness : hint_range(0.0, 3.0) = 1.1;
// Aurora: slow green curtains in the upper-mid sky at night. Strength 0
// disables it entirely.
uniform vec3 aurora_color : source_color = vec3(0.25, 0.95, 0.55);
uniform float aurora_strength : hint_range(0.0, 2.0) = 0.55;
// Nebula: a faint coloured haze across the night sky.
uniform vec3 nebula_color : source_color = vec3(0.34, 0.20, 0.52);
uniform float nebula_strength : hint_range(0.0, 1.0) = 0.22;

// Convert a unit-length view direction into equirectangular UV coords.
//   u = atan2(z, x) / (2*PI) + 0.5   ->  longitude, 0..1 around horizon
//   v = acos(y) / PI                 ->  latitude, 0 zenith -> 1 nadir
vec2 equirect_uv(vec3 dir) {
	float u = atan(dir.z, dir.x) / (2.0 * 3.14159265) + 0.5;
	float v = acos(clamp(dir.y, -1.0, 1.0)) / 3.14159265;
	return vec2(u, v);
}

// --- Asset-free noise (hash-based value noise + fbm) -----------------
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

// --- Night-sky elements (Phase K) ------------------------------------
// Stars: chop the sky UV into a fine grid; a sparse subset of cells
// host a star whose brightness + twinkle speed come from its own hash.
float stars(vec2 suv) {
	vec2 g = suv * vec2(640.0, 320.0);
	vec2 cell = floor(g);
	float h = cloud_hash(cell);
	// Only the brightest tail of the hash distribution becomes a star.
	if (h < 1.0 - star_density * 0.07) {
		return 0.0;
	}
	vec2 f = fract(g) - 0.5;
	float d = length(f);
	float b = cloud_hash(cell + vec2(13.7, 41.3));
	float s = smoothstep(0.34, 0.0, d) * b;
	// Twinkle — each star at its own pace.
	s *= 0.55 + 0.45 * sin(TIME * (0.7 + b * 2.6) + h * 40.0);
	return s;
}

// Aurora: vertical noise "curtains" confined to a band of the upper
// sky, drifting and shimmering.
float aurora(vec2 suv) {
	// suv.y is latitude: 0 = zenith, 0.5 = horizon. Keep the aurora in
	// a band of the upper-mid sky.
	float band = smoothstep(0.08, 0.26, suv.y) * smoothstep(0.60, 0.36, suv.y);
	if (band <= 0.0) {
		return 0.0;
	}
	float curtain = cloud_fbm(vec2(suv.x * 6.0 + TIME * 0.03, suv.y * 2.2));
	curtain = smoothstep(0.46, 0.86, curtain);
	curtain *= 0.7 + 0.3 * sin(TIME * 1.4 + suv.x * 42.0);
	return band * curtain;
}

// Nebula: a soft low-frequency haze.
float nebula(vec2 suv) {
	float n = cloud_fbm(suv * vec2(3.0, 1.6) + vec2(20.0, 7.0));
	return smoothstep(0.52, 0.95, n);
}

void sky() {
	vec2 uv = equirect_uv(EYEDIR);
	float up = EYEDIR.y;

	// Day factor from the sun's energy (DayNightCycle ramps it 0..2.2):
	// 1 in full daylight, 0 once the sun has set. night = the inverse.
	float day = 0.0;
	if (LIGHT0_ENABLED) {
		day = clamp(LIGHT0_ENERGY * 0.5, 0.0, 1.0);
	}
	float night = 1.0 - day;

	// --- Layer 1: panorama cross-fade ---
	vec3 sky_col = mix(
		texture(texture_from, uv).rgb,
		texture(texture_to, uv).rgb,
		blend);

	// --- Layer 2: night sky (stars / aurora / nebula) ---
	// Only above the horizon, only once the sun is low enough.
	if (up > 0.0 && night > 0.01) {
		// Nebula first (faintest, furthest back).
		sky_col += nebula_color * (nebula(uv) * nebula_strength * night);
		// Aurora over the nebula.
		sky_col += aurora_color * (aurora(uv) * aurora_strength * night);
		// Stars on top — fade them out right at the horizon so the
		// equirect UV crunch there doesn't smear them into a line.
		float star_horizon = smoothstep(0.0, 0.14, up);
		sky_col += vec3(stars(uv) * star_brightness * night * star_horizon);
	}

	// --- Layer 3: cloud layer (drawn last so clouds sit in front) ---
	if (up > 0.01) {
		// Project the view ray onto a flat horizontal cloud layer.
		// Dividing the horizontal direction by the vertical component
		// foreshortens clouds toward the horizon like a real ceiling.
		vec2 plane = EYEDIR.xz / up;
		vec2 cuv = plane * cloud_scale
			+ vec2(TIME * cloud_scroll_speed, TIME * cloud_scroll_speed * 0.6);

		float density = cloud_fbm(cuv);

		// Coverage lowers the threshold so more of the noise is cloud.
		float lo = mix(0.95, 0.12, cloud_coverage);
		float cloud = smoothstep(lo, lo + cloud_softness, density);

		// Cheap lighting: sample the noise again offset TOWARD the sun.
		// A sun-facing cloud edge has less cloud sunward, so
		// (here - sunward) is positive there -> lit.
		float lit = 0.6;
		if (LIGHT0_ENABLED) {
			vec2 sunward = -normalize(LIGHT0_DIRECTION.xz + vec2(0.0001));
			float sun_density = cloud_fbm(cuv + sunward * 0.10);
			lit = clamp((density - sun_density) * 3.2 + 0.55, 0.0, 1.0);
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
