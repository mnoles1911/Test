// CombatXPRouter.h — maps combat events to skill-XP grants.
//
// Ported 1:1 from scripts/skills/CombatXPRouter.gd. The Godot version is a
// Node child of Player3D that listens to Enemy3D.damaged / Enemy3D.died and
// the parry hook, then calls SkillManager.add_xp(...). All of that wiring
// (signals, the scene tree, the active-perk dispatch) is engine glue and lives
// in the UE wrapper. What is LOAD-BEARING and ported here is the routing TABLE:
//
//   given a combat event, which skill gets XP, and how much?
//
// That table is pure data + three trivial lookups, so it ports to free
// functions with no state at all. The engine wrapper does:
//
//   XpGrant g = combat_xp_for_hit(weapon_skill);
//   if (g.amount > 0) progression.add_xp(g.skill, (double)g.amount);
//
// ----------------------------------------------------------------------------
// THE NUMBERS (verified against CombatXPRouter.gd lines 16-18 AND the prose in
// design/SKILLS_AND_PROGRESSION.md):
//
//   non-kill hit  : sword 5,  bow 5,  throwables 8
//   kill          : sword 75, bow 75, throwables 50
//   successful parry : 15  (always credited to "sword")
//
// XP grants are INTEGERS in Godot (the dictionaries hold ints; add_xp is
// passed float(amt)). We keep them as int here and let the caller widen to the
// double the curve wants — same as the GDScript `float(amt)` cast.
//
// PURITY: no engine types, std::string only. Unknown weapon skills return a
// grant of 0 (the Godot Dictionary.get(skill, 0) default — XP is simply not
// awarded rather than crashing).

#pragma once

#include <string>

namespace mira {

// A single routed grant: which skill earns XP, and how many points.
// amount == 0 means "no XP for this event" (unknown weapon, etc.).
struct XpGrant {
    std::string skill;       // one of the canonical 12 skill ids ("" if none)
    int         amount = 0;  // XP points to grant (0 = nothing)
};

// ----------------------------------------------------------------------------
// The routing constants — these mirror CombatXPRouter.gd's three dictionaries.
// Kept as plain functions instead of a map so the whole router is header-only,
// constexpr-friendly, and allocation-free.
// ----------------------------------------------------------------------------

// XP for a NON-KILL hit with the given weapon skill (XP_HIT in Godot).
//   sword 5, bow 5, throwables 8 ; anything else -> 0.
inline int combat_hit_xp(const std::string& weapon_skill) {
    if (weapon_skill == "sword")      return 5;
    if (weapon_skill == "bow")        return 5;
    if (weapon_skill == "throwables") return 8;
    return 0;
}

// XP for a KILL with the given weapon skill (XP_KILL in Godot).
//   sword 75, bow 75, throwables 50 ; anything else -> 0.
inline int combat_kill_xp(const std::string& weapon_skill) {
    if (weapon_skill == "sword")      return 75;
    if (weapon_skill == "bow")        return 75;
    if (weapon_skill == "throwables") return 50;
    return 0;
}

// XP for a successful parry (XP_PARRY in Godot). Always credited to "sword"
// (the Godot report_parry_success hard-codes add_xp("sword", XP_PARRY)).
inline constexpr int combat_parry_xp() {
    return 15;
}

// ----------------------------------------------------------------------------
// The high-level routing functions: event -> (skill, amount).
//
// These are what the engine wrapper actually calls. They package the lookups
// above into the full grant so the caller never has to know which skill a
// parry credits to, etc.
// ----------------------------------------------------------------------------

// A non-kill enemy hit with the given weapon skill.
//   -> (weapon_skill, hit_xp)
// Mirrors CombatXPRouter._on_enemy_damaged's skill attribution: the weapon's
// own skill tag earns the XP. (The Godot `last_hit_skill` override is just a
// way for the caller to pick which weapon_skill to pass — the routing is the
// same either way, so it lives caller-side.)
inline XpGrant combat_xp_for_hit(const std::string& weapon_skill) {
    return XpGrant{weapon_skill, combat_hit_xp(weapon_skill)};
}

// A kill with the given weapon skill.
//   -> (weapon_skill, kill_xp)
// Mirrors CombatXPRouter._on_enemy_died.
inline XpGrant combat_xp_for_kill(const std::string& weapon_skill) {
    return XpGrant{weapon_skill, combat_kill_xp(weapon_skill)};
}

// A successful parry.
//   -> ("sword", 15)
// Mirrors CombatXPRouter.report_parry_success.
inline XpGrant combat_xp_for_parry() {
    return XpGrant{"sword", combat_parry_xp()};
}

// Is this string a weapon skill the router actually recognizes? (mirrors the
// guard in CombatXPRouter.set_weapon_skill: only sword/bow/throwables.)
inline bool is_weapon_skill(const std::string& skill) {
    return skill == "sword" || skill == "bow" || skill == "throwables";
}

} // namespace mira
