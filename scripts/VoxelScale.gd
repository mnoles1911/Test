extends RefCounted

# NOTE: deliberately NO `class_name`. Global class names resolve from
# res://.godot/global_script_class_cache.cfg, which only the editor
# regenerates — a brand-new class_name would fail to parse under
# `--headless` (no editor scan) and break every autoload that uses it.
# Consumers reference this via a path `preload` const instead
# (cache-independent, headless-safe):
#     const VoxelScale := preload("res://scripts/VoxelScale.gd")

# VoxelScale — THE single authority for the voxel grid scale.
#
# WHY THIS FILE EXISTS (plain English):
#
# The number 6.0 (meaning "6 voxels fit in one world metre") was
# hardcoded in at least a dozen different scripts. That meant if we
# ever changed the scale — for instance, the upcoming pivot to 10
# voxels/metre for finer terrain detail — we'd have to hunt down every
# one of those hardcoded 6.0 values and change them. Miss one, and the
# game silently breaks in ways that are very hard to debug.
#
# So this file is the ONE place that knows the scale. Every other file
# reads from here. When the pivot to 10 vox/m happens, this is the
# only file that changes.
#
# THE CONTRACT: the VoxelLodTerrain node in World3D.tscn MUST have
# transform.scale = Vector3(VOXEL_SIZE_M, VOXEL_SIZE_M, VOXEL_SIZE_M).
# That is enforced at boot by World3DBootstrap.gd — it reads the scene
# node's scale and asserts it matches VOXEL_SIZE_M (correcting it with
# a push_error if not). The .tscn can't read a const from a script at
# edit time, so the scene file stores the numeric value and the
# bootstrap enforces alignment at runtime.
#
# RULE: never hardcode 6.0, 0.166667, or 1.0/6.0 anywhere near voxel
# math. Use VOXELS_PER_METER and VOXEL_SIZE_M from here instead.
# See design/PATTERNS_AND_GOTCHAS.md for the full rule.


# How many voxels (grid cells) span one metre in world space.
# Canonical project value since 2026-05-03. A later PR will change
# this to 10 for the 10cm-voxel rearchitecture; when that happens,
# only this constant needs to change (all consumers read from here).
const VOXELS_PER_METER: float = 6.0

# Edge length of one voxel in world-space metres.
# 1.0 / VOXELS_PER_METER = 1.0 / 6.0 ≈ 0.16667 m ≈ 16.7 cm.
# This is the value that goes in VoxelLodTerrain.transform.scale
# (all three axes equal — uniform scale).
const VOXEL_SIZE_M: float = 1.0 / VOXELS_PER_METER


# Convert a world-space distance (in metres) to the nearest integer
# number of voxels. Useful for checking "how many voxels wide is this
# thing?" or sizing explosion / gravity bubbles.
#
# Note: rounds to nearest, not floors — a 0.9 m object is 5 voxels
# wide, not 4. If you need floor-rounding, use int(m * VOXELS_PER_METER)
# directly at the call site.
#
# This function is a pure calculation — no SceneTree access — so it is
# safe to call from generator worker threads as well as the main thread.
static func meters_to_voxels(m: float) -> int:
	return roundi(m * VOXELS_PER_METER)


# Convert an integer voxel count to its world-space distance in metres.
# Useful for "I know this is N voxels; where is that in the world?"
#
# Pure calculation, worker-thread-safe.
static func voxels_to_meters(v: int) -> float:
	return float(v) * VOXEL_SIZE_M
