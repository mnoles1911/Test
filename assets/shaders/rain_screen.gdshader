// rain_screen.gdshader — full-screen rain streaks (canvas_item layer).
//
// Phase A of the Weather rework (design/WEATHER_REWORK_2026-05.md).
//
// Replaces the GPUParticles3D billboard streak rig which:
//   - vanished when the camera aimed away from the player-following emit box
//   - read as on/off rather than a build-up even with per-particle alpha
//     modulation (designer report 2026-05-27)
//
// Approach:
//   Two procedural streak layers at different parallax depths. Both layers
//   are pure UV-hash noise (no texture asset) — closer layer has bigger,
//   sparser, faster streaks; farther layer has smaller, denser, slower ones.
//   `rain_density` (0..1) drives streak length, alpha, AND the count gate.
//   `rain_slant` (in screen-space radians, derived from wind) tilts the
//   streak direction so they lean with the wind.
//   `parallax_offset` (Vector2, derived from camera yaw + pitch by the
//   driving script) shifts the layers oppositely so the rain feels
//   3D — looking down moves the streaks toward the bottom of the screen.
//
// Renders ADDITIVELY on top of the existing RainOverlay TintRect (which
// keeps the blue-grey mood colour). Output is just the streak luminance —
// no opaque coverage.
//
// Reference: design/WEATHER_REWORK_2026-05.md → Phase A

shader_type canvas_item;
render_mode blend_mix;  // mix-blend so streak alpha actually composites; tint sits underneath

uniform float rain_density : hint_range(0.0, 1.0) = 0.0;
uniform float rain_slant : hint_range(-1.5, 1.5) = 0.10;  // radians; positive = lean right
uniform vec2 parallax_offset = vec2(0.0, 0.0);   // shifts both layers; from camera yaw/pitch
uniform vec3 streak_color : source_color = vec3(0.85, 0.92, 1.0);
uniform float streak_alpha_max : hint_range(0.0, 1.0) = 0.65;
uniform float aspect = 1.778;  // viewport width / height; pushed each frame
// 0..1 driven from UnderwaterFilter — fades the rain out smoothly when the
// player submerges so we don't see streaks AND water at the same time.
uniform float surface_visibility : hint_range(0.0, 1.0) = 1.0;

// One streak layer's contribution at the given screen UV.
//   tile_scale  — how many streak "columns" the screen is divided into.
//                 Higher = more, narrower streaks.
//   speed       — vertical scroll rate (UV units per second).
//   length      — vertical length of a single streak in tile-UV units.
//   spawn_gate  — probability a column has an active streak (modulated by
//                 rain_density so layers fade IN/OUT smoothly rather than
//                 turning on at full count).
//   tilt        — radians; rotates the streak direction within its column.
float rain_layer(vec2 uv, float tile_scale, float speed, float length, float spawn_gate, float tilt) {
	// Aspect correction so streaks are vertical regardless of viewport width.
	vec2 cuv = uv;
	cuv.x *= aspect;
	// Apply tilt by rotating the sampling coordinates around an arbitrary
	// pivot — for slant the pivot doesn't matter, only the rotation.
	float ct = cos(tilt);
	float st = sin(tilt);
	cuv = mat2(vec2(ct, -st), vec2(st, ct)) * cuv;

	// Divide screen into columns.
	vec2 g = cuv * tile_scale;
	float col = floor(g.x);
	float row_in_col = g.y;  // continuous vertical coord within the column

	// Per-column hash decides whether this column hosts a streak this frame
	// and offsets its phase so adjacent columns aren't in lock-step.
	float column_hash = fract(sin(col * 47.7531) * 4321.123);
	if (column_hash > spawn_gate) {
		return 0.0;
	}

	// Streak phase — column's own offset plus time scroll.
	float phase_offset = fract(sin(col * 19.7) * 8123.9);
	float scroll_y = row_in_col + TIME * speed + phase_offset * 10.0;
	// Fractional position within ONE streak cycle. cycle length = length * 4
	// so streaks have noticeable gaps between them in the column.
	float cycle_pos = fract(scroll_y / (length * 4.0)) * (length * 4.0);

	// Anti-aliased streak shape: bright where cycle_pos is inside [0, length],
	// fading at both ends so we don't see hard rectangles.
	float head_fade = smoothstep(0.0, length * 0.15, cycle_pos);
	float tail_fade = 1.0 - smoothstep(length * 0.85, length, cycle_pos);
	float in_streak = head_fade * tail_fade;

	// Horizontal anti-alias inside the column — a narrow vertical line
	// rather than the full column width.
	float col_frac = fract(g.x);
	float col_dist = abs(col_frac - 0.5) * 2.0;  // 0 at centre, 1 at edges
	float col_alpha = 1.0 - smoothstep(0.18, 0.42, col_dist);

	// Per-streak brightness variance — some streaks are dimmer.
	float brightness_jitter = 0.55 + 0.45 * fract(sin(col * 91.3 + floor(scroll_y / (length * 4.0)) * 5.7) * 23.1);

	return in_streak * col_alpha * brightness_jitter;
}


void fragment() {
	// Early-out at zero density / underwater — costs nothing during CLEAR
	// / OVERCAST / submerged. GDSL forbids `return` in fragment(), so we
	// gate the whole computation behind the visibility check instead.
	vec4 out_color = vec4(0.0);
	if (rain_density >= 0.001 && surface_visibility >= 0.001) {
		vec2 uv = SCREEN_UV + parallax_offset;
		// Near layer — chunkier, fewer streaks, fast scroll.
		float near_layer = rain_layer(uv, 80.0,  1.40, 0.18, rain_density * 0.55, rain_slant);
		// Far layer — finer, more streaks, slower scroll (parallax depth cue).
		float far_layer  = rain_layer(uv + vec2(0.13, 0.27),
		                              160.0, 0.85, 0.10, rain_density * 0.85, rain_slant * 0.8);
		// Combine. Far layer scaled down so it reads as "behind" the near.
		float streaks = max(near_layer, far_layer * 0.60);
		// Density also gates the overall alpha so the FIRST streaks come
		// in faint, ramping to full opacity at rain_density = 1.
		float a = streaks * streak_alpha_max * rain_density * surface_visibility;
		out_color = vec4(streak_color, a);
	}
	COLOR = out_color;
}
