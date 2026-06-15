// test_bands.cpp — parity harness for Core/BandPolicy.h.
//   cd tests/standalone && ./build.sh bands

#include <cstdio>
#include "Core/BandPolicy.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)

using namespace mira;
using bands::Band;

int main() {
    bands::BandConfig cfg; // far_radius 8, hysteresis 1, cold_dwell 5s

    // ---- distance bands ----
    CHECK(bands::classify(2.0f, Band::COLD, 100.0f, cfg) == Band::COLD, "near + stale -> COLD");
    CHECK(bands::classify(2.0f, Band::HOT,  0.5f,   cfg) == Band::HOT,  "near + fresh edit -> HOT");
    CHECK(bands::classify(20.0f, Band::COLD, 0.0f,  cfg) == Band::FAR,  "far dominates even if just edited");

    // ---- recency drives HOT<->COLD inside the near band ----
    CHECK(bands::classify(3.0f, Band::COLD, 4.9f, cfg) == Band::HOT,  "edit within dwell -> HOT");
    CHECK(bands::classify(3.0f, Band::HOT,  5.1f, cfg) == Band::COLD, "past dwell -> COLD");
    // an edit resets the timer -> snaps back to HOT
    CHECK(bands::classify(3.0f, Band::COLD, 0.0f, cfg) == Band::HOT,  "fresh edit re-HOTs a COLD chunk");

    // ---- near<->far hysteresis: no flip-flop on the boundary ----
    // Just past the line, a near chunk becomes FAR.
    CHECK(bands::classify(8.5f, Band::COLD, 100.0f, cfg) == Band::FAR, "cross out to FAR past far_radius");
    // A chunk ALREADY far, sitting at 7.5 (inside far_radius but within hysteresis
    // margin 8-1=7), stays FAR rather than snapping back.
    CHECK(bands::classify(7.5f, Band::FAR, 100.0f, cfg) == Band::FAR, "stay FAR within hysteresis margin");
    // Only once well inside (below 7) does it return to the near band.
    CHECK(bands::classify(6.5f, Band::FAR, 100.0f, cfg) == Band::COLD, "return to near below the margin");
    // A near chunk at 7.5 (below far_radius) is NOT far.
    CHECK(bands::classify(7.5f, Band::COLD, 100.0f, cfg) != Band::FAR, "near chunk at 7.5 stays near");

    // ---- LRU residency ----
    {
        bands::LruResidency<Vec3i> res(3);
        Vec3i ev;
        CHECK(!res.touch({0,0,0}, ev), "first insert: no eviction");
        CHECK(!res.touch({1,0,0}, ev), "second insert: no eviction");
        CHECK(!res.touch({2,0,0}, ev), "third insert fills capacity");
        CHECK(res.size() == 3 && res.capacity() == 3, "size/capacity");
        CHECK(res.contains({0,0,0}), "oldest still present at capacity");

        // Touch the oldest so it is no longer the LRU victim.
        Vec3i ignore;
        res.touch({0,0,0}, ignore);
        // Now insert a 4th -> evicts the true LRU, which is {1,0,0} (untouched longest).
        bool evicted = res.touch({3,0,0}, ev);
        CHECK(evicted && ev == Vec3i(1,0,0), "eviction removes least-recently-used");
        CHECK(!res.contains({1,0,0}), "evicted key gone");
        CHECK(res.contains({0,0,0}) && res.contains({3,0,0}), "recently-used keys retained");
        CHECK(res.size() == 3, "size stays at capacity after eviction");

        res.clear();
        CHECK(res.size() == 0, "clear empties residency");
    }

    std::printf("[bands   ] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
