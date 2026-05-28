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
// aurora_color is pushed per in-game day by DayNightCycle on a smooth
// 7-day colour cycle. nebula_color is a constant (not pushed).
uniform vec3 aurora_color : source_color = vec3(0.25, 0.95, 0.55);
uniform float aurora_strength : hint_range(0.0, 3.0) = 0.3;
uniform vec3 nebula_color : source_color = vec3(0.46, 0.32, 0.72);
uniform float nebula_strength : hint_range(0.0, 2.0) = 1.0;
// Azimuth (radians) the nebula anchor is rotated around the sky.
// DayNightCycle advances this slowly so the nebula drifts over weeks.
uniform float nebula_rotation = 0.0;

// === Rainbow-after-rain (Phase K bundle, 2026-05-27) =================
// `rainbow_factor` is a GLOBAL shader parameter declared in
// project.godot [shader_globals]. WeatherManager pushes 0..1 to it
// based on a state machine that triggers on rain → clear transitions:
// ramps 0→1 over 30s, holds 60s, ramps 1→0 over 60s. Toggle-respecting
// (forced 0 when GraphicsManager.is_effect_enabled("rainbow") = false).
//
// The rainbow forms a circle of radius 42° around the antisolar point
// (-LIGHT0_DIRECTION). Drawn only on the sky-facing side of the
// rainbow's angular band; thin (~2° wide); colour cycles red (outside,
// 42°) → orange → yellow → green → blue → violet (inside, 40°).
// Multiplied by rainbow_factor and the day mix so it fades into
// nothing at night when there'd be no sunlight to refract.
global uniform float rainbow_factor;
uniform float rainbow_band_strength : hint_range(0.0, 2.0) = 0.85;

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

// Rotate a direction around the Y (vertical) axis — drifts the nebula
// around the sky's azimuth without changing its elevation.
vec3 rotate_y(vec3 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c);
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
	// A narrow ribbon in the upper-mid sky (~29-50 deg elevation). Was
	// lat 0.06..0.60 — nearly zenith to below the horizon — which made
	// the aurora swallow the whole sky and bury the nebula behind it.
	float band = smoothstep(0.22, 0.26, lat) * smoothstep(0.34, 0.30, lat);
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

// Nebula: a concentrated billowy cloud high in the sky — NOT a sky-
// spanning curtain. The aurora samples noise on a longitude ring with a
// lat offset, which produces vertical draped streaks; doing the same for
// the nebula made the two look identical. This instead builds a LOCALISED
// blob: a radial glow around a fixed anchor direction, textured by FBM
// sampled in the anchor's own tangent plane so the structure is round,
// isotropic billows rather than streaks. Static (no TIME) — a nebula is
// a deep-sky object, not an atmospheric effect.
float nebula(vec3 dir) {
	// Anchor high in the sky, drifted around the azimuth by nebula_rotation.
	vec3 center = rotate_y(normalize(vec3(0.25, 0.90, 0.35)), nebula_rotation);
	float prox = dot(dir, center);
	// Radial falloff: bright near the anchor, gone well before the
	// horizon. Squared to tighten it into a concentrated core.
	float glow = smoothstep(0.62, 1.0, prox);
	glow *= glow;
	if (glow <= 0.0) {
		return 0.0;
	}
	// Local tangent frame at the anchor, so the FBM gives round billows
	// rather than the aurora's vertical curtains.
	vec3 t1 = normalize(cross(center, vec3(0.0, 1.0, 0.0)));
	vec3 t2 = cross(center, t1);
	vec2 local = vec2(dot(dir, t1), dot(dir, t2)) * 3.2;
	float clouds = smoothstep(0.30, 0.82, cloud_fbm(local + vec2(11.0, 4.0)));
	// Radial glow shapes the blob; the FBM carves billowy structure into
	// it. The 0.4 floor keeps the core bright even in the noise gaps.
	return glow * (0.4 + 0.6 * clouds);
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

	// --- Layer 2.5: rainbow-after-rain (Phase K bundle 2026-05-27) ---
	// Forms an arc centred on the antisolar point at ~42° radius. Visible
	// only when (a) rainbow_factor > 0 (WeatherManager state machine
	// active), (b) the sun is enabled (no sun = no light to refract),
	// (c) it's day (rainbows don't form at night). Multiplied by `day`
	// so the band fades automatically with the day cycle even mid-arc.
	if (rainbow_factor > 0.001 && LIGHT0_ENABLED && day > 0.05 && up > -0.10) {
		vec3 antisolar = -LIGHT0_DIRECTION;
		float cos_theta = clamp(dot(EYEDIR, antisolar), -1.0, 1.0);
		float theta_deg = degrees(acos(cos_theta));
		// 40° inner edge, 42° outer edge — primary rainbow.
		float t_band = (theta_deg - 40.0) / 2.0;  // 0 at inner, 1 at outer
		if (t_band >= 0.0 && t_band <= 1.0) {
			// Map t_band 0..1 to violet→red. Standard rainbow spectrum
			// reversed because the OUTER edge is red, INNER is violet.
			// 6 anchor colours; lerp between adjacent pair.
			vec3 spectrum[6] = {
				vec3(0.58, 0.00, 0.83),  // violet (inner, t=0)
				vec3(0.00, 0.00, 1.00),  // blue
				vec3(0.00, 1.00, 0.00),  // green
				vec3(1.00, 1.00, 0.00),  // yellow
				vec3(1.00, 0.50, 0.00),  // orange
				vec3(1.00, 0.00, 0.00)   // red (outer, t=1)
			};
			float seg_f = t_band * 5.0;
			int seg = int(floor(seg_f));
			if (seg > 4) seg = 4;
			float seg_t = seg_f - float(seg);
			vec3 rainbow_col = mix(spectrum[seg], spectrum[seg + 1], seg_t);
			// Soft AA at band edges so the rainbow doesn't have a hard
			// stripe boundary.
			float edge_aa = min(t_band, 1.0 - t_band) * 4.0;
			float band_alpha = clamp(edge_aa, 0.0, 1.0);
			// Final additive contribution. day folds out the colour as
			// the sky darkens; rainbow_factor is the WeatherManager ramp.
			sky_col += rainbow_col * (band_alpha * rainbow_band_strength
									* rainbow_factor * day);
		}
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
