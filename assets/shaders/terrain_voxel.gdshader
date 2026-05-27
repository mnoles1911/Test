shader_type spatial;
// terrain_voxel.gdshader — the per-pixel-lit voxel terrain shader.
//
// Phase I of the graphics roadmap (design/GRAPHICS_PASS_2026-05-19.md).
//
// What it is, in plain English:
//
//   The 14 solid voxel materials (stone, dirt, grass, ...) used to
//   share one plain StandardMaterial3D — a flat texture lookup with no
//   surface detail. This shader replaces it and does three things:
//
//     1. Reproduces that StandardMaterial3D EXACTLY — samples the atlas
//        texture, nearest-filtered with mipmaps + anisotropy, cuts
//        fully-transparent pixels at a 0.5 alpha threshold, matte
//        roughness, no metal or specular. With its uniforms left at
//        their defaults a voxel looks identical to before.
//
//     2. Adds tangent-free per-pixel surface relief. A 3D value-noise
//        height field is sampled in WORLD space; the surface normal is
//        bumped from that height's screen-space derivatives using
//        Mikkelsen's surface-gradient method. It needs NO vertex
//        tangents — which is the whole point: the earlier normal-map
//        attempt (Phase C) was shelved because turning on vertex
//        tangents (`bake_tangents`) breaks the native-fluid water
//        meshes. This shader never goes near tangents, so it is
//        water-safe. (Complementary generates its normals the same
//        derivative way — lib/util/dFdxdFdy.glsl.)
//
//     3. Optional emission, so a VoxelMaterial flagged emissive glows.
//
// Faithful-reproduction notes (do not "improve" these without a reason
// — they are matched to the StandardMaterial3D this replaces):
//   - specular_disabled render mode  == specular_mode SPECULAR_DISABLED
//   - filter_nearest_mipmap_anisotropic == NEAREST_WITH_MIPMAPS_ANISOTROPIC
//   - ALPHA_SCISSOR_THRESHOLD 0.5     == TRANSPARENCY_ALPHA_SCISSOR @ 0.5
//   - ROUGHNESS default 0.85, METALLIC 0
//   - albedo is the atlas ONLY — the old material did not tint by
//     vertex colour, so this shader does not multiply by COLOR either.

render_mode specular_disabled;

// The voxel texture atlas. source_color = decode sRGB so colours match.
uniform sampler2D atlas_tex : source_color, filter_nearest_mipmap_anisotropic;

// --- Surface relief (tangent-free bump) ---
// detail_strength 0 = perfectly flat (the pre-Phase-I look). Raise it
// for more pronounced micro-relief. detail_scale sets the relief
// feature size in world metres (higher = finer, busier).
uniform float detail_strength : hint_range(0.0, 2.0) = 0.3;
uniform float detail_scale : hint_range(0.1, 8.0) = 1.6;

// --- PBR ---
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.85;

// --- Emission (off by default — emission_strength 0) ---
uniform vec3 emission_tint : source_color = vec3(1.0, 0.85, 0.55);
uniform float emission_strength : hint_range(0.0, 16.0) = 0.0;

// --- Phase J baked emissive light volume ---
// Managed by EmissiveBakedLightManager autoload via RenderingServer
// global shader parameters. Default values (1x1x1 black tex, inv_volume=0)
// keep this branch visually inert until the autoload pushes a real volume.
// inv_volume_m = 1.0 / (cells_per_axis * cell_size_metres), so a single
// multiply maps a world position into UV space.
global uniform sampler3D baked_light_tex : filter_linear, repeat_disable;
global uniform vec3 baked_light_origin_world;
global uniform float baked_light_inv_volume_m;
global uniform float baked_light_strength;

// --- F10 debug: tag emissive voxels ---
// World3DBootstrap toggles this global on F10 so the designer can find
// emissive ore (currently only copper_ore) in-world. > 0.5 means: every
// fragment whose material is emissive (emission_strength > 0) renders as
// flat full-bright magenta — ignoring atlas / relief / EMISSION. Cheap
// throw-away diagnostic; defaults to 0 in project.godot [shader_globals].
global uniform float debug_emissive_magenta;

varying vec3 v_world_pos;

// --- 3D value noise -------------------------------------------------
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

// Two-octave height field — enough relief without churning the GPU.
float relief_height(vec3 p) {
	return vnoise(p) * 0.65 + vnoise(p * 2.7) * 0.35;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 tex = texture(atlas_tex, UV);
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	METALLIC = 0.0;
	ROUGHNESS = surface_roughness;
	EMISSION = emission_tint * emission_strength;

	// F10 debug override: paint emissive voxels flat magenta so the
	// designer can locate ore at a glance. Only emissive variants
	// (emission_strength > 0) react — non-emissive terrain is unaffected.
	if (debug_emissive_magenta > 0.5 && emission_strength > 0.0) {
		ALBEDO = vec3(1.0, 0.0, 1.0);
		EMISSION = vec3(1.0, 0.0, 1.0);
		ALPHA = 1.0;
	}

	// Phase J baked emissive volume — sample the 3D light texture the
	// EmissiveBakedLightManager autoload bakes around the player. The
	// floodfill stops at solid voxels in C++, so this never bleeds light
	// through rock (the OmniLight3D system the v1 used could not avoid
	// that because shadowless cluster lights pass through geometry).
	// inv_volume_m == 0 (default) disables the sample — keeps the shader
	// visually identical to pre-Phase-J when the autoload is parked.
	if (baked_light_inv_volume_m > 0.0) {
		vec3 uv = (v_world_pos - baked_light_origin_world) * baked_light_inv_volume_m;
		if (all(greaterThanEqual(uv, vec3(0.0))) && all(lessThanEqual(uv, vec3(1.0)))) {
			vec3 baked = texture(baked_light_tex, uv).rgb;
			EMISSION += baked * baked_light_strength;
		}
	}

	// Tangent-free bump — Mikkelsen's surface-gradient method.
	// h is the relief height at this fragment, sampled in WORLD space so
	// the relief stays anchored as the camera moves. dFdx/dFdy of the
	// view-space VERTEX + NORMAL build a frame on the fly — no vertex
	// tangents needed, so this never touches `bake_tangents`.
	if (detail_strength > 0.0) {
		float h = relief_height(v_world_pos * detail_scale);
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		float dhdx = dFdx(h);
		float dhdy = dFdy(h);
		vec3 n = normalize(NORMAL);
		vec3 r1 = cross(dpdy, n);
		vec3 r2 = cross(n, dpdx);
		float det = dot(dpdx, r1);
		vec3 surf_grad = sign(det) * (dhdx * r1 + dhdy * r2);
		NORMAL = normalize(n - detail_strength * surf_grad);
	}
}
