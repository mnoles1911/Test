extends Perk

# Active perk: Silent Kill
# Skill: bow   |   Milestone: L28
# Bow kills outside combat do not alert nearby enemies.
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
