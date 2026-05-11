@tool
extends VoxelGeneratorScript
class_name CubicHeightmapGenerator

# CubicHeightmapGenerator — fills CHANNEL_TYPE so VoxelMesherBlocky
# can render the world with per-face textures from a VoxelBlockyLibrary.
#
# What this does in plain English:
#
#   For every voxel block the engine asks us to fill, we walk a 2D
#   grid (X, Z) at the block's world position, sample 2D noise to get
#   a ground height, then for every Y in the block:
#       - if Y <= ground_height → write a material_id integer into
#         CHANNEL_TYPE (visible solid block, looked up in the library)
#       - if Y >  ground_height → leave default 0 (air, no block emitted)
#
#   Material selection by depth: top voxel is grass (or sand below the
#   beach line), then a dirt band, then stone, with the bedrock layer
#   exactly at WORLD_FLOOR_VOXEL_Y. The mesher reads the integer per
#   voxel and emits the model from the VoxelBlockyLibrary at that index.
#
# Why CHANNEL_TYPE and not CHANNEL_COLOR?
#
#   VoxelMesherBlocky is a library-driven mesher: each integer in
#   CHANNEL_TYPE maps to a model entry (cube, custom mesh, etc.) with
#   per-face texture atlas tile coordinates. CHANNEL_COLOR is unused
#   for terrain after the v13 migration.
#
#   Pre-v13 (CubicMesher era) the generator wrote packed RGBA into
#   CHANNEL_COLOR with the alpha byte carrying material_id. That
#   encoding is gone — the integer in CHANNEL_TYPE IS the material_id.
#
# Coordinates:
#
#   - origin_in_voxels and the inner X/Y/Z indices are in voxel-grid
#     space (1 voxel = 1 grid unit). The VoxelLodTerrain node's
#     transform scale (locked at 0.166667 = 1/6) maps voxel-grid coords →
#     world-space metres at render time. This script does NOT need
#     to know about world scale.
#   - LOD: at LOD 0 we sample one grid unit per voxel. At higher
#     LODs each voxel covers (1 << lod) grid units, so we step the
#     noise by that stride.

# =============================================================
# PRESETS — quick-apply tuning bundles for live iteration
# =============================================================
#
# Iteration loop with the designer:
#   1. Run World3D.tscn (F5)
#   2. In the running scene tree, find VoxelLodTerrain → generator
#   3. Pick a preset from the dropdown to A/B between bundled looks,
#      OR drag the @export_range sliders below to fine-tune one
#      parameter at a time
#   4. Walk around → terrain chunks not yet streamed will use new
#      params; force a refresh by walking far enough to unload then
#      back in
#   5. When a setting feels right, tell Claude the values and we'll
#      bake them into a named preset
#
# Add new presets to the PRESETS dict; the enum + dropdown updates
# automatically.

enum Preset {
	CUSTOM,
	MOUNTAIN_VALLEY,
	LAY_OF_THE_LAND,
	MINECRAFT_BLOCKY,
	SMOOTH_GRADIENT,
}

# All voxel-amplitude values are in the project's locked 6 vox/m grid.
# Physical metre conversion: voxels / 6 = metres.
const PRESETS: Dictionary = {
	Preset.MOUNTAIN_VALLEY: {
		"height_range_voxels": 900.0,           # 150 m peak-to-trough — real mountains
		"height_offset_voxels": 60,             # +10 m bias above sea level
		"mid_amplitude_voxels": 10,             # ±1.7 m gentle undulation (was 24, too rocky)
		"mid_frequency_multiplier": 3.0,        # wider mid features for smoother slopes
		"detail_amplitude_voxels": 2,           # ±0.33 m surface grain (was 6, too noisy)
		"detail_frequency_multiplier": 12.0,    # smoother detail
		"color_jitter": 0.10,                   # cleaner colour, less per-cube noise
		"quantize_to_meters": false,
	},
	Preset.LAY_OF_THE_LAND: {
		"color_jitter": 0.25,
		"mid_amplitude_voxels": 12,             # ±2 m
		"mid_frequency_multiplier": 8.0,
		"detail_amplitude_voxels": 3,           # ±0.5 m
		"detail_frequency_multiplier": 30.0,
		"quantize_to_meters": false,
	},
	Preset.MINECRAFT_BLOCKY: {
		"color_jitter": 0.05,
		"mid_amplitude_voxels": 0,
		"detail_amplitude_voxels": 0,
		"quantize_to_meters": true,
	},
	Preset.SMOOTH_GRADIENT: {
		"color_jitter": 0.05,
		"mid_amplitude_voxels": 3,              # ±0.5 m
		"mid_frequency_multiplier": 6.0,
		"detail_amplitude_voxels": 0,
		"quantize_to_meters": false,
	},
}

# Re-entrancy guard so applying a preset's params doesn't recursively
# trigger the preset setter while it's writing them. Without it,
# selecting a preset would fight itself as each `set(key, ...)` call
# re-invoked the preset setter.
var _applying_preset: bool = false

## Quick-apply tuning bundle for the rest of the parameters below.
## Selecting any value other than CUSTOM batch-writes that bundle's
## values into the other sliders, then snaps back to CUSTOM so the
## dropdown signals "you're now in custom-tuned territory."
@export var preset: Preset = Preset.CUSTOM:
	set(value):
		preset = value
		if _applying_preset:
			return
		if value != Preset.CUSTOM and PRESETS.has(value):
			_applying_preset = true
			for key in PRESETS[value]:
				set(key, PRESETS[value][key])
			# Reset to CUSTOM after applying so the dropdown shows
			# "you're now in custom-tuned mode" rather than implying
			# the params still match the preset (which they may not
			# after subsequent manual tweaks).
			preset = Preset.CUSTOM
			_applying_preset = false


# =============================================================
# CORE PARAMETERS — tunable in the Inspector while the scene runs
# =============================================================

## FastNoiseLite resource that drives all three height layers (macro,
## mid, detail) at different frequency multiples. Tweak this resource's
## own properties (Type, Octaves, Frequency, Lacunarity) to change the
## underlying terrain character — ridged vs simplex, fewer/more octaves,
## etc. Lower frequency = bigger horizontal features.
@export var noise: FastNoiseLite

## Total vertical relief from the macro noise layer, in VOXELS
## (6 voxels = 1 m). Bigger = taller mountains. Default 900 = ±75 m
## macro relief = 150 m peak-to-trough. With wide noise frequency
## (set on the FastNoiseLite resource), the slope between peak and
## valley spans hundreds of metres horizontally — slow, gradual
## elevation changes rather than sharp climbs.
@export_range(0.0, 2000.0, 1.0) var height_range_voxels: float = 900.0

## Vertical shift applied to every column AFTER the noise. Positive
## pushes terrain UP (above sea level); negative pushes DOWN. Default
## +60 voxels (+10 m) keeps the average ground above the ocean
## (surface_y=8 m) while letting low ground dip below for valley
## lakes and rivers.
@export_range(-300, 400, 1) var height_offset_voxels: int = 60

## When ON, terrain heights snap to integer-metre (6-voxel) steps —
## Minecraft-style terraces with hard 1 m cliffs. When OFF (default),
## noise stays continuous and slopes are stair-stepped voxel-by-voxel.
@export var quantize_to_meters: bool = false

## Mid-scale layer amplitude in voxels (6 vox = 1 m). Default 10
## = ±1.7 m gentle undulation on the macro silhouette. Push higher
## (24+) for a rockier, broken-rock-face surface; lower (3-4) for
## clean grass/snow slopes. Set 0 for pure macro slopes.
@export_range(0, 96, 1) var mid_amplitude_voxels: int = 10

## How tight the mid-scale features are, as a multiple of macro
## noise frequency. Higher = tighter wavy ground (lots of small humps);
## lower = wider rolling features. Default 3.0 = wide rolling humps
## that don't fight the slow macro slopes.
@export_range(1.0, 20.0, 0.5) var mid_frequency_multiplier: float = 3.0

## Cube-by-cube surface grain amplitude in voxels. Default 2 = ±0.33 m
## subtle wobble. Adds just enough texture so flat tops aren't dead-flat.
## Set to 0 for fully clean slopes; push higher (5-8) for visible grit.
@export_range(0, 24, 1) var detail_amplitude_voxels: int = 2

## How fast the cube-by-cube grain varies, as a multiple of macro
## noise frequency. Higher = each adjacent cube very different from
## its neighbour (gritty); lower = grain blends smoothly across cubes.
## Default 12× = grain visible but smooth across multiple cubes.
@export_range(1.0, 80.0, 0.5) var detail_frequency_multiplier: float = 12.0

## Per-voxel brightness variation as ± fraction of base colour. 0.10
## = ±10 % brightness — clean look that lets the macro silhouette
## breathe. Push to 0.20+ for stronger Lay-of-the-Land contrast; drop
## to 0.05 for uniform colour per height.
@export_range(0.0, 0.5, 0.01) var color_jitter: float = 0.10

## Reference voxel-Y for "ocean surface" — also used as the upper bound
## for generator water emission. Every column whose ground_y is below
## this value gets water voxels written into CHANNEL_DATA from
## ground_y+1 up through SEA_LEVEL_VOXELS. Columns above it stay dry.
##
## 72 voxels = world Y 12 m at 6 vox/m. The terrain noise centerline
## sits at height_offset_voxels=60 (world Y=10), so a sea level of 72
## puts ~60% of columns underwater and 40% above — clearly visible
## ocean basins between landmasses, instead of the 50/50 split that
## sea level=60 produced.
const SEA_LEVEL_VOXELS: int = 72

## Colour of the LOWEST ground voxels (deep valleys, beach floor).
## LEGACY — used only as a fallback when the VoxelMaterialRegistry
## autoload isn't available (e.g. running this script in isolation
## for a unit test). In normal play, per-material colours come from
## the .tres files in `assets/voxels/materials/`.
@export var color_low: Color = Color(0.30, 0.42, 0.18)

## Colour of the HIGHEST ground voxels (ridge peaks). LEGACY — see
## `color_low` above. The active per-material colour pipeline lives
## in the .tres files; designers tune those, not these sliders.
@export var color_high: Color = Color(0.62, 0.55, 0.42)

## DEBUG — when true, emit vivid per-material colours in place of
## the .tres palette. Stone = bright red, dirt = bright orange,
## grass = bright green, sand = bright yellow. Lets us prove that
## (a) the vertex-color channel is reaching the screen, and
## (b) material selection is actually picking different materials
## by depth/altitude. If you flip this on and STILL see flat grey
## terrain, the problem is downstream of the generator (mesher
## config or terrain material) — not the colour pipeline.
@export var debug_vivid_colors: bool = false


# =============================================================
# MATERIAL BANDS — which material lives at which depth
# =============================================================
#
# The world is split into vertical bands measured DOWN from each
# column's ground_y. The top voxel is grass (or sand at coastlines),
# the next few voxels are dirt, and everything below is stone.
# Designers can re-tune these without touching code.

## Number of voxels at the very top of each ground column that are
## grass (the green skin). Default 1 — a single voxel of green over
## the dirt. Set to 0 to remove grass entirely (e.g. a desert preset).
@export_range(0, 5, 1) var grass_layer_thickness_voxels: int = 1

## Voxels of dirt directly below the grass layer. Default 3
## (~50 cm of soil before stone). The chunkier the world, the
## thicker this layer should feel relative to the player.
@export_range(0, 12, 1) var dirt_layer_thickness_voxels: int = 3

## At or below this voxel-Y, the top layer of the column is sand
## instead of grass. Sits just above SEA_LEVEL_VOXELS so a thin sand
## strip forms at the natural coastline (where columns whose ground_y
## is between sea level and this threshold show as exposed beach
## above the waterline).
##
## 74 voxels = world Y 12.33 m, two voxels above SEA_LEVEL_VOXELS=72.
## Earlier value of 7 was stale (carried over from the pre-refactor
## OceanVolume at Y=8 in legacy voxel coords) and put sand entirely
## below the new waterline — beaches were never visible.
@export var beach_y_threshold: int = 74


# =============================================================
# TIER 1 — slope-driven cliff rule
# =============================================================
#
# Sample neighbour columns at `cliff_slope_sample_distance_voxels`
# away in ±X and ±Z, measure the largest Y drop, and if it crosses
# `cliff_slope_threshold_voxels`, override the column's top voxels
# to bare stone. Slope math at 6 vox/m, sample_distance=6:
#   threshold = ceil(tan(angle) × 6)
#   45°→6, 50°→8, 55°→9, 60°→11, 65°→13, 70°→17, 75°→23
# Default 10 ≈ 59° slope.

@export_range(0, 30, 1) var cliff_slope_sample_distance_voxels: int = 6
@export_range(0, 50, 1) var cliff_slope_threshold_voxels: int = 10
@export_range(-1, 3, 1) var cliff_rule_max_lod: int = 2


# =============================================================
# TIER 3 — marble + stone_dark jitter on stone
# =============================================================
# Per stone-band voxel, sample a deterministic 3D hash. Above
# `marble_rare_threshold` → marble; above `marble_dark_threshold`
# but below the rare cut → stone_dark; otherwise plain stone.
# Coords are integer-divided by `marble_jitter_block_size` so the
# patches read as ~4-voxel chunks rather than per-voxel speckle.

@export_range(1, 16, 1) var marble_jitter_block_size: int = 4
@export_range(0, 99999, 1) var marble_jitter_seed: int = 1
@export_range(0.0, 1.0, 0.01) var marble_rare_threshold: float = 0.92
@export_range(0.0, 1.0, 0.01) var marble_dark_threshold: float = 0.75


# =============================================================
# TIER 2 — altitude-driven snow line
# =============================================================
# Default 30000 = effectively disabled on the procedural Mira map
# (max ground_y at the default noise settings is ~520 voxels). The
# Copper Isles heightmap generator uses 12000 by default to catch
# the peak band. Override in the Inspector for any world that has
# real altitude.

@export_range(0, 30000, 1) var snow_line_voxels: int = 30000
@export_range(0, 200, 1) var snow_line_jitter_voxels: int = 30
@export_range(1, 64, 1) var snow_line_jitter_block_size: int = 8
@export_range(0, 99999, 1) var snow_line_seed: int = 2


# =============================================================
# TIER 5 — clay / gravel disks near water
# =============================================================
@export_range(8, 96, 1) var disk_anchor_grid_voxels: int = 24
@export_range(-1, 3, 1) var disk_rule_max_lod: int = 1


# =============================================================
# RUNTIME CACHE — material references, looked up once
# =============================================================
#
# `_generate_block` runs on Zylann's worker threads, so we don't
# want to do a registry lookup per voxel (or even per chunk). We
# fetch the four pilot materials lazily on first call and cache
# the references. Writes to these member vars are idempotent
# (same VoxelMaterial reference every time) so race conditions
# between worker threads doing the same lookup are harmless.

var _cached_stone: VoxelMaterial = null
var _cached_dirt: VoxelMaterial = null
var _cached_grass: VoxelMaterial = null
var _cached_sand: VoxelMaterial = null
var _cached_bedrock: VoxelMaterial = null
var _cached_marble: VoxelMaterial = null
var _cached_stone_dark: VoxelMaterial = null
var _cached_snow: VoxelMaterial = null
var _materials_lookup_attempted: bool = false
var _depth_logged: bool = false
var _first_water_byte_logged: bool = false
# Diagnostic — set true the first time the generator successfully
# writes a water byte to CHANNEL_DATA5 in any chunk. The print fires
# once and tells you (a) the generator IS being called for at least
# one below-sea-level column, and (b) the column's water bytes are
# in the buffer. If you never see this print, generation is the
# bottleneck — investigate the channel-depth log line above and the
# generator's emit_water_here gate.


# =============================================================
# NO-EDIT-ZONE WATER-GENERATION SUPPRESSION
# =============================================================
#
# A snapshot of world-space AABBs of every NoEditZone whose
# blocks_water_generation flag is true. Populated ONCE on the main
# thread by World3DBootstrap (via set_no_edit_water_aabbs) before
# the terrain begins streaming chunks.
#
# Worker threads then read this Array directly during _generate_block
# — pure data, no SceneTree access, race-safe across threads. The
# Array reference itself is set once on the main thread; readers see
# either the empty default or the populated snapshot, never a
# half-built state.
#
# Runtime-streamed NoEditZones are intentionally NOT picked up here.
# See NoEditZoneRegistry.get_water_blocking_aabbs_snapshot for the
# constraint and rationale.
var _no_edit_water_aabbs: Array[AABB] = []


func set_no_edit_water_aabbs(aabbs: Array[AABB]) -> void:
	# Called by World3DBootstrap on the main thread after the snapshot
	# is captured. Safe to call again at world reload.
	_no_edit_water_aabbs = aabbs


# Tier 4: receives the pre-filtered ore list from
# VoxelMaterialRegistry.get_ore_materials(). Bootstrap pushes on the
# main thread; worker threads iterate the local Array reference.
var _cached_ore_list: Array[VoxelMaterial] = []

func set_ore_materials(list: Array[VoxelMaterial]) -> void:
	_cached_ore_list = list


# Tier 5: see CopperIslesHeightmapGenerator for the long-form rationale.
var _cached_disk_list: Array[VoxelMaterial] = []

func set_disk_materials(list: Array[VoxelMaterial]) -> void:
	_cached_disk_list = list


func _disk_at_column(world_x: int, world_z: int, ground_y: int, sea_level_v: int) -> VoxelMaterial:
	if _cached_disk_list.is_empty():
		return null
	var max_reach: int = 0
	for d in _cached_disk_list:
		if d.disk_max_distance_to_water_voxels > max_reach:
			max_reach = d.disk_max_distance_to_water_voxels
	if absi(ground_y - sea_level_v) > max_reach:
		return null
	var grid: int = maxi(1, disk_anchor_grid_voxels)
	for disk in _cached_disk_list:
		if absi(ground_y - sea_level_v) > disk.disk_max_distance_to_water_voxels:
			continue
		var r: int = disk.disk_radius_voxels
		if r <= 0:
			continue
		var ax_min: int = floori(float(world_x - r) / float(grid))
		var ax_max: int = floori(float(world_x + r) / float(grid))
		var az_min: int = floori(float(world_z - r) / float(grid))
		var az_max: int = floori(float(world_z + r) / float(grid))
		var density_seed: int = disk.material_id * 7919
		var jitter_seed: int = disk.material_id
		for ax in range(ax_min, ax_max + 1):
			for az in range(az_min, az_max + 1):
				var density_hash: float = VoxelGenerationMath.hash3(ax, 0, az, density_seed)
				if density_hash > disk.disk_anchor_density:
					continue
				var jx: float = VoxelGenerationMath.hash3(ax, 1, az, jitter_seed) - 0.5
				var jz: float = VoxelGenerationMath.hash3(ax, 2, az, jitter_seed) - 0.5
				var anchor_x: int = ax * grid + int(jx * float(grid))
				var anchor_z: int = az * grid + int(jz * float(grid))
				var dx: int = world_x - anchor_x
				var dz: int = world_z - anchor_z
				if dx * dx + dz * dz <= r * r:
					return disk
	return null


func _column_blocks_water_generation(world_x: float, world_z: float) -> bool:
	# Worker-thread-safe AABB membership test. Walks the cached
	# snapshot — pure math, no physics, no SceneTree.
	# The Y axis is intentionally ignored: a NoEditZone defined as a
	# Box around a settlement at sea level should suppress water for
	# the whole column underneath it (otherwise water below the zone's
	# Y would still flood). Use a Y range later if a use case appears.
	if _no_edit_water_aabbs.is_empty():
		return false
	for aabb in _no_edit_water_aabbs:
		var min_x: float = aabb.position.x
		var min_z: float = aabb.position.z
		var max_x: float = min_x + aabb.size.x
		var max_z: float = min_z + aabb.size.z
		if world_x >= min_x and world_x <= max_x \
				and world_z >= min_z and world_z <= max_z:
			return true
	return false


# =============================================================
# WORLD FLOOR — bedrock layer at the bottom of the world
# =============================================================

## Y coordinate (in voxel units, 6 vox/m) of the bedrock floor. The
## generator writes one solid layer of bedrock material at this Y.
## VoxelEditManager rejects any player edit that would touch or
## go below this Y, so the bedrock is unbreakable.
##
## Default -300 voxels = -50 m. With min natural terrain bottom at
## ~-7 m (height_offset_voxels=60, half_range=100, so min_ground_y =
## -100 + 60 = -40 vox = -6.67 m), the player has ~43 m of underground
## exploration before hitting bedrock. Below the bedrock layer is
## empty space (no voxels), so digging straight down stops cleanly.
##
## CRITICAL: keep this in sync with `VoxelEditManager.WORLD_FLOOR_VOXEL_Y`
## — they must be the same value or the player will hit invisible
## edit-rejection above the visible bedrock layer (or vice versa).
const WORLD_FLOOR_VOXEL_Y: int = -300


# =============================================================
# PERF INSTRUMENTATION (worker-thread safe; toggleable)
# =============================================================

@export var perf_log_enabled: bool = false
# When true, log per-block generation time. Look for "[PERF GEN]" in
# the Output panel. Filter is in microseconds — see perf_log_min_us.
# OFF by default — the periodic 100-block summary line happens
# during chunk streaming, which is exactly when the player is
# walking around (so the print itself contributes to the perceived
# stutter). Flip on for diagnostics, then back off.

@export var perf_log_min_us: int = 5000
# Only log blocks slower than this many microseconds (default 5 ms).
# Filters out the trivial "fully above terrain" / "deep underground"
# early-out cases so the log shows only blocks that actually did
# per-voxel work.

@export var perf_log_per_block: bool = false
# When true, emit one [PERF GEN] line per slow block. Default OFF —
# during world streaming this fires for nearly every block and
# completely floods the Output panel (10k+ lines), drowning out
# everything else. Only flip on when actively diagnosing slow
# individual blocks. The aggregate summary every 100 blocks is
# always on and tells you the same story (avg, max) without the
# spam.

# Counters for the periodic summary line. These are written from
# worker threads — concurrent writes are slightly racy (one thread
# may stomp another's increment), but the summary is just a
# visibility tool and a few missed counts don't change the
# diagnosis. If we ever need exact totals, switch to a Mutex.
var _perf_blocks_generated: int = 0
var _perf_total_us: int = 0
var _perf_max_us: int = 0
var _perf_summary_at_blocks: int = 100
# Print a summary line every N completed blocks.

# Per-LOD counters. Index 0 = LOD0, etc. Up to 8 LOD levels (matches
# our lod_count cap). Tells us whether worker threads are spending
# their time on near LOD0 blocks (good — that's what the player sees
# refining) vs distant LOD2+ blocks (suspicious if LOD0 is starving).
var _perf_blocks_by_lod: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
var _perf_us_by_lod: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
# Per-exit-path counters. "above" / "deep" / "flat" / "full".
# A high "full" share is normal for the active band of terrain;
# many "above" or "deep" early-outs are normal for chunks above
# the sky or deep underground. If the totals don't match
# _perf_blocks_generated something is wrong.
var _perf_count_above: int = 0
var _perf_count_deep: int = 0
var _perf_count_flat: int = 0
var _perf_count_full: int = 0

# Mutex for the perf summary block — without this, multiple worker
# threads finishing _generate_block at nearly the same time all see
# `_perf_blocks_generated >= threshold`, all print the summary, and
# all reset the counters. Result: 2-3 duplicate summary lines per
# 100-block window in the Output panel. The Mutex serialises just
# the threshold-check + print + reset, so exactly one thread emits
# each summary. The per-block counter increments outside the Mutex
# stay racy (occasional missed +1) but that's diagnostic noise, not
# a correctness issue.
var _perf_summary_mutex: Mutex = Mutex.new()


func _get_used_channels_mask() -> int:
	# CRITICAL — without this override, Zylann assumes the generator
	# writes only the default (SDF) channel and never allocates
	# CHANNEL_TYPE in the chunk buffer. The mesher then tries to
	# read an unallocated channel and throws "Central buffer must be
	# valid" — thousands of times, once per streamed chunk.
	#
	# Returning a bitmask of channels we write tells the engine which
	# channels to set up before calling _generate_block.
	#
	# CHANNEL_DATA5 is declared because the Minecraft-style water
	# rewrite stores per-voxel water bytes there. VoxelMesherBlocky
	# ignores any channel other than TYPE, so terrain rendering is
	# unaffected — water voxels are invisible to the blocky mesher and
	# get their own transparent surfaces from WaterChunkMesher.
	return (1 << VoxelBuffer.CHANNEL_TYPE) | (1 << VoxelBuffer.CHANNEL_DATA5)


# Public: sample the ground voxel-Y at an arbitrary world XZ. Reuses
# the exact macro+mid+detail noise sum the per-column block uses, so
# slope-rule neighbour samples land on the same surface the generator
# would emit at that XZ. Worker-thread-safe (pure FastNoiseLite reads).
func _ground_y_at(world_x: int, world_z: int) -> int:
	if noise == null:
		return height_offset_voxels   # flat-fallback case
	var half_range: float = height_range_voxels * 0.5
	var n_macro: float = noise.get_noise_2d(float(world_x), float(world_z))
	var macro_y: int
	if quantize_to_meters:
		var macro_meters: int = roundi(n_macro * half_range / 8.0)
		macro_y = macro_meters * 8
	else:
		macro_y = int(n_macro * half_range)
	var n_mid: float = noise.get_noise_2d(
		float(world_x) * mid_frequency_multiplier,
		float(world_z) * mid_frequency_multiplier,
	)
	var mid_y: int = int(n_mid * float(mid_amplitude_voxels))
	var n_detail: float = noise.get_noise_2d(
		float(world_x) * detail_frequency_multiplier,
		float(world_z) * detail_frequency_multiplier,
	)
	var detail_y: int = int(n_detail * float(detail_amplitude_voxels))
	return macro_y + mid_y + detail_y + height_offset_voxels


# Tier 1 helper. True when the column at (world_x, world_z) has a
# ≥ cliff_slope_threshold_voxels drop to any of its 4-neighbour
# columns at ± cliff_slope_sample_distance_voxels away.
func _column_is_cliff(world_x: int, world_z: int, this_ground_y: int) -> bool:
	var step: int = cliff_slope_sample_distance_voxels
	if step <= 0 or cliff_slope_threshold_voxels <= 0:
		return false
	var max_drop: int = 0
	max_drop = maxi(max_drop, this_ground_y - _ground_y_at(world_x - step, world_z))
	max_drop = maxi(max_drop, this_ground_y - _ground_y_at(world_x + step, world_z))
	max_drop = maxi(max_drop, this_ground_y - _ground_y_at(world_x, world_z - step))
	max_drop = maxi(max_drop, this_ground_y - _ground_y_at(world_x, world_z + step))
	return max_drop >= cliff_slope_threshold_voxels


func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	# Engine calls this for every chunk the player approaches. We
	# fill out_buffer with TYPE values (material_id integers) for
	# that chunk.
	#
	# DO NOT call out_buffer.set_channel_depth() here — confirmed
	# 2026-05-05: even calling on a fresh buffer before any writes
	# produces empty chunks (terrain disappears, player falls
	# forever). The depth must be set globally on the terrain via
	# the VoxelLodTerrain.format property — see World3DBootstrap.

	# Perf timer — wraps the whole function. The deferred-print at the
	# bottom decides whether to emit a log line based on perf_log_min_us.
	var t_start: int = 0
	if perf_log_enabled:
		t_start = Time.get_ticks_usec()

	# DIAGNOSTIC: log the channel depth on the first block so we can
	# confirm what the engine has allocated. Read-only — does NOT mutate.
	if not _depth_logged:
		_depth_logged = true
		var dep_now: int = out_buffer.get_channel_depth(VoxelBuffer.CHANNEL_TYPE)
		var dep_data: int = out_buffer.get_channel_depth(VoxelBuffer.CHANNEL_DATA5)
		print("[Generator] CHANNEL_TYPE depth: %d  CHANNEL_DATA5 depth: %d  (DEPTH_8_BIT=%d, DEPTH_16_BIT=%d, DEPTH_32_BIT=%d, DEPTH_64_BIT=%d)" % [
			dep_now,
			dep_data,
			VoxelBuffer.DEPTH_8_BIT,
			VoxelBuffer.DEPTH_16_BIT,
			VoxelBuffer.DEPTH_32_BIT,
			VoxelBuffer.DEPTH_64_BIT,
		])

	var size: Vector3i = out_buffer.get_size()
	var stride: int = 1 << lod  # 1 at LOD0, 2 at LOD1, etc.

	# Bound the heightmap range so we can skip blocks fully above or
	# fully below terrain without per-voxel work. Includes the bias
	# offset, the mid layer amplitude, and the detail amplitude so
	# the early-out test stays correct after all three layers stack.
	var extra_amplitude: int = mid_amplitude_voxels + detail_amplitude_voxels
	var max_ground_y: int = int(height_range_voxels * 0.5) + height_offset_voxels + extra_amplitude + 1
	var min_ground_y: int = -int(height_range_voxels * 0.5) + height_offset_voxels - extra_amplitude - 1
	var block_min_y: int = origin_in_voxels.y
	var block_max_y: int = origin_in_voxels.y + (size.y * stride) - 1

	if block_min_y > max_ground_y and block_min_y > SEA_LEVEL_VOXELS:
		# Entire block is above terrain AND above sea level — leave as
		# air (default 0). The sea-level check matters for blocks that
		# float above terrain in a deep ocean basin: terrain ground_y
		# may be below the block, but water (which exists from ground_y+1
		# up to SEA_LEVEL_VOXELS) might still occupy the block. Skip the
		# early-out unless BOTH terrain and water are absent.
		_perf_record_block_done(t_start, lod, "above")
		return

	# Materials registered? (Lazy lookup; safe across worker threads
	# because writes are idempotent — every thread fetches the same
	# VoxelMaterial references.)
	_ensure_materials_cached()

	# Below-the-world floor: the entire block is below the bedrock layer.
	# Leave as default (air). The player can never dig down here because
	# bedrock blocks them above.
	if block_max_y < WORLD_FLOOR_VOXEL_Y:
		_perf_record_block_done(t_start, lod, "below_floor")
		return

	if block_max_y < min_ground_y:
		# Entire block is buried deep below terrain. Three sub-cases
		# based on where the block sits relative to the world floor:
		#   - fully above floor → all stone (existing fast path)
		#   - straddles the floor → bedrock at the floor row, stone above,
		#     air below (per-voxel write)
		#   - fully below floor → already returned above
		var stone_packed: int = _pack_for_material(_cached_stone, Color.WHITE)
		if block_min_y > WORLD_FLOOR_VOXEL_Y:
			out_buffer.fill(stone_packed, VoxelBuffer.CHANNEL_TYPE)
		else:
			# Straddles the floor — per-voxel fill.
			var bedrock_packed: int = stone_packed
			if _cached_bedrock != null:
				bedrock_packed = _pack_for_material(_cached_bedrock, Color.WHITE)
			for y_s in size.y:
				var world_y_s: int = origin_in_voxels.y + y_s * stride
				var fill_packed: int = 0
				if world_y_s == WORLD_FLOOR_VOXEL_Y:
					fill_packed = bedrock_packed
				elif world_y_s > WORLD_FLOOR_VOXEL_Y:
					fill_packed = stone_packed
				else:
					continue  # air below floor
				for x_s in size.x:
					for z_s in size.z:
						out_buffer.set_voxel(fill_packed, x_s, y_s, z_s, VoxelBuffer.CHANNEL_TYPE)
		_perf_record_block_done(t_start, lod, "deep")
		return

	if noise == null:
		# Fall back to flat ground at Y=0 with a default color. Useful
		# for sanity-checking the channel wiring without noise.
		_fill_flat(out_buffer, origin_in_voxels, stride)
		_perf_record_block_done(t_start, lod, "flat")
		return

	# --- Pre-extract per-material tuples (HOT-LOOP OPTIMISATION) ---
	# The y-loop below runs up to 4096 times per block. Originally each
	# voxel called _select_material_for_depth() + _compute_voxel_color()
	# + _pack_for_material() — 4 GDScript function calls per voxel,
	# ~16k calls per block. With many blocks streaming, that
	# function-call overhead alone became the LOD bottleneck.
	#
	# Now we read each material's properties ONCE per block into local
	# variables, then the y-loop just reads locals + does inline math.
	# Same output, ~3-5× less GDScript overhead.
	#
	# Layout: one tuple of (color_low, color_high, mat_id) per band —
	# top (grass), top_low (sand for beaches), dirt, stone. Fallback:
	# if a material is null, fall back to dirt then stone (matching
	# the pre-optimisation _select_material_for_depth chain).
	# (`color_jitter` no longer read — jitter was removed.)
	var dirt_lo: Color = color_low
	var dirt_hi: Color = color_high
	var dirt_id: int = 0
	if _cached_dirt != null:
		dirt_lo = _cached_dirt.color_low
		dirt_hi = _cached_dirt.color_high
		dirt_id = _cached_dirt.material_id

	var stone_lo: Color = color_low
	var stone_hi: Color = color_high
	var stone_id: int = 0
	if _cached_stone != null:
		stone_lo = _cached_stone.color_low
		stone_hi = _cached_stone.color_high
		stone_id = _cached_stone.material_id

	# Tier 3 jitter materials (0 = not loaded → fall back to plain stone).
	var marble_id: int = 0
	if _cached_marble != null:
		marble_id = _cached_marble.material_id
	var stone_dark_id: int = 0
	if _cached_stone_dark != null:
		stone_dark_id = _cached_stone_dark.material_id

	# Tier 2 snow material (0 = not loaded → snow line silently disabled).
	var snow_id: int = 0
	if _cached_snow != null:
		snow_id = _cached_snow.material_id

	var grass_lo: Color = dirt_lo
	var grass_hi: Color = dirt_hi
	var grass_id: int = dirt_id
	if _cached_grass != null:
		grass_lo = _cached_grass.color_low
		grass_hi = _cached_grass.color_high
		grass_id = _cached_grass.material_id

	var sand_lo: Color = grass_lo
	var sand_hi: Color = grass_hi
	var sand_id: int = grass_id
	if _cached_sand != null:
		sand_lo = _cached_sand.color_low
		sand_hi = _cached_sand.color_high
		sand_id = _cached_sand.material_id

	# Bedrock is written at exactly world_y == WORLD_FLOOR_VOXEL_Y.
	# Pre-pack the bedrock voxel value once per block so the floor row
	# is a single bit-op + set_voxel call, not a full pack each time.
	var bedrock_packed_v: int = 0
	if _cached_bedrock != null:
		var br_c: Color = _cached_bedrock.color_high
		var br_r: int = clampi(int(round(br_c.r * 255.0)), 0, 255)
		var br_g: int = clampi(int(round(br_c.g * 255.0)), 0, 255)
		var br_b: int = clampi(int(round(br_c.b * 255.0)), 0, 255)
		bedrock_packed_v = br_r | (br_g << 8) | (br_b << 16) \
			| ((_cached_bedrock.material_id & 0xFF) << 24)

	# Per-column thickness boundaries (read property once per block).
	# height_offset_voxels is now read inside _ground_y_at, not here.
	var grass_thick: int = grass_layer_thickness_voxels
	var dirt_band_end: int = grass_thick + dirt_layer_thickness_voxels
	var beach_y: int = beach_y_threshold
	# Reference depth (in voxels) over which the stone band lerps from
	# color_high (top, just under dirt) down to color_low (deep). 30 vox
	# = 5 m at 6 vox/m. Anything deeper than this pegs at color_low.
	# Sized to give visible vertical variation within the player's
	# typical mining range without making cliff faces look striped.
	const STONE_BAND_REF_VOXELS: float = 30.0
	# Pre-divide the dirt-band lerp denominator. dirt_layer_thickness_voxels
	# can be 0 (designer turned off the dirt band), so guard against div-zero.
	var dirt_band_size: int = dirt_band_end - grass_thick
	var dirt_band_inv_max: float = 0.0
	if dirt_band_size > 1:
		dirt_band_inv_max = 1.0 / float(dirt_band_size - 1)

	# Per-voxel colour jitter was removed entirely — was costing ~30% of
	# the per-block hot-loop time (hash + scalar + 3× clampf per voxel
	# × thousands of voxels per block) for marginal visual benefit. The
	# `color_jitter` field on VoxelMaterial.tres files is now unused;
	# leave it in the resource definition so existing .tres files don't
	# need to be edited, but the value is ignored at generation time.
	# Cliff faces will read as flat per material band — slightly more
	# uniform than before, but the LOD silhouette and material colour
	# bands carry the visual.

	# Water emission is LOD0-only. At LOD>0 the cube mesher renders
	# coarser terrain but water doesn't have a coarse equivalent —
	# averaging "ocean voxel" with stride 4 produces nothing useful.
	# Distant water is covered by the horizon plane (Phase 5) instead.
	var write_water: bool = (lod == 0)
	# Pre-pack the canonical water source byte once per block so the
	# inner loop is a single set_voxel call. SOURCE_BYTE = level 8 |
	# source bit | tick 0 — see WaterByteCodec.gd for the layout.
	var water_byte: int = WaterByteCodec.SOURCE_BYTE

	# Per-column heightmap pass. `_ground_y_at` reads the same noise
	# sum the old inline code computed; the slope-rule neighbour
	# samples need the same source-of-truth, so the math lives in
	# one place.
	# Tier 1: only run slope check at near LODs. Distant LODs already
	# blur cliff detail; per-column ×4 noise lookups would be wasted.
	var run_cliff_rule: bool = cliff_rule_max_lod >= 0 and lod <= cliff_rule_max_lod

	# Tier 3 jitter cache. Clamped to ≥1 so the integer division in the
	# hash input never crashes on a misconfigured 0.
	var jitter_block: int = maxi(1, marble_jitter_block_size)
	var jitter_seed: int = marble_jitter_seed
	var jitter_marble: float = marble_rare_threshold
	var jitter_dark: float = marble_dark_threshold

	# Tier 2 snow-line cache.
	var snow_block: int = maxi(1, snow_line_jitter_block_size)
	var snow_jitter_amp: float = float(snow_line_jitter_voxels)
	var snow_alt_voxels: int = snow_line_voxels
	var run_snow_line: bool = snow_id != 0

	# Tier 4 ore-vein cache.
	var ore_list: Array[VoxelMaterial] = _cached_ore_list
	var has_ores: bool = not ore_list.is_empty()

	# Tier 5 disk cache.
	var run_disk_rule: bool = disk_rule_max_lod >= 0 \
		and lod <= disk_rule_max_lod \
		and not _cached_disk_list.is_empty()
	var sea_level_v_local: int = SEA_LEVEL_VOXELS

	for x in size.x:
		for z in size.z:
			var world_x: int = origin_in_voxels.x + x * stride
			var world_z: int = origin_in_voxels.z + z * stride

			var ground_y: int = _ground_y_at(world_x, world_z)

			# Pick this column's TOP-band tuple (grass on grasslands,
			# sand at coastlines). Done once per column.
			var top_lo: Color = grass_lo
			var top_hi: Color = grass_hi
			var top_id: int = grass_id
			if ground_y <= beach_y:
				top_lo = sand_lo
				top_hi = sand_hi
				top_id = sand_id

			# Tier 1: cliff override — collapse top + dirt sandwich to
			# bare stone when slope exceeds the threshold.
			var col_dirt_band_end: int = dirt_band_end
			var column_is_cliff: bool = run_cliff_rule \
				and _column_is_cliff(world_x, world_z, ground_y)
			if column_is_cliff:
				top_id = stone_id
				col_dirt_band_end = grass_thick

			# Tier 2: snow line. Wins on non-cliff columns whose
			# ground_y crosses (snow_alt + jitter) — cliff faces poke
			# through snowcaps.
			if run_snow_line and not column_is_cliff and ground_y >= snow_alt_voxels:
				@warning_ignore("integer_division")
				var sj: float = (VoxelGenerationMath.hash3(
					world_x / snow_block,
					0,
					world_z / snow_block,
					snow_line_seed,
				) - 0.5) * 2.0 * snow_jitter_amp
				if float(ground_y) >= float(snow_alt_voxels) + sj:
					top_id = snow_id

			# Tier 5: per-column disk lookup.
			var disk_match: VoxelMaterial = null
			var disk_thickness: int = 0
			if run_disk_rule and not column_is_cliff:
				disk_match = _disk_at_column(world_x, world_z, ground_y, sea_level_v_local)
				if disk_match != null:
					disk_thickness = 1 + disk_match.disk_half_height_voxels * 2

			# Decide once per column whether this column emits water.
			# Three gates: LOD must be 0 (water is LOD0-only), the
			# column's ground must dip below sea level (above-water
			# columns are dry), and no NoEditZone with
			# blocks_water_generation must cover this XZ.
			var emit_water_here: bool = write_water \
					and ground_y < SEA_LEVEL_VOXELS \
					and not _column_blocks_water_generation(float(world_x), float(world_z))

			for y in size.y:
				var world_y: int = origin_in_voxels.y + y * stride
				if world_y > ground_y:
					# Air above terrain. If this air voxel sits at or
					# below sea level and the column emits water, write
					# a water source byte into CHANNEL_DATA5. The cube
					# mesher ignores DATA5, so this voxel still renders
					# as air — the water mesher (Phase 2) emits the
					# transparent surface from this byte.
					if emit_water_here and world_y <= SEA_LEVEL_VOXELS:
						out_buffer.set_voxel(water_byte, x, y, z, VoxelBuffer.CHANNEL_DATA5)
						if not _first_water_byte_logged:
							_first_water_byte_logged = true
							print("[Generator] FIRST water byte written: world_voxel=(%d, %d, %d) ground_y=%d byte=0x%02X" % [
								world_x, world_y, world_z, ground_y, water_byte,
							])
					continue
				# World floor enforcement: anything below the bedrock
				# layer is air (no voxels). The bedrock row itself
				# writes a special unmineable voxel.
				if world_y < WORLD_FLOOR_VOXEL_Y:
					continue
				if world_y == WORLD_FLOOR_VOXEL_Y and bedrock_packed_v != 0:
					out_buffer.set_voxel(bedrock_packed_v, x, y, z, VoxelBuffer.CHANNEL_TYPE)
					continue

				# Pick band based on depth from this column's ground_y.
				# col_dirt_band_end collapses to grass_thick on cliff
				# columns (Tier 1), so depth>=1 lands straight in the
				# stone band — no dirt sandwich on exposed rock faces.
				var depth: int = ground_y - world_y  # 0 = top voxel
				var lo: Color
				var hi: Color
				var mat_id: int
				if depth < grass_thick:
					lo = top_lo
					hi = top_hi
					mat_id = top_id
				elif depth < col_dirt_band_end:
					lo = dirt_lo
					hi = dirt_hi
					mat_id = dirt_id
				else:
					lo = stone_lo
					hi = stone_hi
					# Tier 3 stone-band jitter. Patches of rare marble
					# and uncommon stone_dark break up uniform stone.
					# Missing materials (id 0) fall back to plain stone.
					@warning_ignore("integer_division")
					var n: float = VoxelGenerationMath.hash3(
						world_x / jitter_block,
						world_y / jitter_block,
						world_z / jitter_block,
						jitter_seed,
					)
					if n > jitter_marble and marble_id != 0:
						mat_id = marble_id
					elif n > jitter_dark and stone_dark_id != 0:
						mat_id = stone_dark_id
					else:
						mat_id = stone_id

					# Tier 4 ore veins — first matching ore wins.
					# Ores only replace their declared parent material
					# (iron stays in plain stone, skipping marble and
					# stone_dark) for the "rare stripe through plain
					# rock" feel.
					if has_ores:
						for ore in ore_list:
							if mat_id != ore.replaces_material_id:
								continue
							if world_y < ore.min_altitude_voxels or world_y > ore.max_altitude_voxels:
								continue
							var s: float = ore.ore_noise_scale
							var on: float = VoxelGenerationMath.hash3(
								int(float(world_x) * s),
								int(float(world_y) * s),
								int(float(world_z) * s),
								ore.material_id * 1009,
							)
							if on > ore.ore_noise_threshold:
								mat_id = ore.material_id
								break

				# Tier 5: disk override on the top voxels of any
				# column inside a near-water disk anchor.
				if disk_match != null and depth < disk_thickness:
					mat_id = disk_match.material_id

				# v13: VoxelMesherBlocky reads CHANNEL_TYPE as plain
				# integers — the material_id IS the value to write.
				# No color packing, no per-voxel colour lerp. Material
				# variation comes from the texture atlas tiles in the
				# VoxelBlockyLibrary, not from per-voxel RGB.
				#
				# The lo/hi/c locals from the Cubes-era band lerp are
				# unused here — kept the band selection above so the
				# layer geometry is unchanged and so VoxelClusterBuilder
				# (which still reads color_low/high for falling-cluster
				# tinting via the registry) keeps working with the same
				# material assignments.
				_unused(lo); _unused(hi)
				out_buffer.set_voxel(mat_id, x, y, z, VoxelBuffer.CHANNEL_TYPE)
	_perf_record_block_done(t_start, lod, "full")


func _perf_record_block_done(t_start: int, lod: int, label: String) -> void:
	# Called from each exit point of _generate_block. No-op if perf
	# logging is off. Both per-block (slow blocks only) and an aggregate
	# summary line every N blocks.
	#
	# Worker-thread note: print() is safe from worker threads in Godot
	# 4 (it goes through a thread-safe ring buffer). Time.get_ticks_usec
	# is also thread-safe. The counter writes themselves can race
	# between worker threads (no atomic increment in GDScript), but
	# this is a diagnostic — slightly inaccurate counts are fine.
	if not perf_log_enabled:
		return
	var dur_us: int = Time.get_ticks_usec() - t_start
	_perf_blocks_generated += 1
	_perf_total_us += dur_us
	if dur_us > _perf_max_us:
		_perf_max_us = dur_us
	# Per-LOD bookkeeping. Clamp lod into the array bounds in case
	# Zylann ever passes an LOD higher than we expected.
	var lod_idx: int = clampi(lod, 0, _perf_blocks_by_lod.size() - 1)
	_perf_blocks_by_lod[lod_idx] += 1
	_perf_us_by_lod[lod_idx] += dur_us
	# Per-exit-path bookkeeping.
	match label:
		"above":
			_perf_count_above += 1
		"deep":
			_perf_count_deep += 1
		"flat":
			_perf_count_flat += 1
		"full":
			_perf_count_full += 1
	# Log slow individual blocks so we see worst cases. Gated behind
	# perf_log_per_block so the default run doesn't flood Output —
	# during world streaming nearly every block is >5 ms, which would
	# emit 10k+ prints in seconds. The summary every 100 blocks
	# (below) tells the same story without the spam.
	if perf_log_per_block and dur_us >= perf_log_min_us:
		print("[PERF GEN] block: %s lod=%d  %d us (%.2f ms)" % [
			label, lod, dur_us, dur_us / 1000.0,
		])
	# Periodic aggregate. Serialised behind a Mutex so only ONE worker
	# thread emits each 100-block summary. Without the mutex, multiple
	# threads crossing the threshold simultaneously all printed and all
	# reset, producing 2-3 duplicate lines in the Output panel.
	_perf_summary_mutex.lock()
	if _perf_blocks_generated >= _perf_summary_at_blocks:
		@warning_ignore("integer_division")
		var avg_us: int = _perf_total_us / max(1, _perf_blocks_generated)
		@warning_ignore("integer_division")
		var total_ms: int = _perf_total_us / 1000
		print("[PERF GEN] summary: %d blocks  total=%d ms  avg=%d us  max=%d us (%.2f ms)" % [
			_perf_blocks_generated,
			total_ms,
			avg_us,
			_perf_max_us,
			_perf_max_us / 1000.0,
		])
		# Per-LOD breakdown. Reads "lod=NN(count, avg_us)" — count is
		# blocks at that LOD this window, avg_us is mean time. Empty
		# LOD slots are omitted to keep the line readable. If you see
		# LOD0 starving (low count) while LOD3+ has lots of activity,
		# Zylann's queue is favouring distant chunks — at that point
		# the right next move is to cut view_distance further or
		# bump worker count.
		var lod_parts: Array[String] = []
		for i in _perf_blocks_by_lod.size():
			var c: int = _perf_blocks_by_lod[i]
			if c > 0:
				@warning_ignore("integer_division")
				var per_lod_avg: int = _perf_us_by_lod[i] / c
				lod_parts.append("L%d(n=%d, avg=%dus)" % [i, c, per_lod_avg])
		print("[PERF GEN] by-LOD: " + " ".join(lod_parts))
		# Exit-path breakdown — counts only, since these are mostly
		# instant early-outs anyway.
		print("[PERF GEN] exits: above=%d deep=%d flat=%d full=%d" % [
			_perf_count_above, _perf_count_deep, _perf_count_flat, _perf_count_full,
		])
		_perf_blocks_generated = 0
		_perf_total_us = 0
		_perf_max_us = 0
		for i in _perf_blocks_by_lod.size():
			_perf_blocks_by_lod[i] = 0
			_perf_us_by_lod[i] = 0
		_perf_count_above = 0
		_perf_count_deep = 0
		_perf_count_flat = 0
		_perf_count_full = 0
	_perf_summary_mutex.unlock()


func _fill_flat(out_buffer: VoxelBuffer, origin: Vector3i, stride: int) -> void:
	# Ground-truth fallback when no noise resource is configured.
	# Solid up to Y=0, air above. Used only for sanity-checking the
	# channel wiring without noise; not reached during normal play.
	_ensure_materials_cached()
	var size: Vector3i = out_buffer.get_size()
	var packed: int = _pack_for_material(_cached_dirt, Color.WHITE)
	for x in size.x:
		for z in size.z:
			for y in size.y:
				var world_y: int = origin.y + y * stride
				if world_y <= 0:
					out_buffer.set_voxel(packed, x, y, z, VoxelBuffer.CHANNEL_TYPE)


# =============================================================
# MATERIAL HELPERS — band selection, colour, and packing
# =============================================================

func _ensure_materials_cached() -> void:
	# Lazy first-call lookup of the four pilot materials.
	#
	# THREADING NOTE — this matters and was a bug.
	#   Zylann calls _generate_block on worker threads. The earlier
	#   implementation walked the SceneTree (`root.get_node_or_null(
	#   "VoxelMaterialRegistry")`) to fetch the autoload, but Godot 4
	#   forbids `get_node_or_null` from any thread that isn't main.
	#   Result: every block emitted an error AND the cache stayed
	#   empty, so the legacy grey color_low/high fallback ran for the
	#   whole world. (That's exactly the "still grey, no colors"
	#   symptom the player reported.)
	#
	#   Fix: load the material .tres files directly via ResourceLoader
	#   with hardcoded paths. ResourceLoader.load() IS safe to call
	#   from worker threads (Godot caches resources globally with
	#   internal locking). No autoload, no SceneTree, no threading
	#   hazard. The autoload (VoxelMaterialRegistry) is still the
	#   source of truth for runtime queries from gameplay code — but
	#   the generator doesn't need to go through it.
	#
	# Race-safety: multiple worker threads may run this concurrently
	# on first generation. ResourceLoader.load() returns the same
	# cached Resource on every call, so all threads write the same
	# pointer to _cached_*. The flag write isn't atomic across all
	# four materials, but each individual property assignment is, and
	# the worst case is "two threads do the same load" — benign.
	if _materials_lookup_attempted:
		return
	_materials_lookup_attempted = true
	# Hardcoded paths — these are the v1 pilot materials per CLAUDE.md
	# ("stone/dirt/grass/sand"). Adding a new material .tres still
	# auto-registers via VoxelMaterialRegistry, but the generator only
	# selects from these four bands today.
	_cached_stone = ResourceLoader.load("res://assets/voxels/materials/stone.tres") as VoxelMaterial
	_cached_dirt = ResourceLoader.load("res://assets/voxels/materials/dirt.tres") as VoxelMaterial
	_cached_grass = ResourceLoader.load("res://assets/voxels/materials/grass.tres") as VoxelMaterial
	_cached_sand = ResourceLoader.load("res://assets/voxels/materials/sand.tres") as VoxelMaterial
	_cached_bedrock = ResourceLoader.load("res://assets/voxels/materials/bedrock.tres") as VoxelMaterial
	_cached_marble = ResourceLoader.load("res://assets/voxels/materials/marble.tres") as VoxelMaterial
	_cached_stone_dark = ResourceLoader.load("res://assets/voxels/materials/stone_dark.tres") as VoxelMaterial
	_cached_snow = ResourceLoader.load("res://assets/voxels/materials/snow.tres") as VoxelMaterial
	# If any of the four .tres files is missing, the corresponding
	# `_cached_*` will be null. _select_material_for_depth() already
	# falls through to the next-best material, so missing files
	# degrade gracefully (e.g. no sand .tres → beaches use grass).


func _select_material_for_depth(depth: int, ground_y: int) -> VoxelMaterial:
	# `depth` is "voxels below the ground_y of this column" — 0 = the
	# topmost voxel of the column, 1 = one below, etc.
	#
	# Bands (measured from the top down):
	#   0 to grass_layer_thickness_voxels-1 → top layer (grass or sand)
	#   next dirt_layer_thickness_voxels    → dirt
	#   below that                           → stone
	#
	# At low altitudes (ground_y at or below beach_y_threshold), the
	# top layer is sand instead of grass, producing beaches.
	#
	# If a material isn't loaded (registry missing or .tres file
	# absent), we fall through to the next-best option so the
	# generator still produces SOMETHING rather than air. The
	# fallback chain: top layer → grass/sand → dirt → stone.

	# Top layer.
	if depth < grass_layer_thickness_voxels:
		if ground_y <= beach_y_threshold:
			if _cached_sand != null:
				return _cached_sand
		else:
			if _cached_grass != null:
				return _cached_grass
		# Fall through if the top-layer material isn't loaded.

	# Dirt layer (also catches the fall-through from the top layer).
	if depth < grass_layer_thickness_voxels + dirt_layer_thickness_voxels:
		if _cached_dirt != null:
			return _cached_dirt

	# Everything else is stone.
	return _cached_stone


func _compute_voxel_color(
	material: VoxelMaterial,
	world_x: int,
	world_y: int,
	world_z: int,
	half_range: float,
) -> Color:
	# Lerp the material's colour palette by altitude, then apply
	# per-voxel jitter. Identical to the old per-voxel colour code,
	# but the palette comes from the material's .tres rather than
	# the global color_low/color_high sliders.
	var lo: Color = color_low
	var hi: Color = color_high
	var jitter_amount: float = color_jitter
	if material != null:
		lo = material.color_low
		hi = material.color_high
		jitter_amount = material.color_jitter

	var t: float = clamp(
		(float(world_y) + half_range - float(height_offset_voxels)) / height_range_voxels,
		0.0,
		1.0,
	)
	var c: Color = lo.lerp(hi, t)

	# Per-voxel deterministic colour jitter — same triple-prime hash
	# the original generator used. Breaks up uniform colour on flat
	# tops so individual cubes are visible.
	if jitter_amount > 0.0:
		var hash_val: int = ((world_x * 73856093) ^ (world_y * 19349663) ^ (world_z * 83492791)) & 0xFF
		var j: float = (float(hash_val) / 255.0 - 0.5) * jitter_amount
		c.r = clampf(c.r + j, 0.0, 1.0)
		c.g = clampf(c.g + j, 0.0, 1.0)
		c.b = clampf(c.b + j, 0.0, 1.0)
	return c


func _pack_for_material(material: VoxelMaterial, color: Color) -> int:
	# Build the packed RGBA32 voxel value with the material id in the
	# integer in CHANNEL_TYPE.
	#
	# THREADING NOTE — this function runs on a Zylann worker thread
	# (called from _generate_block). Touching the SceneTree (e.g.
	# `get_node_or_null("/root/VoxelMaterialRegistry")`) from a worker
	# thread is forbidden in Godot 4. We keep the function pure: the
	# material is already cached on the main thread by
	# _ensure_materials_cached(), and we just read its material_id.
	#
	# v13: post-VoxelMesherBlocky migration, the value to write is
	# simply material.material_id. The `color` argument is kept for
	# API compatibility but ignored — material colour now lives in
	# the texture atlas, not in per-voxel data. (VoxelClusterBuilder
	# still reads color_low/high directly off the VoxelMaterial
	# resource for falling-cluster vertex tinting, but that's a
	# separate code path.)
	_unused(color)
	if material == null:
		return 0  # treat as air
	return material.material_id & 0xFF


func _unused(_x) -> void:
	# Tiny helper — silences "local variable not used" warnings on
	# values we keep around for clarity but no longer feed into a
	# write. Cheaper than scattering @warning_ignore everywhere.
	pass
