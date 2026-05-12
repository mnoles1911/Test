#!/usr/bin/env python3
"""Generate the 300 PerkData .tres files + active Perk .gd stubs from
a flat spec table.

Run from the repo root:
    python3 tools/generate_perks.py

Layout per skill: 25 perks across 25 milestones (L4, L8, ..., L100).
Some perks form exclusive_group pairs (within a skill) to force a
branching choice. `is_active = True` perks also get a sibling .gd
file under scripts/skills/perks/{skill}/ with a TODO body — the
authoritative hook implementations land alongside whatever gameplay
system they affect (Riposte, Second Wind, etc).
"""
from __future__ import annotations
import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TRES_ROOT = REPO_ROOT / "assets" / "skills" / "perks"
SCRIPT_ROOT = REPO_ROOT / "scripts" / "skills" / "perks"

# Each spec entry:
#   (perk_id, display_name, description,
#    effect_type, effect_value, effect_target, condition,
#    exclusive_group, is_active)
# perk_id is unique across all skills. Each skill list has exactly 25
# entries — ordering implies milestone_index 0..24 (L4, L8, ..., L100).

SPECS = {

# =================== SWORD ===================
"sword": [
    ("sword_first_blood",      "First Blood",       "+10% damage with swords against full-HP enemies.",            "damage_mult",   0.10,  "sword",        "target_full_hp",   "",                 False),
    ("sword_steady_hand",      "Steady Hand",       "Sword swings cost 10% less endurance.",                       "stamina_mult",  -0.10, "sword",        "",                 "",                 False),
    ("sword_keen_edge",        "Keen Edge",         "+5% sword damage.",                                            "damage_mult",   0.05,  "sword",        "",                 "",                 False),
    ("sword_quickstep",        "Quickstep",         "Move 8% faster while a sword is drawn.",                       "move_mult",     0.08,  "while_sword",  "",                 "sword_form_A",     False),
    ("sword_root_stance",      "Root Stance",       "Take 12% less damage while standing still with a sword drawn.","damage_taken",  -0.12, "while_sword",  "standing_still",   "sword_form_A",     False),
    ("sword_riposte",          "Riposte",           "After a successful parry, your next sword hit within 2 s deals +50% damage.","damage_mult", 0.50, "sword", "post_parry_2s", "", True),
    ("sword_disarming_strike", "Disarming Strike",  "5% chance per sword hit to stagger the target.",               "proc_chance",   0.05,  "sword",        "on_hit",           "",                 True),
    ("sword_bleed",            "Bleed",             "Sword hits apply a bleed dealing 1 dmg/s for 6 s.",            "dot_apply",     1.0,   "sword",        "on_hit",           "sword_finisher",   True),
    ("sword_overpower",        "Overpower",         "Power attacks deal +20% damage.",                              "damage_mult",   0.20,  "sword",        "on_power_attack",  "sword_finisher",   False),
    ("sword_whirlwind",        "Whirlwind",         "Power attacks hit all enemies within 1.5 m.",                  "aoe_radius",    1.5,   "sword",        "on_power_attack",  "",                 True),
    ("sword_dueling_focus",    "Dueling Focus",     "+15% damage when only one enemy is within 3 m.",              "damage_mult",   0.15,  "sword",        "lone_target",      "",                 False),
    ("sword_thicket",          "Thicket",           "+10% damage per additional enemy within 3 m (cap +40%).",     "damage_mult",   0.10,  "sword",        "per_extra_enemy",  "",                 True),
    ("sword_resolute",         "Resolute",          "Sword swings cannot be staggered by mob attacks.",             "flag",          1.0,   "sword",        "",                 "",                 False),
    ("sword_swift_recovery",   "Swift Recovery",    "Recover 25% faster from a missed swing.",                      "recovery_mult", -0.25, "sword",        "",                 "",                 False),
    ("sword_executioner",      "Executioner",       "+40% damage to enemies below 25% HP.",                         "damage_mult",   0.40,  "sword",        "target_low_hp",    "",                 False),
    ("sword_iron_arm",         "Iron Arm",          "+10% damage with all one-handed weapons.",                    "damage_mult",   0.10,  "sword",        "",                 "",                 False),
    ("sword_battle_rhythm",    "Battle Rhythm",     "Each consecutive sword hit within 3 s adds +3% damage (cap +24%).","damage_mult", 0.03, "sword", "rhythm_stack", "", True),
    ("sword_unbroken",         "Unbroken",          "Take 15% less damage while above 75% HP.",                     "damage_taken",  -0.15, "while_sword", "self_high_hp",     "",                 False),
    ("sword_second_wind",      "Second Wind",       "Once per fight, regain 30% endurance when it hits 0.",        "proc_once",     0.30,  "stamina",      "stamina_zero",     "",                 True),
    ("sword_swords_dance",     "Sword's Dance",     "+10% damage and -10% endurance cost while moving with sword.","damage_mult",   0.10,  "while_sword", "while_moving",     "",                 True),
    ("sword_grand_strike",     "Grand Strike",      "+50% damage on first sword hit after entering combat.",       "damage_mult",   0.50,  "sword",        "first_hit_combat", "",                 True),
    ("sword_dread_blade",      "Dread Blade",       "Killing an enemy with a sword frightens others within 5 m for 3 s.","aoe_apply", 1.0, "sword", "on_kill",        "",                 True),
    ("sword_undying",          "Undying",           "Once per day, surviving a killing blow leaves you at 1 HP.",  "proc_once",     1.0,   "self",         "lethal_damage",    "",                 True),
    ("sword_master_of_arms",   "Master of Arms",    "+15% damage with all melee weapons.",                          "damage_mult",   0.15,  "sword",        "",                 "",                 False),
    ("sword_perfect_form",     "Perfect Form",      "+10% damage and +10% parry window with swords.",              "damage_mult",   0.10,  "sword",        "",                 "",                 False),
],

# =================== THROWABLES ===================
"throwables": [
    ("throw_steady_arm",       "Steady Arm",        "+10% throw range.",                                            "range_mult",     0.10, "throwables",   "",                 "",                 False),
    ("throw_keen_eye",         "Keen Eye",          "+10% throw damage at point-blank range (<5 m).",              "damage_mult",    0.10, "throwables",   "short_range",      "",                 False),
    ("throw_long_arc",         "Long Arc",          "+15% damage on throws over 15 m.",                             "damage_mult",    0.15, "throwables",   "long_range",       "",                 False),
    ("throw_javelin_grip",     "Javelin Grip",      "+20% spear damage.",                                           "damage_mult",    0.20, "spear",        "",                 "throw_focus_A",    False),
    ("throw_powder_grip",      "Powder Grip",       "+20% powder charge AoE radius.",                               "aoe_radius_mult",0.20, "powder_charge","",                 "throw_focus_A",    False),
    ("throw_silent_throw",     "Silent Throw",      "Thrown weapons no longer alert enemies outside 6 m.",         "flag",           1.0,  "throwables",   "",                 "",                 False),
    ("throw_armor_pierce",     "Armor Pierce",      "Ignore 20% of target armor on thrown hits.",                  "armor_pierce",   0.20, "throwables",   "",                 "",                 False),
    ("throw_double_grab",      "Double Grab",       "Drawing a spear pulls 2 into hand (if 2+ in inventory).",     "flag",           1.0,  "spear",        "",                 "",                 True),
    ("throw_ricochet",         "Ricochet",          "Thrown spears bounce once off terrain.",                       "flag",           1.0,  "spear",        "",                 "",                 True),
    ("throw_marked_target",    "Marked Target",     "First thrown hit on an enemy marks them: +20% damage from all sources for 5 s.","apply_debuff", 0.20, "throwables", "first_hit", "", True),
    ("throw_charged_throw",    "Charged Throw",     "Held throws (1 s) deal +30% damage and +10% range.",          "damage_mult",    0.30, "throwables",   "on_charged",       "",                 True),
    ("throw_fast_hands",       "Fast Hands",        "Draw and throw 25% faster.",                                   "speed_mult",     0.25, "throwables",   "",                 "",                 False),
    ("throw_demolition_kin",   "Demolition Kin",    "+10% damage with powder charges and sappers' bundles.",        "damage_mult",    0.10, "explosives",   "",                 "",                 False),
    ("throw_terrain_eye",      "Terrain Eye",       "Powder charges break +25% more voxels.",                       "voxel_count_mult",0.25,"powder_charge","",                 "",                 False),
    ("throw_collector",        "Collector",         "Auto-collect range for thrown weapons +50%.",                  "pickup_radius_mult",0.50,"throwables", "",                 "",                 False),
    ("throw_blood_arrow",      "Blood Arrow",       "Thrown kills heal 5 HP.",                                      "heal_on_kill",   5.0,  "throwables",   "on_kill",          "",                 True),
    ("throw_volley",           "Volley",            "Each thrown weapon hit reduces the next throw's endurance cost by 50% for 3 s.","stamina_mult", -0.50, "throwables", "post_hit", "", True),
    ("throw_perfect_aim",      "Perfect Aim",       "First thrown weapon of an encounter has -50% spread.",        "accuracy",       0.50, "throwables",   "first_throw",      "",                 True),
    ("throw_iron_grip",        "Iron Grip",         "+15% throw damage.",                                           "damage_mult",    0.15, "throwables",   "",                 "",                 False),
    ("throw_keep_close",       "Keep Close",        "Throwables in inventory weigh 50% less.",                      "weight_mult",   -0.50, "throwables",   "",                 "",                 False),
    ("throw_executioner",      "Executioner",       "+50% throw damage to enemies below 25% HP.",                  "damage_mult",    0.50, "throwables",   "target_low_hp",    "",                 False),
    ("throw_storm_caller",     "Storm Caller",      "Detonating a powder charge near another causes both to chain.","chain_explode", 1.0,  "powder_charge","",                 "",                 True),
    ("throw_javelin_storm",    "Javelin Storm",     "Killing with a spear refunds 50% chance to find the spear at the corpse.","pickup_proc", 0.50, "spear", "on_kill", "", True),
    ("throw_unerring",         "Unerring",          "+20% thrown damage.",                                          "damage_mult",    0.20, "throwables",   "",                 "",                 False),
    ("throw_master_thrower",   "Master Thrower",    "+25% range, +15% damage with all thrown weapons.",            "damage_mult",    0.15, "throwables",   "",                 "",                 False),
],

# =================== BOW ===================
"bow": [
    ("bow_steady_draw",        "Steady Draw",       "+10% bow damage at point-blank (<10 m).",                     "damage_mult",   0.10,  "bow",          "short_range",      "",                 False),
    ("bow_long_shot",          "Long Shot",         "+15% bow damage at long range (>30 m).",                      "damage_mult",   0.15,  "bow",          "long_range",       "",                 False),
    ("bow_eagle_eye",          "Eagle Eye",         "Zoom level +20% while drawing.",                              "zoom_mult",     0.20,  "bow",          "",                 "bow_form_A",       False),
    ("bow_quick_nock",         "Quick Nock",        "Draw 20% faster.",                                            "draw_speed_mult",0.20, "bow",          "",                 "bow_form_A",       False),
    ("bow_keen_arrows",        "Keen Arrows",       "+10% bow damage.",                                            "damage_mult",   0.10,  "bow",          "",                 "",                 False),
    ("bow_armor_pierce",       "Armor Pierce",      "Ignore 25% target armor.",                                    "armor_pierce",  0.25,  "bow",          "",                 "",                 False),
    ("bow_silent_kill",        "Silent Kill",       "Bow kills outside combat do not alert nearby enemies.",       "flag",          1.0,   "bow",          "stealth",          "",                 True),
    ("bow_focus",              "Focus",             "Hold draw to slow time 25% for up to 3 s.",                   "time_dilation", 0.25,  "bow",          "on_draw_hold",     "",                 True),
    ("bow_double_nock",        "Double Nock",       "10% chance to fire a free second arrow per shot.",            "proc_chance",   0.10,  "bow",          "",                 "",                 True),
    ("bow_bleed_arrows",       "Bleed Arrows",      "Bow hits apply 1 dmg/s bleed for 6 s.",                       "dot_apply",     1.0,   "bow",          "on_hit",           "bow_path_a",       True),
    ("bow_fire_arrows",        "Fire Arrows",       "Bow hits ignite for 2 dmg/s, 4 s.",                            "dot_apply",     2.0,   "bow",          "on_hit",           "bow_path_a",       True),
    ("bow_marksman",           "Marksman",          "+15% headshot damage.",                                       "damage_mult",   0.15,  "bow",          "on_headshot",      "",                 False),
    ("bow_fletcher",           "Fletcher",          "Recover 50% of arrows from corpses.",                          "recover_chance",0.50,  "bow",          "on_loot",          "",                 False),
    ("bow_steady_under_fire",  "Steady Under Fire", "Draw is not interrupted by taking damage.",                   "flag",          1.0,   "bow",          "",                 "",                 False),
    ("bow_hunter",             "Hunter",            "+20% bow damage to beasts.",                                  "damage_mult",   0.20,  "bow",          "target_beast",     "",                 False),
    ("bow_executioner",        "Executioner",       "+40% bow damage below 25% HP.",                                "damage_mult",   0.40,  "bow",          "target_low_hp",    "",                 False),
    ("bow_volley",             "Volley",            "Each consecutive hit within 3 s adds +5% damage (cap +30%).","damage_mult",   0.05,  "bow",          "rhythm_stack",     "",                 True),
    ("bow_silver_string",      "Silver String",     "Bows fire 5% faster.",                                        "rof_mult",      0.05,  "bow",          "",                 "",                 False),
    ("bow_pincushion",         "Pincushion",        "Each arrow lodged in an enemy adds +5% damage from your next hit (cap +25%).","damage_mult", 0.05, "bow", "stacking_arrows", "", True),
    ("bow_iron_pull",          "Iron Pull",         "Heavy-pull bows cost -20% endurance.",                        "stamina_mult", -0.20,  "bow",          "",                 "",                 False),
    ("bow_quick_quiver",       "Quick Quiver",      "Arrows in inventory weigh 75% less.",                          "weight_mult",  -0.75,  "bow",          "",                 "",                 False),
    ("bow_third_eye",          "Third Eye",         "On a hit, briefly outline the target through walls.",         "vision",        1.0,   "bow",          "on_hit",           "",                 True),
    ("bow_wind_reader",        "Wind Reader",       "Wind and gravity drop are halved.",                            "ballistic_mult",-0.50,"bow",           "",                 "",                 False),
    ("bow_kill_shot",          "Kill Shot",         "+25% damage on the first shot of an encounter.",              "damage_mult",   0.25,  "bow",          "first_hit_combat", "",                 False),
    ("bow_master_archer",      "Master Archer",     "+20% bow damage.",                                            "damage_mult",   0.20,  "bow",          "",                 "",                 False),
],

# =================== MINING ===================
"mining": [
    ("mine_keen_pick",         "Keen Pick",         "+10% mining damage.",                                         "damage_mult",   0.10,  "pickaxe",      "",                 "",                 False),
    ("mine_double_swing",      "Double Swing",      "Pickaxe swings cost -10% endurance.",                         "stamina_mult", -0.10,  "pickaxe",      "",                 "",                 False),
    ("mine_yield_one",         "Steady Yield",      "+10% chance to gain an extra ore drop.",                     "yield_proc",    0.10,  "ore",          "on_break",         "",                 False),
    ("mine_vein_sense",        "Vein Sense",        "Briefly outlines ore veins within 8 m when a pickaxe is drawn.","vision", 1.0,    "ore",          "while_pickaxe",    "mine_path_a",      True),
    ("mine_quick_hands",       "Quick Hands",       "Pickaxe swings 10% faster.",                                  "speed_mult",    0.10,  "pickaxe",      "",                 "mine_path_a",      False),
    ("mine_stonebreaker",      "Stonebreaker",      "+15% mining damage on stone, marble, dark stone.",            "damage_mult",   0.15,  "stone",        "",                 "",                 False),
    ("mine_iron_eater",        "Iron Eater",        "+20% mining damage on iron + copper ore.",                    "damage_mult",   0.20,  "ore",          "",                 "",                 False),
    ("mine_extra_ore",         "Extra Ore",         "Iron and copper drops are +1.",                               "yield_flat",    1.0,   "ore",          "on_break",         "",                 False),
    ("mine_marble_master",     "Marble Master",     "+30% chance to gain an extra marble.",                       "yield_proc",    0.30,  "marble",       "on_break",         "",                 False),
    ("mine_blastproof",        "Blastproof",        "Take 30% less damage from falling voxels.",                  "damage_taken", -0.30,  "self",         "from_voxel",       "",                 False),
    ("mine_deep_lungs",        "Deep Lungs",        "Holding breath underwater is 50% longer.",                    "breath_mult",   0.50,  "self",         "",                 "",                 False),
    ("mine_steady_step",       "Steady Step",       "Don't slip on gravel or wet stone.",                         "flag",          1.0,   "self",         "",                 "",                 False),
    ("mine_ore_sense",         "Ore Sense",         "Minimap pings within 16 m when ore veins are near.",         "vision",        1.0,   "ore",          "passive",          "",                 True),
    ("mine_swing_through",     "Swing Through",     "Pickaxe hits can break 2 adjacent voxels of the same type.","aoe_voxel_count",1.0,"pickaxe",      "",                 "mine_finisher",    True),
    ("mine_powder_pick",       "Powder Pick",       "Stone breaks 10% faster.",                                    "speed_mult",    0.10,  "pickaxe",      "stone",            "mine_finisher",    False),
    ("mine_endless_pit",       "Endless Pit",       "Yield bonus on excavating below Y=0.",                       "yield_proc",    0.10,  "ore",          "deep",             "",                 False),
    ("mine_geologist",         "Geologist",         "+15% XP from any voxel break.",                              "xp_mult",       0.15,  "mining",       "",                 "",                 False),
    ("mine_lucky_strike",      "Lucky Strike",      "5% chance per break to drop a gem.",                          "proc_chance",   0.05,  "ore",          "on_break",         "",                 True),
    ("mine_no_falls",          "Sure Footed",       "Falls of <3 m deal no damage.",                              "fall_threshold",3.0,   "self",         "on_land",          "",                 False),
    ("mine_pillar_breaker",    "Pillar Breaker",    "+25% damage on stone columns over 4 voxels tall.",          "damage_mult",   0.25,  "stone",        "tall_column",      "",                 False),
    ("mine_hauler",            "Hauler",            "Ore weighs 50% less in inventory.",                          "weight_mult",  -0.50,  "ore",          "",                 "",                 False),
    ("mine_battlepick",        "Battlepick",        "Pickaxes deal +20% combat damage.",                          "damage_mult",   0.20,  "pickaxe",      "vs_enemy",         "",                 False),
    ("mine_quarry",            "Quarry",            "Marble + stone_dark drops are doubled.",                     "yield_mult",    1.0,   "marble_dark",  "on_break",         "",                 False),
    ("mine_relentless",        "Relentless",        "Mining swings never tire (endurance regen 100% while mining).","stamina_regen",1.0, "pickaxe",      "while_mining",     "",                 True),
    ("mine_master_miner",      "Master Miner",      "+25% mining damage, +20% ore drops.",                       "damage_mult",   0.25,  "pickaxe",      "",                 "",                 False),
],

# =================== FELLING ===================
"felling": [
    ("fell_keen_axe",          "Keen Axe",          "+10% felling damage.",                                        "damage_mult",   0.10,  "axe",          "",                 "",                 False),
    ("fell_two_grip",          "Two-Hand Grip",     "Axe swings cost -10% endurance.",                             "stamina_mult", -0.10,  "axe",          "",                 "",                 False),
    ("fell_quick_chop",        "Quick Chop",        "Axe swings 10% faster.",                                      "speed_mult",    0.10,  "axe",          "",                 "fell_form_a",      False),
    ("fell_heavy_blow",        "Heavy Blow",        "+15% damage on first axe swing of the day.",                "damage_mult",   0.15,  "axe",          "first_per_day",    "fell_form_a",      False),
    ("fell_logsplitter",       "Logsplitter",       "+15% felling damage on wood.",                               "damage_mult",   0.15,  "wood",         "",                 "",                 False),
    ("fell_extra_log",         "Extra Log",         "Tree voxels yield +1 wood.",                                  "yield_flat",    1.0,   "wood",         "on_break",         "",                 False),
    ("fell_tree_sense",        "Tree Sense",        "Outlines the felling-direction line on a tree trunk.",       "vision",        1.0,   "wood",         "while_axe",        "",                 True),
    ("fell_silent_step",       "Silent Step",       "Walking on logs does not alert wildlife.",                    "flag",          1.0,   "self",         "stealth",          "",                 False),
    ("fell_battleaxe",         "Battleaxe",         "Axes deal +20% combat damage.",                              "damage_mult",   0.20,  "axe",          "vs_enemy",         "",                 False),
    ("fell_woodsman",          "Woodsman",          "+15% XP from felling actions.",                              "xp_mult",       0.15,  "felling",      "",                 "",                 False),
    ("fell_double_strike",     "Double Strike",     "10% chance per swing to hit twice.",                          "proc_chance",   0.10,  "axe",          "on_hit",           "",                 True),
    ("fell_branch_break",      "Branch Break",      "Felling a tree drops kindling for campfires.",               "yield_extra",   1.0,   "wood",         "on_tree_break",    "",                 True),
    ("fell_hauler",            "Wood Hauler",       "Wood weighs 50% less in inventory.",                         "weight_mult",  -0.50,  "wood",         "",                 "",                 False),
    ("fell_clear_cut",         "Clear Cut",         "Felled trees grant +25% bonus wood.",                        "yield_mult",    0.25,  "wood",         "on_tree_break",    "fell_path_b",      False),
    ("fell_select_cut",        "Select Cut",        "Each tree felled grants +10% XP to other crafting skills.","xp_mult",       0.10,  "crafting",     "on_tree_break",    "fell_path_b",      True),
    ("fell_unbroken_grip",     "Unbroken Grip",     "Axe swings cannot be staggered.",                            "flag",          1.0,   "axe",          "",                 "",                 False),
    ("fell_chopping_block",    "Chopping Block",    "+15% damage on stationary axe swings.",                     "damage_mult",   0.15,  "axe",          "standing_still",   "",                 False),
    ("fell_axe_thrower",       "Axe Thrower",       "Axes can be thrown (1-shot consumable until recovered).",   "flag",          1.0,   "axe",          "",                 "",                 True),
    ("fell_evergreen",         "Evergreen",         "Tree drops include +1 sapling per 10 felled.",              "yield_periodic",10.0,  "wood",         "on_tree_break",    "",                 True),
    ("fell_two_handed_might",  "Two-Handed Might",  "+15% damage with two-handed weapons.",                       "damage_mult",   0.15,  "axe",          "",                 "",                 False),
    ("fell_endurance",         "Endurance",         "+10% max endurance.",                                        "max_stam_mult", 0.10,  "self",         "",                 "",                 False),
    ("fell_lumberlord",        "Lumberlord",        "+30% wood drops.",                                            "yield_mult",    0.30,  "wood",         "on_break",         "",                 False),
    ("fell_resolve",           "Resolve",           "Take 15% less damage while above 50% HP.",                   "damage_taken", -0.15,  "self",         "high_hp",          "",                 False),
    ("fell_master_feller",     "Master Feller",     "+25% felling damage, +25% wood drops.",                      "damage_mult",   0.25,  "axe",          "",                 "",                 False),
    ("fell_split_wood",        "Split Wood",        "Killing an enemy with an axe drops kindling.",              "yield_on_kill", 1.0,   "axe",          "on_kill",          "",                 True),
],

# =================== EXCAVATION ===================
"excavation": [
    ("dig_steady_shovel",      "Steady Shovel",     "+10% excavation damage.",                                    "damage_mult",   0.10,  "shovel",       "",                 "",                 False),
    ("dig_swift_dig",          "Swift Dig",         "Shovel swings 15% faster.",                                  "speed_mult",    0.15,  "shovel",       "",                 "",                 False),
    ("dig_cheap_swing",        "Cheap Swing",       "Shovel swings cost -15% endurance.",                         "stamina_mult", -0.15,  "shovel",       "",                 "",                 False),
    ("dig_extra_dirt",         "Extra Dirt",        "+25% dirt/sand drops.",                                       "yield_mult",    0.25,  "dirt",         "on_break",         "",                 False),
    ("dig_clay_finder",        "Clay Finder",       "+25% chance to expose clay disk when near water.",           "proc_chance",   0.25,  "clay",         "near_water",       "",                 True),
    ("dig_gravel_finder",      "Gravel Finder",     "+25% chance to expose gravel disk when near water.",         "proc_chance",   0.25,  "gravel",       "near_water",       "",                 True),
    ("dig_no_slip",            "No Slip",           "Don't slide on sand or wet dirt.",                           "flag",          1.0,   "self",         "",                 "",                 False),
    ("dig_bury",               "Bury",              "Spawn 1 dirt at every shovel strike to bury bodies.",        "flag",          1.0,   "shovel",       "",                 "",                 True),
    ("dig_grave_robber",       "Grave Robber",      "Excavating dropped corpses yields +1 random crafting mat.",  "yield_extra",   1.0,   "shovel",       "on_corpse",        "",                 True),
    ("dig_archeologist",       "Archeologist",      "5% chance to unearth a small treasure when digging.",        "proc_chance",   0.05,  "shovel",       "on_break",         "",                 True),
    ("dig_terrain_eye",        "Terrain Eye",       "Outline buried objects within 4 m.",                         "vision",        1.0,   "shovel",       "while_shovel",     "",                 True),
    ("dig_water_finder",       "Water Finder",      "Pings nearby water table within 12 m.",                       "vision",        1.0,   "water",        "passive",          "",                 True),
    ("dig_hauler",             "Hauler",            "Dirt + sand + gravel weigh 50% less.",                       "weight_mult",  -0.50,  "dirt",         "",                 "",                 False),
    ("dig_battle_shovel",      "Battle Shovel",     "Shovels deal +20% combat damage.",                           "damage_mult",   0.20,  "shovel",       "vs_enemy",         "",                 False),
    ("dig_pit_master",         "Pit Master",        "+25% damage to enemies in dirt pits below the player.",     "damage_mult",   0.25,  "shovel",       "target_below",     "",                 False),
    ("dig_sapper",             "Sapper",            "+25% damage to wooden structures.",                          "damage_mult",   0.25,  "shovel",       "vs_wood",          "",                 False),
    ("dig_strong_back",        "Strong Back",       "+10% carry weight.",                                          "carry_mult",    0.10,  "self",         "",                 "",                 False),
    ("dig_field_medic",        "Field Medic",       "Excavating a corpse heals you for 5 HP.",                    "heal_on_use",   5.0,   "shovel",       "on_corpse",        "",                 True),
    ("dig_loose_earth",        "Loose Earth",       "Dirt voxels broken trigger gravity scans more aggressively.","flag",          1.0,   "dirt",         "",                 "",                 False),
    ("dig_swift_recovery",     "Swift Recovery",    "Recover endurance 15% faster.",                              "stamina_regen", 0.15,  "self",         "",                 "",                 False),
    ("dig_terraformer",        "Terraformer",       "Dirt placement (Build Mode) costs no endurance.",           "stamina_mult", -1.0,   "shovel",       "build_mode",       "",                 False),
    ("dig_archaeologist_2",    "Lost Cache",        "Buried treasures grant +50% gold.",                         "gold_mult",     0.50,  "treasure",     "",                 "",                 False),
    ("dig_quickburial",        "Quick Burial",      "Burying a corpse refreshes endurance to full.",             "stamina_refill",1.0,   "shovel",       "on_corpse",        "",                 True),
    ("dig_no_traps",           "Tripwise",          "Reveal pressure plates within 4 m while a shovel is drawn.","vision",        1.0,   "traps",        "while_shovel",     "",                 True),
    ("dig_master_digger",      "Master Digger",     "+25% excavation damage, +25% dirt drops.",                  "damage_mult",   0.25,  "shovel",       "",                 "",                 False),
],

# =================== DEMOLITION ===================
"demolition": [
    ("demo_keen_charge",       "Keen Charge",       "+10% powder charge damage.",                                  "damage_mult",   0.10,  "explosives",   "",                 "",                 False),
    ("demo_big_boom",          "Big Boom",          "+15% AoE radius.",                                            "aoe_radius_mult",0.15,"explosives",   "",                 "",                 False),
    ("demo_long_fuse",         "Long Fuse",         "Powder charges detonate 1 s slower (more time to back away).","fuse_mult",   1.0,    "explosives",   "",                 "demo_form_a",      False),
    ("demo_short_fuse",        "Short Fuse",        "Powder charges detonate 0.5 s faster.",                       "fuse_mult",    -0.5,  "explosives",   "",                 "demo_form_a",      False),
    ("demo_proximity",         "Proximity",         "Charges detonate on enemy contact instead of timer.",         "flag",          1.0,   "explosives",   "",                 "",                 True),
    ("demo_chain",             "Chain Reaction",    "+50% chance a nearby charge chains on detonation.",          "proc_chance",   0.50,  "explosives",   "near_charge",      "",                 True),
    ("demo_double_pack",       "Double Pack",       "Sappers' bundles count as 2 in inventory.",                  "stack_mult",    2.0,   "sappers_bundle","",                "",                 False),
    ("demo_blast_resist",      "Blast Resist",      "Take 40% less damage from your own explosions.",             "damage_taken", -0.40,  "self",         "self_explosion",   "",                 False),
    ("demo_yield_boost",       "Yield Boost",       "Charges drop +25% mined ore from breakable terrain.",       "yield_mult",    0.25,  "explosives",   "on_detonate",      "",                 False),
    ("demo_shrapnel",          "Shrapnel",          "Explosions deal +20% damage to enemies.",                    "damage_mult",   0.20,  "explosives",   "vs_enemy",         "",                 False),
    ("demo_focused_blast",     "Focused Blast",     "Explosions deal +30% damage in a 30° forward cone.",         "damage_mult",   0.30,  "explosives",   "cone_forward",     "demo_path_b",      True),
    ("demo_omnidirectional",   "Omnidirectional",   "+20% explosion radius.",                                     "aoe_radius_mult",0.20,"explosives",   "",                 "demo_path_b",      False),
    ("demo_smoker",            "Smoker",            "Explosions leave a 5 s smoke cloud blinding enemies.",       "apply_debuff",  5.0,   "explosives",   "on_detonate",      "",                 True),
    ("demo_pyro",              "Pyromaniac",       "+10% XP from demolition.",                                    "xp_mult",       0.10,  "demolition",   "",                 "",                 False),
    ("demo_safe_handler",      "Safe Handler",      "Powder charges in inventory weigh 30% less.",               "weight_mult",  -0.30,  "explosives",   "",                 "",                 False),
    ("demo_blast_thrower",     "Blast Thrower",     "+25% throw range with explosives.",                          "range_mult",    0.25,  "explosives",   "",                 "",                 False),
    ("demo_fast_pack",         "Fast Pack",         "Drawing an explosive is 25% faster.",                        "draw_speed_mult",0.25, "explosives",   "",                 "",                 False),
    ("demo_charge_recovery",   "Charge Recovery",   "10% chance an unexploded charge can be recovered.",         "recover_chance",0.10,  "explosives",   "on_dud",           "",                 True),
    ("demo_sapper_master",     "Sapper Master",     "Sappers' bundles deal +30% damage to walls.",               "damage_mult",   0.30,  "sappers_bundle","vs_wall",         "",                 False),
    ("demo_clear_air",         "Clear Air",         "Smoke and dust clears 50% faster around you.",              "vfx_mult",     -0.50,  "self",         "",                 "",                 False),
    ("demo_concussion",        "Concussion",        "Stuns enemies within 4 m for 1 s on detonation.",            "apply_debuff",  1.0,   "explosives",   "on_detonate",      "",                 True),
    ("demo_blast_eyes",        "Blast Eyes",        "Outline enemies inside the next explosion zone for 2 s.",   "vision",        2.0,   "explosives",   "while_aim",        "",                 True),
    ("demo_demolisher",        "Demolisher",        "+20% damage to wooden + stone structures.",                "damage_mult",   0.20,  "explosives",   "vs_structure",     "",                 False),
    ("demo_charge_master",     "Charge Master",     "+15% charge damage, +15% AoE.",                              "damage_mult",   0.15,  "explosives",   "",                 "",                 False),
    ("demo_master_demolisher", "Master Demolisher", "+25% damage, +25% AoE on all explosives.",                  "damage_mult",   0.25,  "explosives",   "",                 "",                 False),
],

# =================== LOCKPICKING ===================
"lockpicking": [
    ("lock_steady_hand",       "Steady Hand",       "Lock dial drifts 15% slower.",                              "drift_mult",   -0.15,  "lock",         "",                 "",                 False),
    ("lock_fast_fingers",      "Fast Fingers",      "Lock attempts 20% faster.",                                  "speed_mult",    0.20,  "lock",         "",                 "",                 False),
    ("lock_save_picks",        "Save Picks",        "Picks 25% less likely to break.",                            "break_mult",   -0.25,  "lock",         "",                 "",                 False),
    ("lock_thief_eye",         "Thief's Eye",       "Outline locked containers within 8 m.",                     "vision",        1.0,   "lock",         "passive",          "",                 True),
    ("lock_tumblers",          "Tumbler Sense",     "Lock sweet-spot arc is 20% wider.",                          "arc_mult",      0.20,  "lock",         "",                 "",                 False),
    ("lock_silver_pick",       "Silver Pick",       "Tier-1 locks open in one attempt.",                          "flag",          1.0,   "lock",         "tier_1",           "lock_path_a",      True),
    ("lock_gold_pick",         "Gold Pick",         "Tier-2 locks have 50% wider sweet spot.",                    "arc_mult",      0.50,  "lock",         "tier_2",           "lock_path_a",      False),
    ("lock_pickpocket",        "Pickpocket",        "Begin pickpocketing without alerting NPCs.",                "flag",          1.0,   "self",         "stealth",          "",                 True),
    ("lock_double_loot",       "Double Loot",       "Pick locks drop +1 random consumable.",                     "yield_extra",   1.0,   "lock",         "on_open",          "",                 True),
    ("lock_silent_open",       "Silent Open",       "Opened locks no longer alert nearby NPCs.",                 "flag",          1.0,   "lock",         "",                 "",                 False),
    ("lock_master_thief",      "Master Thief",      "+25% gold from locked containers.",                          "gold_mult",     0.25,  "lock",         "",                 "",                 False),
    ("lock_hidden_caches",     "Hidden Caches",     "Reveal hidden cache markers within 16 m.",                  "vision",        1.0,   "lock",         "passive",          "",                 True),
    ("lock_keen_eye",          "Keen Eye",          "Reveal pick sweet spot for 1 s on entry.",                  "vision",        1.0,   "lock",         "on_enter",         "",                 True),
    ("lock_steady_breath",     "Steady Breath",     "Time penalty for failed attempt halved.",                   "penalty_mult", -0.50,  "lock",         "on_fail",          "",                 False),
    ("lock_burglar",           "Burglar",           "Open locks 30% faster on the third+ attempt of an evening.","speed_mult",    0.30,  "lock",         "rhythm",           "",                 True),
    ("lock_decoy",             "Decoy",             "Drop a fake pick to distract patrolling NPCs for 5 s.",     "apply_debuff",  5.0,   "self",         "active_ability",   "",                 True),
    ("lock_smith_friend",      "Smith's Friend",    "Smithing-crafted picks have +50% durability.",              "durability_mult",0.50, "lock",         "",                 "",                 False),
    ("lock_iron_grip",         "Iron Grip",         "Locks attempted with an iron pick are 10% easier.",          "arc_mult",      0.10,  "lock",         "iron_pick",        "",                 False),
    ("lock_silver_grip",       "Silver Grip",       "Locks attempted with a silver pick are 20% easier.",         "arc_mult",      0.20,  "lock",         "silver_pick",      "",                 False),
    ("lock_inside_man",        "Inside Man",        "Failed attempts no longer count toward guard suspicion.",    "flag",          1.0,   "lock",         "",                 "",                 False),
    ("lock_steady_legs",       "Steady Legs",       "Pick locks while crouched without penalty.",                 "flag",          1.0,   "lock",         "while_crouch",     "",                 False),
    ("lock_perfect_pick",      "Perfect Pick",      "First attempt of the day on any lock auto-wins tier-2 or below.","flag",     1.0,   "lock",         "first_per_day",    "",                 True),
    ("lock_treasure_hunter",   "Treasure Hunter",   "Locked containers have +10% rare loot chance.",             "rare_chance",   0.10,  "lock",         "",                 "",                 False),
    ("lock_silent_steps",      "Silent Steps",      "Footstep noise -50% while a pick is drawn.",                "noise_mult",   -0.50,  "self",         "while_pick",       "",                 False),
    ("lock_master_picker",     "Master Picker",     "All locks 20% easier.",                                      "arc_mult",      0.20,  "lock",         "",                 "",                 False),
],

# =================== ALCHEMY ===================
"alchemy": [
    ("alch_keen_nose",         "Keen Nose",         "Reveal herb gather points within 8 m.",                     "vision",        1.0,   "herb",         "passive",          "",                 True),
    ("alch_steady_hand",       "Steady Hand",       "Brewing time -15%.",                                          "brew_speed",   -0.15,  "alchemy",      "",                 "",                 False),
    ("alch_double_dose",       "Double Dose",       "+1 potion per craft for tier-1 recipes.",                  "yield_flat",    1.0,   "potion_t1",    "on_craft",         "",                 False),
    ("alch_strong_brew",       "Strong Brew",       "Potions are +15% effective.",                                "effect_mult",   0.15,  "potion",       "",                 "alch_form_a",      False),
    ("alch_long_brew",         "Long Brew",         "Potion durations +25%.",                                     "duration_mult", 0.25,  "potion",       "",                 "alch_form_a",      False),
    ("alch_save_reagent",      "Save Reagent",      "10% chance to refund 1 ingredient per craft.",              "refund_chance", 0.10,  "alchemy",      "on_craft",         "",                 False),
    ("alch_taster",            "Taster",            "Reveal first effect of unknown ingredients by tasting.",    "flag",          1.0,   "alchemy",      "active_ability",   "",                 True),
    ("alch_field_medic",       "Field Medic",       "Potions you drink heal +10% extra HP.",                     "heal_mult",     0.10,  "potion",       "self_drink",       "",                 False),
    ("alch_poisoner",          "Poisoner",          "Coat blade poison on swords for 30 s.",                     "apply_buff",    30.0,  "potion",       "active_ability",   "",                 True),
    ("alch_master_brewer",     "Master Brewer",     "Potions never spoil.",                                       "flag",          1.0,   "potion",      "",                 "",                 False),
    ("alch_double_brew",       "Double Brew",       "+25% chance to craft 2 potions instead of 1.",             "proc_chance",   0.25,  "potion",       "on_craft",         "",                 True),
    ("alch_recipe_eye",        "Recipe Eye",        "Reveal recipe matches when 2 ingredients in cauldron.",     "vision",        1.0,   "alchemy",      "while_craft",      "",                 True),
    ("alch_strong_potions",    "Strong Potions",    "Potion effects +20%.",                                       "effect_mult",   0.20,  "potion",       "",                 "",                 False),
    ("alch_efficient",         "Efficient",         "Ingredients used per brew -1 (min 1).",                     "cost_flat",    -1.0,   "alchemy",      "on_craft",         "",                 False),
    ("alch_safe_handler",      "Safe Handler",      "Poisons cannot harm the brewer.",                            "flag",          1.0,   "self",         "",                 "",                 False),
    ("alch_wild_picker",       "Wild Picker",       "+25% herb gather yield.",                                   "yield_mult",    0.25,  "herb",         "on_gather",        "",                 False),
    ("alch_smith_friend",      "Smith's Friend",    "Crafted oils + tinctures last +50% longer.",               "duration_mult", 0.50,  "potion",       "oil_or_tincture",  "",                 False),
    ("alch_extra_yield",       "Extra Yield",       "+1 ingredient per herb gather pile.",                       "yield_flat",    1.0,   "herb",         "on_gather",        "",                 False),
    ("alch_quick_drink",       "Quick Drink",       "Drinking potions in combat is 50% faster.",                "speed_mult",    0.50,  "potion",       "in_combat",        "",                 False),
    ("alch_potion_belt",       "Potion Belt",       "Carry 8 potions in quick slots (up from 4).",              "slot_count",    4.0,   "potion",       "",                 "",                 False),
    ("alch_grand_brew",        "Grand Brew",        "Tier-3 potions take 25% less time.",                        "brew_speed",   -0.25,  "potion_t3",    "",                 "",                 False),
    ("alch_versatility",       "Versatility",       "Drinking 2 potions within 5 s doesn't break stack rules.","flag",          1.0,   "potion",       "",                 "",                 True),
    ("alch_sober_mind",        "Sober Mind",        "Negative effects from drunkenness or bad brews halved.",   "effect_mult",  -0.50,  "self",         "negative",         "",                 False),
    ("alch_apothecary",        "Apothecary",        "+15% effect to all healing potions.",                       "heal_mult",     0.15,  "potion",       "healing",          "",                 False),
    ("alch_grandmaster",       "Grandmaster",       "+25% potion effect, +25% duration.",                        "effect_mult",   0.25,  "potion",       "",                 "",                 False),
],

# =================== SMITHING ===================
"smithing": [
    ("smith_steady_strike",    "Steady Strike",     "Forge strike sweet spot 10% wider.",                        "arc_mult",      0.10,  "smithing",     "",                 "",                 False),
    ("smith_strong_arm",       "Strong Arm",        "Hammer swings cost -15% endurance.",                         "stamina_mult", -0.15,  "smithing",     "",                 "",                 False),
    ("smith_iron_grip",        "Iron Grip",         "Smithing iron items takes -15% strikes.",                   "strike_mult",  -0.15,  "smithing_iron","",                 "smith_form_a",     False),
    ("smith_silver_grip",      "Silver Grip",       "Smithing silver items takes -15% strikes.",                 "strike_mult",  -0.15,  "smithing_silver","",               "smith_form_a",     False),
    ("smith_armorer",          "Armorer",           "Crafted armor has +10% condition.",                          "condition_mult",0.10,  "armor",        "",                 "",                 False),
    ("smith_weaponsmith",      "Weaponsmith",       "Crafted weapons deal +5% damage.",                          "damage_mult",   0.05,  "weapon",       "",                 "",                 False),
    ("smith_keen_edge",        "Keen Edge",         "Sharpening at a whetstone +50% effect.",                    "effect_mult",   0.50,  "smithing",     "whetstone",        "",                 False),
    ("smith_double_yield",     "Double Yield",      "Crafting tier-1 items yields +1 result.",                   "yield_flat",    1.0,   "smithing_t1",  "on_craft",         "",                 False),
    ("smith_temper",           "Temper",            "Crafted items have +10% durability.",                       "durability_mult",0.10, "smithing",     "",                 "",                 False),
    ("smith_master_form",      "Master Form",       "Crafted weapons grant +5% damage with that weapon type.","damage_mult",   0.05,  "weapon",       "self_made",        "",                 True),
    ("smith_cheap_repair",     "Cheap Repair",      "Repairs cost 30% less.",                                     "cost_mult",    -0.30,  "smithing",     "repair",           "",                 False),
    ("smith_fast_repair",      "Fast Repair",       "Repairs 25% faster.",                                        "speed_mult",    0.25,  "smithing",     "repair",           "",                 False),
    ("smith_recipe_eye",       "Recipe Eye",        "Forge UI highlights ingredients that match a known recipe.","vision",        1.0,   "smithing",     "while_craft",      "",                 True),
    ("smith_iron_master",      "Iron Master",       "Iron items +10% damage / +10% armor.",                      "stat_mult",     0.10,  "smithing_iron","",                 "",                 False),
    ("smith_silver_master",    "Silver Master",     "Silver items +15% damage / +15% armor.",                    "stat_mult",     0.15,  "smithing_silver","",               "",                 False),
    ("smith_runed",            "Runed",             "1 in 5 crafts produces a +1 quality result.",              "quality_proc",  0.20,  "smithing",     "on_craft",         "",                 True),
    ("smith_save_ore",         "Save Ore",          "10% chance to refund 1 ingot per craft.",                  "refund_chance", 0.10,  "smithing",     "on_craft",         "",                 False),
    ("smith_keen_eye",         "Keen Eye",          "Forge defects appear 50% less often.",                      "defect_mult",  -0.50,  "smithing",     "",                 "",                 False),
    ("smith_efficient",        "Efficient",         "Recipes use 1 less ingot (min 1).",                         "cost_flat",    -1.0,   "smithing",     "on_craft",         "",                 False),
    ("smith_signature",        "Signature",         "Your name appears on crafted items (+10% sell value).",     "value_mult",    0.10,  "smithing",     "self_made",        "",                 False),
    ("smith_quick_strike",     "Quick Strike",      "Forge hammer swings 20% faster.",                           "speed_mult",    0.20,  "smithing",     "",                 "",                 False),
    ("smith_dwarven_grip",     "Dwarven Grip",      "Smithing dwarven-style items unlocks improved quality.",   "flag",          1.0,   "smithing",     "",                 "",                 False),
    ("smith_legendary_form",   "Legendary Form",    "Crafts at 100 condition with perfect rhythm get +1 tier.","quality_proc",  1.0,   "smithing",     "perfect_rhythm",   "",                 True),
    ("smith_market_smith",     "Market Smith",      "Crafted items sell for +20% gold.",                         "value_mult",    0.20,  "smithing",     "",                 "",                 False),
    ("smith_grandmaster",      "Grandmaster",       "+15% damage / +15% armor on all crafted items.",            "stat_mult",     0.15,  "smithing",     "",                 "",                 False),
],

# =================== VITALITY ===================
"vitality": [
    ("vit_robust",             "Robust",            "+10 max HP.",                                                "max_hp_flat",   10.0,  "self",         "",                 "",                 False),
    ("vit_deep_breath",        "Deep Breath",       "+25% breath underwater.",                                    "breath_mult",   0.25,  "self",         "",                 "",                 False),
    ("vit_steady_recovery",    "Steady Recovery",   "Endurance regen +15%.",                                      "stamina_regen", 0.15,  "self",         "",                 "vit_form_a",       False),
    ("vit_iron_belly",         "Iron Belly",        "Food heals +25% HP.",                                        "heal_mult",     0.25,  "food",         "",                 "vit_form_a",       False),
    ("vit_cold_blood",         "Cold Blood",        "Cold environments deal 50% less damage.",                   "damage_taken", -0.50,  "self",         "cold",             "",                 False),
    ("vit_warm_blood",         "Warm Blood",        "Hot environments deal 50% less damage.",                    "damage_taken", -0.50,  "self",         "heat",             "",                 False),
    ("vit_hardy",              "Hardy",             "Take 10% less damage from non-magical sources.",            "damage_taken", -0.10,  "self",         "physical",         "",                 False),
    ("vit_fast_runner",        "Fast Runner",       "+10% sprint speed.",                                         "sprint_mult",   0.10,  "self",         "",                 "",                 False),
    ("vit_quick_swim",         "Quick Swim",        "+25% swim speed.",                                           "swim_mult",     0.25,  "self",         "",                 "",                 False),
    ("vit_no_fall",            "Hard Landing",      "Falls of <5 m deal no damage.",                              "fall_threshold",5.0,   "self",         "on_land",          "",                 False),
    ("vit_well_rested",        "Well Rested",       "Sleeping in a bed grants +10% all skill XP for 1 day.",     "xp_mult",       0.10,  "self",         "rested",           "",                 True),
    ("vit_carry_more",         "Strong Back",       "+20% carry weight.",                                         "carry_mult",    0.20,  "self",         "",                 "",                 False),
    ("vit_swift_step",         "Swift Step",        "+5% movement speed always.",                                 "move_mult",     0.05,  "self",         "",                 "",                 False),
    ("vit_endurance",          "Endurance",         "+15% max endurance.",                                        "max_stam_mult", 0.15,  "self",         "",                 "",                 False),
    ("vit_iron_will",          "Iron Will",         "Status effects last 25% less time on you.",                 "duration_mult",-0.25,  "self",         "negative",         "",                 False),
    ("vit_second_chance",      "Second Chance",     "Once per day, the next lethal blow leaves you at 1 HP.",   "proc_once",     1.0,   "self",         "lethal_damage",    "",                 True),
    ("vit_meditation",         "Meditation",        "Resting refills HP + endurance to full.",                   "refill_full",   1.0,   "self",         "on_rest",          "",                 False),
    ("vit_grit",               "Grit",              "Below 25% HP, take 25% less damage.",                       "damage_taken", -0.25,  "self",         "self_low_hp",      "",                 False),
    ("vit_swift_drink",        "Swift Drink",       "Drinking water-skin heals +5 HP.",                          "heal_flat",     5.0,   "food",         "drink",            "",                 False),
    ("vit_hunger_resilience",  "Hunger Resilience", "Starvation effects begin 50% later.",                       "duration_mult",-0.50,  "self",         "hunger",           "",                 False),
    ("vit_iron_lungs",         "Iron Lungs",        "+50% breath underwater.",                                    "breath_mult",   0.50,  "self",         "",                 "",                 False),
    ("vit_swift_climb",        "Swift Climb",       "Climbing ladders + ledges costs no endurance.",            "stamina_mult", -1.0,   "self",         "climb",            "",                 False),
    ("vit_wakeful",            "Wakeful",           "Going without sleep for 24 h has no negative effects.",     "flag",          1.0,   "self",         "",                 "",                 False),
    ("vit_titan",              "Titan",             "+25 max HP.",                                                "max_hp_flat",   25.0,  "self",         "",                 "",                 False),
    ("vit_indomitable",        "Indomitable",       "+15% all damage resistance.",                                "damage_taken", -0.15,  "self",         "",                 "",                 False),
],

# =================== SPEECH ===================
"speech": [
    ("speech_charm",           "Charm",             "+5 effective Speech in friendly checks.",                   "speech_bonus",  5.0,   "speech",       "friendly",         "",                 False),
    ("speech_intimidate",      "Intimidate",        "+5 effective Speech in hostile checks.",                   "speech_bonus",  5.0,   "speech",       "hostile",          "",                 False),
    ("speech_persuade",        "Persuade",          "+5 effective Speech in neutral checks.",                   "speech_bonus",  5.0,   "speech",       "neutral",          "",                 False),
    ("speech_merchant",        "Merchant",          "+10% sell price.",                                          "sell_mult",     0.10,  "trade",        "",                 "",                 False),
    ("speech_haggler",         "Haggler",           "-10% buy price.",                                           "buy_mult",     -0.10,  "trade",        "",                 "",                 False),
    ("speech_bard",            "Bard",              "Singing in taverns grants +10 disposition to all nearby for 1 day.","disposition_mult",10.0,"speech","tavern_song",    "",                 True),
    ("speech_lie",             "Practiced Lie",     "+10 effective Speech when telling falsehoods.",            "speech_bonus", 10.0,   "speech",       "deception",        "",                 False),
    ("speech_truth",           "Earnest Tongue",    "+10 effective Speech when telling truth.",                 "speech_bonus", 10.0,   "speech",       "truth",            "",                 False),
    ("speech_listener",        "Good Listener",     "NPCs reveal 25% more secret topics.",                     "secret_mult",   0.25,  "speech",       "",                 "",                 False),
    ("speech_diplomat",        "Diplomat",          "+10 disposition with all NPCs of one faction.",            "disposition_flat",10.0,"speech",       "active_ability",   "",                 True),
    ("speech_master_haggle",   "Master Haggler",    "Additional -10% buy price after Haggler.",                 "buy_mult",     -0.10,  "trade",        "",                 "",                 False),
    ("speech_market_voice",    "Market Voice",      "Sell prices +15% in cities.",                              "sell_mult",     0.15,  "trade",        "city",             "",                 False),
    ("speech_oratorical",      "Oratorical",        "Persuade checks succeed at DC 5 above your Speech.",       "dc_cushion",    5.0,   "speech",       "",                 "",                 True),
    ("speech_quick_tongue",    "Quick Tongue",      "Speech checks can be retried once after fail.",           "retry_flag",    1.0,   "speech",       "",                 "",                 True),
    ("speech_wit",             "Wit",               "+10 effective Speech vs nobles + scholars.",              "speech_bonus", 10.0,   "speech",       "noble",            "",                 False),
    ("speech_bargain",         "Bargain",           "+15% gold from quest rewards.",                            "gold_mult",     0.15,  "trade",        "quest_reward",     "",                 False),
    ("speech_blackmail",       "Blackmail",         "Failed checks reveal a piece of leverage 25% of the time.","proc_chance",   0.25,  "speech",       "on_fail",          "",                 True),
    ("speech_reputation",      "Reputation",        "+5 disposition with all factions per Act.",                "disposition_flat",5.0, "speech",       "passive_per_act",  "",                 False),
    ("speech_calm",            "Calming Voice",     "Reduce nearby enemy aggression for 5 s once per encounter.","aoe_apply",    5.0,   "speech",       "active_ability",   "",                 True),
    ("speech_inspire",         "Inspire",           "Companions deal +10% damage for 30 s after a speech.",     "buff_mult",     0.10,  "companions",   "active_ability",   "",                 True),
    ("speech_iron_will",       "Iron Will",         "Cannot be intimidated or persuaded against your faction.","flag",          1.0,   "speech",       "",                 "",                 False),
    ("speech_negotiator",      "Negotiator",        "Buy + sell prices improve 5% more.",                       "trade_mult",    0.05,  "trade",        "",                 "",                 False),
    ("speech_celebrity",       "Celebrity",         "Free room + board at any inn.",                            "flag",          1.0,   "trade",        "lodging",          "",                 False),
    ("speech_mediator",        "Mediator",          "Resolving a quest peacefully grants +50% XP.",            "xp_mult",       0.50,  "speech",       "peaceful_resolve", "",                 False),
    ("speech_silver_tongue",   "Silver Tongue",     "+15 effective Speech in all checks.",                     "speech_bonus", 15.0,   "speech",       "",                 "",                 False),
],

}


TRES_TEMPLATE = '''[gd_resource type="Resource" script_class="PerkData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/skills/PerkData.gd" id="1"]

[resource]
script = ExtResource("1")
perk_id = "{perk_id}"
skill = "{skill}"
level_required = {level_required}
milestone_index = {milestone_index}
display_name = "{display_name}"
description = "{description}"
exclusive_group = "{exclusive_group}"
is_active = {is_active}
effect_type = "{effect_type}"
effect_value = {effect_value}
effect_target = "{effect_target}"
condition = "{condition}"
'''


GD_TEMPLATE = '''extends Perk

# Active perk: {display_name}
# Skill: {skill}   |   Milestone: L{level_required}
# {description}
#
# Hooks below are stubs; the gameplay system that fires the hook is
# the source of truth for what this perk actually does at runtime.
# Effect-table inspection lets passive logic + UI also reflect this
# perk where it matters.

func _init() -> void:
    pass

{hooks}
'''


def emit_hook_stub(hook_name: str) -> str:
    return f"""func {hook_name}(ctx: Dictionary) -> void:
    # TODO: implement
    pass"""


# Map perk to which hook it most likely uses, for stub seeding.
ACTIVE_PERK_HOOKS = {
    "sword_riposte":          ["on_parry", "on_attack"],
    "sword_disarming_strike": ["on_attack"],
    "sword_bleed":            ["on_attack"],
    "sword_whirlwind":        ["on_attack"],
    "sword_thicket":          ["on_attack"],
    "sword_battle_rhythm":    ["on_attack"],
    "sword_second_wind":      ["on_take_damage"],
    "sword_swords_dance":     ["on_attack"],
    "sword_grand_strike":     ["on_attack"],
    "sword_dread_blade":      ["on_kill"],
    "sword_undying":          ["on_take_damage"],
    "throw_double_grab":      ["on_picked"],
    "throw_ricochet":         ["on_attack"],
    "throw_marked_target":    ["on_attack"],
    "throw_charged_throw":    ["on_attack"],
    "throw_blood_arrow":      ["on_kill"],
    "throw_volley":           ["on_attack"],
    "throw_perfect_aim":      ["on_attack"],
    "throw_storm_caller":     ["on_attack"],
    "throw_javelin_storm":    ["on_kill"],
    "bow_silent_kill":        ["on_kill"],
    "bow_focus":              ["on_attack"],
    "bow_double_nock":        ["on_attack"],
    "bow_bleed_arrows":       ["on_attack"],
    "bow_fire_arrows":        ["on_attack"],
    "bow_volley":             ["on_attack"],
    "bow_pincushion":         ["on_attack"],
    "bow_third_eye":          ["on_attack"],
    "mine_vein_sense":        ["on_picked"],
    "mine_ore_sense":         ["on_picked"],
    "mine_swing_through":     ["on_voxel_broken"],
    "mine_lucky_strike":      ["on_voxel_broken"],
    "mine_relentless":        ["on_voxel_broken"],
    "fell_tree_sense":        ["on_picked"],
    "fell_double_strike":     ["on_voxel_broken"],
    "fell_branch_break":      ["on_voxel_broken"],
    "fell_select_cut":        ["on_voxel_broken"],
    "fell_axe_thrower":       ["on_picked"],
    "fell_evergreen":         ["on_voxel_broken"],
    "fell_split_wood":        ["on_kill"],
    "dig_clay_finder":        ["on_voxel_broken"],
    "dig_gravel_finder":      ["on_voxel_broken"],
    "dig_bury":               ["on_voxel_broken"],
    "dig_grave_robber":       ["on_voxel_broken"],
    "dig_archeologist":       ["on_voxel_broken"],
    "dig_terrain_eye":        ["on_picked"],
    "dig_water_finder":       ["on_picked"],
    "dig_field_medic":        ["on_voxel_broken"],
    "dig_quickburial":        ["on_voxel_broken"],
    "dig_no_traps":           ["on_picked"],
    "demo_proximity":         ["on_attack"],
    "demo_chain":             ["on_attack"],
    "demo_focused_blast":     ["on_attack"],
    "demo_smoker":            ["on_attack"],
    "demo_charge_recovery":   ["on_attack"],
    "demo_concussion":        ["on_attack"],
    "demo_blast_eyes":        ["on_picked"],
    "lock_thief_eye":         ["on_picked"],
    "lock_silver_pick":       ["on_lock_opened"],
    "lock_pickpocket":        ["on_picked"],
    "lock_double_loot":       ["on_lock_opened"],
    "lock_hidden_caches":     ["on_picked"],
    "lock_keen_eye":          ["on_lock_opened"],
    "lock_burglar":           ["on_lock_opened"],
    "lock_decoy":             ["on_picked"],
    "lock_perfect_pick":      ["on_lock_opened"],
    "alch_keen_nose":         ["on_picked"],
    "alch_taster":            ["on_picked"],
    "alch_poisoner":          ["on_picked"],
    "alch_double_brew":       ["on_potion_drunk"],
    "alch_recipe_eye":        ["on_picked"],
    "alch_versatility":       ["on_potion_drunk"],
    "smith_master_form":      ["on_picked"],
    "smith_runed":             ["on_picked"],
    "smith_legendary_form":   ["on_picked"],
    "smith_recipe_eye":       ["on_picked"],
    "vit_well_rested":        ["on_xp_gained"],
    "vit_second_chance":      ["on_take_damage"],
    "speech_bard":            ["on_picked"],
    "speech_diplomat":        ["on_picked"],
    "speech_oratorical":      ["on_picked"],
    "speech_quick_tongue":    ["on_picked"],
    "speech_blackmail":       ["on_picked"],
    "speech_calm":            ["on_picked"],
    "speech_inspire":         ["on_picked"],
}


def main() -> None:
    total_perks = 0
    total_active = 0
    for skill, entries in SPECS.items():
        assert len(entries) == 25, f"{skill}: expected 25 perks, got {len(entries)}"
        skill_dir = TRES_ROOT / skill
        script_dir = SCRIPT_ROOT / skill
        skill_dir.mkdir(parents=True, exist_ok=True)
        script_dir.mkdir(parents=True, exist_ok=True)
        for i, entry in enumerate(entries):
            (perk_id, display_name, description,
             effect_type, effect_value, effect_target, condition,
             exclusive_group, is_active) = entry
            level_required = (i + 1) * 4
            milestone_index = i
            tres = TRES_TEMPLATE.format(
                perk_id=perk_id,
                skill=skill,
                level_required=level_required,
                milestone_index=milestone_index,
                display_name=display_name.replace('"', '\\"'),
                description=description.replace('"', '\\"'),
                exclusive_group=exclusive_group,
                is_active="true" if is_active else "false",
                effect_type=effect_type,
                effect_value=effect_value,
                effect_target=effect_target,
                condition=condition,
            )
            (skill_dir / f"{perk_id}.tres").write_text(tres)
            total_perks += 1

            if is_active:
                hooks_for_perk = ACTIVE_PERK_HOOKS.get(perk_id, ["on_picked"])
                hook_bodies = "\n\n\n".join(emit_hook_stub(h) for h in hooks_for_perk)
                gd_text = GD_TEMPLATE.format(
                    display_name=display_name,
                    skill=skill,
                    level_required=level_required,
                    description=description,
                    hooks=hook_bodies,
                )
                (script_dir / f"{perk_id}.gd").write_text(gd_text)
                total_active += 1

    print(f"Wrote {total_perks} perks ({total_active} active).")


if __name__ == "__main__":
    main()
