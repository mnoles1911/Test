extends Perk

# Active perk: Dread Blade
# Skill: sword   |   Milestone: L88
# Killing an enemy with a sword frightens others within 5 m for 3 s.
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
