extends Perk

# Active perk: Sword's Dance
# Skill: sword   |   Milestone: L80
# +10% damage and -10% endurance cost while moving with sword.
#
# Hooks below are stubs; the gameplay system that fires the hook is
# the source of truth for what this perk actually does at runtime.
# Effect-table inspection lets passive logic + UI also reflect this
# perk where it matters.

func _init() -> void:
    pass

func on_attack(ctx: Dictionary) -> void:
    # TODO: implement
    pass
