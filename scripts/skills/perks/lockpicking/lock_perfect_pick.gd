extends Perk

# Active perk: Perfect Pick
# Skill: lockpicking   |   Milestone: L88
# First attempt of the day on any lock auto-wins tier-2 or below.
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
