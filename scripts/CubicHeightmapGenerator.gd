@tool
extends VoxelGeneratorScript
class_name CubicHeightmapGenerator

# CubicHeightmapGenerator — fills the COLOR channel so VoxelMesherCubes
# can render the world as hard-edged colored cubes.
#
# What this does in plain English:
#
#   For every voxel block the engine asks us to fill, we walk a 2D
#   grid (X, Z) at the block's world position, sample 2D noise to get
#   a ground height, then for every Y in the block:
#       - if Y <= ground_height → write a packed RGBA color into
#         CHANNEL_COLOR (visible solid cube)
#       - if Y >  ground_height → leave default 0 (air, transparent,
#         no cube emitted)
#
#   Color shifts subtly with altitude — peaks paler than valleys —
#   so the cubic terrain reads as terrain rather than a uniform
#   slab of one color.
#
# Why CHANNEL_COLOR and not CHANNEL_TYPE?
#
#   VoxelMesherCubes determines "is this voxel solid?" by reading the
#   COLOR channel: alpha=0 means air, alpha>0 means a solid cube of
#   that RGBA. Writing TYPE doesn't help Cubes — that channel is for
#   VoxelMesherBlocky (which uses a per-type model library).
#
#   Earlier versions of this script wrote TYPE and threw thousands
#   of "Central buffer must be valid" errors at world load because
#   the COLOR channel was never populated. The fix is to write COLOR.
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

## Reference voxel-Y for "ocean surface". Currently informational only
## — actual water elevation lives on `OceanVolume.surface_y` in
## `World3D.tscn` (default Y=8). Kept here for future generator-side
## logic (e.g. forced sand colour at coastline).
@export var sea_level_voxels: int = 0

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
## instead of grass. Roughly the OceanVolume.surface_y plus a
## small margin to give beaches their characteristic strip above
## the waterline. Default 7 ≈ 1 voxel above the test ocean's
## surface_y of 8 (-1 below it for the tide line).
@export var beach_y_threshold: int = 7


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
var _materials_lookup_attempted: bool = false
var _depth_logged: bool = false


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
	# CHANNEL_COLOR in the chunk buffer. The mesher then tries to
	# read an unallocated channel and throws "Central buffer must be
	# valid" — thousands of times, once per streamed chunk.
	#
	# Returning a bitmask of channels we write tells the engine which
	# channels to set up before calling _generate_block.
	return 1 << VoxelBuffer.CHANNEL_COLOR


func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	# Engine calls this for every chunk the player approaches. We
	# fill out_buffer with COLOR values for that chunk.
	#
	# DO NOT call out_buffer.set_channel_depth() here — confirmed
	# 2026-05-05: even calling on a fresh buffer before any writes
	# produces empty chunks (terrain disappears, player falls
	# forever). The depth must be set globally on the terrain or
	# via a different mechanism entirely (e.g. switching the mesher
	# to COLOR_PALETTE mode so 1 byte per voxel suffices).

	# Perf timer — wraps the whole function. The deferred-print at the
	# bottom decides whether to emit a log line based on perf_log_min_us.
	var t_start: int = 0
	if perf_log_enabled:
		t_start = Time.get_ticks_usec()

	# DIAGNOSTIC: log the channel depth on the first block so we can
	# confirm what the engine has allocated. Read-only — does NOT mutate.
	if not _depth_logged:
		_depth_logged = true
		var dep_now: int = out_buffer.get_channel_depth(VoxelBuffer.CHANNEL_COLOR)
		print("[Generator] CHANNEL_COLOR depth: %d (DEPTH_8_BIT=%d, DEPTH_16_BIT=%d, DEPTH_32_BIT=%d, DEPTH_64_BIT=%d)" % [
			dep_now,
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

	if block_min_y > max_ground_y:
		# Entire block is above terrain — leave as air (default 0).
		_perf_record_block_done(t_start, lod, "above")
		return

	# Materials registered? (Lazy lookup; safe across worker threads
	# because writes are idempotent — every thread fetches the same
	# VoxelMaterial references.)
	_ensure_materials_cached()

	if block_max_y < min_ground_y:
		# Entire block is buried deep below terrain — fill solid with
		# stone. Player only sees these voxels if they dig deep enough
		# to expose them.
		var stone_packed: int = _pack_for_material(_cached_stone, _cached_stone.color_low if _cached_stone != null else color_low)
		out_buffer.fill(stone_packed, VoxelBuffer.CHANNEL_COLOR)
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

	# Per-column thickness boundaries (read property once per block).
	var grass_thick: int = grass_layer_thickness_voxels
	var dirt_band_end: int = grass_thick + dirt_layer_thickness_voxels
	var beach_y: int = beach_y_threshold
	var h_offset_v: int = height_offset_voxels
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

	# Per-column heightmap pass.
	var half_range: float = height_range_voxels * 0.5
	for x in size.x:
		for z in size.z:
			var world_x: int = origin_in_voxels.x + x * stride
			var world_z: int = origin_in_voxels.z + z * stride

			# --- Macro height: wide-feature noise, optionally quantized
			#     to integer-metre (8-voxel) steps for terraced look. ---
			var n_macro: float = noise.get_noise_2d(float(world_x), float(world_z))
			var macro_y: int
			if quantize_to_meters:
				# roundi → terraces centred on integer metres rather
				# than always rounded down. Cliff transitions happen
				# at the half-metre crossings of the macro noise.
				var macro_meters: int = roundi(n_macro * half_range / 8.0)
				macro_y = macro_meters * 8
			else:
				macro_y = int(n_macro * half_range)

			# --- Mid height: 8-m-scale rolling hills layered on the
			#     macro silhouette. ±2 m amplitude. ---
			var n_mid: float = noise.get_noise_2d(
				float(world_x) * mid_frequency_multiplier,
				float(world_z) * mid_frequency_multiplier,
			)
			var mid_y: int = int(n_mid * float(mid_amplitude_voxels))

			# --- Detail height: cube-by-cube high-frequency wobble.
			#     ±50 cm at ~1-2 m feature scale. ---
			var n_detail: float = noise.get_noise_2d(
				float(world_x) * detail_frequency_multiplier,
				float(world_z) * detail_frequency_multiplier,
			)
			var detail_y: int = int(n_detail * float(detail_amplitude_voxels))

			var ground_y: int = macro_y + mid_y + detail_y + h_offset_v

			# Pick this column's TOP-band tuple (grass on grasslands,
			# sand at coastlines). Done once per column.
			var top_lo: Color = grass_lo
			var top_hi: Color = grass_hi
			var top_id: int = grass_id
			if ground_y <= beach_y:
				top_lo = sand_lo
				top_hi = sand_hi
				top_id = sand_id

			for y in size.y:
				var world_y: int = origin_in_voxels.y + y * stride
				if world_y > ground_y:
					continue

				# Pick band based on depth from this column's ground_y.
				var depth: int = ground_y - world_y  # 0 = top voxel
				var lo: Color
				var hi: Color
				var mat_id: int
				if depth < grass_thick:
					lo = top_lo
					hi = top_hi
					mat_id = top_id
				elif depth < dirt_band_end:
					lo = dirt_lo
					hi = dirt_hi
					mat_id = dirt_id
				else:
					lo = stone_lo
					hi = stone_hi
					mat_id = stone_id

				# Inline color computation (was _compute_voxel_color).
				var c: Color
				if debug_vivid_colors:
					# DEBUG mode — vivid per-material colours so the user
					# can verify that (a) vertex colours are reaching the
					# screen and (b) different materials get selected at
					# different depths. If terrain still reads as flat
					# grey/black with this on, the problem is downstream
					# (terrain material, mesher config). If terrain shows
					# distinct colour bands, the problem is the .tres
					# palette being too dark for current lighting.
					if mat_id == 1:
						c = Color(1.0, 0.15, 0.15)   # stone → red
					elif mat_id == 2:
						c = Color(1.0, 0.55, 0.15)   # dirt → orange
					elif mat_id == 3:
						c = Color(0.20, 1.0, 0.20)   # grass → green
					elif mat_id == 4:
						c = Color(1.0, 1.0, 0.20)    # sand → yellow
					else:
						c = Color(1.0, 0.20, 1.0)    # unknown → magenta (loud)
				else:
					# Lerp within this material's NATURAL band, not the
					# global world height range. Each material's color_low
					# is the bottom of its band; color_high is the top.
					# Without this, a grass voxel at altitude 100 would
					# look different from a grass voxel at altitude 50 —
					# same material, different shade — which contradicts
					# the .tres palette design intent (see VoxelMaterial.gd
					# docstring on color_low / color_high).
					var t_band: float
					if depth < grass_thick:
						# 1-voxel-thick top layer — no internal band to
						# lerp across. Use color_high (the lit/exposed
						# surface tint the material author intended).
						t_band = 1.0
					elif depth < dirt_band_end:
						# Dirt band — top of band → color_high,
						# bottom of band → color_low.
						t_band = 1.0 - float(depth - grass_thick) * dirt_band_inv_max
					else:
						# Stone band — fade from color_high at the top
						# of the band (just below dirt) to color_low
						# over STONE_BAND_REF_VOXELS depth. Anything
						# deeper pegs at color_low (deep cool stone).
						var stone_depth: int = depth - dirt_band_end
						t_band = clampf(1.0 - float(stone_depth) / STONE_BAND_REF_VOXELS, 0.0, 1.0)
					c = lo.lerp(hi, t_band)

				# Inline pack: RGB from c, alpha byte = mat_id.
				# (Was _pack_for_material — now one bit-op.)
				var packed: int = (c.to_rgba32() & 0xFFFFFF00) | (mat_id & 0xFF)
				out_buffer.set_voxel(packed, x, y, z, VoxelBuffer.CHANNEL_COLOR)
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
	var packed: int = _pack_for_material(_cached_dirt, _cached_dirt.color_low if _cached_dirt != null else color_low)
	for x in size.x:
		for z in size.z:
			for y in size.y:
				var world_y: int = origin.y + y * stride
				if world_y <= 0:
					out_buffer.set_voxel(packed, x, y, z, VoxelBuffer.CHANNEL_COLOR)


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
	# alpha byte.
	#
	# THREADING NOTE — second instance of the same bug as
	# _ensure_materials_cached. This function runs on a Zylann worker
	# thread (called from _generate_block at line 384). Touching the
	# SceneTree (`get_node_or_null("/root/...")`) from a worker thread
	# is forbidden in Godot 4 and produces ~160k errors per minute of
	# play during continuous chunk streaming.
	#
	# Fix: do the alpha-byte pack inline. The encoding is one bit-op
	# (alpha byte = material_id) and lives canonically in
	# VoxelMaterialRegistry.pack_voxel, but copying that math here
	# (with a comment so it can be kept in sync if the encoding ever
	# changes) is far cheaper than the threading hazard. The registry
	# stays the source of truth for runtime queries from gameplay
	# code; the generator just produces voxels matching the same
	# encoding.
	if material == null:
		return color.to_rgba32()
	# Encoding: high 24 bits = RGB888 from `color`, low 8 bits =
	# material_id. Mirrors VoxelMaterialRegistry.pack_voxel(); if the
	# alpha-byte-as-id encoding ever changes, update both sites.
	var packed: int = color.to_rgba32()
	return (packed & 0xFFFFFF00) | (material.material_id & 0xFF)
