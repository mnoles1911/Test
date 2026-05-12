extends Perk

# Active perk: Marked Target
# Skill: throwables   |   Milestone: L40
# First thrown hit on an enemy marks them: +20% damage from all sources for 5 s.
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
