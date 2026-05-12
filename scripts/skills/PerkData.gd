extends Resource
class_name PerkData

# Passive perk schema. One .tres per perk under
# assets/skills/perks/{skill}/{perk_id}.tres.
# Active perks ALSO have a PerkData (for display + milestone metadata)
# but additionally a sibling .gd script extending Perk with hook overrides.
# `is_active = true` tells PerkRegistry to look for the script.

@export var perk_id: String = ""
@export var skill: String = ""                         # canonical skill name (see SkillManager.SKILLS)
@export var level_required: int = 4                    # 4, 8, 12, ..., 100
@export var milestone_index: int = 0                   # 0..24

@export var display_name: String = ""
@export_multiline var description: String = ""

# Empty string = standalone, mandatory single-pick milestone.
# Non-empty = exclusive choice; the player picks one from the group.
@export var exclusive_group: String = ""

@export var is_active: bool = false                    # if true, expect scripts/skills/perks/{skill}/{perk_id}.gd

# Declarative effect for passive perks. Active perks ignore these fields
# (the .gd script does the work) but may still set them for UI display.
@export var effect_type: String = ""                   # "damage_mult" | "yield_bonus" | "stamina_regen" | ...
@export var effect_value: float = 0.0
@export var effect_target: String = ""                 # "sword_weapons" | "all" | "iron_pickaxe" | ...
@export var condition: String = ""                     # "" (always) | "on_power_attack" | "low_hp_50" | ...
