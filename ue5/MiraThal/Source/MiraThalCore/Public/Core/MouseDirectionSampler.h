// MouseDirectionSampler.h — turns recent mouse motion into a directional intent.
//
// Ported 1:1 from Godot scripts/combat/MouseDirectionSampler.gd. This is the
// "which way did the player just flick?" reader that Mount & Blade-style
// directional combat needs at the exact moment the attack/parry button goes
// down. You feed it mouse-delta samples as they arrive, it keeps a short
// rolling window of them, and when asked it resolves one of four directions.
//
// WHY THIS LIVES IN CORE (plain English):
// The classification math — accumulate the recent deltas, throw out the ones
// that are too old, decide "is this flick mostly horizontal or mostly vertical,
// and which way?" — is pure logic with no engine in it. In Godot it read the
// clock with Time.get_ticks_usec(); here time is INJECTED. The caller (the UE
// MeleeHandler wrapper, or the headless test) passes the per-sample dt, so Core
// never touches a clock and the harness can replay an exact flick deterministically.
//
// DESIGNER MODEL (2026-05-29): "flick TOWARD where the sword comes FROM."
// The flick points at the ORIGIN of the strike; the sword then travels from
// there toward the enemy (screen centre):
//
//     flick UP    -> OVERHEAD — sword chops down from the top (high parry)
//     flick DOWN  -> THRUST   — forward stab / jab (low parry)
//     flick LEFT  -> sword comes from the LEFT, sweeps to centre (left parry)
//     flick RIGHT -> sword comes from the RIGHT, sweeps to centre (right parry)
//
// NAMING CAVEAT (carried over verbatim from the GDScript, do not "fix" it):
// a LEFT flick returns the DIR_RIGHT enum, because that enum's pose is the
// left-to-right sweep (the strike that ORIGINATES on the left). The
// DIR_LEFT/DIR_RIGHT names track the sword's travel/landing side; the flick
// selects the origin side. Hit detection is a forward-centred cone, so left vs
// right is purely cosmetic — only the visible swing pose differs.
//
// NO-FLICK = DIR_NONE: if the accumulated motion is below MIN_TOTAL_PIXELS the
// window is treated as "no meaningful flick" and sample() returns DIR_NONE, so
// the caller can run its own fallback (MeleeHandler auto-alternates L/R, the
// Bannerlord "hold and the game cycles your swings" behaviour). DIR_NONE is a
// distinct sentinel from DIR_RIGHT on purpose — the old default-RIGHT made every
// silent press a right swing, which was boring and unidiomatic.

#pragma once

#include <cmath>
#include <deque>

namespace mira {

// Direction enum exposed to callers. Integer values are STICKY — they are
// referenced from MeleeHandler tween targets and HUD arrow rotation, and they
// match the GDScript constants exactly (OVERHEAD=0, LEFT=1, RIGHT=2, THRUST=3,
// NONE=-1). Kept as plain ints so the values stay pinned across the boundary.
enum class MeleeDir : int {
    Overhead = 0,
    Left     = 1,
    Right    = 2,
    Thrust   = 3,
    None     = -1,
};

class MouseDirectionSampler {
public:
    // Rolling window length. 120 ms covers a deliberate flick (~50-80 ms) plus
    // a comfortable buffer. Matches WINDOW_SECONDS in the GDScript.
    static constexpr float WINDOW_SECONDS = 0.12f;

    // Sum of the window's |delta| magnitudes below which we treat the input as
    // "no motion" and return DIR_NONE. 60 px at 1080p is roughly a 3% screen
    // flick — clearly intentional, but small enough that a ~1 cm mouse flick
    // still registers. Matches MIN_TOTAL_PIXELS in the GDScript.
    static constexpr float MIN_TOTAL_PIXELS = 60.0f;

    MouseDirectionSampler() = default;

    // Push a new motion sample. In Godot this was called from MeleeHandler's
    // _input on every InputEventMouseMotion, with the engine clock supplying
    // "now". Here time is injected: `dt` is the seconds elapsed SINCE THE LAST
    // push (or since construction for the first one). We advance an internal
    // monotonic clock by dt, stamp the sample, then prune anything older than
    // the window. dx/dy are the raw mouse-relative deltas (Godot screen
    // convention: +y is DOWN).
    void push(float dx, float dy, float dt) {
        _now += dt;
        _samples.push_back(Sample{_now, dx, dy});
        prune();
    }

    // Resolve one of MeleeDir based on the accumulated window. Stateless with
    // respect to the sample log — calling sample() twice in a row returns the
    // same answer (the GDScript guaranteed this too). Does a lazy prune first so
    // a stale window decays even if no new sample arrived.
    MeleeDir sample() const {
        // The window is short enough (~120 ms) that plain linear accumulation
        // reads as "the direction of the flick"; no recency weighting needed.
        float sum_x = 0.0f;
        float sum_y = 0.0f;
        float total_mag = 0.0f;
        for (const Sample& s : _samples) {
            sum_x += s.dx;
            sum_y += s.dy;
            total_mag += std::sqrt(s.dx * s.dx + s.dy * s.dy);
        }

        if (total_mag < MIN_TOTAL_PIXELS) {
            // No meaningful flick this window — caller decides what that means.
            return MeleeDir::None;
        }

        // Pick the dominant axis. The 10-degree overlap window described in the
        // GDScript is implicit: we only switch horizontal<->vertical when one
        // axis exceeds the other, and the ">=" tie-break biases toward
        // horizontal exactly as the original did.
        const float abs_x = std::fabs(sum_x);
        const float abs_y = std::fabs(sum_y);
        if (abs_x >= abs_y) {
            // flick RIGHT (sum.x > 0) -> DIR_LEFT (right-originating sweep);
            // flick LEFT  (sum.x < 0) -> DIR_RIGHT (left-originating sweep).
            return (sum_x > 0.0f) ? MeleeDir::Left : MeleeDir::Right;
        }
        // flick DOWN (sum.y > 0) -> THRUST; flick UP (sum.y < 0) -> OVERHEAD.
        return (sum_y > 0.0f) ? MeleeDir::Thrust : MeleeDir::Overhead;
    }

    // Convenience for the parry path: true if the sampled direction matches.
    // Mirrors the GDScript matches(direction).
    bool matches(MeleeDir direction) const { return sample() == direction; }

    // Reset the buffer (authority handoff in MP, or handler enable/disable).
    void clear() {
        _samples.clear();
        // Leave the injected clock where it is; only the samples are state.
    }

    // True when no motion has been recorded in the current window. The GDScript
    // pruned against the live clock here; we expose a const helper that just
    // reports whether the window is empty after the last push's prune.
    bool is_empty() const { return _samples.empty(); }

private:
    struct Sample {
        float t;   // injected timestamp (seconds, monotonic)
        float dx;  // mouse-relative x
        float dy;  // mouse-relative y (+ is down)
    };

    // Drop samples older than WINDOW_SECONDS. Done at push time so we never need
    // a per-frame tick — same lazy strategy as the GDScript's _prune().
    void prune() {
        const float cutoff = _now - WINDOW_SECONDS;
        while (!_samples.empty() && _samples.front().t < cutoff) {
            _samples.pop_front();
        }
    }

    std::deque<Sample> _samples;
    float _now = 0.0f;  // injected monotonic clock, advanced by push() dt
};

} // namespace mira
