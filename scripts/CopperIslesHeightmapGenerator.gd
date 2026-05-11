@tool
extends VoxelGeneratorScript
class_name CopperIslesHeightmapGenerator

# CopperIslesHeightmapGenerator — fills CHANNEL_TYPE (terrain
# material_id) and CHANNEL_DATA5 (water source bytes) from a Gaea
# heightmap EXR.
#
# Mirrors the structure of CubicHeightmapGenerator but replaces the
# layered-noise ground-height calculation with a heightmap sample.
# Material banding (sand at coastline, grass above, dirt, then stone)
# is identical so the world reads the same as procedural Mira at any
# scale.
#
# v13 textured tileset (2026-05-10): writes integer material_id to
# CHANNEL_TYPE for VoxelMesherBlocky + VoxelBlockyLibrary, matching
# the pipeline World3D / CubicHeightmapGenerator already use. The
# legacy CHANNEL_COLOR (packed RGBA + mat_id in alpha) path is gone.
#
# Heightmap mapping (gray 0..1):
#   gray < 0.5  → seabed at sea_level - (0.5 - gray) * 2 * deep_below_sea_voxels
#   gray = 0.5  → exactly at sea level (waterline)
#   gray > 0.5  → land at sea_level + (gray - 0.5) * 2 * peak_above_sea_voxels
#
# Coordinate mapping:
#   The heightmap covers a rectangle in voxel-grid space defined by
#   origin_*_voxels (top-left corner) and extent_*_voxels (size). At
#   the locked default 6 vox/m terrain transform.scale, an extent of
#   30000 voxels equals 5 km of world space — the spec for Copper
#   Isles. When the test scene cycles transform.scale to find the
#   right feel, the voxel-space extent stays fixed; only the world
#   metres change.
#
# Outside the heightmap rectangle: deep ocean (gray 0).


# =============================================================
# HEIGHTMAP PARAMETERS
# =============================================================

## Path to the EXR/PNG/HDR heightmap. Loaded directly via Image.load
## so the file does NOT need to go through Godot's import pipeline —
## drop the file in `assets/heightmaps/` and the generator picks it up
## on first chunk generation.
@export_file("*.exr", "*.png", "*.hdr") var heightmap_path: String = "res://assets/heightmaps/copper_isles_heightmap.exr"

## Voxel-grid extent of the heightmap on the X axis. With the default
## 30000 voxels and transform.scale 1/6 (≈ 6 vox/m), the heightmap
## covers 5 km of world space — matching the Copper Isles spec.
@export var extent_x_voxels: int = 30000
@export var extent_z_voxels: int = 30000

## Top-left corner of the heightmap in voxel-grid space. Default
## centres the heightmap on (voxel) origin so world (0,0) renders the
## middle of the archipelago.
@export var origin_x_voxels: int = -15000
@export var origin_z_voxels: int = -15000

## Voxel-Y of the waterline. The gray value `sea_level_gray` in the
## heightmap maps to exactly this voxel-Y. Default 0 keeps the
## waterline at world Y=0 regardless of terrain.transform.scale, which
## makes the F5–F9 scale sweep easier to reason about.
@export var sea_level_voxels: int = 0

## Gray value (0..1) in the heightmap that corresponds to the
## waterline. Below this the column sinks below sea level by up to
## `elevation_below_at_black_voxels`; above this it rises by up to
## `elevation_above_at_white_voxels`.
##
##   sea_level_gray = 0.0 → heightmap is pure land (gray=0 is the
##   waterline; nothing in the heightmap goes underwater). Use this
##   when Gaea exports a normalised land-only heightmap.
##
##   sea_level_gray = 0.5 → heightmap encodes both bathymetry (dark
##   pixels) and terrain (light pixels) symmetrically — the original
##   COPPER_ISLES_DEMO_HEIGHTMAP spec.
@export_range(0.0, 1.0, 0.01) var sea_level_gray: float = 0.0

## Voxels of vertical relief above sea level when the heightmap reads
## pure white (gray = 1.0). Default 15000 vox = 2500 m world at the
## canonical 6 vox/m terrain.transform.scale, matching the new 8K EXR
## spec (5 km horizontal × 2.5 km peak; height-scale ratio 0.5).
@export var elevation_above_at_white_voxels: int = 15000

## Voxels of seabed depth below sea level when the heightmap reads
## pure black (gray = 0.0). Default 240 vox = 40 m at canonical scale.
## Only matters when `sea_level_gray` > 0.0 OR the column is outside
## the heightmap rectangle (out-of-bounds returns gray = 0 → deep
## ocean).
@export var elevation_below_at_black_voxels: int = 240

## When true, write water source bytes into CHANNEL_DATA for every
## column whose ground sits below sea level. Required for
## WaterFlowManager + WaterChunkMesher to render the ocean.
@export var emit_water: bool = true

## Bilinear sampling between heightmap pixels. Slower but smoother;
## OFF gives Minecraft-style 1-pixel-per-column terraces, useful for
## debugging the pixel→column mapping.
@export var bilinear_sampling: bool = true

## When true, the generator refuses to load the EXR in shipped builds
## (anywhere `OS.has_feature("template")` reports a release export).
## Editor + dev builds still load it normally for re-baking. The
## intended runtime story for shipped builds: every in-bounds chunk
## already lives in the baked baseline SQLite, so the generator never
## actually runs — it's only invoked for out-of-bounds chunks (deep
## ocean past the heightmap rectangle), which return flat sea-floor
## without needing the EXR. Set by `CopperIslesTestBootstrap` so the
## flag tracks the build mode automatically.
@export var require_heightmap_in_editor_only: bool = false


# =============================================================
# MATERIAL BAND PARAMETERS (mirror CubicHeightmapGenerator)
# =============================================================

@export_range(0, 5, 1) var grass_layer_thickness_voxels: int = 1
@export_range(0, 12, 1) var dirt_layer_thickness_voxels: int = 3

## At or below this voxel-Y the top voxel of the column is sand
## instead of grass — produces beaches. Default 12 vox above sea
## level = ~2 m world band of beach at the canonical 6 vox/m scale.
@export var beach_y_threshold: int = 12

## Safety margin in voxels added on top of the scanned max-ground when
## computing the early-out ceiling. Anything above (max_ground +
## margin) is treated as guaranteed air. 4 vox = handles bilinear
## sampling overshoot at the absolute brightest pixel.
@export var early_out_margin_voxels: int = 4


# =============================================================
# WORLD FLOOR (must mirror CubicHeightmapGenerator + VoxelEditManager)
# =============================================================

const WORLD_FLOOR_VOXEL_Y: int = -300


# =============================================================
# RUNTIME CACHE
# =============================================================

var _heightmap_image: Image = null
var _heightmap_load_attempted: bool = false
var _heightmap_w: int = 0
var _heightmap_h: int = 0

# Maximum red-channel value found anywhere in the heightmap, scanned
# once on first load. Used to compute _max_ground_y_voxels — the true
# tallest peak the EXR encodes — so the per-block early-out can skip
# every block above that value instead of using the much higher
# theoretical (sea_level + elevation_above_at_white).
var _max_gray: float = 1.0
var _max_ground_y_voxels: int = 0
var _max_ground_y_computed: bool = false

# Diagnostic: per-block early-out hit-rate. Bumped from worker threads
# (slightly racy increments are tolerable for a diagnostic). Printed
# once after the first 1000 blocks so the developer can confirm the
# extent cap actually took effect.
var _diag_blocks_total: int = 0
var _diag_blocks_early_out: int = 0
var _diag_printed: bool = false
# Periodic rate-report state (every ~5 s). Lets us SEE in real time
# whether the generator is busy (cache miss heavy) or idle (cache
# serving). A populated cache should show ~0 blocks/s after the
# initial spawn-stream window.
var _diag_last_rate_print_ms: int = 0
var _diag_blocks_at_last_print: int = 0
# Per-LOD counters. Tells us whether cache misses are concentrated
# at a specific LOD (usually LOD0 if the bake's walker spacing was
# wider than the runtime's LOD0 radius). 8 slots covers Zylann's
# typical lod_count cap.
var _diag_blocks_by_lod: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
var _diag_blocks_by_lod_at_last_print: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]

var _cached_stone: VoxelMaterial = null
var _cached_dirt: VoxelMaterial = null
var _cached_grass: VoxelMaterial = null
var _cached_sand: VoxelMaterial = null
var _cached_bedrock: VoxelMaterial = null
var _materials_lookup_attempted: bool = false


# Required by VoxelMesherBlocky — see CubicHeightmapGenerator for the
# long-form explanation. Without this override the engine never
# allocates CHANNEL_TYPE and the mesher logs thousands of "Central
# buffer must be valid" errors at world load.
#
# CHANNEL_DATA5 carries water source bytes (see WaterByteCodec). The
# blocky mesher ignores it; WaterChunkMesher reads it separately.
func _get_used_channels_mask() -> int:
	return (1 << VoxelBuffer.CHANNEL_TYPE) | (1 << VoxelBuffer.CHANNEL_DATA5)


# Stub so World3DBootstrap-style callers that push NoEditZone water
# AABBs into the generator don't crash. The Copper Isles test scene
# has no NoEditZones, so this snapshot stays empty.
func set_no_edit_water_aabbs(_aabbs: Array[AABB]) -> void:
	pass


# Public: sample the ground voxel-Y at a world voxel coord. Used by
# CopperIslesTestBootstrap to spawn the player just above the central
# island's actual peak instead of dropping them from the
# theoretically-highest-possible peak (which can be a 7.5 km fall at
# scale 0.5 with the current defaults).
func get_ground_voxel_y_at(world_x: int, world_z: int) -> int:
	return _gray_to_ground_y(_sample_gray(world_x, world_z))


# Diagnostic counter — tracks how often _generate_block early-outs
# vs runs the per-voxel loop. Worker-thread safe in the relaxed sense
# (raw int increments may race; the count is approximate).
#
# Two-stage output:
#   - One-shot summary after the first 1000 blocks (early-out %).
#   - Periodic rate prints every ~5 seconds reporting blocks/sec,
#     so we can SEE whether the generator is constantly busy
#     (cache miss rate is high) or quiet (cache is serving).
#     A healthy populated cache should show ~0 blocks/s after the
#     initial spawn-stream completes.
func _diag_record(was_early_out: bool, lod: int) -> void:
	_diag_blocks_total += 1
	if was_early_out:
		_diag_blocks_early_out += 1
	# Per-LOD count. Clamp to array bounds in case Zylann ever passes
	# a higher LOD than we expect.
	var lod_idx: int = clampi(lod, 0, _diag_blocks_by_lod.size() - 1)
	_diag_blocks_by_lod[lod_idx] += 1

	if not _diag_printed and _diag_blocks_total >= 1000:
		_diag_printed = true
		var pct: float = 100.0 * float(_diag_blocks_early_out) / float(maxi(1, _diag_blocks_total))
		print("[CopperIsles] DIAG after %d blocks: %d early-outs (%.1f%%) — max_ground_y=%d vox" % [
			_diag_blocks_total, _diag_blocks_early_out, pct, _max_ground_y_voxels,
		])
	# Periodic rate report. Time.get_ticks_msec is thread-safe.
	var now_ms: int = Time.get_ticks_msec()
	if _diag_last_rate_print_ms == 0:
		_diag_last_rate_print_ms = now_ms
		_diag_blocks_at_last_print = _diag_blocks_total
		for i in _diag_blocks_by_lod.size():
			_diag_blocks_by_lod_at_last_print[i] = _diag_blocks_by_lod[i]
		return
	var elapsed_ms: int = now_ms - _diag_last_rate_print_ms
	if elapsed_ms < 5000:
		return
	var blocks_in_window: int = _diag_blocks_total - _diag_blocks_at_last_print
	var rate: float = float(blocks_in_window) * 1000.0 / float(maxi(elapsed_ms, 1))
	# Build per-LOD rate breakdown for the window — empty LOD slots
	# are omitted so the line stays readable. Tells us where misses
	# live: "L0=600/s" → bake walker LOD0 spacing too sparse.
	var per_lod_parts: Array[String] = []
	for i in _diag_blocks_by_lod.size():
		var delta: int = _diag_blocks_by_lod[i] - _diag_blocks_by_lod_at_last_print[i]
		if delta > 0:
			var lod_rate: float = float(delta) * 1000.0 / float(maxi(elapsed_ms, 1))
			per_lod_parts.append("L%d=%d/s" % [i, int(lod_rate)])
		_diag_blocks_by_lod_at_last_print[i] = _diag_blocks_by_lod[i]
	print("[CopperIsles] DIAG rate: %d blocks/s  [%s]  (total %d, early-out %d)" % [
		int(rate), " ".join(per_lod_parts), _diag_blocks_total, _diag_blocks_early_out,
	])
	_diag_last_rate_print_ms = now_ms
	_diag_blocks_at_last_print = _diag_blocks_total


# =============================================================
# HEIGHT SAMPLING
# =============================================================

func _ensure_image() -> Image:
	# Lazy load. Image.load reads the file directly off disk so the
	# editor's import pipeline (which would convert EXR → CompressedTexture2D)
	# is bypassed. Race-safe across worker threads: the worst case is
	# two threads both calling Image.new + Image.load on first access,
	# producing identical Image objects, and one stomp on the cache —
	# benign because both objects have the same pixel data.
	if _heightmap_load_attempted:
		return _heightmap_image
	_heightmap_load_attempted = true
	# Shipped-build guard. When the bake pipeline is finished, the
	# baseline SQLite contains every in-bounds chunk and the generator
	# only runs for out-of-bounds (deep ocean) — no EXR needed. Set
	# `require_heightmap_in_editor_only = true` and the generator
	# skips the load in release builds (saves ~30 MB of memory + the
	# scan time, and lets us drop the EXR from the shipped PCK).
	if require_heightmap_in_editor_only and OS.has_feature("template"):
		# Print once via the load_attempted flag — same race-tolerant
		# pattern as the rest of the cache.
		print("[CopperIsles] Heightmap load skipped (release build, " +
				"require_heightmap_in_editor_only=true). Generator will " +
				"return flat sea-floor for out-of-bounds chunks.")
		return null
	if heightmap_path == "":
		push_error("[CopperIsles] heightmap_path is empty.")
		return null
	var img := Image.new()
	var err: int = img.load(heightmap_path)
	if err != OK:
		push_error("[CopperIsles] Failed to load heightmap '%s' (err=%d)." % [heightmap_path, err])
		return null
	_heightmap_image = img
	_heightmap_w = img.get_width()
	_heightmap_h = img.get_height()
	# Scan once for the brightest pixel to bound the vertical extent
	# the generator actually produces. Without this the early-out check
	# uses the THEORETICAL ceiling (sea_level + elevation_above_at_white
	# = 15001 vox at defaults), which forces the streamer to allocate +
	# touch every block all the way up to 2500 m world even when the
	# tallest peak in this particular EXR is only, say, 700 m.
	#
	# Single linear pass over the whole image: 8192 × 8192 = 67M reads,
	# ~1-2 s on a modern CPU. Done once on the first chunk-generation
	# call (no editor freeze). Future bake invocations reuse the cache.
	var max_g: float = 0.0
	var min_g: float = 1.0
	var sum_g: float = 0.0
	# OCEAN THRESHOLD with the linear gray-to-Y mapping (post-2026-05-09
	# refactor): ground_y_voxels = gray * elevation_above_at_white_voxels.
	# A pixel is ocean iff its ground voxel-Y is below sea_level_voxels,
	# i.e. gray < sea_level_voxels / elevation_above_at_white_voxels.
	var elev_above: int = maxi(elevation_above_at_white_voxels, 1)
	var ocean_threshold: float = float(sea_level_voxels) / float(elev_above)
	var below_thresh: int = 0
	var hist_buckets: PackedInt32Array = PackedInt32Array()
	hist_buckets.resize(10)
	for y_scan in _heightmap_h:
		for x_scan in _heightmap_w:
			var g: float = clampf(img.get_pixel(x_scan, y_scan).r, 0.0, 1.0)
			if g > max_g:
				max_g = g
			if g < min_g:
				min_g = g
			sum_g += g
			if g < ocean_threshold:
				below_thresh += 1
			var bucket: int = clampi(int(g * 10.0), 0, 9)
			hist_buckets[bucket] += 1
	var total_pixels: int = _heightmap_h * _heightmap_w
	var avg_g: float = sum_g / float(total_pixels)
	var ocean_pct: float = 100.0 * float(below_thresh) / float(total_pixels)
	_max_gray = clampf(max_g, 0.0, 1.0)
	_max_ground_y_voxels = _gray_to_ground_y(_max_gray)
	_max_ground_y_computed = true
	print("[CopperIsles] Loaded heightmap %dx%d from %s  (max_gray=%.4f → max_ground_y=%d vox)" % [
		_heightmap_w, _heightmap_h, heightmap_path, _max_gray, _max_ground_y_voxels,
	])
	print("[CopperIsles] heightmap stats: min_gray=%.4f  max_gray=%.4f  avg_gray=%.4f" % [min_g, max_g, avg_g])
	print("[CopperIsles] ocean threshold (gray<%.4f) covers %.2f%% of pixels (%d / %d)" % [
		ocean_threshold, ocean_pct, below_thresh, total_pixels,
	])
	var hist_str := ""
	for i in 10:
		var pct: float = 100.0 * float(hist_buckets[i]) / float(total_pixels)
		hist_str += "  [%.1f-%.1f]:%.1f%%" % [i * 0.1, (i + 1) * 0.1, pct]
	print("[CopperIsles] gray histogram:%s" % hist_str)
	# ASCII heightmap dump: 32x32 grid sampled across the full image.
	# Each character covers ~256 heightmap pixels, ~156 m world. Legend:
	#   '~'  ocean (gray < threshold)
	#   '.'  low land (gray < 2*threshold, just above sea level)
	#   ':'  mid (gray < 0.1)
	#   '+'  hills (gray < 0.2)
	#   '#'  mountain (gray >= 0.2)
	# The grid origin (0,0 in ASCII) is the heightmap's (-X, -Z) corner;
	# the grid centre is world (0, 0) where the player spawns.
	print("[CopperIsles] ASCII heightmap (32x32; ~ocean . low : mid + hill # mountain):")
	var grid_size: int = 32
	var step_x: int = _heightmap_w / grid_size
	var step_y: int = _heightmap_h / grid_size
	# Bands chosen relative to ocean_threshold so they remain meaningful
	# at any sea level: shallow above ocean = up to ~2× ocean threshold
	# (or "barely above water"); lowland up to 4×; hill up to 6×;
	# mountain everything taller. With sea_level_voxels=900 and
	# elev_above=15000, ocean_threshold=0.06 → bands at 0.06, 0.12,
	# 0.24, 0.36, ∞.
	var band_shallow: float = ocean_threshold * 2.0
	var band_low: float = ocean_threshold * 4.0
	var band_hill: float = ocean_threshold * 6.0
	for gy in grid_size:
		var row := ""
		for gx in grid_size:
			var px: int = gx * step_x + step_x / 2
			var py: int = gy * step_y + step_y / 2
			var g: float = clampf(img.get_pixel(px, py).r, 0.0, 1.0)
			var ch: String = "#"
			if g < ocean_threshold:
				ch = "~"
			elif g < band_shallow:
				ch = "."
			elif g < band_low:
				ch = ":"
			elif g < band_hill:
				ch = "+"
			row += ch
		print("  " + row)
	return img


func _sample_gray(world_x: int, world_z: int) -> float:
	# Returns 0..1 grayscale value at the given voxel-grid coord, with
	# bilinear smoothing if enabled. Out-of-bounds (outside the heightmap
	# rectangle) returns 0 — deep ocean.
	var img: Image = _ensure_image()
	if img == null or _heightmap_w == 0 or _heightmap_h == 0:
		return 0.5  # flat sea level fallback when the file is missing
	var u: float = float(world_x - origin_x_voxels) / float(extent_x_voxels)
	var v: float = float(world_z - origin_z_voxels) / float(extent_z_voxels)
	if u < 0.0 or u >= 1.0 or v < 0.0 or v >= 1.0:
		return 0.0
	if not bilinear_sampling:
		var px: int = clampi(int(u * _heightmap_w), 0, _heightmap_w - 1)
		var pz: int = clampi(int(v * _heightmap_h), 0, _heightmap_h - 1)
		return img.get_pixel(px, pz).r
	# Bilinear: sample four neighbours and weight by fractional offset.
	var fx: float = u * _heightmap_w - 0.5
	var fz: float = v * _heightmap_h - 0.5
	var x0: int = clampi(int(floor(fx)), 0, _heightmap_w - 1)
	var z0: int = clampi(int(floor(fz)), 0, _heightmap_h - 1)
	var x1: int = clampi(x0 + 1, 0, _heightmap_w - 1)
	var z1: int = clampi(z0 + 1, 0, _heightmap_h - 1)
	var tx: float = clampf(fx - floor(fx), 0.0, 1.0)
	var tz: float = clampf(fz - floor(fz), 0.0, 1.0)
	var g00: float = img.get_pixel(x0, z0).r
	var g10: float = img.get_pixel(x1, z0).r
	var g01: float = img.get_pixel(x0, z1).r
	var g11: float = img.get_pixel(x1, z1).r
	var g0: float = lerp(g00, g10, tx)
	var g1: float = lerp(g01, g11, tx)
	return lerp(g0, g1, tz)


func _gray_to_ground_y(gray: float) -> int:
	# REFACTORED 2026-05-09: simple linear mapping from gray ∈ [0, 1]
	# to ground_y ∈ [0, elevation_above_at_white_voxels]. Sea level
	# is now an INDEPENDENT visual concept — it does NOT enter this
	# formula at all.
	#
	# Contract:
	#   gray = 0.0 → ground at world Y = 0 (lowest ocean floor)
	#   gray = 1.0 → ground at world Y = elevation_above_at_white_voxels / 6
	#                (= 2500 m at the default of 15000 voxels)
	#
	# Anything below sea_level_voxels is automatically ocean (no
	# separate threshold needed). Raising or lowering sea_level_voxels
	# only moves the water plane — terrain Y never shifts.
	#
	# The legacy `sea_level_gray` and `elevation_below_at_black_voxels`
	# fields are now ignored. They remain on the resource for backward
	# compatibility with old .tres files, but the values do not affect
	# generation. See design/COPPER_ISLES_BAKE_NOTES.md "World scale
	# refactor" for the full rationale.
	#
	# Gray is clamped to 0..1 because Gaea's EXR exports can carry HDR
	# values outside the standard 0..1 range. Without the clamp those
	# would blow past the elevation cap.
	var g: float = clampf(gray, 0.0, 1.0)
	return int(round(g * float(elevation_above_at_white_voxels)))


# =============================================================
# MATERIAL CACHE
# =============================================================

func _ensure_materials_cached() -> void:
	# Same lazy-ResourceLoader pattern as CubicHeightmapGenerator —
	# ResourceLoader.load is safe from worker threads (Godot caches
	# resources globally with internal locking).
	if _materials_lookup_attempted:
		return
	_materials_lookup_attempted = true
	_cached_stone = ResourceLoader.load("res://assets/voxels/materials/stone.tres") as VoxelMaterial
	_cached_dirt = ResourceLoader.load("res://assets/voxels/materials/dirt.tres") as VoxelMaterial
	_cached_grass = ResourceLoader.load("res://assets/voxels/materials/grass.tres") as VoxelMaterial
	_cached_sand = ResourceLoader.load("res://assets/voxels/materials/sand.tres") as VoxelMaterial
	_cached_bedrock = ResourceLoader.load("res://assets/voxels/materials/bedrock.tres") as VoxelMaterial


# =============================================================
# GENERATION
# =============================================================

func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	var size: Vector3i = out_buffer.get_size()
	var stride: int = 1 << lod

	# Touching _ensure_image() up front guarantees _max_ground_y_voxels
	# is populated before the early-out math runs. If the heightmap
	# fails to load, _max_ground_y_computed stays false and we fall
	# back to the theoretical ceiling (the original behaviour).
	_ensure_image()

	# Vertical bounds for early-out. Two ceilings:
	#   - theoretical: sea_level + elevation_above_at_white (always valid)
	#   - actual:     sea_level mapped through the heightmap's brightest
	#                  pixel + a safety margin (much tighter, only valid
	#                  once the EXR has been scanned)
	var theoretical_max_y: int = sea_level_voxels + elevation_above_at_white_voxels + 1
	var max_ground_y: int = theoretical_max_y
	if _max_ground_y_computed:
		max_ground_y = _max_ground_y_voxels + early_out_margin_voxels
	var block_min_y: int = origin_in_voxels.y
	var block_max_y: int = origin_in_voxels.y + (size.y * stride) - 1

	if block_min_y > max_ground_y and block_min_y > sea_level_voxels:
		_diag_record(true, lod)
		return
	if block_max_y < WORLD_FLOOR_VOXEL_Y:
		_diag_record(true, lod)
		return

	_diag_record(false, lod)
	_ensure_materials_cached()

	# Pre-extract per-material ids (one lookup per block; the inner
	# y-loop just reads locals + does inline math). v13: only the
	# integer material_id is needed for CHANNEL_TYPE; per-material
	# colour palettes are unused at generation time and live in the
	# texture atlas instead.
	var dirt_id: int = 0
	if _cached_dirt != null:
		dirt_id = _cached_dirt.material_id

	var stone_id: int = 0
	if _cached_stone != null:
		stone_id = _cached_stone.material_id

	var grass_id: int = dirt_id
	if _cached_grass != null:
		grass_id = _cached_grass.material_id

	var sand_id: int = grass_id
	if _cached_sand != null:
		sand_id = _cached_sand.material_id

	# Bedrock material id for the world-floor row. v13: just the integer
	# id goes into CHANNEL_TYPE; no RGBA packing.
	var bedrock_id: int = 0
	if _cached_bedrock != null:
		bedrock_id = _cached_bedrock.material_id & 0xFF

	var grass_thick: int = grass_layer_thickness_voxels
	var dirt_band_end: int = grass_thick + dirt_layer_thickness_voxels
	var beach_y: int = beach_y_threshold

	var write_water: bool = emit_water and (lod == 0)
	var water_byte: int = WaterByteCodec.SOURCE_BYTE

	for x in size.x:
		for z in size.z:
			var world_x: int = origin_in_voxels.x + x * stride
			var world_z: int = origin_in_voxels.z + z * stride

			# Heightmap → ground voxel-Y for this column.
			var gray: float = _sample_gray(world_x, world_z)
			var ground_y: int = _gray_to_ground_y(gray)

			# Top-band id (sand at coastline, grass elsewhere).
			var top_id: int = grass_id
			if ground_y <= beach_y:
				top_id = sand_id

			var emit_water_here: bool = write_water and ground_y < sea_level_voxels

			for y in size.y:
				var world_y: int = origin_in_voxels.y + y * stride

				# Air above terrain — write water byte if this column is
				# below sea level and we're at LOD0.
				if world_y > ground_y:
					if emit_water_here and world_y <= sea_level_voxels:
						out_buffer.set_voxel(water_byte, x, y, z, VoxelBuffer.CHANNEL_DATA5)
					continue

				# Below the world floor: air.
				if world_y < WORLD_FLOOR_VOXEL_Y:
					continue

				# Bedrock layer — single solid unmineable row.
				if world_y == WORLD_FLOOR_VOXEL_Y and bedrock_id != 0:
					out_buffer.set_voxel(bedrock_id, x, y, z, VoxelBuffer.CHANNEL_TYPE)
					continue

				# Pick band by depth. Only the material_id is needed for
				# the textured cube pipeline — per-voxel colour lerp is
				# gone (texture atlas tiles in the VoxelBlockyLibrary
				# carry the visual variation).
				var depth: int = ground_y - world_y
				var mat_id: int
				if depth < grass_thick:
					mat_id = top_id
				elif depth < dirt_band_end:
					mat_id = dirt_id
				else:
					mat_id = stone_id
				out_buffer.set_voxel(mat_id, x, y, z, VoxelBuffer.CHANNEL_TYPE)
