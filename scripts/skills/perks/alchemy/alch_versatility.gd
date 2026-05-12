extends Perk

# Active perk: Versatility
# Skill: alchemy   |   Milestone: L88
# Drinking 2 potions within 5 s doesn't break stack rules.
#
# Hooks below are stubs; the gameplay system that fires the hook is
# the source of truth for what this perk actually does at runtime.
# Effect-table inspection lets passive logic + UI also reflect this
# perk where it matters.

func _init() -> void:
    pass

func on_potion_drunk(ctx: Dictionary) -> void:
    # TODO: implement
    pass
