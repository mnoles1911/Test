extends Perk

# Active perk: Volley
# Skill: bow   |   Milestone: L68
# Each consecutive hit within 3 s adds +5% damage (cap +30%).
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
