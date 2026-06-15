// test_skills.cpp — standalone parity harness for the skill XP curve + routing.
//
// Covers the engine-agnostic Core port of the Godot skill system:
//   MiraThalCore/Public/Core/SkillProgression.h  (curve + per-skill bookkeeping)
//   MiraThalCore/Public/Core/CombatXPRouter.h     (event -> (skill, xp) routing)
// ported from scripts/skills/{SkillCurve,SkillManager,CombatXPRouter}.gd.
//
// WHY THIS EXISTS:
// Unreal can't build in the dev container, but the Core layer is pure C++17 with
// no engine headers, so it compiles + runs HERE under clang. This is the
// iterative verification loop for the port's load-bearing math, mirroring the
// Godot headless gate: the `skills` selector goes green before the port is done.
//
// COMPILE / RUN (build.sh auto-discovers every Core source across all modules):
//   cd tests/standalone && ./build.sh skills
// Exit 0 = PASS, non-zero = FAIL. Prints "[skills  ] PASS"/"FAIL" like the
// other harnesses (see test_main.cpp for the print style).

#include <cstdio>
#include <string>

#include "Core/SkillProgression.h"
#include "Core/CombatXPRouter.h"

// ----------------------------------------------------------------------------
// Minimal assertion plumbing (no gtest — keep the loop zero-setup), same shape
// as test_main.cpp's CHECK macros.
// ----------------------------------------------------------------------------
static int g_checks = 0;
static int g_fails  = 0;

#define CHECK(cond, msg)                                                        \
    do {                                                                        \
        ++g_checks;                                                             \
        if (!(cond)) {                                                          \
            ++g_fails;                                                          \
            std::printf("  FAIL [skills] %s  (%s:%d)\n",                        \
                        (msg), __FILE__, __LINE__);                             \
        }                                                                       \
    } while (0)

#define CHECK_EQ(a, b, msg)                                                     \
    do {                                                                        \
        ++g_checks;                                                             \
        if (!((a) == (b))) {                                                    \
            ++g_fails;                                                          \
            std::printf("  FAIL [skills] %s  expected=%lld got=%lld  (%s:%d)\n",\
                        (msg), (long long)(b), (long long)(a),                  \
                        __FILE__, __LINE__);                                    \
        }                                                                       \
    } while (0)

// A small float comparison helper for the curve checks (the curve works in
// double; we compare to a tolerance rather than exact bits).
static bool approx(double a, double b, double tol = 1e-6) {
    double d = a - b;
    if (d < 0) d = -d;
    return d <= tol;
}

// ----------------------------------------------------------------------------
// 1. The curve: exact anchor points + strict monotonicity.
// ----------------------------------------------------------------------------
static void test_curve() {
    using SC = mira::SkillCurve;

    // Curve constants carried from SkillCurve.gd.
    CHECK_EQ(SC::MAX_LEVEL, 100, "MAX_LEVEL is 100");
    CHECK_EQ(SC::MIN_LEVEL, 1, "MIN_LEVEL is 1");

    // Exact anchor points from xp_to_next_level(L) = 25 * L^1.95.
    //   L1->L2 = 25 * 1^1.95          = 25.0
    //   L2->L3 = 25 * 2^1.95          ~ 96.5936...
    //   L99->L100 = 25 * 99^1.95      ~ 194728.105...
    CHECK(approx(SC::xp_to_next_level(1), 25.0), "L1->L2 costs exactly 25 XP");
    CHECK(approx(SC::xp_to_next_level(2), 96.59363289248455, 1e-6),
          "L2->L3 ~ 96.59 XP");
    CHECK(approx(SC::xp_to_next_level(99), 194728.10527366571, 1e-3),
          "L99->L100 ~ 194728 XP");

    // At and above the cap the curve yields 0 (no further XP accepted).
    CHECK(approx(SC::xp_to_next_level(100), 0.0), "cap costs 0 (no next level)");
    CHECK(approx(SC::xp_to_next_level(150), 0.0), "above cap also costs 0");

    // Below MIN_LEVEL the curve floors to L1's cost (max(level, MIN_LEVEL)).
    CHECK(approx(SC::xp_to_next_level(0), 25.0), "level 0 floors to L1 cost");

    // STRICT MONOTONICITY: the per-level cost strictly increases over 1..99, so
    // the total banked XP is a strictly increasing function of level. This is
    // exactly what the Godot `skills` gate asserts.
    double prev = -1.0;
    for (int L = 1; L < SC::MAX_LEVEL; ++L) {
        double c = SC::xp_to_next_level(L);
        CHECK(c > prev, "per-level cost strictly increases");
        prev = c;
    }

    // total_xp_to_reach is the running sum; reaching L1 needs 0; reaching L5 is
    // the sum of L1..L4 costs (~707.78).
    CHECK(approx(SC::total_xp_to_reach(1), 0.0), "reaching L1 needs 0 XP");
    CHECK(approx(SC::total_xp_to_reach(5), 707.7807646012434, 1e-4),
          "reaching L5 needs ~707.78 XP total");

    // A known total maps to the expected level: bank exactly 707.78 XP from a
    // clean L1 and you land at L5 (the threshold for L5 met to the penny).
    mira::SkillCurve::Applied a =
        SC::apply_xp(1, 0.0, SC::total_xp_to_reach(5));
    CHECK_EQ(a.level, 5, "exactly the L5 total lands at L5");
    CHECK(approx(a.progress, 0.0, 1e-3), "and leftover progress is ~0");

    // Perk milestones: every 4 levels, indices 0..24.
    CHECK_EQ(SC::milestone_for_level(4), 0, "L4 is milestone 0");
    CHECK_EQ(SC::milestone_for_level(8), 1, "L8 is milestone 1");
    CHECK_EQ(SC::milestone_for_level(100), 24, "L100 is milestone 24");
    CHECK_EQ(SC::milestone_for_level(5), -1, "non-multiple-of-4 is no milestone");
    CHECK_EQ(SC::milestones_unlocked(100), 25, "L100 has unlocked 25 milestones");
}

// ----------------------------------------------------------------------------
// 2. add_xp: accumulation, level-up thresholds, progress reporting, cap.
// ----------------------------------------------------------------------------
static void test_add_xp() {
    mira::SkillProgression prog;

    // All 12 skills start at L1 / progress 0.
    CHECK_EQ(prog.get_level("sword"), 1, "sword starts at L1");
    CHECK(approx(prog.get_xp_progress("sword"), 0.0), "sword starts with 0 progress");

    // A sub-threshold grant accumulates without leveling. L1->L2 needs 25, so
    // a 24 grant stays L1 with progress 24, and reports no level-up.
    auto r1 = prog.add_xp("sword", 24.0);
    CHECK(r1.accepted, "24 XP accepted");
    CHECK_EQ(r1.new_level, 1, "still L1 after 24 XP");
    CHECK(!r1.leveled_up, "no level-up below threshold");
    CHECK(approx(r1.new_progress, 24.0), "progress banked at 24");
    CHECK(approx(prog.get_xp_progress("sword"), 24.0), "state holds 24 progress");

    // One more point crosses exactly the 25-XP threshold -> L2, progress rolls
    // to 0 (24 + 1 - 25 = 0). This is the precise level-up boundary.
    auto r2 = prog.add_xp("sword", 1.0);
    CHECK(r2.leveled_up, "crossing 25 total levels up");
    CHECK_EQ(r2.old_level, 1, "reported old level is 1");
    CHECK_EQ(r2.new_level, 2, "reported new level is 2");
    CHECK_EQ(r2.levels_gained, 1, "gained exactly one level");
    CHECK(approx(r2.new_progress, 0.0), "leftover progress is 0 at the boundary");
    CHECK_EQ(prog.get_level("sword"), 2, "state now at L2");

    // A huge grant can jump multiple levels at once (the apply_xp while-loop).
    mira::SkillProgression prog2;
    auto rbig = prog2.add_xp("mining", 1000.0);
    CHECK(rbig.levels_gained >= 2, "1000 XP jumps several levels at once");
    CHECK_EQ(rbig.old_level, 1, "big-grant old level is 1");
    CHECK(rbig.new_level > 1, "big-grant new level above 1");
    // milestones_hit should equal how many multiples of 4 the jump crossed.
    int expect_ms = rbig.new_level / 4;  // from L1, multiples of 4 reached
    CHECK_EQ(rbig.milestones_hit, expect_ms, "milestones-hit matches 4-level crossings");

    // Non-positive grants are ignored (no-op, not accepted).
    auto rzero = prog2.add_xp("mining", 0.0);
    CHECK(!rzero.accepted, "0 XP is a no-op");
    auto rneg = prog2.add_xp("mining", -50.0);
    CHECK(!rneg.accepted, "negative XP is a no-op");

    // Unknown skills are dropped (Godot push_warns; Core just reports not-accepted).
    auto runk = prog2.add_xp("flying", 100.0);
    CHECK(!runk.accepted, "unknown skill XP is dropped");
}

// ----------------------------------------------------------------------------
// 3. MAX_LEVEL cap: a skill at 100 banks no more XP and progress stays 0.
// ----------------------------------------------------------------------------
static void test_cap() {
    mira::SkillProgression prog;

    // Slam a skill to the cap directly, then try to feed it more.
    prog.set_state("speech", mira::SkillCurve::MAX_LEVEL, 0.0);
    CHECK_EQ(prog.get_level("speech"), 100, "speech forced to L100");
    CHECK(approx(prog.get_xp_progress("speech"), 0.0), "capped progress is 0");

    auto r = prog.add_xp("speech", 999999.0);
    CHECK(!r.accepted, "capped skill rejects further XP");
    CHECK_EQ(prog.get_level("speech"), 100, "stays at L100");
    CHECK(approx(prog.get_xp_progress("speech"), 0.0), "progress stays 0 at cap");

    // A colossal grant from L1 also caps at 100 with 0 progress (no overflow).
    mira::SkillProgression prog2;
    auto rbig = prog2.add_xp("vitality", 1.0e12);
    CHECK_EQ(rbig.new_level, 100, "1e12 XP caps at L100");
    CHECK(approx(prog2.get_xp_progress("vitality"), 0.0), "no leftover banked at cap");
    CHECK_EQ(rbig.new_progress, 0.0, "reported progress is 0 at cap");
}

// ----------------------------------------------------------------------------
// 4. The 12 canonical skills are all present, in the right ids.
// ----------------------------------------------------------------------------
static void test_twelve_skills() {
    const auto& ids = mira::skill_ids();
    CHECK_EQ((long long)ids.size(), 12ll, "exactly 12 canonical skills");

    // Every expected id must be present and valid.
    const char* expected[12] = {
        "sword", "throwables", "bow",
        "mining", "felling", "excavation", "demolition",
        "lockpicking", "alchemy", "smithing",
        "vitality", "speech",
    };
    for (int i = 0; i < 12; ++i) {
        CHECK(mira::is_valid_skill(expected[i]), "expected skill id is valid");
    }
    CHECK(!mira::is_valid_skill("archery"), "bogus skill id is invalid");

    // A fresh SkillProgression initializes all 12 to L1.
    mira::SkillProgression prog;
    for (int i = 0; i < 12; ++i) {
        CHECK_EQ(prog.get_level(expected[i]), 1, "each canonical skill starts at L1");
    }
}

// ----------------------------------------------------------------------------
// 5. CombatXPRouter: event -> (skill, amount) for the canonical cases.
//    hit 5/5/8, kill 75/75/50, parry 15 (always sword).
// ----------------------------------------------------------------------------
static void test_router() {
    using namespace mira;

    // Sword hit -> ("sword", 5).
    XpGrant sh = combat_xp_for_hit("sword");
    CHECK(sh.skill == "sword", "sword hit credits sword");
    CHECK_EQ(sh.amount, 5, "sword hit grants 5 XP");

    // Sword kill -> ("sword", 75).
    XpGrant sk = combat_xp_for_kill("sword");
    CHECK(sk.skill == "sword", "sword kill credits sword");
    CHECK_EQ(sk.amount, 75, "sword kill grants 75 XP");

    // Throwable kill -> ("throwables", 50).
    XpGrant tk = combat_xp_for_kill("throwables");
    CHECK(tk.skill == "throwables", "throwable kill credits throwables");
    CHECK_EQ(tk.amount, 50, "throwable kill grants 50 XP");

    // A parry -> ("sword", 15), always credited to sword.
    XpGrant p = combat_xp_for_parry();
    CHECK(p.skill == "sword", "parry always credits sword");
    CHECK_EQ(p.amount, 15, "parry grants 15 XP");

    // Spot-check the remaining table entries (bow, throwable hit).
    CHECK_EQ(combat_xp_for_hit("bow").amount, 5, "bow hit grants 5");
    CHECK_EQ(combat_xp_for_kill("bow").amount, 75, "bow kill grants 75");
    CHECK_EQ(combat_xp_for_hit("throwables").amount, 8, "throwable hit grants 8");

    // Unknown weapon skills route 0 XP (the Godot Dictionary.get default).
    CHECK_EQ(combat_xp_for_hit("mining").amount, 0, "non-weapon hit grants 0");
    CHECK_EQ(combat_xp_for_kill("speech").amount, 0, "non-weapon kill grants 0");

    // is_weapon_skill guard (mirrors set_weapon_skill).
    CHECK(is_weapon_skill("sword"), "sword is a weapon skill");
    CHECK(is_weapon_skill("bow"), "bow is a weapon skill");
    CHECK(is_weapon_skill("throwables"), "throwables is a weapon skill");
    CHECK(!is_weapon_skill("mining"), "mining is not a weapon skill");

    // End-to-end: routing a kill through the progression banks the right XP.
    SkillProgression prog;
    XpGrant g = combat_xp_for_kill("sword");
    auto r = prog.add_xp(g.skill, static_cast<double>(g.amount));
    CHECK(r.accepted, "routed sword-kill XP is accepted");
    CHECK(approx(prog.get_xp_progress("sword"), 75.0 - 25.0),
          "75 XP from L1 lands at L2 with 50 progress (75-25)");
    CHECK_EQ(prog.get_level("sword"), 2, "75 XP from a clean L1 reaches L2");
}

int main() {
    test_curve();
    test_add_xp();
    test_cap();
    test_twelve_skills();
    test_router();

    std::printf("[skills  ] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
