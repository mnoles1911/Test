// water.gdshader — Sine-sum surface waves for WaterVolume meshes.
//
// Vertex stage displaces VERTEX.y by the sum of two sine waves
// (different directions, frequencies, speeds, amplitudes). Wind biases
// the dominant wave direction and scales overall amplitude.
//
// Fragment stage tints crests slightly lighter than troughs by reading
// the displacement value passed through COLOR.r.
//
// World-space XZ is used as the wave domain so adjacent water bodies
// stay phase-aligned (no visible seam if two volumes overlap).
//
// Driven by WaterVolume.gd — wind_dir / wind_strength uniforms get
// updated each frame from the script's @export vars, which the future
// WeatherManager will write via WaterVolume.set_wind(dir, strength).

shader_type spatial;
// cull_disabled (was cull_back): submerged players were seeing nothing
// where the water surface should be, because the back face of the
// surface plane (the "underside" you see when diving below it) was
// culled. Disabling culling makes the surface visible from both sides
// — looking up through the surface from below now reads as a tinted
// ceiling, not blank space.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// --- WAVE PARAMS (designer-tunable in the inspector via the .tres) ---
uniform float wave_amplitude_a : hint_range(0.0, 1.0) = 0.08;
uniform float wave_frequency_a : hint_range(0.05, 5.0) = 0.5;
uniform float wave_speed_a : hint_range(0.0, 5.0) = 1.0;
uniform vec2 wave_dir_a = vec2(1.0, 0.0);

uniform float wave_amplitude_b : hint_range(0.0, 1.0) = 0.04;
uniform float wave_frequency_b : hint_range(0.05, 5.0) = 1.3;
uniform float wave_speed_b : hint_range(0.0, 5.0) = 0.8;
uniform vec2 wave_dir_b = vec2(0.7, 0.7);

// --- WIND COUPLING (driven by WaterVolume.gd, future WeatherManager) ---
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float wind_strength : hint_range(0.0, 5.0) = 0.5;

// --- COLOUR ---
uniform vec4 base_color : source_color = vec4(0.16, 0.32, 0.48, 0.78);
uniform vec4 crest_color : source_color = vec4(0.45, 0.65, 0.78, 0.85);
uniform float crest_threshold : hint_range(0.0, 1.0) = 0.5;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.4;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.18;

void vertex() {
	// World-space XZ keeps adjacent bodies phase-aligned.
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 xz = world_pos.xz;

	// Wind biases wave-A direction; wind strength scales total amplitude.
	vec2 wind = normalize(mix(wave_dir_a, wind_dir, 0.5));
	float wind_amp = 1.0 + wind_strength * 0.5;

	float wave_a = sin(dot(xz, wind) * wave_frequency_a + TIME * wave_speed_a);
	float wave_b = sin(dot(xz, wave_dir_b) * wave_frequency_b + TIME * wave_speed_b);

	float displacement = (wave_a * wave_amplitude_a + wave_b * wave_amplitude_b) * wind_amp;
	VERTEX.y += displacement;

	// Pass normalised displacement (0..1) to fragment for crest tint.
	float max_disp = max(wave_amplitude_a + wave_amplitude_b, 0.001);
	COLOR.r = clamp(displacement / max_disp * 0.5 + 0.5, 0.0, 1.0);
}

void fragment() {
	float crest_t = smoothstep(crest_threshold, 1.0, COLOR.r);
	vec4 tinted = mix(base_color, crest_color, crest_t);
	ALBEDO = tinted.rgb;
	ALPHA = tinted.a;
	METALLIC = metallic_amount;
	ROUGHNESS = roughness_amount;
}
