extends Perk

# Active perk: Undying
# Skill: sword   |   Milestone: L92
# Once per day, surviving a killing blow leaves you at 1 HP.
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
