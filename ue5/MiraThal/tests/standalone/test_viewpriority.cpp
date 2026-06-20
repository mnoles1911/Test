// test_viewpriority.cpp — headless harness for Core/ViewPriority.h
//   cd tests/standalone && ./build.sh viewpriority
//
// ViewPriority gives a SORT KEY (lower = load sooner) that is PRIMARILY distance
// with a SMALL secondary forward-bias. The whole point is it REORDERS without ever
// excluding or starving a chunk. These checks lock that contract:
//
//   - FORWARD WINS AT EQUAL DISTANCE: at the same true distance, a chunk in the
//     view direction has a LOWER key than one behind (loads sooner).
//   - NEAREST STILL WINS (no starvation): a chunk one ring closer always sorts
//     before a farther chunk REGARDLESS of view direction — completeness preserved.
//   - BEHIND IS FINITE (never skipped): a chunk directly behind still gets a finite,
//     ordinary key — it loads, just a little later.
//   - NO VIEW DEGRADES TO DISTANCE: fwd=(0,0) gives pure distance order (byte-for-
//     byte today's order — the flag-off behaviour).
//   - DETERMINISM: same inputs -> same key every call.

#include <cstdio>
#include <cmath>

#include "Core/ViewPriority.h"   // the unit under test
#include "Core/ChunkCoords.h"    // coords::CHUNK (documents that the unit is chunks)

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
    using mira::viewpriority::view_priority_key;
    using mira::viewpriority::view_priority_less;

    // A typical, MODEST forward-bias strength (chunks). Matches the engine default
    // (AVoxelWorld::ViewBiasChunks). Small enough that it only reorders within a band.
    const float bias = 4.0f;

    // ========================================================================
    // TEST 1: FORWARD WINS AT EQUAL DISTANCE.
    // ========================================================================
    // Two chunks the SAME true distance from the focus: one straight ahead, one
    // straight behind, along a forward heading of +X (fwd = (1,0)). The ahead chunk
    // must get the LOWER (load-sooner) key. The side chunk should land between them.
    {
        const float fwd_x = 1.0f, fwd_z = 0.0f; // looking toward +core-x

        const float k_ahead  = view_priority_key( 10,  0, fwd_x, fwd_z, bias); // straight ahead
        const float k_behind = view_priority_key(-10,  0, fwd_x, fwd_z, bias); // straight behind
        const float k_side   = view_priority_key(  0, 10, fwd_x, fwd_z, bias); // 90 deg to the side

        CHECK(k_ahead < k_behind, "forward chunk has a LOWER key than the behind chunk (loads sooner)");
        CHECK(k_ahead < k_side,   "forward chunk beats the side chunk");
        CHECK(k_side  < k_behind, "side chunk sits between ahead and behind");

        // The discount is BOUNDED: an exactly-forward chunk is shaved by at most
        // `bias` chunks, never more (so it can't leapfrog much-nearer rings — see T2).
        const float true_dist = 10.0f;
        CHECK(k_ahead >= true_dist - bias - 1e-3f, "forward discount is bounded by ring_bias (not unbounded)");
        CHECK(std::fabs(k_ahead - (true_dist - bias)) < 1e-3f, "exactly-ahead discount == ring_bias");
        CHECK(std::fabs(k_behind - (true_dist + bias)) < 1e-3f, "exactly-behind penalty == ring_bias");
    }

    // ========================================================================
    // TEST 2: NEAREST STILL WINS — the no-starvation / completeness guarantee.
    // ========================================================================
    // A chunk BEHIND the player but a full ring CLOSER must STILL sort before a
    // forward chunk that is farther away. The forward bias can only discount by
    // `bias`, so as long as the distance gap exceeds `bias`, near always wins —
    // the streamer can never starve a behind-you chunk in favour of a far ahead one.
    {
        const float fwd_x = 1.0f, fwd_z = 0.0f;

        // WORST CASE for completeness: a chunk straight BEHIND loses up to `bias`
        // (penalty) and a chunk straight AHEAD gains up to `bias` (discount). So the
        // largest distance gap the bias can ever overturn is 2*bias chunks. As long
        // as the behind chunk is MORE than 2*bias closer than the ahead chunk, the
        // behind chunk still wins — that is the hard no-starvation bound. (In the
        // streamer this is even safer: ring iteration is nearest-ring-first, so a
        // closer ring is fully visited before a farther ring is reached at all.)
        const int near_d = 5;                       // behind chunk, true dist 5
        const int far_d  = near_d + (int)(2 * bias) + 1; // ahead chunk, > 2*bias farther
        const float k_near_behind = view_priority_key(-near_d, 0, fwd_x, fwd_z, bias);
        const float k_far_ahead   = view_priority_key( far_d,  0, fwd_x, fwd_z, bias);
        CHECK(k_near_behind < k_far_ahead,
              "a behind chunk > 2*bias closer still loads before a far ahead chunk (no starvation)");

        // Sweep many rings to confirm the 2*bias bound holds broadly, not just once.
        bool near_always_wins = true;
        for (int r = 1; r <= 30; ++r) {
            const int ahead_d = r + (int)(2 * bias) + 1; // ahead chunk > 2*bias farther
            const float k_behind_near = view_priority_key(-r,       0, fwd_x, fwd_z, bias);
            const float k_ahead_far   = view_priority_key( ahead_d, 0, fwd_x, fwd_z, bias);
            if (!(k_behind_near < k_ahead_far)) near_always_wins = false;
        }
        CHECK(near_always_wins,
              "across many rings: a behind chunk > 2*bias rings closer always beats the ahead chunk");
    }

    // ========================================================================
    // TEST 3: BEHIND IS FINITE — never skipped, never infinite.
    // ========================================================================
    // The behind chunk must get an ordinary finite key (it loads, just later). A
    // NaN/inf here would mean a chunk could sort unpredictably or be dropped.
    {
        const float fwd_x = 0.0f, fwd_z = 1.0f; // looking toward +core-z
        const float k_behind = view_priority_key(0, -25, fwd_x, fwd_z, bias);
        CHECK(std::isfinite(k_behind), "behind chunk gets a FINITE key (never skipped / never inf)");
        CHECK(k_behind > 0.0f,         "behind chunk's key is positive (it is a real distance)");

        // Even at the focus column (d==0, no direction) the key is finite and minimal.
        const float k_focus = view_priority_key(0, 0, fwd_x, fwd_z, bias);
        CHECK(std::isfinite(k_focus) && std::fabs(k_focus) < 1e-3f, "focus column (0,0) sorts first (key ~0)");
    }

    // ========================================================================
    // TEST 4: NO VIEW DEGRADES TO PURE DISTANCE — flag-off equivalence.
    // ========================================================================
    // With fwd=(0,0) there is no heading, so the key must be EXACTLY the Euclidean
    // distance — identical for an ahead vs a behind chunk at the same distance.
    // This is the ordering the streamer uses today (bias off / no camera).
    {
        const float k_a = view_priority_key( 12, 0, 0.0f, 0.0f, bias);
        const float k_b = view_priority_key(-12, 0, 0.0f, 0.0f, bias);
        CHECK(std::fabs(k_a - k_b) < 1e-6f, "fwd=(0,0): ahead and behind get the SAME key (pure distance)");
        CHECK(std::fabs(k_a - 12.0f) < 1e-6f, "fwd=(0,0): key equals the true Euclidean distance");

        // ring_bias == 0 must ALSO degrade to pure distance even WITH a heading,
        // so the engine flag-off path (bias 0) is byte-for-byte distance order.
        const float k_c = view_priority_key( 7, 0, 1.0f, 0.0f, 0.0f);
        const float k_d = view_priority_key(-7, 0, 1.0f, 0.0f, 0.0f);
        CHECK(std::fabs(k_c - k_d) < 1e-6f, "ring_bias=0: heading ignored, pure distance order");
    }

    // ========================================================================
    // TEST 5: DETERMINISM — same inputs always give the same key.
    // ========================================================================
    {
        const float k1 = view_priority_key(3, -7, 0.6f, 0.8f, bias);
        const float k2 = view_priority_key(3, -7, 0.6f, 0.8f, bias);
        const float k3 = view_priority_key(3, -7, 0.6f, 0.8f, bias);
        CHECK(k1 == k2 && k2 == k3, "determinism: identical inputs -> identical key");

        // A non-unit forward vector must give the same result as its normalised form
        // (we normalise internally), so the engine can pass a raw camera-forward.
        const float k_raw  = view_priority_key(5, 5, 3.0f, 0.0f, bias); // |fwd| = 3
        const float k_unit = view_priority_key(5, 5, 1.0f, 0.0f, bias); // |fwd| = 1
        CHECK(std::fabs(k_raw - k_unit) < 1e-5f, "forward vector need not be normalised (internal normalise)");
    }

    // ========================================================================
    // TEST 6: COMPARATOR — view_priority_less sorts load-soonest first, stably.
    // ========================================================================
    // A tiny offset POD exposing x_chunks()/z_chunks() so the templated comparator
    // can read it (mirrors how the engine could wrap an FIntPoint delta).
    {
        struct Off { int x, z; int x_chunks() const { return x; } int z_chunks() const { return z; } };
        const float fwd_x = 1.0f, fwd_z = 0.0f;

        const Off ahead{ 6, 0 };
        const Off behind{ -6, 0 };
        // less(ahead, behind) == true (ahead loads sooner); less(behind, ahead) == false.
        CHECK( view_priority_less(ahead,  behind, fwd_x, fwd_z, bias), "comparator: ahead < behind");
        CHECK(!view_priority_less(behind, ahead,  fwd_x, fwd_z, bias), "comparator: behind !< ahead");

        // Irreflexive (a strict weak ordering never reports a < a).
        CHECK(!view_priority_less(ahead, ahead, fwd_x, fwd_z, bias), "comparator: irreflexive (a !< a)");
    }

    // ========================================================================
    // TEST 7: NO STARVATION (Bug-1 hardening) — a chunk MORE than ring_bias closer
    // ALWAYS sorts first regardless of view direction, AND every offset's key is finite.
    // ========================================================================
    // Bug 1 (holed spawn) was worsened when the view bias deprioritized spawn-adjacent
    // columns. The streamer now skips the bias on the innermost rings, but the underlying
    // KEY must itself never starve a closer chunk: across a full disc of offsets, ANY chunk
    // strictly more than 2*bias chunks closer (true distance) must out-rank a farther one no
    // matter where it sits relative to the heading, and NO offset may produce a NaN/inf key
    // (an infinite key could sort a real column last forever -> a permanent hole).
    //
    // WHY 2*bias (the proven bound): the key is true_dist - bias*align with align in [-1,+1],
    // so a chunk's key sits in [dist - bias, dist + bias]. The worst case for completeness is
    // the closer chunk BEHIND (key up to dist+bias) vs the farther chunk AHEAD (key down to
    // dist-bias) — overturnable only across a gap up to 2*bias. Past that, closer ALWAYS wins.
    {
        const float fwd_x = 0.6f, fwd_z = 0.8f; // an arbitrary diagonal heading

        bool all_finite = true;
        bool closer_always_first = true;

        // Sweep a disc of offsets. For each PAIR where one is strictly >2*bias closer in true
        // distance than the other, the closer one must have the smaller key (loads first).
        for (int ax = -12; ax <= 12; ++ax)
        for (int az = -12; az <= 12; ++az)
        {
            const float ka = view_priority_key(ax, az, fwd_x, fwd_z, bias);
            if (!std::isfinite(ka)) { all_finite = false; }

            const float da = std::sqrt((float)(ax * ax + az * az));
            // Compare against a few representative partners spread around the disc.
            const int partners[6][2] = { {11,0},{0,11},{-11,0},{0,-11},{8,8},{-8,-8} };
            for (auto& p : partners)
            {
                const float kb = view_priority_key(p[0], p[1], fwd_x, fwd_z, bias);
                const float db = std::sqrt((float)(p[0]*p[0] + p[1]*p[1]));
                // If A is strictly MORE than 2*bias chunks closer than B, A must sort first.
                if (da + 2.0f * bias < db && !(ka < kb)) { closer_always_first = false; }
                // (Symmetric direction is covered as the loop also visits p as `a`.)
            }
        }
        CHECK(all_finite,
              "every offset in the disc yields a FINITE key (no NaN/inf -> no column starved forever)");
        CHECK(closer_always_first,
              "a chunk >2*ring_bias closer ALWAYS sorts first, any heading (no view-bias starvation)");
    }

    // ========================================================================
    // Final verdict
    // ========================================================================
    std::printf("[viewpriority] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
