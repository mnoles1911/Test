extends Perk

# Active perk: Bleed
# Skill: sword   |   Milestone: L32
# Sword hits apply a bleed dealing 1 dmg/s for 6 s.
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
