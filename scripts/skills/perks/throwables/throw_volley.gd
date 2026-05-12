extends Perk

# Active perk: Volley
# Skill: throwables   |   Milestone: L68
# Each thrown weapon hit reduces the next throw's endurance cost by 50% for 3 s.
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
