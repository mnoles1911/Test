extends Node3D

# FarGrassManager — the far-grass impostor layer.
#
# THE PROBLEM (plain English):
#   R4 ships REAL destructible voxel grass + flowers (ids 24..26), but the
#   C++ generator only scatters them at LOD0 — roughly a 12.8 m ring around
#   the player (the Zylann LOD0 cap at 10 vox/m). Past that ring the lawn
#   just STOPS, leaving a visible "bald ring" where the meadow ends in a
#   hard circle. Standing in a field, you see a haircut line ~12.8 m out.
#
# THE FIX (designer-approved):
#   A non-interactive, GPU-instanced grass layer that covers the LOD1/LOD2
#   bands (~13..51 m) so the lawn appears to continue out to the horizon.
#   These blades are cosmetic only — no collision, no digging, no sim. They
#   exist purely to hide the seam.
#
# THE MAGIC — continuity with the real grass:
#   The impostor blades are placed using the EXACT SAME deterministic hash
#   the C++ generator uses to decide real grass (hash3(world_x, 0,
#   world_z, flora_seed) < 0.37 → grass; see heightmap_generator_base.cpp).
#   So when the player walks toward a far blade, the moment it crosses into
#   the LOD0 ring and the real voxel grass takes over, a REAL blade is
#   already standing in the same spot. The handoff is invisible: the field
#   never "rebuilds itself" as you approach — the far grass simply becomes
#   near grass. That continuity is the whole point.
#
# HOW IT'S BUILT:
#   The XZ plane around the player is divided into a fixed grid of square
#   "impostor chunks". A ring of chunks whose centres fall in the [inner,
#   outer] radius band is kept live; each live chunk owns one
#   MultiMeshInstance3D holding every impostor blade in that chunk. As the
#   player moves, chunks that leave the band are freed (their MultiMesh
#   nodes pooled + reused) and new chunks entering the band are built — a
#   few per frame so a fast sprint never hitches. This mirrors the
#   chunk-ring-follows-player pattern in DistantTerrainManager.
#
# GROUND HEIGHT + GRASSLAND TEST:
#   Each candidate blade column asks the generator get_ground_voxel_y_at(wx,
#   wz) for the surface voxel Y (a pure, cheap height function — worker-safe
#   and main-thread-safe). "Is this grassland?" is APPROXIMATED as
#   "above sea level and below the snow line" — the generator's full
#   grassland test also excludes cliffs and clay/gravel disks, but those
#   are invisible distinctions on a 10cm blade 13..51 m away, and replaying
#   them here would mean a second copy of the cliff/disk math drifting out
#   of sync with C++. The approximation is documented and deliberate: a few
#   stray far blades on a distant cliff lip is unnoticeable; a bald ring is
#   not. When the player walks close, the real generator (which DOES run the
#   full test) is authoritative, so any approximation error self-corrects at
#   the LOD0 handoff (the far blade vanishes if the real column had none).
#
# TOGGLE:
#   GraphicsManager.far_grass_enabled gates the whole layer. Default ON —
#   this is the one exception to the repo's "new visual layers default OFF"
#   rule, because it exists to FIX a seam in an already-shipped default-ON
#   feature (R4 grass) and the designer explicitly approved it ON. Flipping
#   it off is instant: the manager hides + frees its chunks and stops
#   rebuilding (the bald ring returns — useful for A/B'ing the fix).
#
# NO class_name (headless-safe, same rule as DistantTerrainManager /
# VoxelScale / FloraMaterial): loaded by path from World3DBootstrap.

const VoxelScale := preload("res://scripts/VoxelScale.gd")
const FloraMaterial := preload("res://scripts/FloraMaterial.gd")

const _SWAY_SHADER_PATH: String = "res://assets/shaders/flora_sway.gdshader"

# --- Tunables --------------------------------------------------------
## Inner radius of the impostor band, in world metres. Sits at the LOD0
## edge (~12.8 m at 10 vox/m) so the impostor grass starts exactly where
## the real grass stops — no overlap doubling, no gap.
@export var inner_radius_m: float = 12.8
## Outer radius of the impostor band, in world metres. The LOD2 ring ends
## at ~51.2 m (PATTERNS_AND_GOTCHAS terrain-collision table); past that the
## distant smooth heightmesh takes over and individual blades are sub-pixel.
@export var outer_radius_m: float = 51.2
## Edge length of one impostor chunk, in world metres. Smaller = finer ring
## fit + smaller per-rebuild cost, but more MultiMeshInstance3D nodes.
@export var chunk_size_m: float = 8.0
## Stride between candidate blade columns, in world metres. The real LOD0
## grass is per-voxel (0.1 m); sampling EVERY voxel column out to 51 m would
## be ~800k candidates. We sample on a coarser lattice (every Nth voxel) so
## the far field reads as dense without the instance count exploding. The
## stride is in WHOLE VOXELS so candidate columns land on real voxel
## centres — the same integer (wx,wz) the generator hashes — preserving the
## walk-in continuity. See _voxel_stride.
##
## BUDGET MATH: band area ≈ π(51.2² − 12.8²) ≈ 7720 m². At stride 3 (0.3 m
## spacing) that's ~11 columns/m², and ~35% roll grass, so ~30k blades —
## comfortably under max_total_instances (40k) so the ring fully populates
## to its outer edge instead of getting clamped. stride 2 (0.2 m) would
## overflow the cap (~67k) and leave the outer band sparse.
@export var sample_stride_voxels: int = 3
## Hard cap on TOTAL live impostor instances across all chunks. A safety
## valve: if the band + density would exceed this, per-chunk builds bail
## early (a slightly sparser far field beats a memory/time blowout). Sized
## to land in the 20..40k blades the budget allows.
@export var max_total_instances: int = 40000
## Impostor chunks built per frame. Budgeted so a boundary crossing never
## drops a frame — the ring fills in over a few frames as you move.
@export var builds_per_frame: int = 2
## Grass density gate: a candidate column grows an impostor blade when its
## generator hash roll is below this. MUST match the C++ generator's grass
## band [0.02 .. 0.37) total ~35%; we fold flowers in too (roll < 0.37
## covers both the flower sub-band and the grass sub-band) so the far field
## density reads like the real scatter. See _column_has_grass.
@export var grass_roll_threshold: float = 0.37

# --- Runtime state ---------------------------------------------------
var _active: bool = false               # configured + enabled
var _enabled: bool = true               # GraphicsManager toggle mirror
var _generator: Object = null           # HeightmapGeneratorBase (C++ cpp_impl)
var _graphics: Node = null              # cached GraphicsManager autoload (toggle source)
var _player: Node3D = null
var _sway_material: ShaderMaterial = null
var _blade_mesh: Mesh = null

# Generator params snapshotted at configure() so the worker-safe hash math
# matches the live generator exactly (these are the values the C++ scatter
# uses; reading them once avoids a Variant call per candidate column).
var _flora_seed: int = 1337
var _sea_level_voxels: int = 120
var _snow_line_voxels: int = 30000
var _voxels_per_metre: float = VoxelScale.VOXELS_PER_METER

# Live chunks: Dictionary[Vector2i chunk_coord -> MultiMeshInstance3D].
var _chunks: Dictionary = {}
# Player chunk coord at last recompute — recompute fires when it changes.
var _last_center: Vector2i = Vector2i(0x7fffffff, 0x7fffffff)
# Pending chunk builds (Vector2i coords), drained builds_per_frame/frame.
var _build_queue: Array[Vector2i] = []
# Freed MultiMeshInstance3D nodes, reused to avoid per-chunk node churn.
var _pool: Array[MultiMeshInstance3D] = []
# Running total of live instances (kept in lockstep with chunk adds/frees).
var _live_instances: int = 0


# Convenience setup — World3DBootstrap creates this node under the
# (unscaled) world root and calls this. Mirrors
# DistantTerrainManager.setup_from_terrain: drills the adapter -> cpp_impl
# to reach the real HeightmapGeneratorBase whose get_ground_voxel_y_at we
# call, and resolves voxels-per-metre off the terrain's own scale.
func setup_from_terrain(terrain: Node) -> void:
	if terrain == null:
		push_warning("[FarGrass] no terrain — far grass skipped.")
		return
	var gen = terrain.get("generator") if "generator" in terrain else null
	if gen == null:
		push_warning("[FarGrass] terrain has no generator — far grass skipped.")
		return
	# adapter (VoxelGeneratorScript) -> cpp_impl (HeightmapGeneratorBase).
	var cpp = gen.get("cpp_impl") if "cpp_impl" in gen else gen
	var vpm := VoxelScale.VOXELS_PER_METER
	if terrain is Node3D:
		var sx: float = (terrain as Node3D).transform.basis.get_scale().x
		if sx > 0.0:
			vpm = 1.0 / sx
	configure(cpp, vpm)


# Resolve generator params + build the shared blade mesh/material, then go
# live. `generator` must be the C++ HeightmapGeneratorBase (cpp_impl).
func configure(generator: Object, vpm: float) -> void:
	_generator = generator
	if vpm > 0.0:
		_voxels_per_metre = vpm
	if _generator == null or not _generator.has_method("get_ground_voxel_y_at"):
		push_warning("[FarGrass] generator missing get_ground_voxel_y_at — far grass disabled.")
		return
	# Snapshot the generator's flora/biome params so our hash matches the
	# C++ scatter byte-for-byte. Read-back with defaults if a getter is
	# missing (older build) so we never crash on a partial API.
	if "flora_seed" in _generator:
		_flora_seed = int(_generator.get("flora_seed"))
	if "sea_level_voxels" in _generator:
		_sea_level_voxels = int(_generator.get("sea_level_voxels"))
	if "snow_line_voxels" in _generator:
		_snow_line_voxels = int(_generator.get("snow_line_voxels"))

	_blade_mesh = _build_impostor_blade_mesh()
	_sway_material = _build_sway_material()
	if _blade_mesh == null or _sway_material == null:
		push_warning("[FarGrass] could not build blade mesh / sway material — far grass disabled.")
		return

	# Mirror GraphicsManager's toggle (default ON for this layer — see the
	# header). Cache the node + subscribe so a runtime flip is instant. We
	# hold the reference rather than re-resolving the autoload path each
	# time, so the toggle handler doesn't depend on path lookups.
	_graphics = get_node_or_null("/root/GraphicsManager")
	if _graphics != null:
		if "far_grass_enabled" in _graphics:
			_enabled = bool(_graphics.get("far_grass_enabled"))
		if _graphics.has_signal("effect_toggles_changed") \
				and not _graphics.effect_toggles_changed.is_connected(_on_toggles_changed):
			_graphics.effect_toggles_changed.connect(_on_toggles_changed)

	_active = true
	print("[FarGrass] active — band %.1f..%.1f m, chunk %.0f m, stride %d vox, seed %d, enabled=%s." % [
		inner_radius_m, outer_radius_m, chunk_size_m, sample_stride_voxels, _flora_seed, str(_enabled)])


# GraphicsManager toggle changed — apply instantly.
func _on_toggles_changed() -> void:
	if _graphics == null or not is_instance_valid(_graphics) \
			or not ("far_grass_enabled" in _graphics):
		return
	var want := bool(_graphics.get("far_grass_enabled"))
	if want == _enabled:
		return
	_enabled = want
	if not _enabled:
		# Instant off: free every chunk, clear the queue, reset the center
		# so re-enabling rebuilds the full ring around the player.
		_clear_all_chunks()
		_build_queue.clear()
		_last_center = Vector2i(0x7fffffff, 0x7fffffff)
		print("[FarGrass] disabled — impostor layer freed (bald ring returns).")
	else:
		# Instant on: next _process recompute rebuilds the ring.
		_last_center = Vector2i(0x7fffffff, 0x7fffffff)
		print("[FarGrass] enabled — impostor layer will rebuild around the player.")


func _process(_delta: float) -> void:
	# Per-autoload-style perf attribution (PATTERNS_AND_GOTCHAS recipe).
	var _t0: int = Time.get_ticks_usec()
	_process_inner()
	var _elapsed: int = Time.get_ticks_usec() - _t0
	var hud := get_node_or_null("/root/HUDOverlay")
	if hud != null and hud.has_method("profile_record"):
		hud.profile_record("FarGrass", _elapsed)
	var prof := get_node_or_null("/root/Profiler")
	if prof != null:
		prof.record("WORLD", "FarGrass", _elapsed)


func _process_inner() -> void:
	if not _active or not _enabled:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var p: Vector3 = _player.global_position
	var center := _world_to_chunk(p.x, p.z)
	if center != _last_center:
		_last_center = center
		_recompute(center)
	_drain_build_queue()


# --- Ring geometry ---------------------------------------------------

func _world_to_chunk(wx: float, wz: float) -> Vector2i:
	return Vector2i(int(floor(wx / chunk_size_m)), int(floor(wz / chunk_size_m)))


# Recompute which chunks should be live for this player center: free the
# ones that left the band, queue the ones that entered it. Cheap — only
# touches the small set of chunks within the outer radius.
func _recompute(center: Vector2i) -> void:
	# Chunk-radius the outer band spans (+1 so a chunk straddling the edge
	# still counts).
	var reach: int = int(ceil(outer_radius_m / chunk_size_m)) + 1
	var wanted: Dictionary = {}
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var coord := center + Vector2i(dx, dz)
			if _chunk_in_band(center, coord):
				wanted[coord] = true

	# Free chunks no longer wanted.
	for coord in _chunks.keys():
		if not wanted.has(coord):
			_free_chunk(coord)

	# Queue chunks newly wanted (not live, not already queued).
	_build_queue.clear()
	for coord in wanted.keys():
		if not _chunks.has(coord):
			_build_queue.append(coord)
	# Build nearest-first so the ring fills in around the player outward.
	_build_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - center).length_squared() < (b - center).length_squared())


# True when chunk `coord`'s nearest point to the player's chunk centre
# falls inside the outer radius AND its farthest point reaches past the
# inner radius (i.e. the chunk overlaps the [inner, outer] band at all).
func _chunk_in_band(center: Vector2i, coord: Vector2i) -> bool:
	# Player position approximated as the centre of its chunk for the band
	# test (cheap; the per-blade ground/grass test is exact later).
	var pc := Vector2(
		(float(center.x) + 0.5) * chunk_size_m,
		(float(center.y) + 0.5) * chunk_size_m)
	var lo := Vector2(float(coord.x) * chunk_size_m, float(coord.y) * chunk_size_m)
	var hi := lo + Vector2(chunk_size_m, chunk_size_m)
	# Nearest point of the chunk AABB to the player centre.
	var nx: float = clampf(pc.x, lo.x, hi.x)
	var nz: float = clampf(pc.y, lo.y, hi.y)
	var near_d: float = Vector2(nx, nz).distance_to(pc)
	if near_d > outer_radius_m:
		return false
	# Farthest corner distance — if even the farthest corner is inside the
	# inner radius, the whole chunk is in the LOD0 zone (real grass), skip.
	var far_d: float = 0.0
	for cx in [lo.x, hi.x]:
		for cz in [lo.y, hi.y]:
			far_d = maxf(far_d, Vector2(cx, cz).distance_to(pc))
	return far_d > inner_radius_m


# --- Build queue -----------------------------------------------------

func _drain_build_queue() -> void:
	var had_work: bool = not _build_queue.is_empty()
	var built: int = 0
	while built < builds_per_frame and not _build_queue.is_empty():
		var coord: Vector2i = _build_queue.pop_front()
		if not _chunks.has(coord):
			_build_chunk(coord)
		built += 1
	# Log the live instance total the moment the ring finishes filling after
	# a recompute — the designer/perf evidence for the impostor budget.
	if had_work and _build_queue.is_empty():
		print("[FarGrass] ring settled — %d live blade instances across %d chunk(s) (cap %d)." % [
			_live_instances, _chunks.size(), max_total_instances])


# Build one impostor chunk: scatter blades on the generator's grass hash,
# query ground height per column, pack them into a MultiMesh. Skips columns
# that aren't grassland or already sit inside the LOD0 ring (real grass).
func _build_chunk(coord: Vector2i) -> void:
	if _live_instances >= max_total_instances:
		return  # budget hit — leave this chunk empty rather than blow the cap.

	var stride: int = _voxel_stride()
	# Voxel-space bounds of this chunk (integer voxel columns — the same
	# (wx,wz) the generator hashes, so impostor positions match real grass).
	var vx0: int = int(floor((float(coord.x) * chunk_size_m) * _voxels_per_metre))
	var vz0: int = int(floor((float(coord.y) * chunk_size_m) * _voxels_per_metre))
	var vx1: int = int(ceil((float(coord.x + 1) * chunk_size_m) * _voxels_per_metre))
	var vz1: int = int(ceil((float(coord.y + 1) * chunk_size_m) * _voxels_per_metre))
	# Snap the start to the global stride lattice so chunk seams don't drop
	# or double a column (the lattice is world-global, not chunk-local).
	vx0 -= ((vx0 % stride) + stride) % stride
	vz0 -= ((vz0 % stride) + stride) % stride

	var player_xz := Vector2(0, 0)
	if _player != null and is_instance_valid(_player):
		player_xz = Vector2(_player.global_position.x, _player.global_position.z)

	var transforms: Array[Transform3D] = []
	var vz: int = vz0
	while vz < vz1:
		var vx: int = vx0
		while vx < vx1:
			if _column_has_grass(vx, vz):
				# World-metre position of this voxel column's centre.
				var wx: float = (float(vx) + 0.5) / _voxels_per_metre
				var wz: float = (float(vz) + 0.5) / _voxels_per_metre
				var d: float = Vector2(wx, wz).distance_to(player_xz)
				# Per-blade band test (exact — the chunk test was coarse).
				# Only emit in [inner, outer]: inside inner the real grass
				# owns it, past outer it's sub-pixel.
				if d >= inner_radius_m and d <= outer_radius_m:
					var gy: int = _ground_voxel_y(vx, vz)
					if gy > _sea_level_voxels and gy < _snow_line_voxels:
						# Blade sits on TOP of the surface voxel — one voxel
						# above ground, the same cell the generator writes the
						# real blade into (world_y == ground_y + 1).
						var wy: float = (float(gy) + 1.0) / _voxels_per_metre
						transforms.append(_blade_transform(wx, wy, wz, vx, vz))
						if _live_instances + transforms.size() >= max_total_instances:
							break
			vx += stride
		if _live_instances + transforms.size() >= max_total_instances:
			break
		vz += stride

	if transforms.is_empty():
		# Nothing to draw here — record an empty entry so we don't re-queue
		# this coord every recompute (keys() drives the free pass).
		_chunks[coord] = null
		return

	var mmi: MultiMeshInstance3D = _acquire_mmi()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _blade_mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	mmi.multimesh = mm
	mmi.material_override = _sway_material
	mmi.visible = true
	# Far grass casts no shadow — 40k tiny shadow casters would be a heavy,
	# invisible cost at this distance.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_chunks[coord] = mmi
	_live_instances += transforms.size()


# Per-blade world transform: position + a small deterministic yaw + height
# jitter so the field doesn't look like a stamped grid. The yaw/scale seed
# off the SAME (vx,vz) so it's stable across rebuilds (a blade doesn't spin
# when you re-enter a chunk) and matches nothing the generator does (the
# generator's blades are axis-aligned cross-quads; a little yaw variety on
# the impostor reads richer at distance and the handoff hides it).
func _blade_transform(wx: float, wy: float, wz: float, vx: int, vz: int) -> Transform3D:
	var yaw: float = _hash3(vx, 7, vz, _flora_seed) * TAU
	var sc: float = 0.85 + 0.3 * _hash3(vx, 9, vz, _flora_seed)
	var b := Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc))
	return Transform3D(b, Vector3(wx, wy, wz))


# --- Grass / ground queries -----------------------------------------

# True when the generator would scatter GRASS or a FLOWER on this column.
# Replays the C++ generator's exact first hash roll
# (hash3(world_x, 0, world_z, flora_seed)): roll < 0.37 covers BOTH the
# flower sub-band [0..0.02) and the grass sub-band [0.02..0.37). We draw a
# grass blade for all of them — at 13..51 m a far flower reads as a green
# speck anyway, and using the same single roll guarantees the density and
# POSITIONS match the real scatter exactly (the continuity magic).
func _column_has_grass(vx: int, vz: int) -> bool:
	return _hash3(vx, 0, vz, _flora_seed) < grass_roll_threshold


# Surface voxel Y for a column via the generator's pure height function.
func _ground_voxel_y(vx: int, vz: int) -> int:
	return int(_generator.call("get_ground_voxel_y_at", vx, vz))


# Sample stride in WHOLE voxels (>=1). Sampling every Nth voxel column keeps
# the far-field instance count sane while landing every candidate on a real
# voxel centre the generator hashes.
func _voxel_stride() -> int:
	return maxi(1, sample_stride_voxels)


# Deterministic hash mirroring scripts/VoxelGenerationMath.gd hash3 AND the
# C++ voxel_gen::math::hash3 — bit-identical so impostor grass lands exactly
# where the real generator grass will. Triple-prime XOR, masked to 24 bits,
# normalised to [0,1].
func _hash3(x: int, y: int, z: int, seed: int) -> float:
	var h: int = ((x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (seed * 39916801)) & 0xFFFFFF
	return float(h) / float(0xFFFFFF)


# --- Mesh + material builders ---------------------------------------

# Build the impostor blade mesh. It MUST look like the real LOD0 flora, so
# it reuses the EXACT cross-quad builder from World3DBootstrap (extracted to
# a static so there is one source of truth for blade geometry). Same height,
# half-width, and grass tint as the real grass_blade model (id 24).
func _build_impostor_blade_mesh() -> Mesh:
	const FloraMeshBuilder := preload("res://scripts/FloraMeshBuilder.gd")
	# These three numbers mirror the grass_blade spec in
	# World3DBootstrap._inject_flora_models_into_library. Kept in sync by
	# both reading the same intent: a ~25 cm blade, grass-green.
	var height_m: float = 0.25
	var half_width_m: float = 0.05
	var color := Color(0.40, 0.56, 0.23)
	# The real flora mesh is built in CUBE-LOCAL voxel units (a unit cube =
	# one voxel). The impostor lives in WORLD space (MultiMesh transforms are
	# world metres), so we ask the builder for a WORLD-METRE mesh: same shape,
	# scaled to real size. The builder's world_scale flag does exactly that.
	return FloraMeshBuilder.build_cross_quad(
		height_m, half_width_m, color, _voxels_per_metre, true)


# Build the shared wind-sway ShaderMaterial used by every impostor chunk.
func _build_sway_material() -> ShaderMaterial:
	var sh := load(_SWAY_SHADER_PATH) as Shader
	if sh == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.resource_name = "far_grass_sway"
	# The impostor blade mesh is built in WORLD metres ~0.25 m tall (see
	# _build_impostor_blade_mesh). Tell the sway shader that height so it
	# normalises the bend weight to a clean 0..1 along the blade — matching
	# how the real LOD0 flora is normalised (its uniform is 0.92 voxel).
	# Same world-metre amplitude → near and far blades sway identically.
	mat.set_shader_parameter("blade_local_height", 0.25)
	return mat


# --- Node pool / teardown -------------------------------------------

func _acquire_mmi() -> MultiMeshInstance3D:
	var mmi: MultiMeshInstance3D
	if not _pool.is_empty():
		mmi = _pool.pop_back()
	else:
		mmi = MultiMeshInstance3D.new()
		add_child(mmi)
	mmi.visible = true
	return mmi


func _free_chunk(coord: Vector2i) -> void:
	var mmi = _chunks.get(coord, null)
	_chunks.erase(coord)
	if mmi == null:
		return
	if mmi.multimesh != null:
		_live_instances -= mmi.multimesh.instance_count
		mmi.multimesh = null
	mmi.visible = false
	_pool.append(mmi)


func _clear_all_chunks() -> void:
	for coord in _chunks.keys():
		var mmi = _chunks[coord]
		if mmi != null:
			if mmi.multimesh != null:
				mmi.multimesh = null
			mmi.visible = false
			_pool.append(mmi)
	_chunks.clear()
	_live_instances = 0
