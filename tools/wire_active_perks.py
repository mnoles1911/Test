#!/usr/bin/env python3
"""Wire the 85 active perks with hook bodies.

Each entry below maps perk_id -> { "hooks": {hook_name: body_str},
"members": [member_var_decl, ...] }.  The script overwrites the
existing stub .gd file at scripts/skills/perks/{skill}/{perk_id}.gd
with the new body. Re-run after editing this file's SPECS.

Bodies fall into a few patterns documented inline at the spec site:
  A. Once-per-thing counter (kept on the perk instance)
  B. Stacking counter with time decay
  C. Conditional ctx mutation (passive logic that needs runtime ctx)
  D. Visual TODO (perks that need future systems — minimap, fear,
     etc.). Hook body prints + logs + leaves a TODO marker.
  E. Loot / drop side effects (call existing inventory/voxel APIs).
"""
from __future__ import annotations
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCRIPT_ROOT = REPO / "scripts" / "skills" / "perks"

HEADER_TEMPLATE = '''extends Perk

# {display}  ({skill} L{lvl}, milestone {ms})
# {desc}
#
# {pattern_note}

{members}

func _init() -> void:
\tpass

{hooks}
'''


# ───────────────────────────────────────────────────────────────────
# SPECS
# Format: perk_id -> {
#   "skill", "display", "lvl", "ms", "desc",
#   "pattern_note", "members", "hooks": {hook_name: body},
# }
# Bodies are inlined into "func {hook_name}(ctx: Dictionary) -> void:"
# Indentation: every line must start with a tab.
# ───────────────────────────────────────────────────────────────────

S: dict = {}


# ===== SWORD =====

S["sword_riposte"] = {
    "hooks": {
        "on_parry": "\t_parry_window_open_until = (Time.get_ticks_msec() / 1000.0) + 2.0",
        "on_attack": (
            "\tvar t: float = Time.get_ticks_msec() / 1000.0\n"
            "\tif ctx.get(\"skill\", \"\") != \"sword\":\n"
            "\t\treturn\n"
            "\tif t > _parry_window_open_until:\n"
            "\t\treturn\n"
            "\tctx[\"damage\"] = int(ctx.get(\"damage\", 0) * 1.50)\n"
            "\tctx[\"riposte_active\"] = true\n"
            "\t_parry_window_open_until = 0.0"
        ),
    },
    "members": ["var _parry_window_open_until: float = 0.0"],
    "pattern_note": "Pattern A: post-parry window (2 s). on_parry opens it, the next sword attack consumes it for +50% damage.",
}

S["sword_disarming_strike"] = {
    "hooks": {
        "on_attack": (
            "\tif ctx.get(\"skill\", \"\") != \"sword\":\n"
            "\t\treturn\n"
            "\tif randf() < 0.05:\n"
            "\t\tvar tgt: Node = ctx.get(\"target\", null)\n"
            "\t\tif tgt != null and tgt.has_method(\"apply_stagger\"):\n"
            "\t\t\ttgt.call(\"apply_stagger\", 1.0)\n"
            "\t\tctx[\"staggered\"] = true"
        ),
    },
    "members": [],
    "pattern_note": "5% proc per sword hit. Calls apply_stagger if the enemy supports it (TODO: stagger system not in production yet — flag is set in ctx for future readers).",
}

S["sword_bleed"] = {
    "hooks": {
        "on_attack": (
            "\tif ctx.get(\"skill\", \"\") != \"sword\":\n"
            "\t\treturn\n"
            "\tvar tgt: Node = ctx.get(\"target\", null)\n"
            "\tif tgt == null:\n"
            "\t\treturn\n"
            "\tif tgt.has_method(\"apply_dot\"):\n"
            "\t\ttgt.call(\"apply_dot\", \"bleed\", 1.0, 6.0)\n"
            "\telse:\n"
            "\t\tctx[\"pending_dot\"] = {\"type\": \"bleed\", \"dps\": 1.0, \"duration\": 6.0}"
        ),
    },
    "members": [],
    "pattern_note": "Apply 1 dmg/s bleed for 6 s. Uses Enemy3D.apply_dot if present, else stashes the DoT request in ctx for whoever wires DoT next.",
}

S["sword_whirlwind"] = {
    "hooks": {
        "on_attack": (
            "\tif not ctx.get(\"power_attack\", false):\n"
            "\t\treturn\n"
            "\tif ctx.get(\"skill\", \"\") != \"sword\":\n"
            "\t\treturn\n"
            "\tctx[\"aoe_radius\"] = max(float(ctx.get(\"aoe_radius\", 0.0)), 1.5)"
        ),
    },
    "members": [],
    "pattern_note": "Power attacks gain a 1.5 m AoE. Caller (combat system) reads ctx.aoe_radius to apply to all enemies in range.",
}

S["sword_thicket"] = {
    "hooks": {
        "on_attack": (
            "\tif ctx.get(\"skill\", \"\") != \"sword\":\n"
            "\t\treturn\n"
            "\tvar extra: int = int(ctx.get(\"extra_enemies\", 0))\n"
            "\tvar bonus: float = clampf(0.10 * float(extra), 0.0, 0.40)\n"
            "\tif bonus > 0.0:\n"
            "\t\tctx[\"damage\"] = int(ctx.get(\"damage\", 0) * (1.0 + bonus))"
        ),
    },
    "members": [],
    "pattern_note": "+10% damage per extra enemy within 3 m, cap +40%. Reads ctx.extra_enemies set by combat code.",
}

S["sword_battle_rhythm"] = {
    "hooks": {
        "on_attack": (
            "\tif ctx.get(\"skill\", \"\") != \"sword\":\n"
            "\t\treturn\n"
            "\tvar t: float = Time.get_ticks_msec() / 1000.0\n"
            "\tif t - _last_hit > 3.0:\n"
            "\t\t_stacks = 0\n"
            "\t_stacks = min(_stacks + 1, 8)\n"
            "\t_last_hit = t\n"
            "\tvar bonus: float = 0.03 * float(_stacks - 1)\n"
            "\tif bonus > 0.0:\n"
            "\t\tctx[\"damage\"] = int(ctx.get(\"damage\", 0) * (1.0 + bonus))"
        ),
    },
    "members": ["var _stacks: int = 0", "var _last_hit: float = 0.0"],
    "pattern_note": "Pattern B: stacking +3% damage per consecutive sword hit (3-s decay window), cap +24%.",
}

S["sword_second_wind"] = {
    "hooks": {
        "on_take_damage": (
            "\tif _used_this_fight:\n"
            "\t\treturn\n"
            "\tif Engine.get_main_loop() == null:\n"
            "\t\treturn\n"
            "\tvar player: Node = Engine.get_main_loop().root.get_node_or_null(\"World3D/Player3D\")\n"
            "\tif player == null:\n"
            "\t\treturn\n"
            "\tvar stam: float = float(player.get(\"endurance\")) if \"endurance\" in player else 0.0\n"
            "\tvar maxstam: float = float(player.get(\"max_endurance\")) if \"max_endurance\" in player else 100.0\n"
            "\tif stam <= 0.01:\n"
            "\t\t_used_this_fight = true\n"
            "\t\tplayer.set(\"endurance\", maxstam * 0.30)"
        ),
        "on_kill": "\t_used_this_fight = false  # arbitrary fight-end heuristic: kill resets the once-per-fight flag",
    },
    "members": ["var _used_this_fight: bool = false"],
    "pattern_note": "Once-per-fight: when stamina hits 0 from damage, refund 30%. Pattern A. Fight-boundary heuristic is reset on kill.",
}

S["sword_swords_dance"] = {
    "hooks": {
        "on_attack": (
            "\tif not ctx.get(\"moving\", false):\n"
            "\t\treturn\n"
            "\tif ctx.get(\"skill\", \"\") != \"sword\":\n"
            "\t\treturn\n"
            "\tctx[\"damage\"] = int(ctx.get(\"damage\", 0) * 1.10)\n"
            "\tctx[\"stamina_cost_mult\"] = float(ctx.get(\"stamina_cost_mult\", 1.0)) * 0.90"
        ),
    },
    "members": [],
    "pattern_note": "Conditional damage + stamina mult while moving with sword drawn. Pattern C.",
}

S["sword_grand_strike"] = {
    "hooks": {
        "on_attack": (
            "\tif ctx.get(\"skill\", \"\") != \"sword\":\n"
            "\t\treturn\n"
            "\tif not ctx.get(\"first_hit\", false):\n"
            "\t\treturn\n"
            "\tctx[\"damage\"] = int(ctx.get(\"damage\", 0) * 1.50)"
        ),
    },
    "members": [],
    "pattern_note": "+50% damage on first sword hit after entering combat. Combat system marks ctx.first_hit on the opening swing.",
}

S["sword_dread_blade"] = {
    "hooks": {
        "on_kill": (
            "\tif ctx.get(\"skill\", \"\") != \"sword\":\n"
            "\t\treturn\n"
            "\tvar tgt: Node = ctx.get(\"target\", null)\n"
            "\tif tgt == null:\n"
            "\t\treturn\n"
            "\tvar origin: Vector3 = tgt.global_position if \"global_position\" in tgt else Vector3.ZERO\n"
            "\tfor n in tgt.get_tree().get_nodes_in_group(\"enemy\"):\n"
            "\t\tif not is_instance_valid(n) or n == tgt:\n"
            "\t\t\tcontinue\n"
            "\t\tif n.global_position.distance_to(origin) <= 5.0:\n"
            "\t\t\tif n.has_method(\"apply_status\"):\n"
            "\t\t\t\tn.call(\"apply_status\", \"feared\", 3.0)"
        ),
    },
    "members": [],
    "pattern_note": "Kill with sword → frighten other enemies within 5 m. Uses Enemy3D.apply_status if it exists (TODO: fear AI state not in production).",
}

S["sword_undying"] = {
    "hooks": {
        "on_take_damage": (
            "\tvar amt: int = int(ctx.get(\"amount\", 0))\n"
            "\tif amt < int(ctx.get(\"self_hp\", 999999)):\n"
            "\t\treturn\n"
            "\tif _used_today:\n"
            "\t\treturn\n"
            "\t_used_today = true\n"
            "\tctx[\"amount\"] = max(int(ctx.get(\"self_hp\", 1)) - 1, 0)\n"
            "\tctx[\"undying_proc\"] = true"
        ),
        "on_xp_gained": "\tpass  # day-boundary reset wired when WorldClock day_changed signal is hooked in",
    },
    "members": ["var _used_today: bool = false"],
    "pattern_note": "Once-per-day: lethal damage leaves player at 1 HP. Caller must populate ctx.self_hp before calling on_take_damage. Day reset wires onto WorldClock.day_changed when that hook lands.",
}


# ===== THROWABLES =====

S["throw_double_grab"] = {
    "hooks": {
        "on_picked": "\tprint(\"[throw_double_grab] Active — drawing a spear pulls 2 (UI surfaces via ThrowableHandler).\")",
    },
    "members": [],
    "pattern_note": "Pure flag perk; ThrowableHandler queries PerkQuery.has_flag(\"spear\") at draw time.",
}

S["throw_ricochet"] = {
    "hooks": {
        "on_attack": (
            "\tif ctx.get(\"skill\", \"\") != \"throwables\":\n"
            "\t\treturn\n"
            "\tif ctx.get(\"surface_hit\", false) and not ctx.get(\"ricochet_used\", false):\n"
            "\t\tctx[\"ricochet_used\"] = true\n"
            "\t\tctx[\"request_ricochet\"] = true"
        ),
    },
    "members": [],
    "pattern_note": "First terrain hit on a thrown spear flips request_ricochet so ThrowableSpear can spawn a follow-up. TODO: ThrowableSpear ricochet path not in production.",
}

S["throw_marked_target"] = {
    "hooks": {
        "on_attack": (
            "\tif ctx.get(\"skill\", \"\") != \"throwables\":\n"
            "\t\treturn\n"
            "\tvar tgt: Node = ctx.get(\"target\", null)\n"
            "\tif tgt == null:\n"
            "\t\treturn\n"
            "\tvar tgt_id: int = tgt.get_instance_id()\n"
            "\tif _marked.has(tgt_id):\n"
            "\t\treturn\n"
            "\t_marked[tgt_id] = (Time.get_ticks_msec() / 1000.0) + 5.0\n"
            "\tif tgt.has_method(\"apply_status\"):\n"
            "\t\ttgt.call(\"apply_status\", \"marked\", 5.0)"
        ),
    },
    "members": ["var _marked: Dictionary = {}"],
    "pattern_note": "First thrown hit marks an enemy for 5 s — they take +20% damage from any source. Combat code reads ctx.target_marked to apply.",
}

S["throw_charged_throw"] = {
    "hooks": {
        "on_attack": (
            "\tif ctx.get(\"skill\", \"\") != \"throwables\":\n"
            "\t\treturn\n"
            "\tif not ctx.get(\"charged\", false):\n"
            "\t\treturn\n"
            "\tctx[\"damage\"] = int(ctx.get(\"damage\", 0) * 1.30)\n"
            "\tctx[\"range_mult\"] = float(ctx.get(\"range_mult\", 1.0)) * 1.10"
        ),
    },
    "members": [],
    "pattern_note": "ThrowableHandler sets ctx.charged when the throw was held ≥1 s before release.",
}

S["throw_blood_arrow"] = {
    "hooks": {
        "on_kill": (
            "\tif ctx.get(\"skill\", \"\") != \"throwables\":\n"
            "\t\treturn\n"
            "\tif Engine.get_main_loop() == null:\n"
            "\t\treturn\n"
            "\tvar player: Node = Engine.get_main_loop().root.get_node_or_null(\"World3D/Player3D\")\n"
            "\tif player == null:\n"
            "\t\treturn\n"
            "\tif \"hp\" in player:\n"
            "\t\tvar cur: float = float(player.get(\"hp\"))\n"
            "\t\tvar mx: float = float(player.get(\"max_hp\")) if \"max_hp\" in player else 100.0\n"
            "\t\tplayer.set(\"hp\", minf(cur + 5.0, mx))"
        ),
    },
    "members": [],
    "pattern_note": "Thrown kill heals player +5 HP. Reads Player3D.hp / max_hp.",
}

S["throw_volley"] = {
    "hooks": {
        "on_attack": (
            "\tif ctx.get(\"skill\", \"\") != \"throwables\":\n"
            "\t\treturn\n"
            "\tvar t: float = Time.get_ticks_msec() / 1000.0\n"
            "\t_next_throw_discount_until = t + 3.0\n"
            "\tctx[\"next_stamina_discount\"] = 0.50"
        ),
    },
    "members": ["var _next_throw_discount_until: float = 0.0"],
    "pattern_note": "Each throw discounts the next one's stamina by 50% for 3 s. ThrowableHandler reads ctx.next_stamina_discount on the following throw.",
}

S["throw_perfect_aim"] = {
    "hooks": {
        "on_attack": (
            "\tif _used_this_combat:\n"
            "\t\treturn\n"
            "\tif ctx.get(\"skill\", \"\") != \"throwables\":\n"
            "\t\treturn\n"
            "\tif not ctx.get(\"first_hit\", false):\n"
            "\t\treturn\n"
            "\t_used_this_combat = true\n"
            "\tctx[\"spread_mult\"] = float(ctx.get(\"spread_mult\", 1.0)) * 0.50"
        ),
        "on_kill": "\t_used_this_combat = false  # crude combat-end reset",
    },
    "members": ["var _used_this_combat: bool = false"],
    "pattern_note": "Once per encounter: first thrown weapon has -50% spread. ThrowableHandler reads ctx.spread_mult at aim time.",
}

S["throw_storm_caller"] = {
    "hooks": {
        "on_attack": (
            "\tif ctx.get(\"skill\", \"\") != \"throwables\":\n"
            "\t\treturn\n"
            "\tif ctx.get(\"detonation_source\", \"\") == \"powder_charge\":\n"
            "\t\tctx[\"chain_explode\"] = true"
        ),
    },
    "members": [],
    "pattern_note": "Powder charges flag chain_explode in ctx so PowderCharge.gd can detect neighboring charges and trigger them. TODO: PowderCharge chain-detect not in production.",
}

S["throw_javelin_storm"] = {
    "hooks": {
        "on_kill": (
            "\tif ctx.get(\"skill\", \"\") != \"throwables\":\n"
            "\t\treturn\n"
            "\tif randf() > 0.50:\n"
            "\t\treturn\n"
            "\tif Engine.get_main_loop() == null:\n"
            "\t\treturn\n"
            "\tvar inv: Node = Engine.get_main_loop().root.get_node_or_null(\"InventoryManager\")\n"
            "\tif inv != null and inv.has_method(\"add_item\"):\n"
            "\t\tinv.call(\"add_item\", \"spear\", 1)"
        ),
    },
    "members": [],
    "pattern_note": "50% chance to refund a spear on thrown kill (the spear may stay stuck in the corpse anyway; this is bonus on top).",
}


# ===== BOW =====

S["bow_silent_kill"] = {
    "hooks": {
        "on_kill": (
            "\tif ctx.get(\"skill\", \"\") != \"bow\":\n"
            "\t\treturn\n"
            "\tif not ctx.get(\"stealth\", false):\n"
            "\t\treturn\n"
            "\tctx[\"suppress_alert\"] = true  # combat / AI systems suppress aggro alert"
        ),
    },
    "members": [],
    "pattern_note": "Out-of-combat bow kills don't alert nearby enemies. Sets ctx.suppress_alert flag. TODO: stealth/aggro broadcast not wired yet.",
}

S["bow_focus"] = {
    "hooks": {
        "on_attack": (
            "\tif not ctx.get(\"draw_hold\", false):\n"
            "\t\treturn\n"
            "\tif ctx.get(\"skill\", \"\") != \"bow\":\n"
            "\t\treturn\n"
            "\tEngine.time_scale = 0.75\n"
            "\tif Engine.get_main_loop() != null:\n"
            "\t\tEngine.get_main_loop().create_timer(3.0).timeout.connect(_restore_time)"
        ),
        "on_picked": "\tpass",
    },
    "members": [
        "func _restore_time() -> void:",
        "\tEngine.time_scale = 1.0",
    ],
    "pattern_note": "Bow draw-and-hold triggers 25% time dilation for up to 3 s. Restores via SceneTree timer.",
}

S["bow_double_nock"] = {
    "hooks": {
        "on_attack": (
            "\tif ctx.get(\"skill\", \"\") != \"bow\":\n"
            "\t\treturn\n"
            "\tif randf() < 0.10:\n"
            "\t\tctx[\"fire_extra_arrow\"] = true"
        ),
    },
    "members": [],
    "pattern_note": "10% proc: caller fires a second arrow. TODO: bow firing system not in production.",
}

S["bow_bleed_arrows"] = {
    "hooks": {
        "on_attack": (
            "\tif ctx.get(\"skill\", \"\") != \"bow\":\n"
            "\t\treturn\n"
            "\tvar tgt: Node = ctx.get(\"target\", null)\n"
            "\tif tgt != null and tgt.has_method(\"apply_dot\"):\n"
            "\t\ttgt.call(\"apply_dot\", \"bleed\", 1.0, 6.0)"
        ),
    },
    "members": [],
    "pattern_note": "Apply 1 dmg/s bleed for 6 s on bow hit.",
}

S["bow_fire_arrows"] = {
    "hooks": {
        "on_attack": (
            "\tif ctx.get(\"skill\", \"\") != \"bow\":\n"
            "\t\treturn\n"
            "\tvar tgt: Node = ctx.get(\"target\", null)\n"
            "\tif tgt != null and tgt.has_method(\"apply_dot\"):\n"
            "\t\ttgt.call(\"apply_dot\", \"burn\", 2.0, 4.0)"
        ),
    },
    "members": [],
    "pattern_note": "Apply 2 dmg/s burn for 4 s on bow hit.",
}

S["bow_volley"] = {
    "hooks": {
        "on_attack": (
            "\tif ctx.get(\"skill\", \"\") != \"bow\":\n"
            "\t\treturn\n"
            "\tvar t: float = Time.get_ticks_msec() / 1000.0\n"
            "\tif t - _last_hit > 3.0:\n"
            "\t\t_stacks = 0\n"
            "\t_stacks = min(_stacks + 1, 6)\n"
            "\t_last_hit = t\n"
            "\tvar bonus: float = 0.05 * float(_stacks - 1)\n"
            "\tif bonus > 0.0:\n"
            "\t\tctx[\"damage\"] = int(ctx.get(\"damage\", 0) * (1.0 + bonus))"
        ),
    },
    "members": ["var _stacks: int = 0", "var _last_hit: float = 0.0"],
    "pattern_note": "Pattern B: +5% per consecutive bow hit, 3-s decay, cap +30%.",
}

S["bow_pincushion"] = {
    "hooks": {
        "on_attack": (
            "\tif ctx.get(\"skill\", \"\") != \"bow\":\n"
            "\t\treturn\n"
            "\tvar tgt: Node = ctx.get(\"target\", null)\n"
            "\tif tgt == null:\n"
            "\t\treturn\n"
            "\tvar id: int = tgt.get_instance_id()\n"
            "\tvar arrows: int = int(_lodged.get(id, 0))\n"
            "\tif arrows > 0:\n"
            "\t\tvar bonus: float = clampf(0.05 * float(arrows), 0.0, 0.25)\n"
            "\t\tctx[\"damage\"] = int(ctx.get(\"damage\", 0) * (1.0 + bonus))\n"
            "\t_lodged[id] = arrows + 1"
        ),
    },
    "members": ["var _lodged: Dictionary = {}"],
    "pattern_note": "Each arrow lodged in an enemy adds +5% damage to the next shot, cap +25%. Tracks per-instance arrow counts.",
}

S["bow_third_eye"] = {
    "hooks": {
        "on_attack": (
            "\tif ctx.get(\"skill\", \"\") != \"bow\":\n"
            "\t\treturn\n"
            "\tvar tgt: Node = ctx.get(\"target\", null)\n"
            "\tif tgt != null and tgt.has_method(\"set_xray_outline\"):\n"
            "\t\ttgt.call(\"set_xray_outline\", true, 5.0)"
        ),
    },
    "members": [],
    "pattern_note": "Bow hit outlines target through walls for 5 s. TODO: x-ray outline shader pass not in production.",
}


# ===== MINING =====

S["mine_vein_sense"] = {
    "hooks": {
        "on_picked": "\tprint(\"[mine_vein_sense] Active — ore-vein highlights when pickaxe drawn (renderer hook pending).\")",
    },
    "members": [],
    "pattern_note": "Visual perk. EditToolHandler queries PerkQuery.has_flag(\"ore\", \"while_pickaxe\") to enable highlight.",
}

S["mine_ore_sense"] = {
    "hooks": {
        "on_picked": "\tprint(\"[mine_ore_sense] Active — minimap pings ore within 16 m (minimap pending).\")",
    },
    "members": [],
    "pattern_note": "Minimap system not in production; perk registers as active so it shows owned.",
}

S["mine_swing_through"] = {
    "hooks": {
        "on_voxel_broken": (
            "\tif ctx.get(\"skill\", \"\") != \"mining\":\n"
            "\t\treturn\n"
            "\tctx[\"extra_adjacent_breaks\"] = max(int(ctx.get(\"extra_adjacent_breaks\", 0)), 1)"
        ),
    },
    "members": [],
    "pattern_note": "EditToolHandler reads extra_adjacent_breaks after the primary break to fire additional carves on same-material neighbors.",
}

S["mine_lucky_strike"] = {
    "hooks": {
        "on_voxel_broken": (
            "\tif ctx.get(\"skill\", \"\") != \"mining\":\n"
            "\t\treturn\n"
            "\tif randf() > 0.05:\n"
            "\t\treturn\n"
            "\tif Engine.get_main_loop() == null:\n"
            "\t\treturn\n"
            "\tvar inv: Node = Engine.get_main_loop().root.get_node_or_null(\"InventoryManager\")\n"
            "\tif inv != null and inv.has_method(\"add_item\"):\n"
            "\t\tinv.call(\"add_item\", \"raw_marble\", 1)  # gem stand-in until gem item id lands"
        ),
    },
    "members": [],
    "pattern_note": "5% per mining break: spawn bonus drop. Uses marble as a stand-in until a gem item id is added.",
}

S["mine_relentless"] = {
    "hooks": {
        "on_voxel_broken": (
            "\tif ctx.get(\"skill\", \"\") != \"mining\":\n"
            "\t\treturn\n"
            "\tif Engine.get_main_loop() == null:\n"
            "\t\treturn\n"
            "\tvar player: Node = Engine.get_main_loop().root.get_node_or_null(\"World3D/Player3D\")\n"
            "\tif player == null or not \"endurance\" in player:\n"
            "\t\treturn\n"
            "\tvar mx: float = float(player.get(\"max_endurance\")) if \"max_endurance\" in player else 100.0\n"
            "\tplayer.set(\"endurance\", mx)"
        ),
    },
    "members": [],
    "pattern_note": "Refill stamina to full on every mining break — equivalent to 100% regen while actively mining.",
}


# ===== FELLING =====

S["fell_tree_sense"] = {
    "hooks": {
        "on_picked": "\tprint(\"[fell_tree_sense] Active — tree felling-line highlight when axe drawn (renderer hook pending).\")",
    },
    "members": [],
    "pattern_note": "Visual TODO.",
}

S["fell_double_strike"] = {
    "hooks": {
        "on_voxel_broken": (
            "\tif ctx.get(\"skill\", \"\") != \"felling\":\n"
            "\t\treturn\n"
            "\tif randf() < 0.10:\n"
            "\t\tctx[\"double_strike\"] = true"
        ),
    },
    "members": [],
    "pattern_note": "10% proc: caller fires an extra hit. EditToolHandler reads ctx.double_strike.",
}

S["fell_branch_break"] = {
    "hooks": {
        "on_voxel_broken": (
            "\tif ctx.get(\"skill\", \"\") != \"felling\":\n"
            "\t\treturn\n"
            "\tif not ctx.get(\"on_tree_break\", false):\n"
            "\t\treturn\n"
            "\tif Engine.get_main_loop() == null:\n"
            "\t\treturn\n"
            "\tvar inv: Node = Engine.get_main_loop().root.get_node_or_null(\"InventoryManager\")\n"
            "\tif inv != null and inv.has_method(\"add_item\"):\n"
            "\t\tinv.call(\"add_item\", \"raw_leaves\", 2)  # kindling stand-in"
        ),
    },
    "members": [],
    "pattern_note": "Tree fell → kindling. Uses raw_leaves as kindling stand-in until a kindling item lands.",
}

S["fell_select_cut"] = {
    "hooks": {
        "on_voxel_broken": (
            "\tif ctx.get(\"skill\", \"\") != \"felling\":\n"
            "\t\treturn\n"
            "\tif not ctx.get(\"on_tree_break\", false):\n"
            "\t\treturn\n"
            "\tif Engine.get_main_loop() == null:\n"
            "\t\treturn\n"
            "\tvar sm: Node = Engine.get_main_loop().root.get_node_or_null(\"SkillManager\")\n"
            "\tif sm == null:\n"
            "\t\treturn\n"
            "\tfor s in [\"mining\", \"excavation\", \"smithing\", \"alchemy\"]:\n"
            "\t\tsm.call(\"add_xp\", s, 1.0)"
        ),
    },
    "members": [],
    "pattern_note": "Each tree felled grants a small XP nudge to other crafting skills.",
}

S["fell_axe_thrower"] = {
    "hooks": {
        "on_picked": "\tprint(\"[fell_axe_thrower] Active — axes can be thrown (ThrowableHandler reads flag at draw time).\")",
    },
    "members": [],
    "pattern_note": "Flag perk. ThrowableHandler checks PerkQuery.has_flag(\"axe\") when LMB-throw is held on an axe.",
}

S["fell_evergreen"] = {
    "hooks": {
        "on_voxel_broken": (
            "\tif ctx.get(\"skill\", \"\") != \"felling\":\n"
            "\t\treturn\n"
            "\tif not ctx.get(\"on_tree_break\", false):\n"
            "\t\treturn\n"
            "\t_trees_felled += 1\n"
            "\tif _trees_felled % 10 != 0:\n"
            "\t\treturn\n"
            "\tif Engine.get_main_loop() == null:\n"
            "\t\treturn\n"
            "\tvar inv: Node = Engine.get_main_loop().root.get_node_or_null(\"InventoryManager\")\n"
            "\tif inv != null and inv.has_method(\"add_item\"):\n"
            "\t\tinv.call(\"add_item\", \"raw_leaves\", 1)  # sapling stand-in"
        ),
    },
    "members": ["var _trees_felled: int = 0"],
    "pattern_note": "Every 10th tree felled drops a sapling (placeholder: raw_leaves).",
}

S["fell_split_wood"] = {
    "hooks": {
        "on_kill": (
            "\tif ctx.get(\"skill\", \"\") != \"sword\" and ctx.get(\"weapon\", \"\") != \"axe\":\n"
            "\t\treturn\n"
            "\tif Engine.get_main_loop() == null:\n"
            "\t\treturn\n"
            "\tvar inv: Node = Engine.get_main_loop().root.get_node_or_null(\"InventoryManager\")\n"
            "\tif inv != null and inv.has_method(\"add_item\"):\n"
            "\t\tinv.call(\"add_item\", \"raw_leaves\", 1)"
        ),
    },
    "members": [],
    "pattern_note": "Axe-killing an enemy drops kindling.",
}


# ===== EXCAVATION =====

def _voxel_skill_check(skill: str) -> str:
    return f"\tif ctx.get(\"skill\", \"\") != \"{skill}\":\n\t\treturn"


S["dig_clay_finder"] = {
    "hooks": {
        "on_voxel_broken": (
            _voxel_skill_check("excavation") + "\n"
            "\tif not ctx.get(\"near_water\", false):\n"
            "\t\treturn\n"
            "\tif randf() > 0.25:\n"
            "\t\treturn\n"
            "\tif Engine.get_main_loop() == null:\n"
            "\t\treturn\n"
            "\tvar inv: Node = Engine.get_main_loop().root.get_node_or_null(\"InventoryManager\")\n"
            "\tif inv != null and inv.has_method(\"add_item\"):\n"
            "\t\tinv.call(\"add_item\", \"raw_clay\", 1)"
        ),
    },
    "members": [],
    "pattern_note": "25% proc near water: clay drop.",
}

S["dig_gravel_finder"] = {
    "hooks": {
        "on_voxel_broken": (
            _voxel_skill_check("excavation") + "\n"
            "\tif not ctx.get(\"near_water\", false):\n"
            "\t\treturn\n"
            "\tif randf() > 0.25:\n"
            "\t\treturn\n"
            "\tif Engine.get_main_loop() == null:\n"
            "\t\treturn\n"
            "\tvar inv: Node = Engine.get_main_loop().root.get_node_or_null(\"InventoryManager\")\n"
            "\tif inv != null and inv.has_method(\"add_item\"):\n"
            "\t\tinv.call(\"add_item\", \"raw_gravel\", 1)"
        ),
    },
    "members": [],
    "pattern_note": "25% proc near water: gravel drop.",
}

S["dig_bury"] = {
    "hooks": {
        "on_voxel_broken": (
            _voxel_skill_check("excavation") + "\n"
            "\tctx[\"spawn_dirt_at_player\"] = true"
        ),
    },
    "members": [],
    "pattern_note": "Flag for EditToolHandler to place a dirt voxel at the player's feet after a shovel swing (TODO: place-voxel path not in production for this trigger).",
}

S["dig_grave_robber"] = {
    "hooks": {
        "on_voxel_broken": (
            _voxel_skill_check("excavation") + "\n"
            "\tif not ctx.get(\"on_corpse\", false):\n"
            "\t\treturn\n"
            "\tif Engine.get_main_loop() == null:\n"
            "\t\treturn\n"
            "\tvar inv: Node = Engine.get_main_loop().root.get_node_or_null(\"InventoryManager\")\n"
            "\tif inv != null and inv.has_method(\"add_item\"):\n"
            "\t\tvar candidates: PackedStringArray = [\"raw_clay\", \"raw_gravel\", \"copper_ore\"]\n"
            "\t\tinv.call(\"add_item\", candidates[randi() % candidates.size()], 1)"
        ),
    },
    "members": [],
    "pattern_note": "Digging on a corpse yields a random crafting mat.",
}

S["dig_field_medic"] = {
    "hooks": {
        "on_voxel_broken": (
            _voxel_skill_check("excavation") + "\n"
            "\tif not ctx.get(\"on_corpse\", false):\n"
            "\t\treturn\n"
            "\tif Engine.get_main_loop() == null:\n"
            "\t\treturn\n"
            "\tvar p: Node = Engine.get_main_loop().root.get_node_or_null(\"World3D/Player3D\")\n"
            "\tif p == null or not \"hp\" in p:\n"
            "\t\treturn\n"
            "\tvar cur: float = float(p.get(\"hp\"))\n"
            "\tvar mx: float = float(p.get(\"max_hp\")) if \"max_hp\" in p else 100.0\n"
            "\tp.set(\"hp\", minf(cur + 5.0, mx))"
        ),
    },
    "members": [],
    "pattern_note": "Heal +5 HP per corpse excavation tick.",
}

S["dig_quickburial"] = {
    "hooks": {
        "on_voxel_broken": (
            _voxel_skill_check("excavation") + "\n"
            "\tif not ctx.get(\"on_corpse\", false):\n"
            "\t\treturn\n"
            "\tif Engine.get_main_loop() == null:\n"
            "\t\treturn\n"
            "\tvar p: Node = Engine.get_main_loop().root.get_node_or_null(\"World3D/Player3D\")\n"
            "\tif p == null or not \"endurance\" in p:\n"
            "\t\treturn\n"
            "\tvar mx: float = float(p.get(\"max_endurance\")) if \"max_endurance\" in p else 100.0\n"
            "\tp.set(\"endurance\", mx)"
        ),
    },
    "members": [],
    "pattern_note": "Refill stamina to full after burying a corpse.",
}

S["dig_terrain_eye"] = {
    "hooks": {
        "on_picked": "\tprint(\"[dig_terrain_eye] Active — buried objects highlight within 4 m (renderer pending).\")",
    },
    "members": [],
    "pattern_note": "Visual TODO.",
}

S["dig_water_finder"] = {
    "hooks": {
        "on_picked": "\tprint(\"[dig_water_finder] Active — minimap pings water table within 12 m (minimap pending).\")",
    },
    "members": [],
    "pattern_note": "Visual TODO.",
}

S["dig_archeologist"] = {
    "hooks": {
        "on_voxel_broken": (
            _voxel_skill_check("excavation") + "\n"
            "\tif randf() > 0.05:\n"
            "\t\treturn\n"
            "\tif Engine.get_main_loop() == null:\n"
            "\t\treturn\n"
            "\tvar inv: Node = Engine.get_main_loop().root.get_node_or_null(\"InventoryManager\")\n"
            "\tif inv == null:\n"
            "\t\treturn\n"
            "\tif inv.has_method(\"add_coin\"):\n"
            "\t\tinv.call(\"add_coin\", 5)"
        ),
    },
    "members": [],
    "pattern_note": "5% per dig: unearth a small treasure (5 coin).",
}

S["dig_no_traps"] = {
    "hooks": {
        "on_picked": "\tprint(\"[dig_no_traps] Active — pressure plates highlight within 4 m (trap system pending).\")",
    },
    "members": [],
    "pattern_note": "Trap system not in production.",
}


# ===== DEMOLITION =====

S["demo_proximity"] = {
    "hooks": {
        "on_picked": "\tprint(\"[demo_proximity] Active — PowderCharge reads PerkQuery.has_flag('explosives','') to detonate on enemy contact.\")",
    },
    "members": [],
    "pattern_note": "Flag for PowderCharge — body_entered already exists; the trigger check (any solid body) already detonates on enemy contact too, so this perk is effectively already 'on' once PowderCharge reads the flag.",
}

S["demo_chain"] = {
    "hooks": {
        "on_attack": (
            "\tif ctx.get(\"detonation_source\", \"\") != \"powder_charge\":\n"
            "\t\treturn\n"
            "\tif randf() < 0.50:\n"
            "\t\tctx[\"chain_explode\"] = true"
        ),
    },
    "members": [],
    "pattern_note": "PowderCharge dispatches on_attack with detonation_source set; perk flags chain_explode for the engine to detonate neighbors.",
}

S["demo_focused_blast"] = {
    "hooks": {
        "on_attack": (
            "\tif ctx.get(\"detonation_source\", \"\") != \"powder_charge\":\n"
            "\t\treturn\n"
            "\tif not ctx.get(\"cone_forward\", false):\n"
            "\t\treturn\n"
            "\tctx[\"damage\"] = int(ctx.get(\"damage\", 0) * 1.30)"
        ),
    },
    "members": [],
    "pattern_note": "Demo system sets ctx.cone_forward for enemies in a 30° forward cone.",
}

S["demo_smoker"] = {
    "hooks": {
        "on_attack": (
            "\tif ctx.get(\"detonation_source\", \"\") != \"powder_charge\":\n"
            "\t\treturn\n"
            "\tctx[\"leave_smoke_seconds\"] = 5.0"
        ),
    },
    "members": [],
    "pattern_note": "Sets a flag for PowderCharge to spawn a 5-s smoke cloud (TODO: smoke particle scene not in production).",
}

S["demo_charge_recovery"] = {
    "hooks": {
        "on_attack": (
            "\tif ctx.get(\"detonation_source\", \"\") != \"powder_charge\":\n"
            "\t\treturn\n"
            "\tif not ctx.get(\"is_dud\", false):\n"
            "\t\treturn\n"
            "\tif randf() > 0.10:\n"
            "\t\treturn\n"
            "\tif Engine.get_main_loop() == null:\n"
            "\t\treturn\n"
            "\tvar inv: Node = Engine.get_main_loop().root.get_node_or_null(\"InventoryManager\")\n"
            "\tif inv != null and inv.has_method(\"add_item\"):\n"
            "\t\tinv.call(\"add_item\", \"powder_charge\", 1)"
        ),
    },
    "members": [],
    "pattern_note": "10% recovery chance when a charge fails to detonate. PowderCharge currently never marks duds, so this is wired but dormant.",
}

S["demo_concussion"] = {
    "hooks": {
        "on_attack": (
            "\tif ctx.get(\"detonation_source\", \"\") != \"powder_charge\":\n"
            "\t\treturn\n"
            "\tvar pos: Vector3 = ctx.get(\"world_pos\", Vector3.ZERO)\n"
            "\tif Engine.get_main_loop() == null:\n"
            "\t\treturn\n"
            "\tfor n in Engine.get_main_loop().get_nodes_in_group(\"enemy\"):\n"
            "\t\tif not is_instance_valid(n):\n"
            "\t\t\tcontinue\n"
            "\t\tif n.global_position.distance_to(pos) <= 4.0:\n"
            "\t\t\tif n.has_method(\"apply_status\"):\n"
            "\t\t\t\tn.call(\"apply_status\", \"stunned\", 1.0)"
        ),
    },
    "members": [],
    "pattern_note": "Stun enemies within 4 m of detonation for 1 s. Calls Enemy3D.apply_status if present.",
}

S["demo_blast_eyes"] = {
    "hooks": {
        "on_picked": "\tprint(\"[demo_blast_eyes] Active — outline enemies inside next explosion zone (renderer pending).\")",
    },
    "members": [],
    "pattern_note": "Visual TODO.",
}


# ===== LOCKPICKING =====

S["lock_thief_eye"] = {
    "hooks": {
        "on_picked": "\tprint(\"[lock_thief_eye] Active — locked containers outline within 8 m (renderer pending).\")",
    },
    "members": [],
    "pattern_note": "Visual TODO.",
}

S["lock_silver_pick"] = {
    "hooks": {
        "on_lock_opened": "\tpass  # Logged by LockObject3D when the perk auto-resolves the lock (gate handled at lock-open time via PerkQuery.has_flag).",
    },
    "members": [],
    "pattern_note": "Flag perk — LockObject3D reads PerkQuery.has_flag('lock','tier_1') and auto-opens tier-1 locks. Hook fires after the open is granted.",
}

S["lock_pickpocket"] = {
    "hooks": {
        "on_picked": "\tprint(\"[lock_pickpocket] Active — pickpocket without alerting NPCs (pickpocket system pending).\")",
    },
    "members": [],
    "pattern_note": "Pickpocket system not in production.",
}

S["lock_double_loot"] = {
    "hooks": {
        "on_lock_opened": (
            "\tif Engine.get_main_loop() == null:\n"
            "\t\treturn\n"
            "\tvar inv: Node = Engine.get_main_loop().root.get_node_or_null(\"InventoryManager\")\n"
            "\tif inv == null or not inv.has_method(\"add_item\"):\n"
            "\t\treturn\n"
            "\tvar pool: PackedStringArray = [\"potion_healing\", \"potion_stamina\", \"lockpick_standard\"]\n"
            "\tinv.call(\"add_item\", pool[randi() % pool.size()], 1)"
        ),
    },
    "members": [],
    "pattern_note": "Random consumable on every lock open.",
}

S["lock_hidden_caches"] = {
    "hooks": {
        "on_picked": "\tprint(\"[lock_hidden_caches] Active — hidden cache markers within 16 m (cache system pending).\")",
    },
    "members": [],
    "pattern_note": "Cache discovery system not in production.",
}

S["lock_keen_eye"] = {
    "hooks": {
        "on_lock_opened": "\tpass  # LockpickingUI reads PerkQuery.has_flag('lock','on_enter') at open time to flash sweet spot.",
    },
    "members": [],
    "pattern_note": "Flag for LockpickingUI hint.",
}

S["lock_burglar"] = {
    "hooks": {
        "on_lock_opened": (
            "\t_attempts_today += 1\n"
            "\tif _attempts_today >= 3:\n"
            "\t\tprint(\"[lock_burglar] Speed-up active (3rd+ attempt this evening).\")"
        ),
    },
    "members": ["var _attempts_today: int = 0"],
    "pattern_note": "After 3rd+ attempt this evening, picking is 30% faster. LockpickingUI reads PerkQuery (with ctx.attempts >= 3) at start.",
}

S["lock_decoy"] = {
    "hooks": {
        "on_picked": "\tprint(\"[lock_decoy] Active — drop fake pick distracts patrolling NPCs (AI system pending).\")",
    },
    "members": [],
    "pattern_note": "NPC distraction system not in production.",
}

S["lock_perfect_pick"] = {
    "hooks": {
        "on_lock_opened": (
            "\tif _used_today:\n"
            "\t\treturn\n"
            "\tvar tier: int = int(ctx.get(\"tier\", 0))\n"
            "\tif tier > 1:\n"
            "\t\treturn\n"
            "\tif not ctx.get(\"first_per_day\", false):\n"
            "\t\treturn\n"
            "\t_used_today = true\n"
            "\tctx[\"perfect_pick_fired\"] = true"
        ),
    },
    "members": ["var _used_today: bool = false"],
    "pattern_note": "Auto-resolve first tier-≤2 lock per day. LockObject3D dispatches on_lock_opened with first_per_day=true before opening; the perk flips ctx.perfect_pick_fired to signal acceptance.",
}


# ===== ALCHEMY =====

S["alch_keen_nose"] = {
    "hooks": {
        "on_picked": "\tprint(\"[alch_keen_nose] Active — herb gather points highlight within 8 m (renderer pending).\")",
    },
    "members": [],
    "pattern_note": "Visual TODO.",
}

S["alch_taster"] = {
    "hooks": {
        "on_picked": "\tprint(\"[alch_taster] Active — taste an unknown ingredient to reveal first effect (UI pending).\")",
    },
    "members": [],
    "pattern_note": "Ingredient taste flow not in production.",
}

S["alch_poisoner"] = {
    "hooks": {
        "on_picked": "\tprint(\"[alch_poisoner] Active — apply blade poison from inventory (oil-coat UI pending).\")",
    },
    "members": [],
    "pattern_note": "Blade-coat UI not in production.",
}

S["alch_double_brew"] = {
    "hooks": {
        "on_potion_drunk": "\tpass  # AlchemyStation reads PerkQuery.sum('proc_chance', 'potion', {'on_craft': true}) at craft time.",
    },
    "members": [],
    "pattern_note": "Wired at craft-time, not consumption-time. Hook here is a no-op intentionally.",
}

S["alch_recipe_eye"] = {
    "hooks": {
        "on_picked": "\tprint(\"[alch_recipe_eye] Active — recipe matches highlight in cauldron UI (UI pending).\")",
    },
    "members": [],
    "pattern_note": "Recipe UI not in production.",
}

S["alch_versatility"] = {
    "hooks": {
        "on_potion_drunk": "\tpass  # Effect: drinking 2 potions within 5 s bypasses stack rules. Potion-stack manager (when wired) checks PerkQuery.has_flag('potion','').",
    },
    "members": [],
    "pattern_note": "Wired via flag query at stack-check time.",
}


# ===== SMITHING =====

S["smith_master_form"] = {
    "hooks": {
        "on_attack": (
            "\tif not ctx.get(\"self_made\", false):\n"
            "\t\treturn\n"
            "\tctx[\"damage\"] = int(ctx.get(\"damage\", 0) * 1.05)"
        ),
    },
    "members": [],
    "pattern_note": "+5% damage when using a weapon Roland smithed himself. Combat code sets ctx.self_made by reading the equipped item's metadata.",
}

S["smith_runed"] = {
    "hooks": {
        "on_picked": "\tprint(\"[smith_runed] Active — 1/5 forge crafts produce +1 quality result (SmithingForge reads PerkQuery on craft).\")",
    },
    "members": [],
    "pattern_note": "Wired at craft-time in SmithingForge.",
}

S["smith_legendary_form"] = {
    "hooks": {
        "on_picked": "\tprint(\"[smith_legendary_form] Active — perfect-rhythm crafts get +1 tier (SmithingForge reads PerkQuery).\")",
    },
    "members": [],
    "pattern_note": "Wired at craft-time.",
}

S["smith_recipe_eye"] = {
    "hooks": {
        "on_picked": "\tprint(\"[smith_recipe_eye] Active — forge UI highlights recipe-matching ingredients (UI pending).\")",
    },
    "members": [],
    "pattern_note": "Forge UI not in production.",
}


# ===== VITALITY =====

S["vit_well_rested"] = {
    "hooks": {
        "on_xp_gained": (
            "\tif not _rested_until_unix > 0:\n"
            "\t\treturn\n"
            "\tvar now: int = int(Time.get_unix_time_from_system())\n"
            "\tif now > _rested_until_unix:\n"
            "\t\t_rested_until_unix = 0\n"
            "\t\treturn\n"
            "\tvar amt: float = float(ctx.get(\"amount\", 0.0))\n"
            "\tif amt <= 0.0:\n"
            "\t\treturn\n"
            "\tvar bonus: float = amt * 0.10\n"
            "\tvar skill: String = String(ctx.get(\"skill\", \"\"))\n"
            "\tif skill == \"\" or Engine.get_main_loop() == null:\n"
            "\t\treturn\n"
            "\tvar sm: Node = Engine.get_main_loop().root.get_node_or_null(\"SkillManager\")\n"
            "\tif sm != null and sm.has_method(\"add_xp\"):\n"
            "\t\t# Cap recursion: don't double-fire the on_xp_gained hook.\n"
            "\t\t_in_bonus = true\n"
            "\t\tif not _in_bonus_reentry:\n"
            "\t\t\t_in_bonus_reentry = true\n"
            "\t\t\tsm.call(\"add_xp\", skill, bonus)\n"
            "\t\t\t_in_bonus_reentry = false"
        ),
        "on_picked": "\tpass  # Caller (rest system) sets _rested_until_unix to (now + 86400) on sleeping.",
    },
    "members": [
        "var _rested_until_unix: int = 0",
        "var _in_bonus: bool = false",
        "var _in_bonus_reentry: bool = false",
    ],
    "pattern_note": "Pattern A daily-ish flag. Rest system pokes _rested_until_unix when Roland sleeps. Re-entry guard prevents infinite hook recursion.",
}

S["vit_second_chance"] = {
    "hooks": {
        "on_take_damage": (
            "\tif _used_today:\n"
            "\t\treturn\n"
            "\tvar amt: int = int(ctx.get(\"amount\", 0))\n"
            "\tif amt < int(ctx.get(\"self_hp\", 999999)):\n"
            "\t\treturn\n"
            "\t_used_today = true\n"
            "\tctx[\"amount\"] = max(int(ctx.get(\"self_hp\", 1)) - 1, 0)\n"
            "\tctx[\"second_chance_proc\"] = true"
        ),
    },
    "members": ["var _used_today: bool = false"],
    "pattern_note": "Same shape as sword_undying but on Vitality instead of Sword.",
}


# ===== SPEECH =====

S["speech_bard"] = {
    "hooks": {
        "on_picked": "\tprint(\"[speech_bard] Active — tavern song grants +10 disposition to nearby NPCs (tavern-song trigger pending).\")",
    },
    "members": [],
    "pattern_note": "Tavern song trigger not in production.",
}

S["speech_blackmail"] = {
    "hooks": {
        "on_picked": "\tprint(\"[speech_blackmail] Active — failed speech checks reveal leverage 25% of the time (SpeechCheckBroker reads on fail).\")",
    },
    "members": [],
    "pattern_note": "Wired at fail-resolution time inside SpeechCheckBroker.",
}

S["speech_calm"] = {
    "hooks": {
        "on_picked": "\tprint(\"[speech_calm] Active — reduce nearby enemy aggression for 5 s once per encounter (AI aggro hook pending).\")",
    },
    "members": [],
    "pattern_note": "Enemy aggression system not in production.",
}

S["speech_diplomat"] = {
    "hooks": {
        "on_picked": "\tprint(\"[speech_diplomat] Active — +10 disposition with a chosen faction (UI to pick faction pending).\")",
    },
    "members": [],
    "pattern_note": "Faction-pick UI not in production.",
}

S["speech_inspire"] = {
    "hooks": {
        "on_picked": "\tprint(\"[speech_inspire] Active — companion damage +10% for 30 s after a speech (companion buff system pending).\")",
    },
    "members": [],
    "pattern_note": "Companion buff system not in production.",
}

S["speech_oratorical"] = {
    "hooks": {
        "on_picked": "\tprint(\"[speech_oratorical] Active — persuade checks succeed at DC 5 above your Speech (SpeechCheckBroker reads PerkQuery at check time).\")",
    },
    "members": [],
    "pattern_note": "Wired at check time in SpeechCheckBroker.",
}

S["speech_quick_tongue"] = {
    "hooks": {
        "on_picked": "\tprint(\"[speech_quick_tongue] Active — speech checks can be retried once after fail (SpeechCheckBroker reads PerkQuery at fail).\")",
    },
    "members": [],
    "pattern_note": "Wired at fail time in SpeechCheckBroker.",
}


# ───────────────────────────────────────────────────────────────────
# Default body for any active perk not given a custom spec above:
# print a one-liner so the perk announces itself and document the
# missing dep.
# ───────────────────────────────────────────────────────────────────

def default_spec(perk_id: str, display: str, desc: str) -> dict:
    body = f"\tprint(\"[{perk_id}] Active — effect TODO: backing gameplay system pending.\")"
    return {
        "hooks": {"on_picked": body},
        "members": [],
        "pattern_note": "Default stub. Replace with a real spec when the backing system lands.",
    }


# ───────────────────────────────────────────────────────────────────
# Emitter
# ───────────────────────────────────────────────────────────────────

TRES_ROOT = REPO / "assets" / "skills" / "perks"


def parse_existing(path: Path) -> dict:
    """Read display_name / desc / lvl / ms / skill from the matching
    .tres resource. The .tres is the source of truth; the .gd file is
    a build artifact that wire_active_perks.py overwrites on each run."""
    perk_id = path.stem
    skill = path.parent.name
    tres = TRES_ROOT / skill / f"{perk_id}.tres"
    out = {"display": perk_id, "skill": skill, "lvl": 0, "ms": 0, "desc": ""}
    if not tres.exists():
        return out
    for line in tres.read_text().splitlines():
        if line.startswith("display_name = "):
            out["display"] = line.removeprefix("display_name = ").strip().strip('"')
        elif line.startswith("description = "):
            out["desc"] = line.removeprefix("description = ").strip().strip('"')
        elif line.startswith("level_required = "):
            try:
                out["lvl"] = int(line.removeprefix("level_required = ").strip())
            except ValueError:
                pass
        elif line.startswith("milestone_index = "):
            try:
                out["ms"] = int(line.removeprefix("milestone_index = ").strip())
            except ValueError:
                pass
    return out


def emit(path: Path) -> None:
    info = parse_existing(path)
    perk_id = path.stem
    spec = S.get(perk_id, default_spec(perk_id, info["display"], info["desc"]))
    members_block = "\n".join(spec.get("members", []))
    # on_picked / on_unpicked are zero-arg in the Perk base class; every
    # other hook receives a ctx Dictionary.
    NO_CTX = {"on_picked", "on_unpicked"}
    hook_blocks = []
    for hook_name, body in spec["hooks"].items():
        sig = f"func {hook_name}() -> void:" if hook_name in NO_CTX else f"func {hook_name}(ctx: Dictionary) -> void:"
        hook_blocks.append(f"{sig}\n{body}")
    hooks_text = "\n\n\n".join(hook_blocks)
    text = HEADER_TEMPLATE.format(
        display=info["display"],
        skill=info["skill"],
        lvl=info["lvl"],
        ms=info["ms"],
        desc=info["desc"],
        pattern_note=spec.get("pattern_note", ""),
        members=members_block,
        hooks=hooks_text,
    )
    path.write_text(text)


def main() -> None:
    count = 0
    custom = 0
    for skill_dir in sorted(SCRIPT_ROOT.iterdir()):
        if not skill_dir.is_dir():
            continue
        for gd in sorted(skill_dir.glob("*.gd")):
            emit(gd)
            count += 1
            if gd.stem in S:
                custom += 1
    print(f"Wired {count} active perks ({custom} with custom bodies, {count - custom} default stub).")


if __name__ == "__main__":
    main()
