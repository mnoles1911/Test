// test_combat.cpp — standalone parity harness for the ported directional-combat
// Core: MouseDirectionSampler, ParryChainTracker, EnemyAttackPool.
//
// COMPILE + RUN (either works):
//   cd /home/user/Test/ue5/MiraThal/tests/standalone && ./build.sh combat
// or directly:
//   clang++ -std=c++17 -O2 -Wall -Wextra -Wshadow \
//     -I /home/user/Test/ue5/MiraThal/Source/MiraThalCore/Public \
//     -I /home/user/Test/ue5/MiraThal/Source/MiraThalVoxel/Public \
//     test_combat.cpp -o test_combat.run && ./test_combat.run
//
// This is one self-contained program (its own main). It mirrors the print style
// of tests/standalone/test_main.cpp: each selector prints PASS/FAIL and main
// returns 0 only if every check passed.

#include <cstdio>
#include <string>

#include "Core/MouseDirectionSampler.h"
#include "Core/ParryChainTracker.h"
#include "Core/EnemyAttackPool.h"

// ---------------------------------------------------------------------------
// Minimal assertion plumbing (matches test_main.cpp's CHECK macro / counters).
// ---------------------------------------------------------------------------
static int g_checks = 0;
static int g_fails  = 0;
static std::string g_current;

#define CHECK(cond, msg)                                                        \
    do {                                                                        \
        ++g_checks;                                                             \
        if (!(cond)) {                                                          \
            ++g_fails;                                                          \
            std::printf("  FAIL [%s] %s  (%s:%d)\n",                            \
                        g_current.c_str(), (msg), __FILE__, __LINE__);          \
        }                                                                       \
    } while (0)

// ---------------------------------------------------------------------------
// Part 1: MouseDirectionSampler — flicks resolve to the right of 4 directions.
//
// Designer model: "flick TOWARD where the sword comes FROM." Screen +y is DOWN.
//   flick UP    (dy<0) -> Overhead
//   flick DOWN  (dy>0) -> Thrust
//   flick LEFT  (dx<0) -> Right  (left-originating sweep -> DIR_RIGHT enum)
//   flick RIGHT (dx>0) -> Left   (right-originating sweep -> DIR_LEFT enum)
// Plus a no-motion / ambiguous case that must resolve to None.
// ---------------------------------------------------------------------------
using mira::MeleeDir;
using mira::MouseDirectionSampler;

// Helper: feed one decisive flick as a handful of samples inside the window,
// then read the resolved direction. dt per sample stays well under WINDOW.
static MeleeDir flick(float total_dx, float total_dy) {
    MouseDirectionSampler s;
    const int n = 4;
    for (int i = 0; i < n; ++i) {
        // 0.02 s per sample -> 0.08 s total, comfortably inside the 0.12 s window.
        s.push(total_dx / n, total_dy / n, 0.02f);
    }
    return s.sample();
}

static void sel_mouse() {
    // Decisive vertical flicks. 200 px total magnitude >> 60 px MIN_TOTAL_PIXELS.
    CHECK(flick(0.0f, -200.0f) == MeleeDir::Overhead, "flick UP -> Overhead");
    CHECK(flick(0.0f,  200.0f) == MeleeDir::Thrust,   "flick DOWN -> Thrust");
    // Decisive horizontal flicks (note the deliberate enum swap).
    CHECK(flick(-200.0f, 0.0f) == MeleeDir::Right, "flick LEFT -> Right enum");
    CHECK(flick( 200.0f, 0.0f) == MeleeDir::Left,  "flick RIGHT -> Left enum");

    // Diagonal but vertical-dominant -> vertical wins (10-degree overlap implicit).
    CHECK(flick(40.0f, -200.0f) == MeleeDir::Overhead, "up-ish diagonal -> Overhead");
    // Horizontal-dominant diagonal -> horizontal wins, and the >= tie-break.
    CHECK(flick(200.0f, 40.0f) == MeleeDir::Left, "right-ish diagonal -> Left");

    // AMBIGUOUS / NO-MOTION: tiny total magnitude below MIN_TOTAL_PIXELS -> None.
    CHECK(flick(5.0f, 5.0f) == MeleeDir::None, "sub-threshold flick -> None");
    {
        // Empty sampler (no pushes at all) is also None.
        MouseDirectionSampler empty;
        CHECK(empty.sample() == MeleeDir::None, "empty window -> None");
        CHECK(empty.is_empty(), "fresh sampler reports empty");
    }
    {
        // Window decay: a flick that has aged past WINDOW_SECONDS leaves the
        // window empty on the next push, so the old motion no longer counts.
        MouseDirectionSampler s;
        s.push(-200.0f, 0.0f, 0.0f);          // big left flick at t=0
        CHECK(s.sample() == MeleeDir::Right, "fresh left flick reads Right");
        // Push a tiny sample 0.2 s later — that prunes the old big one out.
        s.push(1.0f, 0.0f, 0.20f);
        CHECK(s.sample() == MeleeDir::None, "aged-out flick decays to None");
    }
}

// ---------------------------------------------------------------------------
// Part 2: ParryChainTracker — chain builds, refund at >=2, window decays.
// Window schedule: chain1=1.0s, chain2=0.7s, chain3=0.5s, chain4+=0.5s.
// ---------------------------------------------------------------------------
using mira::ParryChainTracker;

static void sel_parry() {
    ParryChainTracker t;

    // First parry: chain 1, no refund yet, window opens at 1.0 s.
    CHECK(t.register_parry() == 1, "first parry -> chain 1");
    CHECK(!t.should_refund_endurance(), "chain 1 does NOT refund");
    CHECK(t.window_remaining() > 0.999f && t.window_remaining() < 1.001f,
          "chain 1 window is 1.0 s");

    // Tick within the window, parry again before it lapses -> chain 2 + refund.
    t.tick(0.5f);  // 0.5 s elapsed, 0.5 s left
    CHECK(t.current_chain_count() == 1, "still chain 1 mid-window");
    CHECK(t.register_parry() == 2, "second parry in window -> chain 2");
    CHECK(t.should_refund_endurance(), "chain 2 REFUNDS endurance");
    CHECK(t.window_remaining() > 0.699f && t.window_remaining() < 0.701f,
          "chain 2 window tightens to 0.7 s");

    // Third parry -> chain 3, window 0.5 s.
    t.tick(0.3f);
    CHECK(t.register_parry() == 3, "third parry -> chain 3");
    CHECK(t.window_remaining() > 0.499f && t.window_remaining() < 0.501f,
          "chain 3 window tightens to 0.5 s");

    // Fourth+ parry stays at 0.5 s.
    t.tick(0.2f);
    CHECK(t.register_parry() == 4, "fourth parry -> chain 4");
    CHECK(t.window_remaining() > 0.499f && t.window_remaining() < 0.501f,
          "chain 4+ window stays 0.5 s");

    // DECAY: let the window lapse without a parry -> chain auto-breaks to 0.
    t.tick(0.6f);  // > 0.5 s window -> break
    CHECK(t.current_chain_count() == 0, "lapsed window breaks the chain");
    CHECK(!t.should_refund_endurance(), "broken chain no longer refunds");
    CHECK(t.window_remaining() <= 0.0001f, "broken chain has no window left");

    // After a break, the next parry resets to chain 1 (no refund).
    CHECK(t.register_parry() == 1, "post-break parry resets to chain 1");
    CHECK(!t.should_refund_endurance(), "reset chain 1 does not refund");

    // Explicit break_chain() also clears everything immediately.
    t.register_parry();  // chain 2
    CHECK(t.should_refund_endurance(), "chain 2 again refunds");
    t.break_chain();
    CHECK(t.current_chain_count() == 0, "explicit break clears chain");
}

// ---------------------------------------------------------------------------
// Part 3: EnemyAttackPool — seeded deterministic READY->WINDUP->STRIKE->
// RECOVERY, committed_attack fires exactly once at WINDUP, stagger interrupts.
//
// Goblin pool (verbatim from scripts/enemies/Goblin.gd _ATTACK_POOL_CONFIG):
//   jab        w0.50 dir THRUST(3)   windup0.45 strike0.10 recovery0.40 parryable
//   swing_left w0.18 dir LEFT(1)     windup0.60 strike0.10 recovery0.45 parryable
//   swing_rght w0.17 dir RIGHT(2)    windup0.60 strike0.10 recovery0.45 parryable
//   leap       w0.15 dir OVERHEAD(0) windup0.75 strike0.12 recovery0.55 UNBLOCKABLE
// ---------------------------------------------------------------------------
using mira::AttackOption;
using mira::AttackState;
using mira::EnemyAttackPool;

static std::vector<AttackOption> goblin_pool() {
    // {direction, weight, is_unblockable, windup, strike_window, recovery}
    return {
        AttackOption{ /*dir*/3, 0.50f, false, 0.45f, 0.10f, 0.40f }, // jab/THRUST
        AttackOption{ /*dir*/1, 0.18f, false, 0.60f, 0.10f, 0.45f }, // swing_left
        AttackOption{ /*dir*/2, 0.17f, false, 0.60f, 0.10f, 0.45f }, // swing_right
        AttackOption{ /*dir*/0, 0.15f, true,  0.75f, 0.12f, 0.55f }, // leap (unblockable)
    };
}

// Look up the option matching a committed direction so we can assert the
// strike/recovery timeline that direction implies.
static AttackOption option_for_dir(int dir) {
    for (const AttackOption& o : goblin_pool()) if (o.direction == dir) return o;
    return AttackOption{};
}

static void sel_enemy() {
    EnemyAttackPool pool;
    pool.set_attack_pool(goblin_pool());
    pool.set_attack_cooldown(0.8f);  // Goblin host set 0.8 s
    mira::Rng rng(12345);            // SEEDED -> reproducible attack sequence

    // Starts READY.
    CHECK(pool.state() == AttackState::Ready, "starts READY");
    CHECK(!pool.committed_attack().fired, "no commit before first windup");
    CHECK(pool.velocity_scale() > 0.999f, "READY -> full move speed");

    // Player out of range: advancing must NOT start a windup.
    pool.advance(0.1f, rng, /*player_in_range*/false);
    CHECK(pool.state() == AttackState::Ready, "out of range stays READY");
    CHECK(!pool.committed_attack().fired, "out of range fires no commit");

    // Player IN range: the next advance commits an attack and enters WINDUP.
    pool.advance(0.016f, rng, /*player_in_range*/true);
    CHECK(pool.state() == AttackState::Windup, "in range -> WINDUP");
    CHECK(pool.committed_attack().fired, "committed_attack FIRES on WINDUP entry");

    // Capture the committed attack and verify it's a real pool entry.
    const int committed_dir = pool.committed_attack().direction;
    const AttackOption chosen = option_for_dir(committed_dir);
    CHECK(committed_dir == 0 || committed_dir == 1 || committed_dir == 2 || committed_dir == 3,
          "committed direction is one of the 4 cardinals");
    CHECK(pool.committed_attack().time_to_impact > 0.0f, "time_to_impact > 0");
    // time_to_impact == that option's windup duration.
    CHECK(pool.committed_attack().time_to_impact > chosen.windup - 0.001f &&
          pool.committed_attack().time_to_impact < chosen.windup + 0.001f,
          "time_to_impact == chosen windup duration");
    CHECK(pool.committed_attack().is_unblockable == chosen.is_unblockable,
          "committed unblockable flag matches the chosen option");
    CHECK(pool.velocity_scale() < 0.999f, "WINDUP -> slowed move speed");

    // The committed pulse is ONE FRAME: the very next advance (still winding up)
    // must NOT re-fire it.
    pool.advance(0.016f, rng, true);
    CHECK(pool.state() == AttackState::Windup, "still WINDUP next frame");
    CHECK(!pool.committed_attack().fired, "committed_attack fires only ONCE");

    // Drive past the windup -> STRIKE.
    float t = 0.016f + 0.016f;  // time already spent in windup
    while (pool.state() == AttackState::Windup && t < chosen.windup + 1.0f) {
        pool.advance(0.05f, rng, true);
        t += 0.05f;
    }
    CHECK(pool.state() == AttackState::Strike, "windup elapses -> STRIKE");

    // Drive past the strike window -> RECOVERY.
    int guard = 0;
    while (pool.state() == AttackState::Strike && guard++ < 100) {
        pool.advance(0.05f, rng, true);
    }
    CHECK(pool.state() == AttackState::Recovery, "strike elapses -> RECOVERY");

    // Drive past recovery -> back to READY (now carrying the 0.8 s cooldown).
    guard = 0;
    while (pool.state() == AttackState::Recovery && guard++ < 100) {
        pool.advance(0.05f, rng, true);
    }
    CHECK(pool.state() == AttackState::Ready, "recovery elapses -> READY");

    // The post-attack cooldown blocks an immediate re-windup even in range.
    pool.advance(0.1f, rng, true);
    CHECK(pool.state() == AttackState::Ready, "cooldown blocks immediate re-windup");

    // STAGGER INTERRUPT: force another windup, then stagger mid-swing.
    guard = 0;
    while (pool.state() == AttackState::Ready && guard++ < 100) {
        pool.advance(0.1f, rng, true);  // burns cooldown, then commits
    }
    CHECK(pool.state() == AttackState::Windup, "re-enters WINDUP after cooldown");
    pool.apply_stagger(0.5f);
    CHECK(pool.state() == AttackState::Staggered, "stagger interrupts to STAGGERED");
    CHECK(pool.is_locked_out(), "STAGGERED reports locked out");
    CHECK(pool.velocity_scale() <= 0.0001f, "STAGGERED -> frozen (0 move speed)");

    // Stagger counts down then returns to READY.
    guard = 0;
    while (pool.state() == AttackState::Staggered && guard++ < 100) {
        pool.advance(0.1f, rng, true);
    }
    CHECK(pool.state() == AttackState::Ready, "stagger elapses -> READY");

    // DETERMINISM: a second pool driven by the SAME seed picks the SAME first
    // attack direction — proving the seeded RNG reproduces the sequence.
    {
        EnemyAttackPool a, b;
        a.set_attack_pool(goblin_pool());
        b.set_attack_pool(goblin_pool());
        mira::Rng ra(999), rb(999);
        a.advance(0.016f, ra, true);
        b.advance(0.016f, rb, true);
        CHECK(a.committed_attack().fired && b.committed_attack().fired,
              "both seeded pools commit");
        CHECK(a.committed_attack().direction == b.committed_attack().direction,
              "same seed -> same committed direction (determinism)");
    }
}

// ---------------------------------------------------------------------------
int main() {
    struct Sel { const char* name; void (*fn)(); };
    const Sel sels[] = {
        {"mouse", sel_mouse},
        {"parry", sel_parry},
        {"enemy", sel_enemy},
    };
    for (const Sel& s : sels) {
        g_current = s.name;
        const int before = g_fails;
        s.fn();
        std::printf("  [%-6s] %s\n", s.name, (g_fails == before) ? "ok" : "FAIL");
    }

    std::printf("%d checks, %d failure(s)\n", g_checks, g_fails);
    if (g_fails == 0) {
        std::printf("[combat  ] PASS\n");
        return 0;
    }
    std::printf("[combat  ] FAIL\n");
    return 1;
}
