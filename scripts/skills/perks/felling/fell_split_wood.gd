extends Perk

# Active perk: Split Wood
# Skill: felling   |   Milestone: L100
# Killing an enemy with an axe drops kindling.
#
# Hooks below are stubs; the gameplay system that fires the hook is
# the source of truth for what this perk actually does at runtime.
# Effect-table inspection lets passive logic + UI also reflect this
# perk where it matters.

func _init() -> void:
    pass

func on_kill(ctx: Dictionary) -> void:
    # TODO: implement
    pass
