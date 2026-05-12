extends Perk

# Active perk: Decoy
# Skill: lockpicking   |   Milestone: L64
# Drop a fake pick to distract patrolling NPCs for 5 s.
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
