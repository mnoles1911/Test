extends Perk

# Active perk: Double Grab
# Skill: throwables   |   Milestone: L32
# Drawing a spear pulls 2 into hand (if 2+ in inventory).
#
# Hooks below are stubs; the gameplay system that fires the hook is
# the source of truth for what this perk actually does at runtime.
# Effect-table inspection lets passive logic + UI also reflect this
# perk where it matters.

func _init() -> void:
    pass

func on_picked(ctx: Dictionary) -> void:
    # TODO: implement
    pass
