// FiniteWaterCore.cpp — implementation of the finite volume-conserving water
// sim. Ported 1:1 from Godot scripts/FiniteWaterCore.gd. See the header for
// the plain-English overview; the comments here track the original RULE 1..5
// structure so a reader can diff the two files side by side.

#include "Core/FiniteWaterCore.h"

#include <algorithm> // std::sort, std::min, std::max
#include <climits>   // INT_MAX

namespace mira {

// ----------------------------------------------------------------------------
// Fixed neighbour tables (the order IS part of the determinism contract).
// ----------------------------------------------------------------------------
// Lateral neighbour order is FIXED (+X, -X, +Z, -Z): it is the tie-break rule.
static const Vec3i kLateral[4] = {
    Vec3i(1, 0, 0), Vec3i(-1, 0, 0),
    Vec3i(0, 0, 1), Vec3i(0, 0, -1),
};
static const int kLateralCode[4] = {
    WaterByteCodec::DIR_POS_X, WaterByteCodec::DIR_NEG_X,
    WaterByteCodec::DIR_POS_Z, WaterByteCodec::DIR_NEG_Z,
};

// The 6 face neighbours (down, up, +X, -X, +Z, -Z). Same set as GDScript.
static const Vec3i kFaces6[6] = {
    Vec3i(0, -1, 0), Vec3i(0, 1, 0),
    Vec3i(1, 0, 0),  Vec3i(-1, 0, 0),
    Vec3i(0, 0, 1),  Vec3i(0, 0, -1),
};

// GDScript int helpers (so the math reads identically to the original).
static inline int maxi(int a, int b) { return a > b ? a : b; }
static inline int mini(int a, int b) { return a < b ? a : b; }
static inline int clampi(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }

// ----------------------------------------------------------------------------
// Construction
// ----------------------------------------------------------------------------
FiniteWaterCore::FiniteWaterCore(SolidFn solid, SourceFn source, int sea_y_in)
    : solid_cb(std::move(solid)), source_cb(std::move(source)), sea_y(sea_y_in) {}

// ----------------------------------------------------------------------------
// Tiny ledger lookups (mirror GDScript Dictionary.get / .has)
// ----------------------------------------------------------------------------
int FiniteWaterCore::ledger_get(const Vec3i& p) const {
    auto it = _ledger.find(p);
    return it == _ledger.end() ? 0 : it->second;
}
bool FiniteWaterCore::ledger_has(const Vec3i& p) const {
    return _ledger.find(p) != _ledger.end();
}

// ----------------------------------------------------------------------------
// Public API
// ----------------------------------------------------------------------------
int FiniteWaterCore::place(const Vec3i& pos, int units) {
    // Fill `pos` up to 8 units, then stack excess into the cells above.
    int remaining = maxi(0, units);
    int k = 0;
    while (remaining > 0 && k < 256) {
        Vec3i p = pos + Vec3i(0, k, 0);
        if (is_solid(p) || is_source(p)) {
            break; // can't pour into rock or into the (infinite) ocean
        }
        int cur = ledger_get(p);
        int add = mini(MAX_UNITS_PER_CELL - cur, remaining);
        if (add > 0) {
            _ledger[p] = cur + add;
            if (cur == 0) {
                _dist[p] = 0; // fresh water starts a fresh spread budget
            }
            placed += add;
            remaining -= add;
            _external_changed[p] = true;
            activate_with_neighbours(p);
        }
        k += 1;
    }
    return maxi(0, units) - remaining;
}

void FiniteWaterCore::activate(const Vec3i& pos) {
    activate_with_neighbours(pos);
}

void FiniteWaterCore::ingest(const Vec3i& pos, int units) {
    if (units <= 0 || is_solid(pos) || is_source(pos)) {
        return;
    }
    if (ledger_has(pos)) {
        return; // already tracked — don't double-count
    }
    _ledger[pos] = clampi(units, 1, MAX_UNITS_PER_CELL);
    _dist[pos] = 0;
    placed += _ledger[pos];
    _external_changed[pos] = true;
    activate_with_neighbours(pos);
}

int FiniteWaterCore::remove(const Vec3i& pos, int max_units) {
    // Scoop from this cell, then the cells stacked directly above it.
    int got = 0;
    int k = 0;
    while (got < max_units && k < 16) {
        Vec3i p = pos + Vec3i(0, k, 0);
        if (ledger_has(p)) {
            int u = _ledger[p];
            int take = mini(u, max_units - got);
            got += take;
            if (take >= u) {
                clear_cell(p);
            } else {
                _ledger[p] = u - take;
            }
            _external_changed[p] = true;
            wake_ledger_neighbours(p);
            activate_with_neighbours(p);
        }
        k += 1;
    }
    removed += got;
    return got;
}

int FiniteWaterCore::projected_byte(const Vec3i& pos) const {
    return projected_byte_impl(pos);
}

bool FiniteWaterCore::has_cell(const Vec3i& pos) const {
    return ledger_has(pos);
}

int FiniteWaterCore::total_units() const {
    int sum = 0;
    for (const auto& kv : _ledger) {
        sum += kv.second;
    }
    return sum;
}

bool FiniteWaterCore::is_settled() const {
    return _active.empty();
}

bool FiniteWaterCore::has_pending_changes() const {
    return !_active.empty() || !_external_changed.empty();
}

int FiniteWaterCore::units_at(const Vec3i& pos) const {
    return ledger_get(pos);
}

int FiniteWaterCore::conservation_delta() const {
    return total_units() - (placed - evaporated - absorbed - merged - removed);
}

FiniteWaterCore::Stats FiniteWaterCore::stats() const {
    Stats s;
    s.units      = total_units();
    s.active     = static_cast<int>(_active.size());
    s.placed     = placed;
    s.evaporated = evaporated;
    s.absorbed   = absorbed;
    s.merged     = merged;
    s.removed    = removed;
    return s;
}

std::string FiniteWaterCore::state_signature() const {
    // Sorted (y, x, z) so the string is byte-identical across runs/languages
    // regardless of unordered_map iteration order.
    std::vector<Vec3i> keys;
    keys.reserve(_ledger.size());
    for (const auto& kv : _ledger) keys.push_back(kv.first);
    std::sort(keys.begin(), keys.end(), cell_order);

    std::string out;
    bool first = true;
    char buf[96];
    for (const Vec3i& p : keys) {
        int u = ledger_get(p);
        auto dit = _dist.find(p);
        int dist = dit == _dist.end() ? 0 : dit->second;
        auto rit = _dir.find(p);
        int dir = rit == _dir.end() ? WaterByteCodec::DIR_STILL : rit->second;
        std::snprintf(buf, sizeof(buf), "%d,%d,%d=%d/%d/%d",
                      p.x, p.y, p.z, u, dist, dir);
        if (!first) out += ";";
        out += buf;
        first = false;
    }
    return out;
}

// ----------------------------------------------------------------------------
// step() — advance one tick
// ----------------------------------------------------------------------------
FiniteWaterCore::StepResult FiniteWaterCore::step(int budget) {
    std::unordered_map<Vec3i, bool> changed;

    // Fold in cells mutated between ticks (place / ingest / remove) so their
    // projection rides the same change stream as sim moves.
    for (const auto& kv : _external_changed) {
        changed[kv.first] = true;
    }
    _external_changed.clear();

    // Worklist = active cells, sorted ascending (y, x, z), capped to budget.
    std::vector<Vec3i> worklist;
    worklist.reserve(_active.size());
    for (const auto& kv : _active) worklist.push_back(kv.first);
    std::sort(worklist.begin(), worklist.end(), cell_order);
    if (budget > 0 && static_cast<int>(worklist.size()) > budget) {
        worklist.resize(budget);
    }

    for (const Vec3i& c : worklist) {
        _active.erase(c); // re-armed below if the cell is still busy
        if (!ledger_has(c)) {
            _evap_ttl.erase(c);
            continue;
        }
        step_cell(c, changed);
    }

    // Build the change stream, sorted (y, x, z).
    StepResult result;
    std::vector<Vec3i> ckeys;
    ckeys.reserve(changed.size());
    for (const auto& kv : changed) ckeys.push_back(kv.first);
    std::sort(ckeys.begin(), ckeys.end(), cell_order);
    result.changes.reserve(ckeys.size());
    for (const Vec3i& p : ckeys) {
        result.changes.push_back(Change{p, projected_byte_impl(p)});
    }
    result.stats = stats();
    return result;
}

// ----------------------------------------------------------------------------
// step_cell — the per-cell rules. The order here IS the spec (RULE 1..5 below
// mirror WATER_FINITE_SIM_PLAN.md "Sim rules"). Note the GDScript order in the
// file is: ocean-merge (rule 5), down (rule 1), lateral (rule 2), dir byte,
// evap (rule 4), activity (rule 3) — preserved exactly.
// ----------------------------------------------------------------------------
void FiniteWaterCore::step_cell(const Vec3i& c,
                                std::unordered_map<Vec3i, bool>& changed) {
    int u = _ledger[c];

    // RULE 5 — ocean merge. Touching the infinite ocean at/below sea level
    // means this cell IS ocean now; its units leave the finite books.
    if (c.y <= sea_y && touches_source(c)) {
        merged += u;
        clear_cell(c);
        _merged_sources[c] = true;
        changed[c] = true;
        wake_ledger_neighbours(c);
        return;
    }

    // RULE 1 — DOWN first. Water under us beats everything else.
    Vec3i below = c + Vec3i(0, -1, 0);
    int moved_down = 0;
    if (!is_solid(below)) {
        if (is_source(below)) {
            // Falling into the ocean: swallowed entirely.
            absorbed += u;
            clear_cell(c);
            changed[c] = true;
            wake_ledger_neighbours(c);
            return;
        }
        int ub = ledger_get(below);
        if (ub < MAX_UNITS_PER_CELL) {
            int m = mini(u, MAX_UNITS_PER_CELL - ub);
            _ledger[below] = ub + m;
            if (ub == 0) {
                _dist[below] = 0; // a drop starts a fresh spread budget
            }
            u -= m;
            moved_down = m;
            changed[below] = true;
            activate_with_neighbours(below);
            if (u == 0) {
                clear_cell(c);
                changed[c] = true;
                wake_ledger_neighbours(c);
                return;
            }
            _ledger[c] = u;
            changed[c] = true; // partial drop still changed OUR level
        }
    }

    // RULE 2 — lateral equalization. Only donors with >= 2 units, and only
    // while standing on something (solid / source / full water).
    std::unordered_map<int, int> lateral_moved; // dir code -> units moved
    if (u >= 2 && is_supported(c)) {
        auto dit = _dist.find(c);
        int my_dist = dit == _dist.end() ? 0 : dit->second;
        while (u >= 2) {
            Vec3i best_n = c;
            int best_u = INT_MAX;          // mirror GDScript 0x7fffffff
            int best_code = WaterByteCodec::DIR_STILL;
            for (int i = 0; i < 4; ++i) {
                Vec3i d = kLateral[i];
                Vec3i n = c + d;
                if (is_solid(n)) {
                    continue;
                }
                int n_eff;
                if (is_source(n)) {
                    if (n.y > sea_y) {
                        continue; // never absorb into an above-sea headwater
                    }
                    n_eff = -1; // the ocean is always "lower" — absorb
                } else if (ledger_has(n)) {
                    n_eff = _ledger[n];
                    if (n_eff > u - 2) {
                        continue; // gap of 1 is level enough — stop (this is
                                  // what makes convergence terminate)
                    }
                } else {
                    if (my_dist >= SPREAD_REACH_VOXELS) {
                        continue; // front has used up its creep budget
                    }
                    n_eff = 0;
                }
                if (n_eff < best_u) {
                    best_u = n_eff;
                    best_n = n;
                    best_code = kLateralCode[i];
                }
            }
            if (best_u == INT_MAX) {
                break; // nowhere lower to go
            }
            // Move exactly 1 unit (integer moves = exact conservation).
            u -= 1;
            _ledger[c] = u;
            if (best_u == -1) {
                absorbed += 1;
            } else {
                bool was_empty = !ledger_has(best_n);
                _ledger[best_n] = ledger_get(best_n) + 1;
                if (was_empty) {
                    _dist[best_n] = my_dist + 1;
                }
                _evap_ttl.erase(best_n); // fresh water cancels any countdown
                changed[best_n] = true;
                activate_with_neighbours(best_n);
            }
            lateral_moved[best_code] = (lateral_moved.count(best_code)
                                            ? lateral_moved[best_code]
                                            : 0) + 1;
            changed[c] = true;
        }
    }

    // Flow-direction byte: whichever way the most units went this tick.
    // DOWN beats laterals on a tie. Fixed iteration order (+X,-X,+Z,-Z).
    int new_dir = WaterByteCodec::DIR_STILL;
    int best_moved = 0;
    for (int i = 0; i < 4; ++i) {
        int code = kLateralCode[i];
        int m_code = lateral_moved.count(code) ? lateral_moved[code] : 0;
        if (m_code > best_moved) {
            best_moved = m_code;
            new_dir = code;
        }
    }
    if (moved_down >= best_moved && moved_down > 0) {
        new_dir = WaterByteCodec::DIR_DOWN;
    }
    {
        auto rit = _dir.find(c);
        int old_dir = rit == _dir.end() ? WaterByteCodec::DIR_STILL : rit->second;
        if (new_dir != old_dir) {
            _dir[c] = new_dir;
            changed[c] = true;
        }
    }

    bool did_move = moved_down > 0 || !lateral_moved.empty();

    // RULE 4 — orphaned-film evaporation. A lone 1-unit cell with no water
    // beside it counts down and disappears (ledgered).
    if (u == 1 && !has_water_neighbour(c)) {
        auto tit = _evap_ttl.find(c);
        int t = (tit == _evap_ttl.end() ? 0 : tit->second) + 1;
        if (t >= EVAP_TTL) {
            evaporated += 1;
            clear_cell(c);
            changed[c] = true;
            return;
        }
        _evap_ttl[c] = t;
        _active[c] = true; // must keep ticking or the countdown freezes
        return;
    } else {
        _evap_ttl.erase(c);
    }

    // RULE 3 — stay awake only while something is happening. A cell whose
    // units changed must ALSO wake its water neighbours.
    if (did_move) {
        _active[c] = true;
        wake_ledger_neighbours(c);
    }
    // else: cell goes dormant. Neighbours it fed were woken above.
}

// ----------------------------------------------------------------------------
// Internal — small helpers
// ----------------------------------------------------------------------------
bool FiniteWaterCore::is_solid(const Vec3i& p) const {
    return solid_cb && solid_cb(p);
}

bool FiniteWaterCore::is_source(const Vec3i& p) const {
    if (_merged_sources.find(p) != _merged_sources.end()) {
        return true;
    }
    return source_cb && source_cb(p);
}

bool FiniteWaterCore::is_supported(const Vec3i& c) const {
    Vec3i b = c + Vec3i(0, -1, 0);
    return is_solid(b) || is_source(b) || ledger_get(b) >= MAX_UNITS_PER_CELL;
}

bool FiniteWaterCore::touches_source(const Vec3i& c) const {
    for (const Vec3i& d : kFaces6) {
        if (is_source(c + d)) {
            return true;
        }
    }
    return false;
}

bool FiniteWaterCore::has_water_neighbour(const Vec3i& c) const {
    for (const Vec3i& d : kFaces6) {
        Vec3i n = c + d;
        if (ledger_has(n) || is_source(n)) {
            return true;
        }
    }
    return false;
}

void FiniteWaterCore::clear_cell(const Vec3i& c) {
    _ledger.erase(c);
    _dist.erase(c);
    _evap_ttl.erase(c);
    _dir.erase(c);
}

void FiniteWaterCore::activate_with_neighbours(const Vec3i& p) {
    if (ledger_has(p)) {
        _active[p] = true;
    }
    wake_ledger_neighbours(p);
}

void FiniteWaterCore::wake_ledger_neighbours(const Vec3i& p) {
    for (const Vec3i& d : kFaces6) {
        Vec3i n = p + d;
        if (ledger_has(n)) {
            _active[n] = true;
        }
    }
}

int FiniteWaterCore::projected_byte_impl(const Vec3i& p) const {
    if (_merged_sources.find(p) != _merged_sources.end()) {
        return WaterByteCodec::SOURCE_BYTE;
    }
    if (!ledger_has(p)) {
        return WaterByteCodec::AIR_BYTE;
    }
    auto rit = _dir.find(p);
    int dir = rit == _dir.end() ? WaterByteCodec::DIR_STILL : rit->second;
    return WaterByteCodec::pack(ledger_get(p), false, dir);
}

// ----------------------------------------------------------------------------
// Total ordering — ascending (y, x, z). The cross-language determinism rule.
// ----------------------------------------------------------------------------
bool FiniteWaterCore::cell_order(const Vec3i& a, const Vec3i& b) {
    if (a.y != b.y) return a.y < b.y;
    if (a.x != b.x) return a.x < b.x;
    return a.z < b.z;
}

} // namespace mira
