extends Perk

# Active perk: Bury
# Skill: excavation   |   Milestone: L32
# Spawn 1 dirt at every shovel strike to bury bodies.
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
