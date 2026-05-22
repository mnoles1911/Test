// sky_atmosphere.gdshader
// (Renamed from sky_blend.gdshader 2026-05-21 to force Godot to compile
//  a fresh shader — the old name had a stuck stale compile.)
//
// The world's sky. Layers drawn back-to-front:
//   1. Panorama cross-fade — two equirectangular time-of-day paintings
//      mixed by DayNightCycle (dawn / noon / dusk / night anchors).
//      Darkened toward night so midnight reads near-black.
//   2. Night sky (Phase K) — procedural stars, aurora and nebula that
//      fade in as the sun sets. The star field rotates with the day
//      cycle (DayNightCycle pushes `star_rotation`).
//   3. Cloud layer (Phase H) — procedural moving clouds lit by the sun.
//
// Everything is procedural — NO textures for clouds or stars (asset-free
// noise, no tiling). Cloud shape = a hash-based value-noise FBM field
// thresholded by `cloud_coverage`.
//
// The sun and moon discs are NOT in this shader — they're 3D sphere
// meshes (SunMesh / MoonMesh) positioned by DayNightCycle.

shader_type sky;

// --- Panorama cross-fade (DayNightCycle writes these every frame) ---
uniform sampler2D texture_from : source_color, filter_linear;
uniform sampler2D texture_to   : source_color, filter_linear;
uniform float blend : hint_range(0.0, 1.0) = 0.0;
// How dark the painted sky goes at full night. 1 = unchanged,
// low = near-black midnight so the procedural stars pop and the
// night world is lit by the moon rather than a glowing sky.
uniform float night_sky_darkness : hint_range(0.0, 1.0) = 0.06;
// Day/night driver — DayNightCycle pushes this every tick (0 = full
// day, 1 = full night). The shader does NOT infer it from LIGHT0
// energy, which proved unreliable.
uniform float night_factor : hint_range(0.0, 1.0) = 0.0;
// --- Volumetric cloud layer (Phase H) ---
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.3;
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.95;
uniform float cloud_scale = 0.8;
// Drift speed — weather-driven. WeatherManager pushes a per-state value
// via DayNightCycle.set_cloud_speed(); this default only applies when no
// weather system is running.
uniform float cloud_scroll_speed = 0.03;
uniform float cloud_softness : hint_range(0.01, 0.5) = 0.12;
uniform vec3 cloud_lit_color : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shadow_color : source_color = vec3(0.46, 0.51, 0.62);
uniform vec3 cloud_night_color : source_color = vec3(0.05, 0.07, 0.13);

// --- Night sky (Phase K) ---
uniform float star_density : hint_range(0.0, 1.0) = 0.5;
uniform float star_brightness : hint_range(0.0, 5.0) = 2.8;
// 0 = stars hold steady, 1 = strong blink.
uniform float star_twinkle : hint_range(0.0, 1.0) = 0.8;
// Radians. DayNightCycle pushes the celestial rotation so the star
// field pivots across the sky with the sun/moon.
uniform float star_rotation = 0.0;
// aurora_color / nebula_color are pushed per in-game day by
// DayNightCycle._update_night_palette() so each night has its own hue.
uniform vec3 aurora_color : source_color = vec3(0.25, 0.95, 0.55);
// Toned down from 1.1 — the aurora was overpowering the night sky.
uniform float aurora_strength : hint_range(0.0, 3.0) = 0.5;
uniform vec3 nebula_color : source_color = vec3(0.34, 0.20, 0.52);
uniform float nebula_strength : hint_range(0.0, 1.0) = 0.7;

// Equirectangular UV for the panorama textures.
vec2 equirect_uv(vec3 dir) {
	float u = atan(dir.z, dir.x) / (2.0 * 3.14159265) + 0.5;
	float v = acos(clamp(dir.y, -1.0, 1.0)) / 3.14159265;
	return vec2(u, v);
}

// Rotate a direction around the X axis — used to spin the star field.
vec3 rotate_x(vec3 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(v.x, v.y * c - v.z * s, v.y * s + v.z * c);
}

// --- Asset-free noise --------------------------------------------------
float cloud_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// 3D hash (Dave Hoskins style) — used for the seamless star field.
float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
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

// --- Night-sky elements (Phase K) — all seamless (no equirect seam) ---
// Stars: a 3D grid hashed straight off the view direction, so there is
// no longitude seam. A sparse subset of cells host a twinkling star.
float stars(vec3 dir) {
	vec3 g = dir * 230.0;
	vec3 cell = floor(g);
	float h = hash3(cell);
	if (h < 1.0 - star_density * 0.06) {
		return 0.0;
	}
	vec3 f = fract(g) - 0.5;
	float d = length(f);
	float b = hash3(cell + vec3(19.3, 7.1, 41.7));
	float s = smoothstep(0.45, 0.0, d) * (0.45 + 0.55 * b);
	// Twinkle — fast, deep. star_twinkle scales how far it dips.
	float tw = 0.5 + 0.5 * sin(TIME * (2.5 + b * 6.0) + h * 50.0);
	s *= 1.0 - star_twinkle * (1.0 - tw);
	return s;
}

// Aurora: vertical noise "curtains" in an upper-mid sky band. Sampled
// on a cos/sin ring of the longitude so it wraps with no hard seam.
float aurora(vec3 dir) {
	float lat = acos(clamp(dir.y, -1.0, 1.0)) / 3.14159265;  // 0 zenith
	float band = smoothstep(0.06, 0.24, lat) * smoothstep(0.60, 0.34, lat);
	if (band <= 0.0) {
		return 0.0;
	}
	float lon = atan(dir.z, dir.x);
	vec2 ring = vec2(cos(lon), sin(lon)) * 3.2;
	float curtain = cloud_fbm(ring + vec2(TIME * 0.05, lat * 3.0));
	curtain = smoothstep(0.42, 0.9, curtain);
	// sin(lon * 6) is continuous across the +-PI wrap (6 full periods).
	curtain *= 0.6 + 0.4 * sin(TIME * 1.6 + lon * 6.0);
	return band * curtain;
}

// Nebula: a soft low-frequency haze, also sampled on the seamless ring.
float nebula(vec3 dir) {
	float lat = acos(clamp(dir.y, -1.0, 1.0)) / 3.14159265;
	float lon = atan(dir.z, dir.x);
	// Lower ring scale => larger, broader nebula clouds. The smoothstep
	// floor sits well below the fbm average so the haze is actually
	// visible across the sky, not just catching the rare noise peaks.
	vec2 ring = vec2(cos(lon), sin(lon)) * 1.5;
	float n = cloud_fbm(ring + vec2(7.0, lat * 2.0));
	return smoothstep(0.34, 0.78, n);
}

void sky() {
	vec2 uv = equirect_uv(EYEDIR);
	float up = EYEDIR.y;

	// Day / night come straight from DayNightCycle's explicit push
	// (night_factor uniform) — 0 = full day, 1 = full night.
	float night = night_factor;
	float day = 1.0 - night_factor;

	// --- Layer 1: panorama, darkened toward night ---
	vec3 sky_col = mix(
		texture(texture_from, uv).rgb,
		texture(texture_to, uv).rgb,
		blend);
	sky_col *= mix(1.0, night_sky_darkness, night);

	// --- Layer 2: night sky (stars / aurora / nebula) ---
	if (up > 0.0 && night > 0.01) {
		// Nebula first (faintest), aurora over it.
		sky_col += nebula_color * (nebula(EYEDIR) * nebula_strength * night);
		sky_col += aurora_color * (aurora(EYEDIR) * aurora_strength * night);
		// Stars on top. Rotate the view direction by the celestial
		// rotation so the whole field pivots with the day cycle. Fade
		// out right at the horizon so they don't sit on the ground.
		vec3 star_dir = rotate_x(EYEDIR, star_rotation);
		float star_horizon = smoothstep(0.0, 0.12, up);
		sky_col += vec3(stars(star_dir) * star_brightness * night * star_horizon);
	}

	// --- Layer 3: cloud layer (drawn last so clouds sit in front) ---
	if (up > 0.01) {
		// Project the view ray onto a flat horizontal cloud layer.
		vec2 plane = EYEDIR.xz / up;
		// Drift, with a gentle gust — a bounded sine wobble on the phase
		// makes the clouds surge and ease instead of sliding at a
		// dead-flat rate (natural variance on top of the weather speed).
		float gust = sin(TIME * 0.07) * 0.08 + sin(TIME * 0.17 + 2.0) * 0.04;
		float drift = TIME * cloud_scroll_speed + gust;
		vec2 cuv = plane * cloud_scale + vec2(drift, drift * 0.6);

		float density = cloud_fbm(cuv);

		// Coverage -> threshold. At coverage 0 the threshold (1.02) sits
		// ABOVE the noise's max (~0.97) so the sky is genuinely clear;
		// at coverage 1 it drops to 0.05 for full overcast.
		float lo = mix(1.02, 0.05, cloud_coverage);
		float cloud = smoothstep(lo, lo + cloud_softness, density);

		// Cheap lighting: sample the noise again offset toward the sun.
		float lit = 0.6;
		if (LIGHT0_ENABLED) {
			vec2 sunward = -normalize(LIGHT0_DIRECTION.xz + vec2(0.0001));
			float sun_density = cloud_fbm(cuv + sunward * 0.10);
			lit = clamp((density - sun_density) * 3.2 + 0.55, 0.0, 1.0);
		}

		vec3 day_cloud = mix(cloud_shadow_color, cloud_lit_color, lit);
		if (LIGHT0_ENABLED) {
			day_cloud *= mix(vec3(1.0), LIGHT0_COLOR, 0.5 * lit);
		}
		vec3 cloud_rgb = mix(cloud_night_color, day_cloud, day);

		float horizon_fade = smoothstep(0.02, 0.32, up);
		float alpha = cloud * cloud_opacity * horizon_fade;
		sky_col = mix(sky_col, cloud_rgb, alpha);
	}

	COLOR = sky_col;
}
