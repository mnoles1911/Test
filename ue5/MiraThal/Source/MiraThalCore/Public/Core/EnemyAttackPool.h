// EnemyAttackPool.h — directional attack state machine for a single enemy.
//
// Ported from Godot scripts/enemies/EnemyAttackPool.gd (the per-enemy windup ->
// strike -> recovery state machine) PLUS the attack-pool config that the Goblin
// host set on it (scripts/enemies/Goblin.gd _ATTACK_POOL_CONFIG). In the Godot
// build the state machine lived in EnemyAttackPool and the WEIGHTS/DURATIONS were
// data the species subclass injected; here we keep the same split — you build a
// pool of AttackOption entries (the test uses the Goblin numbers verbatim) and
// hand them to the machine.
//
// WHAT THIS DOES IN PLAIN ENGLISH:
// One enemy decides WHEN to swing and WHICH WAY. It cycles through five states:
//
//     READY      — idle, eligible to start a new windup (after its cooldown).
//     WINDUP     — telegraph is up. On ENTRY it commits to an attack: it picks a
//                  direction + duration from the weighted pool and "fires" a
//                  committed_attack event so the player's parry window can open.
//     STRIKE     — the brief active-hit window (one overlap test in the game).
//     RECOVERY   — short cooldown after the swing; can't immediately re-swing.
//     STAGGERED  — locked out, e.g. by a successful player parry. Waits out a
//                  stagger timer then returns to READY.
//
// TWO PLACES C++ DIVERGES FROM THE GDSCRIPT (on purpose):
//
//  1. SIGNALS -> POLLED STRUCT. Godot emitted `committed_attack(direction,
//     time_to_impact, is_unblockable)` as a signal at WINDUP entry. Core has no
//     signals, so advance() returns a small optional event: when it transitions
//     INTO windup it flags `committed` and fills `committed_attack` with the same
//     three fields. The caller polls it. It fires EXACTLY ONCE per attack — only
//     on the READY->WINDUP edge, never again while winding up.
//
//  2. TIME IS INJECTED + RNG IS SEEDED. The GDScript read randf() and ticked on
//     the engine clock. Here advance(dt) takes the seconds elapsed, and the
//     weighted pick draws from a caller-owned mira::Rng&. Same seed -> same
//     sequence of attacks, so the headless harness asserts real behaviour.
//
// The host-world bits the GDScript also did — distance/range gating, material
// tinting, dealing damage through the player's MeleeHandler — are NOT in Core.
// Those touch the scene and belong in the UE wrapper. Core owns only the timing
// + selection logic, which is what has to stay parity-identical across engines.

#pragma once

#include <vector>

#include "Core/Rng.h"
#include "Core/MouseDirectionSampler.h"  // for MeleeDir (direction enum)

namespace mira {

// One row of the weighted attack table. Mirrors the Dictionary entries the
// Godot host built in Goblin._ATTACK_POOL_CONFIG:
//   { id, weight, is_unblockable, direction, windup, strike_window, recovery }
// `weight`s need not sum to 1.0 — the pick normalises by the running total, same
// as the GDScript _pick_weighted(). `direction < 0` means "roll a random one of
// the four cardinals at commit time" (the GDScript `randi() % 4` fallback).
struct AttackOption {
    int   direction      = -1;     // MeleeDir value, or < 0 = random at commit
    float weight         = 1.0f;   // relative selection weight
    bool  is_unblockable = false;  // red telegraph; parry won't save you
    float windup         = 0.6f;   // seconds of telegraph before the strike
    float strike_window  = 0.10f;  // seconds the hit is "live"
    float recovery       = 0.40f;  // seconds of post-swing cooldown
};

// The five states, values pinned to the GDScript enum order
// (READY=0, WINDUP=1, STRIKE=2, RECOVERY=3, STAGGERED=4).
enum class AttackState : int {
    Ready     = 0,
    Windup    = 1,
    Strike    = 2,
    Recovery  = 3,
    Staggered = 4,
};

// The "committed_attack" payload, modelled as a polled struct instead of a
// signal. `fired` is true on exactly the frame the machine entered WINDUP.
struct CommittedAttack {
    bool fired = false;          // true only on the READY->WINDUP edge this advance()
    int  direction = -1;         // MeleeDir the attack will land as
    float time_to_impact = 0.0f; // == the chosen windup duration (parry window length)
    bool is_unblockable = false; // matches the chosen option's flag
};

class EnemyAttackPool {
public:
    // Cooldown between finishing one attack (RECOVERY/STAGGER end) and being
    // eligible to wind up the next. The Goblin host set 0.8 s; default mirrors
    // the GDScript's own 0.6 s @export default. Designer-tunable per species.
    EnemyAttackPool() = default;

    // Configure the weighted pool. Pass the species' attack rows (the test uses
    // the four Goblin rows verbatim). Copies them in.
    void set_attack_pool(std::vector<AttackOption> pool) { _pool = std::move(pool); }

    // Cooldown after an attack before the next windup may start (Goblin: 0.8 s).
    void set_attack_cooldown(float seconds) { _attack_cooldown = seconds; }

    // ---- State queries (the host reads these) -------------------------------
    AttackState state() const { return _state; }
    bool is_locked_out() const { return _state == AttackState::Staggered; }

    // Per-frame velocity scalar the host applies to its walk speed, mirroring
    // velocity_scale() in the GDScript: full speed while READY, frozen while
    // STAGGERED, slowed during the swing states.
    float velocity_scale() const {
        if (_state == AttackState::Ready)     return 1.0f;
        if (_state == AttackState::Staggered) return 0.0f;
        return _movement_scale_during_attack;
    }
    void set_movement_scale_during_attack(float s) { _movement_scale_during_attack = s; }

    // The most recent committed-attack event. `fired` is reset to false at the
    // top of every advance() and set true only on a fresh READY->WINDUP edge, so
    // the caller can poll it once per frame and react exactly once per attack.
    const CommittedAttack& committed_attack() const { return _committed; }

    // ---- Driving the machine ------------------------------------------------

    // Apply a stagger (e.g. the player landed a parry). The host called this via
    // its _stagger_remaining mirror in the GDScript; here it's an explicit call.
    // Snaps the machine into STAGGERED and arms the lockout timer. While
    // STAGGERED, advance() counts this down before returning to READY.
    void apply_stagger(float stagger_seconds) {
        _state = AttackState::Staggered;
        _state_remaining = stagger_seconds;
        // The committed event is one-shot; clear it so a stale "fired" can't leak.
        _committed.fired = false;
    }

    // Advance the state machine by `dt` seconds. `rng` is used only on the
    // READY->WINDUP edge (the weighted pick + the random-direction fallback), so
    // a given seed reproduces the same attack sequence. `player_in_range` gates
    // whether READY may start a new windup — the GDScript checked actual world
    // distance; here the caller passes the boolean result of that check.
    void advance(float dt, Rng& rng, bool player_in_range) {
        // The committed event is a one-frame pulse — clear it every advance and
        // only re-raise it if we cross the READY->WINDUP edge this call.
        _committed.fired = false;

        switch (_state) {
            case AttackState::Ready:     tick_ready(dt, rng, player_in_range); break;
            case AttackState::Windup:    tick_windup(dt);    break;
            case AttackState::Strike:    tick_strike(dt);    break;
            case AttackState::Recovery:  tick_recovery(dt);  break;
            case AttackState::Staggered: tick_staggered(dt); break;
        }
    }

private:
    // READY: burn the post-attack cooldown first, then — if the player is in
    // range and the pool isn't empty — commit to an attack and enter WINDUP.
    void tick_ready(float dt, Rng& rng, bool player_in_range) {
        if (_ready_cooldown_remaining > 0.0f) {
            _ready_cooldown_remaining -= dt;
            if (_ready_cooldown_remaining < 0.0f) _ready_cooldown_remaining = 0.0f;
            return;
        }
        if (!player_in_range || _pool.empty()) {
            return;
        }

        // Pick a weighted attack (same normalise-by-running-total as the
        // GDScript _pick_weighted), resolving a random direction if asked.
        const AttackOption& opt = pick_weighted(rng);
        int dir = opt.direction;
        if (dir < 0) {
            // GDScript: randi() % 4 over the four cardinals.
            dir = rng.next_int(4);
        }

        _current_direction     = dir;
        _current_is_unblockable = opt.is_unblockable;
        _current_strike_window = opt.strike_window;
        _current_recovery      = opt.recovery;

        // Enter WINDUP — _state_remaining is the windup duration.
        _state_remaining = opt.windup;
        _state = AttackState::Windup;

        // Fire the committed_attack event (the signal in the GDScript). Exactly
        // once, here on the entry edge. time_to_impact == windup duration.
        _committed.fired          = true;
        _committed.direction      = dir;
        _committed.time_to_impact = opt.windup;
        _committed.is_unblockable = opt.is_unblockable;
    }

    // WINDUP: count down; when the telegraph ends, snap to STRIKE.
    void tick_windup(float dt) {
        _state_remaining -= dt;
        if (_state_remaining > 0.0f) return;
        _state = AttackState::Strike;
        _state_remaining = _current_strike_window;
        // (The single overlap test / damage happens in the host wrapper.)
    }

    // STRIKE: count down the active-hit window, then into RECOVERY.
    void tick_strike(float dt) {
        _state_remaining -= dt;
        if (_state_remaining > 0.0f) return;
        _state = AttackState::Recovery;
        _state_remaining = _current_recovery;
    }

    // RECOVERY: count down, then back to READY with the inter-attack cooldown.
    void tick_recovery(float dt) {
        _state_remaining -= dt;
        if (_state_remaining > 0.0f) return;
        _state = AttackState::Ready;
        _ready_cooldown_remaining = _attack_cooldown;
    }

    // STAGGERED: count down the lockout, then back to READY with a cooldown so
    // the enemy doesn't swing the instant the stagger ends (matches GDScript).
    void tick_staggered(float dt) {
        _state_remaining -= dt;
        if (_state_remaining > 0.0f) return;
        _state = AttackState::Ready;
        _ready_cooldown_remaining = _attack_cooldown;
    }

    // Weighted pick over the pool. Normalise by the running total (weights need
    // not sum to 1). Mirrors _pick_weighted: r = randf() * total, walk the pool
    // accumulating, return the first entry whose running sum reaches r.
    const AttackOption& pick_weighted(Rng& rng) {
        float total = 0.0f;
        for (const AttackOption& e : _pool) total += e.weight;
        if (total <= 0.0f) return _pool.front();

        const float r = rng.next_float() * total;
        float acc = 0.0f;
        for (const AttackOption& e : _pool) {
            acc += e.weight;
            if (r <= acc) return e;
        }
        return _pool.back();
    }

    std::vector<AttackOption> _pool;

    AttackState _state = AttackState::Ready;
    float _state_remaining          = 0.0f;  // countdown within the current state
    float _ready_cooldown_remaining = 0.0f;  // between attacks
    float _attack_cooldown          = 0.6f;  // GDScript @export default
    float _movement_scale_during_attack = 0.15f;  // GDScript @export default

    // The currently-committed attack's carried fields (chosen at WINDUP entry).
    int   _current_direction      = static_cast<int>(MeleeDir::Right);
    bool  _current_is_unblockable = false;
    float _current_strike_window  = 0.10f;
    float _current_recovery       = 0.40f;

    CommittedAttack _committed;
};

} // namespace mira
