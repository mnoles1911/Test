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
// Reference: design/WATER_SHADER_V3_PLAN.md (current shader spec) +
//   design/WATER_STAGE6_PLAN.md (native-fluid pivot decision record).

shader_type spatial;

// Lit transparent water (NOT unshaded — the sun specular sells it).
// cull_disabled so a submerged player sees the underside as a ceiling.
// depth_draw_never: the depth-fade samples DEPTH_TEXTURE for the OPAQUE
// terrain behind the water; if water wrote depth, each chunk read the
// neighbour water as "the surface behind me" -> hard seam lines. Never
// writing depth keeps the fade measuring to real terrain across all
// chunks (standard Godot depth-fade-water setup).
// shadows_disabled (added 2026-05-20): water must NOT cast shadows on
// the underwater volumetric fog. Designer screenshot showed a dark
// SUN-SHAPED orb when looking up from underwater — that was the water
// polygon shadow-casting onto the god-ray fog, blocking the sun's
// light exactly along the camera-to-sun column. Real water passes
// most light through; a stylized voxel water that casts hard shadows
// reads as opaque. With shadows off, the fog underwater is fully lit
// by the directional light → visible sunbeams, no shadow disc.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_schlick_ggx, diffuse_burley;


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
// Modes:
//   0 normal · 1 depth_t · 2 fresnel · 3 thickness · 4 surface-facing
//   5 flow-vector · 6 MAGENTA proof-of-life
//   7 RAW ALPHA grayscale (white = opaque, black = transparent) —
//       added 2026-05-27 to bisect "is the gap a low-alpha pixel or a
//       missing mesh fragment?" If the gap bands show BLACK in mode 7,
//       the water mesh IS there and alpha is collapsing → fix in this
//       shader. If the gap bands show NOTHING (background visible
//       through them), the fluid mesh is absent for those LOD chunks
//       → fix in Zylann fluid mesher / generator.
//   8 LOD-DISTANCE band — colours each water fragment by distance
//       from the player along the visible LOD rings:
//         green   <  21 m  (LOD0, lod_distance=128 vox = 21.3 m)
//         yellow  21..43m  (LOD1)
//         orange  43..85m  (LOD2)
//         red     85..170m (LOD3)
//         purple  >170m    (DistantTerrain band, no water mesh past here)
//       Matches the F11 terrain-LOD-debug shader so designer can
//       overlay both. Reads `player_world_pos` global shader
//       parameter (already pushed by World3DBootstrap each frame).
uniform int debug_mode : hint_range(0, 8) = 0;
global uniform vec3 player_world_pos;

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

// --- V3 Phase 3: shoreline edge foam (REWORKED 2026-05-20 — animated,
// noise-broken, tight). Foam is a scrolling FBM-broken fringe that hugs
// the shore and laps over time, not a flat painted stripe. Knobs:
//   foam_edge_dist   = band width from the water/terrain contact edge,
//                      in metres. ~0.33 ~= 2 voxels at 6 vox/m (tight).
//   foam_strength    = opacity (0 = invisible, 1 = solid).
//   foam_noise_scale = spatial frequency of the foam churn (bigger =
//                      finer flecks).
//   foam_scroll_speed= how fast the foam laps / churns (0 = frozen).
//   foam_raggedness  = 0 clean smooth band (old look) .. 1 fully
//                      noise-broken ragged fringe.
// All tuned in water_material.tres.
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 1.0);
uniform float foam_edge_dist : hint_range(0.0, 4.0) = 0.33;
uniform float foam_strength : hint_range(0.0, 1.0) = 0.6;
uniform float foam_noise_scale : hint_range(0.05, 4.0) = 0.7;
uniform float foam_scroll_speed : hint_range(0.0, 3.0) = 0.35;
uniform float foam_raggedness : hint_range(0.0, 1.0) = 0.7;

// --- §2c side-face camouflage knobs (2026-05-19) ---
// side_color = mix(water_tint_color * side_tint_brighten,
//                  sky_reflection_color, side_sky_mix)
// The water_tint_color base (0.10,0.30,0.42) alone read too dark on
// LOD-seam sides — designer wanted brighter + a fraction of sky.
uniform float side_tint_brighten : hint_range(1.0, 3.0) = 1.7;
uniform float side_sky_mix : hint_range(0.0, 1.0) = 0.30;

// ============================================================
// V3 PHASE 4a — UNDERSIDE (back-face / "looking up from underwater")
// ============================================================
// The shader is cull_disabled so the underside renders, but the v9/v10
// code path assumes "looking down at water from above" — depth-fade
// reads sky as the scene behind the water (giant thickness → 100%
// deep_water_color blend) and Fresnel paints the surface with
// sky_reflection_color, which together make the underside read as a
// pale sky-tinted ceiling with no visible flow motion. The 2026-05-19
// "atmospheric fog seems backwards" screenshot is exactly this. Below
// we branch on FRONT_FACING: for back-faces we render a *dark* underside
// (deep_water_color) with the SAME flow-perturbed normal animation
// (so the surface visibly moves) and a soft sun glint where the view
// ray points toward where the sun is shining down through the water.
//
// sun_direction_world: direction the sun's light TRAVELS in world space
// (i.e. points from sun toward ground). UnderwaterFilter.gd pushes the
// live value from the Sun DirectionalLight3D each frame while
// submerged. Default points straight down so the glint sits at the
// zenith if the autoload isn't pushing yet (dev scenes etc.).
uniform vec3 sun_direction_world = vec3(0.0, -1.0, 0.0);
// Glint tightness — higher = smaller, harder bright spot. v1 was 48
// (very tight at sun-zenith only); 2026-05-20 designer report "no
// rays at dawn/dusk shallow angles" → widened to 24 so the bright
// spot reads at low sun angles too. Halve for an even wider halo
// if dawn/dusk still feels dark.
uniform float underside_sun_glint_power : hint_range(2.0, 256.0) = 24.0;
uniform float underside_sun_glint_strength : hint_range(0.0, 4.0) = 1.6;
// Underside alpha — near-opaque so the dark deep-water ceiling reads
// against the brightly-lit underwater fog beyond the polygon. v1 used
// 0.92 → 8% bright-fog bleed-through dominated the look, hiding the
// dark blue. 0.98 keeps only a 2% bleed (enough that the bright glint
// feels like real light breaking through, not pasted on).
uniform float underside_alpha : hint_range(0.0, 1.0) = 0.98;
// Underside glint tint — warm-white. Multiplied by glint mask.
uniform vec3 underside_glint_color : source_color = vec3(1.0, 0.95, 0.80);

// === DEPTH GRADIENT (added 2026-05-20) ===================================
// Player's submerged depth, in metres below where they entered the water.
// UnderwaterFilter.gd snapshots the player's Y at the submerge moment
// and pushes this uniform every frame as `surface_snapshot_y - current_y`.
// Used by the back-face branch below to fade brightness with depth.
uniform float underwater_depth_meters = 0.0;
// At this depth the underside reads fully dark (the depth_attenuation
// term reaches 0). Linear ramp between 0 m (full brightness) and this.
uniform float depth_for_full_dark : hint_range(1.0, 40.0) = 12.0;
// Skylight ambient bleed — even at low sun angles, the bright sky
// above the water surface should lift the underside slightly so the
// "looking up" view isn't pitch black. Scales linearly with
// depth_attenuation (shallow = full bleed, deep = none).
uniform float skylight_ambient_strength : hint_range(0.0, 1.0) = 0.35;
// Skylight bleed colour — mostly sky_reflection_color but uniform so
// the designer can taste-tune separately.
uniform vec3 skylight_ambient_color : source_color = vec3(0.45, 0.62, 0.80);

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
	vec3 n_geo = normalize(NORMAL);
	// GEOMETRIC up-ness, captured for §2b/§2c face classification (is
	// this a top face or a vertical side sliver?). MUST be sourced from
	// the per-vertex NORMAL, not the shaded `n` below — the wave-rippled
	// shaded normal isn't a face-orientation cue.
	float geo_ny = n_geo.y;
	//
	// LOD-SEAM FIX (2026-05-27, fix/water-lod-seam). The shading normal
	// `n` is now derived purely from a flat (0,1,0) base + the world-XZ
	// wave gradient, NOT from per-vertex NORMAL. WHY: Zylann's fluid
	// mesher triangulates the auto-sloped fluid surface at different
	// densities per LOD ring (LOD0 mesh_block=16, LOD1+=32), so adjacent
	// chunks at a LOD seam interpolate slightly different NORMAL vectors
	// at the same world-XZ position. The previous shader did
	// `n = NORMAL + wave_grad → norm`, which propagated that mismatch →
	// ndv differed across the seam → Fresnel, refraction offset, and
	// depth-fade alpha all differed → a visible "transparent line" along
	// every LOD chunk boundary on every body of water (designer-reported
	// 2026-05-22, deferred from PR #240 as needing a water-shader session).
	// World-XZ-derived normals are identical at the same world position
	// regardless of which LOD chunk owns the fragment, killing the seam.
	// Geometric SLOPE is still visible because the GEOMETRY slopes — we
	// just stop letting per-vertex normals drive lighting. §2c camouflage
	// continues to override side-face colour using geo_ny.
	vec3 n = vec3(0.0, 1.0, 0.0);
	float flow_strength = 0.0;
	vec2 flow_dir = decode_flow(v_flow_uv, flow_strength);
	// Wave height captured at OUTER scope so the back-face branch can
	// read it to drive an underside brightness pattern that animates
	// in lockstep with the surface ripple visible from above. Default
	// 0.5 (neutral) for the cases where the flow block doesn't run.
	float wave_height = 0.5;
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
		wave_height = h;  // capture for back-face branch
		// Upness keyed off the GEOMETRIC normal (face classification);
		// the shaded `n` starts at (0,1,0) so reading n.y here would be
		// ~1 on every fragment and remove the side-face gating.
		float upness = clamp(geo_ny, 0.0, 1.0);
		float amp = flow_motion_strength * upness * (0.45 + 0.55 * flow_strength);
		// World-XZ height gradient → flat-up + wave perturbation. Same
		// world position → same `n` regardless of LOD triangulation.
		n = normalize(n + vec3(h - hx, 0.0, h - hz) * (flow_normal_strength * 8.0 * amp));
	}

	// === 2.5 BACK-FACE (player is underwater looking up) ============
	// Only override the default visual (debug_mode == 0) — non-zero
	// debug modes fall through to keep F6 diagnostics working from
	// below too. See uniform block "UNDERSIDE" up top for why.
	//
	// NB Godot shaders disallow `return` in fragment(), so we set a
	// flag and gate the rest of fragment() with an inverse check
	// below. Functionally identical to early-return.
	bool _uw_back_face = (!FRONT_FACING && debug_mode == 0);
	if (_uw_back_face) {
		// World-space view direction (vertex toward camera). VIEW is in
		// VIEW space (frag→cam); mat3(INV_VIEW_MATRIX) rotates it back.
		// When the player is BELOW a water surface fragment, view_world
		// points DOWN (from the up-fragment to the down-camera).
		vec3 view_world = normalize(mat3(INV_VIEW_MATRIX) * VIEW);
		// Both vectors should point DOWN when the camera is looking at
		// the sun through the water:
		//   sun_direction_world = direction the sun's light TRAVELS = DOWN
		//   view_world          = frag-to-camera                    = DOWN
		// So `dot(view_world, sun_direction_world)` peaks at 1.0 when
		// the camera ray aligns with the sun-down column. v1 had this
		// negated (`-sun_direction_world` then dotted) which gave -1
		// everywhere → glint always 0. Designer screenshot 2026-05-20
		// showed no bright spot; this fixes it.
		float glint_align = clamp(dot(view_world, normalize(sun_direction_world)), 0.0, 1.0);
		float glint = pow(glint_align, underside_sun_glint_power)
		            * underside_sun_glint_strength;
		// Modulate glint very mildly by the wave-perturbed normal so
		// the bright spot shimmers with the surface motion (NOT
		// a hard wiggle — wave normal here is small, this is just
		// "alive" feel).
		glint *= (0.85 + 0.15 * clamp(n.y, 0.0, 1.0));

		// 2026-05-20 designer report (pass 2): ripple bands ×5 more
		// prominent so they're plainly visible even far from the surface,
		// PLUS depth-graded brightness (shallow = much brighter than
		// deep), PLUS skylight ambient bleed so the underside isn't
		// pitch-dark when the sun is at a low angle.
		//
		// Wave-pattern brightness: huge ratio between peaks and troughs.
		//   trough (h=0):     deep_water * 0.30 — near-black
		//   peak   (h=1):     deep_water * 2.50 + water_tint * 1.5 + sun warm
		// + caustic_lift adds water_tint colour at peaks (refraction-style
		//   focusing of sky-light through the wave lens).
		// + sun_caustic adds a warm tint at peaks scaled by wave_height
		//   squared so it's concentrated on the actual peaks (lensing).
		float wave_brightness = mix(0.30, 2.50, wave_height);
		vec3 caustic_lift = mix(vec3(0.0), water_tint_color * 1.5, wave_height);
		vec3 sun_caustic = mix(vec3(0.0),
		                        underside_glint_color * 0.5,
		                        wave_height * wave_height);
		vec3 wave_underside = deep_water_color * wave_brightness
		                    + caustic_lift
		                    + sun_caustic;

		// Depth attenuation — fades underside brightness from 1.0 at
		// surface to ~0 at depth_for_full_dark. Player's depth pushed
		// by UnderwaterFilter; defaults to 0 (no attenuation) when above
		// water or when the uniform hasn't been written yet.
		float depth_attenuation = 1.0 - clamp(
			underwater_depth_meters / max(depth_for_full_dark, 0.5),
			0.0, 1.0);
		// At shallow depths, lift everything; at deep, crush it.
		// 0.4 minimum keeps the underside from going pitch-black even
		// at full depth (some light always makes it through).
		float depth_factor = 0.4 + 0.6 * depth_attenuation;

		// Skylight ambient: a sun-direction-INDEPENDENT lift so the
		// underside reads as "light coming through water" at any time
		// of day, not only when the sun is directly overhead. Fades
		// with depth.
		vec3 skylight_bleed = skylight_ambient_color
		                    * skylight_ambient_strength
		                    * depth_attenuation;

		vec3 underside = wave_underside * depth_factor
		               + skylight_bleed
		               + underside_glint_color * glint
		                  * (0.5 + 0.5 * depth_attenuation);
		// Unlit emission so the bright spot reads at any time of day
		// (sun could be below horizon; we still want some glow from
		// scattered/refracted light through the surface — at night this
		// term goes near-zero anyway because UnderwaterFilter drops
		// the sun energy / fog density to inky values).
		ALBEDO = underside;
		EMISSION = underside_glint_color * (glint * 0.4);
		ALPHA = underside_alpha;
		METALLIC = 0.0;
		ROUGHNESS = 1.0;
	}

	// Everything below is the regular front-face / debug-mode path.
	// Gated by !_uw_back_face since Godot shaders cannot early-return
	// from fragment(). The closing `}` for this block is just before
	// the closing `}` of fragment().
	if (!_uw_back_face) {
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

	// === 2c. LOD-SEAM SIDE-FACE CAMOUFLAGE (2026-05-19 v2) ===========
	// Zylann's fluid mesher fills LOD-block-edge height mismatches with
	// near-vertical side polygons (n.y ≈ 0). Untouched they render as a
	// dark grid (low Fresnel → black; visible in mode 2 + mode 0, and
	// they POP into existence on every chunk during movement because
	// re-meshing isn't synced to LOD-fade). The previous attempts —
	// alpha-cut (this branch) and the OLD smoothstep 0.30..0.72 up_face
	// dim — both failed: alpha-0 leaves a noticeable band, and the
	// 0.72 threshold also killed auto-sloped fluid tops (the "whole
	// lake at 17% alpha" bug). We CAN'T stop the mesher generating the
	// side polys without modifying Zylann. So instead: blend the side
	// fragment's COLOUR toward the top-water tint so it visually
	// continues the surface, and keep it opaque so the lakebed doesn't
	// leak through the seam. Always-on (no distance gate) → grid hides
	// near AND far, while moving AND stopped.
	//
	// top_weight: 1 on real top / auto-sloped fluid surface
	//             (n.y ≳ 0.30 — fluid auto-slopes never go below this),
	//             0 on truly vertical seam side faces (n.y ≲ 0.10).
	float top_weight = smoothstep(0.10, 0.30, geo_ny);

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

	// Phase 3 — shoreline EDGE FOAM (reworked 2026-05-20: animated +
	// noise-broken). Base proximity band: foam where the water column is
	// thin (thickness -> 0, water meets terrain). foam_edge_dist is kept
	// TIGHT so the band hugs the true contact edge. The cutoff is then
	// wobbled in/out by scrolling FBM noise -> a ragged, churning foam
	// fringe that laps over time instead of a flat painted stripe. Tops
	// only (up_face) so LOD-seam slivers stay clean.
	vec3 foam_wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 foam_p = foam_wpos.xz * foam_noise_scale;
	float foam_t = TIME * foam_scroll_speed;
	// Advect the noise along the flow direction; the small constant drift
	// keeps still-water foam lapping too (flow_dir is 0 on idle water).
	float foam_noise = _fbm(foam_p + flow_dir * foam_t + vec2(0.0, foam_t * 0.5));
	// Noise pushes the foam cutoff in/out by +/-(raggedness*edge) so the
	// edge dissolves into moving flecks. raggedness 0 = exact old band.
	float foam_cut = thickness + (foam_noise - 0.5) * foam_raggedness * foam_edge_dist;
	float foam = clamp((1.0 - smoothstep(0.0, max(foam_edge_dist, 0.01), foam_cut))
	                   * foam_strength * up_face, 0.0, 1.0);
	// Mottle the foam itself (light/dark patches from the same noise) so
	// it does not read as a flat fill.
	vec3 foam_shaded = foam_color * (0.82 + 0.30 * foam_noise);
	surface = mix(surface, foam_shaded, foam);

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
		// Surface-facing diagnostic: white = top face, black = vertical
		// side sliver. Uses GEOMETRIC normal (geo_ny) — the shaded `n`
		// starts at (0,1,0) post the 2026-05-27 LOD-seam fix, so n.y
		// would be ~1 everywhere and the diagnostic would lose its
		// top-vs-side signal.
		ALBEDO = vec3(clamp(geo_ny, 0.0, 1.0)); ALPHA = 1.0;
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
	} else if (debug_mode == 7) {
		// RAW ALPHA grayscale (2026-05-27). Render the full alpha calc
		// as a grayscale value with ALPHA forced to 1 so it's always
		// visible. The visible "gap bands" at LOD rings: if they show as
		// BLACK STRIPES against white water in this mode, the water mesh
		// IS rendering at those fragments and alpha is collapsing →
		// the bug lives in this shader's alpha math (probably the
		// `thickness` / Beer-Lambert term reading a different depth at
		// LOD boundaries). If the gap bands show as the unchanged scene
		// background (terrain colour bleeding through), the water mesh
		// is ABSENT for those LOD chunks → bug lives in Zylann's fluid
		// mesher or the C++ generator's per-LOD water emission.
		ALBEDO = vec3(clamp(alpha, 0.0, 1.0));
		ALPHA = 1.0;
		EMISSION = vec3(0.0);
	} else if (debug_mode == 8) {
		// LOD-DISTANCE band (2026-05-27). Distance from the player along
		// the visible LOD rings. Matches the F11 terrain LOD-debug
		// shader's bands exactly so designer can overlay both: the gap
		// bands should map onto a SPECIFIC LOD ring boundary (e.g.
		// green→yellow at 21 m). Reads `player_world_pos` global
		// (registered in project.godot [shader_globals]).
		vec3 wpos_dbg = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float d_dbg = length(wpos_dbg - player_world_pos);
		vec3 band_color;
		if (d_dbg < 21.0) {
			band_color = vec3(0.2, 0.9, 0.2);          // green   LOD0  <21m
		} else if (d_dbg < 43.0) {
			band_color = vec3(0.95, 0.95, 0.2);        // yellow  LOD1  21..43m
		} else if (d_dbg < 85.0) {
			band_color = vec3(1.0, 0.6, 0.15);         // orange  LOD2  43..85m
		} else if (d_dbg < 170.0) {
			band_color = vec3(0.95, 0.25, 0.25);       // red     LOD3  85..170m
		} else {
			band_color = vec3(0.65, 0.30, 0.95);       // purple  >170m DistantTerrain
		}
		// Dark gridline at each ring boundary so the band edges are
		// unmissable even on a flat surface.
		float ring_marker = 0.0;
		float[5] ring_bounds = float[](21.0, 43.0, 85.0, 170.0, 256.0);
		for (int i = 0; i < 5; i++) {
			if (abs(d_dbg - ring_bounds[i]) < 0.4) {
				ring_marker = 1.0;
			}
		}
		ALBEDO = mix(band_color, vec3(0.0), ring_marker);
		ALPHA = 1.0;
		EMISSION = vec3(0.0);
	} else {
		// §2c camouflage: on truly vertical seam side faces, replace
		// the dark Fresnel-driven `surface` with the top-water tint
		// (no sun-specular / no Fresnel sky-reflection — those are
		// what made sides read black), and force solid alpha so the
		// lakebed can't leak through the geometric seam. Auto-sloped
		// fluid tops (n.y ≳ 0.30) get full `surface`/`alpha` — the
		// recent murk/shallow_alpha/Fresnel tune is preserved.
		vec3 side_base = water_tint_color.rgb * side_tint_brighten;
		vec3 side_color = mix(side_base, sky_reflection_color.rgb, side_sky_mix);
		float side_alpha = max(shallow_alpha, 0.92);
		ALBEDO = mix(side_color, surface, top_weight);
		ALPHA = clamp(mix(side_alpha, alpha, top_weight), 0.0, 1.0);
	}

	METALLIC = metallic_amount;
	ROUGHNESS = roughness_amount;
	// Subtle specular: the depth-fade + Fresnel sky tint carry the
	// "this is water" read; a hard mirror glint on flat voxel faces is
	// ugly. Tune via the .tres (roughness_amount) + this constant.
	SPECULAR = 0.15;
	}  // end of `if (!_uw_back_face) { ... }` front-face gate
}
