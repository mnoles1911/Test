extends Node3D

const WaterMaterial := preload("res://scripts/WaterMaterial.gd")

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
#
# DEFAULT OFF (2026-05-18): the 1 Hz [DIAG] line + F8 debug draws are a
# TERRAIN-PERF / LOD-STREAMING investigation tool, not needed for normal
# play or water testing — it spammed the Output panel and drowned the
# [WaterDiag]/[WaterInspect] lines. To re-enable for a terrain/LOD perf
# pass: flip this to true here, or tick "Diag Enabled" on the
# World3DBootstrap node in the World3D.tscn Inspector (no re-edit
# needed). What it gives you is documented in design/PROFILER_AND_
# DIAGNOSTICS.md ("World3DBootstrap [DIAG] line"). [PERF] (Profiler)
# and [WaterDiag] (F4 panel) are SEPARATE and unaffected by this.
@export var diag_enabled: bool = false

var _diag_terrain: Object = null
var _diag_player: Node3D = null
var _diag_viewer: Node3D = null
var _diag_acc_time: float = 0.0
var _diag_last_player_pos: Vector3 = Vector3.ZERO
var _diag_last_player_pos_valid: bool = false
var _diag_debug_draw_on: bool = false

# Cache-miss telemetry — see HeightmapGeneratorBase.get_generated_block_count().
# The adapter exposes this method via the cpp_impl Resource. Drill through
# adapter → cpp_impl in _ready; poll the counter once per [DIAG] tick.
# Each generator call corresponds to a Zylann CACHE MISS. A LOW miss rate
# while walking means we're hitting the SQLite cache; a HIGH miss rate
# means Zylann is regenerating chunks on the fly.
var _diag_gen_counter_source: Object = null
var _diag_last_gen_count: int = 0


const WORKING_SQLITE_PATH: String = "user://voxel_deltas.sqlite"
# The working SQLite that VoxelStreamSQLite on World3D.tscn reads from
# and writes edits back to. Must match the database_path on the .tscn's
# VoxelStreamSQLite sub-resource.

const BAKED_BASELINE_PATH: String = "user://baked_baseline_world3d.sqlite"
# Output of scenes/_dev/BakeWorld3D.tscn. If this file exists at world
# load AND the working file doesn't, we copy baseline → working so the
# player drops into a pre-populated world. Without this seed step the
# C++ generator has to regen every chunk on first load, which (with
# Forward+ Tier 1/2/3 rendering on) can take many minutes and timed
# the spawn freeze out (observed 2026-05-13).

## ⚠ TESTING TOGGLE — re-seeds the working SQLite from the baked baseline
## on EVERY launch (matches the CopperIslesTestBootstrap pattern). This
## verifies the "World3D streaming is slow because the cache is sparse"
## hypothesis: if you flip this ON and the LOD-pop feel disappears, the
## bake coverage is sufficient and we just weren't re-using it. If it
## DOESN'T help, the bake area is too small and needs to be re-run wider.
##
## WIPES PLAYER EDITS each launch — mining, water placement, gravity
## settling — everything outside the baseline gets reset to generator
## output. Flip OFF before real play sessions.
##
## CAVEAT (2026-05-14): the current baked_baseline_world3d.sqlite is
## SMALLER than typical accumulated voxel_deltas.sqlite (582 MB vs
## ~687 MB), and the bake didn't cover the (0, 0) spawn area. Flipping
## this ON regressed cache coverage. Re-bake World3D wider before
## relying on this toggle in earnest.
@export var force_reseed_on_launch: bool = false


func _enter_tree() -> void:
	# Seed copy MUST happen before VoxelLodTerrain's child opens its
	# SQLite stream. Godot's _enter_tree fires top-down (parent before
	# children); _ready fires bottom-up. If we did the copy in _ready,
	# Zylann would have already opened the working file with stale
	# contents and ignored our new copy. This is the same constraint
	# CopperIslesTestBootstrap calls out in its own _enter_tree.
	_seed_from_baseline_if_needed()


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
	# LOD fade duration: tried 2.0 to smooth cross-fade + spread mesh
	# upload, but this Zylann build silently rejects values > 1.0 (the
	# `actual=` readback returned 1.0). Reverted to 1.0 to match what
	# Zylann actually applies — keeps the .tscn / bootstrap state and
	# the engine state in sync so the property dump isn't misleading.
	if "lod_fade_duration" in terrain:
		terrain.set("lod_fade_duration", 1.0)
		print("[World3D] terrain.lod_fade_duration set to 1.0 (actual=%s)" % terrain.get("lod_fade_duration"))

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
		# Resolve the cache-miss counter source. The adapter forwards
		# to its cpp_impl Resource (the actual HeightmapGeneratorBase
		# subclass). The C++ base bound get_generated_block_count().
		_diag_gen_counter_source = _resolve_gen_counter_source(gen)
		if _diag_gen_counter_source != null:
			# Reset to zero so the first poll reports new misses cleanly.
			if _diag_gen_counter_source.has_method("reset_generated_block_count"):
				_diag_gen_counter_source.call("reset_generated_block_count")
			print("[World3D] Cache-miss telemetry armed on %s." % _diag_gen_counter_source)
		else:
			print("[World3D] Cache-miss telemetry unavailable (no get_generated_block_count method found).")
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

	# --- Snap the campfire OmniLight onto the terrain surface ---
	# The .tscn hard-codes Campfire to world Y=0.5, which assumes
	# ground_y == 0. The C++ cubic generator places real ground anywhere
	# from ~20-50 m depending on noise at the campfire's X,Z, so without
	# this snap the campfire either floats above terrain or is buried.
	# Uses the same generator.get_ground_voxel_y_at() path as the player
	# spawn pre-snap, so the two stay consistent.
	_snap_campfire_to_ground()

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

# Water Voxel V2 (Minecraft model, 2026-05-16): water is TYPE id 5, a
# transparent blocky cube whose material is the v8 depth-fade water
# shader (NOT an atlas tile — the shader IS the water look). Applied at
# runtime here for the same Zylann .tres-doesn't-restore reason as the
# atlas materials. See design/WATER_VOXEL_V2_PLAN.md.
# The LEGACY cube water slot (id 5) — this block applies the water
# shader/transparency/collision to the OLD transparent-cube model that
# still lives in blocky_library.tres (kept so pre-pivot saves render).
# It must be 5 (LEGACY_WATER_ID), NOT BODY_ID — BODY_ID is now the
# full-level FLUID id 23, which isn't in models_arr at this point, so
# pointing here skipped the whole block (regression fixed 2026-05-18).
const _WATER_MATERIAL_ID: int = WaterMaterial.LEGACY_WATER_ID
const _WATER_MATERIAL_PATH: String = "res://assets/shaders/water_material.tres"

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

	# --- Water (id 5): the Minecraft-model water block. ---
	# Unlike the atlas materials above, water wears the v8 depth-fade
	# SHADER material — the shader is the water look, there is no atlas
	# tile. Critical Minecraft behaviour: water must NOT cull the faces
	# of the opaque blocks it touches, or the lakebed/terrain under and
	# beside the water becomes invisible (you'd see nothing through it).
	# transparency_index = 2 (its own class, distinct from leaves' 1) so
	# the blocky mesher culls water↔water internal faces (only the outer
	# shell of a body of water renders — no per-cube overdraw) while
	# still drawing water↔terrain and water↔air faces.
	if _WATER_MATERIAL_ID >= 0 and _WATER_MATERIAL_ID < models_arr.size():
		var wm = models_arr[_WATER_MATERIAL_ID]
		if wm == null:
			push_warning("[World3D] inject_atlas_materials: water model[%d] is null in blocky_library.tres — water won't render." % _WATER_MATERIAL_ID)
		else:
			var water_mat: Material = load(_WATER_MATERIAL_PATH) as Material
			if water_mat == null:
				push_warning("[World3D] inject_atlas_materials: failed to load %s — water will be untextured." % _WATER_MATERIAL_PATH)
			elif wm.has_method("set_material_override"):
				wm.call("set_material_override", 0, water_mat)
				# transparency_index = 2 (water's own class) makes the
				# blocky mesher cull water↔water internal faces — a body
				# of water meshes as a hollow SHELL, not a solid fill of
				# millions of internal cube faces (that was a ~10M-prim
				# perf catastrophe). Because water is transparent, the
				# single boundary face against terrain is see-through, so
				# the lakebed is still visible WITHOUT disabling neighbor
				# culling. (Earlier `culls_neighbors=false` defeated the
				# water↔water culling and caused the solid fill — removed.)
				wm.set("transparency_index", 2)
				# KEYSTONE (2026-05-17): water must be NON-SOLID so the
				# player falls in and the existing
				# WaterFlowManager.is_position_in_water / Player3D swim
				# path takes over. Zylann VoxelBlockyModelCube has TWO
				# independent collider paths and BOTH must be killed:
				#   1. Box collision  — `collision_aabbs` (default = one
				#      full unit cube). Cleared via set_collision_aabbs([]).
				#   2. Per-surface MESH collision — `collision_enabled_0`
				#      (the probe showed it = true). This is what was
				#      STILL generating the floor after path 1 was empty:
				#      the [WaterProbe] proved on_floor=true with
				#      collision_aabbs=[] while below_type=5. Disabled via
				#      set_mesh_collision_enabled(surface_index, enabled)
				#      — it is a 2-ARG per-surface API (calling it with one
				#      arg is what crashed an earlier load). A cube model
				#      has exactly one surface, index 0.
				# collision_mask=0 is kept as belt-and-suspenders.
				# Readback strings use str()+ concatenation, NOT
				# `"%s" % arr` — an emptied array is `[]` and `String % []`
				# is read as ZERO format args → a runtime error that
				# previously aborted this function before lib.bake().
				wm.call("set_collision_aabbs", [])
				wm.call("set_collision_mask", 0)
				if wm.has_method("set_mesh_collision_enabled"):
					# surface 0 = the cube's only surface (collision_enabled_0)
					wm.call("set_mesh_collision_enabled", 0, false)
				var _ca = wm.call("get_collision_aabbs")
				var _cm = wm.call("get_collision_mask")
				var _mc = "?"
				if wm.has_method("is_mesh_collision_enabled"):
					_mc = str(wm.call("is_mesh_collision_enabled", 0))
				print("[World3D][WaterColl] water model[5] non-solid: collision_aabbs=" + str(_ca) + " collision_mask=" + str(_cm) + " mesh_collision_surf0=" + _mc)
				print("[World3D] inject_atlas_materials: water model[5] ← depth-fade shader (transparent, shell-meshed, NON-COLLIDING).")
			else:
				push_warning("[World3D] inject_atlas_materials: water model lacks set_material_override; water won't render.")

	# --- Native fluid water (ids 16..23): the pivot's per-level models. ---
	# 8 VoxelBlockyModelFluid (level 1..8) sharing ONE VoxelBlockyFluid,
	# injected at RUNTIME via add_model() — NOT stored in the .tres (same
	# "bootstrap is source of truth" reason as the materials above, and it
	# sidesteps Zylann's .tres-doesn't-restore bug for fluid props). The
	# blocky mesher auto-slopes the top corners from neighbour levels
	# (smooth surface, full LOD, no custom mesher) — the whole point of
	# the pivot. Collision disabled exactly like the cube water (KEYSTONE:
	# the player must fall in; WaterFlowManager/Player3D swim path takes
	# over). The cube water model (id 5) stays in the library — the C++
	# generator still emits it until Phase 4; both read as water.
	if lib.has_method("add_model"):
		var pre_count: int = models_arr.size()
		if pre_count != WaterMaterial.WATER_FLUID_BASE_ID:
			push_error("[World3D][WaterFluid] library has %d models, expected %d before fluid inject — ids would misalign with WaterMaterial. Fix blocky_library.tres or WATER_FLUID_BASE_ID." % [pre_count, WaterMaterial.WATER_FLUID_BASE_ID])
		else:
			var water_mat2: Material = load(_WATER_MATERIAL_PATH) as Material
			var fluid: Object = ClassDB.instantiate("VoxelBlockyFluid")
			if fluid == null:
				push_error("[World3D][WaterFluid] could not instantiate VoxelBlockyFluid (GATE 0 said registered) — aborting fluid inject.")
			else:
				if water_mat2 != null and fluid.has_method("set_material"):
					fluid.call("set_material", water_mat2)
				if fluid.has_method("set_dip_when_flowing_down"):
					fluid.call("set_dip_when_flowing_down", true)  # Minecraft falling-water dip (#12)
				var added_ids: Array[int] = []
				for level in range(1, WaterMaterial.WATER_LEVEL_COUNT + 1):  # 1..8
					var fm: Object = ClassDB.instantiate("VoxelBlockyModelFluid")
					if fm == null:
						push_error("[World3D][WaterFluid] could not instantiate VoxelBlockyModelFluid (level %d)." % level)
						break
					fm.call("set_fluid", fluid)
					fm.call("set_level", level)
					if water_mat2 != null and fm.has_method("set_material_override"):
						fm.call("set_material_override", 0, water_mat2)
					# Water's own transparency class (mirrors the cube's 2)
					# so fluid sorts after opaque solids and the lakebed
					# stays visible. Exact value = Phase-2 designer-visual
					# checkpoint.
					if fm.has_method("set_transparency_index"):
						fm.call("set_transparency_index", 2)
					# NON-SOLID — identical KEYSTONE to the cube water.
					if fm.has_method("set_collision_aabbs"):
						fm.call("set_collision_aabbs", [])
					if fm.has_method("set_collision_mask"):
						fm.call("set_collision_mask", 0)
					if fm.has_method("set_mesh_collision_enabled"):
						fm.call("set_mesh_collision_enabled", 0, false)
					added_ids.append(int(lib.call("add_model", fm)))
				var want: Array[int] = []
				for L in range(1, WaterMaterial.WATER_LEVEL_COUNT + 1):
					want.append(WaterMaterial.WATER_FLUID_BASE_ID + L - 1)
				print("[World3D][WaterFluid] injected %d fluid level-models at ids %s sharing 1 VoxelBlockyFluid (dip_when_flowing_down=true)." % [added_ids.size(), str(added_ids)])
				if added_ids != want:
					push_error("[World3D][WaterFluid] add_model ids %s != expected %s — WaterMaterial id math will be wrong." % [str(added_ids), str(want)])
				else:
					print("[World3D][WaterFluid] ids match WaterMaterial (base=%d, level L -> id BASE+L-1, full=%d)." % [WaterMaterial.WATER_FLUID_BASE_ID, WaterMaterial.FULL_FLUID_ID])
	else:
		push_error("[World3D][WaterFluid] library has no add_model() — cannot inject native fluid models.")

	# Disable baked tangents. Nothing in this project uses a normal map
	# (atlas = StandardMaterial3D albedo-only nearest; water v9 shader
	# references no TANGENT/BINORMAL). With tangents baked, the blocky
	# mesher must emit a vertex*4 tangent array for EVERY model surface;
	# the runtime-injected VoxelBlockyModelFluid surfaces don't supply a
	# matching one, so the real Vulkan renderer rejects each fluid chunk
	# mesh — the repeating "_surface_set_data: array.size() !=
	# p_vertex_array_len * 4 / add_surface_from_arrays" spam seen near
	# water (2026-05-19). The --headless dummy driver skips that
	# validation, which is why it only shows on GPU. No tangents needed
	# anywhere → turn them off so no tangent array is built at all.
	if lib.has_method("set_bake_tangents"):
		lib.call("set_bake_tangents", false)
	elif "bake_tangents" in lib:
		lib.set("bake_tangents", false)

	# Re-bake so Zylann recomputes per-cube UVs from the freshly
	# written tile coords + atlas_size_in_tiles (and now WITHOUT tangents).
	if lib.has_method("bake"):
		lib.bake()

	print("[World3D] inject_atlas_materials: re-applied tiles + atlas mat to %d models, library re-baked." % injected)

	# --- [WaterFluidDiag] hard readback (2026-05-18 debug) -------------
	# White/solid/F6-inert fluid means material_override and/or collision
	# and/or the fluid link did NOT take, or the water material failed to
	# load, or the lib didn't pick up the material. Print ground truth so
	# we fix from data, not guesses. Cheap, runs once at boot.
	var _wfd_mat = load(_WATER_MATERIAL_PATH)
	var _wfd_sh = _wfd_mat.get("shader") if _wfd_mat != null else null
	print("[WaterFluidDiag] water_material.tres load=%s shader=%s code_len=%s" % [
		("null" if _wfd_mat == null else _wfd_mat.get_class()),
		("null" if _wfd_sh == null else _wfd_sh.get_class()),
		("?" if _wfd_sh == null else str(String(_wfd_sh.get("code")).length()))])
	if "models" in lib:
		var _wfd_models: Array = lib.get("models")
		print("[WaterFluidDiag] lib model count=%d" % _wfd_models.size())
		var _fid: int = WaterMaterial.WATER_FLUID_BASE_ID  # 16, level 1
		if _fid < _wfd_models.size() and _wfd_models[_fid] != null:
			var fm0 = _wfd_models[_fid]
			var mo = fm0.call("get_material_override", 0) if fm0.has_method("get_material_override") else "<no method>"
			var fl = fm0.call("get_fluid") if fm0.has_method("get_fluid") else "<no method>"
			var fl_mat = fl.call("get_material") if (fl != null and fl is Object and fl.has_method("get_material")) else "<n/a>"
			var aabbs = fm0.call("get_collision_aabbs") if fm0.has_method("get_collision_aabbs") else "<no method>"
			var meshcoll = fm0.call("is_mesh_collision_enabled", 0) if fm0.has_method("is_mesh_collision_enabled") else "<no method>"
			var cmask = fm0.call("get_collision_mask") if fm0.has_method("get_collision_mask") else "<no method>"
			print("[WaterFluidDiag] model[%d] class=%s level=%s fluid=%s" % [
				_fid, fm0.get_class(),
				str(fm0.call("get_level")) if fm0.has_method("get_level") else "?",
				("null" if fl == null else "set")])
			print("[WaterFluidDiag] model[%d] material_override(0)=%s fluid.material=%s" % [
				_fid, ("null" if mo == null else (mo.get_class() if mo is Object else str(mo))),
				("null" if fl_mat == null else (fl_mat.get_class() if fl_mat is Object else str(fl_mat)))])
			print("[WaterFluidDiag] model[%d] collision_aabbs=%s mesh_collision_enabled(0)=%s collision_mask=%s" % [
				_fid, str(aabbs), str(meshcoll), str(cmask)])
	if lib.has_method("get_materials"):
		var _mats = lib.call("get_materials")
		var _mat_classes := PackedStringArray()
		if _mats is Array:
			for _m in _mats:
				_mat_classes.append("null" if _m == null else _m.get_class())
		print("[WaterFluidDiag] lib.get_materials() count=%d classes=%s" % [
			(_mats.size() if _mats is Array else -1), str(_mat_classes)])


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
	# Cache-miss rate: chunks the generator was actually called on
	# since the previous DIAG tick. High = Zylann is regenerating
	# new territory; low (or zero) = SQLite cache is serving requests.
	# Caps at 9999/s in the format string so the line stays readable
	# during initial spawn-load when 1000s of chunks generate at once.
	var miss_per_s: String = "?"
	if _diag_gen_counter_source != null \
			and _diag_gen_counter_source.has_method("get_generated_block_count"):
		var cur: int = _diag_gen_counter_source.call("get_generated_block_count")
		var delta_count: int = cur - _diag_last_gen_count
		_diag_last_gen_count = cur
		miss_per_s = "%d" % int(float(delta_count) / dt) if dt > 0.0 else "0"
	print("[DIAG] player=(%.1f, %.1f, %.1f)  speed=%.2f m/s  viewer=(%.1f, %.1f, %.1f)  lag_xz=%.1f m  cache_miss=%s/s%s" % [
		p_pos.x, p_pos.y, p_pos.z, speed,
		v_pos.x, v_pos.y, v_pos.z, lag_xz,
		miss_per_s, stats,
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


func _seed_from_baseline_if_needed() -> void:
	# If the working DB already exists, leave it alone — the player has
	# an in-progress world and their edits live there. Stomping it would
	# wipe their progress.
	# EXCEPTION: when force_reseed_on_launch is on (testing toggle), we
	# proceed to copy regardless. See the @export comment up top.
	if FileAccess.file_exists(WORKING_SQLITE_PATH) and not force_reseed_on_launch:
		return
	if force_reseed_on_launch and FileAccess.file_exists(WORKING_SQLITE_PATH):
		print("[World3D] force_reseed_on_launch=true — overwriting working SQLite with baseline.")
	# No baseline shipped/baked yet? Silent fall through to live
	# regeneration. This is expected the very first time you run the
	# project before any bake has happened.
	if not FileAccess.file_exists(BAKED_BASELINE_PATH):
		print(
			"[World3D] No baked baseline at %s — falling through to live regen."
			% BAKED_BASELINE_PATH
		)
		print(
			"[World3D]   To pre-populate, run scenes/_dev/BakeWorld3D.tscn."
		)
		return
	# Resolve to OS-absolute paths so DirAccess.copy_absolute can bridge
	# the user:// prefix (the high-level .copy() refuses cross-prefix
	# copies in some Godot versions).
	var src_abs: String = ProjectSettings.globalize_path(BAKED_BASELINE_PATH)
	var dst_abs: String = ProjectSettings.globalize_path(WORKING_SQLITE_PATH)
	var user_dir := DirAccess.open("user://")
	if user_dir == null:
		push_warning("[World3D] user:// not accessible; skipping baseline seed.")
		return
	var err: int = DirAccess.copy_absolute(src_abs, dst_abs)
	if err == OK:
		var size_bytes: int = 0
		var f: FileAccess = FileAccess.open(WORKING_SQLITE_PATH, FileAccess.READ)
		if f != null:
			size_bytes = f.get_length()
			f.close()
		print("[World3D] Seeded %s from baseline (%.1f MB)." % [
			WORKING_SQLITE_PATH, float(size_bytes) / (1024.0 * 1024.0),
		])
	else:
		push_warning("[World3D] Failed to copy baseline (err=%d)." % err)


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


func _snap_campfire_to_ground() -> void:
	# Lift the Campfire OmniLight3D so its mesh rests on the generated
	# terrain surface at its authored X,Z. The .tscn places it at world
	# Y=0.5, which is correct only if ground_y happens to be 0.
	#
	# CampfireMesh local layout (from World3D.tscn):
	#   - OmniLight3D root transform.origin.y is what we set here.
	#   - CampfireMesh child local Y = -0.4 (mesh center below the light).
	#   - BoxMesh size = (0.5, 0.3, 0.5), so mesh half-height = 0.15.
	# Bottom of mesh in world space = root_y + (-0.4) - 0.15 = root_y - 0.55.
	# To park the mesh's bottom on the ground, set root_y = ground_y + 0.55.
	var campfire := get_node_or_null("Campfire") as Node3D
	if campfire == null:
		return
	var terrain := get_node_or_null(voxel_terrain_path) as Node3D
	if terrain == null:
		return
	var terrain_scale: float = terrain.transform.basis.get_scale().y
	if absf(terrain_scale) < 0.00001:
		terrain_scale = 0.166667  # fall-through: assume 6 vox/m
	var voxels_per_m: float = 1.0 / terrain_scale
	var generator = terrain.get("generator") if "generator" in terrain else null
	if generator == null:
		return
	var c_local: Vector3 = campfire.transform.origin
	var vx: int = int(roundf(c_local.x * voxels_per_m))
	var vz: int = int(roundf(c_local.z * voxels_per_m))
	# Drill through adapter → cpp_impl if the method isn't on the
	# generator directly (mirrors _pre_snap_player_to_generator_ground).
	var ground_voxel_y: int = 0
	var found: bool = false
	if generator.has_method("get_ground_voxel_y_at"):
		ground_voxel_y = int(generator.call("get_ground_voxel_y_at", vx, vz))
		found = true
	elif "cpp_impl" in generator:
		var cpp = generator.get("cpp_impl")
		if cpp != null and cpp.has_method("get_ground_voxel_y_at"):
			ground_voxel_y = int(cpp.call("get_ground_voxel_y_at", vx, vz))
			found = true
	if not found:
		print("[World3D] campfire snap: generator has no get_ground_voxel_y_at; leaving Y as authored.")
		return
	const CAMPFIRE_GROUND_OFFSET_M: float = 0.55
	var new_y: float = float(ground_voxel_y) * terrain_scale + CAMPFIRE_GROUND_OFFSET_M
	var old_y: float = c_local.y
	campfire.transform.origin = Vector3(c_local.x, new_y, c_local.z)
	print("[World3D] Campfire snapped Y %.2f → %.2f (ground vox=%d, scale=%.4f)" % [
		old_y, new_y, ground_voxel_y, terrain_scale,
	])


func _pre_snap_player_to_generator_ground() -> void:
	# Analytical ground lookup so the player doesn't spawn 100m above
	# terrain and fall through the LOD0 collision gap.
	#
	# Sequence:
	#   1. Find player + terrain in tree
	#   2. Read terrain transform scale (1/6 → 6 vox/m)
	#   3. Convert player world X,Z to voxel coords
	#   4. Call generator.get_ground_voxel_y_at(vx, vz) — for the
	#      adapter pattern, drill through to cpp_impl if needed
	#   5. Convert voxel-Y back to world-Y, add a small margin
	#   6. Teleport the player; zero velocity so accumulated gravity
	#      doesn't punch through after unfreeze
	#
	# Caller is responsible for spawn-freeze + the raycast retry that
	# confirms collision has streamed. This function only handles the
	# "put the player in the right neighbourhood" part.

	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node3D = players[0] as Node3D
	if player == null:
		return

	var terrain := get_node_or_null(voxel_terrain_path) as Node3D
	if terrain == null:
		return

	var terrain_scale: float = terrain.transform.basis.get_scale().y
	if absf(terrain_scale) < 0.00001:
		terrain_scale = 0.166667  # fall-through safety: assume 6 vox/m
	var voxels_per_m: float = 1.0 / terrain_scale

	var generator = terrain.get("generator") if "generator" in terrain else null
	if generator == null:
		return

	var vx: int = int(roundf(player.global_position.x * voxels_per_m))
	var vz: int = int(roundf(player.global_position.z * voxels_per_m))

	# Drill through adapter → cpp_impl if the method isn't on the
	# generator directly (same pattern as WorldBakeController).
	var ground_voxel_y: int = 0
	var found: bool = false
	if generator.has_method("get_ground_voxel_y_at"):
		ground_voxel_y = int(generator.call("get_ground_voxel_y_at", vx, vz))
		found = true
	elif "cpp_impl" in generator:
		var cpp = generator.get("cpp_impl")
		if cpp != null and cpp.has_method("get_ground_voxel_y_at"):
			ground_voxel_y = int(cpp.call("get_ground_voxel_y_at", vx, vz))
			found = true
	if not found:
		print("[World3D] pre-snap: generator has no get_ground_voxel_y_at; skipping analytical ground lookup.")
		return

	# Margin above ground: 3m world. Gives capsule clearance + a
	# little air-time so any leftover gravity from the freeze frame
	# settles cleanly when the freeze clears.
	const GROUND_MARGIN_M: float = 3.0
	var new_y: float = float(ground_voxel_y) * terrain_scale + GROUND_MARGIN_M

	var old_y: float = player.global_position.y
	player.global_position = Vector3(
		player.global_position.x,
		new_y,
		player.global_position.z,
	)
	if "velocity" in player:
		player.velocity = Vector3.ZERO
	print("[World3D] pre-snap: Y %.1f → %.1f (ground vox=%d, scale=%.4f)" % [
		old_y, new_y, ground_voxel_y, terrain_scale,
	])


# State for the per-physics-frame wiggle + raycast loop. See
# _physics_process below for the rationale (user-observed:
# Zylann CLIPBOX doesn't stream chunks for a STATIONARY viewer).
var _spawn_wiggle_active: bool = false
var _spawn_wiggle_start_msec: int = 0
var _spawn_wiggle_frame: int = 0
var _spawn_timeout_warned: bool = false

# Saved terrain.view_distance during spawn. Default 512 voxels = ~85 m
# means Zylann has to build a ~1700-chunk pyramid before the player is
# safe. We shrink to 96 voxels (~16 m, just past the player's view of
# their feet) during spawn so Zylann only has to load ~30 chunks before
# the raycast hits ground. After ground hit we restore the full 512 so
# the rest of the world streams in as normal (LOD pyramid expands
# outward, respecting the existing PrefetchViewer).
var _suspend_terrain: Object = null
var _suspend_view_distance: int = -1
const SPAWN_VIEW_DISTANCE_VOX: int = 96
const SPAWN_WIGGLE_MAX_S: float = 45.0
# Bumped 15 → 45s on 2026-05-13 after user reported falling through the
# world when voxel_deltas.sqlite was deleted. Cold-cache regen (no
# pre-baked chunks) needs more time for Zylann to stream + generate
# chunks around the player before terrain collision exists. 15s was
# fine for warm-cache loads but timed out during cold regen.
# Wiggle amplitude — REVERTED to 0.001 (1 mm) on 2026-05-12 after a
# 10mm × dual-axis tune blew up. Zylann started doing 200ms/frame of
# detect work and dropped 16k chunk loads per second — the wiggle
# was invalidating the chunk box faster than Zylann could process
# each batch, causing churn. 1mm × single-axis is the proven config.
const SPAWN_WIGGLE_AMPLITUDE_M: float = 0.001   # 1 mm per-frame nudge

# Wiggle cadence — only fire the nudge every N physics frames. At
# 60Hz physics this means N=6 → 10 nudges/sec, giving Zylann ~6
# frames to process each chunk batch before the next nudge
# invalidates again. Eliminates the saturate-and-drop thrash that
# 60Hz nudging caused. Raycast still runs every frame regardless.
const SPAWN_WIGGLE_FRAME_INTERVAL: int = 6


func _snap_spawn_to_ground(_retries_remaining: int = 0) -> void:
	# Three-phase spawn:
	#
	#   Phase 1: analytical pre-snap via the generator's
	#     get_ground_voxel_y_at(). Teleports the player from the .tscn
	#     default Y=120 down to ground+3m (~Y=23-31 on cubic noise) so
	#     they're inside the LOD0 view-distance sphere.
	#
	#   Phase 2: per-physics-frame WIGGLE + raycast (in _physics_process
	#     below, gated by _spawn_wiggle_active). The wiggle is a
	#     ±1mm position nudge each frame — user observation 2026-05-12:
	#     Zylann's CLIPBOX (and likely the legacy octree too) only
	#     re-evaluates the chunk set when the viewer's position
	#     changes. A frozen viewer == no chunks stream, no collision
	#     ever builds, raycast never hits, freeze times out, player
	#     falls. The mm-scale nudge forces Zylann to keep re-scanning
	#     each frame; chunks stream normally; collision builds; raycast
	#     succeeds. Visually invisible.
	#
	#   Phase 3: on raycast hit, snap to ground+1m and clear freeze.
	#     If no hit by SPAWN_WIGGLE_MAX_S (12s safety net), clear
	#     freeze anyway so the player isn't permanently locked. The
	#     pre-snap left them at ground+3m so the worst-case fall is
	#     small even on a complete failure.
	#
	# _retries_remaining parameter retained for call-site compat but
	# unused — the wiggle loop self-times via SPAWN_WIGGLE_MAX_S.
	_pre_snap_player_to_generator_ground()
	_suspend_expensive_rendering_for_spawn()
	_spawn_wiggle_active = true
	_spawn_wiggle_frame = 0
	_spawn_wiggle_start_msec = Time.get_ticks_msec()


func _suspend_expensive_rendering_for_spawn() -> void:
	# Shrink terrain.view_distance to SPAWN_VIEW_DISTANCE_VOX so Zylann
	# only has to stream a small bubble around the player before
	# collision exists. Restored on raycast-hit, then the rest of the
	# world streams in progressively (LOD pyramid expands outward,
	# respecting the existing PrefetchViewer).
	#
	# Note: SDFGI + volumetric fog are intentionally NOT auto-disabled
	# here (user preference 2026-05-13). They're heavy during cold-cache
	# regen, but the supported workaround is to pre-bake the world via
	# scenes/_dev/BakeWorld3D.tscn so the SQLite has all chunks ready
	# before the gameplay scene loads.
	var terrain: Object = get_node_or_null(voxel_terrain_path)
	if terrain != null and "view_distance" in terrain:
		_suspend_terrain = terrain
		_suspend_view_distance = terrain.get("view_distance") as int
		terrain.set("view_distance", SPAWN_VIEW_DISTANCE_VOX)
		print(
			"[World3D] Shrunk view_distance %d → %d for spawn-load."
			% [_suspend_view_distance, SPAWN_VIEW_DISTANCE_VOX]
		)


func _resume_expensive_rendering_after_spawn() -> void:
	# Mirror of the suspension. Called from the wiggle's raycast-hit
	# branch (after we know the player has ground under them).
	if _suspend_terrain != null and _suspend_view_distance > 0:
		_suspend_terrain.set("view_distance", _suspend_view_distance)
		print(
			"[World3D] Restored view_distance to %d."
			% _suspend_view_distance
		)
		_suspend_terrain = null
		_suspend_view_distance = -1


func _physics_process(_delta: float) -> void:
	# Spawn wiggle loop. Only active during the freeze window.
	if not _spawn_wiggle_active:
		return

	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node3D = players[0] as Node3D
	if player == null:
		return

	# Step 1: nudge X by ±SPAWN_WIGGLE_AMPLITUDE_M every Nth frame.
	# Zylann's CLIPBOX only re-evaluates chunks when the viewer's
	# transform changes — but if it changes EVERY frame, Zylann
	# saturates: it queues a chunk batch, the next frame's nudge
	# invalidates the box, the batch is canceled before any load
	# completes, and dropped_block_loads explodes (16k+ observed
	# 2026-05-12 with 60Hz nudging). Per-N-frame gating gives Zylann
	# breathing room to actually finish each batch.
	#
	# Single-axis (just X) is the proven config from the first
	# successful test. Dual-axis (X+Z) made the thrash worse.
	_spawn_wiggle_frame += 1
	if _spawn_wiggle_frame % SPAWN_WIGGLE_FRAME_INTERVAL == 0:
		var sign_x: float = 1.0 if ((_spawn_wiggle_frame / SPAWN_WIGGLE_FRAME_INTERVAL) % 2 == 0) else -1.0
		player.global_position.x += SPAWN_WIGGLE_AMPLITUDE_M * sign_x

	# Step 2: raycast for collision. As soon as Zylann builds a
	# collider below the player, this hits and we snap + unfreeze.
	var origin: Vector3 = Vector3(player.global_position.x, player.global_position.y + 100.0, player.global_position.z)
	var dest: Vector3 = Vector3(player.global_position.x, player.global_position.y - 200.0, player.global_position.z)
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(origin, dest)
	params.exclude = [player.get_rid()]
	var hit: Dictionary = space.intersect_ray(params)

	if not hit.is_empty():
		# Got ground. Final placement = ground + 1 m capsule clearance.
		var ground_y: float = hit["position"].y
		player.global_position = Vector3(
			player.global_position.x,
			ground_y + 1.0,
			player.global_position.z,
		)
		if "velocity" in player:
			player.velocity = Vector3.ZERO
		if "_spawn_freeze" in player:
			player.set("_spawn_freeze", false)
		_spawn_wiggle_active = false
		# Restore SDFGI / volumetric fog / view_distance now that the
		# player is grounded. Rest of the world streams in outward
		# behind these settings.
		_resume_expensive_rendering_after_spawn()
		var elapsed_s: float = (Time.get_ticks_msec() - _spawn_wiggle_start_msec) / 1000.0
		print("[World3D] Spawn snapped to ground at Y=%.2f (hit at %.2f, %.1fs wiggle); spawn-freeze cleared." % [
			player.global_position.y, ground_y, elapsed_s,
		])
		_mark_world_ready_when_settled()
		return

	# Step 3: log progress on the soft timeout, but DO NOT unfreeze.
	# Previously this gave up at SPAWN_WIGGLE_MAX_S and unfroze the
	# player even when raycast still hit nothing. On cold-cache regen
	# (no SQLite present), Zylann can need several minutes to generate
	# enough chunks for collision below the player — unfreezing early
	# drops them through the world into the void (observed 2026-05-13,
	# player Y went from 30 → -8000 over a few seconds).
	#
	# Now we stay frozen as long as the raycast keeps missing. The
	# player is in a controlled hover at the analytical pre-snap Y;
	# eventually Zylann finishes a chunk under them and the hit-above
	# branch fires. If this never happens, the user should quit and
	# run scenes/_dev/BakeWorld3D.tscn to pre-populate the SQLite —
	# print a hint so they know what to do.
	var elapsed_s: float = (Time.get_ticks_msec() - _spawn_wiggle_start_msec) / 1000.0
	if elapsed_s > SPAWN_WIGGLE_MAX_S and not _spawn_timeout_warned:
		_spawn_timeout_warned = true
		print(
			"[World3D] Spawn still waiting for ground after %.1fs."
			% elapsed_s
		)
		print(
			"[World3D]   Cold-cache regen can take several minutes."
			+ " If this hangs forever, quit and run"
			+ " scenes/_dev/BakeWorld3D.tscn to pre-bake the SQLite."
		)
		print(
			"[World3D]   Or restore the previous voxel_deltas.sqlite"
			+ " from a backup."
		)

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
	# Deterministic test pond for water QA (swim / underwater filter /
	# dig-near-water / waterline behaviour). Writes TYPE-5 water over a
	# footprint via VoxelEditManager so it goes through the queue, gets
	# the modified-chunk mark for save persistence, and emits
	# water_changed_at so the mesher rebuilds the affected chunks.
	#
	# RELOCATED + slope-robust 2026-05-17 (backlog #2). The legacy
	# footprint was world (-23,-1.5,-1)..(-13,1.5,9) — fixed at world
	# Y≈0, ~70 voxels BELOW sea level (72), buried in rock: unreachable,
	# never testable. v1 of the relocation anchored the whole footprint
	# to ONE ground sample at the centre — but the terrain near spawn is
	# steep (ground vox 172 @ spawn(0,0), 155 @ campfire(-3,0), 128 @
	# pond(12,0) — ~7 m drop over 12 m). A single-sample box on that
	# slope is malformed: the uphill side stays roofed by solid rock
	# (not open to sky), the downhill side has the box bottom floating
	# in air. v2: sample ground across the WHOLE footprint, EXCAVATE the
	# cuboid to AIR up to the highest ground in it (so every side opens
	# to the sky with clean walls), then FILL the lower part with water.
	# Result: a proper open pool dug into the hillside on any slope,
	# ~3 m deep, surface ~flush with the LOW (downhill) approach so the
	# player can walk straight in (wade → swim → fully submerge: tests
	# the underwater filter + waterline-jitter item). Verify with
	# WaterDiag F5 standing in it — [WaterInspect] top= should match the
	# surfaceVoxY printed below; navigate via the F4 panel's player pos
	# to world X≈12, Z≈0.
	if get_node_or_null("/root/VoxelEditManager") == null:
		return

	var terrain := get_node_or_null(voxel_terrain_path) as Node3D
	if terrain == null:
		push_warning("[World3D] Test pond: no terrain; skipped.")
		return
	var terrain_scale: float = terrain.transform.basis.get_scale().y
	if absf(terrain_scale) < 0.00001:
		terrain_scale = 0.166667  # fall-through: assume 6 vox/m
	var voxels_per_m: float = 1.0 / terrain_scale

	# Pond footprint in WORLD metres, then → voxels. Centred at world
	# (12, 0); 7 m × 7 m; 3 m deep.
	const POND_CENTER_X_M: float = 12.0
	const POND_CENTER_Z_M: float = 0.0
	const POND_HALF_M: float = 3.5      # → 7 m square footprint
	const POND_DEPTH_M: float = 3.0     # water depth below the surface
	const POND_RIM_VOX: int = 4         # extra air cleared above g_max
	var cx_vox: int = int(roundf(POND_CENTER_X_M * voxels_per_m))
	var cz_vox: int = int(roundf(POND_CENTER_Z_M * voxels_per_m))
	var half_vox: int = int(roundf(POND_HALF_M * voxels_per_m))
	var depth_vox: int = int(roundf(POND_DEPTH_M * voxels_per_m))

	# Resolve the object that answers get_ground_voxel_y_at (generator,
	# or its cpp_impl behind the adapter) — same path the spawn pre-snap
	# + campfire snap use, so all anchor consistently.
	var generator = terrain.get("generator") if "generator" in terrain else null
	var ground_src: Object = null
	if generator != null:
		if generator.has_method("get_ground_voxel_y_at"):
			ground_src = generator
		elif "cpp_impl" in generator:
			var cpp = generator.get("cpp_impl")
			if cpp != null and cpp.has_method("get_ground_voxel_y_at"):
				ground_src = cpp

	# Sample ground over a 3×3 grid across the footprint so a sloped
	# site is handled: g_min drives the water surface (≈flush on the
	# low/downhill approach), g_max drives how high to clear air (so the
	# high/uphill side is dug open to the sky, not left roofed).
	var g_min: int = 0x7fffffff
	var g_max: int = -0x7fffffff
	if ground_src != null:
		for sx in [cx_vox - half_vox, cx_vox, cx_vox + half_vox]:
			for sz in [cz_vox - half_vox, cz_vox, cz_vox + half_vox]:
				var g: int = int(ground_src.call("get_ground_voxel_y_at", sx, sz))
				g_min = min(g_min, g)
				g_max = max(g_max, g)
	else:
		push_warning("[World3D] Test pond: no get_ground_voxel_y_at; anchoring at sea level (vox 72).")
		g_min = 72
		g_max = 72

	# Water surface one voxel above the LOWEST ground in the footprint
	# (≈flush on the downhill approach). Inclusive-min / exclusive-max
	# (one-past on max), matching queue_set_water_box / box_voxels.
	var surface_vox_y: int = g_min + 1
	var floor_vox_y: int = surface_vox_y - depth_vox
	var x0: int = cx_vox - half_vox
	var x1: int = cx_vox + half_vox
	var z0: int = cz_vox - half_vox
	var z1: int = cz_vox + half_vox

	# 1) Excavate the whole cuboid to AIR from the basin floor up past
	#    the highest ground (+ a rim) so every side is open to the sky.
	var air_min := Vector3i(x0, floor_vox_y, z0)
	var air_max := Vector3i(x1, g_max + POND_RIM_VOX + 1, z1)
	var air_ok: bool = VoxelEditManager.queue_edit_box_voxels(air_min, air_max, 0)

	# 2) Fill the lower part with water (overwrites the just-cleared air;
	#    queue is FIFO so this lands after the excavation).
	var water_min := Vector3i(x0, floor_vox_y, z0)
	var water_max := Vector3i(x1, surface_vox_y + 1, z1)
	var water_ok: bool = VoxelEditManager.queue_set_water_box(water_min, water_max, WaterByteCodec.SOURCE_BYTE)

	if air_ok and water_ok:
		print("[World3D] Test pond queued: world centre (%.1f, %.2f, %.1f) gMinVox=%d gMaxVox=%d surfaceVoxY=%d (worldY=%.2f) air=%s..%s water=%s..%s" % [
			POND_CENTER_X_M, float(surface_vox_y) * terrain_scale, POND_CENTER_Z_M,
			g_min, g_max, surface_vox_y, float(surface_vox_y) * terrain_scale,
			air_min, air_max, water_min, water_max])
	else:
		push_warning("[World3D] Test pond seed failed (air_ok=%s water_ok=%s — queue full or NoEditZone reject)." % [air_ok, water_ok])



func _resolve_gen_counter_source(gen: Resource) -> Object:
	# The adapter (CubicHeightmapGeneratorAdapter / CopperIslesHeightmap-
	# GeneratorAdapter) extends VoxelGeneratorScript but forwards to a
	# cpp_impl Resource (the actual HeightmapGeneratorBase subclass).
	# The counter method lives on the base, so try the adapter first
	# then drill through cpp_impl.
	if gen == null:
		return null
	if gen.has_method("get_generated_block_count"):
		return gen
	if "cpp_impl" in gen:
		var impl = gen.get("cpp_impl")
		if impl != null and impl.has_method("get_generated_block_count"):
			return impl
	return null
