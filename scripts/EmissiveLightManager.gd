extends Node
# ======================================================================
# DEPRECATED — v1 OmniLight3D-streaming emissive system.
#
# Superseded by `EmissiveBakedLightManager` (Phase J v2) which BFS-
# floodfills a 3D `ImageTexture3D` the terrain shader samples. The baked
# system disables this one at startup (`EmissiveBakedLight] disabled
# EmissiveLightManager v1` log line).
#
# Kept on disk as a FALLBACK only — used if EmissiveBakedCpp DLL is
# missing. Do NOT extend this file for new emissive features. New work
# goes into `scripts/EmissiveBakedLightManager.gd` +
# `extensions/voxel_gen/src/emissive_baked_cpp.{h,cpp}`.
#
# Known v1 cosmetic limitation that motivated the v2 supersession:
# shadowless cluster lights bled brightness up through terrain (light
# leaked across walls). Phase J fixes this by construction (BFS stops
# at solid voxels) — see PR #241 receipt in `memory/`.
# ======================================================================
#
# EmissiveLightManager — emissive voxels cast coloured light.
#
# Phase J of the graphics roadmap (design/GRAPHICS_PASS_2026-05-19.md).
#
# What this does in plain English:
#
#   Some voxel materials are flagged "emissive" (VoxelMaterial.gd —
#   emission_enabled). A glowing ore vein, a lava block, a placed
#   light-stone. Phase I makes the SURFACE of such a voxel glow; this
#   manager makes it actually LIGHT THE WORLD around it — it drops a
#   coloured OmniLight3D on each cluster of emissive voxels, so a
#   copper vein you mine into washes the tunnel in warm amber, casts
#   real light on the floor and walls, and bleeds colour via SSIL.
#
# How it finds emissive voxels (no world-wide scan — that would be the
# multi-million-voxel cost the roadmap flagged):
#
#   1. EDIT-DRIVEN (primary). It listens to VoxelEditManager.edit_applied
#      and bulk-reads just the small region around each edit. Mine into
#      a glowing vein -> the exposed voxels light up; place a glowing
#      block -> it lights up; mine a glowing voxel away -> its light
#      goes out.
#   2. PERIODIC vicinity sweep (secondary). Every few seconds it
#      bulk-reads a modest box around the player, so emissive voxels in
#      a natural cave the player walks into (no edit) also light up.
#
#   Both paths share _scan_region(). Voxels are read with Zylann's
#   VoxelTool.copy() — one C++ call per region, then we iterate the
#   in-process buffer. This is the same fast bulk-read VoxelGravity
#   Manager uses; the slow path is the per-voxel GDScript<->native
#   crossing, which copy() avoids.
#
# Architecture note (why no C++ / no baked light texture):
#
#   The graphics roadmap sketched Phase J as a C++ BFS floodfill baking
#   light into a 3D texture the terrain shader samples — the Minecraft
#   technique. Minecraft needs that because it has no real-time lighting
#   engine. This game runs Forward+, whose clustered renderer handles
#   many dynamic lights cheaply. So coloured voxel light is delivered
#   the engine-native way: real OmniLight3Ds. They cast and interact
#   with shadows / SSIL / AgX like every other light. Trade-off vs. the
#   baked approach: light is line-of-sight (a wall blocks it) and does
#   NOT wrap around corners the Minecraft way. Chosen deliberately —
#   see design/GRAPHICS_PASS_2026-05-19.md → Phase J.
#
# Registered as an autoload AFTER VoxelEditManager (so edit_applied
# exists when we connect) and after VoxelMaterialRegistry (so the
# emissive-material set can be built).


# =============================================================
# CONFIGURATION (tunable in the Inspector / project autoload)
# =============================================================

@export var enabled: bool = true
# Master kill-switch. Turn off to rule the system out while debugging.

@export_range(2, 12, 1) var cell_size_voxels: int = 5
# Emissive voxels are clustered onto a coarse grid this many voxels
# wide; one OmniLight3D is placed per occupied cell. Bigger = fewer
# lights (a long vein still gets several, one per cell it spans).

@export_range(1.0, 24.0, 0.5) var light_range_m: float = 7.0
# OmniLight3D range, in metres, for each cluster light.

@export_range(0.05, 4.0, 0.05) var light_energy_scale: float = 0.4
# The cluster light's energy = VoxelMaterial.emission_energy x this x a
# small cluster-size boost. Lower it if glowing voxels blow out under
# the AgX tonemap; raise it if they read too dim.

@export_range(4, 64, 1) var max_active_lights: int = 28
# Hard cap on live OmniLight3Ds. Forward+ clusters lights cheaply, but
# this stops a huge emissive cave from spawning hundreds. Nearest
# clusters to the player win.

@export_range(8.0, 96.0, 1.0) var light_radius_m: float = 30.0
# Cluster lights beyond this distance from the player are streamed out
# (the OmniLight3D node is freed); they respawn when the player
# returns. The cluster's discovered position is remembered cheaply.

@export_range(2, 16, 1) var edit_scan_margin_voxels: int = 6
# How far past an edit's bounding box to scan for emissive voxels — so
# mining a tunnel reveals glowing ore in the wall just beyond the cut.

@export var periodic_scan_enabled: bool = true
# The secondary vicinity sweep (see header). Turn off to make the
# system purely edit-driven (zero idle cost).

@export_range(0.5, 10.0, 0.5) var periodic_scan_interval_s: float = 2.0
# Seconds between vicinity sweeps.

@export_range(8, 40, 1) var vicinity_scan_radius_voxels: int = 24
# Half-side of the vicinity sweep box, in voxels (6 voxels = 1 m). The
# sweep bulk-reads one box this big around the player each interval —
# the cost is iterating the buffer, so keep it modest. The box is
# sliced into 8 octants and drained one per tick (see
# _queue_vicinity_scan) so a 24-voxel radius costs ~5 ms per tick spread
# over 8 ticks instead of one ~38 ms frame stall.

@export_range(0.0, 8.0, 0.5) var vicinity_movement_threshold_m: float = 1.0
# Movement gate. If the player has moved less than this many metres
# since the last vicinity sweep, skip the new sweep — the box would
# cover almost the same voxels. Standing still: one scan after the
# player arrives, then idle. Moving: the gate is opened by the player's
# own motion. Set to 0 to disable the gate (sweep on every interval).


# =============================================================
# STATE
# =============================================================

# material_id -> VoxelMaterial, for every material flagged emissive.
var _emissive_mats: Dictionary = {}
# True only when at least one material is emissive AND `enabled`. When
# false the manager parks itself (set_process(false)) for zero cost.
var _active: bool = false

# Vector3i voxel-grid coord -> material_id, for every emissive voxel
# the manager has discovered. Cheap knowledge; persists for the session.
var _emissive_voxels: Dictionary = {}

# Vector3i coarse-cell coord -> {count:int, color:Color, energy:float,
# node:OmniLight3D|null}. One entry per cell that holds >=1 emissive
# voxel. `node` is null while the cell is streamed out.
var _lights: Dictionary = {}

# Pending scan requests: each {min_v:Vector3i, side:Vector3i}.
var _scan_queue: Array = []
const _SCAN_QUEUE_MAX: int = 24
# Largest box (per axis) a single scan may cover — guards the buffer
# allocation against a runaway request.
const _MAX_SCAN_SIDE: int = 72
# At most this many queued scans are drained per tick. Vicinity sweeps
# are sliced into 8 octants in _queue_vicinity_scan, so a value of 1
# spreads each sweep over 8 ticks (~1.6 s) — keeping each tick's scan
# work well under the 16 ms frame budget. Profiler capture 2026-05-25:
# the old un-sliced sweep cost 38 ms in a single frame; sliced + 1/tick
# is ~5 ms per tick, invisible.
const _MAX_SCANS_PER_TICK: int = 1

# Face-neighbour offsets — used to test whether an emissive voxel is
# exposed to air (and therefore worth lighting).
const _FACE_NEIGHBOURS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

var _terrain: Node = null
var _terrain_id: int = 0

# C++ scan impl (extensions/voxel_gen/src/emissive_light_cpp.cpp). Owns
# the per-voxel classification + _has_air_neighbor gate + coarse-cell
# dedupe. The autoload still owns OmniLight3D node creation/streaming,
# camera lookup, _resolve_terrain, and the diff-against-existing-state.
# When this is null (DLL missing), _scan_region falls back to the
# original full-GD path.
var _cpp: Resource = null
const _EmissiveRef := preload("res://scripts/_dev/EmissiveReference.gd")

# 10 Hz-ish heavy-work gate, mirroring DayNightCycle / WeatherManager.
const _TICK_S: float = 0.2
var _tick_accum: float = 0.0
var _periodic_accum: float = 0.0

# Movement-gate state. _last_vicinity_pos is the camera position the
# last vicinity sweep was centred on; _vicinity_first forces the first
# sweep to always run (otherwise it would be gated against ZERO).
var _last_vicinity_pos: Vector3 = Vector3.ZERO
var _vicinity_first: bool = true


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	if not enabled:
		set_process(false)
		return

	# Build the emissive-material set from the registry.
	if get_node_or_null("/root/VoxelMaterialRegistry") == null:
		push_warning("[EmissiveLightManager] VoxelMaterialRegistry missing — disabled.")
		set_process(false)
		return
	for vm in VoxelMaterialRegistry.get_all():
		if vm != null and vm.emission_enabled:
			_emissive_mats[vm.material_id] = vm

	if _emissive_mats.is_empty():
		# Nothing glows — park the manager. It costs nothing until a
		# material is flagged emissive and the project is reloaded.
		print("[EmissiveLightManager] no emissive materials — parked.")
		set_process(false)
		return

	_active = true

	# Connect to edits. VoxelEditManager loads before us (autoload order).
	if get_node_or_null("/root/VoxelEditManager") != null:
		VoxelEditManager.edit_applied.connect(_on_edit_applied)
	else:
		push_warning("[EmissiveLightManager] VoxelEditManager missing — edit-driven lighting off.")

	# Resolve the C++ scan impl + push the emissive id set.
	if ClassDB.class_exists("EmissiveLightCpp"):
		_cpp = ClassDB.instantiate("EmissiveLightCpp")
		if _cpp != null:
			var ids: PackedInt32Array = PackedInt32Array()
			for id in _emissive_mats.keys():
				ids.append(int(id))
			_cpp.set_emissive_material_ids(ids)
			_cpp.set_cell_size_voxels(cell_size_voxels)
			print("[EmissiveLightManager] using C++ scan (EmissiveLightCpp).")
		else:
			print("[EmissiveLightManager] EmissiveLightCpp registered but instantiate failed; using GD fallback.")
	else:
		print("[EmissiveLightManager] EmissiveLightCpp not registered; using GD fallback.")

	print("[EmissiveLightManager] active — %d emissive material(s)." % _emissive_mats.size())


func _process(delta: float) -> void:
	if not _active:
		return
	_tick_accum += delta
	if _tick_accum < _TICK_S:
		return
	var ticked: float = _tick_accum
	_tick_accum = 0.0

	var t0: int = Time.get_ticks_usec()
	_tick(ticked)
	var elapsed: int = Time.get_ticks_usec() - t0
	HUDOverlay.profile_record("EmissiveLightManager", elapsed)
	var prof: Node = get_node_or_null("/root/Profiler")
	if prof != null:
		prof.record("WORLD", "EmissiveLightManager", elapsed)


func _tick(delta: float) -> void:
	if not _resolve_terrain():
		return

	# Periodic vicinity sweep.
	if periodic_scan_enabled:
		_periodic_accum += delta
		if _periodic_accum >= periodic_scan_interval_s:
			_periodic_accum = 0.0
			_queue_vicinity_scan()

	# Drain a bounded number of scan requests.
	var drained: int = 0
	while not _scan_queue.is_empty() and drained < _MAX_SCANS_PER_TICK:
		var req: Dictionary = _scan_queue.pop_front()
		_scan_region(req["min_v"], req["side"])
		drained += 1

	# Stream the OmniLight3D nodes in/out around the player.
	_update_light_streaming()


# =============================================================
# SCAN REQUESTS
# =============================================================

func _on_edit_applied(_world_pos: Vector3, _chunk_coords: Vector3i, edit_aabb: AABB) -> void:
	if not _active:
		return
	# edit_aabb is in voxel-grid space. Expand by the margin so emissive
	# voxels just beyond the cut (an ore face in the tunnel wall) are
	# caught too.
	var m: int = edit_scan_margin_voxels
	var lo: Vector3i = Vector3i(floori(edit_aabb.position.x), floori(edit_aabb.position.y), floori(edit_aabb.position.z)) - Vector3i(m, m, m)
	var hi: Vector3i = Vector3i(ceili(edit_aabb.end.x), ceili(edit_aabb.end.y), ceili(edit_aabb.end.z)) + Vector3i(m, m, m)
	_queue_scan(lo, hi - lo)


func _queue_vicinity_scan() -> void:
	var cam: Camera3D = _get_camera()
	if cam == null:
		return
	var pos: Vector3 = cam.global_position
	# Movement gate — skip if the player hasn't moved enough since the
	# last sweep. The scan box would otherwise cover almost the same
	# voxels we already know about (the lights are cached in _lights and
	# _emissive_voxels and persist for the session).
	if not _vicinity_first \
			and vicinity_movement_threshold_m > 0.0 \
			and pos.distance_to(_last_vicinity_pos) < vicinity_movement_threshold_m:
		return
	_vicinity_first = false
	_last_vicinity_pos = pos
	# Slice the (2r)³ box into 8 (r)³ octants. With _MAX_SCANS_PER_TICK=1
	# the drain spreads the work across 8 ticks (~1.6 s) — each tick
	# handles ~r³ voxels instead of the (2r)³ all-at-once frame stall.
	var g: Vector3i = _world_to_voxel(pos)
	var r: int = vicinity_scan_radius_voxels
	for dx in [-r, 0]:
		for dy in [-r, 0]:
			for dz in [-r, 0]:
				_queue_scan(g + Vector3i(dx, dy, dz), Vector3i(r, r, r))


func _queue_scan(min_v: Vector3i, side: Vector3i) -> void:
	# Clamp the box so a bad request can't allocate a giant buffer.
	side.x = clampi(side.x, 1, _MAX_SCAN_SIDE)
	side.y = clampi(side.y, 1, _MAX_SCAN_SIDE)
	side.z = clampi(side.z, 1, _MAX_SCAN_SIDE)
	_scan_queue.append({"min_v": min_v, "side": side})
	# Drop the oldest request if the queue overflows — the player has
	# moved on; a stale scan is wasted work.
	while _scan_queue.size() > _SCAN_QUEUE_MAX:
		_scan_queue.pop_front()


# =============================================================
# SCANNING
# =============================================================

func _scan_region(min_v: Vector3i, side: Vector3i) -> void:
	var tool: VoxelTool = _terrain.get_voxel_tool()
	if tool == null:
		return
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	if not tool.has_method("copy"):
		# Without bulk copy a region scan would be a per-voxel native
		# crossing storm — refuse rather than hitch the main thread.
		return

	var buf: VoxelBuffer = VoxelBuffer.new()
	buf.create(side.x, side.y, side.z)
	tool.copy(min_v, buf, 1 << VoxelBuffer.CHANNEL_TYPE)

	# One pass over the box: reconcile every voxel against what we knew.
	# A voxel can have become emissive (mined into / placed), stopped
	# being emissive (mined away), or be unchanged.
	var affected: Dictionary = {}

	if _cpp != null:
		# FAST PATH — C++ classifies every voxel + applies the
		# _has_air_neighbor gate, returning the full set of currently-
		# lit emissive cells in the region. GD then diffs against
		# _emissive_voxels to compute add / remove / change.
		var result: Dictionary = _cpp.scan_region(buf, min_v, side)
		var now_lit_stream: PackedInt32Array = result["now_lit"]
		var lit_set: Dictionary = {}
		@warning_ignore("integer_division")
		var n: int = now_lit_stream.size() / 4
		for i in range(n):
			var g: Vector3i = Vector3i(
				now_lit_stream[i * 4],
				now_lit_stream[i * 4 + 1],
				now_lit_stream[i * 4 + 2],
			)
			var mid: int = now_lit_stream[i * 4 + 3]
			lit_set[g] = mid
			var was: bool = _emissive_voxels.has(g)
			if not was or _emissive_voxels[g] != mid:
				_emissive_voxels[g] = mid
				affected[_cell_of(g)] = true
		# Removals: walk _emissive_voxels for entries inside the
		# scanned region that aren't in this scan's now_lit. The walk
		# is O(|_emissive_voxels|); the dict holds dozens to hundreds
		# of entries in practice, not thousands, so it stays cheap.
		var region_end: Vector3i = min_v + side
		var to_erase: Array = []
		for g_v in _emissive_voxels.keys():
			var g: Vector3i = g_v
			if g.x < min_v.x or g.y < min_v.y or g.z < min_v.z:
				continue
			if g.x >= region_end.x or g.y >= region_end.y or g.z >= region_end.z:
				continue
			if lit_set.has(g):
				continue
			to_erase.append(g)
		for g in to_erase:
			_emissive_voxels.erase(g)
			affected[_cell_of(g)] = true
	else:
		# GD fallback — original per-voxel inner loop.
		for x in range(side.x):
			for y in range(side.y):
				for z in range(side.z):
					var g: Vector3i = min_v + Vector3i(x, y, z)
					var mid: int = buf.get_voxel(x, y, z, VoxelBuffer.CHANNEL_TYPE) & 0xFF
					# Only EXPOSED emissive voxels light the world. A
					# glowing voxel sealed in solid rock is skipped —
					# cluster lights are shadowless, so lighting a
					# buried voxel just bleeds brightness up through the
					# terrain. Copper stays dark underground until mined into.
					var now_lit: bool = _emissive_mats.has(mid) \
							and _has_air_neighbor(buf, x, y, z, side)
					var was: bool = _emissive_voxels.has(g)
					if now_lit:
						if not was or _emissive_voxels[g] != mid:
							_emissive_voxels[g] = mid
							affected[_cell_of(g)] = true
					elif was:
						_emissive_voxels.erase(g)
						affected[_cell_of(g)] = true

	for cell in affected:
		_rebuild_cell(cell)


# True if any of the 6 face-neighbours of buffer voxel (x,y,z) is air.
# Neighbours outside the buffer are treated as unknown (not air) — a
# border voxel with no in-buffer air neighbour is simply re-evaluated
# on the next sweep, when the box has recentred and its neighbours are
# in range.
func _has_air_neighbor(buf: VoxelBuffer, x: int, y: int, z: int, side: Vector3i) -> bool:
	for o in _FACE_NEIGHBOURS:
		var nx: int = x + o.x
		var ny: int = y + o.y
		var nz: int = z + o.z
		if nx < 0 or ny < 0 or nz < 0 or nx >= side.x or ny >= side.y or nz >= side.z:
			continue
		if (buf.get_voxel(nx, ny, nz, VoxelBuffer.CHANNEL_TYPE) & 0xFF) == 0:
			return true
	return false


# Recount one coarse cell and create / refresh / drop its light meta.
func _rebuild_cell(cell: Vector3i) -> void:
	var base: Vector3i = cell * cell_size_voxels
	var count: int = 0
	var mat_id: int = -1
	for x in range(cell_size_voxels):
		for y in range(cell_size_voxels):
			for z in range(cell_size_voxels):
				var g: Vector3i = base + Vector3i(x, y, z)
				if _emissive_voxels.has(g):
					count += 1
					mat_id = _emissive_voxels[g]

	if count == 0:
		# Cell emptied — drop its light.
		if _lights.has(cell):
			var meta: Dictionary = _lights[cell]
			var node: OmniLight3D = meta.get("node")
			if node != null and is_instance_valid(node):
				node.queue_free()
			_lights.erase(cell)
		return

	var vm: VoxelMaterial = _emissive_mats[mat_id]
	var entry: Dictionary = _lights.get(cell, {"node": null})
	entry["count"] = count
	entry["color"] = vm.emission_color
	entry["energy"] = vm.emission_energy
	_lights[cell] = entry
	var live: OmniLight3D = entry.get("node")
	if live != null and is_instance_valid(live):
		_apply_light_props(live, entry)


# =============================================================
# LIGHT STREAMING
# =============================================================

func _update_light_streaming() -> void:
	var cam: Camera3D = _get_camera()
	if cam == null:
		return
	var p: Vector3 = cam.global_position

	# Rank every known cell by distance to the player.
	var ranked: Array = []
	for cell in _lights:
		var wpos: Vector3 = _cell_to_world(cell)
		ranked.append({"cell": cell, "d": p.distance_to(wpos), "wpos": wpos})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["d"] < b["d"])

	var lit: int = 0
	for r in ranked:
		var cell: Vector3i = r["cell"]
		var entry: Dictionary = _lights[cell]
		var want: bool = r["d"] <= light_radius_m and lit < max_active_lights
		var node: OmniLight3D = entry.get("node")
		if want:
			lit += 1
			if node == null or not is_instance_valid(node):
				node = OmniLight3D.new()
				node.shadow_enabled = false
				node.light_volumetric_fog_energy = 0.0
				add_child(node)
				node.global_position = r["wpos"]
				entry["node"] = node
				_lights[cell] = entry
				_apply_light_props(node, entry)
		elif node != null and is_instance_valid(node):
			node.queue_free()
			entry["node"] = null
			_lights[cell] = entry


func _apply_light_props(node: OmniLight3D, entry: Dictionary) -> void:
	node.light_color = entry["color"]
	# More emissive voxels packed into a cell -> a touch brighter.
	var boost: float = clampf(float(entry["count"]) / float(cell_size_voxels), 0.5, 2.0)
	node.light_energy = float(entry["energy"]) * light_energy_scale * boost
	node.omni_range = light_range_m
	node.light_specular = 0.25


# =============================================================
# HELPERS
# =============================================================

func _resolve_terrain() -> bool:
	if _terrain != null and is_instance_valid(_terrain):
		return true
	# Terrain changed or first resolve — drop any stale lighting state.
	if not _emissive_voxels.is_empty() or not _lights.is_empty():
		_clear_state()
	_terrain = null
	var root: Node = get_tree().current_scene
	if root == null:
		return false
	for child in root.get_children():
		if child.get_class() == "VoxelLodTerrain" or child.get_class() == "VoxelTerrain":
			_terrain = child
			_terrain_id = child.get_instance_id()
			return true
	return false


func _clear_state() -> void:
	for cell in _lights:
		var node: OmniLight3D = _lights[cell].get("node")
		if node != null and is_instance_valid(node):
			node.queue_free()
	_lights.clear()
	_emissive_voxels.clear()
	_scan_queue.clear()


func _get_camera() -> Camera3D:
	var vp: Viewport = get_viewport()
	if vp == null:
		return null
	return vp.get_camera_3d()


# Voxel grid coord -> coarse-cell coord (floor division, negatives-safe).
func _cell_of(g: Vector3i) -> Vector3i:
	var s: float = float(cell_size_voxels)
	return Vector3i(floori(g.x / s), floori(g.y / s), floori(g.z / s))


# Coarse-cell coord -> the cell centre in world metres.
func _cell_to_world(cell: Vector3i) -> Vector3:
	var half: float = float(cell_size_voxels) * 0.5
	var local: Vector3 = Vector3(cell) * float(cell_size_voxels) + Vector3(half, half, half)
	return _terrain.global_transform * local


# World metres -> voxel grid coord.
func _world_to_voxel(world: Vector3) -> Vector3i:
	var local: Vector3 = _terrain.global_transform.affine_inverse() * world
	return Vector3i(floori(local.x), floori(local.y), floori(local.z))
