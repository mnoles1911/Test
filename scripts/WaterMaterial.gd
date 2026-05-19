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

# Canonical single representative id (collision/queries/migration target).
const BODY_ID: int = 5

# What pre-pivot saves and the pre-pivot C++ generator wrote for water.
const LEGACY_WATER_ID: int = 5

# Every CHANNEL_TYPE id that counts as water. Phase 1: just [5].
# Phase 2 expands this to the 8 contiguous fluid-level model ids.
# (Array literal — a const must be a constant expression; the
# PackedInt32Array(...) constructor is not one.)
const WATER_IDS: Array[int] = [5]


# "Is this CHANNEL_TYPE value water?" — replaces every `== 5` /
# `== WATER_TYPE_ID` consumer. Phase 1 = exact identity with the old
# single-id test; Phase 2 becomes a contiguous-range check.
static func is_water_type(type_id: int) -> bool:
	return type_id == BODY_ID


# Project a sim water level (0 = air .. 8 = full, see WaterByteCodec)
# plus flow direction onto the CHANNEL_TYPE id the blocky mesher draws.
# Phase 1: identity — any water -> BODY_ID, else air (byte-identical to
# the old `5 if WaterByteCodec.is_water(byte) else 0`). Phase 3: returns
# the per-level fluid model id.
static func render_id_for_level(level: int, _dir: int) -> int:
	return BODY_ID if level > 0 else 0


# Legacy save / generator id -> canonical body id. Identity today;
# Phase 7 save-migration maps the old literal 5 onto the full-level
# fluid id here.
static func map_legacy_id(type_id: int) -> int:
	return type_id
