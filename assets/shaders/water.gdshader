// water.gdshader — v8 (2026-05-16). PROPER REWRITE.
//
// WHY THIS REWRITE (plain English):
//   v6/v7 was an `unshaded` shader that hand-composited "the scene
//   behind the water" and lerped it toward a tint by depth. It had NO
//   surface of its own — no sky reflection, no sun glint, no base
//   sheen. Tuned opaque it was a flat slab; tuned clear it was
//   invisible glass (you saw straight through to the dry lakebed).
//   The horizon plane was secretly doing all the "looks like water"
//   work. Proven by the 2026-05-16 experiment: 250 chunked meshes
//   present, horizon plane removed → zero visible water.
//
// WHAT v8 DOES DIFFERENTLY — two layers that always coexist:
//
//   1. A SURFACE that always reads as water, at any depth or angle:
//        • base water colour,
//        • Fresnel sheen toward the sky colour (grazing angles go
//          bright/reflective — the #1 cue your eye uses for "water"),
//        • real lit sun specular (this shader is NOT unshaded).
//
//   2. DEPTH-DRIVEN TRANSPARENCY using the real depth texture to
//      measure how much water the view ray passes through:
//        • shallow  → low ALPHA → you see the bottom THROUGH a
//          visible, sheened water film,
//        • deep      → ALPHA rises → opaque blue→navy,
//        • grazing   → Fresnel raises ALPHA → reflective sheet.
//      Godot composites the bottom for us via normal alpha blending
//      (no manual screen_texture sampling — that path was fragile).
//
// UNIFICATION INVARIANT: the shared-look uniforms
//   deep_water_color / water_tint_color / sky_reflection_color /
//   fresnel_power / fresnel_strength / metallic_amount /
//   roughness_amount
// MUST stay identical to water_horizon_material.tres. The horizon
// shader runs this same surface with depth forced to "deep", so the
// near water and the distant horizon plane match seamlessly.
//
// debug_mode: 0 normal · 1 depth_t (white=deep) · 2 fresnel ·
//             3 thickness/​fade as grey. Set in the .tres, stop/run.
//
// Reference: design/WATER_SHADER_V2_PLAN.md.

shader_type spatial;

// NOT unshaded (that was the core v6 mistake): we want the lit
// pipeline so the sun produces a specular glint and the surface reads
// as water. cull_disabled so a submerged player still sees the
// underside as a ceiling. blend_mix + depth_draw_opaque: standard
// transparent-water setup; Godot composites whatever is behind.
// depth_draw_never (was depth_draw_opaque): the depth-fade samples
// DEPTH_TEXTURE to find the OPAQUE terrain behind the water. With
// depth_draw_opaque, distant (opaque) water wrote itself into that
// depth buffer, so each water chunk read the NEIGHBOUR water chunk as
// "the surface behind me" → thickness≈0 at every chunk boundary → hard
// seam lines across distant water. depth_draw_never = water never
// pollutes the depth texture it reads → the fade always measures down
// to real terrain, consistently across all chunks → seamless,
// near-infinite water (standard Godot depth-fade-water setup).
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx, diffuse_burley;


// ============================================================
// DEPTH TEXTURE (read-only — for the water-column thickness)
// ============================================================
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;


// ============================================================
// SHARED LOOK PARAMS — keep identical to water_horizon_material.tres
// ============================================================
// Colour of shallow / mid water (the tint you see the bottom through).
uniform vec3 water_tint_color : source_color = vec3(0.10, 0.30, 0.42);
// Colour deep water saturates to.
uniform vec3 deep_water_color : source_color = vec3(0.02, 0.06, 0.12);
// Approximate sky colour the surface reflects at grazing angles. This
// is what makes clear water still obviously read as water. Tune toward
// your sky/horizon tint.
uniform vec3 sky_reflection_color : source_color = vec3(0.55, 0.70, 0.85);
// Fresnel curve: higher power = sheen only at the steepest grazing.
uniform float fresnel_power : hint_range(0.5, 16.0) = 3.0;
uniform float fresnel_strength : hint_range(0.0, 1.0) = 1.0;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.08;


// ============================================================
// DEPTH-FADE (near-water only; horizon plane forces this to "deep")
// ============================================================
// Metres of water the view ray must pass through before the surface
// is fully opaque. Bigger = clearer water (see deeper). This is the
// headline "how clear is the water" dial.
//   3.0  → murky pond     8.0 → lake      15.0 → clear ocean
uniform float depth_fade_distance : hint_range(0.5, 40.0) = 7.0;
// Minimum surface alpha even over a paper-thin puddle, so there is
// always a faint water film + the Fresnel/specular sheen on top.
uniform float shallow_alpha : hint_range(0.0, 1.0) = 0.10;


// ============================================================
// LEGACY UNIFORMS (declared, unused — kept so
// WaterFlowManager.set_global_wind(...) + existing .tres don't error)
// ============================================================
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float wind_strength : hint_range(0.0, 5.0) = 0.5;


// ============================================================
// DEBUG
// ============================================================
uniform int debug_mode : hint_range(0, 3) = 0;


void vertex() {
	// Flat voxel water — no vertex displacement (matches the blocky
	// art direction; waves were intentionally dropped earlier).
}


void fragment() {
	// === 1. WATER-COLUMN THICKNESS (how much water the ray crosses) =
	// Linear view-space depth of the opaque thing behind this pixel
	// (lakebed / seafloor / terrain), reconstructed from the depth
	// texture. Standard Godot 4 / Vulkan reconstruction.
	float raw_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float scene_dist = -view.z;          // distance camera → bottom
	float frag_dist  = -VERTEX.z;        // distance camera → this water pixel
	// How far the ray travels through water before hitting the bottom.
	float thickness = max(scene_dist - frag_dist, 0.0);
	// Exponential (Beer-Lambert-style) falloff — NOT a linear clamp.
	// A linear clamp produced the "clear, then suddenly fully dark past
	// a hard line" cutoff. exp() ramps smoothly and only *approaches*
	// 1.0, so there is no threshold edge: shallow → clear, gradually
	// → opaque, asymptotically deep. depth_fade_distance is now the
	// 1/e distance (~63% opaque), so larger = clearer/longer gradient.
	float depth_t = 1.0 - exp(-thickness / max(depth_fade_distance, 0.01));

	// === 2. FRESNEL (angle-accurate, uses the real surface normal) ==
	// At steep angles (looking straight down) → ~0 (clear, see bottom).
	// At grazing angles (looking across) → ~1 (bright reflective sheet).
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	float fresnel = pow(1.0 - ndv, fresnel_power) * fresnel_strength;

	// === 3. SURFACE COLOUR ==========================================
	// Body colour: shallow tint → deep navy by how deep the water is.
	vec3 body = mix(water_tint_color, deep_water_color, depth_t);
	// Grazing angles reflect the sky → the surface always reads as
	// water even when it's crystal clear over a shallow bottom.
	vec3 surface = mix(body, sky_reflection_color, fresnel);

	// === 4. TRANSPARENCY ============================================
	// DEPTH drives transparency — NOT Fresnel. A first-person player
	// walking up to a pond views it at a near-grazing angle almost all
	// the time; if Fresnel forced opacity (v8's bug) you could never
	// see into water except by looking straight down. So: shallow water
	// → low alpha (see the bottom) regardless of view angle; deep water
	// → opaque. The Fresnel sky-sheen still sells "this is water" via
	// the COLOUR (step 3) + the lit sun specular (step 5).
	float alpha = max(depth_t, shallow_alpha);

	// === 5. OUTPUT ==================================================
	if (debug_mode == 1) {
		ALBEDO = vec3(depth_t); ALPHA = 1.0;
	} else if (debug_mode == 2) {
		ALBEDO = vec3(fresnel); ALPHA = 1.0;
	} else if (debug_mode == 3) {
		ALBEDO = vec3(clamp(thickness / max(depth_fade_distance, 0.01), 0.0, 1.0));
		ALPHA = 1.0;
	} else {
		ALBEDO = surface;
		ALPHA = clamp(alpha, 0.0, 1.0);
	}

	METALLIC = metallic_amount;
	ROUGHNESS = roughness_amount;
	// v8 used SPECULAR 0.5 + roughness 0.08 → a hard mirror glint on
	// every flat cube face = ugly blocky lighting on voxel water.
	// Soften it: the depth-fade + Fresnel sky tint already carry the
	// "this is water" read, so keep specular subtle. Tune via the .tres
	// (roughness_amount) + this constant.
	SPECULAR = 0.15;
}
