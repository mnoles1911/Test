extends Perk

# Active perk: Burglar
# Skill: lockpicking   |   Milestone: L60
# Open locks 30% faster on the third+ attempt of an evening.
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
