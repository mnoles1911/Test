// test_throwable.cpp — parity harness for Core/ThrowableCharge.h.
//
// Verifies the spear hold-to-charge mapping ported from ThrowableHandler.gd.
//   cd tests/standalone && ./build.sh throwable

#include <cstdio>
#include <cmath>
#include "Core/ThrowableCharge.h"

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)
static bool approx(float a, float b) { return std::fabs(a - b) < 0.001f; }

int main() {
    using namespace mira::throwable;

    // charge_t clamps below MIN and above MAX, linear between
    CHECK(approx(charge_t_from_hold(0), 0.0f),   "0ms -> t=0");
    CHECK(approx(charge_t_from_hold(150), 0.0f), "150ms (MIN) -> t=0");
    CHECK(approx(charge_t_from_hold(700), 1.0f), "700ms (MAX) -> t=1");
    CHECK(approx(charge_t_from_hold(1000), 1.0f), "above MAX clamps t=1");
    // midpoint: (425-150)/(700-150) = 275/550 = 0.5
    CHECK(approx(charge_t_from_hold(425), 0.5f), "425ms -> t=0.5");

    // speed lerps 12 -> 16
    CHECK(approx(speed_for_hold(150), 12.0f), "light throw speed 12");
    CHECK(approx(speed_for_hold(700), 16.0f), "charged speed 16");
    CHECK(approx(speed_for_hold(425), 14.0f), "half charge speed 14");

    // damage lerps base(30) -> 60, rounded
    CHECK(damage_for_hold(150) == 30, "light throw damage 30 (base)");
    CHECK(damage_for_hold(700) == 60, "full charge damage 60");
    CHECK(damage_for_hold(425) == 45, "half charge damage 45");
    CHECK(damage_for_hold(700, 20) == 60, "charged always reaches 60 from any base");
    CHECK(damage_for_hold(150, 20) == 20, "light throw keeps the item base damage");

    // is_charged gate
    CHECK(!is_charged(100), "100ms is a light tap, not charged");
    CHECK(is_charged(150),  "150ms is charged (>= MIN)");
    CHECK(is_charged(700),  "700ms is charged");

    // gib threshold: only a fully-charged (>=60) lethal hit gibs
    CHECK(triggers_gib(60),  "60 dmg gibs");
    CHECK(triggers_gib(75),  "above-threshold gibs");
    CHECK(!triggers_gib(59), "59 dmg does not gib");
    CHECK(!triggers_gib(30), "light throw does not gib");
    CHECK(triggers_gib(damage_for_hold(700)), "a full-charge throw gibs on kill");
    CHECK(!triggers_gib(damage_for_hold(150)), "a light throw does not gib on kill");

    std::printf("[throwable] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
