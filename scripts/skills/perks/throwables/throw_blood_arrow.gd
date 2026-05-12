extends Perk

# Active perk: Blood Arrow
# Skill: throwables   |   Milestone: L64
# Thrown kills heal 5 HP.
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
