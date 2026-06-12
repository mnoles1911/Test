extends RefCounted

# NOTE: deliberately NO `class_name` — exactly like WaterMaterial.gd and
# VoxelScale.gd. Global class names resolve from
# res://.godot/global_script_class_cache.cfg, which only the editor
# regenerates; a brand-new class_name would fail to parse under
# `--headless` (no editor scan) and break every autoload that uses it.
# Consumers reference this via a path `preload` const instead
# (cache-independent, headless-safe):
#     const FloraMaterial := preload("res://scripts/FloraMaterial.gd")

# FloraMaterial — single authority for "which CHANNEL_TYPE id(s) mean
# micro-voxel flora" (grass blades, flowers).
#
# WHY (plain English): R4 adds real, destructible voxel grass and
# flowers — the signature "Lay of the Land" look. They are REAL voxels
# (cross-quad custom meshes) that you can walk through and dig out, NOT
# multimesh decoration. Because they live in CHANNEL_TYPE just like dirt
# and stone, every system that asks "is this voxel solid ground?" would
# wrongly say yes for a blade of grass — and a tree would "connect" to
# the ground through a grass blade, water would treat a flower as a wall,
# a falling cluster would carry blades along for the ride.
#
# So flora needs the same treatment water got: a single helper that every
# physics/sim system funnels through. `is_flora(t)` is the grass/flower
# equivalent of `WaterMaterial.is_water_type(t)`. Wherever code already
# skips water (gravity flood-fill, sever BFS, the finite-water solid
# callback), it now ALSO skips flora.
#
# Mirrors WaterMaterial.gd's structure on purpose so the two read the
# same way. The ids are chosen ABOVE the water fluid range (water = 16..23)
# so the two id spaces never overlap.

# Flora CHANNEL_TYPE ids. The blocky library has 16 static models (ids
# 0..15) in blocky_library.tres; World3DBootstrap injects the 8 water
# fluid models at runtime at ids 16..23. Flora is injected right after,
# at the next three free contiguous ids 24..26. These ids are reserved
# here so the registry, the C++ generator, the bootstrap, and the sim
# code all agree on the same three numbers.
#
#   24 = grass_blade   (a thin green blade — the field filler)
#   25 = flower_red    (a poppy-red bloom)
#   26 = flower_blue   (a cornflower-blue bloom)
const GRASS_BLADE_ID: int = 24
const FLOWER_RED_ID: int = 25
const FLOWER_BLUE_ID: int = 26

# Contiguous range [FLORA_BASE_ID .. FLORA_BASE_ID + FLORA_COUNT) covers
# every flora id. A range check is one branch on the hot path (same trick
# WaterMaterial uses for the 16..23 fluid block).
const FLORA_BASE_ID: int = GRASS_BLADE_ID   # 24
const FLORA_COUNT: int = 3                   # 24, 25, 26

# Every flora CHANNEL_TYPE id, for documentation / tests. The hot path
# uses the range check in is_flora().
const FLORA_IDS: Array[int] = [24, 25, 26]


# "Is this CHANNEL_TYPE value flora?" — the grass/flower analogue of
# WaterMaterial.is_water_type(). Contiguous range -> single branch.
# Callers that already special-case water (gravity, sever, finite water)
# add an OR on this so grass and flowers are treated as pass-through air
# by the physics/sim, never as solid ground and never as water.
static func is_flora(type_id: int) -> bool:
	return type_id >= FLORA_BASE_ID and type_id < FLORA_BASE_ID + FLORA_COUNT
