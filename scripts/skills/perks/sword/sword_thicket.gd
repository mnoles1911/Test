extends Perk

# Active perk: Thicket
# Skill: sword   |   Milestone: L48
# +10% damage per additional enemy within 3 m (cap +40%).
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
