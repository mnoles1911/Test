extends Node3D
# World3DBootstrap — wires up scene-level systems when the World3D
# scene loads.
#
# What this does in plain English:
#
#   When World3D.tscn opens for play, the autoloads (VoxelEditManager,
#   NoEditZoneRegistry) are alive but they don't yet know about the
#   VoxelLodTerrain that lives inside this scene. This script runs in
#   _ready() and hands the terrain over so every voxel edit verb
#   (pickaxe, axe, shovel, explosive, spell) can find its target.
#
# This script is the single entry point for "things that have to
# happen at world load." If we add more world-level wiring later
# (per-slot voxel save paths, NoEditZoneRegistry pre-warm, weather
# system init), it goes here.
#
# Attached to the root node of World3D.tscn.


@export var voxel_terrain_path: NodePath = "VoxelLodTerrain"
# Path to the VoxelLodTerrain node within this World3D scene.
# Exposed as a NodePath so the scene can be reorganized without
# touching this script.


# =============================================================
# DIAGNOSTIC STATE — LOD / streaming investigation 2026-05-07
# =============================================================
# When the user reports "I outwalked the terrain loader," we need
# concrete numbers: player speed, viewer position vs player, generator
# throughput per LOD. The generator already prints [PERF GEN] every
# 100 blocks (perf_log_enabled = true on the .tres). This script adds:
#   • a 1 Hz [DIAG] line: player pos, speed, VoxelViewer pos, lag.
#   • F8 toggles Zylann's built-in debug draws (clipboxes + active
#     mesh blocks) so the user can SEE which chunks are loaded and
#     which are starving ahead of the player.
# All of this is gated behind diag_enabled so it can be flipped off
# from the inspector without re-editing the script.

@export var diag_enabled: bool = true

var _diag_terrain: Object = null
var _diag_player: Node3D = null
var _diag_viewer: Node3D = null
var _diag_acc_time: float = 0.0
var _diag_last_player_pos: Vector3 = Vector3.ZERO
var _diag_last_player_pos_valid: bool = false
var _diag_debug_draw_on: bool = false


func _ready() -> void:
	# --- Hand the voxel terrain to the edit manager ---
	# Without this call, VoxelEditManager has no terrain to write to
	# and silently rejects every queue_edit_* call (returns false).
	var terrain := get_node_or_null(voxel_terrain_path)
	if terrain == null:
		push_error("[World3D] VoxelLodTerrain not found at path: %s" % voxel_terrain_path)
		return

	# Configure the terrain's CHANNEL_TYPE storage depth. After the v13
	# VoxelMesherBlocky migration we store material_id directly in
	# CHANNEL_TYPE — 8-bit is sufficient (material_id range 0-254).
	# Default depth for TYPE is already 8-bit, but we set it explicitly
	# so the format is documented in code rather than implicit.
	if "format" in terrain:
		_configure_voxel_format(terrain)

	# Move per-edit voxel-block updates off the main thread.
	# `threaded_update_enabled` defaults to FALSE in this Zylann
	# build, which is what made `tool.do_box(...)` cost ~37 ms per
	# 3×3×3 mining swing — the mesh rebuild for the affected mesh
	# blocks ran synchronously on the main thread and was the
	# entirety of the [SPIKE _apply_edit total=37 ms (carve=37 ms)]
	# we just measured. Turning it on offloads the work to a worker.
	if "threaded_update_enabled" in terrain:
		terrain.set("threaded_update_enabled", true)
		print("[World3D] terrain.threaded_update_enabled = true")
	# Defer collision-shape rebuilds so they batch instead of firing
	# on every single edit / stream. CRITICAL: in this Zylann build the
	# property is INT (likely milliseconds), so the previous set(..., 0.1)
	# silently truncated to 0 — every chunk streaming in/out fired an
	# immediate main-thread collision rebuild. The dump in the Output
	# panel confirms whatever value lands here: look for
	# "terrain.collision_update_delay = N".
	if "collision_update_delay" in terrain:
		terrain.set("collision_update_delay", 100)
		var actual_delay = terrain.get("collision_update_delay")
		print("[World3D] terrain.collision_update_delay set to 100 (actual=%s)" % actual_delay)
	# Belt-and-suspenders for the .tscn values that the editor has been
	# stripping on save. Setting them programmatically AND in the .tscn
	# means at least one path lands. The readback prints make it obvious
	# in the Output panel whether Zylann accepted the value or clamped:
	#   - mesh_block_size: 32 makes each mesh chunk cover 8x more voxels
	#     than the default 16, cutting per-LOD-transition mesh-upload
	#     count by ~8x. If readback shows 16 instead of 32, this Zylann
	#     build doesn't allow 32 and we'll need a different angle.
	#   - lod_distance: 128 (Zylann hard cap) widens each LOD shell by
	#     33% vs the previous 96, so the player has to walk further
	#     before chunks transition LOD level. Reduces backtracking spikes.
	if "mesh_block_size" in terrain:
		terrain.set("mesh_block_size", 32)
		print("[World3D] terrain.mesh_block_size set to 32 (actual=%s)" % terrain.get("mesh_block_size"))
	if "lod_distance" in terrain:
		terrain.set("lod_distance", 128.0)
		print("[World3D] terrain.lod_distance set to 128.0 (actual=%s)" % terrain.get("lod_distance"))
	# Streaming system: 0 = LEGACY_OCTREE (default), 1 = CLIPBOX.
	# CLIPBOX walks a clipped box of chunks rather than a full octree
	# per viewer — typically 2-5× faster main-thread cost than the
	# legacy octree path. Probe-confirmed via BakeWorld's diagnostics.
	# Enforced here in addition to the .tscn property so Godot's editor
	# silently reverting to default-0 doesn't regress the perf win.
	if "streaming_system" in terrain:
		terrain.set("streaming_system", 1)
		print("[World3D] terrain.streaming_system set to 1 CLIPBOX (actual=%s)" % terrain.get("streaming_system"))
	# LOD fade duration: extends the cross-fade between LOD levels from
	# 1s to 2s. Smoother visual transitions + spreads the mesh upload
	# cost over twice as many frames, mitigating the chunk-stream-in
	# spike phenomenon.
	if "lod_fade_duration" in terrain:
		terrain.set("lod_fade_duration", 2.0)
		print("[World3D] terrain.lod_fade_duration set to 2.0 (actual=%s)" % terrain.get("lod_fade_duration"))

	# DIAGNOSTIC — dump every public property on VoxelLodTerrain so we
	# can hunt for a "max mesh blocks applied per frame" or similar
	# setting. The earlier filtered dump only showed depth/format/
	# channel/block matches; the lag investigation now needs a wider
	# net (anything that controls streaming pacing, threading, view
	# distance, queue caps, etc.).
	print("[World3D] Full VoxelLodTerrain property dump:")
	for prop in terrain.get_property_list():
		var p_name: String = prop.get("name", "")
		if p_name == "" or p_name.begins_with("script") or p_name == "resource_local_to_scene":
			continue
		if p_name == "resource_path" or p_name == "resource_name":
			continue
		# Skip uninteresting Node-level properties (transform, visibility,
		# editor scaffolding) — those don't have streaming-perf relevance.
		if p_name in ["transform", "global_transform", "visible",
				"position", "rotation", "scale", "rotation_order",
				"top_level", "metadata", "owner", "name",
				"unique_name_in_owner", "process_priority",
				"editor_description", "process_mode", "_import_path",
				"multiplayer", "physics_interpolation_mode"]:
			continue
		print("[World3D]   terrain.%s = %s" % [p_name, terrain.get(p_name)])

	if "mesher" in terrain:
		var mesher: Resource = terrain.mesher
		if mesher != null:
			# Runtime fix for a Zylann gdextension serialization bug:
			# VoxelBlockyModelCube's per-surface `material_override_0`
			# saves into blocky_library.tres but doesn't restore on load
			# (get_material_override(0) returns null at runtime even
			# though the .tres clearly carries the SubResource ref).
			# Workaround: load the atlas texture, build a fresh shared
			# StandardMaterial3D, and inject it into every cube model's
			# surface 0 right now. Tile coords serialize/restore fine,
			# so only the materials need this round-trip bypass.
			_inject_atlas_materials_into_library(mesher)

			print("[World3D] Mesher class: %s" % mesher.get_class())
			# Verify the blocky library's first cube model has an
			# atlas material attached. In Zylann's current API,
			# materials live on each VoxelBlockyModelCube and are
			# accessed via get_material_override(surface_idx) — the
			# `material_override_0` listed in get_property_list() is
			# a dynamic per-surface property name and the `in`
			# operator returns false for it even when the property
			# really exists. Use the method directly to avoid that.
			var lib: Resource = mesher.get("library") if "library" in mesher else null
			if lib != null and "models" in lib:
				var models_arr: Array = lib.get("models")
				var first_solid = null
				for m in models_arr:
					if m != null:
						first_solid = m
						break
				if first_solid != null and first_solid.has_method("get_material_override"):
					var mat0 = first_solid.call("get_material_override", 0)
					if mat0 == null:
						print("[World3D]   ⚠ blocky library model[0] has no material_override(0) — re-run tools/build_blocky_library.gd.")
					else:
						var has_tex: bool = false
						if mat0 is BaseMaterial3D:
							has_tex = (mat0 as BaseMaterial3D).albedo_texture != null
						print("[World3D]   ✓ blocky library model[0].material = %s (albedo_texture=%s)" % [
							mat0.get_class(), "yes" if has_tex else "MISSING"
						])
				else:
					print("[World3D]   ⚠ blocky library has no usable first model.")
			else:
				print("[World3D]   ⚠ mesher has no library — wire it in World3D.tscn.")
			for prop in mesher.get_property_list():
				var pname: String = prop.get("name", "")
				if pname == "" or pname.begins_with("script") or pname == "resource_local_to_scene":
					continue
				if pname == "resource_path" or pname == "resource_name":
					continue
				print("[World3D]   mesher.%s = %s" % [pname, mesher.get(pname)])

	# Same dump for VoxelStreamSQLite so we can find the right
	# property name for full-caching mode. With save_generator_output
	# = true in the .tscn, the cache file should grow into MBs as
	# the player explores. If it's stuck at 20 KB (only edit deltas),
	# the property name is wrong for this Zylann build.
	if "stream" in terrain:
		var stream: Resource = terrain.stream
		if stream != null:
			print("[World3D] Stream class: %s" % stream.get_class())
			for prop in stream.get_property_list():
				var pname: String = prop.get("name", "")
				if pname == "" or pname.begins_with("script") or pname == "resource_local_to_scene":
					continue
				if pname == "resource_path" or pname == "resource_name":
					continue
				print("[World3D]   stream.%s = %s" % [pname, stream.get(pname)])

	# Guard with get_node_or_null in case the autoload isn't registered
	# yet (e.g. a fresh project without our autoload entries). The
	# project should always have it registered, but this prevents a
	# crash if something is misconfigured.
	if get_node_or_null("/root/VoxelEditManager"):
		VoxelEditManager.set_terrain(terrain)
		print("[World3D] Voxel terrain handed to VoxelEditManager.")
	else:
		push_warning("[World3D] VoxelEditManager autoload not registered; voxel edits will not work.")

	# --- Hand the NoEditZone water-blocking snapshot to the generator ---
	# The generator's _generate_block runs on Zylann worker threads,
	# which cannot touch the SceneTree (no get_node_or_null, no physics
	# queries). Build the snapshot here on the main thread and push it
	# into the generator resource via set_no_edit_water_aabbs(). Worker
	# threads then read from the resource's local Array — pure data,
	# safe across threads.
	#
	# Runtime-streamed NoEditZones are NOT picked up here. Generator
	# output is final once written, so a settlement spawned mid-game
	# below sea level can't retroactively dry already-generated chunks.
	# Documented as a v1 constraint in NoEditZone.gd.
	if "generator" in terrain:
		var gen: Resource = terrain.get("generator")
		if gen != null and gen.has_method("set_no_edit_water_aabbs") \
				and get_node_or_null("/root/NoEditZoneRegistry"):
			var snapshot: Array[AABB] = NoEditZoneRegistry.get_water_blocking_aabbs_snapshot()
			gen.set_no_edit_water_aabbs(snapshot)
			print("[World3D] Pushed %d NoEditZone water-blocking AABB(s) to generator." % snapshot.size())
		# Tier 4: push the registry's pre-filtered ore list into the
		# generator on the main thread. Worker threads then iterate
		# the local Array reference without touching the SceneTree.
		if gen != null and gen.has_method("set_ore_materials") \
				and get_node_or_null("/root/VoxelMaterialRegistry") \
				and VoxelMaterialRegistry.is_loaded():
			var ores: Array[VoxelMaterial] = VoxelMaterialRegistry.get_ore_materials()
			gen.call("set_ore_materials", ores)
			print("[World3D] Pushed %d ore material(s) to generator." % ores.size())
		# Tier 5: clay / gravel disk materials.
		if gen != null and gen.has_method("set_disk_materials") \
				and get_node_or_null("/root/VoxelMaterialRegistry") \
				and VoxelMaterialRegistry.is_loaded():
			var disks: Array[VoxelMaterial] = VoxelMaterialRegistry.get_disk_materials()
			gen.call("set_disk_materials", disks)
			print("[World3D] Pushed %d disk material(s) to generator." % disks.size())

	# --- Configure water surface + seed test pond ---
	# Phase 5: the AABB-source-region model is gone. Ocean water lives
	# in CHANNEL_DATA, written at gen time by CubicHeightmapGenerator
	# for every below-sea-level column. World3DBootstrap's job here is
	# just to (a) tell WaterFlowManager what world Y the horizon plane
	# should sit at, and (b) seed any author-time water bodies (the
	# legacy test pond) via the new water-edit API.
	#
	# OCEAN_SURFACE_Y at 12 m — matches the generator's
	# SEA_LEVEL_VOXELS=72 / 6 vox/m. Keep them aligned or the chunked
	# water mesh and any future horizon plane will sit at different Ys.
	const OCEAN_SURFACE_Y: float = 12.0
	if get_node_or_null("/root/WaterFlowManager"):
		WaterFlowManager.set_horizon_plane_y(OCEAN_SURFACE_Y)
		# Test pond at world (-23..-13, -1.5..1.5, -1..9). The 10×3×10 m
		# footprint matches the legacy pond AABB. Convert to voxel units
		# (×6) for queue_set_water_box and write source bytes into
		# CHANNEL_DATA. Deferred one frame so VoxelEditManager has the
		# terrain bound (set_terrain runs above; the queue drain is in
		# _physics_process so even an immediate enqueue is fine, but
		# call_deferred keeps load-order forgiving).
		call_deferred("_seed_test_pond")
		print("[World3D] Configured horizon plane Y=%.1f; test pond queued." % OCEAN_SURFACE_Y)
	else:
		push_warning("[World3D] WaterFlowManager autoload not registered; water disabled.")

	# --- Apply saved player position ---
	# When the world scene loads after a load_save_file() call,
	# GameState.player_position holds Roland's saved 3D position.
	# Apply it to the live player so he respawns where the save
	# was taken. Without this, every load drops Roland at the
	# scene's default Player3D spawn (Y=35 on noise terrain).
	#
	# Skip on a fresh New Game where player_position is the default
	# Vector3.ZERO — let the scene's default placement win.
	#
	# Deferred one frame so the Player3D node has run its own
	# _ready (collision shape resolved, voxel terrain has had a
	# chance to load nearby chunks for collision).
	if get_node_or_null("/root/GameState"):
		if GameState.player_position != Vector3.ZERO:
			call_deferred("_apply_saved_player_position")
		else:
			# Fresh New Game (no saved position) — snap player to the
			# top of whatever terrain exists at his X,Z spawn rather
			# than letting him fall from the scene's default Y=120.
			# Falling 100+ m through unloaded chunks looks bad and
			# wastes the first few seconds of play. Retry every
			# 0.2 s for up to 5 s while terrain streams in.
			#
			# CRITICAL: set _spawn_freeze BEFORE deferring the snap.
			# Without this, the player's _physics_process runs gravity
			# while _snap_spawn_to_ground is still searching, so the
			# player falls past the raycast dest (Y=-200) before a hit
			# can register and ends up falling forever. The freeze is
			# cleared by _snap_spawn_to_ground on both success and
			# retry-exhausted paths so the player is never permanently
			# locked. Set synchronously here (not deferred) because
			# player._ready already ran (children _ready before parent
			# _ready in Godot's tree traversal) so the player exists.
			var players: Array = get_tree().get_nodes_in_group("player")
			if not players.is_empty():
				var player: Node = players[0]
				if "_spawn_freeze" in player:
					player.set("_spawn_freeze", true)
			call_deferred("_snap_spawn_to_ground")


const _ATLAS_TEXTURE_PATH: String = "res://assets/voxels/texture_packs/default/atlas.png"
const _ATLAS_TILES_PER_ROW: int = 64   # 2048 / 32

# Zylann Cube SIDE enum (from voxel/util/godot/classes/cube.h):
const _SIDE_NEG_X: int = 0
const _SIDE_POS_X: int = 1
const _SIDE_NEG_Y: int = 2
const _SIDE_POS_Y: int = 3
const _SIDE_NEG_Z: int = 4
const _SIDE_POS_Z: int = 5

# Per-material face tile coords. Single source of truth at runtime —
# mirrors MATERIAL_TILES in tools/build_blocky_library.gd because the
# .tres save/load round-trip loses these values (Zylann gdextension
# bug). Tiles must be re-applied here every scene load.
const _MATERIAL_TILES: Dictionary = {
	1:  {"top": Vector2i(0, 0),  "side": Vector2i(0, 0),  "bottom": Vector2i(0, 0)},
	2:  {"top": Vector2i(1, 0),  "side": Vector2i(1, 0),  "bottom": Vector2i(1, 0)},
	3:  {"top": Vector2i(2, 0),  "side": Vector2i(3, 0),  "bottom": Vector2i(1, 0)},
	4:  {"top": Vector2i(4, 0),  "side": Vector2i(4, 0),  "bottom": Vector2i(4, 0)},
	# 5 = water, no library entry
	6:  {"top": Vector2i(4, 1),  "side": Vector2i(4, 1),  "bottom": Vector2i(4, 1)},
	7:  {"top": Vector2i(5, 0),  "side": Vector2i(5, 0),  "bottom": Vector2i(5, 0)},
	8:  {"top": Vector2i(6, 0),  "side": Vector2i(6, 0),  "bottom": Vector2i(6, 0)},
	9:  {"top": Vector2i(7, 0),  "side": Vector2i(7, 0),  "bottom": Vector2i(7, 0)},
	10: {"top": Vector2i(0, 1),  "side": Vector2i(1, 1),  "bottom": Vector2i(0, 1)},
	11: {"top": Vector2i(2, 1),  "side": Vector2i(2, 1),  "bottom": Vector2i(2, 1)},
	12: {"top": Vector2i(3, 1),  "side": Vector2i(3, 1),  "bottom": Vector2i(3, 1)},
	13: {"top": Vector2i(8, 0),  "side": Vector2i(8, 0),  "bottom": Vector2i(8, 0)},   # snow (Tier 2)
	14: {"top": Vector2i(9, 0),  "side": Vector2i(9, 0),  "bottom": Vector2i(9, 0)},   # stone_dark (Tier 3)
	15: {"top": Vector2i(10, 0), "side": Vector2i(10, 0), "bottom": Vector2i(10, 0)},  # iron_ore (Tier 4)
}

const _NON_CULLING_MATERIALS: Array[int] = [11]   # leaves
const _TRANSPARENT_MATERIALS: Array[int] = [11]   # leaves


func _inject_atlas_materials_into_library(mesher: Resource) -> void:
	# See call site for the why. Both `material_override_0` AND the
	# per-face `tile_*` properties survive the .tres save but fail to
	# restore on load (Zylann gdextension dynamic-property bug). The
	# saved cubes come back with default tile (0,0) and null material,
	# so every face renders with full-atlas UVs sampling the entire
	# 2048x2048 — the visible "8 textures across the top, transparent
	# bottom" symptom is alpha-scissor cutting the empty atlas region.
	# Workaround: re-apply tiles + material at runtime.
	var lib: Resource = mesher.get("library") if "library" in mesher else null
	if lib == null:
		print("[World3D]   ⚠ inject_atlas_materials: no library on mesher.")
		return

	var atlas_tex: Texture2D = load(_ATLAS_TEXTURE_PATH) as Texture2D
	if atlas_tex == null:
		printerr("[World3D]   ⚠ inject_atlas_materials: failed to load %s" % _ATLAS_TEXTURE_PATH)
		return

	var atlas_mat: StandardMaterial3D = StandardMaterial3D.new()
	atlas_mat.resource_name = "atlas_default_runtime"
	atlas_mat.albedo_texture = atlas_tex
	atlas_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	atlas_mat.alpha_scissor_threshold = 0.5
	atlas_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	atlas_mat.roughness = 0.85
	atlas_mat.metallic = 0.0
	atlas_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	if not "models" in lib:
		print("[World3D]   ⚠ inject_atlas_materials: library has no models array.")
		return
	var models_arr: Array = lib.get("models")
	var atlas_grid: Vector2i = Vector2i(_ATLAS_TILES_PER_ROW, _ATLAS_TILES_PER_ROW)
	var injected: int = 0
	for slot_idx in _MATERIAL_TILES.keys():
		var idx: int = int(slot_idx)
		if idx < 0 or idx >= models_arr.size():
			continue
		var m = models_arr[idx]
		if m == null:
			continue
		var faces: Dictionary = _MATERIAL_TILES[idx]
		# Re-apply atlas grid + per-face tile coords. Use .set() for the
		# plain property, .call() for the methods (the per-side tiles
		# only stick when written through set_tile).
		m.set("atlas_size_in_tiles", atlas_grid)
		if m.has_method("set_tile"):
			m.call("set_tile", _SIDE_POS_Y, faces["top"])
			m.call("set_tile", _SIDE_NEG_Y, faces["bottom"])
			m.call("set_tile", _SIDE_NEG_X, faces["side"])
			m.call("set_tile", _SIDE_POS_X, faces["side"])
			m.call("set_tile", _SIDE_NEG_Z, faces["side"])
			m.call("set_tile", _SIDE_POS_Z, faces["side"])
		if m.has_method("set_material_override"):
			m.call("set_material_override", 0, atlas_mat)
		# Transparency / culling overrides for leaves etc.
		if idx in _TRANSPARENT_MATERIALS:
			m.set("transparency_index", 1)
		if idx in _NON_CULLING_MATERIALS:
			m.set("culls_neighbors", false)
		injected += 1

	# Re-bake so Zylann recomputes per-cube UVs from the freshly
	# written tile coords + atlas_size_in_tiles.
	if lib.has_method("bake"):
		lib.bake()

	print("[World3D] inject_atlas_materials: re-applied tiles + atlas mat to %d models, library re-baked." % injected)


func _process(delta: float) -> void:
	# 1 Hz diagnostic line for the LOD-streaming investigation.
	# Prints player position, instantaneous speed (m/s), VoxelViewer
	# position, and the XZ distance between them ("viewer lag"). If
	# the viewer lag stays at ~0 while chunks visibly fail to keep
	# up, the bottleneck is throughput, not viewer placement.
	if not diag_enabled:
		return
	_diag_acc_time += delta
	if _diag_acc_time < 1.0:
		return
	var dt: float = _diag_acc_time
	_diag_acc_time = 0.0
	_diag_resolve_refs()
	if _diag_player == null:
		return
	var p_pos: Vector3 = _diag_player.global_position
	var speed: float = 0.0
	if _diag_last_player_pos_valid:
		var d: Vector3 = p_pos - _diag_last_player_pos
		# Horizontal speed only — vertical drift from gravity / spawn-snap
		# would otherwise skew the number on idle frames.
		var d_xz: Vector2 = Vector2(d.x, d.z)
		speed = d_xz.length() / dt
	_diag_last_player_pos = p_pos
	_diag_last_player_pos_valid = true
	var v_pos: Vector3 = Vector3.INF
	var lag_xz: float = -1.0
	if _diag_viewer != null:
		v_pos = _diag_viewer.global_position
		var lag_v: Vector2 = Vector2(p_pos.x - v_pos.x, p_pos.z - v_pos.z)
		lag_xz = lag_v.length()
	# Pull a couple of relevant counters off VoxelEditManager / generator
	# without crashing if they're not present.
	var stats: String = ""
	if _diag_terrain != null and "get_statistics" in _diag_terrain:
		var s = _diag_terrain.call("get_statistics")
		if s is Dictionary:
			# Print only the fields we care about (keeps the line readable).
			# Names vary between Zylann builds — we probe and print
			# whatever the dict contains.
			for k in s.keys():
				stats += " %s=%s" % [k, s[k]]
	print("[DIAG] player=(%.1f, %.1f, %.1f)  speed=%.2f m/s  viewer=(%.1f, %.1f, %.1f)  lag_xz=%.1f m%s" % [
		p_pos.x, p_pos.y, p_pos.z, speed,
		v_pos.x, v_pos.y, v_pos.z, lag_xz,
		stats,
	])


func _input(event: InputEvent) -> void:
	# F12 toggles Zylann's terrain debug draws. Visible:
	#   • debug_draw_active_mesh_blocks → coloured wireframes around
	#     the chunks Zylann is actively meshing.
	#   • debug_draw_viewer_clipboxes → the streaming sphere(s).
	#   • debug_draw_octree_nodes → octree subdivision (LOD shells).
	# All three together let us SEE where the streamer is spending
	# effort vs where the player actually is.
	#
	# Why F12 and not F8: F8 is the Godot editor's "Stop Scene"
	# shortcut. When the project is run from the editor (the normal
	# case during development), F8 is intercepted by the editor
	# before the running game ever sees it — pressing F8 closes the
	# scene instead of toggling debug draws. F12 is unbound in the
	# editor so the running game receives it.
	if not diag_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			_diag_resolve_refs()
			if _diag_terrain == null:
				return
			_diag_debug_draw_on = not _diag_debug_draw_on
			_diag_terrain.set("debug_draw_enabled", _diag_debug_draw_on)
			_diag_terrain.set("debug_draw_active_mesh_blocks", _diag_debug_draw_on)
			_diag_terrain.set("debug_draw_viewer_clipboxes", _diag_debug_draw_on)
			_diag_terrain.set("debug_draw_octree_nodes", _diag_debug_draw_on)
			var _state_str: String = "ON" if _diag_debug_draw_on else "OFF"
			print("[DIAG] terrain debug draws %s (active_mesh_blocks + viewer_clipboxes + octree_nodes)" % _state_str)


func _diag_resolve_refs() -> void:
	# Lazy lookup — Player3D is added to the "player" group in its
	# own _ready; the bootstrap's _ready may race ahead of it on slow
	# loads. Cache once everything is alive.
	if _diag_terrain == null:
		_diag_terrain = get_node_or_null(voxel_terrain_path)
	if _diag_player == null:
		var players: Array = get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			_diag_player = players[0] as Node3D
	if _diag_viewer == null and _diag_player != null:
		# VoxelViewer lives as a direct child of Player3D (see Player3D.tscn).
		_diag_viewer = _diag_player.get_node_or_null("VoxelViewer") as Node3D


func _configure_voxel_format(terrain: Object) -> void:
	# Set CHANNEL_TYPE depth to 8-bit. After the v13 migration to
	# VoxelMesherBlocky we store the material_id directly in TYPE,
	# which fits in a single byte (0-254 is the valid range).
	#
	# 8-bit is the Zylann default for TYPE so this is mostly defensive
	# documentation — but we still set it explicitly because (a) older
	# saves may have a stored format with COLOR depth pinned to 32-bit
	# from the pre-v13 era, and (b) being explicit makes the file
	# easier to find via grep when something goes wrong.
	#
	# The exact API of VoxelFormat depends on the Zylann build. We
	# probe a couple of common patterns: a method (set_channel_depth)
	# or an array property (channel_depths). One should work.
	var fmt: Resource = null
	if ClassDB.class_exists("VoxelFormat"):
		fmt = ClassDB.instantiate("VoxelFormat")
	if fmt == null:
		# No VoxelFormat — pre-v13 builds didn't need this either, the
		# defaults (8-bit TYPE) are correct. Skip silently.
		return

	var configured: bool = false

	# Path 1 — method-based API: VoxelFormat.set_channel_depth(channel, depth)
	if fmt.has_method("set_channel_depth"):
		fmt.call("set_channel_depth", VoxelBuffer.CHANNEL_TYPE, VoxelBuffer.DEPTH_8_BIT)
		print("[World3D] Set CHANNEL_TYPE depth via fmt.set_channel_depth(...)")
		configured = true

	# Path 2 — typed per-channel property: VoxelFormat.type_depth = X
	if not configured and "type_depth" in fmt:
		fmt.set("type_depth", VoxelBuffer.DEPTH_8_BIT)
		print("[World3D] Set CHANNEL_TYPE depth via fmt.type_depth")
		configured = true

	# Path 3 — array property indexed by channel
	if not configured and "channel_depths" in fmt:
		var depths = fmt.get("channel_depths")
		if depths is Array:
			depths[VoxelBuffer.CHANNEL_TYPE] = VoxelBuffer.DEPTH_8_BIT
			fmt.set("channel_depths", depths)
			print("[World3D] Set CHANNEL_TYPE depth via fmt.channel_depths[CHANNEL_TYPE]")
			configured = true

	if not configured:
		# Defaults are 8-bit on TYPE, so missing API path isn't fatal.
		return

	# CHANNEL_DATA5 depth — same three-path probe.
	#
	# Phase 0 of the Minecraft-style water rewrite: the generator now
	# writes water bytes into CHANNEL_DATA. One byte per voxel is plenty
	# (level 0-8 + source bit + 3-bit tick = 8 bits exactly), so
	# DEPTH_8_BIT is what we ask for. Default is also 8-bit on most
	# Zylann builds, so this is usually a no-op confirmation, but make
	# it explicit so the storage size can never silently widen and
	# double save-file size.
	#
	# Per the LESSONS_LEARNED.md note: never call set_channel_depth in
	# _generate_block — only on the global VoxelFormat resource here.
	var data_configured: bool = false
	if fmt.has_method("set_channel_depth"):
		fmt.call("set_channel_depth", VoxelBuffer.CHANNEL_DATA5, VoxelBuffer.DEPTH_8_BIT)
		print("[World3D] Set CHANNEL_DATA depth via fmt.set_channel_depth(...)")
		data_configured = true
	if not data_configured and "data_depth" in fmt:
		fmt.set("data_depth", VoxelBuffer.DEPTH_8_BIT)
		print("[World3D] Set CHANNEL_DATA depth via fmt.data_depth")
		data_configured = true
	if not data_configured and "channel_depths" in fmt:
		var depths_d = fmt.get("channel_depths")
		if depths_d is Array:
			depths_d[VoxelBuffer.CHANNEL_DATA5] = VoxelBuffer.DEPTH_8_BIT
			fmt.set("channel_depths", depths_d)
			print("[World3D] Set CHANNEL_DATA depth via fmt.channel_depths[CHANNEL_DATA]")
			data_configured = true
	if not data_configured:
		push_warning("[World3D] VoxelFormat exists but no known API path worked for CHANNEL_DATA; water encoding may break if engine default differs from 8-bit.")

	# Assign the format BEFORE terrain begins generating blocks. The
	# property in our diagnostic dump showed up as `format`, so just
	# write to it. If the terrain has already started generating, this
	# may not retroactively fix existing chunks — fresh save / new game
	# may be needed for the depth to apply across the world.
	terrain.set("format", fmt)
	print("[World3D] terrain.format assigned (CHANNEL_TYPE 8-bit).")


func _snap_spawn_to_ground(retries_remaining: int = 25) -> void:
	# Raycast straight down from a high point above the player and
	# place the player on whatever solid surface we hit. If the
	# raycast misses (terrain chunks not yet loaded), retry after
	# a short delay until either a hit lands or we run out of retries.
	#
	# `retries_remaining` defaults to 25 (× 0.2 s = 5 s total budget).
	# After that we give up — the player will fall from the scene's
	# default Y, which is ugly but never permanently stuck.
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node3D = players[0] as Node3D
	if player == null:
		return

	# Cast from a high origin DOWN through the player's X,Z. Origin
	# above the scene's spawn Y (120) by another 100 m so we cover
	# any terrain peak. Cast down to Y = -200 (well below valley
	# floors) so we cover any depth.
	var origin: Vector3 = Vector3(player.global_position.x, 250.0, player.global_position.z)
	var dest: Vector3 = Vector3(player.global_position.x, -200.0, player.global_position.z)
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(origin, dest)
	# Exclude the player's own collision shape so we don't hit it.
	params.exclude = [player.get_rid()]
	var hit: Dictionary = space.intersect_ray(params)

	if hit.is_empty():
		# No terrain under spawn yet. Voxel chunks still streaming.
		if retries_remaining <= 0:
			# Out of retries — clear _spawn_freeze so the player isn't
			# permanently locked in place. Falling from default Y is
			# uglier than infinite hover but recoverable.
			if "_spawn_freeze" in player:
				player.set("_spawn_freeze", false)
			print("[World3D] Spawn-snap gave up after retries; unfreezing player (will fall from default Y).")
			return
		# Retry after a short delay using a SceneTreeTimer (no scene
		# changes / signals needed). _spawn_freeze stays true during
		# the retry window — _physics_process is gated so the player
		# hovers at the default Y while we keep looking for ground.
		var timer: SceneTreeTimer = get_tree().create_timer(0.2)
		timer.timeout.connect(_snap_spawn_to_ground.bind(retries_remaining - 1))
		return

	# Hit something. Place player just above the hit point — capsule
	# is offset by 0.9 m (half-height) so we add a small margin to
	# avoid clipping into terrain on landing.
	var ground_y: float = hit["position"].y
	player.global_position = Vector3(
		player.global_position.x,
		ground_y + 1.0,  # 1 m above ground = capsule clears the surface
		player.global_position.z,
	)
	# Zero the player's vertical velocity so any momentum from the
	# previous-frame fall doesn't punch them back through the surface.
	if "velocity" in player:
		player.velocity = Vector3.ZERO
	# Ground found — let gravity take over from here.
	if "_spawn_freeze" in player:
		player.set("_spawn_freeze", false)
	print("[World3D] Spawn snapped to ground at Y=%.2f (hit at %.2f); spawn-freeze cleared." % [
		player.global_position.y, ground_y,
	])

	# Spawn ground confirmed — kick off the loading-screen close
	# negotiation. The helper polls Zylann's blocked_lods until the
	# backlog around the player settles (or a max wait elapses), then
	# tells TransitionManager we're ready. TransitionManager has its
	# own min-hold so the loading screen never closes instantly.
	_mark_world_ready_when_settled()


# State tracker for the world-ready signal. Set true once we've called
# TransitionManager.mark_voxel_world_ready, so a re-entrant call from
# _wait_for_ground_under_player (load-from-save path) doesn't double-fire.
var _world_ready_signaled: bool = false


func _mark_world_ready_when_settled() -> void:
	# Combined readiness gate: a DENSE LOD0 spatial probe AND
	# a near-idle Zylann streaming queue. Both must hold for
	# REQUIRED_GOOD_SAMPLES consecutive 0.4 s polls before the
	# loading screen advances.
	#
	# Why this is stricter than the previous 48-probe gate:
	# 48 probes at 4 radii could pass while many LOD0 chunks
	# in the ring were still pending — the rays just happened to
	# hit chunks that were already loaded. The fix is two-fold:
	#
	#   (1) Denser probe: 6 radii × 16 directions = 96 probes.
	#       Tighter angular and radial sampling makes it harder
	#       for missing-LOD0 holes to slip between rays. Probe
	#       still doesn't sample every chunk — that's covered by:
	#
	#   (2) blocked_lods settle gate: Zylann's get_statistics()
	#       reports the LOD-pipeline queue depth as `blocked_lods`.
	#       When it drops to ≤ STREAM_QUEUE_NEAR_IDLE the streamer
	#       has very little left to do globally — any LOD0 chunks
	#       not caught by the spatial probe are also done.
	#
	# Both gates close each other's blind spots: the probe handles
	# "is the local area visually presentable" and the queue gate
	# handles "is the streamer globally finished."
	#
	# Why raycasts ≡ LOD0: in this terrain config
	# (`collision_lod_count = 0`), only LOD0 chunks have collision
	# bodies. A raycast hit is therefore a direct confirmation that
	# the chunk at that location is meshed at full LOD0 resolution.
	# Higher-LOD chunks (LOD1+) are visible but uncollidable, and
	# the raycast passes through them.
	#
	# REQUIRED_GOOD_SAMPLES of 3 × POLL_INTERVAL 0.4 s = 1.2 s of
	# sustained "both gates pass" before signaling. Three samples
	# filter out single-frame races and transient queue dips
	# between request waves.
	#
	# MAX_EXTRA_WAIT 60 s — fully meshing the LOD0 sphere AND
	# letting the queue drain takes longer than just the spatial
	# probe. 60 s matches TransitionManager's loading_seconds cap.
	if _world_ready_signaled:
		return
	const PROBE_RADII_M: Array = [20.0, 40.0, 60.0, 80.0, 100.0, 120.0]
	const PROBE_DIRECTION_COUNT: int = 16
	const STREAM_QUEUE_NEAR_IDLE: int = 15
	const REQUIRED_GOOD_SAMPLES: int = 3
	# 120 s — generator throughput is ~600 LOD0 blocks/s and the LOD0
	# sphere has ~58k blocks at this scale. 60 s wasn't enough cold-start
	# time for the queue to actually drain. Real fix is the bake (Tier 4),
	# which makes this irrelevant.
	const MAX_EXTRA_WAIT: float = 120.0
	const POLL_INTERVAL: float = 0.4

	# Build the ring of unit directions once. 16 directions = every
	# 22.5° around the compass; tight enough that LOD0 chunks
	# (~5–6 m wide at this scale) at the inner radius are nearly
	# always covered by at least one ray nearby.
	var probe_dirs: Array[Vector2] = []
	for i in range(PROBE_DIRECTION_COUNT):
		var theta: float = TAU * float(i) / float(PROBE_DIRECTION_COUNT)
		probe_dirs.append(Vector2(cos(theta), sin(theta)))

	var terrain := get_node_or_null(voxel_terrain_path)
	var total_probes: int = probe_dirs.size() * PROBE_RADII_M.size()
	var elapsed: float = 0.0
	var consecutive_good: int = 0
	var last_hits: int = 0
	var last_blocked: int = -1
	while elapsed < MAX_EXTRA_WAIT:
		await get_tree().create_timer(POLL_INTERVAL).timeout
		elapsed += POLL_INTERVAL
		last_hits = _count_probe_hits(probe_dirs, PROBE_RADII_M)
		# Read Zylann's queue depth. If get_statistics is missing or
		# the field isn't there, fall back to "queue gate is
		# permissive" so the probe alone can still close the screen.
		last_blocked = -1
		if terrain != null and terrain.has_method("get_statistics"):
			var s = terrain.call("get_statistics")
			if s is Dictionary and s.has("blocked_lods"):
				last_blocked = int(s["blocked_lods"])
		var probe_ok: bool = last_hits == total_probes
		var queue_ok: bool = last_blocked < 0 or last_blocked <= STREAM_QUEUE_NEAR_IDLE
		if probe_ok and queue_ok:
			consecutive_good += 1
			if consecutive_good >= REQUIRED_GOOD_SAMPLES:
				_signal_world_ready("probes %d/%d hit AND queue=%d ≤ %d × %d samples after %.1fs" \
					% [last_hits, total_probes, last_blocked,
						STREAM_QUEUE_NEAR_IDLE, REQUIRED_GOOD_SAMPLES, elapsed])
				return
		else:
			consecutive_good = 0
	# Timed out — partial coverage is better than a stuck loading screen.
	_signal_world_ready("timed out at %.1fs (probes %d/%d, queue=%d)" \
		% [MAX_EXTRA_WAIT, last_hits, total_probes, last_blocked])


func _count_probe_hits(probe_dirs: Array[Vector2], probe_radii: Array) -> int:
	# Returns how many of the (direction × radius) probes hit voxel
	# collision. For each direction × radius combination, casts from
	# 200 m above the probe point straight down 400 m so we cover
	# any plausible terrain Y at that XZ — peaks above the player's
	# spawn elevation, deep valleys far below. Player's own collider
	# is excluded so we don't self-hit.
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return 0
	var player: Node3D = players[0] as Node3D
	if player == null:
		return 0
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var p_pos: Vector3 = player.global_position
	var hits: int = 0
	for radius in probe_radii:
		for dir in probe_dirs:
			var probe_x: float = p_pos.x + dir.x * float(radius)
			var probe_z: float = p_pos.z + dir.y * float(radius)
			var origin: Vector3 = Vector3(probe_x, p_pos.y + 200.0, probe_z)
			var dest: Vector3 = Vector3(probe_x, p_pos.y - 200.0, probe_z)
			var params := PhysicsRayQueryParameters3D.create(origin, dest)
			params.exclude = [player.get_rid()]
			if not space.intersect_ray(params).is_empty():
				hits += 1
	return hits


func _signal_world_ready(reason: String) -> void:
	if _world_ready_signaled:
		return
	_world_ready_signaled = true
	print("[World3D] Signaling voxel world ready (%s)." % reason)
	if get_node_or_null("/root/TransitionManager"):
		TransitionManager.mark_voxel_world_ready()


func _apply_saved_player_position() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		push_warning("[World3D] No player in tree to apply saved position to")
		return
	var player: Node3D = players[0] as Node3D
	if player == null:
		return
	player.global_position = GameState.player_position
	# Restore facing direction (Y rotation only — pitch and roll
	# live on the camera, not the body). The CameraRig follows the
	# player body's rotation.y in standard mode, so this also gets
	# the camera looking the same way Roland was looking at save.
	player.rotation.y = GameState.player_rotation_y
	if "velocity" in player:
		player.velocity = Vector3.ZERO
	print("[World3D] Restored player position to %s, rotation_y=%.2f rad" % [
		GameState.player_position, GameState.player_rotation_y
	])

	# Freeze physics until terrain has streamed in below the saved
	# position. Without this freeze, gravity pulls Roland straight
	# through unloaded chunks — by the time voxel collision arrives,
	# he's hundreds of metres below the world. _wait_for_ground_under_player
	# raycasts every 0.2 s; once it finds floor, it unfreezes the player
	# (who then settles onto the actual surface in a frame or two).
	if "_spawn_freeze" in player:
		player.set("_spawn_freeze", true)
	_wait_for_ground_under_player()


func _wait_for_ground_under_player(retries_remaining: int = 25) -> void:
	# Casts a short ray downward from the player to confirm a voxel
	# collider exists below. While terrain is still streaming, the ray
	# misses and we retry every 0.2 s (× 25 = 5 s budget). Once it
	# hits, we clear the spawn-freeze flag and let normal physics run.
	#
	# We don't snap the player to the hit — the saved position is the
	# ground truth (the player WAS standing somewhere when they saved).
	# The natural settle from "saved Y" to "actual collider Y" is
	# usually a fraction of a metre and physics handles it cleanly.
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node3D = players[0] as Node3D
	if player == null:
		return

	# Ray spans from 1 m above the player down 100 m. 1 m up gives the
	# capsule centre clearance so we don't start inside the player's
	# own collider; 100 m down covers any plausible drop including
	# tall caves and surface-to-ocean-floor distances.
	var origin: Vector3 = player.global_position + Vector3(0, 1.0, 0)
	var dest: Vector3 = player.global_position + Vector3(0, -100.0, 0)
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(origin, dest)
	params.exclude = [player.get_rid()]
	var hit: Dictionary = space.intersect_ray(params)

	if hit.is_empty():
		if retries_remaining <= 0:
			# Out of retries — unfreeze anyway so the player isn't
			# permanently stuck. Better to fall through the void with
			# gravity than to be locked in place forever.
			print("[World3D] Saved-position ground check timed out; unfreezing player.")
			if "_spawn_freeze" in player:
				player.set("_spawn_freeze", false)
			# Tell the loading screen to close — partial world is
			# better than a stuck loading screen.
			_signal_world_ready("saved-position ground timeout")
			return
		var timer: SceneTreeTimer = get_tree().create_timer(0.2)
		timer.timeout.connect(_wait_for_ground_under_player.bind(retries_remaining - 1))
		return

	# Ground confirmed. Unfreeze and let physics take it from here.
	if "_spawn_freeze" in player:
		player.set("_spawn_freeze", false)
	print("[World3D] Saved-position ground confirmed at Y=%.2f; unfreezing player." % hit["position"].y)

	# Same world-ready negotiation as the new-game path. blocked_lods
	# polling lets the loading screen close as soon as the saved-area
	# chunks settle, instead of always running the full 45 s timer.
	_mark_world_ready_when_settled()


func _seed_test_pond() -> void:
	# Replaces the legacy WaterFlowManager.add_source_region pond seed.
	# Writes water source bytes into CHANNEL_DATA over the pond's voxel
	# footprint via VoxelEditManager so the bytes go through the queue,
	# get the modified-chunk mark for save persistence, and emit
	# water_changed_at so the mesher rebuilds the affected chunks.
	#
	# Pond footprint: world (-23, -1.5, -1) to (-13, 1.5, 9). At 6 vox/m
	# that's voxel (-138, -9, -6) to (-78, 9, 54), with the surface at
	# voxel Y=9 (= world 1.5). queue_set_water_box uses inclusive-min /
	# exclusive-max convention so we use one-past on the max side.
	if get_node_or_null("/root/VoxelEditManager") == null:
		return
	var voxel_min := Vector3i(-138, -9, -6)
	var voxel_max := Vector3i(-78, 9, 54)
	if VoxelEditManager.queue_set_water_box(voxel_min, voxel_max, WaterByteCodec.SOURCE_BYTE):
		print("[World3D] Test pond water-box queued (%s..%s)." % [voxel_min, voxel_max])
	else:
		push_warning("[World3D] Test pond seed failed (queue full or NoEditZone reject).")
