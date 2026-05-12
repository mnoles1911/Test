extends Perk

# Active perk: Riposte
# Skill: sword   |   Milestone: L24
# After a successful parry, your next sword hit within 2 s deals +50% damage.
#
# Hooks below are stubs; the gameplay system that fires the hook is
# the source of truth for what this perk actually does at runtime.
# Effect-table inspection lets passive logic + UI also reflect this
# perk where it matters.

func _init() -> void:
    pass

func on_parry(ctx: Dictionary) -> void:
    # TODO: implement
    pass


func on_attack(ctx: Dictionary) -> void:
    # TODO: implement
    pass
