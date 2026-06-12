class_name BiomeProfile
extends Resource

# BiomeProfile — pure DATA describing one biome's terrain recipe.
#
# WHAT THIS IS (plain English): a biome (plains, hills, forest, desert,
# mountains) is just a bag of numbers that tells the world generator how
# to shape and dress the ground there — how tall the hills are, how flat
# the floor is, what the surface material is, how much grass grows. This
# Resource holds those numbers and NOTHING else: no code runs here. The
# C++ generator reads a flattened copy (a plain Dictionary) of these
# fields per biome and blends them at biome borders.
#
# HOW A DESIGNER ADDS / TUNES A BIOME:
#   1. In Godot, open assets/biomes/<name>.tres (or right-click → New
#      Resource → BiomeProfile to make a new one).
#   2. Every field below shows in the Inspector with these comments as
#      tooltips. Tune the numbers, save, restart.
#   3. Register a new biome in the bootstrap's BIOME FRAMEWORK block
#      (World3DBootstrap.gd) so it gets loaded + bound to a Whittaker kind.
#
# `class_name BiomeProfile` is intentional here — it mirrors VoxelMaterial.gd
# (also a `class_name` Resource authored as .tres in the Inspector). This is
# the designer-facing data type, NOT a path-preloaded autoload helper, so the
# class_name is safe (the editor scan registers it; the headless `biome`
# selector loads the .tres by PATH via load(), never by the global name).
#
# Reference: design/BIOME_FRAMEWORK.md


# =============================================================
# HEIGHTFIELD — the shape of the ground
# =============================================================
# All frequencies are PER-METRE (cycles per world metre), so the terrain
# keeps its real-world shape regardless of the voxel grid scale. All
# amplitudes are in METRES of elevation.

@export_group("Heightfield")

@export_range(0.0, 80.0, 0.5) var base_amplitude_m: float = 8.0
# Half the vertical range of the MACRO relief, in metres. 2 = nearly flat
# plains; 8 = rolling; 55 = dramatic mountains. The macro noise swings the
# ground ±base_amplitude_m around the biome's baseline.

@export_range(0.0001, 0.02, 0.0001) var base_frequency_per_m: float = 0.0012
# How quickly the macro relief undulates, in cycles per metre. Lower =
# broader landforms (a single hill spans hundreds of metres); higher =
# choppier. 0.0012 ≈ one full rise-and-fall every ~800 m.

@export_range(0.0, 1.0, 0.01) var ridge_mix: float = 0.0
# Blends the macro SHAPE between two looks:
#   0.0 = fBm / billow — smooth rolling hills (plains, forest).
#   1.0 = ridged — sharp |noise| crests + valleys (mountains).
# Intermediate values mix the two; 0.35 gives desert mesas a hint of edge.

@export_range(0.0, 1.0, 0.01) var flatness: float = 0.0
# Plateau redistribution. Pushes the mid-range of the macro field toward a
# flat plateau while preserving the extremes (peaks + valleys). The math is
# a smoothstep S-curve blended in by `flatness`:
#   shaped = lerp(h, smoothstep(h), flatness)
# smoothstep compresses the middle band (→ broad flats) and steepens the
# tails (→ peaks stay sharp). 0 = no flattening; 0.85 = mostly-flat floor
# with occasional rises (plains).

@export_range(0.0, 10.0, 0.1) var terrace_band_m: float = 0.0
# Mesa-strata quantization. 0 = off. Otherwise elevation is snapped into
# horizontal bands this many metres tall, with a rounded lip between bands
# (the desert's layered-rock look). The lip uses smoothstep so the step
# isn't a razor edge.

@export_range(0.0, 1.0, 0.01) var terrace_sharpness: float = 0.5
# How hard the terrace step is. 0 = no terracing even if terrace_band_m is
# set (fully smooth); 1 = full snap to the band (crisp strata). Lerps the
# raw elevation toward the stepped value by this fraction.

@export_range(0.0, 10.0, 0.1) var mid_amplitude_m: float = 1.7
# Amplitude (m) of the MID-frequency detail layer (sampled at 3× the macro
# frequency). Adds the medium bumps that keep slopes from looking like
# smooth ramps.

@export_range(0.0, 5.0, 0.05) var detail_amplitude_m: float = 0.3
# Amplitude (m) of the FINE detail layer (12× macro frequency). The small
# surface roughness right under the player's feet.

@export var detail_slope_only: bool = false
# When true, the fine detail layer is SUPPRESSED on near-flat ground (only
# emitted where the macro field is visibly sloped). Keeps plains floors
# clean + readable instead of stippled with noise.


# =============================================================
# SURFACE — what the ground is made of on top
# =============================================================

@export_group("Surface")

@export_range(0, 254, 1) var top_material_id: int = 3
# The material id of the TOP voxel on flat/gentle ground. 3 = grass,
# 4 = sand, 13 = snow, 1 = stone. (See VoxelMaterial .tres ids.)

@export_range(0, 254, 1) var slope_material_id: int = 1
# The material on steep faces (when the column reads as a cliff/canyon
# wall). 1 = stone — desert canyon walls + mountain faces use this so steep
# ground reads as rock even where the flat top is sand.

@export_range(0.0, 5.0, 0.05) var slope_threshold: float = 1.2
# Rise/run that counts as "slope" for the slope_material override. Lower =
# more columns read as slope (desert canyons want a low threshold so walls
# go rocky readily). Carried through to the generator's cliff rule.

@export_range(0, 254, 1) var patch_material_id: int = 0
# Optional scattered surface patch material (gravel in plains, dirt
# leaf-litter in forest). 0 = no patches.

@export_range(0.001, 1.0, 0.001) var patch_frequency_per_m: float = 0.08
# Blob size of the patches, in cycles per metre. Lower = bigger blobs.

@export_range(0.0, 1.0, 0.01) var patch_threshold: float = 0.0
# Fraction of columns that get a patch (0 = patches off). 0.12 ≈ scattered
# gravel; 0.25 ≈ heavy leaf litter.

@export_range(0.0, 1.0, 0.01) var micro_relief_chance: float = 0.0
# Pebble-scatter density bias for this biome (feeds the D1 surface-detail
# pass). 0 = use the generator's global default (~1.5%). Higher = strewn
# with pebbles (rocky_desert floors).


# =============================================================
# VEGETATION — grass, flowers, trees
# =============================================================

@export_group("Vegetation")

@export_range(0.0, 1.0, 0.01) var grass_density: float = 0.35
# Fraction of grass-topped columns that grow a grass blade (R4 flora). The
# C++ scatter reads THIS per-biome instead of its old global 0.35 constant.
# 0.7 = lush plains; 0.1 = sparse forest-shade grass; 0 = none (desert).

@export_range(0.0, 0.5, 0.005) var flower_density: float = 0.02
# Fraction of grass-topped columns that grow a flower (red/blue split 50/50
# downstream). Sits at the bottom of the flora roll band.

@export var tree_table: Array = []
# DATA-ONLY tree spec for a future trees PR to consume. Each entry is a
# Dictionary describing a tree type + weight (e.g. {"kind":"oak",
# "weight":1.0}). Carried through the pipeline now so biomes can be authored
# with their forests; nothing reads it yet.


# =============================================================
# IDENTITY
# =============================================================

@export_group("Identity")

@export var biome_name: String = ""
# Stable name — "flat_plains", "mountains". Shown in the F-key biome debug
# readout and used by the bootstrap to bind this profile to its Whittaker
# kind.

@export var debug_color: Color = Color.MAGENTA
# Flat colour for debug overlays / minimaps. Not used in normal rendering.


# Flatten this profile into the plain Dictionary the C++ BiomeField parses
# (worker-thread-safe POD, mirrors VoxelMaterial → ore/disk dict). Keys
# match BiomeProfilePOD field names in biome_field.h EXACTLY. tree_table +
# biome_name + debug_color are NOT forwarded (not needed in the hot loop).
func to_pod_dict() -> Dictionary:
	return {
		"base_amplitude_m": base_amplitude_m,
		"base_frequency_per_m": base_frequency_per_m,
		"ridge_mix": ridge_mix,
		"flatness": flatness,
		"terrace_band_m": terrace_band_m,
		"terrace_sharpness": terrace_sharpness,
		"mid_amplitude_m": mid_amplitude_m,
		"detail_amplitude_m": detail_amplitude_m,
		"detail_slope_only": detail_slope_only,
		"top_material_id": top_material_id,
		"slope_material_id": slope_material_id,
		"slope_threshold": slope_threshold,
		"patch_material_id": patch_material_id,
		"patch_frequency_per_m": patch_frequency_per_m,
		"patch_threshold": patch_threshold,
		"micro_relief_chance": micro_relief_chance,
		"grass_density": grass_density,
		"flower_density": flower_density,
	}
