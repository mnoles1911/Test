// LodFade.h — the TIMING + POLICY math for LOD-transition cross-fades.
//
// THE JOB (plain English): when a voxel chunk-column swaps from one LOD level to
// another (say the player walked far enough that a near full-res column should
// now draw as a coarser one), the naive thing is to instantly delete the old mesh
// and show the new one. That instant swap "POPS" on screen — the silhouette jumps
// because the two meshes are built independently (each LOD is its own greedy mesh,
// no shared vertices, so we can't smoothly morph one into the other).
//
// To hide that pop we briefly show BOTH meshes at once and DITHER cross-fade
// between them: over a short window (a third of a second or so) the OUTGOING mesh
// fades out and the INCOMING mesh fades in. Each mesh stays OPAQUE (Nanite/Lumen
// friendly) — the fade is a per-pixel dither mask in the material, driven by a
// single 0..1 scalar this file computes. (The material's Dither node is wired up
// separately in-editor; this header only produces the scalar + the policy.)
//
// WHY THE MATH LIVES HERE (and not in the streamer): keeping the curve + the
// "should I even start a fade?" decision in a tiny, engine-free header lets the
// headless clang harness lock the behaviour down (test_lodfade.cpp) so the streamer
// just CALLS these and can't get the timing subtly wrong. No engine types here —
// pure C++17, header-only (all inline), so it compiles in the harness and in UE5
// alike with no .cpp to add to any build list.
//
// THE FADE SCALAR CONTRACT (what the streamer feeds the material):
//   * The INCOMING (new-LOD) mesh is driven with alpha a = fade_alpha(...), going
//     0 -> 1 across the window (fades IN).
//   * The OUTGOING (old-LOD) mesh is driven with (1 - a), going 1 -> 0 (fades OUT).
//   * At a == 1 the fade is done: the outgoing mesh is destroyed and only the new
//     mesh remains (back to a normal single opaque chunk).

#pragma once

namespace mira {
namespace lodfade {

// ---------------------------------------------------------------------------
// fade_alpha — how far through the cross-fade we are, as a smooth 0..1 value.
//
//   elapsed_s   — seconds since the fade started (now - start_time).
//   duration_s  — how long the whole fade lasts (e.g. 0.35 s).
//
// Returns a clamped 0..1 "fade fraction":
//   * elapsed <= 0          -> 0   (fade hasn't visibly begun: new mesh invisible)
//   * elapsed >= duration   -> 1   (fade complete: new mesh fully shown)
//   * in between            -> a SMOOTHSTEP eased value (3t^2 - 2t^3)
//
// WHY SMOOTHSTEP (not a straight line): a linear ramp starts and stops abruptly —
// the eye catches the kink at both ends. Smoothstep eases in and out (zero slope
// at 0 and 1), so the dither dissolve feels gentle rather than mechanical. It's the
// classic Hermite curve s(t) = 3t^2 - 2t^3, monotonic increasing on [0,1].
//
// A zero/negative duration is treated as "instant": anything past the start is 1
// (we never divide by zero). This also means a misconfigured 0-second fade simply
// behaves like the old hard swap, which is the safe fallback.
// ---------------------------------------------------------------------------
inline float fade_alpha(double elapsed_s, double duration_s) {
    // Instant / degenerate window: no smooth region exists. Before the start it's
    // 0; at or after the start it's already fully faded (1). Guards the divide.
    if (duration_s <= 0.0) {
        return (elapsed_s <= 0.0) ? 0.0f : 1.0f;
    }

    // Clamp the raw fraction t = elapsed/duration into [0,1] so the curve below
    // only ever sees its valid domain (the endpoints become exactly 0 and 1).
    double t = elapsed_s / duration_s;
    if (t <= 0.0) return 0.0f;   // not started yet
    if (t >= 1.0) return 1.0f;   // finished

    // Smoothstep ease: s(t) = 3t^2 - 2t^3. At t=0 -> 0, at t=1 -> 1, with zero
    // slope at both ends (the soft start/stop that hides the swap).
    const double s = t * t * (3.0 - 2.0 * t);
    return static_cast<float>(s);
}

// ---------------------------------------------------------------------------
// should_start_fade — the POLICY gate: do we kick off a brand-new cross-fade?
//
//   old_lod        — the LOD the column currently renders at.
//   new_lod        — the LOD it now WANTS to render at (the committed target).
//   already_fading — true if this column is already mid-fade right now.
//
// Returns true ONLY for a genuine, fresh LOD change:
//   * old_lod == new_lod      -> false (nothing changed; no fade needed).
//   * already_fading == true  -> false (one fade at a time per column; the caller
//                                defers the new target until the current fade ends,
//                                so we never stack two outgoing meshes on a column).
//   * otherwise               -> true  (a real change with no fade in progress).
//
// Keeping this one-liner in the policy header (rather than inlined in the streamer)
// means the harness pins the exact "when does a fade begin" rule, and the streamer
// reads as `if (should_start_fade(...)) { ...start... } else { ...defer... }`.
// ---------------------------------------------------------------------------
inline bool should_start_fade(int old_lod, int new_lod, bool already_fading) {
    if (already_fading)     return false;  // finish the current fade first (caller defers)
    if (old_lod == new_lod) return false;  // no actual tier change -> no fade
    return true;                           // a real, fresh LOD change -> fade it
}

// ---------------------------------------------------------------------------
// should_destroy_outgoing — the MESH-THEN-SWAP gate (Bug 2 fix): when may we
// finally destroy the OLD (outgoing) mesh that we kept on screen?
//
//   incoming_ready — true ONLY when the replacement (new-LOD) mesh is ACTUALLY
//                    uploaded and committed for this column. The streamer
//                    computes this as: the column is in MeshedColumns, AND it is
//                    NOT in the in-flight mesh set (no worker still building it),
//                    AND its committed meshed span matches the target span.
//
// Returns:
//   * incoming_ready == false -> FALSE  (the new mesh is NOT up yet — KEEP the
//                                old one visible; destroying now would leave a
//                                literal hole in front of the player).
//   * incoming_ready == true  -> TRUE   (the new mesh is fully in — it is now
//                                safe to drop the old one; the swap is seamless).
//
// This is the dither-FREE sibling of the LOD cross-fade: a "swap-hold" keeps the
// old coarse mesh alive (NOT a fade — no alpha is touched) purely as a backstop
// until the finer mesh lands, then destroys it in one step. Pinning the rule in
// this engine-free header lets the harness lock the one load-bearing invariant:
// the outgoing mesh is NEVER destroyed while incoming_ready == false.
// ---------------------------------------------------------------------------
inline bool should_destroy_outgoing(bool incoming_ready) {
    return incoming_ready; // hold the old mesh until the new one is genuinely ready
}

} // namespace lodfade
} // namespace mira
