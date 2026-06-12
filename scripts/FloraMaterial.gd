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


# --- 10cm micro-detail pass: surface scatter (D1) -------------------
# Pebbles and twigs — tiny low-profile decoration voxels scattered on the
# ground so the world "reads as material" up close (VISION_VOXEL_10CM.md
# micro-detail pillar). They are NOT flora (not vegetation), so they get
# their OWN helper `is_surface_detail()` — but for the physics/sim they
# behave EXACTLY like flora: pass-through air. A pebble must never anchor a
# structure, never ride a falling cluster, never dam water, never count as
# solid ground.
#
# Ids 27, 28 sit DIRECTLY after the flora ids (24..26) so the combined
# "pass-through decoration" range is one contiguous block 24..28 — which is
# what every physics/sim exclusion site range-checks (see is_passthrough()).
# They are injected at runtime right after the flora models in
# World3DBootstrap, and scattered by the C++ generator with its own salt.
#
#   27 = pebble   (a squat grey-brown mini-rock lump)
#   28 = twig     (a thin horizontal brown stick)
const PEBBLE_ID: int = 27
const TWIG_ID: int = 28

const SURFACE_DETAIL_BASE_ID: int = PEBBLE_ID   # 27
const SURFACE_DETAIL_COUNT: int = 2             # 27, 28
const SURFACE_DETAIL_IDS: Array[int] = [27, 28]

# The combined pass-through decoration range: flora (24..26) PLUS surface
# detail (27..28) = 24..28 inclusive. EVERY physics/sim site that treats
# flora as air uses THIS range so pebbles/twigs get the identical exemption
# with one branch and no second preload. The C++ ports (gravity, sever) and
# GravityReference.gd mirror this exact range by value.
const PASSTHROUGH_BASE_ID: int = FLORA_BASE_ID                          # 24
const PASSTHROUGH_COUNT: int = FLORA_COUNT + SURFACE_DETAIL_COUNT       # 5 → 24..28


# "Is this CHANNEL_TYPE value flora?" — the grass/flower analogue of
# WaterMaterial.is_water_type(). Contiguous range -> single branch.
# NOTE: flora is the VEGETATION subset (24..26) only — pebbles/twigs are
# surface detail, not flora. For the "treat as pass-through air" question
# use is_passthrough(), which covers both.
static func is_flora(type_id: int) -> bool:
	return type_id >= FLORA_BASE_ID and type_id < FLORA_BASE_ID + FLORA_COUNT


# "Is this CHANNEL_TYPE value pebble/twig surface detail?" (27..28).
# Separate helper from is_flora() so call sites that genuinely care about
# vegetation (e.g. trample, scythe drops) don't accidentally include rocks.
static func is_surface_detail(type_id: int) -> bool:
	return type_id >= SURFACE_DETAIL_BASE_ID and type_id < SURFACE_DETAIL_BASE_ID + SURFACE_DETAIL_COUNT


# "Should the physics/sim treat this voxel as pass-through air?" — true for
# BOTH flora (24..26) and surface detail (27..28). This is the single helper
# every gravity / sever / finite-water exclusion site funnels through, so
# adding a new decoration id is a one-line range change here, mirrored by
# value in the two C++ ports + GravityReference.gd.
static func is_passthrough(type_id: int) -> bool:
	return type_id >= PASSTHROUGH_BASE_ID and type_id < PASSTHROUGH_BASE_ID + PASSTHROUGH_COUNT
