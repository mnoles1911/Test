extends Perk

# Active perk: Double Brew
# Skill: alchemy   |   Milestone: L44
# +25% chance to craft 2 potions instead of 1.
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
