extends Perk

# Active perk: Charged Throw
# Skill: throwables   |   Milestone: L44
# Held throws (1 s) deal +30% damage and +10% range.
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
