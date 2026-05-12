extends Perk

# Active perk: Select Cut
# Skill: felling   |   Milestone: L60
# Each tree felled grants +10% XP to other crafting skills.
#
# Hooks below are stubs; the gameplay system that fires the hook is
# the source of truth for what this perk actually does at runtime.
# Effect-table inspection lets passive logic + UI also reflect this
# perk where it matters.

func _init() -> void:
    pass

func on_voxel_broken(ctx: Dictionary) -> void:
    # TODO: implement
    pass
