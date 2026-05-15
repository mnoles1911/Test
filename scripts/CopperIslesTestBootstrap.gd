extends Node3D
# CopperIslesTestBootstrap — minimal world wiring for the Copper Isles
# scale-test scene.
#
# What this does in plain English:
#
#   The test scene contains a VoxelLodTerrain driven by the Copper Isles
#   heightmap generator and a Player3D. The autoloads (VoxelEditManager,
#   WaterFlowManager, etc.) are alive but they don't yet know about the
#   terrain in this scene. This script handles the small set of wire-ups
#   needed to make mining and water work, and snaps the player above the
#   highest possible terrain so they don't spawn inside an island.
#
#   This is a slimmed-down sibling of World3DBootstrap.gd — it skips the
#   features the test scene doesn't need (dialogue triggers, NoEditZones,
#   per-slot save paths, save/load player position) and keeps only what
#   the F7 scale-cycle workflow needs.
#
# Attached to the root node of CopperIslesTest.tscn.


@export var voxel_terrain_path: NodePath = "VoxelLodTerrain"

## When true, the player is teleported to Player3D.SPAWN_POSITION on
## _ready (and after every F7 scale change). The actual coords live as
## a constant in scripts/Player3D.gd — that's the single source of
## truth for both this initial-spawn path AND the toggle_fly_mode
## reset path. Change there, both behaviours follow.
##
## When false, the bootstrap reverts to the dynamic spawn that samples
## the heightmap centre and drops the player above the actual ground.
@export var spawn_override_enabled: bool = true

## When true, immediately enable Player3D's fly mode after spawn so
## the camera doesn't fall off the peak. Player3D.gd exposes
## toggle_fly_mode(); we call it once at startup if requested.
##
## Default flipped to false 2026-05-12 — the Copper Isles scene now
## starts in normal walking mode. When false, the spawn path engages
## Player3D._spawn_freeze and runs the wait-for-ground raycast retry
## (mirror of the World3D bootstrap pattern) so the player doesn't
## fall through unloaded chunks during the loading window.
@export var start_in_fly_mode: bool = false

## Optional per-scene spawn override. When this Vector3 is anything
## other than (0, 0, 0), it OVERRIDES Player3D.SPAWN_POSITION for the
## CopperIslesTest scene only — useful for water-rendering iteration
## (set to a known coastline like (-2000, 500, 0) so launch puts you
## right next to ocean instead of needing 40 s of flight). Leave at
## (0, 0, 0) to defer to Player3D.SPAWN_POSITION.
@export var spawn_position_override: Vector3 = Vector3.ZERO

# Vertical drop height for the player on first spawn (dynamic mode
# only — overridden when spawn_override_enabled is true).
const SPAWN_HEIGHT_MARGIN_M: float = 30.0


# =============================================================
# DIAGNOSTIC TELEMETRY — ported from World3DBootstrap (2026-05-08)
# =============================================================
# 1 Hz [DIAG] line: player pos, speed, VoxelViewer pos, lag_xz.
# Critical for diagnosing "I outwalked the streamer" symptoms in
# fly-mode traversal of the baked world. F12 toggles Zylann's
# built-in debug draws.

@export var diag_enabled: bool = true

var _diag_terrain: Object = null
var _diag_player: Node3D = null
var _diag_viewer: Node3D = null
var _diag_acc_time: float = 0.0
var _diag_last_player_pos: Vector3 = Vector3.ZERO
var _diag_last_player_pos_valid: bool = false
var _diag_debug_draw_on: bool = false

# Cache-miss telemetry — see HeightmapGeneratorBase.get_generated_block_count().
# Mirror of the World3DBootstrap counter. Each generator call corresponds
# to a Zylann CACHE MISS; a LOW miss rate while walking means we're hitting
# the SQLite baseline cache, a HIGH miss rate means new territory.
var _diag_gen_counter_source: Object = null
var _diag_last_gen_count: int = 0


func _enter_tree() -> void:
	# CRITICAL ordering: this seed copy MUST happen before the
	# VoxelLodTerrain child opens its SQLite stream. Godot's _enter_tree
	# fires top-down (parent before children), whereas _ready fires
	# bottom-up (children before parent). If we did the copy in _ready,
	# Zylann would already have opened the empty/missing user:// file
	# and our copy would land too late — exactly the "39.7 MB on disk
	# but generator runs anyway" symptom we hit on first attempt.
	_seed_from_baseline_if_needed()


func _ready() -> void:
	# CopperIslesTest.tscn is now the main play scene loaded via the
	# MainMenu flow (see MainMenu.WORLD_SCENE), so the gameplay UI
	# autoloads — HUDOverlay (HP/STAM bars), PauseMenu (Esc menu),
	# JournalUI (J key), SaveNotification — all need to render normally.
	# We deliberately do NOT add this scene to the `dev_scene` group;
	# that group is reserved for scenes opened directly via F6 (e.g.
	# `scenes/_dev/BakeWorld.tscn`) where the chrome would distract
	# from the dev tool. See GameState.is_dev_scene() for the contract.

	# Defensive belt-and-suspenders: even with the _enter_tree seed,
	# reassign the terrain.stream to a fresh VoxelStreamSQLite pointing
	# at the same path. Forces Zylann to re-open the file from a known
	# clean state. Costs nothing if the seed already worked; saves us
	# if the .tscn's stream resource was constructed before _enter_tree
	# fired (which can happen when scene resources cache aggressively).
	var terrain := get_node_or_null(voxel_terrain_path)
	if terrain == null:
		push_error("[CopperIslesTest] VoxelLodTerrain not found at: %s" % voxel_terrain_path)
		return

	# Force-reopen the stream against the (possibly newly-seeded) file.
	# We rebuild the resource rather than mutating the existing one so
	# Zylann's internal SQLite handle is fully torn down + reopened.
	# Carries forward the .tscn-defined settings so the .tscn stays the
	# source of truth for stream config.
	if "stream" in terrain:
		var old_stream: Resource = terrain.get("stream")
		if old_stream != null and old_stream is VoxelStreamSQLite:
			var fresh := VoxelStreamSQLite.new()
			fresh.database_path = old_stream.database_path
			fresh.save_generator_output = old_stream.save_generator_output
			if "preferred_coordinate_format" in old_stream:
				fresh.preferred_coordinate_format = old_stream.preferred_coordinate_format
			if "compression_mode" in old_stream:
				fresh.compression_mode = old_stream.compression_mode
			terrain.set("stream", fresh)
			# One-shot diagnostic — confirms the reopen happened with
			# the populated file. Compare bytes printed here with the
			# size of user://copper_isles_test.sqlite on disk.
			var f: FileAccess = FileAccess.open(fresh.database_path, FileAccess.READ)
			var sz: int = f.get_length() if f != null else 0
			if f != null:
				f.close()
			print("[CopperIslesTest] Reopened stream: %s (%d bytes on disk)" % [fresh.database_path, sz])

	# Configure CHANNEL_TYPE depth to 8-bit (Zylann default, set
	# explicitly here for parity with World3D). CHANNEL_DATA5 carries
	# water bytes — also 8-bit. v13: terrain rendering reads
	# CHANNEL_TYPE via VoxelMesherBlocky, not the pre-v13 CHANNEL_COLOR.
	if "format" in terrain:
		_configure_voxel_format(terrain)

	# Re-apply per-cube tile coords + atlas material at runtime to work
	# around Zylann's gdextension serialization bug — `material_override_0`
	# and per-face `tile_*` properties save into the .tres but fail to
	# restore on load (return null / default (0,0) at runtime). Without
	# this re-injection the terrain renders all-white or with the
	# full-atlas UV smear. See World3DBootstrap for the full rationale.
	if "mesher" in terrain:
		var mesher: Resource = terrain.mesher
		if mesher != null:
			_inject_atlas_materials_into_library(mesher)

	# Tell the generator to skip the EXR load in shipped builds. The
	# baked SQLite covers every in-bounds chunk, so the generator only
	# runs for out-of-bounds (deep ocean) — which doesn't need the
	# heightmap. Editor + dev builds keep loading the EXR for re-bakes.
	# `OS.has_feature("template")` is true ONLY in release export
	# builds; false in editor and debug exports.
	if "generator" in terrain:
		var gen: Resource = terrain.get("generator")
		if gen != null and "require_heightmap_in_editor_only" in gen:
			gen.set("require_heightmap_in_editor_only", true)
		# Tier 4: push the pre-filtered ore list into the generator on
		# the main thread. `set_ore_materials` is the worker-thread-safe
		# data handoff pattern (mirror of set_no_edit_water_aabbs). The
		# registry's _ores array is read-only after _loaded=true, so the
		# generator can iterate it from any worker thread.
		if gen != null and gen.has_method("set_ore_materials") \
				and get_node_or_null("/root/VoxelMaterialRegistry") \
				and VoxelMaterialRegistry.is_loaded():
			var ores: Array[VoxelMaterial] = VoxelMaterialRegistry.get_ore_materials()
			gen.call("set_ore_materials", ores)
			print("[CopperIslesTest] Pushed %d ore material(s) to generator." % ores.size())
		# Tier 5: same pattern for clay / gravel disk materials.
		if gen != null and gen.has_method("set_disk_materials") \
				and get_node_or_null("/root/VoxelMaterialRegistry") \
				and VoxelMaterialRegistry.is_loaded():
			var disks: Array[VoxelMaterial] = VoxelMaterialRegistry.get_disk_materials()
			gen.call("set_disk_materials", disks)
			print("[CopperIslesTest] Pushed %d disk material(s) to generator." % disks.size())
		# Force-load the heightmap on bootstrap so its stats print
		# immediately, even when the cache fully covers the spawn area
		# and the generator never fires on-demand. Diagnostic only;
		# the call is idempotent — if the EXR is already loaded, it
		# returns the cached image.
		if gen != null and gen.has_method("_ensure_image"):
			gen.call("_ensure_image")
		# Resolve the cache-miss counter source. The adapter forwards to
		# its cpp_impl Resource (the actual HeightmapGeneratorBase
		# subclass). The C++ base bound get_generated_block_count().
		_diag_gen_counter_source = _resolve_gen_counter_source(gen)
		if _diag_gen_counter_source != null:
			if _diag_gen_counter_source.has_method("reset_generated_block_count"):
				_diag_gen_counter_source.call("reset_generated_block_count")
			print("[CopperIslesTest] Cache-miss telemetry armed on %s." % _diag_gen_counter_source)
		else:
			print("[CopperIslesTest] Cache-miss telemetry unavailable (no get_generated_block_count method found).")

	# Move per-edit voxel-block updates off the main thread; defer
	# collision-shape rebuilds so they batch instead of firing on every
	# edit. Same settings World3DBootstrap applies to Mira. NOTE: the
	# collision_update_delay property is INT in this Zylann build —
	# previous code passed 0.1 which truncated to 0 (no batching). 100
	# is the working value; readback below confirms what landed.
	if "threaded_update_enabled" in terrain:
		terrain.set("threaded_update_enabled", true)
	if "collision_update_delay" in terrain:
		terrain.set("collision_update_delay", 100)
		print("[CopperIslesTest] terrain.collision_update_delay set to 100 (actual=%s)" % terrain.get("collision_update_delay"))
	# mesh_block_size: 32 makes each rendered mesh cover 8× more voxels
	# than the default 16. Ported from World3DBootstrap — measurable
	# improvement on per-chunk overhead during streaming. Doesn't
	# invalidate the voxel cache (cache is keyed by data-block coords,
	# not mesh-block coords). Readback flags any silent clamp.
	if "mesh_block_size" in terrain:
		terrain.set("mesh_block_size", 32)
		print("[CopperIslesTest] terrain.mesh_block_size set to 32 (actual=%s)" % terrain.get("mesh_block_size"))

	# Belt-and-suspenders LOD enforcement (mirror of WorldBakeController).
	# These MUST match the bake scene or cached chunks are at the wrong
	# LOD coords. Set in script so Godot editor's silent .tscn property
	# normalisation can't break the cache contract.
	_enforce_lod_config(terrain)

	# Hand the terrain to VoxelEditManager so the pickaxe / shovel in
	# the player loadout can carve it.
	if get_node_or_null("/root/VoxelEditManager"):
		VoxelEditManager.set_terrain(terrain)

	# Ocean source region — gives the central archipelago a visible
	# waterline. The generator already writes water source bytes into
	# CHANNEL_DATA at LOD0 below sea level; this AABB tells
	# WaterFlowManager that the surface is at world Y = 10 m so swim /
	# breath physics work and the WaterChunkMesher can render it.
	#
	# Surface Y = sea_level_voxels (60) × terrain.transform.scale (1/6)
	# = 10 m world at the default scale. When the F5–F9 hotkeys cycle
	# scale, the surface moves with the terrain — the AABB stays fixed
	# in world space, so at smaller scales the water surface shifts to
	# the actual world-Y the generator's sea level renders at.
	# Re-applied on each scale change in _reseed_water_for_scale.
	if get_node_or_null("/root/WaterFlowManager"):
		_reseed_water_for_scale(_terrain_scale(terrain))

	# Snap the player above the terrain so they fall into the world
	# rather than spawning inside an island peak.
	call_deferred("_snap_player_above_terrain")


# Path of the player's working SQLite (matches the .tscn's
# VoxelStreamSQLite.database_path). Hardcoded here rather than
# read off the stream because we run BEFORE the stream resource
# initialises — the copy must happen first or the stream opens an
# empty file at the user:// path.
#
# Path bumps invalidate the cache after generator output changes —
# the .tres-based stream re-opens the new (empty) file rather than
# reading stale chunks. Old files remain on disk inert; the user
# can delete them whenever convenient.
#   _v13: CHANNEL_COLOR → CHANNEL_TYPE textured tileset (2026-05-10)
#   _v14: Tiers 1-6 generation rules — cliff override, snow line,
#         marble + stone_dark jitter, ore veins, near-water disks,
#         cliff outcrops (2026-05-10)
const WORKING_SQLITE_PATH: String = "user://copper_isles_test_v14.sqlite"
const BAKED_BASELINE_PATH: String = "res://assets/voxel/copper_isles_baseline_v14.sqlite"


# =============================================================
# DIAG TELEMETRY (ported from World3DBootstrap)
# =============================================================

func _process(delta: float) -> void:
	# 1 Hz [DIAG] line — player pos, speed, viewer pos, viewer lag.
	# If lag_xz stays near 0 while chunks visibly fail to keep up, the
	# bottleneck is throughput (worker threads, meshing, collision),
	# not viewer placement. If lag_xz grows when moving fast, the
	# viewer node isn't tracking the player — different bug.
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
		# Horizontal speed only — gravity drift would skew the number
		# while idle / falling.
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
	# Pull terrain.get_statistics() if exposed (varies by Zylann build).
	var stats: String = ""
	if _diag_terrain != null and "get_statistics" in _diag_terrain:
		var s = _diag_terrain.call("get_statistics")
		if s is Dictionary:
			for k in s.keys():
				stats += " %s=%s" % [k, s[k]]
	# Cache-miss rate: chunks the generator was called on since last tick.
	# High = Zylann is regenerating new territory; low = SQLite cache is
	# serving requests. On Copper Isles this should stay near zero inside
	# the baseline footprint and spike only at map edges.
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
	# F12 toggles Zylann's built-in chunk visualisations:
	#   - debug_draw_active_mesh_blocks (wireframes around active chunks)
	#   - debug_draw_viewer_clipboxes (the streaming sphere)
	#   - debug_draw_octree_nodes (LOD shells)
	# F12 instead of F8 because F8 is Godot editor's "Stop Scene"
	# shortcut; the editor intercepts it before the running game.
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
			var state_str: String = "ON" if _diag_debug_draw_on else "OFF"
			print("[DIAG] terrain debug draws %s" % state_str)


func _diag_resolve_refs() -> void:
	# Lazy lookup — Player3D adds itself to the "player" group in its
	# own _ready, which may race ahead of bootstrap _ready on some
	# loads. Cache once everything's alive.
	if _diag_terrain == null:
		_diag_terrain = get_node_or_null(voxel_terrain_path)
	if _diag_player == null:
		var players: Array = get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			_diag_player = players[0] as Node3D
	if _diag_viewer == null and _diag_player != null:
		# VoxelViewer lives as a direct child of Player3D (Player3D.tscn).
		_diag_viewer = _diag_player.get_node_or_null("VoxelViewer") as Node3D


func _seed_from_baseline_if_needed() -> void:
	# If the working DB already exists, leave it alone (player has a
	# game in progress; don't stomp on it).
	if FileAccess.file_exists(WORKING_SQLITE_PATH):
		return
	# If the baseline doesn't ship in this build, fall back to live
	# generation — silent, as this is the expected first-run state
	# before any bake has been done.
	if not FileAccess.file_exists(BAKED_BASELINE_PATH):
		return
	# Resolve to OS-absolute paths so DirAccess.copy_absolute can
	# bridge res:// → user:// (the high-level .copy() method refuses
	# cross-prefix copies).
	var src_abs: String = ProjectSettings.globalize_path(BAKED_BASELINE_PATH)
	var dst_abs: String = ProjectSettings.globalize_path(WORKING_SQLITE_PATH)
	# Make sure the user:// directory exists. ProjectSettings handles
	# the standard user-data dir creation, but a fresh OS account on
	# the very first run might not have it yet.
	var user_dir := DirAccess.open("user://")
	if user_dir == null:
		push_warning("[CopperIslesTest] user:// not accessible; skipping baseline seed.")
		return
	var err: int = DirAccess.copy_absolute(src_abs, dst_abs)
	if err == OK:
		var size_bytes: int = 0
		var f: FileAccess = FileAccess.open(WORKING_SQLITE_PATH, FileAccess.READ)
		if f != null:
			size_bytes = f.get_length()
			f.close()
		print("[CopperIslesTest] Seeded %s from baseline (%.1f MB)." % [
			WORKING_SQLITE_PATH, float(size_bytes) / (1024.0 * 1024.0),
		])
	else:
		push_warning("[CopperIslesTest] Failed to copy baseline (err=%d)." % err)


# Terrain config the runtime MUST run with. MUST stay in lockstep
# with REQUIRED_* constants in scripts/_dev/WorldBakeController.gd —
# changing one without the other corrupts the cache contract.
const REQUIRED_LOD_COUNT: int = 9
# 9 LOD levels — sized for view_distance = 8000 voxels.
# At lod_distance=128 (Zylann max), LOD6 outer radius reaches 8192
# vox (1366 m world), just past the 1333 m view_distance. LODs 7-8
# are safety margin in case view_distance grows. LODs 9-13 would be
# pure overhead — entirely outside any plausible view radius.
# Earlier we set lod_count=14 thinking it was free; the diagnostic
# now confirms it's just unused bookkeeping.
# Lowering only affects future bakes; existing baselines baked at the
# old count remain readable (Zylann ignores LOD slots above lod_count).
const REQUIRED_LOD_DISTANCE: float = 128.0
# Zylann hard-caps lod_distance at 128.0 (probed empirically — see
# `scripts/_dev/WorldBakeController._on_probe_lod_distance`).
# secondary_lod_distance controls LOD chunk SIZE for LODs above 0
# in CLIPBOX streaming mode. Cranked to 128 to make distant LODs
# look as crisp as Zylann allows.
const REQUIRED_SECONDARY_LOD_DISTANCE: float = 128.0
const REQUIRED_LOD_FADE_DURATION: float = 1.0
# CLIPBOX = 1, LEGACY_OCTREE = 0. CLIPBOX is the newer streaming
# system, supports multiple viewers, and uses secondary_lod_distance
# (above) for finer LOD>0 control.
const REQUIRED_STREAMING_SYSTEM: int = 1


func _enforce_lod_config(terrain: Object) -> void:
	# Belt-and-suspenders LOD enforcement. Override the .tscn values so
	# Godot editor's silent property normalisation can't break the
	# bake/runtime cache contract. Verifies the set actually took
	# (Zylann silently clamps some properties, e.g. lod_distance) and
	# loudly flags any clamp because that breaks the cache contract.
	var fields: Array = [
		["lod_count", REQUIRED_LOD_COUNT],
		["lod_distance", REQUIRED_LOD_DISTANCE],
		["secondary_lod_distance", REQUIRED_SECONDARY_LOD_DISTANCE],
		["lod_fade_duration", REQUIRED_LOD_FADE_DURATION],
		["streaming_system", REQUIRED_STREAMING_SYSTEM],
		["cache_generated_blocks", true],
	]
	var changes_made: int = 0
	var clamps_detected: int = 0
	for f in fields:
		var key: String = f[0]
		var want = f[1]
		if not key in terrain:
			push_warning("[CopperIslesTest] terrain has no property '%s' — Zylann version mismatch?" % key)
			continue
		var before = terrain.get(key)
		if before == want:
			continue
		terrain.set(key, want)
		var after = terrain.get(key)
		changes_made += 1
		if after != want:
			clamps_detected += 1
			push_error("[CopperIslesTest] CLAMP DETECTED on terrain.%s: asked %s, got %s (Zylann silently capped)" % [
				key, want, after,
			])
		print("[CopperIslesTest] enforced terrain.%s: %s → %s (actual after set: %s)" % [
			key, before, want, after,
		])
	if changes_made == 0:
		print("[CopperIslesTest] LOD config already aligned — all %d required properties match. No enforcement needed." % fields.size())
	elif clamps_detected > 0:
		print("[CopperIslesTest] LOD config enforcement: %d changes, %d CLAMPS — see [CLAMP DETECTED] lines above." % [changes_made, clamps_detected])
	else:
		print("[CopperIslesTest] LOD config enforcement: %d changes applied successfully, no clamps." % changes_made)


func _configure_voxel_format(terrain: Object) -> void:
	# Lifted from World3DBootstrap. v13: CHANNEL_TYPE (8-bit) carries
	# the material_id integer that VoxelMesherBlocky reads;
	# CHANNEL_DATA5 (8-bit) carries water source bytes for
	# WaterChunkMesher. Assign the format BEFORE the terrain starts
	# streaming so cached chunks store at the right depth.
	var fmt: Resource = null
	if ClassDB.class_exists("VoxelFormat"):
		fmt = ClassDB.instantiate("VoxelFormat")
	if fmt == null:
		push_warning("[CopperIslesTest] VoxelFormat class not found.")
		return
	if fmt.has_method("set_channel_depth"):
		fmt.call("set_channel_depth", VoxelBuffer.CHANNEL_TYPE, VoxelBuffer.DEPTH_8_BIT)
		fmt.call("set_channel_depth", VoxelBuffer.CHANNEL_DATA5, VoxelBuffer.DEPTH_8_BIT)
	elif "type_depth" in fmt:
		fmt.set("type_depth", VoxelBuffer.DEPTH_8_BIT)
	elif "channel_depths" in fmt:
		var depths = fmt.get("channel_depths")
		if depths is Array:
			depths[VoxelBuffer.CHANNEL_TYPE] = VoxelBuffer.DEPTH_8_BIT
			depths[VoxelBuffer.CHANNEL_DATA5] = VoxelBuffer.DEPTH_8_BIT
			fmt.set("channel_depths", depths)
	terrain.set("format", fmt)


# =============================================================
# TEXTURE ATLAS RUNTIME RE-INJECTION
# =============================================================
# Mirrors World3DBootstrap._inject_atlas_materials_into_library. Per-
# cube `material_override_0` and per-face `tile_*` properties save
# correctly into blocky_library.tres but Zylann's gdextension fails
# to restore them on load — get_material_override(0) returns null and
# get_tile() returns (0,0). Without re-injection the terrain renders
# all-white or smears the full atlas across each cube. Re-apply every
# scene load. The .tres remains a build artifact; this script is the
# source of truth at runtime.

const _ATLAS_TEXTURE_PATH: String = "res://assets/voxels/texture_packs/default/atlas.png"
const _ATLAS_TILES_PER_ROW: int = 64   # 2048 / 32

# Zylann Cube SIDE enum (voxel/util/godot/classes/cube.h):
const _SIDE_NEG_X: int = 0
const _SIDE_POS_X: int = 1
const _SIDE_NEG_Y: int = 2
const _SIDE_POS_Y: int = 3
const _SIDE_NEG_Z: int = 4
const _SIDE_POS_Z: int = 5

# Per-material face tile coords — must mirror MATERIAL_TILES in
# tools/build_blocky_library.gd and the matching dict in
# World3DBootstrap. Keep all three in sync if tile coords change.
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
	var lib: Resource = mesher.get("library") if "library" in mesher else null
	if lib == null:
		push_warning("[CopperIslesTest] inject_atlas_materials: no library on mesher.")
		return

	var atlas_tex: Texture2D = load(_ATLAS_TEXTURE_PATH) as Texture2D
	if atlas_tex == null:
		printerr("[CopperIslesTest] inject_atlas_materials: failed to load %s" % _ATLAS_TEXTURE_PATH)
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
		push_warning("[CopperIslesTest] inject_atlas_materials: library has no models array.")
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
		if idx in _TRANSPARENT_MATERIALS:
			m.set("transparency_index", 1)
		if idx in _NON_CULLING_MATERIALS:
			m.set("culls_neighbors", false)
		injected += 1

	if lib.has_method("bake"):
		lib.bake()

	print("[CopperIslesTest] inject_atlas_materials: re-applied tiles + atlas mat to %d models, library re-baked." % injected)


func _terrain_scale(terrain: Node3D) -> float:
	return terrain.transform.basis.get_scale().x


# Sea level + peak-elevation constants for player-spawn and water-
# horizon math. These mirror the defaults baked into
# `assets/voxel/copper_isles_generator.tres` — keep them in sync if
# you tune the generator there. (Reading the values back off the live
# generator resource at runtime would be cleaner, but the property
# names are versioned and a stale read would silently put the player
# inside the islands; hardcoding here is the safer option for a dev
# scene.)
# Sea level at voxel-Y 1980 (= world Y 330 m at scale 1/6). MUST
# match `sea_level_voxels` in assets/voxel/copper_isles_generator.tres.
#
# REFACTORED 2026-05-09: this is now PURELY the water plane Y. Sea
# level no longer anchors any terrain math — moving this value moves
# only the visual water surface, not any voxel positions. Terrain Y
# is fixed by the heightmap gray-to-Y mapping (see
# CopperIslesHeightmapGenerator._gray_to_ground_y).
#
# 2026-05-10: bumped to 1440 (= world Y 240 m at scale 1/6) to match
# author's visual placement intuition. Bake at user//baked_baseline
# emitted CHANNEL_DATA5 water bytes up to this voxel-Y, so the
# chunked water mesher will find a surface at Y=240 to render.
const GEN_SEA_LEVEL_VOXELS: float = 1440.0
const GEN_PEAK_ABOVE_SEA_VOXELS: float = 15000.0

# Horizon plane override DISABLED 2026-05-08 — now that the
# generator's sea level is at voxel-Y 1200 (= world Y 200 m), the
# voxel sea and the follow-player horizon plane match exactly.
# No seam, no override needed. Set to 0 means "use generator sea
# level"; the bootstrap's _reseed_water_for_scale uses maxf() so a
# zero override never wins.
const HORIZON_PLANE_OVERRIDE_Y: float = 0.0


func _reseed_water_for_scale(terrain_scale: float) -> void:
	# Phase 5: AABB source regions are gone — water is per-voxel in
	# CHANNEL_DATA5, written by the generator. The only thing this
	# function still controls is the horizon plane Y, which scales
	# with terrain.transform.scale so a 1:1000 demo still shows water
	# at the right elevation.
	#
	# Parameter renamed from `scale` → `terrain_scale` to dodge the
	# Node3D.scale property shadow warning (this script's class
	# extends Node3D).
	if not get_node_or_null("/root/WaterFlowManager"):
		return
	# Visual horizon plane Y: uses HORIZON_PLANE_OVERRIDE_Y if set
	# above the generator's sea level (decoupled), else tracks the
	# generator's sea level scaled by terrain.transform.scale. This
	# lets us push the visual ocean higher without invalidating the
	# voxel cache. Trade-off: 35 m vertical seam where chunked water
	# (drawn at voxel Y=720 / world Y=120) meets the override
	# horizon — visible at the chunked-mesh radius (~64 m).
	var sea_level_world_y: float = GEN_SEA_LEVEL_VOXELS * terrain_scale
	var horizon_y: float = maxf(sea_level_world_y, HORIZON_PLANE_OVERRIDE_Y)
	WaterFlowManager.set_horizon_plane_y(horizon_y)
	# Tell WaterChunkMesher (via the manager) which voxel-Y row to
	# scan for the ocean surface mesh. Always tracks the generator's
	# sea level (where water bytes actually live in CHANNEL_DATA5);
	# the visual horizon override above does NOT affect this.
	if WaterFlowManager.has_method("set_sea_level_voxel_y"):
		WaterFlowManager.set_sea_level_voxel_y(int(GEN_SEA_LEVEL_VOXELS))


func _snap_player_above_terrain() -> void:
	# Two modes — see the @export comments at the top of the script:
	#   spawn_override_enabled = true:  hard-coded position, fly mode
	#                                   on, no terrain sampling.
	#   spawn_override_enabled = false: dynamic spawn above the
	#                                   heightmap centre (legacy).
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node3D = players[0] as Node3D

	if spawn_override_enabled:
		# Engage fly mode first (if requested), then place the player.
		# toggle_fly_mode() preserves position now, so the explicit
		# global_position assignment below is the authoritative spawn
		# placement on scene load.
		if start_in_fly_mode and player.has_method("toggle_fly_mode"):
			var already_flying: bool = "is_flying" in player and bool(player.get("is_flying"))
			if not already_flying:
				player.call("toggle_fly_mode")
		# Per-scene override wins over Player3D.SPAWN_POSITION when set.
		# Used for water-rendering iteration: set spawn_position_override
		# to (-2000, 500, 0) in the Inspector to launch directly at the
		# west coastline.
		var spawn_pos: Vector3 = Player3D.SPAWN_POSITION
		if spawn_position_override != Vector3.ZERO:
			spawn_pos = spawn_position_override
			print("[CopperIslesTest] spawn_position_override active: %s" % str(spawn_pos))
		player.global_position = spawn_pos
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO

		# Spawn-freeze + wait-for-ground (mirrors World3DBootstrap pattern,
		# 2026-05-12). Fly mode bypasses gravity so the freeze isn't
		# needed there; in walking mode (start_in_fly_mode=false) the
		# player would otherwise fall straight through unloaded chunks
		# during the loading window. Freeze stops physics; the retry
		# loop unfreezes the moment a downward raycast finds collider.
		if not start_in_fly_mode and "_spawn_freeze" in player:
			player.set("_spawn_freeze", true)
			_wait_for_ground_under_player()

		# Spawn placed — kick off the loading-screen close negotiation.
		# Polls Zylann's blocked_lods + a dense LOD0 probe ring around
		# the spawn point, then tells TransitionManager when the area
		# is presentable. TransitionManager has its own min-hold so the
		# loading screen never closes instantly even on a fully-cached
		# baseline.
		_mark_world_ready_when_settled()
		return

	# --- Dynamic spawn (no override) ---
	var terrain := get_node_or_null(voxel_terrain_path) as Node3D
	if terrain == null:
		# No terrain to probe; signal ready immediately so the loading
		# screen doesn't sit on its 25 s cap waiting for nothing.
		_signal_world_ready("no terrain in scene")
		return
	# Local renamed `scale` → `terrain_scale` to dodge the Node3D.scale
	# property shadow warning.
	var terrain_scale: float = _terrain_scale(terrain)
	var ground_voxels: float = (GEN_SEA_LEVEL_VOXELS + GEN_PEAK_ABOVE_SEA_VOXELS)
	var generator = terrain.get("generator") if "generator" in terrain else null
	if generator != null and generator.has_method("get_ground_voxel_y_at"):
		# Sample the column directly under spawn (world X=0, Z=0 maps
		# to the centre of the heightmap → middle island per the spec).
		ground_voxels = float(generator.call("get_ground_voxel_y_at", 0, 0))
	var spawn_y: float = ground_voxels * terrain_scale + SPAWN_HEIGHT_MARGIN_M
	player.global_position = Vector3(0.0, spawn_y, 0.0)
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	# Same spawn-freeze + ground-wait as the override path. Dynamic
	# spawn always uses walking mode (no fly override here), so the
	# freeze is unconditional.
	if "_spawn_freeze" in player:
		player.set("_spawn_freeze", true)
		_wait_for_ground_under_player()
	# Same readiness handoff as the override path — see comment there.
	_mark_world_ready_when_settled()


# =============================================================
# SPAWN-FREEZE + PER-FRAME WIGGLE + RAYCAST (matches World3DBootstrap)
# =============================================================
#
# User observation 2026-05-12: Zylann's CLIPBOX (and likely legacy
# octree) only re-evaluates the chunk set when the viewer's transform
# CHANGES. A stationary frozen viewer never triggers new chunk
# streaming, so collision never builds, the raycast always misses,
# the freeze times out, and the player falls through.
#
# Fix (ported from World3DBootstrap 3d47216): per-physics-frame
# wiggle by SPAWN_WIGGLE_AMPLITUDE_M (10mm) on both X and Z, run
# the raycast each frame, clear the freeze the moment a hit lands
# (or after SPAWN_WIGGLE_MAX_S as failsafe).
#
# TODO: extract into a shared helper. Both bootstraps now run
# nearly-identical wiggle loops; a Player3D.freeze_until_grounded()
# helper would dedupe both. Low priority while the implementations
# stay this small.

const SPAWN_WIGGLE_MAX_S: float = 15.0
# Aligned with World3DBootstrap 2026-05-12 revert: 10mm × dual-axis
# at 60Hz overwhelmed Zylann (200ms/frame detect, 16k dropped loads).
# 1mm × single-axis × every 6 frames is the stable config.
const SPAWN_WIGGLE_AMPLITUDE_M: float = 0.001
const SPAWN_WIGGLE_FRAME_INTERVAL: int = 6

var _spawn_wiggle_active: bool = false
var _spawn_wiggle_start_msec: int = 0
var _spawn_wiggle_frame: int = 0


func _wait_for_ground_under_player(_retries_remaining: int = 0) -> void:
	# Kicks off the wiggle loop (the actual work runs in
	# _physics_process below). Parameter retained for call-site
	# compatibility but unused — the loop self-times via
	# SPAWN_WIGGLE_MAX_S.
	_spawn_wiggle_active = true
	_spawn_wiggle_frame = 0
	_spawn_wiggle_start_msec = Time.get_ticks_msec()


func _physics_process(_delta: float) -> void:
	if not _spawn_wiggle_active:
		return
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node3D = players[0] as Node3D
	if player == null:
		return

	# Step 1: wiggle X every Nth frame to keep Zylann's CLIPBOX
	# scanning chunks WITHOUT saturating it. See World3DBootstrap
	# for the full rationale on amplitude + cadence.
	_spawn_wiggle_frame += 1
	if _spawn_wiggle_frame % SPAWN_WIGGLE_FRAME_INTERVAL == 0:
		var sign_x: float = 1.0 if ((_spawn_wiggle_frame / SPAWN_WIGGLE_FRAME_INTERVAL) % 2 == 0) else -1.0
		player.global_position.x += SPAWN_WIGGLE_AMPLITUDE_M * sign_x

	# Step 2: raycast for collision below. Brackets the player's
	# current Y because Copper Isles spawn altitude varies wildly
	# depending on which island the player lands on.
	var origin: Vector3 = Vector3(player.global_position.x, player.global_position.y + 100.0, player.global_position.z)
	var dest: Vector3 = Vector3(player.global_position.x, player.global_position.y - 200.0, player.global_position.z)
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(origin, dest)
	params.exclude = [player.get_rid()]
	var hit: Dictionary = space.intersect_ray(params)

	if not hit.is_empty():
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
		var elapsed_s: float = (Time.get_ticks_msec() - _spawn_wiggle_start_msec) / 1000.0
		print("[CopperIslesTest] spawn-freeze cleared, ground at Y=%.2f (%.1fs wiggle)" % [
			ground_y, elapsed_s,
		])
		return

	# Step 3: timeout failsafe.
	var elapsed_s: float = (Time.get_ticks_msec() - _spawn_wiggle_start_msec) / 1000.0
	if elapsed_s > SPAWN_WIGGLE_MAX_S:
		if "_spawn_freeze" in player:
			player.set("_spawn_freeze", false)
		_spawn_wiggle_active = false
		print("[CopperIslesTest] spawn-freeze wiggle timed out at %.1fs; unfreezing at Y=%.2f." % [
			elapsed_s, player.global_position.y,
		])


# =============================================================
# LOADING-SCREEN READINESS — adaptive close
# =============================================================
#
# TransitionManager opens the loading screen when MainMenu kicks off a
# scene change with `loading_seconds > 0`. It polls `_voxel_world_ready`
# (a flag this script flips via mark_voxel_world_ready) every frame
# after the min-hold elapses and closes the screen as soon as we say
# "world is presentable" — so a fully-cached baseline doesn't sit on
# the loading screen for the full 25 s cap.
#
# This is a port of the same probe World3DBootstrap uses for Mira;
# see that file for the long-form rationale on why the gate combines
# a dense LOD0 raycast ring AND Zylann's blocked_lods queue depth.

# State tracker so re-entrant calls (override + dynamic spawn paths,
# F7 scale cycle resnap) don't double-fire the signal.
var _world_ready_signaled: bool = false


func _mark_world_ready_when_settled() -> void:
	# Two-gate readiness check, polled every POLL_INTERVAL until both
	# gates pass for REQUIRED_GOOD_SAMPLES consecutive polls OR
	# MAX_EXTRA_WAIT elapses (whichever comes first).
	#
	# Gate 1 — DENSE LOD0 SPATIAL PROBE: 6 radii × 16 directions = 96
	# raycasts straight down from 200 m above each probe XZ. Because
	# the terrain runs with collision_lod_count = 0, only LOD0 chunks
	# have collision shapes — a hit means "this column has a meshed
	# LOD0 block." All 96 must hit.
	#
	# Gate 2 — STREAMING QUEUE NEAR-IDLE: Zylann's get_statistics()
	# reports `blocked_lods`, the global LOD-pipeline queue depth.
	# When it drops to ≤ STREAM_QUEUE_NEAR_IDLE, even chunks the
	# probes don't sample are very nearly done.
	#
	# Together they close each other's blind spots: probes confirm
	# "spawn area is visually presentable", the queue gate confirms
	# "the streamer is globally finished".
	#
	# REQUIRED_GOOD_SAMPLES × POLL_INTERVAL = 1.2 s of sustained
	# "both pass" filters out single-frame races.
	#
	# MAX_EXTRA_WAIT 60 s — Copper Isles loads from a populated
	# baseline SQLite (no generator work for in-bounds chunks), so
	# 60 s is generous; on a warm cache this completes in well under
	# 10 s. Fallback caps the wait so a stuck stream can't strand the
	# player on a black screen forever.
	if _world_ready_signaled:
		return
	const PROBE_RADII_M: Array = [20.0, 50.0, 90.0, 130.0, 170.0, 210.0, 250.0]
	const PROBE_DIRECTION_COUNT: int = 16
	const STREAM_QUEUE_NEAR_IDLE: int = 15
	const REQUIRED_GOOD_SAMPLES: int = 3
	const MAX_EXTRA_WAIT: float = 60.0
	const POLL_INTERVAL: float = 0.4
	# Probe Y bounds — ABSOLUTE world-space, NOT relative to player. The
	# spawn point can be anywhere (high above peaks for fly-mode debug,
	# deep below the seabed for water testing); a player-relative ±200 m
	# probe would miss all terrain in those cases. These bounds bracket
	# the entire generator output range:
	#   - Top: above peaks at gray=1 (= elevation_above_at_white/6 = 2500 m
	#     world at the canonical 6 vox/m). +500 m headroom.
	#   - Bottom: below the WORLD_FLOOR_VOXEL_Y bedrock (= -300 vox / -50 m
	#     world). -200 m for cushion.
	const PROBE_Y_TOP: float = 3000.0
	const PROBE_Y_BOTTOM: float = -200.0

	# Build the unit-direction ring once (16 directions = every 22.5°).
	var probe_dirs: Array[Vector2] = []
	for i in range(PROBE_DIRECTION_COUNT):
		var theta: float = TAU * float(i) / float(PROBE_DIRECTION_COUNT)
		probe_dirs.append(Vector2(cos(theta), sin(theta)))

	var terrain := get_node_or_null(voxel_terrain_path)
	var total_probes: int = probe_dirs.size() * PROBE_RADII_M.size()
	print("[CopperIslesTest] readiness probe: %d total (radii=%s × %d dirs); polling every %.1fs up to %.0fs."
		% [total_probes, PROBE_RADII_M, PROBE_DIRECTION_COUNT, POLL_INTERVAL, MAX_EXTRA_WAIT])
	var elapsed: float = 0.0
	var consecutive_good: int = 0
	var last_hits: int = 0
	var last_blocked: int = -1
	while elapsed < MAX_EXTRA_WAIT:
		await get_tree().create_timer(POLL_INTERVAL).timeout
		elapsed += POLL_INTERVAL
		last_hits = _count_probe_hits(probe_dirs, PROBE_RADII_M, PROBE_Y_TOP, PROBE_Y_BOTTOM)
		# Read Zylann's queue depth. Fallback: if the API is missing or
		# the field isn't there, treat the queue gate as permissive so
		# the spatial probe alone can still close the screen.
		last_blocked = -1
		if terrain != null and terrain.has_method("get_statistics"):
			var s = terrain.call("get_statistics")
			if s is Dictionary and s.has("blocked_lods"):
				last_blocked = int(s["blocked_lods"])
		var probe_ok: bool = last_hits == total_probes
		var queue_ok: bool = last_blocked < 0 or last_blocked <= STREAM_QUEUE_NEAR_IDLE
		# Per-poll diagnostic print so we can see exactly why the gate
		# isn't passing in the Output panel — debug aid, ~once every
		# 0.4 s. Drop print to a less-frequent cadence if it's too noisy.
		print("[CopperIslesTest] probe poll t=%.1fs hits=%d/%d queue=%s consec_good=%d/%d"
			% [elapsed, last_hits, total_probes,
				("n/a" if last_blocked < 0 else str(last_blocked)),
				consecutive_good, REQUIRED_GOOD_SAMPLES])
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


func _count_probe_hits(
	probe_dirs: Array[Vector2],
	probe_radii: Array,
	y_top: float,
	y_bottom: float,
) -> int:
	# Returns how many of the (direction × radius) probes hit voxel
	# collision. Casts from y_top straight down to y_bottom — these are
	# ABSOLUTE world-Y bounds passed in from the caller, NOT relative to
	# the player. The whole point: a player at any spawn Y (deep ocean
	# debug, sky-high fly mode start) still gets a probe sweep that
	# covers the entire generator's vertical output range. Player's own
	# collider is excluded so we don't self-hit.
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
			var origin: Vector3 = Vector3(probe_x, y_top, probe_z)
			var dest: Vector3 = Vector3(probe_x, y_bottom, probe_z)
			var params := PhysicsRayQueryParameters3D.create(origin, dest)
			params.exclude = [player.get_rid()]
			if not space.intersect_ray(params).is_empty():
				hits += 1
	return hits


func _signal_world_ready(reason: String) -> void:
	if _world_ready_signaled:
		return
	_world_ready_signaled = true
	print("[CopperIslesTest] Signaling voxel world ready (%s)." % reason)
	if get_node_or_null("/root/TransitionManager"):
		TransitionManager.mark_voxel_world_ready()


# =============================================================
# PUBLIC API — called by DebugOverlay's F7 scale-cycle hotkey
# =============================================================

func apply_terrain_scale(new_scale: float) -> void:
	# Applies a uniform scale to the VoxelLodTerrain transform, then
	# re-seeds water and snaps the player above the new highest peak.
	# No mesh rebuild is required — Zylann uses the node transform for
	# render scaling, so the same voxel data renders at the new size
	# immediately. Streaming radii (in voxels) stay the same; the
	# player perceives a different world-meters extent.
	var terrain := get_node_or_null(voxel_terrain_path) as Node3D
	if terrain == null:
		return
	var origin: Vector3 = terrain.transform.origin
	terrain.transform = Transform3D(Basis().scaled(Vector3.ONE * new_scale), origin)
	_reseed_water_for_scale(new_scale)
	_snap_player_above_terrain()


func _resolve_gen_counter_source(gen: Resource) -> Object:
	# Mirror of World3DBootstrap._resolve_gen_counter_source. The adapter
	# (CopperIslesHeightmapGeneratorAdapter) extends VoxelGeneratorScript
	# but forwards to a cpp_impl Resource (HeightmapGeneratorBase subclass).
	# The counter method lives on the base, so try the adapter first then
	# drill through cpp_impl.
	if gen == null:
		return null
	if gen.has_method("get_generated_block_count"):
		return gen
	if "cpp_impl" in gen:
		var impl = gen.get("cpp_impl")
		if impl != null and impl.has_method("get_generated_block_count"):
			return impl
	return null
