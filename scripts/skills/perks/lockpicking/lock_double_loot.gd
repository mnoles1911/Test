extends Perk

# Active perk: Double Loot
# Skill: lockpicking   |   Milestone: L36
# Pick locks drop +1 random consumable.
#
# Hooks below are stubs; the gameplay system that fires the hook is
# the source of truth for what this perk actually does at runtime.
# Effect-table inspection lets passive logic + UI also reflect this
# perk where it matters.

func _init() -> void:
    pass

func on_lock_opened(ctx: Dictionary) -> void:
    # TODO: implement
    pass
