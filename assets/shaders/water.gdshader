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
uniform float depth_fade_distance : hint_range(0.5, 40.0) = 7.0;
uniform float shallow_alpha : hint_range(0.0, 1.0) = 0.10;
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
uniform int debug_mode : hint_range(0, 5) = 0;

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
	// Exponential (Beer-Lambert) falloff: shallow->clear, asymptotically
	// deep->opaque, no hard cutoff. depth_fade_distance = 1/e distance.
	float depth_t = 1.0 - exp(-thickness / max(depth_fade_distance, 0.01));

	// === 2. FLOW + NORMAL ==========================================
	vec3 n = normalize(NORMAL);
	float flow_strength = 0.0;
	vec2 flow_dir = decode_flow(v_flow_uv, flow_strength);
	if (debug_mode == 0 && flow_motion_strength > 0.001 && flow_strength > 0.001) {
		vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec2 base = wpos.xz * flow_ripple_scale;
		// Scroll DOWNSTREAM (advected ripples). Speed rides flow
		// strength so faster water visibly moves faster.
		vec2 scroll = flow_dir * (TIME * flow_motion_speed * (0.3 + flow_strength));
		float w1 = sin(base.x + scroll.x) + cos(base.y * 0.85 - scroll.y);
		float w2 = sin((base.x + base.y) * 2.3 - scroll.x * 1.7)
		         + cos((base.x - base.y) * 1.9 + scroll.y * 1.3);
		float upness = clamp(n.y, 0.0, 1.0);
		float amp = flow_motion_strength * flow_strength * upness;
		// Perturb the normal along the wave gradient so the lit
		// highlight + Fresnel travel with the flow. Tops only (upness)
		// so it can NOT touch the #222 LOD-seam side slivers.
		n = normalize(n + vec3(w1, 0.0, w2) * (flow_normal_strength * amp));
	}
	vec3 v = normalize(VIEW);
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	float fresnel = pow(1.0 - ndv, fresnel_power) * fresnel_strength;

	// === 2b. LOD-SEAM SIDE-FACE SUPPRESSION (distance-gated) =======
	// Near water keeps full opacity on every face; the suppression
	// ramps in only past seam_suppress_near_m, full by _far where the
	// distant dark grid actually was. (Root-caused 2026-05-17; the
	// 2026-05-18 distance gate stops it fading near shallow water.)
	float up_face_raw = smoothstep(0.30, 0.72, n.y);
	float seam_region = smoothstep(seam_suppress_near_m, seam_suppress_far_m, frag_dist);
	float up_face = mix(1.0, up_face_raw, seam_region);
	float depth_t_eff = depth_t * up_face;

	// === 3. SURFACE COLOUR =========================================
	vec3 body = mix(water_tint_color, deep_water_color, depth_t_eff);
	vec3 surface = mix(body, sky_reflection_color, fresnel);

	// === 4. TRANSPARENCY ===========================================
	// DEPTH drives alpha (NOT Fresnel): shallow -> see the bottom at any
	// view angle; deep -> opaque. shallow_alpha floor scaled by up_face
	// so LOD-seam side slivers (up_face~0) vanish into the water behind
	// them instead of leaving a pale line.
	float alpha = max(depth_t_eff, shallow_alpha * up_face);

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
