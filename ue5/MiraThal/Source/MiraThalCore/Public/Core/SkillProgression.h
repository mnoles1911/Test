// SkillProgression.h — the skill XP curve + per-skill xp/level bookkeeping.
//
// Ported 1:1 from the Godot sources:
//   scripts/skills/SkillCurve.gd    (the XP-to-level curve + apply_xp math)
//   scripts/skills/SkillManager.gd  (the single add_xp entry point + the 12 skills)
// Design intent: design/SKILLS_AND_PROGRESSION.md.
//
// This is the engine-agnostic Core copy used by the UE5 port AND by the
// standalone clang parity harness — so it touches NO engine types at all
// (no Unreal, no Godot, no scene tree, no I/O). Pure C++17, std lib only.
//
// ----------------------------------------------------------------------------
// WHAT THIS IS, IN PLAIN ENGLISH:
//
// Roland has 12 skills (sword, mining, speech, ...). Each one tracks two
// numbers: a LEVEL (1..100) and a PROGRESS bar (how much XP he has banked
// toward the NEXT level). When the game grants XP — a sword hit, a felled
// tree, a successful parry — it calls add_xp(skill, amount). That:
//
//   1. adds the amount onto the progress bar,
//   2. rolls the bar over into one (or many) level-ups if it crossed the
//      threshold(s) — a huge grant can jump several levels at once,
//   3. stops dead at level 100 (the cap — no further XP is banked), and
//   4. hands back a small report of exactly what changed.
//
// THE CURVE is Skyrim's: the XP needed to go from level L to L+1 is
//
//       xp_to_next_level(L) = 25 * L^1.95
//
// So early levels are cheap (L1->L2 costs 25 XP) and late levels are brutal
// (L99->L100 costs ~194,728 XP). The curve is strictly increasing, so the
// total XP banked is a strictly increasing function of level — that
// monotonicity is what the headless `skills` selector asserts.
//
// NOTE ON A DOC vs FORMULA MISMATCH (carried faithfully): the design doc's
// prose says "total to cap ~= 430,000 XP". The ACTUAL formula it also prints
// (25 * L^1.95) totals ~6.63 MILLION XP to reach L100. The formula is the
// source of truth (SkillCurve.gd implements exactly it), so this port carries
// the formula, not the prose estimate. The 430k figure is stale prose.
//
// FLOATS vs INTS: the Godot curve works in float (pow returns float, progress
// is a float, grants are passed as float even though the router's grant
// constants are ints). This port keeps XP/progress as `double` to match the
// GDScript float math closely and avoid precision drift on big late-game
// totals. Skill levels are ints, exactly as in Godot.

#pragma once

#include <cmath>
#include <string>
#include <unordered_map>
#include <vector>

namespace mira {

// ----------------------------------------------------------------------------
// SkillCurve — the pure XP math (ports scripts/skills/SkillCurve.gd).
// Static-only; no state. Every caller goes through SkillProgression below.
// ----------------------------------------------------------------------------
struct SkillCurve {
    // Curve constants — match SkillCurve.gd EXACTLY. Do not retune without a
    // designer decision (these define the entire progression pacing).
    static constexpr int    MIN_LEVEL              = 1;
    static constexpr int    MAX_LEVEL              = 100;
    static constexpr int    LEGENDARY_RESET_LEVEL  = 15;
    static constexpr int    PERK_MILESTONE_INTERVAL = 4; // milestones at L4,L8,...,L100 (25 total)
    static constexpr double CURVE_BASE             = 25.0;
    static constexpr double CURVE_EXPONENT         = 1.95;

    // XP required to advance from `current_level` to `current_level + 1`.
    // At or above MAX_LEVEL this returns 0 (no further XP is accepted).
    static double xp_to_next_level(int current_level) {
        if (current_level >= MAX_LEVEL) {
            return 0.0;
        }
        const int lvl = current_level < MIN_LEVEL ? MIN_LEVEL : current_level;
        return CURVE_BASE * std::pow(static_cast<double>(lvl), CURVE_EXPONENT);
    }

    // The total XP (banked from a clean L1, progress 0) required to first
    // REACH level `target`. This is just the running sum of xp_to_next_level
    // over levels 1..target-1. Handy for tests / trainers; not used by add_xp.
    static double total_xp_to_reach(int target) {
        double total = 0.0;
        for (int L = MIN_LEVEL; L < target && L < MAX_LEVEL; ++L) {
            total += xp_to_next_level(L);
        }
        return total;
    }

    // Result of folding `amount` XP into a (level, progress) state.
    struct Applied {
        int    level;     // new level after the grant (>= the old level)
        double progress;  // leftover XP toward the NEXT level (0 once capped)
    };

    // Return the new (level, leftover progress) after applying `amount` XP to
    // the given starting state. Handles multi-level jumps when `amount` is
    // huge. Mirrors SkillCurve.gd apply_xp() line-for-line.
    static Applied apply_xp(int current_level, double xp_progress, double amount) {
        int    lvl  = current_level;
        double prog = xp_progress + amount;
        while (lvl < MAX_LEVEL) {
            const double need = xp_to_next_level(lvl);
            if (prog < need) {
                break;
            }
            prog -= need;
            lvl  += 1;
        }
        if (lvl >= MAX_LEVEL) {
            prog = 0.0; // the cap stops accumulation entirely
        }
        return Applied{lvl, prog};
    }

    // How many perk milestones a skill at this level has unlocked.
    // Level 4 -> 1 milestone, level 100 -> 25 milestones.
    static int milestones_unlocked(int level) {
        return level / PERK_MILESTONE_INTERVAL;
    }

    // Which milestone index (0..24) does the level just-reached unlock, if any?
    // Returns -1 if this level did not cross a milestone boundary.
    static int milestone_for_level(int level) {
        if (level <= 0 || level > MAX_LEVEL) {
            return -1;
        }
        if (level % PERK_MILESTONE_INTERVAL != 0) {
            return -1;
        }
        return (level / PERK_MILESTONE_INTERVAL) - 1;
    }
};

// ----------------------------------------------------------------------------
// The canonical 12 skills (ports SkillManager.SKILLS exactly, same order).
//
// VERIFIED against scripts/skills/SkillManager.gd lines 14-19. The string ids
// are the contract — combat routing, persistence, and the Journal UI all key
// off these exact spellings.
// ----------------------------------------------------------------------------
inline const std::vector<std::string>& skill_ids() {
    static const std::vector<std::string> ids = {
        "sword", "throwables", "bow",
        "mining", "felling", "excavation", "demolition",
        "lockpicking", "alchemy", "smithing",
        "vitality", "speech",
    };
    return ids;
}

// Is `skill` one of the canonical 12? (ports SkillManager._is_valid_skill)
inline bool is_valid_skill(const std::string& skill) {
    for (const std::string& s : skill_ids()) {
        if (s == skill) {
            return true;
        }
    }
    return false;
}

// ----------------------------------------------------------------------------
// SkillProgression — the per-skill xp/level bookkeeping.
//
// Ports the XP-accounting half of SkillManager.gd (add_xp + the level/progress
// getters). The Godot autoload also handles perks, Legendary resets, signals,
// and active-perk hook dispatch — all of which depend on GameState / the scene
// tree / PerkRegistry, so they are OUT OF SCOPE for the pure Core. What lives
// here is the load-bearing math: the single XP entry point and its level-up
// bookkeeping. Perk-milestone crossings are REPORTED (so an engine wrapper can
// award perk points + fire UI), not actioned.
//
// In Godot the per-skill state lived on GameState as two dictionaries
// (_skill_levels, _skill_xp_progress). Here it is one std::unordered_map from
// skill-id -> SkillState. Same shape, engine-free.
// ----------------------------------------------------------------------------
class SkillProgression {
public:
    // Per-skill state: where on the curve this skill currently sits.
    struct SkillState {
        int    level    = SkillCurve::MIN_LEVEL; // start every skill at L1
        double progress = 0.0;                   // XP banked toward L+1
    };

    // What an add_xp call changed. The engine wrapper turns this into the
    // Godot signals (xp_gained / level_up / perk_milestone_unlocked).
    struct XpResult {
        bool   accepted        = false; // false if skill unknown, amount<=0, or already capped
        int    old_level       = 0;
        int    new_level       = 0;
        double new_progress    = 0.0;
        int    levels_gained   = 0;     // new_level - old_level (>= 0)
        bool   leveled_up      = false; // levels_gained > 0
        int    milestones_hit  = 0;     // how many perk milestones the level-ups crossed
    };

    // Construct with all 12 skills initialized to L1 / progress 0 (mirrors
    // SkillManager._ready() calling GameState.ensure_skill_initialized).
    SkillProgression() {
        for (const std::string& s : skill_ids()) {
            states_[s] = SkillState{};
        }
    }

    // THE single XP entry point. Ports SkillManager.add_xp(skill, amount).
    //
    // Rules carried over exactly:
    //   - amount <= 0 is ignored (no-op, accepted=false).
    //   - an unknown skill is ignored (the Godot version push_warns; we just
    //     return accepted=false — Core can't push warnings).
    //   - a skill already at MAX_LEVEL ignores further XP (accepted=false).
    //   - otherwise the curve folds the grant in, possibly across many levels,
    //     and we report every level-up + every perk milestone crossed.
    XpResult add_xp(const std::string& skill, double amount) {
        XpResult r;
        if (amount <= 0.0) {
            return r; // accepted stays false
        }
        auto it = states_.find(skill);
        if (it == states_.end()) {
            return r; // unknown skill — XP dropped
        }
        SkillState& st = it->second;
        if (st.level >= SkillCurve::MAX_LEVEL) {
            return r; // already capped
        }

        const int old_level = st.level;
        const SkillCurve::Applied applied =
            SkillCurve::apply_xp(st.level, st.progress, amount);

        st.level    = applied.level;
        st.progress = applied.progress;

        r.accepted     = true;
        r.old_level    = old_level;
        r.new_level    = st.level;
        r.new_progress = st.progress;
        r.levels_gained = st.level - old_level;
        r.leveled_up   = r.levels_gained > 0;

        // Walk every level we just crossed and count perk-milestone hits,
        // exactly like the while-loop in SkillManager.add_xp.
        for (int lvl = old_level + 1; lvl <= st.level; ++lvl) {
            if (SkillCurve::milestone_for_level(lvl) >= 0) {
                ++r.milestones_hit;
            }
        }
        return r;
    }

    // --- Read accessors (port SkillManager.get_level / get_xp_progress / get_xp_to_next) ---

    int get_level(const std::string& skill) const {
        auto it = states_.find(skill);
        return it == states_.end() ? 0 : it->second.level;
    }

    double get_xp_progress(const std::string& skill) const {
        auto it = states_.find(skill);
        return it == states_.end() ? 0.0 : it->second.progress;
    }

    double get_xp_to_next(const std::string& skill) const {
        auto it = states_.find(skill);
        if (it == states_.end()) {
            return 0.0;
        }
        return SkillCurve::xp_to_next_level(it->second.level);
    }

    // Direct state read (handy for persistence / tests).
    const SkillState& state_of(const std::string& skill) const {
        static const SkillState empty{};
        auto it = states_.find(skill);
        return it == states_.end() ? empty : it->second;
    }

    // Overwrite a skill's state (ports GameState.set_skill_state — used by
    // save-load and by Legendary reset in the engine wrapper).
    void set_state(const std::string& skill, int level, double progress) {
        auto it = states_.find(skill);
        if (it == states_.end()) {
            return; // never invent skills outside the canonical 12
        }
        if (level < SkillCurve::MIN_LEVEL) level = SkillCurve::MIN_LEVEL;
        if (level > SkillCurve::MAX_LEVEL) level = SkillCurve::MAX_LEVEL;
        it->second.level    = level;
        it->second.progress = (level >= SkillCurve::MAX_LEVEL) ? 0.0 : progress;
    }

private:
    std::unordered_map<std::string, SkillState> states_;
};

} // namespace mira
