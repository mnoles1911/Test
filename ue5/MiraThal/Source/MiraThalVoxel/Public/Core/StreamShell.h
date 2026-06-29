// StreamShell.h — engine-agnostic MATH for "3D / spherical surface-shell streaming".
//
// WHAT THIS IS (plain English):
// Today the streamer loads voxels COLUMNARLY. For every XZ chunk-column inside the
// horizontal radius it fills (and meshes) the column's WHOLE vertical range — from
// the dig floor (bedrock-ish, a few chunks below the surface) all the way up through
// the surface — no matter how far that column is from the player. That is wasteful:
// a column 100 m away does NOT need its underground meshed into actors, because the
// player can't see underground from there and mining is far too slow to ever reach
// it before the column has streamed in fresh.
//
// "Surface-shell streaming" changes the VERTICAL EXTENT a column streams based on how
// FAR it is from the player:
//   * NEAR the player  -> stream the FULL depth (today's behaviour), so the player can
//                         mine straight down and the hole is real all the way down.
//   * FAR from player   -> stream only a THIN SHELL of chunks HUGGING THE SURFACE
//                         (a couple below for cliff faces, one above for overhangs/air
//                         headroom). The deep underground is simply not meshed out
//                         there — a huge saving in actors + triangles + mesh work.
//
// And separately, the HORIZONTAL cull becomes a TRUE ROUND (spherical) distance test
// instead of a square (chebyshev) one, so the loaded set is a sphere/shell around the
// player rather than a square column field.
//
// HOW THIS HEADER FITS THE EXISTING STREAMING (do not confuse the three knobs):
//   * coarse far-gen (Core/CoarseColumnGen.h) sets, per column, the RESOLUTION the
//     terrain is generated at by distance (coarser far away). ORTHOGONAL to us.
//   * super-chunks (Core/SuperChunk.h) replace the FAR band with coarse aggregates.
//     ORTHOGONAL to us — that path is untouched.
//   * THIS header sets, per column, the VERTICAL chunk-Y EXTENT the NEAR/MID per-chunk
//     band streams (shell vs full depth) and supplies the spherical cull test. It runs
//     ALONGSIDE the other two.
//
// UNITS: distances and Y spans here are in CHUNKS (1 unit == one 32-voxel chunk edge),
// EXCEPT `ground_vy` which is a VOXEL Y (the surface voxel) — we convert it to a chunk
// row internally via chunk_of_voxel_y. The caller passes the column's surface voxel-Y
// (compute_ground_y at the column centre) and the column's distance in chunks.
//
// MONOTONICITY (the no-popping-holes guarantee): for a fixed column, the chunk-Y span
// shell_for_column returns NEVER SHRINKS as the column gets CLOSER (smaller
// dist_chunks). A column streams the same or MORE chunks as you approach it, never
// fewer — so walking toward a far column only ADDS depth (deeper-on-approach), it
// never removes a chunk you could already see. (Proof sketch: far branch returns a
// fixed surface-hugging span independent of distance; the moment dist crosses INSIDE
// near_full_radius it jumps to the full [floor .. surface+pad] span, which is a
// SUPERSET of the shell span as long as floor_y_chunk <= surface-shell_down and
// surface+ceil_pad >= surface+shell_up — which the caller guarantees by passing a
// floor at/below the shell bottom and a ceil pad >= shell_up.)
//
// Pure C++17, NO engine headers (same rule as CoarseColumnGen.h / LodTier.h): this is
// clang-testable in the headless harness and compiles inside the Unreal module alike.

#pragma once

#include "Core/ChunkCoords.h"  // coords::CHUNK, coords::floor_div (the floor-div pattern we reuse)

namespace mira {
namespace streamshell {

// ---------------------------------------------------------------------------
// chunk_of_voxel_y — which chunk-Y row a global voxel-Y belongs to.
//
//   = floor_div(vy, CHUNK)
//
// Floor division (rounds toward negative infinity), NOT C's truncating /, so a voxel
// at vy = -1 lands in chunk row -1 (the row below the origin), not row 0. This is the
// SAME floor_div the rest of the addressing math uses (Core/ChunkCoords.h) — we reuse
// it rather than re-deriving, so storage order never disagrees.
// ---------------------------------------------------------------------------
inline int chunk_of_voxel_y(int vy) {
    return coords::floor_div(vy, coords::CHUNK);
}

// ---------------------------------------------------------------------------
// ShellRange — the inclusive chunk-Y span a column should stream.
//   y_lo_chunk .. y_hi_chunk  (both inclusive chunk-Y rows)
// A column meshes/holds chunk rows y_lo_chunk through y_hi_chunk.
// ---------------------------------------------------------------------------
struct ShellRange {
    int y_lo_chunk;  // lowest chunk-Y row to stream (inclusive)
    int y_hi_chunk;  // highest chunk-Y row to stream (inclusive)
};

// ---------------------------------------------------------------------------
// shell_for_column — pick the chunk-Y span to stream for ONE column.
//
//   ground_vy        — the column's surface VOXEL-Y (compute_ground_y at the column
//                      centre). We convert it to its chunk row internally.
//   dist_chunks      — the column's horizontal distance from the player, in CHUNKS.
//   near_full_radius — within this chunk-distance the column streams FULL DEPTH (so
//                      the player can mine straight down). Beyond it -> thin shell.
//   shell_up_chunks  — far columns: how many chunk rows ABOVE the surface row to keep
//                      (air/overhang headroom; e.g. 1).
//   shell_down_chunks— far columns: how many chunk rows BELOW the surface row to keep
//                      (just enough below-surface so cliff faces aren't see-through;
//                      small, e.g. 1-2 — that is the whole "no deep underground" win).
//   floor_y_chunk    — the lowest chunk-Y row that ever holds terrain (the dig floor /
//                      bedrock row). The full-depth span bottoms out here; the shell is
//                      clamped to never go below it.
//   ceil_y_chunk     — the highest chunk-Y row that ever holds terrain/air-of-interest.
//                      The shell (and the full span's surface+pad) is clamped to it.
//
// NEAR (dist <= near_full_radius): return [floor_y_chunk, surface_chunk + ceil_pad],
//   where ceil_pad == shell_up_chunks (the same air headroom the shell keeps above the
//   surface). This is today's "full depth from bedrock up to a bit above the surface"
//   behaviour — the player can mine straight down to the floor.
//
// FAR (dist > near_full_radius): return [surface_chunk - shell_down_chunks,
//   surface_chunk + shell_up_chunks], clamped to [floor_y_chunk, ceil_y_chunk]. Just a
//   surface-hugging shell; the deep underground is NOT streamed out here.
//
// CLAMPING: both branches clamp the final span into [floor_y_chunk, ceil_y_chunk] so a
// caller's floor/ceil are always respected (a degenerate floor > ceil collapses to a
// single row at the clamp, never an inverted span).
// ---------------------------------------------------------------------------
inline ShellRange shell_for_column(int ground_vy, int dist_chunks,
                                   int near_full_radius,
                                   int shell_up_chunks, int shell_down_chunks,
                                   int floor_y_chunk, int ceil_y_chunk) {
    const int surface_chunk = chunk_of_voxel_y(ground_vy);

    int lo, hi;
    if (dist_chunks <= near_full_radius) {
        // NEAR: full depth from the floor up to a little above the surface (today's
        // behaviour). The ceil pad matches the shell's up-headroom so near and far
        // agree on how much air sits above the surface.
        lo = floor_y_chunk;
        hi = surface_chunk + shell_up_chunks;
    } else {
        // FAR: a thin surface-hugging shell — a couple of rows below (cliff faces) and
        // a row above (overhang/air). The deep underground is intentionally absent.
        lo = surface_chunk - shell_down_chunks;
        hi = surface_chunk + shell_up_chunks;
    }

    // Clamp into the column's real [floor, ceil] chunk-Y limits.
    if (lo < floor_y_chunk) lo = floor_y_chunk;
    if (lo > ceil_y_chunk)  lo = ceil_y_chunk;
    if (hi > ceil_y_chunk)  hi = ceil_y_chunk;
    if (hi < floor_y_chunk) hi = floor_y_chunk;
    // Never let the span invert (lo must not exceed hi after clamping).
    if (lo > hi) lo = hi;

    return ShellRange{ lo, hi };
}

// ---------------------------------------------------------------------------
// within_sphere — the TRUE ROUND (spherical) distance test, in CHUNKS.
//
//   returns dx*dx + dy*dy + dz*dz <= radius*radius   (all integer)
//
// Pass the chunk-deltas from the player to the chunk under test (dx, dy, dz) and the
// radius in chunks. ALL INTEGER (no sqrt, no float) so it is exact and deterministic.
// This replaces the square/cylindrical chebyshev test so the loaded set is a sphere/
// shell hugging the player, not a square column field — "render only within a SPHERICAL
// radius of the player".
//
// BOUNDARY: the test is INCLUSIVE (<=), so a chunk EXACTLY radius chunks away (on the
// sphere surface) is IN. One chunk past it is OUT.
// ---------------------------------------------------------------------------
inline bool within_sphere(int dx_chunks, int dy_chunks, int dz_chunks, int radius_chunks) {
    const long long dx = dx_chunks, dy = dy_chunks, dz = dz_chunks;
    const long long r  = radius_chunks;
    return (dx * dx + dy * dy + dz * dz) <= (r * r);
}

} // namespace streamshell
} // namespace mira
