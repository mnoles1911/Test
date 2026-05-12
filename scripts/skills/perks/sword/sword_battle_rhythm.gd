extends Perk

# Active perk: Battle Rhythm
# Skill: sword   |   Milestone: L68
# Each consecutive sword hit within 3 s adds +3% damage (cap +24%).
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
