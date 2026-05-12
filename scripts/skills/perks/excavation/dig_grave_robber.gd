extends Perk

# Active perk: Grave Robber
# Skill: excavation   |   Milestone: L36
# Excavating dropped corpses yields +1 random crafting mat.
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
