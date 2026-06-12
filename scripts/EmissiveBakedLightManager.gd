extends Node

# Single authority for the voxel grid scale — all scale constants below
# mirror values from this file. See scripts/VoxelScale.gd.
const VoxelScale := preload("res://scripts/VoxelScale.gd")

# EmissiveBakedLightManager — Phase J done properly.
#
# What this does in plain English:
#
#   Around the player, a small 3D box of "indirect light cells" floats
#   along. Each cell holds an RGBA8 colour. Every emissive voxel
#   (copper_ore is the v1 showcase) seeds light into that volume; the
#   light propagates BFS-style through air voxels only — solid rock
#   STOPS it. The terrain shader (terrain_voxel.gdshader) samples this
#   volume per fragment and adds it to EMISSION. Result: a glowing
#   copper vein washes the tunnel it's exposed in but its light does
#   NOT bleed up through solid rock to the surface (the cosmetic issue
#   designer flagged 2026-05-26 with the OmniLight3D v1).
#
# This is the original Phase J spec from
# design/GRAPHICS_PASS_2026-05-19.md — deferred when v1 went with
# engine-native OmniLight3Ds. The v1 (scripts/EmissiveLightManager.gd)
# is kept on disk; this autoload supersedes it. When this autoload is
# active, it sets ELM._active = false at startup so they don't
# double-light.
#
# Architecture:
#   * GD owns: terrain.get_voxel_tool() + tool.copy() (a 128^3 buffer
#     around the player), emissive-voxel discovery (single scan over
#     the bulk channel byte array), the ImageTexture3D upload, the
#     RenderingServer global shader parameters that point the terrain
#     shader at the texture + volume transform.
#   * C++ owns (extensions/voxel_gen/src/emissive_baked_cpp.cpp):
#     pre-computing open[] from the buffer, BFS floodfill from every
#     emitter (FIFO queue, neighbour order +x/-x/+y/-y/+z/-z, gated
#     on cell-centre-is-air), channel-wise max-blend across emitters,
#     output as a flat PackedByteArray of N^3 * 4 RGBA bytes.
#   * Parity gated by `tools/headless/run.ps1 baked_light`.
#
# Trigger:
#   * Edit applied inside the volume → rebake on next tick.
#   * Player crossed a cell boundary (volume slides) → rebake.
#   * Failsafe periodic rebake every PERIODIC_INTERVAL_S in case
#     either trigger missed something.
#
# Reference: design/GRAPHICS_PASS_2026-05-19.md Phase J spec;
# memory/project_vgm_elm_cpp_port.md (the cosmetic issue this fixes).

# --- Volume sizing ---------------------------------------------------
# N=32 cells × K=7 voxels each = 224-voxel cube (~22.4 m at 10 vox/m).
# K was 4 at the old 6 vox/m scale (~21.3 m world span); bumped to 7
# at the 10 vox/m pivot so the lit volume keeps roughly the same WORLD
# size instead of collapsing to 12.8 m. Texture cost is unchanged
# (cells_per_axis sizes the texture): 32^3 * 4 bytes = 128 KB. The
# copy buffer grows to 224^3 ≈ 11 MB — re-profile in the R2 retune.
@export var cells_per_axis: int = 32
@export var cell_size_voxels: int = 7

# BFS reach in cells. Designer 2026-05-27 second-round test: 4 steps
# at falloff 0.5 was STILL too bright + penetrated too many blocks.
# Going aggressive — 2 steps means BFS reaches at most one cell past
# the seed (~1.3 m radius). Combined with the lower falloff below,
# anything past the immediate neighbour is effectively invisible.
@export var max_bfs_steps: int = 2
# falloff_q12 = 1024 ≈ 0.25 per step. At max_bfs_steps=2 the edge
# value is 0.25^2 = 6 % of source; combined with bake_strength below
# that contributes ~0.01 to EMISSION — barely visible.
@export var falloff_q12: int = 1024

# Shader multiplier — bytes encode 0..1 range, this scales them into
# EMISSION (AgX tonemaps from 0..several). Designer round 3
# 2026-05-27: another -30% from 0.15 -> 0.10. Emitter cell now
# contributes ~0.10 EMISSION; neighbour ring ~0.025; past that 0.
# Designer-tunable @export — raise toward 0.3 / 0.5 for stronger glow.
@export var bake_strength: float = 0.10

# Periodic safety rebake — picks up anything edit_applied + player-
# movement missed (e.g. a chunk that streamed in with a new emissive
# voxel and no edit fired).
@export var periodic_interval_s: float = 2.0

# Master kill-switch.
@export var enabled: bool = true

# Debug logging.
@export var verbose: bool = false

# --- Constants -------------------------------------------------------
const VOXEL_SIZE_M: float = VoxelScale.VOXEL_SIZE_M
# Mirrors VoxelScale.VOXEL_SIZE_M (edge length of one voxel in metres).
# Local name kept so call sites inside this file stay unchanged.
const VOXELS_PER_METER: float = VoxelScale.VOXELS_PER_METER
# Mirrors VoxelScale.VOXELS_PER_METER. Single source of truth: VoxelScale.gd.

const _GLOBAL_TEX: String = "baked_light_tex"
const _GLOBAL_ORIGIN: String = "baked_light_origin_world"
const _GLOBAL_INV_VOLUME: String = "baked_light_inv_volume_m"
const _GLOBAL_STRENGTH: String = "baked_light_strength"

const _TICK_S: float = 0.2  # 5 Hz — picks up edits within one tick

# --- State -----------------------------------------------------------
var _cpp: Resource = null
var _emissive_mat_ids: Dictionary = {}     # mat_id -> true
var _texture: ImageTexture3D = null
var _terrain: Node = null
var _active: bool = false

var _last_origin_v: Vector3i = Vector3i(INF_VOXEL, INF_VOXEL, INF_VOXEL)
var _dirty: bool = true
var _tick_accum: float = 0.0
var _periodic_accum: float = 0.0

const INF_VOXEL: int = 2147483647

# Re-use the same Vector3i origin each bake to avoid re-allocs.
var _scratch_buf: VoxelBuffer = null

# 256 × 4 bytes (r, g, b, energy) per material id. energy=0 means
# "not emissive — C++ skips it." Built once in _ready from the
# VoxelMaterialRegistry. Passed by reference into the C++ bake.
var _mat_color_table: PackedByteArray = PackedByteArray()

# Buried emissive voxels still seed their own cell unless this is on
# — the v1 bug the designer flagged 2026-05-27. The C++ port checks
# at least one 6-face-neighbour is air before letting a voxel emit.
@export var air_neighbor_filter: bool = true


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	if not enabled:
		set_process(false)
		return

	if get_node_or_null("/root/VoxelMaterialRegistry") == null:
		push_warning("[EmissiveBakedLight] VoxelMaterialRegistry missing — disabled.")
		set_process(false)
		return
	for vm in VoxelMaterialRegistry.get_all():
		if vm != null and vm.emission_enabled:
			_emissive_mat_ids[vm.material_id] = true
	if _emissive_mat_ids.is_empty():
		print("[EmissiveBakedLight] no emissive materials — parked.")
		set_process(false)
		return

	if not ClassDB.class_exists("EmissiveBakedCpp"):
		push_warning("[EmissiveBakedLight] EmissiveBakedCpp not registered — disabled (build extensions/voxel_gen).")
		set_process(false)
		return
	_cpp = ClassDB.instantiate("EmissiveBakedCpp")
	if _cpp == null:
		push_warning("[EmissiveBakedLight] EmissiveBakedCpp instantiate failed — disabled.")
		set_process(false)
		return

	# Disable the v1 OmniLight3D-based system so we don't double-light.
	# Keep the v1 on disk + autoloaded so reverting this single autoload
	# would re-enable it cleanly.
	var v1: Node = get_node_or_null("/root/EmissiveLightManager")
	if v1 != null and "_active" in v1:
		v1.set("_active", false)
		v1.set_process(false)
		# v1 may have already spawned OmniLight3Ds; clean them up.
		if v1.has_method("_clear_state"):
			v1.call("_clear_state")
		print("[EmissiveBakedLight] disabled EmissiveLightManager v1 (OmniLight3D).")

	# Edits inside the volume should trigger a rebake on the next tick.
	if get_node_or_null("/root/VoxelEditManager") != null:
		VoxelEditManager.edit_applied.connect(_on_edit_applied)

	# Build the 256-entry color table for C++ (one pass over the registry).
	_build_mat_color_table()

	# Initialise the global texture with a 1x1x1 black image. The four
	# globals (baked_light_tex / origin / inv_volume / strength) are
	# DECLARED in project.godot under [shader_globals] — runtime code
	# only ever calls global_shader_parameter_set(). The add/get/get_list
	# APIs are editor-only and error in runtime builds.
	var black := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	black.set_pixel(0, 0, Color(0, 0, 0, 0))
	_texture = ImageTexture3D.new()
	_texture.create(Image.FORMAT_RGBA8, 1, 1, 1, false, [black])
	RenderingServer.global_shader_parameter_set(_GLOBAL_TEX, _texture)
	RenderingServer.global_shader_parameter_set(_GLOBAL_ORIGIN, Vector3.ZERO)
	RenderingServer.global_shader_parameter_set(_GLOBAL_INV_VOLUME, 0.0)
	RenderingServer.global_shader_parameter_set(_GLOBAL_STRENGTH, bake_strength)

	_active = true
	print("[EmissiveBakedLight] active — %d emissive material(s), %dx%dx%d cells × %d voxels (~%.1f m cube)." % [
		_emissive_mat_ids.size(),
		cells_per_axis, cells_per_axis, cells_per_axis,
		cell_size_voxels,
		float(cells_per_axis * cell_size_voxels) * VOXEL_SIZE_M,
	])


# Pre-resolve the per-material emission colour + energy into a 256-byte
# lookup table (256 × 4 bytes = r, g, b, energy). C++ reads this once
# per bake instead of crossing a Dictionary for every emissive voxel
# found. Energy 0 marks "not emissive — skip."
func _build_mat_color_table() -> void:
	_mat_color_table = PackedByteArray()
	_mat_color_table.resize(256 * 4)
	for mid in _emissive_mat_ids.keys():
		var vm: VoxelMaterial = VoxelMaterialRegistry.get_by_id(int(mid))
		if vm == null:
			continue
		var c: Color = vm.emission_color
		var energy: float = clampf(vm.emission_energy, 0.0, 1.0) * 255.0
		var base: int = int(mid) * 4
		_mat_color_table[base + 0] = clampi(int(c.r * 255.0), 0, 255)
		_mat_color_table[base + 1] = clampi(int(c.g * 255.0), 0, 255)
		_mat_color_table[base + 2] = clampi(int(c.b * 255.0), 0, 255)
		_mat_color_table[base + 3] = clampi(int(round(energy)), 0, 255)


func _process(delta: float) -> void:
	if not _active:
		return
	_tick_accum += delta
	if _tick_accum < _TICK_S:
		return
	_tick_accum = 0.0
	_periodic_accum += _TICK_S

	if not _resolve_terrain():
		return

	# Volume follows the player snapped to cell-grid. If the player has
	# crossed a boundary, mark dirty so the next pass slides the volume.
	var cam: Camera3D = _get_camera()
	if cam == null:
		return
	var origin_v: Vector3i = _compute_volume_origin(cam.global_position)
	if origin_v != _last_origin_v:
		_dirty = true

	# Periodic safety net.
	if _periodic_accum >= periodic_interval_s:
		_periodic_accum = 0.0
		_dirty = true

	if _dirty:
		_bake_now(origin_v)


# =============================================================
# SIGNAL HANDLERS
# =============================================================

func _on_edit_applied(_world_pos: Vector3, _chunk_coords: Vector3i, edit_aabb: AABB) -> void:
	if not _active:
		return
	# edit_aabb is in voxel-grid space. If the edit overlaps the current
	# volume, mark dirty. Cheap AABB test.
	var k: int = cell_size_voxels
	var side_v: int = cells_per_axis * k
	var vmin: Vector3 = Vector3(_last_origin_v)
	var vmax: Vector3 = vmin + Vector3(side_v, side_v, side_v)
	var volume_aabb := AABB(vmin, vmax - vmin)
	if volume_aabb.intersects(edit_aabb):
		_dirty = true


# =============================================================
# CORE BAKE
# =============================================================

func _bake_now(origin_v: Vector3i) -> void:
	var t_start: int = Time.get_ticks_usec()
	_last_origin_v = origin_v
	_dirty = false

	var n: int = cells_per_axis
	var k: int = cell_size_voxels
	var side_v: int = n * k

	# Bulk-copy the volume's CHANNEL_TYPE into a VoxelBuffer.
	if _scratch_buf == null:
		_scratch_buf = VoxelBuffer.new()
		_scratch_buf.create(side_v, side_v, side_v)
	var tool: VoxelTool = _terrain.get_voxel_tool()
	if tool == null:
		return
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	if not tool.has_method("copy"):
		return
	var type_mask: int = 1 << VoxelBuffer.CHANNEL_TYPE
	tool.copy(origin_v, _scratch_buf, type_mask)
	var t_after_copy: int = Time.get_ticks_usec()

	# C++ does emitter discovery (with the air-neighbour filter) AND
	# the BFS in one call. Pass the pre-built mat_color_table so per-
	# material colour resolution stays a single byte lookup per voxel.
	var bytes: PackedByteArray = _cpp.bake_light_volume(
		_scratch_buf, origin_v, k, n,
		_mat_color_table, air_neighbor_filter,
		max_bfs_steps, falloff_q12)
	var t_after_bake: int = Time.get_ticks_usec()

	# Upload as Z-slices into the ImageTexture3D. Re-create the texture
	# the first time we have a real (non-1^3) volume; thereafter use
	# update() to push new images into the existing GPU resource.
	var slice_byte_count: int = n * n * 4
	var images: Array[Image] = []
	images.resize(n)
	for zi in range(n):
		var slice: PackedByteArray = bytes.slice(zi * slice_byte_count, (zi + 1) * slice_byte_count)
		images[zi] = Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, slice)
	if _texture == null or _texture.get_width() != n:
		_texture = ImageTexture3D.new()
		_texture.create(Image.FORMAT_RGBA8, n, n, n, false, images)
		RenderingServer.global_shader_parameter_set(_GLOBAL_TEX, _texture)
	else:
		_texture.update(images)
	var t_after_upload: int = Time.get_ticks_usec()

	# Push the transform globals.
	var origin_world: Vector3 = Vector3(origin_v) * VOXEL_SIZE_M
	var volume_size_m: float = float(side_v) * VOXEL_SIZE_M
	RenderingServer.global_shader_parameter_set(_GLOBAL_ORIGIN, origin_world)
	RenderingServer.global_shader_parameter_set(_GLOBAL_INV_VOLUME, 1.0 / volume_size_m)
	RenderingServer.global_shader_parameter_set(_GLOBAL_STRENGTH, bake_strength)

	var t_end: int = Time.get_ticks_usec()
	if verbose or (t_end - t_start) > 20000:
		print("[EmissiveBakedLight] bake: copy=%d  bake=%d  upload=%d  globals=%d  TOTAL=%d us" % [
			t_after_copy - t_start,
			t_after_bake - t_after_copy,
			t_after_upload - t_after_bake,
			t_end - t_after_upload,
			t_end - t_start,
		])
	# Profiler attribution.
	var prof := get_node_or_null("/root/Profiler")
	if prof != null:
		prof.record("WORLD", "EmissiveBakedLight", t_end - t_start)
	if get_node_or_null("/root/HUDOverlay") != null:
		HUDOverlay.profile_record("EmissiveBakedLight", t_end - t_start)


# =============================================================
# HELPERS
# =============================================================

func _compute_volume_origin(player_pos: Vector3) -> Vector3i:
	# World position -> world voxel coord, then back off by half the
	# volume so the player sits at the volume centre, then snap to
	# cell-grid boundary so adjacent bakes share cell positions (no
	# half-cell aliasing as the player walks).
	var player_v: Vector3 = player_pos / VOXEL_SIZE_M
	var side_v: int = cells_per_axis * cell_size_voxels
	var half: int = side_v / 2
	var ox: int = int(floor(player_v.x)) - half
	var oy: int = int(floor(player_v.y)) - half
	var oz: int = int(floor(player_v.z)) - half
	# Snap each axis down to the nearest cell-size multiple. Use a
	# negatives-safe floor-div so the snap is consistent across the origin.
	var k: int = cell_size_voxels
	ox = _floor_div(ox, k) * k
	oy = _floor_div(oy, k) * k
	oz = _floor_div(oz, k) * k
	return Vector3i(ox, oy, oz)


func _floor_div(a: int, b: int) -> int:
	var q: int = a / b
	if (a % b != 0) and ((a < 0) != (b < 0)):
		q -= 1
	return q


func _resolve_terrain() -> bool:
	if _terrain != null and is_instance_valid(_terrain):
		return true
	_terrain = null
	var root: Node = get_tree().current_scene
	if root == null:
		return false
	for child in root.get_children():
		if child.get_class() == "VoxelLodTerrain" or child.get_class() == "VoxelTerrain":
			_terrain = child
			return true
	return false


func _get_camera() -> Camera3D:
	var vp: Viewport = get_viewport()
	if vp == null:
		return null
	return vp.get_camera_3d()
