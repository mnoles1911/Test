extends Perk

# Active perk: Disarming Strike
# Skill: sword   |   Milestone: L28
# 5% chance per sword hit to stagger the target.
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
