extends Perk

# Active perk: Swing Through
# Skill: mining   |   Milestone: L56
# Pickaxe hits can break 2 adjacent voxels of the same type.
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
