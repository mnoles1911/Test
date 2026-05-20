// water.gdshader — v9 (2026-05-18). NATIVE-FLUID PIVOT.
//
// WHY v9 (plain English):
//   v8 drew water as flat transparent cubes and the #15 layer tried to
//   fake life with a hand-rolled wind-foam field. The designer judged
//   the flat-cube + foam look a dead end ("pack-ice"). Water is now
//   Zylann NATIVE fluid (VoxelBlockyModelFluid, ids 16..23 = levels
//   1..8): the blocky mesher auto-slopes the surface between
//   differing-level neighbours and delivers the FLOW vector to us
//   through the mesh UV. This shader keeps everything that read as
//   water in v8 (depth-fade transparency, Fresnel sky sheen, lit sun
//   specular, the distance-gated LOD-seam side-face suppression) and
//   ADDS flow-driven surface motion in place of the removed foam. Calm
//   water (no flow, e.g. a still lake / ocean body) is glassy again.
//
//   #15 HAND-ROLLED FOAM IS FULLY REMOVED (designer decision
//   2026-05-18). "Look alive" is now the real flow animation below.
//
// FLOW ENCODING (Zylann VoxelBlockyFluid -> mesh -> here):
//   The fluid mesher writes per-vertex flow into UV. Convention used
//   here (GATE-0 / Zylann blocky-fluid): UV.x encodes the flow AXIS/
//   direction, UV.y encodes flow STRENGTH ~ surface slope (0 = still,
//   up to ~1 fully flowing). We decode a world-XZ flow vector from it,
//   scroll a cheap procedural ripple/normal along it, and scale the
//   whole effect by strength so a still body is perfectly calm. This is
//   the #1 item for the designer's visual pass — if Zylann's build
//   encodes flow differently, only `decode_flow()` below changes.
//
// debug_mode (cycled live by WaterDiag F6 — keep ALL of these):
//   0 normal · 1 depth_t (white=deep) · 2 fresnel ·
//   3 thickness/fade grey · 4 surface-facing (white=up top) ·
//   5 FLOW VECTOR (hue = flow direction, brightness = flow strength).
//
// Reference: design/WATER_SHADER_V2_PLAN.md, design/WATER_STAGE6_PLAN.md.

shader_type spatial;

// Lit transparent water (NOT unshaded — the sun specular sells it).
// cull_disabled so a submerged player sees the underside as a ceiling.
// depth_draw_never: the depth-fade samples DEPTH_TEXTURE for the OPAQUE
// terrain behind the water; if water wrote depth, each chunk read the
// neighbour water as "the surface behind me" -> hard seam lines. Never
// writing depth keeps the fade measuring to real terrain across all
// chunks (standard Godot depth-fade-water setup).
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx, diffuse_burley;


// ============================================================
// DEPTH TEXTURE (read-only — water-column thickness)
// ============================================================
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;


// ============================================================
// SHARED LOOK PARAMS — keep identical to water_horizon_material.tres
// ============================================================
uniform vec3 water_tint_color : source_color = vec3(0.10, 0.30, 0.42);
uniform vec3 deep_water_color : source_color = vec3(0.02, 0.06, 0.12);
uniform vec3 sky_reflection_color : source_color = vec3(0.55, 0.70, 0.85);
uniform float fresnel_power : hint_range(0.5, 16.0) = 3.0;
uniform float fresnel_strength : hint_range(0.0, 1.0) = 1.0;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.08;


// ============================================================
// DEPTH-FADE (near-water only; horizon plane forces this to "deep")
// ============================================================
// CLARITY MASTER (2026-05-19 physical rework). Divides the per-channel
// extinction below: bigger = clearer water / light travels deeper,
// smaller = murkier. ~2 = readable pond that blues over a few metres,
// ~5 = lake, ~12 = clear ocean.
uniform float depth_fade_distance : hint_range(0.2, 40.0) = 0.5;
// PER-WAVELENGTH absorption (per metre, before the clarity divide).
// Real water kills RED fastest, GREEN mid, BLUE slowest — this RGB
// spread is what makes water read clear→green→deep-blue with depth
// instead of a flat tint. R≫G>B. Tune the HUE of the depth falloff
// here; tune how FAR light reaches with depth_fade_distance.
uniform vec3 water_extinction : source_color = vec3(0.85, 0.30, 0.18);
uniform float shallow_alpha : hint_range(0.0, 1.0) = 0.85;
// 0.14 -> 0.45 (2026-05-19): physically shallow water is optically
// clear, but gameplay needs the SURFACE present — this is the alpha
// floor so thin water still reads as a water surface (sheen/ripple/
// foam) even while the bottom shows through. Lower = more see-through.
// water_murk: how murky the see-through is — 0 = perfectly clear
// refraction, 1 = fully tinted. 0.72 keeps shallow water reading as
// water while the bottom is still faintly visible.
uniform float water_murk : hint_range(0.0, 1.0) = 0.85;
// Distance-gated LOD-seam side-face suppression (2026-05-18). Does
// NOTHING nearer than _near (shallow water you look straight down into
// stays readable); ramps to full by _far where the distant dark grid
// lived. _near=0 restores the old always-on behaviour.
uniform float seam_suppress_near_m : hint_range(0.0, 200.0) = 24.0;
uniform float seam_suppress_far_m : hint_range(0.0, 400.0) = 64.0;


// ============================================================
// LEGACY UNIFORMS (declared, unused — kept so
// WaterFlowManager.set_global_wind(...) + the existing .tres do not
// error; the removed #15 foam params are likewise harmless no-ops if
// still present in the .tres).
// ============================================================
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float wind_strength : hint_range(0.0, 5.0) = 0.5;


// ============================================================
// FLOW ANIMATION (#15 "look alive", now REAL — from the fluid UV)
// ============================================================
// Physically motivated: a flowing fluid surface advects ripples
// downstream. We scroll a cheap dual-octave height field along the
// decoded flow vector; its gradient perturbs the normal so the lit
// specular + Fresnel shift and the surface visibly moves IN THE FLOW
// DIRECTION. Strength scales with the fluid's flow magnitude, so a
// still pond/ocean (strength 0) is perfectly glassy (no motion, no
// foam). Fragment-only (no geometry — blocky art direction, no
// texture). Skipped under any debug_mode so F6 stays exact.
uniform float flow_motion_strength : hint_range(0.0, 1.0) = 0.6;
uniform float flow_motion_speed : hint_range(0.0, 4.0) = 1.4;
uniform float flow_ripple_scale : hint_range(0.05, 4.0) = 0.9;
uniform float flow_normal_strength : hint_range(0.0, 0.5) = 0.12;


// ============================================================
// DEBUG
// ============================================================
uniform int debug_mode : hint_range(0, 6) = 0;

varying vec2 v_flow_uv;


// Decode the Zylann VoxelBlockyFluid flow from UV into a world-XZ flow
// vector. AUTHORITATIVE encoding (godot_voxel doc/source/blocky_terrain
// .md, MIT — spec, not copied code):
//   UV.x = triplanar axis (0=X,1=Y,2=Z) — NOT flow; unused here.
//   UV.y = flow state CODE 0..8 (45° steps, clockwise in XZ):
//          0:+X 1:+X-Z 2:-Z 3:-X-Z 4:-X 5:-X+Z 6:+Z 7:+X+Z 8:IDLE
// strength = 0 when idle (code 8), else 1 (flow is directional, not
// magnitude-graded — animation speed is constant while flowing).
vec2 decode_flow(vec2 uv, out float strength) {
	float code = floor(uv.y + 0.5);          // robust to fp UV
	if (code > 7.5) {                        // 8 = idle
		strength = 0.0;
		return vec2(0.0);
	}
	strength = 1.0;
	float ang = code * 0.78539816;           // code*45° in radians
	// code 0 → +X(1,0); rotates +X→-Z→-X→+Z, so x=cos, z=-sin.
	return vec2(cos(ang), -sin(ang));
}


// ============================================================
// V3 PHASE 1 — asset-free procedural surface (no texture → no tiling)
// ============================================================
// Screen behind the water, for refraction (see-through shallow water).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float refraction_strength : hint_range(0.0, 0.2) = 0.045;

// --- V3 Phase 2: reflection ---
// The screen-Y-flip "planar" hack was REMOVED 2026-05-19: it pasted
// the upside-down framebuffer onto the water (only correct for a mirror
// plane exactly at the horizon) and washed the surface white by
// sampling bright sky/sand. Reflection is now just a CLEAN, correctly-
// oriented Fresnel sky sheen, capped by reflection_strength so grazing
// angles never blow out to pure white. True mirror-of-terrain
// reflection needs a real planar-reflection pass (scoped follow-up
// "Phase 2b"), not a screen hack.
uniform float reflection_strength : hint_range(0.0, 1.0) = 0.7;
// Always-on sky-sheen floor so the water reads reflective/wet at ANY
// view angle (not only grazing) — without this, looking down at the
// water gave zero reflection. Grazing still ramps up via Fresnel on
// top of this floor. ~0.18 = clearly reflective but still see-through.
uniform float reflection_floor : hint_range(0.0, 0.6) = 0.18;

// --- V3 Phase 3: shoreline edge foam ---
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 1.0);
uniform float foam_edge_dist : hint_range(0.0, 4.0) = 0.5;
uniform float foam_strength : hint_range(0.0, 1.0) = 0.85;

float _h12(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float _vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(_h12(i), _h12(i + vec2(1.0, 0.0)), u.x),
	           mix(_h12(i + vec2(0.0, 1.0)), _h12(i + vec2(1.0, 1.0)), u.x), u.y);
}
float _fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	mat2 r = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
	for (int i = 0; i < 4; i++) {
		s += a * _vnoise(p);
		p = r * p * 2.03 + 7.1;
		a *= 0.5;
	}
	return s;
}
// Domain-warped, flow-advected wave height. The warp (q feeding back
// into the sample point) destroys any repeating frequency → no tiling
// / checkerboard, unlike the v9 sin+cos lattice.
float _water_h(vec2 p, vec2 flow, float t) {
	vec2 q = vec2(_fbm(p + vec2(0.0, t * 0.15)),
	              _fbm(p + vec2(5.2, 1.3) - flow * (t * 0.6)));
	return _fbm(p + 1.6 * q - flow * (t * 0.35));
}


void vertex() {
	// Flat voxel fluid — the mesher already slopes the surface
	// geometry from neighbour levels; no extra vertex displacement
	// (matches the blocky art direction). Forward the flow UV.
	v_flow_uv = UV;
}


void fragment() {
	// === 1. WATER-COLUMN THICKNESS ==================================
	float raw_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float scene_dist = -view.z;
	float frag_dist  = -VERTEX.z;
	float thickness = max(scene_dist - frag_dist, 0.0);
	// depth_t / depth_t_eff are now derived from the PER-CHANNEL
	// transmittance in §3 (physical model), after up_face is known.

	// === 2. FLOW + NORMAL ==========================================
	vec3 n = normalize(NORMAL);
	// GEOMETRIC up-ness, captured BEFORE the wave perturbation below.
	// The §2b LOD-seam suppression must key off the real face
	// orientation (is this a top face or a vertical side sliver?), NOT
	// the wave-rippled normal — otherwise the v10 noise waves tilt the
	// top normal, the distance-gated seam test mistakes wavy tops for
	// side slivers, and ALL mid/far water turns transparent (the
	// 2026-05-19 "way too see-through" regression).
	float geo_ny = n.y;
	float flow_strength = 0.0;
	vec2 flow_dir = decode_flow(v_flow_uv, flow_strength);
	if (debug_mode == 0 && flow_motion_strength > 0.001) {
		vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec2 P = wpos.xz * flow_ripple_scale;
		float T = TIME * flow_motion_speed;
		// Idle water still gets a slow non-directional ripple (not dead
		// glass); flowing water advects the waves downstream.
		vec2 fdir = (flow_strength > 0.001) ? flow_dir : vec2(0.0);
		float e = 0.35;
		float h  = _water_h(P, fdir, T);
		float hx = _water_h(P + vec2(e, 0.0), fdir, T);
		float hz = _water_h(P + vec2(0.0, e), fdir, T);
		float upness = clamp(n.y, 0.0, 1.0);
		float amp = flow_motion_strength * upness * (0.45 + 0.55 * flow_strength);
		// World-space height gradient → normal perturbation. Tops only
		// (upness), so the #222 LOD-seam side slivers stay untouched.
		n = normalize(n + vec3(h - hx, 0.0, h - hz) * (flow_normal_strength * 8.0 * amp));
	}
	vec3 v = normalize(VIEW);
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	float fresnel = pow(1.0 - ndv, fresnel_power) * fresnel_strength;

	// === 2b. LOD-SEAM SUPPRESSION — NEUTRALISED for native fluid =====
	// THE ROOT CAUSE of the whole "water way too see-through" saga.
	// This was a CUBE-WATER-era hack: old cube water had clean normals
	// (tops n.y≈1, vertical side slivers n.y≈0), so
	// smoothstep(0.30,0.72,n.y) cleanly killed only the slivers. Native
	// Zylann fluid AUTO-SLOPES its top surface, so legitimate top water
	// has geometric n.y well below 0.72 over most of the body → up_face
	// collapsed to ~0.2, and since alpha = shallow_alpha*up_face AND the
	// depth term is up_face-weighted, the ENTIRE lake rendered at ~0.17
	// alpha no matter how high shallow_alpha was set. Fluid meshing
	// doesn't produce the cube-era dark-grid side slivers, so this
	// suppression has no remaining purpose here and must be off. Forced
	// to 1.0 (full water everywhere); the old terms kept (referenced) so
	// seam_suppress_* uniforms / a future re-enable still resolve. If a
	// distant fluid artefact ever appears, fix it from the geometric
	// face, not by crushing surface alpha.
	float up_face_raw = smoothstep(0.30, 0.72, geo_ny);
	float seam_region = smoothstep(seam_suppress_near_m, seam_suppress_far_m, frag_dist);
	float up_face = 1.0;  // was mix(1.0, up_face_raw, seam_region) — see above

	// === 3. SURFACE: per-channel Beer-Lambert + in-scatter ==========
	// Physical model (2026-05-19): light transmittance through the
	// water column is exp(-k·depth) PER WAVELENGTH (k = water_extinction
	// / clarity). The refracted bottom is attenuated per RGB channel,
	// and the light lost (1-trans, red first) is replaced by the
	// water's own in-scatter colour (deep_water_color) → the real
	// clear → green → deep-blue gradient, not a flat tint mix.
	vec3 ext = water_extinction / max(depth_fade_distance, 0.05);
	vec3 trans_raw = exp(-ext * thickness);          // per-channel bottom transmittance
	// Seam fix (2026-05-17): non-up faces (distant LOD side slivers)
	// read as shallow → push trans toward 1 (no depth) by (1-up_face).
	vec3 trans = mix(vec3(1.0), trans_raw, up_face);
	float depth_t = 1.0 - dot(trans_raw, vec3(0.33333));  // scalar, ground-truth (debug 1/3)
	float depth_t_eff = 1.0 - dot(trans, vec3(0.33333));  // up-face-suppressed (refraction/alpha)
	vec2 refr_uv = clamp(SCREEN_UV + n.xz * (refraction_strength * (1.0 - depth_t_eff)),
	                     vec2(0.001), vec2(0.999));
	vec3 bottom = mix(texture(screen_tex, refr_uv).rgb, water_tint_color, water_murk);
	vec3 body = bottom * trans + deep_water_color * (1.0 - trans);

	// Phase 2 — CLEAN Fresnel sky reflection (the upside-down screen-
	// flip hack was removed; it pasted the mirrored framebuffer onto
	// the water and washed it white). reflection_strength caps the
	// sheen so even at a full grazing angle the surface keeps water
	// colour instead of blowing out to pure sky. Correctly oriented,
	// predictable, never inverted.
	// Cap at 0.5 (was 0.85): even at full grazing, at MOST half sky →
	// the water keeps its body colour and never washes pale-sky. The
	// real root cause of the "see-through pale water" was this term,
	// not alpha (the magenta proof-of-life confirmed the shader runs).
	float refl_amt = clamp(fresnel * reflection_strength + reflection_floor, 0.0, 0.5);
	vec3 surface = mix(body, sky_reflection_color, refl_amt);

	// Phase 3 — shoreline EDGE FOAM. Where the water column is thin
	// (thickness -> 0: water meets terrain / objects) lay a foam band.
	// Tops only (up_face) so LOD-seam slivers stay clean. Small
	// foam_edge_dist so only true shore edges foam, not whole shallow
	// ponds.
	float foam = clamp((1.0 - smoothstep(0.0, max(foam_edge_dist, 0.01), thickness))
	                   * foam_strength * up_face, 0.0, 1.0);
	surface = mix(surface, foam_color, foam);

	// === 4. TRANSPARENCY ===========================================
	// DEPTH drives alpha (NOT Fresnel): shallow -> see the bottom at any
	// view angle; deep -> opaque. shallow_alpha floor scaled by up_face
	// so LOD-seam side slivers (up_face~0) vanish into the water behind
	// them. Foam is opaque spray on top → lift alpha by the foam mask.
	float alpha = max(max(depth_t_eff, shallow_alpha * up_face), foam);

	// === 5. OUTPUT =================================================
	if (debug_mode == 1) {
		ALBEDO = vec3(depth_t); ALPHA = 1.0;
	} else if (debug_mode == 2) {
		ALBEDO = vec3(fresnel); ALPHA = 1.0;
	} else if (debug_mode == 3) {
		ALBEDO = vec3(clamp(thickness / max(depth_fade_distance, 0.01), 0.0, 1.0));
		ALPHA = 1.0;
	} else if (debug_mode == 4) {
		ALBEDO = vec3(clamp(n.y, 0.0, 1.0)); ALPHA = 1.0;
	} else if (debug_mode == 5) {
		// Flow vector: hue = direction (atan2 of decoded XZ flow),
		// brightness = flow strength. Still water -> black. The Phase
		// 5 / Stage-6 inspection tool — confirms the fluid mesher's
		// flow matches the visible slope direction / [FlowDiag] DIR.
		float a = atan(flow_dir.y, flow_dir.x) / 6.2831853 + 0.5;
		vec3 hue = clamp(abs(fract(a + vec3(0.0, 0.6667, 0.3333)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
		ALBEDO = hue * flow_strength; ALPHA = 1.0;
	} else if (debug_mode == 6) {
		// PROOF-OF-LIFE (2026-05-19 root-cause probe). Unmistakable
		// solid opaque MAGENTA, ignoring ALL water math. If F6 mode 6
		// turns the water bright magenta → this shader IS what draws
		// the surface (then the bug is in the colour/alpha math above).
		// If the water looks UNCHANGED → the fluid is NOT rendered with
		// this shader (the real bug = material/mesher binding, and
		// every shader edit so far has been editing a file that does
		// not drive the visible water).
		ALBEDO = vec3(1.0, 0.0, 1.0);
		ALPHA = 1.0;
		EMISSION = vec3(1.0, 0.0, 1.0);  // glow so it's unmissable even unlit
	} else {
		ALBEDO = surface;
		ALPHA = clamp(alpha, 0.0, 1.0);
	}

	METALLIC = metallic_amount;
	ROUGHNESS = roughness_amount;
	// Subtle specular: the depth-fade + Fresnel sky tint carry the
	// "this is water" read; a hard mirror glint on flat voxel faces is
	// ugly. Tune via the .tres (roughness_amount) + this constant.
	SPECULAR = 0.15;
}
