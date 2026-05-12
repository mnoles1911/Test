extends Perk

# Active perk: Second Wind
# Skill: sword   |   Milestone: L76
# Once per fight, regain 30% endurance when it hits 0.
#
# Hooks below are stubs; the gameplay system that fires the hook is
# the source of truth for what this perk actually does at runtime.
# Effect-table inspection lets passive logic + UI also reflect this
# perk where it matters.

func _init() -> void:
    pass

func on_take_damage(ctx: Dictionary) -> void:
    # TODO: implement
    pass
