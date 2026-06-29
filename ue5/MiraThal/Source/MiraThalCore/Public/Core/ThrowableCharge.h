// ThrowableCharge.h — hold-to-charge math for the throwable spear.
//
// Ported from the engine-agnostic parts of scripts/ThrowableHandler.gd (Combat
// Phase 3 charge mechanic). The Godot handler also does camera-FOV pinch, scene
// spawning, and rigidbody wiring — all scene concerns left to the UE wrapper.
// What lives here is the pure mapping the gameplay feel depends on: how long you
// held the button -> how fast + how hard the spear lands, and whether a lethal
// hit gibs.
//
// Pure C++17, no engine types. Time (hold duration) is passed in milliseconds,
// exactly as the GDScript tracked it.

#pragma once

namespace mira {
namespace throwable {

// The charge window. Below MIN it's a "light throw" (same as before charge
// existed — stops a stray click feeling underpowered); at/above MAX it's fully
// charged; linear in between. Values verified against ThrowableHandler.gd.
constexpr int   CHARGE_MIN_HOLD_MS = 150;
constexpr int   CHARGE_MAX_HOLD_MS = 700;

// Spear velocity (m/s): base (light) -> charged. Lerped across the window.
constexpr float LIGHT_THROW_SPEED   = 12.0f; // throw_speed_meters_per_second
constexpr float CHARGED_THROW_SPEED = 16.0f;

// Spear damage: base (the item's combat_damage, typically 30) -> charged.
constexpr int   BASE_SPEAR_DAMAGE = 30;
constexpr int   CHARGED_DAMAGE    = 60;

// A lethal hit from a fully-charged spear (>= CHARGED_DAMAGE) triggers the gib
// explosion + a brief time-slow on the kill. (The 0.15 s slow + camera kick are
// applied by the wrapper; the THRESHOLD decision is the parity-critical bit.)
constexpr int   GIB_DAMAGE_THRESHOLD = CHARGED_DAMAGE; // 60
constexpr float KILL_TIME_SLOW_SECONDS = 0.15f;

// Normalized charge 0..1 from a hold duration. 0 at <= MIN, 1 at >= MAX, linear
// between. Mirrors _charge_t_from_hold.
constexpr float charge_t_from_hold(int hold_ms) {
    if (hold_ms <= CHARGE_MIN_HOLD_MS) return 0.0f;
    if (hold_ms >= CHARGE_MAX_HOLD_MS) return 1.0f;
    return static_cast<float>(hold_ms - CHARGE_MIN_HOLD_MS)
         / static_cast<float>(CHARGE_MAX_HOLD_MS - CHARGE_MIN_HOLD_MS);
}

constexpr float lerpf(float a, float b, float t) { return a + (b - a) * t; }

// Spear launch speed for a given hold.
constexpr float speed_for_hold(int hold_ms) {
    return lerpf(LIGHT_THROW_SPEED, CHARGED_THROW_SPEED, charge_t_from_hold(hold_ms));
}

// Spear damage for a given hold, lerped from a base damage up to CHARGED_DAMAGE.
// Rounded like the GDScript int(round(lerpf(...))).
inline int damage_for_hold(int hold_ms, int base_damage = BASE_SPEAR_DAMAGE) {
    const float t = charge_t_from_hold(hold_ms);
    const float d = lerpf(static_cast<float>(base_damage),
                          static_cast<float>(CHARGED_DAMAGE), t);
    // round-half-away-from-zero to match Godot round()
    return static_cast<int>(d < 0.0f ? d - 0.5f : d + 0.5f);
}

// Was this a real charged throw (vs a light tap)? hold >= MIN.
constexpr bool is_charged(int hold_ms) { return hold_ms >= CHARGE_MIN_HOLD_MS; }

// Does a lethal hit of this final damage gib the target?
constexpr bool triggers_gib(int final_damage) {
    return final_damage >= GIB_DAMAGE_THRESHOLD;
}

} // namespace throwable
} // namespace mira
