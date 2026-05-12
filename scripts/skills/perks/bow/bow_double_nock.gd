extends Perk

# Active perk: Double Nock
# Skill: bow   |   Milestone: L36
# 10% chance to fire a free second arrow per shot.
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
