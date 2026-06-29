// ParryChainTracker.h — tracks consecutive parries within a decaying window.
//
// Ported 1:1 from Godot scripts/combat/ParryChainTracker.gd.
//
// WHAT THIS DOES IN PLAIN ENGLISH:
// The directional-combat redesign rewards reading-the-fight. Land parries in
// quick succession and the endurance cost of parrying drops to zero — each
// chained parry refunds its own cost, so a clean read costs nothing. But the
// window to keep the chain alive TIGHTENS as it grows: you have to keep reading
// the enemy, not just mash the parry button.
//
// In Godot this was a plain RefCounted owned by MeleeHandler. Here it is a tiny
// pure-logic struct. Time is INJECTED: tick(dt) advances the decay window by the
// seconds the caller passes — Core never reads a clock, so the headless harness
// can drive an exact timeline.
//
// WINDOW SCHEDULE (per design — verified against the GDScript _WINDOW_BY_CHAIN):
//     chain 1  -> 1.0 s to land the next parry
//     chain 2  -> 0.7 s
//     chain 3  -> 0.5 s
//     chain 4+ -> stays at 0.5 s
//   Missing within the window = the chain breaks (the next parry resets to 1).
//
// REFUND RULE: chain count >= 2 refunds the full endurance cost (net zero EP).
// The first parry pays normally; the chain is the reward for the successive
// reads. should_refund_endurance() reports exactly that threshold.

#pragma once

namespace mira {

class ParryChainTracker {
public:
    // Window-by-chain schedule. Index 0 is a placeholder so the chain count
    // indexes directly (chain 1 -> [1] = 1.0 s). The last entry covers "4 and
    // beyond". These values are load-bearing — they match _WINDOW_BY_CHAIN in
    // the GDScript exactly: {0.0, 1.0, 0.7, 0.5, 0.5}.
    static constexpr float WINDOW_BY_CHAIN[5] = {
        0.0f,  // 0: no chain active (placeholder so the index lines up)
        1.0f,  // 1
        0.7f,  // 2
        0.5f,  // 3
        0.5f,  // 4+
    };
    static constexpr int WINDOW_TABLE_SIZE = 5;

    ParryChainTracker() = default;

    // Call right after a SUCCESSFUL parry. Bumps the chain and reopens the
    // window (tighter the higher the chain). Returns the new chain count, same
    // as the GDScript register_parry().
    int register_parry() {
        _current_chain_count += 1;
        _window_remaining = window_for_chain(_current_chain_count);
        return _current_chain_count;
    }

    // Explicit break — a missed parry or a landed enemy hit. Cheaper than
    // waiting for the window to time out. Mirrors break_chain().
    void break_chain() {
        _current_chain_count = 0;
        _window_remaining = 0.0f;
    }

    // Advance the decay window by `delta` seconds (INJECTED time). When the
    // window hits zero the chain auto-breaks. No-op while no chain is active,
    // exactly like the GDScript tick().
    void tick(float delta) {
        if (_current_chain_count <= 0) {
            return;
        }
        _window_remaining -= delta;
        if (_window_remaining <= 0.0f) {
            break_chain();
        }
    }

    // True for chained parries (count >= 2) — MeleeHandler refunds the full
    // endurance cost. Matches should_refund_endurance().
    bool should_refund_endurance() const { return _current_chain_count >= 2; }

    // Exposed for the HUD chain-count label.
    int current_chain_count() const { return _current_chain_count; }

    // Exposed for tests / HUD timing readouts; not in the GDScript public API
    // but harmless and useful for asserting the decay timeline.
    float window_remaining() const { return _window_remaining; }

private:
    // Window for a given chain, clamped to the table the same way the GDScript
    // _window_for_chain() did: chain <= 0 -> 0, chain past the table -> last entry.
    static float window_for_chain(int chain) {
        if (chain <= 0) {
            return 0.0f;
        }
        if (chain >= WINDOW_TABLE_SIZE) {
            return WINDOW_BY_CHAIN[WINDOW_TABLE_SIZE - 1];
        }
        return WINDOW_BY_CHAIN[chain];
    }

    int   _current_chain_count = 0;
    float _window_remaining    = 0.0f;
};

} // namespace mira
