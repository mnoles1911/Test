extends Perk

# Active perk: Javelin Storm
# Skill: throwables   |   Milestone: L92
# Killing with a spear refunds 50% chance to find the spear at the corpse.
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
