extends Node3D

# WaterBiomeZone — per-biome underwater fog/tint override (water-polish
# PR 4, Phase 4c of design/SWIMMING_AND_WATER.md).
#
# What this is in plain English:
#
# Drop one of these over a water body in the editor, size `extent` to
# cover it, and pick the murk: while the player's head is under water
# INSIDE this box, UnderwaterFilter swaps its fog/tint anchors for the
# ones authored here — swamp water goes green and thick, mountain
# lakes stay clear and blue. Leaving the box (or surfacing) snaps back
# to the global defaults. Snap, not tween, by design: you can't see
# both sides of the transition at once while underwater.
#
# Same authoring pattern as NoEditZone: a plain Node3D + exported box,
# in a group the consumer queries. No per-frame cost when unused —
# UnderwaterFilter only resolves zones at the submerge transition.

@export var biome_name: String = "swamp"
# Designer label, printed on submerge so you can confirm WHICH zone
# grabbed the player.

@export var extent: Vector3 = Vector3(40.0, 12.0, 40.0)
# Box size in METRES, centred on this node. Make Y generous — it must
# contain the player's head anywhere they can swim in this body.

# --- Fog anchors (mirror UnderwaterFilter's exports; same meanings) ---
@export var fog_density_noon: float = 0.85
@export var fog_density_night: float = 1.40
@export var fog_albedo_noon: Color = Color(0.04, 0.09, 0.05, 1.0)
@export var fog_albedo_night: Color = Color(0.01, 0.03, 0.015, 1.0)
@export var fog_emission_noon: Color = Color(0.06, 0.12, 0.05, 1.0)
@export var fog_emission_night: Color = Color(0.008, 0.02, 0.008, 1.0)
@export var tint_color: Color = Color(0.20, 0.34, 0.16, 0.14)
# Defaults above = swampy green murk (the first authored use case).


func _ready() -> void:
	add_to_group("water_biome_zone")


func contains(world_pos: Vector3) -> bool:
	var half: Vector3 = extent * 0.5
	var d: Vector3 = world_pos - global_position
	return absf(d.x) <= half.x and absf(d.y) <= half.y and absf(d.z) <= half.z
