// underwater_fog.gdshader -- C2 (2026-05-19)
//
// shader_type fog. Drives a FogVolume in World3D.tscn that activates
// only when the player is submerged (UnderwaterFilter.set_active(true)
// flips FogVolume.visible). Layered on top of the env's
// volumetric_fog_* (which is the static baseline murk + god rays);
// THIS shader adds *variety* and *motion* -- three octaves of scrolling
// 3D value noise modulate DENSITY so denser/lighter patches drift past
// the player, the water feels alive instead of being a single static
// colour.
//
// DENSITY only -- we don't override ALBEDO here, so the env's
// volumetric_fog_albedo (which UnderwaterFilter is already lerping
// between *_noon and *_night anchors via the live sun brightness) wins
// for the colour. Result: the colour stays consistent with the rest
// of the underwater scene, the *intensity* varies in soft drifting
// patches.
//
// 3D value noise is hash-based and asset-free (no texture lookup).
// Three octaves at different scales + velocities -> no tiling at any
// reasonable swimming speed.
//
// Reference: https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/fog_shader.html
//   and godotshaders.com "moving gradient noise fog/ mist for Godot 4"

shader_type fog;


// === KNOBS (designer-tunable on the FogVolume's material in-inspector) ===
// base_density is the static FogVolume contribution that gets noise-
// modulated. Lower than the env's underwater density because this is
// ADDITIVE on top of it -- the env supplies the baseline murk, this
// adds the drifting patches.
uniform float base_density : hint_range(0.0, 2.0) = 0.6;
// noise_strength = how much variation. 0 = flat (boring), 1 = ranges
// 0..2x of base, 2 = ranges -1..3x (with hard floor at 0).
uniform float noise_strength : hint_range(0.0, 2.0) = 0.8;
// Spatial scale of the noise -- smaller = bigger patches (slower
// variety as you swim). 0.04 1/m -> patches ~25 m across.
uniform vec3 noise_scale_xyz = vec3(0.04, 0.06, 0.04);
// Per-octave drift velocity in metres/second (world units). Three
// different directions so the octaves never sync.
uniform vec3 vel1 = vec3(0.30, 0.05, 0.20);
uniform vec3 vel2 = vec3(-0.20, 0.10, 0.35);
uniform vec3 vel3 = vec3(0.10, -0.08, -0.25);


// === 3D VALUE NOISE (asset-free) =========================================
float _h3(vec3 p) {
    p = fract(p * vec3(123.34, 456.21, 789.01));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y * p.z);
}

float _vnoise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u = f * f * (3.0 - 2.0 * f);  // smooth interpolation
    return mix(
        mix(mix(_h3(i + vec3(0.0, 0.0, 0.0)), _h3(i + vec3(1.0, 0.0, 0.0)), u.x),
            mix(_h3(i + vec3(0.0, 1.0, 0.0)), _h3(i + vec3(1.0, 1.0, 0.0)), u.x), u.y),
        mix(mix(_h3(i + vec3(0.0, 0.0, 1.0)), _h3(i + vec3(1.0, 0.0, 1.0)), u.x),
            mix(_h3(i + vec3(0.0, 1.0, 1.0)), _h3(i + vec3(1.0, 1.0, 1.0)), u.x), u.y),
        u.z);
}


// === FOG OUTPUT =========================================================
void fog() {
    vec3 p = WORLD_POSITION * noise_scale_xyz;
    // Three octaves at progressively finer scales + their own drift
    // velocities. Frequencies are non-multiple (1.0 / 1.9 / 3.7) so
    // they never re-phase into a tile.
    float n1 = _vnoise3(p          + TIME * vel1 * noise_scale_xyz);
    float n2 = _vnoise3(p * 1.9    + TIME * vel2 * noise_scale_xyz);
    float n3 = _vnoise3(p * 3.7    + TIME * vel3 * noise_scale_xyz);
    float combined = (n1 + n2 + n3) / 3.0;            // ~[0, 1]
    // Modulate density: at combined=0 -> (1 - noise_strength) * base;
    // at combined=1 -> (1 + noise_strength) * base. Clamped to >=0
    // so a negative product doesn't subtract from the env fog.
    float modulated = base_density * mix(1.0 - noise_strength,
                                         1.0 + noise_strength,
                                         combined);
    DENSITY = max(modulated, 0.0);
}
