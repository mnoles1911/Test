extends Perk

# Active perk: Perfect Aim
# Skill: throwables   |   Milestone: L72
# First thrown weapon of an encounter has -50% spread.
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
