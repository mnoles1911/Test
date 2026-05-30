// lens_flare.gdshader — full-screen canvas_item lens flare.
//
// Phase K (2026-05-27). Draws a soft radial halo around the sun's
// screen-space position, plus 3 anamorphic ghost elements at mirrored
// positions along the sun→screen-center axis (the classic "flare
// string" effect that real camera lenses show when the sun is in
// frame). Driven entirely from a CPU-pushed sun_screen_uv uniform —
// no scene-graph lookups inside the shader.
//
// When the sun is BEHIND the camera or BELOW the horizon, the script
// pins sun_screen_uv to a sentinel offscreen value (e.g. (-1, -1)) so
// the halo contribution computes to zero by distance — no manual
// hide/show needed in this shader.

shader_type canvas_item;
render_mode blend_add;  // additive — halo lifts the underlying scene, never darkens

// Driven each frame from scripts/LensFlare.gd. (-1, -1) = sun offscreen.
uniform vec2 sun_screen_uv = vec2(-1.0, -1.0);
// 0..1 visibility from the script's occlusion fade (sun behind horizon
// or behind a near object → fade off). Lets the script choose to fade
// the whole effect smoothly rather than the shader popping it on/off.
uniform float sun_visibility : hint_range(0.0, 1.0) = 1.0;

uniform vec3 flare_color : source_color = vec3(1.00, 0.92, 0.72);
uniform float halo_radius : hint_range(0.02, 0.6) = 0.28;       // v2 0.18 -> 0.28 (designer "barely visible" report 2026-05-27)
uniform float halo_strength : hint_range(0.0, 6.0) = 3.0;        // v2 1.6 -> 3.0 (designer "barely visible" report 2026-05-27)
uniform float ghost_strength : hint_range(0.0, 2.0) = 0.65;       // v2 0.45 -> 0.65 (designer "barely visible" report 2026-05-27)
// Aspect ratio (width / height) so circular falloff stays circular on
// non-square viewports. Script pushes this each frame.
uniform float viewport_aspect : hint_range(0.5, 4.0) = 1.778;


// Single radial gaussian-ish glow at a UV position. Aspect-corrected
// so it stays circular on widescreen.
float radial_glow(vec2 uv, vec2 center, float radius) {
	vec2 d = uv - center;
	d.x *= viewport_aspect;  // correct for non-square pixels
	float r = length(d);
	// Soft falloff: 1.0 at center → 0 at radius. Pow-2 keeps the centre
	// bright enough to actually read against an overcast sky.
	float t = clamp(1.0 - r / max(radius, 0.001), 0.0, 1.0);
	return t * t;
}


void fragment() {
	// Early-out: sun offscreen sentinel.
	if (sun_screen_uv.x < 0.0 || sun_screen_uv.y < 0.0
			|| sun_screen_uv.x > 1.0 || sun_screen_uv.y > 1.0
			|| sun_visibility < 0.001) {
		COLOR = vec4(0.0);
		return;
	}

	vec3 accum = vec3(0.0);

	// Main halo at the sun's position.
	float halo = radial_glow(SCREEN_UV, sun_screen_uv, halo_radius) * halo_strength;
	accum += flare_color * halo;

	// Anamorphic ghost string — 3 elements along the sun→center axis at
	// fixed parametric positions. The line from the sun through screen
	// center is t=0 at sun, t=1 at the screen center, t=2 at the mirror
	// point opposite the sun. Ghosts sit at t = 0.5, 1.0, 1.5 with
	// progressively smaller radii — gives the eye 3 secondary glows
	// that read as a real lens flare without being noisy.
	vec2 center = vec2(0.5, 0.5);
	vec2 axis = center - sun_screen_uv;
	for (int i = 0; i < 3; i++) {
		float t = 0.5 + float(i) * 0.5;
		vec2 ghost_pos = sun_screen_uv + axis * t;
		// Tint each ghost a slightly different hue (warm → magenta) so the
		// flare string reads as multiple lens elements, not three of the
		// same glow.
		vec3 tint = flare_color;
		if (i == 1) tint = vec3(1.0, 0.65, 0.55);     // warm pink
		else if (i == 2) tint = vec3(0.85, 0.65, 1.0);  // cool lilac
		float r = halo_radius * (0.50 - float(i) * 0.10);
		float g = radial_glow(SCREEN_UV, ghost_pos, r) * ghost_strength;
		accum += tint * g;
	}

	accum *= sun_visibility;
	COLOR = vec4(accum, 1.0);
}
