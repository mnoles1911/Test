// test_lodfade.cpp — headless harness for Core/LodFade.h (LOD cross-fade math).
//   cd tests/standalone && ./build.sh lodfade
//
// Covers the two pure functions the streamer leans on for LOD-transition dither
// cross-fades (the timing curve + the "start a fade?" policy):
//
//   fade_alpha(elapsed, duration):
//     - clamps into [0,1] (no overshoot, no negatives)
//     - == 0 for elapsed <= 0 (and for the exact start)
//     - == 1 for elapsed >= duration (and beyond)
//     - smoothstep-shaped: strictly increasing across the open window, == 0.5 at
//       the midpoint (smoothstep is symmetric about t=0.5)
//     - degenerate duration <= 0 behaves like an instant hard swap
//
//   should_start_fade(old, new, already_fading):
//     - rejects old == new (no tier change)
//     - rejects already_fading (one fade per column at a time)
//     - accepts a genuine change when not already fading

#include <cstdio>

#include "Core/LodFade.h"  // the unit under test

// ---------------------------------------------------------------------------
// Harness boilerplate (matches every other test_*.cpp in this suite)
// ---------------------------------------------------------------------------
static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { \
    ++g_checks; \
    if (!(cond)) { \
        ++g_fails; \
        std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__); \
    } \
} while (0)

int main() {
    using namespace mira::lodfade;

    const double D = 0.35; // a representative fade window (LodFadeSeconds default)

    // ========================================================================
    // TEST 1: fade_alpha END-POINTS — clamp to 0 before/at start, 1 at/after end.
    // ========================================================================
    {
        // Before and at the start of the window -> fully 0 (new mesh invisible).
        CHECK(fade_alpha(-1.0, D) == 0.0f, "fade_alpha: elapsed < 0 -> 0");
        CHECK(fade_alpha(0.0,  D) == 0.0f, "fade_alpha: elapsed == 0 -> 0");

        // At and past the end of the window -> fully 1 (new mesh fully shown).
        CHECK(fade_alpha(D,       D) == 1.0f, "fade_alpha: elapsed == duration -> 1");
        CHECK(fade_alpha(D + 1.0, D) == 1.0f, "fade_alpha: elapsed > duration -> 1");
    }

    // ========================================================================
    // TEST 2: fade_alpha RANGE — every sampled value stays inside [0,1].
    // ========================================================================
    {
        bool in_range = true;
        // Sweep from before the window to well past it in fine steps.
        for (int i = -5; i <= 45; ++i) {
            const double elapsed = (static_cast<double>(i) / 40.0) * D; // -0.125D .. 1.125D
            const float a = fade_alpha(elapsed, D);
            if (a < 0.0f || a > 1.0f) in_range = false;
        }
        CHECK(in_range, "fade_alpha: output always clamped within [0,1]");
    }

    // ========================================================================
    // TEST 3: fade_alpha MONOTONIC — strictly increasing across the open window.
    // ========================================================================
    // Sample many interior points; each must be >= the previous (smoothstep is
    // monotonic non-decreasing, and strictly increasing on the open interval).
    {
        bool monotonic = true;
        float prev = fade_alpha(0.0001 * D, D); // just inside the start
        for (int i = 1; i <= 100; ++i) {
            const double elapsed = (static_cast<double>(i) / 100.0) * D;
            const float a = fade_alpha(elapsed, D);
            if (a < prev) monotonic = false; // a decrease would break the dissolve
            prev = a;
        }
        CHECK(monotonic, "fade_alpha: monotonic increasing across the window");

        // A real interior step must actually move (not a flat staircase): the
        // quarter-point is strictly below the three-quarter point.
        CHECK(fade_alpha(0.25 * D, D) < fade_alpha(0.75 * D, D),
              "fade_alpha: strictly increases between quarter and three-quarter");
    }

    // ========================================================================
    // TEST 4: fade_alpha SMOOTHSTEP SHAPE — midpoint is exactly 0.5.
    // ========================================================================
    // s(0.5) = 3(0.25) - 2(0.125) = 0.75 - 0.25 = 0.5. A tiny epsilon allows for
    // float rounding. This pins the curve as the intended Hermite smoothstep.
    {
        const float mid = fade_alpha(0.5 * D, D);
        CHECK(mid > 0.5f - 1e-4f && mid < 0.5f + 1e-4f,
              "fade_alpha: smoothstep midpoint == 0.5");

        // Smoothstep eases IN: at a quarter through, the value is below a linear
        // quarter (0.25) — proving the curve is eased, not a straight ramp.
        CHECK(fade_alpha(0.25 * D, D) < 0.25f,
              "fade_alpha: eased-in (quarter value below linear 0.25)");
    }

    // ========================================================================
    // TEST 5: fade_alpha DEGENERATE duration — instant (safe hard-swap fallback).
    // ========================================================================
    {
        CHECK(fade_alpha(-1.0, 0.0) == 0.0f, "fade_alpha: duration 0, before start -> 0");
        CHECK(fade_alpha(0.5,  0.0) == 1.0f, "fade_alpha: duration 0, after start -> 1 (instant)");
        CHECK(fade_alpha(0.5, -1.0) == 1.0f, "fade_alpha: negative duration -> instant");
    }

    // ========================================================================
    // TEST 6: should_start_fade POLICY — reject no-op + already-fading, accept real.
    // ========================================================================
    {
        // No tier change -> never fade (regardless of the fading flag).
        CHECK(!should_start_fade(2, 2, false), "should_start_fade: old == new -> false");
        CHECK(!should_start_fade(0, 0, false), "should_start_fade: old == new (0) -> false");

        // Already mid-fade -> defer; don't stack a second fade on the column.
        CHECK(!should_start_fade(1, 2, true),  "should_start_fade: already fading -> false");
        CHECK(!should_start_fade(2, 1, true),  "should_start_fade: already fading (finer) -> false");

        // A genuine change with no fade in progress -> go.
        CHECK(should_start_fade(0, 1, false),  "should_start_fade: real change 0->1 -> true");
        CHECK(should_start_fade(3, 1, false),  "should_start_fade: real change 3->1 (finer) -> true");
        CHECK(should_start_fade(2, 5, false),  "should_start_fade: real change 2->5 (coarser) -> true");
    }

    // ========================================================================
    // Final verdict
    // ========================================================================
    std::printf("[lodfade ] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
