// ViewPriority.h — VIEW-PRIORITIZED streaming order: load/mesh the terrain the
// player is LOOKING AT a touch sooner than the terrain behind them.
//
// THE JOB (plain English): the streaming system processes chunk-columns ring by
// ring, nearest first. That already loads the nearest terrain first (good), but
// WITHIN a ring every direction is treated the same — the chunk dead behind you
// loads just as eagerly as the one straight ahead. In a now-1.23 km-deep world a
// player walking forward FEELS this: the ground they're about to walk onto pops
// in no sooner than the ground they just left. This header lets the streamer give
// a small head-start to chunks in the VIEW (forward) direction so look-ahead
// terrain appears first — better PERCEIVED loading, same total work.
//
// CRITICAL PROPERTY — THIS IS AN ORDERING TWEAK, *NOT* A FILTER.
// We return a SORT KEY, never a yes/no. The key is PRIMARILY the chunk's true
// distance from the focus, so:
//   * nearest chunks ALWAYS sort before farther chunks (completeness preserved),
//   * the forward bias is a SMALL secondary discount that can only REORDER chunks
//     that are already at a similar distance — it can never push a chunk out of
//     the loaded set, and it can never starve the chunks behind you. As the ring
//     expands every in-radius chunk is still reached and still gets a finite key.
// In short: forward terrain loads a few chunks SOONER, behind-you terrain still
// loads — just slightly later. No holes, ever.
//
// Pure C++17, no engine headers — compiles in the headless clang harness and in
// the UE5 module alike. Header-only (all inline/constexpr): no .cpp, so the
// harness's Core-source list is untouched. Mirrors the Core style of LodTier.h.

#pragma once

#include <cmath>  // std::sqrt — Euclidean distance + forward-vector normalisation

namespace mira {
namespace viewpriority {

// ---------------------------------------------------------------------------
// view_priority_key — turn a chunk's offset-from-focus + the view direction into
// a SORT KEY where LOWER = "load this sooner".
//
//   dchunk_x, dchunk_z — the chunk's offset from the streaming focus, IN CHUNKS,
//                        on the voxel-horizontal plane (core X and core Z). E.g.
//                        a chunk two columns east and one north of the focus is
//                        (dchunk_x = 2, dchunk_z = 1). (0,0) is the focus column.
//   fwd_x, fwd_z       — the view/camera FORWARD direction projected onto that
//                        same horizontal plane, in the SAME core (x,z) axes. Need
//                        NOT be normalised — we normalise internally. Pass (0,0)
//                        when no view is available (a focus actor with no camera);
//                        the result then degrades to pure distance order.
//   ring_bias_chunks   — the STRENGTH of the forward bias, in chunks. This is the
//                        most a perfectly-forward chunk's EFFECTIVE distance can be
//                        discounted (and the most a perfectly-behind chunk can be
//                        penalised). Keep it MODEST (a few chunks, e.g. 4): the bias
//                        only reshuffles chunks within a band ~2*ring_bias wide; it
//                        never excludes far/behind chunks (the ring still reaches
//                        them). 0 disables the bias entirely (pure distance).
//
// THE FORMULA (and why it preserves completeness):
//
//   true_dist     = sqrt(dx^2 + dz^2)                  // Euclidean, in chunks
//   align         = dot( normalize(d), normalize(fwd) ) // -1 behind .. +1 ahead
//   effective_dist = true_dist - ring_bias * align      // the SORT KEY
//
// `align` is +1 for a chunk straight ahead, 0 to the sides, -1 straight behind.
// So a forward chunk gets up to `ring_bias` chunks SHAVED OFF its effective
// distance (loads sooner) and a behind chunk gets up to `ring_bias` chunks ADDED
// (loads later). Because the discount is BOUNDED by ring_bias and `align` is in
// [-1, +1], the key stays FINITE for every chunk and stays MONOTONIC-ish in true
// distance once you're more than `ring_bias` apart:
//
//   a chunk a full `ring_bias`+ rings CLOSER than another ALWAYS wins, no matter
//   the view — because even the best-case forward discount (ring_bias) can't make
//   a far chunk out-rank a near one that's more than ring_bias closer. That is the
//   no-starvation guarantee: keep ring_bias small and "nearest still loads first"
//   holds for everything outside the thin reorder band.
//
// The focus column itself (d == 0) has no direction; we give it the minimal key
// (true_dist 0, no bias term) so it always sorts first — it's where you stand.
// ---------------------------------------------------------------------------
inline float view_priority_key(int dchunk_x, int dchunk_z,
                               float fwd_x, float fwd_z,
                               float ring_bias_chunks)
{
    // True horizontal distance from the focus, in chunks (Euclidean — smoother and
    // more "round" than chebyshev for a view cone, but any monotone distance works).
    const float dx = static_cast<float>(dchunk_x);
    const float dz = static_cast<float>(dchunk_z);
    const float true_dist = std::sqrt(dx * dx + dz * dz);

    // No bias requested, no view available, or we're standing ON the focus column:
    // there's no meaningful direction to align to. Degrade to pure distance order
    // (this is the EXACT same ordering the streamer uses today with the flag off).
    if (ring_bias_chunks <= 0.0f) {
        return true_dist;
    }
    const float fwd_len = std::sqrt(fwd_x * fwd_x + fwd_z * fwd_z);
    if (fwd_len <= 1e-6f || true_dist <= 1e-6f) {
        return true_dist;
    }

    // Cosine of the angle between (a) the direction FROM the focus TO this chunk and
    // (b) the view forward. dot(normalize(d), normalize(fwd)) == (d . fwd)/(|d||fwd|).
    // +1 = chunk is straight ahead, 0 = to the side, -1 = straight behind.
    const float align = (dx * fwd_x + dz * fwd_z) / (true_dist * fwd_len);

    // Effective distance = true distance minus a bounded forward discount. Forward
    // chunks (align > 0) shrink toward the focus (load sooner); behind chunks
    // (align < 0) push outward (load later). The discount magnitude is at most
    // ring_bias_chunks, so the key never goes below (true_dist - ring_bias) and the
    // ordering only reshuffles WITHIN a ~2*ring_bias-wide band. Far/behind chunks
    // keep finite keys and are still reached as the ring expands — never skipped.
    return true_dist - ring_bias_chunks * align;
}

// ---------------------------------------------------------------------------
// view_priority_less — a strict-weak-ordering comparator for sorting a list of
// chunk OFFSETS (each a {dchunk_x, dchunk_z}) by view priority, lowest key first
// (i.e. "load-soonest first"). Handy when a caller wants to std::sort a small
// already-collected candidate set rather than re-deriving keys inline.
//
// `Offset` is any type exposing integer .first / .second style x,z — we keep it a
// template so the engine side can pass an FIntPoint-like pair or a tiny POD without
// this pure header needing to know the concrete type. Ties (equal keys) fall back
// to a stable lexicographic compare on (dx, dz) so the order is DETERMINISTIC.
// ---------------------------------------------------------------------------
template <typename Offset>
inline bool view_priority_less(const Offset& a, const Offset& b,
                               float fwd_x, float fwd_z, float ring_bias_chunks)
{
    const float ka = view_priority_key(a.x_chunks(), a.z_chunks(), fwd_x, fwd_z, ring_bias_chunks);
    const float kb = view_priority_key(b.x_chunks(), b.z_chunks(), fwd_x, fwd_z, ring_bias_chunks);
    if (ka != kb) {
        return ka < kb;  // lower key loads sooner
    }
    // Deterministic tiebreak on the raw offset so equal-key chunks sort stably.
    if (a.x_chunks() != b.x_chunks()) return a.x_chunks() < b.x_chunks();
    return a.z_chunks() < b.z_chunks();
}

} // namespace viewpriority
} // namespace mira
