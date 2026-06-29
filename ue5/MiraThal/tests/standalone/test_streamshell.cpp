// test_streamshell.cpp — correctness lock for "3D / spherical surface-shell streaming".
//   cd tests/standalone && ./build.sh streamshell
//
// WHY THIS EXISTS (plain English):
// Surface-shell streaming (Core/StreamShell.h) changes the VERTICAL extent a column
// streams by distance: NEAR columns fill full depth (mine straight down), FAR columns
// stream only a thin shell hugging the surface (no wasted underground). It also adds a
// TRUE ROUND (spherical) cull. This harness locks the load-bearing properties so the
// flag-gated wiring in VoxelWorld.cpp can rely on them:
//
//   * chunk_of_voxel_y is floor-div (correct for NEGATIVE voxel-Y too).
//   * a NEAR column returns the FULL span [floor, surface+up_pad] (today's behaviour).
//   * a FAR column returns EXACTLY [surface-down, surface+up], clamped to [floor,ceil].
//   * clamping at floor_y_chunk / ceil_y_chunk is respected (no out-of-range, no invert).
//   * within_sphere boundary: on-surface IN, just-inside IN, just-outside OUT.
//   * MONOTONICITY: a column never streams FEWER chunks as it gets CLOSER (no popping
//     holes / deeper-on-approach is safe).
//   * determinism.
//
// Pure Core, no Unreal. Prints "[streamshell] PASS/FAIL"; returns 0/1 (matches every
// other tests/standalone harness).

#include <cstdio>

#include "Core/StreamShell.h"   // unit under test
#include "Core/ChunkCoords.h"   // coords::CHUNK, coords::floor_div

static int g_checks = 0, g_fails = 0;
#define CHECK(cond, msg) do { ++g_checks; if(!(cond)){ ++g_fails; \
    std::printf("  FAIL %s  (%s:%d)\n", (msg), __FILE__, __LINE__);} } while(0)

using namespace mira;
using mira::streamshell::ShellRange;

int main() {

    const int CH = coords::CHUNK; // 32

    // =======================================================================
    // TEST A — chunk_of_voxel_y is floor division (incl. negatives).
    // =======================================================================
    {
        bool ok = true;
        for (int vy = -200; vy <= 400; ++vy) {
            if (streamshell::chunk_of_voxel_y(vy) != coords::floor_div(vy, CH)) ok = false;
        }
        CHECK(ok, "chunk_of_voxel_y(vy) == floor_div(vy, CHUNK) over a wide range");
        // Spot-check the negative cases that truncating division would get wrong.
        CHECK(streamshell::chunk_of_voxel_y(0)   ==  0, "chunk_of_voxel_y(0) == 0");
        CHECK(streamshell::chunk_of_voxel_y(31)  ==  0, "chunk_of_voxel_y(31) == 0");
        CHECK(streamshell::chunk_of_voxel_y(32)  ==  1, "chunk_of_voxel_y(32) == 1");
        CHECK(streamshell::chunk_of_voxel_y(-1)  == -1, "chunk_of_voxel_y(-1) == -1 (floor, not 0)");
        CHECK(streamshell::chunk_of_voxel_y(-32) == -1, "chunk_of_voxel_y(-32) == -1");
        CHECK(streamshell::chunk_of_voxel_y(-33) == -2, "chunk_of_voxel_y(-33) == -2");
    }

    // Shared shell parameters for the span tests. Surface at voxel-Y 100 -> chunk row 3.
    const int ground_vy   = 100;                                // surface voxel-Y
    const int surface_chk = streamshell::chunk_of_voxel_y(ground_vy); // == 3
    const int near_full   = 10;   // within 10 chunks -> full depth
    const int up          = 1;    // shell keeps 1 row above
    const int down        = 2;    // shell keeps 2 rows below
    const int floor_chk   = -16;  // dig floor / bedrock row
    const int ceil_chk    = 20;   // top row of interest

    CHECK(surface_chk == 3, "surface voxel-Y 100 -> chunk row 3");

    // =======================================================================
    // TEST B — NEAR column returns the FULL span [floor, surface + up_pad].
    // =======================================================================
    {
        // dist exactly == near_full is STILL near (inclusive boundary).
        ShellRange r = streamshell::shell_for_column(ground_vy, near_full, near_full,
                                                     up, down, floor_chk, ceil_chk);
        CHECK(r.y_lo_chunk == floor_chk, "near (dist==near_full): lo == floor_y_chunk");
        CHECK(r.y_hi_chunk == surface_chk + up, "near (dist==near_full): hi == surface + up_pad");

        // A column right on top of the player (dist 0) is also full depth.
        ShellRange r0 = streamshell::shell_for_column(ground_vy, 0, near_full,
                                                      up, down, floor_chk, ceil_chk);
        CHECK(r0.y_lo_chunk == floor_chk && r0.y_hi_chunk == surface_chk + up,
              "near (dist 0): full span [floor, surface+up]");

        // BUG-1 LOCK (spawn-underneath must reach bedrock): at dist_chunks == 0 the column
        // directly UNDER the player streams FULL DEPTH — its bottom is EXACTLY the dig floor,
        // never a trimmed shell. A holed spawn was partly the column under the player not
        // streaming all the way down; this pins y_lo == floor_y_chunk (no trim) at dist 0.
        CHECK(r0.y_lo_chunk == floor_chk,
              "dist 0 (under spawn): y_lo == floor_y_chunk (full depth, no shell trim)");
        // And it is strictly DEEPER than the far shell (which bottoms at surface-down), so the
        // spawn column genuinely reaches bedrock rather than hugging the surface.
        ShellRange farShell = streamshell::shell_for_column(ground_vy, 999, near_full,
                                                            up, down, floor_chk, ceil_chk);
        CHECK(r0.y_lo_chunk < farShell.y_lo_chunk,
              "dist 0 bottoms DEEPER than the far shell (under-spawn is full depth, not a shell)");
    }

    // =======================================================================
    // TEST C — FAR column returns EXACTLY [surface-down, surface+up] (clamped).
    // =======================================================================
    {
        // dist just past near_full -> far branch (thin shell).
        ShellRange r = streamshell::shell_for_column(ground_vy, near_full + 1, near_full,
                                                     up, down, floor_chk, ceil_chk);
        CHECK(r.y_lo_chunk == surface_chk - down, "far: lo == surface - shell_down");
        CHECK(r.y_hi_chunk == surface_chk + up,   "far: hi == surface + shell_up");

        // Way out -> still the SAME fixed shell (distance-independent in the far band).
        ShellRange rFar = streamshell::shell_for_column(ground_vy, 999, near_full,
                                                        up, down, floor_chk, ceil_chk);
        CHECK(rFar.y_lo_chunk == surface_chk - down && rFar.y_hi_chunk == surface_chk + up,
              "far (very distant): shell span is the same fixed surface-hugging band");
    }

    // =======================================================================
    // TEST D — clamping at floor_y_chunk / ceil_y_chunk.
    // =======================================================================
    {
        // Floor clamp: a tight floor JUST below the surface clips the near full-depth
        // span's bottom up to the floor (and the far shell bottom too).
        const int tight_floor = surface_chk - 1; // floor sits one row below surface
        ShellRange near_r = streamshell::shell_for_column(ground_vy, 0, near_full,
                                                          up, down, tight_floor, ceil_chk);
        CHECK(near_r.y_lo_chunk == tight_floor, "near: lo clamped UP to a tight floor");

        ShellRange far_r = streamshell::shell_for_column(ground_vy, 999, near_full,
                                                         up, down, tight_floor, ceil_chk);
        // surface-down = 1, but floor is surface-1, so lo clamps to surface-1.
        CHECK(far_r.y_lo_chunk == tight_floor, "far: shell lo clamped UP to a tight floor");

        // Ceil clamp: a tight ceil AT the surface clips the +up headroom down to it.
        const int tight_ceil = surface_chk;
        ShellRange ceil_r = streamshell::shell_for_column(ground_vy, 999, near_full,
                                                          up, down, floor_chk, tight_ceil);
        CHECK(ceil_r.y_hi_chunk == tight_ceil, "far: hi clamped DOWN to a tight ceil");

        // Degenerate floor > ceil never produces an inverted span (lo <= hi always).
        ShellRange deg = streamshell::shell_for_column(ground_vy, 999, near_full,
                                                       up, down, /*floor*/5, /*ceil*/2);
        CHECK(deg.y_lo_chunk <= deg.y_hi_chunk, "degenerate floor>ceil: span not inverted");
    }

    // =======================================================================
    // TEST E — within_sphere boundary (on-surface IN, just-inside IN, just-out OUT).
    // =======================================================================
    {
        const int R = 5; // radius in chunks; R*R = 25
        // On the axis exactly at the radius -> ON the sphere -> IN (inclusive).
        CHECK(streamshell::within_sphere(R, 0, 0, R),  "within_sphere: exactly on-surface (R,0,0) is IN");
        CHECK(streamshell::within_sphere(0, R, 0, R),  "within_sphere: exactly on-surface (0,R,0) is IN");
        // Just inside.
        CHECK(streamshell::within_sphere(R - 1, 0, 0, R), "within_sphere: just inside is IN");
        // Just outside on the axis.
        CHECK(!streamshell::within_sphere(R + 1, 0, 0, R), "within_sphere: just outside axis is OUT");
        // Diagonal: 3^2+4^2 = 25 == R^2 -> IN; 3^2+4^2+1 just over -> OUT.
        CHECK(streamshell::within_sphere(3, 4, 0, R), "within_sphere: (3,4,0) on sphere is IN");
        CHECK(!streamshell::within_sphere(3, 4, 1, R), "within_sphere: (3,4,1) just past is OUT");
        // Origin is always IN; a corner of the bounding box is OUT (sphere, not square).
        CHECK(streamshell::within_sphere(0, 0, 0, R), "within_sphere: origin IN");
        CHECK(!streamshell::within_sphere(R, R, 0, R), "within_sphere: box corner (R,R,0) is OUT (round, not square)");
    }

    // =======================================================================
    // TEST F — MONOTONICITY: a column never streams FEWER chunks as it gets CLOSER.
    // Sweep distance from far to near; the span count must be NON-DECREASING as dist
    // shrinks (no popping holes; deeper-on-approach only ever ADDS chunks).
    // =======================================================================
    {
        auto span_count = [&](int dist) {
            ShellRange r = streamshell::shell_for_column(ground_vy, dist, near_full,
                                                         up, down, floor_chk, ceil_chk);
            return r.y_hi_chunk - r.y_lo_chunk + 1;
        };
        bool ok = true;
        // dist 40 (far) down to 0 (right on top): count must never DROP as dist drops.
        int prev = span_count(40);
        for (int dist = 40; dist >= 0; --dist) {
            const int c = span_count(dist);
            if (c < prev) ok = false; // got CLOSER but stream FEWER chunks -> violation
            prev = c;
        }
        CHECK(ok, "monotonicity: closer never streams fewer chunks (no popping holes)");

        // And the near span is a strict SUPERSET of the far shell (every far chunk-Y is
        // also in the near full-depth span) — the deeper-on-approach guarantee.
        ShellRange farR  = streamshell::shell_for_column(ground_vy, 999, near_full,
                                                         up, down, floor_chk, ceil_chk);
        ShellRange nearR = streamshell::shell_for_column(ground_vy, 0, near_full,
                                                         up, down, floor_chk, ceil_chk);
        CHECK(nearR.y_lo_chunk <= farR.y_lo_chunk && nearR.y_hi_chunk >= farR.y_hi_chunk,
              "near span is a superset of the far shell (deeper-on-approach is safe)");
    }

    // =======================================================================
    // TEST G — DETERMINISM: same inputs -> identical span, every time.
    // =======================================================================
    {
        ShellRange a = streamshell::shell_for_column(ground_vy, 7, near_full, up, down, floor_chk, ceil_chk);
        ShellRange b = streamshell::shell_for_column(ground_vy, 7, near_full, up, down, floor_chk, ceil_chk);
        CHECK(a.y_lo_chunk == b.y_lo_chunk && a.y_hi_chunk == b.y_hi_chunk,
              "determinism: shell_for_column twice == identical span");
    }

    // =======================================================================
    // TEST H — NEGATIVE surface: a column whose surface sits below the origin still
    // maps to the right (negative) chunk row and shells around it correctly.
    // =======================================================================
    {
        const int gvy = -40;                                  // surface below origin
        const int sc  = streamshell::chunk_of_voxel_y(gvy);   // floor_div(-40,32) == -2
        CHECK(sc == -2, "negative surface voxel-Y -40 -> chunk row -2");
        ShellRange r = streamshell::shell_for_column(gvy, 999, near_full, up, down,
                                                     /*floor*/-16, /*ceil*/20);
        CHECK(r.y_lo_chunk == sc - down && r.y_hi_chunk == sc + up,
              "negative-surface far shell: [sc-down, sc+up]");
    }

    std::printf("[streamshell] %s\n", g_fails == 0 ? "PASS" : "FAIL");
    std::printf("---- %d checks, %d failure(s)\n", g_checks, g_fails);
    return g_fails == 0 ? 0 : 1;
}
