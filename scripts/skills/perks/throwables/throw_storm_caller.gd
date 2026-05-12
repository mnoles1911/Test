extends Perk

# Active perk: Storm Caller
# Skill: throwables   |   Milestone: L88
# Detonating a powder charge near another causes both to chain.
#
# Hooks below are stubs; the gameplay system that fires the hook is
# the source of truth for what this perk actually does at runtime.
# Effect-table inspection lets passive logic + UI also reflect this
# perk where it matters.

func _init() -> void:
    pass

func on_attack(ctx: Dictionary) -> void:
    # TODO: implement
    pass
