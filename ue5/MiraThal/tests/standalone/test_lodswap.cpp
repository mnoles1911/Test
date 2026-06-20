// test_lodswap.cpp — correctness lock for the MESH-THEN-SWAP "swap-hold" decision.
//   cd tests/standalone && ./build.sh lodswap
//
// WHY THIS EXISTS (plain English):
// Bug 2 was a HOLE in front of the player: when a chunk-column swapped LOD tier, the
// streamer destroyed the OLD mesh the instant the swap was decided, but the replacement
// (finer) mesh is async + budgeted and lands MANY ticks later — so for that whole window
// the player saw straight through where terrain should be. The fix is "mesh-then-swap":
// KEEP the old mesh on screen as a backstop and only destroy it once the new mesh is
// GENUINELY ready (uploaded + committed). The one load-bearing rule is a pure predicate
// in Core/LodFade.h — should_destroy_outgoing(incoming_ready) — mirroring should_start_fade.
//
// THE LOCKED INVARIANT (the whole point of this harness):
//   * The outgoing (old) mesh is NEVER destroyed while incoming_ready == false.
//   * The instant incoming_ready == true, the old mesh may (and does) get destroyed.
//   * Determinism: same input -> same answer.
//
// Pure Core, no Unreal. Prints "[lodswap] PASS/FAIL"; returns 0/1 (matches every other
// tests/standalone harness).

#include <cstdio>

#include "Core/LodFade.h"   // the unit under test (should_destroy_outgoing)

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)

using mira::lodfade::should_destroy_outgoing;
using mira::lodfade::should_start_fade;

int main() {

    // =======================================================================
    // TEST A — THE HARD LOCK: never destroy the old mesh while the new one is
    // NOT ready. This is the exact bug (holes) the fix prevents.
    // =======================================================================
    {
        CHECK(should_destroy_outgoing(/*incoming_ready=*/false) == false,
              "incoming NOT ready -> KEEP the old mesh (never destroy -> no hole)");
        CHECK(should_destroy_outgoing(/*incoming_ready=*/true) == true,
              "incoming ready -> may destroy the old mesh now (seamless swap)");
    }

    // =======================================================================
    // TEST B — MONOTONE / NO-FLICKER: as a swap progresses, the answer only ever
    // goes false -> true ONCE (it never says "destroy" then "keep" again for a
    // given readiness). We simulate a swap that becomes ready at tick K and assert
    // the old mesh survives every tick before K and is dropped at/after K.
    // =======================================================================
    {
        const int ReadyAtTick = 7; // the finer mesh finally uploads here
        bool destroyed = false;
        bool ever_destroyed_early = false;
        for (int tick = 0; tick <= 20; ++tick) {
            const bool incoming_ready = (tick >= ReadyAtTick);
            const bool destroy_now = should_destroy_outgoing(incoming_ready);
            if (destroy_now && tick < ReadyAtTick) ever_destroyed_early = true;
            if (destroy_now) destroyed = true;
        }
        CHECK(!ever_destroyed_early,
              "old mesh is NEVER destroyed on any tick before the incoming mesh is ready");
        CHECK(destroyed,
              "old mesh IS destroyed once the incoming mesh becomes ready (no permanent double-draw)");
    }

    // =======================================================================
    // TEST C — the swap-hold is GATED exactly like a real fade would be: a hold is
    // only meaningful for a GENUINE tier change. We pair should_start_fade (the
    // "do we begin?" gate) with should_destroy_outgoing (the "do we end?" gate) to
    // document that a no-op swap (old==new) never even begins, and a begun swap
    // holds until ready.
    // =======================================================================
    {
        // No real change -> nothing to begin, nothing to hold.
        CHECK(should_start_fade(/*old*/2, /*new*/2, /*already*/false) == false,
              "old==new: no swap begins (so there's nothing to hold and nothing to destroy)");
        // A genuine change begins; until ready, the hold keeps the old mesh.
        CHECK(should_start_fade(/*old*/1, /*new*/2, /*already*/false) == true,
              "genuine tier change: a swap begins");
        CHECK(should_destroy_outgoing(false) == false,
              "while that swap's new mesh isn't ready, the old mesh is held");
    }

    // =======================================================================
    // TEST D — DETERMINISM: same input -> same answer, every call.
    // =======================================================================
    {
        CHECK(should_destroy_outgoing(false) == should_destroy_outgoing(false),
              "determinism: false case stable");
        CHECK(should_destroy_outgoing(true) == should_destroy_outgoing(true),
              "determinism: true case stable");
    }

    std::printf("[lodswap] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
