extends Node3D

# Single authority for the voxel grid scale — the export default below
# mirrors the value from VoxelScale. configure() overrides it with the
# live terrain's scale anyway. See scripts/VoxelScale.gd.
const VoxelScale := preload("res://scripts/VoxelScale.gd")

# DistantTerrainManager — streams the smooth distant-terrain heightmesh.
#
# NOTE: deliberately NO `class_name`. World3DBootstrap / CopperIslesTest-
# Bootstrap load this script and instantiate it. Both bootstraps are
# parsed by the headless harness, which runs before any editor rescan —
# a `class_name` here would not be in the global class cache yet and the
# bootstraps would fail to parse. Same rule as WaterMaterial.gd /
# ShaderProfile.gd: load by path, never reference by global class name.
#
# What this is for in plain English:
#
#   The blocky Zylann voxel terrain only reaches a few hundred metres
#   around the player (the editable "near band"). Everything past that is
#   drawn by this manager: a ring of smooth heightmesh chunks, built in
#   C++ by DistantTerrainMesher from the world generator's height
#   function, that follows the player. It replaces the old baked, static
#   HorizonSkirt.
#
#   The chunks are arranged as concentric LOD rings — fine 4 m quads near
#   the player, doubling each ring out to coarse 128 m quads at the
#   horizon. Each chunk carries a vertical "skirt apron" so the rings
#   never show a crack between them, and a LOD swap cross-fades via the
#   distant_terrain.gdshader dither.
#
#   The smooth mesh is NOT rendered inside the blocky band (inner_cull_
#   radius) — so digging a deep hole near the player can never expose it.
#   In the thin overlap zone the smooth mesh sits ~1.5 m below true
#   ground (baked into DistantTerrainMesher) so the blocky terrain always
#   wins the depth test.
#
# Created and configure()'d at runtime by World3DBootstrap /
# CopperIslesTestBootstrap as a child of the (unscaled) world root — the
# mesh vertices are absolute world metres, so the manager must NOT live
# under the 1/6-scaled VoxelLodTerrain.

const _DISTANT_SHADER_PATH := "res://assets/shaders/distant_terrain.gdshader"

# --- Tunables (dialed in-editor in the Phase 5 pass) -----------------
## Number of concentric LOD rings. Ring L uses quads 2^L larger than ring 0.
@export var lod_count: int = 6
## Quad edge length of the finest ring (LOD 0), in world metres.
@export var base_quad_size: float = 4.0
## Quads per chunk edge. Chunk span(L) = base_quad_size * 2^L * this.
@export var quads_per_chunk: int = 32
## Half-extent, in chunks, of each LOD ring's square block around the player.
@export var ring_half_extent: int = 2
## No distant chunk renders fully inside this radius — the blocky band.
## ~130 m sits a touch inside the ~183 m blocky band (VoxelViewer
## view_distance 1100) so the smooth mesh overlaps the band edge with no
## gap, and well outside any range the player can dig (no dig-through).
@export var inner_cull_radius: float = 130.0
## Hard safety cap on live chunk count (a gap-causing valve; sized never to hit).
@export var max_live_chunks: int = 220
## Chunk meshes built per frame (budgeted so a boundary crossing never hitches).
@export var builds_per_frame: int = 2
## Skirt apron depth at LOD 0, in metres; doubles each ring (scales with quad).
@export var apron_base_depth: float = 8.0
## LOD-swap dither cross-fade duration, in seconds.
@export var fade_seconds: float = 0.35
## World voxels per metre — default from VoxelScale, always overridden
## by configure() which reads the live terrain's transform.scale.
## Source of truth at runtime is what configure() sets, not this default.
@export var voxels_per_metre: float = VoxelScale.VOXELS_PER_METER

# --- Runtime state ---------------------------------------------------
var _active: bool = false
var _initialized: bool = false
var _generator: Object = null          # HeightmapGeneratorBase (C++)
var _mesher: Object = null             # DistantTerrainMesher (C++)
var _shader: Shader = null
var _player: Node3D = null
# _rings[L] : Dictionary[Vector2i chunk_coord -> chunk entry].
# A chunk entry is { mi: MeshInstance3D, fade: float, fading_out: bool }.
var _rings: Array[Dictionary] = []
# Player's chunk coord per LOD level — recompute fires when one changes.
var _centers: Array[Vector2i] = []
# Pending builds: each { lod: int, coord: Vector2i }. Rebuilt on recompute.
var _build_queue: Array = []
# Freed MeshInstance3D nodes, reused to avoid per-chunk node churn.
var _pool: Array[MeshInstance3D] = []


# Convenience setup — the world bootstrap creates this node, adds it
# under its (unscaled) world root, then calls this to resolve the
# generator + scale off the VoxelLodTerrain and configure().
func setup_from_terrain(terrain: Node) -> void:
	if terrain == null:
		push_warning("[DistantTerrain] no terrain — distant terrain skipped.")
		return
	var gen = terrain.get("generator") if "generator" in terrain else null
	if gen == null:
		push_warning("[DistantTerrain] terrain has no generator — distant terrain skipped.")
		return
	# Drill adapter -> cpp_impl: the C++ DistantTerrainMesher needs the
	# real HeightmapGeneratorBase, not the GDScript VoxelGeneratorScript
	# adapter that forwards to it.
	var cpp = gen.get("cpp_impl") if "cpp_impl" in gen else gen
	# voxels-per-metre from the terrain's own scale.
	# Default from VoxelScale; overridden below if the terrain has a valid scale.
	var vpm := VoxelScale.VOXELS_PER_METER
	if terrain is Node3D:
		var sx: float = (terrain as Node3D).transform.basis.get_scale().x
		if sx > 0.0:
			vpm = 1.0 / sx
	configure(cpp, vpm)


# Called once by setup_from_terrain. `generator` must be a
# HeightmapGeneratorBase (the C++ cpp_impl, not the GDScript adapter).
func configure(generator: Object, vpm: float) -> void:
	_generator = generator
	if vpm > 0.0:
		voxels_per_metre = vpm
	if not ClassDB.class_exists("DistantTerrainMesher"):
		push_warning("[DistantTerrain] DistantTerrainMesher (C++) not registered — distant terrain disabled. Build extensions/voxel_gen.")
		return
	_mesher = ClassDB.instantiate("DistantTerrainMesher")
	_shader = load(_DISTANT_SHADER_PATH) as Shader
	if _mesher == null or _shader == null or _generator == null:
		push_warning("[DistantTerrain] missing mesher / shader / generator — disabled.")
		return
	_rings.clear()
	_centers.clear()
	for _l in lod_count:
		_rings.append({})
		_centers.append(Vector2i.ZERO)
	_active = true
	print("[DistantTerrain] active — %d LOD rings, base quad %.0f m, %d quads/chunk, inner cull %.0f m." % [
		lod_count, base_quad_size, quads_per_chunk, inner_cull_radius])


func _process(delta: float) -> void:
	# Wrapper instrumentation (added 2026-05-25). The capture of 71343 ms
	# / 14614 frames showed 100+ ms main-thread spike CLUSTERS during
	# fast traversal — 25 consecutive frames at 90-174 ms each — where
	# zylann.detect/io/mesh totalled ~0.4 ms and wrapped-script
	# attribution totalled ~6 ms. The 160+ ms gap matched our own
	# DistantTerrain build pattern (recompute on boundary cross →
	# many chunks queued → drained at builds_per_frame from this
	# unwrapped _process). The wrap pattern below (Time.get_ticks_usec
	# outer + Profiler.record + HUDOverlay.profile_record) matches every
	# other autoload's instrumentation and adds ~1-2 µs per frame.
	# Records the WHOLE _process tick — finer attribution (recompute vs
	# build_queue vs fades) is one inner-wrap pass away if the next
	# capture shows it's needed, but step 1 is just confirming
	# DistantTerrain owns the gap.
	var _t0: int = Time.get_ticks_usec()
	_process_inner(delta)
	var _elapsed: int = Time.get_ticks_usec() - _t0
	HUDOverlay.profile_record("DistantTerrain", _elapsed)
	var prof: Node = get_node_or_null("/root/Profiler")
	if prof != null:
		prof.record("WORLD", "DistantTerrain", _elapsed)


func _process_inner(delta: float) -> void:
	if not _active:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var p: Vector3 = _player.global_position
	var player_xz := Vector2(p.x, p.z)
	if _need_recompute(player_xz):
		_recompute(player_xz)
	_process_build_queue()
	_update_fades(delta)


# --- Ring geometry ---------------------------------------------------
func _quad_size(lod: int) -> float:
	return base_quad_size * float(1 << lod)


func _chunk_span(lod: int) -> float:
	return _quad_size(lod) * float(quads_per_chunk)


func _apron_depth(lod: int) -> float:
	return apron_base_depth * float(1 << lod)


# --- Recentering -----------------------------------------------------
func _need_recompute(player_xz: Vector2) -> bool:
	if not _initialized:
		return true
	for lod in lod_count:
		var span := _chunk_span(lod)
		var c := Vector2i(floori(player_xz.x / span), floori(player_xz.y / span))
		if c != _centers[lod]:
			return true
	return false


# Recompute the desired chunk set for every LOD ring. Runs only when the
# player crosses a chunk boundary. Rebuilds the build queue from scratch
# (so a chunk that became undesired while still queued is simply dropped),
# and marks now-undesired live chunks to fade out.
func _recompute(player_xz: Vector2) -> void:
	var centers: Array[Vector2i] = []
	for lod in lod_count:
		var span := _chunk_span(lod)
		centers.append(Vector2i(floori(player_xz.x / span), floori(player_xz.y / span)))

	_build_queue.clear()
	for lod in lod_count:
		var c: Vector2i = centers[lod]
		var desired := {}
		for dz in range(-ring_half_extent, ring_half_extent + 1):
			for dx in range(-ring_half_extent, ring_half_extent + 1):
				var coord := Vector2i(c.x + dx, c.y + dz)
				if _chunk_culled(lod, coord, centers, player_xz):
					continue
				desired[coord] = true
				if _rings[lod].has(coord):
					# Already live — make sure it is not retiring.
					(_rings[lod][coord] as Dictionary)["fading_out"] = false
				else:
					_build_queue.append({"lod": lod, "coord": coord})
		# Live chunks no longer desired: fade them out.
		for coord in _rings[lod].keys():
			if not desired.has(coord):
				(_rings[lod][coord] as Dictionary)["fading_out"] = true

	# Build nearest chunks first.
	_build_queue.sort_custom(_compare_build_dist.bind(player_xz))
	_centers = centers
	_initialized = true


# True when this LOD-`lod` chunk should NOT render: either it sits fully
# inside the blocky-band inner cull (LOD 0 only) or it is fully covered
# by the next finer LOD ring's block (LOD > 0).
func _chunk_culled(lod: int, coord: Vector2i, centers: Array, player_xz: Vector2) -> bool:
	var span := _chunk_span(lod)
	var cmin := Vector2(float(coord.x) * span, float(coord.y) * span)
	var cmax := cmin + Vector2(span, span)
	if lod == 0:
		var imin := player_xz - Vector2(inner_cull_radius, inner_cull_radius)
		var imax := player_xz + Vector2(inner_cull_radius, inner_cull_radius)
		return cmin.x >= imin.x and cmin.y >= imin.y and cmax.x <= imax.x and cmax.y <= imax.y
	# Covered by the finer ring (LOD lod-1) iff fully inside its block.
	var fspan := _chunk_span(lod - 1)
	var fc: Vector2i = centers[lod - 1]
	var fmin := Vector2(
		float(fc.x - ring_half_extent) * fspan,
		float(fc.y - ring_half_extent) * fspan)
	var fmax := Vector2(
		float(fc.x + ring_half_extent + 1) * fspan,
		float(fc.y + ring_half_extent + 1) * fspan)
	return cmin.x >= fmin.x and cmin.y >= fmin.y and cmax.x <= fmax.x and cmax.y <= fmax.y


func _compare_build_dist(a: Dictionary, b: Dictionary, player_xz: Vector2) -> bool:
	return _queue_dist(a, player_xz) < _queue_dist(b, player_xz)


func _queue_dist(item: Dictionary, player_xz: Vector2) -> float:
	var lod: int = item["lod"]
	var coord: Vector2i = item["coord"]
	var span := _chunk_span(lod)
	var center := Vector2((float(coord.x) + 0.5) * span, (float(coord.y) + 0.5) * span)
	return center.distance_to(player_xz)


# --- Build queue -----------------------------------------------------
func _process_build_queue() -> void:
	var built := 0
	while built < builds_per_frame and not _build_queue.is_empty():
		if _count_live() >= max_live_chunks:
			break
		var item: Dictionary = _build_queue.pop_front()
		var lod: int = item["lod"]
		var coord: Vector2i = item["coord"]
		if _rings[lod].has(coord):
			continue
		_build_chunk(lod, coord)
		built += 1


func _build_chunk(lod: int, coord: Vector2i) -> void:
	var span := _chunk_span(lod)
	var min_xz := Vector2(float(coord.x) * span, float(coord.y) * span)
	var max_xz := min_xz + Vector2(span, span)
	var d = _mesher.call("build_chunk", _generator, min_xz, max_xz,
		_quad_size(lod), voxels_per_metre, _apron_depth(lod))
	if typeof(d) != TYPE_DICTIONARY or (d as Dictionary).is_empty():
		return
	var mesh := _mesh_from_dict(d)
	if mesh.get_surface_count() == 0:
		return
	var mi := _acquire_mi()
	mi.mesh = mesh
	(mi.material_override as ShaderMaterial).set_shader_parameter("fade_factor", 0.0)
	_rings[lod][coord] = {"mi": mi, "fade": 0.0, "fading_out": false}


func _mesh_from_dict(d: Dictionary) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = d.get("vertices", PackedVector3Array())
	arrays[Mesh.ARRAY_NORMAL] = d.get("normals", PackedVector3Array())
	arrays[Mesh.ARRAY_COLOR] = d.get("colors", PackedColorArray())
	arrays[Mesh.ARRAY_INDEX] = d.get("indices", PackedInt32Array())
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- LOD-swap cross-fade ---------------------------------------------
func _update_fades(delta: float) -> void:
	var step: float = delta / maxf(fade_seconds, 0.001)
	for lod in lod_count:
		var ring: Dictionary = _rings[lod]
		var to_free: Array = []
		for coord in ring.keys():
			var e: Dictionary = ring[coord]
			var fade: float = e["fade"]
			if e["fading_out"]:
				fade -= step
				if fade <= 0.0:
					to_free.append(coord)
					continue
			elif fade < 1.0:
				fade = minf(1.0, fade + step)
			e["fade"] = fade
			((e["mi"] as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("fade_factor", fade)
		for coord in to_free:
			_release_mi((ring[coord] as Dictionary)["mi"])
			ring.erase(coord)


# --- MeshInstance3D pool ---------------------------------------------
func _acquire_mi() -> MeshInstance3D:
	var mi: MeshInstance3D
	if not _pool.is_empty():
		mi = _pool.pop_back()
		mi.visible = true
		return mi
	mi = MeshInstance3D.new()
	# Distant terrain does not cast shadows — far away and low payoff;
	# it still RECEIVES the sun + shadows (automatic in a spatial shader).
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mi.material_override = mat
	add_child(mi)
	return mi


func _release_mi(mi: MeshInstance3D) -> void:
	mi.visible = false
	mi.mesh = null
	_pool.append(mi)


func _count_live() -> int:
	var n := 0
	for ring in _rings:
		n += (ring as Dictionary).size()
	return n
