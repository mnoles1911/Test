// underwater_overlay.gdshader -- C4 (2026-05-19)
//
// shader_type canvas_item. Attached to the TintRect ColorRect inside
// UnderwaterFilter (Player3D.tscn). v1 of UnderwaterFilter just painted
// a flat translucent blue ColorRect; v2 (this) replaces that paint with
// a screen-space shader that:
//   - Samples SCREEN_TEXTURE with a slow noise-driven UV displacement
//     (the "looking through water" wobble — very low amplitude, looks
//     like heat-haze but cooler).
//   - Slight chromatic aberration: R/G/B sampled at tiny offsets in
//     the wobble direction (light bending through water by wavelength).
//   - Mixes the result with the underwater tint colour to keep the
//     close-up "I'm submerged" tonal cast.
//
// Cost is one canvas-item pass + three SCREEN_TEXTURE samples (one per
// RGB) when submerged. Tint-only fallback: if this shader fails to
// compile on the player's hardware, the TintRect's `color` property
// still paints the v1 flat tint underneath.
//
// Reference: design/SWIMMING_AND_WATER.md "Underwater camera filter";
//   the file's original "future polish" comment is now this commit.

shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

// === KNOBS ==============================================================
// All knobs are inspector-tunable on the .tres material.

// Wobble amplitude in SCREEN_UV units (0-1 across the screen). 0.006 =
// ~6 pixels at 1080p — perceptible motion, not vomit-inducing.
uniform float wobble_strength : hint_range(0.0, 0.05) = 0.006;
// Wobble speed in Hz-ish (how fast the noise field scrolls).
uniform float wobble_speed : hint_range(0.0, 4.0) = 0.6;
// Spatial scale of the noise. Higher = smaller, more rapid wiggles.
uniform float wobble_scale : hint_range(0.5, 8.0) = 2.5;

// Chromatic aberration in SCREEN_UV units. 0.0015 = ~1.5 px at 1080p,
// genuinely subtle — too much reads as a rendering bug.
uniform float chromatic_aberration : hint_range(0.0, 0.02) = 0.0015;

// Tint colour. Alpha is the mix weight against the distorted scene
// (0 = fully see-through, 1 = fully tinted). Keep low (~0.10) so the
// vol fog + the new water back-face do the heavy lifting; this is
// just the close-up tonal cue.
uniform vec4 tint_color : source_color = vec4(0.18, 0.32, 0.42, 0.10);


// === 2D VALUE NOISE (asset-free) ========================================
float _h2(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float _vnoise2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(_h2(i),                 _h2(i + vec2(1.0, 0.0)), u.x),
               mix(_h2(i + vec2(0.0, 1.0)), _h2(i + vec2(1.0, 1.0)), u.x), u.y);
}


// === FRAGMENT ===========================================================
void fragment() {
    // Two scalar noise samples (offset in noise space) form an XY
    // displacement vector. Different phase / scroll so the displacement
    // isn't aligned with any screen axis (would look "shaky" not
    // "fluid").
    vec2 p = SCREEN_UV * wobble_scale;
    float t = TIME * wobble_speed;
    vec2 offset = vec2(
        _vnoise2(p + vec2(0.0, t))       - 0.5,
        _vnoise2(p + vec2(5.2, t * 0.7)) - 0.5
    ) * wobble_strength;

    // Chromatic aberration: R sampled slightly further along the
    // displacement direction, B slightly less. G is the "true" sample.
    // Using offset direction (not screen axes) keeps the CA aligned
    // with the wobble so it reads as part of the same effect.
    vec2 ca_dir = normalize(offset + vec2(0.001));  // +eps avoids /0
    vec2 ca = ca_dir * chromatic_aberration;

    float r = texture(screen_tex, SCREEN_UV + offset + ca).r;
    float g = texture(screen_tex, SCREEN_UV + offset).g;
    float b = texture(screen_tex, SCREEN_UV + offset - ca).b;
    vec3 distorted = vec3(r, g, b);

    // Apply the underwater tint as a fixed-weight mix. We OWN COLOR
    // here; the rect's own .color property is ignored when a material
    // is assigned, but that's fine — the .tres uniform default
    // matches it (designer changes one place).
    COLOR.rgb = mix(distorted, tint_color.rgb, tint_color.a);
    COLOR.a = 1.0;
}
