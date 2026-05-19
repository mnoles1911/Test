extends RefCounted

# NOTE: deliberately NO `class_name`. Global class names resolve from
# res://.godot/global_script_class_cache.cfg, which only the editor
# regenerates — a brand-new class_name would fail to parse under
# `--headless` (no editor scan) and break every autoload that uses it.
# Consumers reference this via a path `preload` const instead
# (cache-independent, headless-safe):
#     const WaterMaterial := preload("res://scripts/WaterMaterial.gd")

# WaterMaterial — single authority for "which CHANNEL_TYPE id(s) mean
# water" and the sim-level -> render-id projection.
#
# WHY (plain English): before the native-fluid pivot, "water is 5" was
# hardcoded in FOUR independent places (WaterFlowManager, VoxelEditManager
# x2, World3DBootstrap, and the C++ generator). The pivot turns water
# into N=8 per-level Zylann fluid models, so "is this water?" must become
# a set/range check and the written TYPE id must become a function of the
# sim level. Phase 1 funnels every consumer through here with ZERO
# behaviour change — everything still resolves to exactly 5 / 0 — so the
# later swap is a one-file edit (this file), not a project-wide hunt.
#
# The DATA5 level/dir codec (WaterByteCodec) stays the sim source of
# truth; this file is the RENDER projection of it. See
# design/WATER_NATIVE_FLUID_GATE0_RESULTS.md for the bound API facts.

# What pre-pivot saves and the pre-pivot C++ generator wrote for water:
# the old single transparent-cube model (still in blocky_library.tres;
# the C++ generator still emits it until Phase 4). is_water_type() keeps
# accepting it through the transition so a generated id-5 ocean and a
# sim-placed fluid cell are both "water".
const LEGACY_WATER_ID: int = 5

# Native fluid level models. The blocky library has 16 static models
# (ids 0..15) in blocky_library.tres; World3DBootstrap injects the 8
# VoxelBlockyModelFluid models at runtime via add_model(), so they land
# at the contiguous block [16..23]. level L (1..8) -> id BASE + L - 1.
# WATER_LEVEL_COUNT == WaterByteCodec.MAX_LEVEL (8) by construction.
const WATER_FLUID_BASE_ID: int = 16
const WATER_LEVEL_COUNT: int = 8
const FULL_FLUID_ID: int = WATER_FLUID_BASE_ID + WATER_LEVEL_COUNT - 1  # level 8

# Canonical single representative id (queries / migration target). The
# full-level fluid id is the natural "this is water" representative now.
const BODY_ID: int = FULL_FLUID_ID

# Every CHANNEL_TYPE id that counts as water: the legacy cube id (during
# the Phase 2->4 transition) plus the 8 fluid-level ids. Documentation /
# tests; the hot path uses the range check in is_water_type().
const WATER_IDS: Array[int] = [5, 16, 17, 18, 19, 20, 21, 22, 23]


# "Is this CHANNEL_TYPE value water?" — replaces every `== 5` /
# `== WATER_TYPE_ID` consumer. Accepts the legacy cube id (5, still
# emitted by the C++ generator until Phase 4) AND the 8 fluid-level ids
# [16..23]. Contiguous range -> single branch on the hot path.
static func is_water_type(type_id: int) -> bool:
	return type_id == LEGACY_WATER_ID \
		or (type_id >= WATER_FLUID_BASE_ID and type_id < WATER_FLUID_BASE_ID + WATER_LEVEL_COUNT)


# Project a sim water level (0 = air .. 8 = full, see WaterByteCodec)
# plus flow direction onto the CHANNEL_TYPE id the blocky mesher draws.
# Phase 2: collapse to ONE id — the full-level fluid model — so the
# rendering swap (cube -> native fluid) is proven in isolation before
# the sim drives per-level ids. Phase 3 switches this to the true
# per-level id: WATER_FLUID_BASE_ID + clampi(level,1,8) - 1.
static func render_id_for_level(level: int, _dir: int) -> int:
	return FULL_FLUID_ID if level > 0 else 0


# Legacy save / generator id -> canonical body id. Identity today;
# Phase 7 save-migration maps the old literal 5 onto the full-level
# fluid id here.
static func map_legacy_id(type_id: int) -> int:
	return type_id
