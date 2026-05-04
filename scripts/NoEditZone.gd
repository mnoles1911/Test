extends Area3D
# NoEditZone — optional companion script for Area3Ds in the
# "no_edit_zone" group.
#
# What this is in plain English:
#
# NoEditZones don't strictly need a script — the registry just queries
# Godot's physics system for any Area3D in the "no_edit_zone" group. So
# a designer can drop a bare Area3D into the scene, add it to the group,
# and call it done. That works for the basic terrain-edit gate.
#
# This script exists for one reason: per-zone configuration of water-
# flow behavior. Some zones (settlements, dungeons) should block water
# flow; some special cases (a flooded crypt that fills as the player
# progresses) should let water flow through.
#
# To use:
#   1. Drop an Area3D into the scene as before.
#   2. Add it to the group "no_edit_zone".
#   3. Attach this script.
#   4. The Inspector now shows blocks_water_flow (default true). Toggle
#      it for special-case zones.
#
# The NoEditZoneRegistry.is_water_flow_blocked_at(world_pos) helper
# returns true if any overlapping zone has blocks_water_flow=true (or
# is a bare Area3D without this script — default-blocked for backward
# compatibility with PR #126's NoEditZone authoring pattern).
#
# Reference: design/3D_VOXEL_MIGRATION.md → "NoEditZones — The Opt-Out Model"


@export var blocks_water_flow: bool = true
# When true, WaterFlowManager refuses to place water cells inside this
# zone. A river redirected toward this zone will dam against the
# boundary rather than flooding the protected interior.
#
# Set to false ONLY for zones where designed flooding is wanted —
# a crypt that fills with rising water as a dramatic beat, a flood
# scene, etc. Default true means "settlements stay dry."


func _ready() -> void:
	# Auto-add to the group if the designer attached this script but
	# forgot the group. Eliminates the most common authoring mistake.
	if not is_in_group("no_edit_zone"):
		add_to_group("no_edit_zone")
