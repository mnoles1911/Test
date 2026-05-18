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
// LOD-seam dark-grid suppression is distance-gated (2026-05-18). It does
// NOTHING nearer than seam_suppress_near_m — so the shallow water you
// walk up to and look straight down into stays fully readable — and
// ramps to full strength by seam_suppress_far_m, where the distant dark
// grid actually lived. Raise _near if near water still fades out; set
// _near to 0 to restore the old always-on (over-suppressing) behaviour.
uniform float seam_suppress_near_m : hint_range(0.0, 200.0) = 24.0;
uniform float seam_suppress_far_m : hint_range(0.0, 400.0) = 64.0;


// ============================================================
// LEGACY UNIFORMS (declared, unused — kept so
// WaterFlowManager.set_global_wind(...) + existing .tres don't error)
// ============================================================
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float wind_strength : hint_range(0.0, 5.0) = 0.5;


// ============================================================
// "LOOK ALIVE" (#15) — WIND-DRIVEN FOAM / WHITECAPS
// ============================================================
// Physically motivated, NOT a fake sun glow: the surface is whipped up
// by WIND. A cheap procedural dual-octave field scrolls along the live
// global wind (wind_dir / wind_strength, pushed by WaterFlowManager
// from WeatherManager every frame). Its crests are thresholded into
// scattered white FOAM caps; coverage + brightness scale with
// wind_strength, so CALM water is glassy and dark (zero foam) and a
// storm visibly chops it white. Fragment-only (no geometry — blocky
// art direction; no texture). Scaled by up-facing-ness so it can NOT
// touch the #222 LOD-seam side slivers, and skipped under any
// debug_mode so F6 diagnostics stay exact.
//   surface_motion_strength = foam master amount (0 disables)
//   surface_motion_speed    = drift rate
//   surface_ripple_scale    = cap size (higher = smaller, choppier)
uniform float surface_motion_strength : hint_range(0.0, 1.0) = 0.7;
uniform float surface_motion_speed : hint_range(0.0, 3.0) = 0.6;
uniform float surface_ripple_scale : hint_range(0.05, 4.0) = 0.7;
// wind_strength at which foam is fully developed (storm). Below this it
// ramps in; at/above, max coverage. Designer-tunable for weather feel.
uniform float foam_wind_ref : hint_range(0.2, 5.0) = 2.0;
uniform vec3 foam_color : source_color = vec3(0.86, 0.92, 0.96);


// ============================================================
// DEBUG
// ============================================================
// 4 = surface facing (white=up-facing water TOP, black=vertical
//     riser/side sliver) — isolates whether the distant LOD-seam dark
//     grid sits on side slivers (shader-fixable) or stepped tops.
uniform int debug_mode : hint_range(0, 4) = 0;


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
	// === 2-alive. WIND-DRIVEN FOAM (#15). A dual-octave field scrolls
	// along the global wind; its crests become scattered white caps
	// whose coverage AND brightness scale with wind_strength — so calm
	// water has NO foam (glassy/dark) and a storm chops it white. The
	// foam mask is consumed in §3 (mixed toward foam_color). A small
	// normal nudge rides along so lit specular shifts too. Gated to
	// debug_mode==0 (F6 exact) and up-face-scaled (never touches the
	// #222 LOD-seam slivers). foam_wind_ref = wind for full foam.
	float foam = 0.0;
	if (debug_mode == 0 && surface_motion_strength > 0.001) {
		vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec2 base = wpos.xz * surface_ripple_scale;
		vec2 scroll = normalize(wind_dir + vec2(0.001)) * (TIME * surface_motion_speed * (0.6 + wind_strength));
		// Coarse swell + finer chop (the second octave keeps caps small
		// and scattered instead of one broad bright blob — the artifact).
		float w1 = sin(base.x + scroll.x) + cos(base.y * 0.85 - scroll.y);
		float w2 = sin((base.x + base.y) * 2.3 - scroll.x * 1.7)
		         + cos((base.x - base.y) * 1.9 + scroll.y * 1.3);
		float crest = clamp((w1 + w2) * 0.25 + 0.5, 0.0, 1.0);
		float upness = clamp(n.y, 0.0, 1.0);
		// Wind 0..1. No wind → windn 0 → foam 0 (no floor: calm = glass).
		float windn = clamp(wind_strength / max(foam_wind_ref, 0.01), 0.0, 1.0);
		// Higher wind lowers the crest cutoff → more of the surface caps.
		float cut = mix(0.86, 0.42, windn);
		foam = smoothstep(cut, cut + 0.10, crest) * windn
		     * surface_motion_strength * upness;
		// Subtle normal break-up so the lit highlight also moves.
		n = normalize(n + vec3(w1, 0.0, w2) * (0.10 * windn * upness));
	}
	vec3 v = normalize(VIEW);
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	float fresnel = pow(1.0 - ndv, fresnel_power) * fresnel_strength;

	// === 2b. LOD-SEAM SIDE-FACE SUPPRESSION (dark-grid fix) =========
	// Root-caused 2026-05-17 (WaterDiag F5 + debug_mode 4; see
	// design/PROFILER_AND_DIAGNOSTICS.md). The distant dark grid is NOT
	// stepped voxel data — F5 WaterInspect proved the water-top is
	// coplanar (Δ+0, top=72) at LOD0 everywhere. It's Zylann's blocky
	// mesher DOWNSAMPLING the transparent water block at coarse LOD,
	// which exposes near-vertical water SIDE faces (n.y≈0, lit up by
	// debug_mode 4) at every LOD seam. Those edge-on slivers read a
	// huge through-water `thickness`, so the depth-fade saturates them
	// to deep_water_color → a black lattice. The water the player
	// actually reads is the TOP surface (n.y≈1). So weight the
	// depth-fade by how up-facing the fragment is: tops keep the full
	// depth gradient; vertical seam slivers collapse to shallow tint +
	// shallow_alpha (a faint film, not a black wall — the Minecraft
	// look). Flat voxel water has no legitimate vertical faces (waves
	// were dropped), so nothing real is lost. Axis-aligned cube faces
	// give n.y of exactly 1 or 0; the smoothstep band only softens
	// Zylann's angled LOD-transition normals. debug_mode 1/3/4 below
	// deliberately keep RAW depth_t/thickness/n.y so the diagnostics
	// still show ground truth after this fix.
	// 2026-05-18 READABILITY FIX: the suppression described above is
	// correct for DISTANT water (LOD seams) but it was distance-blind,
	// so it ALSO faded out the near shallow water you walk up to and
	// look down into — the #1 "I can't see the water" complaint
	// (confirmed: debug_mode 4 changes as you tilt to look straight
	// down at a shallow pond). Gate it by camera distance: near water
	// has no LOD downsampling, so no seam slivers exist there — keep
	// full opacity on every face. The side-face suppression ramps in
	// only past seam_suppress_near_m, reaching full strength by
	// seam_suppress_far_m where the dark grid actually was. frag_dist
	// (camera→this water pixel, metres) was computed in step 1.
	float up_face_raw = smoothstep(0.30, 0.72, n.y);
	float seam_region = smoothstep(seam_suppress_near_m, seam_suppress_far_m, frag_dist);
	float up_face = mix(1.0, up_face_raw, seam_region);
	float depth_t_eff = depth_t * up_face;

	// === 3. SURFACE COLOUR ==========================================
	// Body colour: shallow tint → deep navy by how deep the water is
	// (effective depth — side slivers stay shallow tint, not navy).
	vec3 body = mix(water_tint_color, deep_water_color, depth_t_eff);
	// Grazing angles reflect the sky → the surface always reads as
	// water even when it's crystal clear over a shallow bottom.
	vec3 surface = mix(body, sky_reflection_color, fresnel);
	// #15 wind foam: lerp toward white foam where the wind whipped a cap
	// up (foam=0 in calm water → unchanged glassy surface).
	surface = mix(surface, foam_color, clamp(foam, 0.0, 1.0));

	// === 4. TRANSPARENCY ============================================
	// DEPTH drives transparency — NOT Fresnel. A first-person player
	// walking up to a pond views it at a near-grazing angle almost all
	// the time; if Fresnel forced opacity (v8's bug) you could never
	// see into water except by looking straight down. So: shallow water
	// → low alpha (see the bottom) regardless of view angle; deep water
	// → opaque. The Fresnel sky-sheen still sells "this is water" via
	// the COLOUR (step 3) + the lit sun specular (step 5).
	//
	// SEAM-RESIDUAL POLISH (2026-05-17, designer-approved): the
	// shallow_alpha FLOOR is the minimum film opacity for thin TOP
	// water so it doesn't read as invisible glass. But applied flat it
	// also gave the LOD-seam side slivers a ~0.40 pale film → a faint
	// light line where the black grid used to be. Scale the floor by
	// up_face so it only protects real up-facing water: side slivers
	// (up_face≈0) get a ~0 floor AND depth_t_eff≈0 → alpha≈0 → the
	// sliver shows the water BEHIND it (slivers are interior to the
	// body, so that's more water, never terrain) → the seam visually
	// disappears. Shallow top water (up_face≈1) keeps the full
	// shallow_alpha floor, unchanged.
	float alpha = max(depth_t_eff, shallow_alpha * up_face);
	// #15: a wind whitecap is spray sitting ON the water — opaque, not
	// see-through. Lift alpha toward 1 by the foam mask so caps read
	// solid even over shallow/clear water.
	alpha = max(alpha, clamp(foam, 0.0, 1.0));

	// === 5. OUTPUT ==================================================
	if (debug_mode == 1) {
		ALBEDO = vec3(depth_t); ALPHA = 1.0;
	} else if (debug_mode == 2) {
		ALBEDO = vec3(fresnel); ALPHA = 1.0;
	} else if (debug_mode == 3) {
		ALBEDO = vec3(clamp(thickness / max(depth_fade_distance, 0.01), 0.0, 1.0));
		ALPHA = 1.0;
	} else if (debug_mode == 4) {
		// White = up-facing water TOP (n.y≈1). Black = vertical riser /
		// side sliver (n.y≈0). If the distant dark grid lines fall on
		// BLACK fragments → edge-on side slivers → shader normal-weight
		// fix. If the grid is on uniformly WHITE top → stepped LOD tops
		// → needs surface-Y / generator fix.
		ALBEDO = vec3(clamp(n.y, 0.0, 1.0)); ALPHA = 1.0;
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
