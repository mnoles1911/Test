extends CanvasLayer

const WaterMaterial := preload("res://scripts/WaterMaterial.gd")

# WaterDiag.gd — the durable water diagnostics surface (2026-05-17).
#
# WHY THIS EXISTS (plain English):
#   Water Voxel V2 has a long polish road ahead (the distant dark-grid
#   fix, the flow-Y bug, waterline jitter, the deferred flow sim). Each
#   of those is hard to reason about from a screenshot alone. Rather
#   than hand-bisecting with throwaway shader tweaks every time, this
#   autoload is ONE place that always answers "what is the water doing
#   right here, right now?" in numbers — so the next water question
#   takes one run, not four.
#
# WHAT IT GIVES YOU (all dev-only, default OFF, keyboard-toggled):
#   F4 — toggle the on-screen Water panel. While the panel is visible a
#        consolidated `[WaterDiag]` line is also printed once per second
#        (so you get the same data in the Output log for pasting).
#   F5 — one-shot `[WaterInspect]` dump: the voxel column + mesh-block
#        neighbourhood under the camera (water-top Y, water count, the
#        Y-delta vs each lateral neighbour, expected LOD). This is the
#        tool that turns "dark grid at chunk seams" into a measured
#        per-block water-top Y mismatch.
#   F6 — cycle the water shader `debug_mode` 0→1→2→3→4→0 live
#        (0 normal · 1 depth_t · 2 fresnel · 3 thickness · 4 surface
#        facing). The recurring workhorse for water rendering work.
#
# It only READS the public WaterFlowManager API + the VoxelTool; it
# never mutates water. Keyboard-only (Button.pressed is broken
# project-wide — see CLAUDE.md). Profiler-attributed under "WATER".
#
# Keys F4/F5/F6 were free in World3D (F1 DebugOverlay, F2 freelook,
# F3 ProfilerOverlay, F7 Copper scale, F12 bootstrap). Registered as an
# autoload AFTER WaterFlowManager — see project.godot / CLAUDE.md.

# Water is CHANNEL_TYPE id 5 (Water Voxel V2). Mirror the constants the
# manager uses so this file stays self-contained.
const WATER_TYPE_ID: int = WaterMaterial.BODY_ID
const VOXELS_PER_METER: float = 6.0
const HEAD_OFFSET_M: float = 1.6   # ~Roland eye height, for submersion test
const WATER_MATERIAL_PATH: String = "res://assets/shaders/water_material.tres"

# Vertical voxel span the "where is the water surface" probe scans
# around the player before giving up (≈ ±8 m at 6 vox/m).
const SURFACE_SCAN_VOXELS: int = 48
# F5 radial "nearest water near the character" scan. Bounded + one-shot
# only (NEVER per-frame — that volume scan every tick would be the bad
# version of this; the F4 panel stays a cheap single player-column
# query). Disk of RADIUS_M around the player, sampled every STRIDE_M.
const RADIAL_SCAN_RADIUS_M: float = 32.0
const RADIAL_SCAN_STRIDE_M: float = 3.0

var _panel_visible: bool = false
var _root: Control = null
var _label: Label = null

# water_changed/sec counter (2026-05-27). Subscribes to
# WaterFlowManager.water_changed at _ready and tallies emissions over
# rolling 1 s windows. Surfaces in the F4 panel — high values during
# idle = chunk mesh rebuild churn (the per-chunk water mesh redraws
# faster than the eye, contributes to "the gap pops in/out as I move")
# while a near-zero idle reading means the water meshes are stable and
# the gap is structural (LOD-stitching), not redraw thrash.
var _water_changed_window_count: int = 0
var _water_changed_per_sec: int = 0

# F5 inspector on-screen result — shown for INSPECT_SHOW_SECONDS even
# when the F4 panel is hidden, so F5 has visible in-game feedback
# (its data also still goes to the Output log).
const INSPECT_SHOW_SECONDS: float = 7.0
var _inspect_root: Control = null
var _inspect_label: Label = null
var _inspect_until_ms: int = 0
var _inspect_text: String = ""

var _sec_accum: float = 0.0          # drives the 1 Hz log line
var _query_us_ema: float = 0.0       # smoothed is_position_in_water cost
var _water_mat: ShaderMaterial = null


func _ready() -> void:
	layer = 6  # above HUDOverlay (5); below pause/journal modal layers.
	visible = true
	_build_panel()
	_water_mat = load(WATER_MATERIAL_PATH) as ShaderMaterial
	# Process even while the SceneTree is paused (Dialogic/pause) so the
	# panel keeps reporting — diagnostics must not freeze with the game.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Subscribe to water_changed for the per-sec emission counter (F4
	# panel). Guarded — WaterFlowManager may not have loaded in dev
	# scenes that opt out.
	var wfm := get_node_or_null("/root/WaterFlowManager")
	if wfm != null and wfm.has_signal("water_changed"):
		wfm.water_changed.connect(_on_water_changed)
	print("[WaterDiag] ready — F4 panel · F5 inspect · F6 cycle shader debug_mode · ` (backtick) look-ray · Shift+` FORCE-FILL.")


func _on_water_changed(_chunk_coord: Vector3i) -> void:
	# Pure tally — no logic. The 1 s window counter is read in _process
	# and reset there.
	_water_changed_window_count += 1


func _build_panel() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.06, 0.09, 0.72)
	bg.position = Vector2(12, 120)
	bg.size = Vector2(430, 250)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	_label = Label.new()
	_label.position = Vector2(22, 128)
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_label)

	_root.visible = false

	# Separate transient overlay for the F5 inspector result, so F5 has
	# clear in-game feedback regardless of the F4 panel state.
	_inspect_root = Control.new()
	_inspect_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_inspect_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_inspect_root)

	var ibg := ColorRect.new()
	ibg.color = Color(0.05, 0.04, 0.02, 0.78)
	ibg.position = Vector2(12, 384)
	ibg.size = Vector2(720, 168)
	ibg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect_root.add_child(ibg)

	_inspect_label = Label.new()
	_inspect_label.position = Vector2(22, 392)
	_inspect_label.add_theme_font_size_override("font_size", 13)
	_inspect_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.70))
	_inspect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect_root.add_child(_inspect_label)

	_inspect_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_F4:
			_panel_visible = not _panel_visible
			_root.visible = _panel_visible
			print("[WaterDiag] panel %s" % ("ON" if _panel_visible else "OFF"))
			get_viewport().set_input_as_handled()
		KEY_F5:
			_dump_inspector()
			get_viewport().set_input_as_handled()
		KEY_F6:
			_cycle_shader_debug_mode()
			get_viewport().set_input_as_handled()
		# NB on key choice: every F-key in this project is taken or
		# reserved.  F1 DebugOverlay · F2 freelook · F3 ProfilerOverlay
		# panel · F4-F6 WaterDiag · F7 Copper scale · F8 Godot EDITOR
		# Stop-Scene (intercepted before reaching us) · F9 ProfilerOverlay
		# StreamDiag (calls set_input_as_handled, blocks us) · F10
		# World3DBootstrap emissive magenta · F11 LOD debug shader · F12
		# Zylann debug draws. So the water probes live on BACKTICK (top-
		# left of every keyboard, never bound anywhere). Plain ` =
		# look-ray; Shift+` = force-fill.
		KEY_QUOTELEFT:
			if k.shift_pressed:
				# Brute-force write SOURCE_BYTE into every voxel in a 32 m
				# XZ box around the player, below sea level. Bypasses the
				# connectivity-fill / settle sim entirely. If the gap-lines
				# survive a successful force-fill, the bug is the mesher's
				# chunk stitching, not the fill sim.
				_force_fill_around_player()
			else:
				# Look-ray probe via WaterFlowManager public API (no raw
				# VoxelTool calls). Prints a 5x5 XZ grid at sea level to the
				# inspect overlay + log so we can see whether the gap-lines
				# correspond to chunks where the BUFFER says no water
				# (generator/sim bug) or to chunks where the buffer has water
				# but the MESHER didn't emit faces (chunk-stitching bug).
				printerr("[WaterLookRay] ` keypress received — deferring probe")
				call_deferred("_dump_lookray_probe")
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# F5 transient overlay auto-hide — must run even when the F4 panel
	# is off, so handle it before the panel early-return.
	if _inspect_root != null and _inspect_root.visible:
		if Time.get_ticks_msec() >= _inspect_until_ms:
			_inspect_root.visible = false

	if not _panel_visible:
		return
	var t0 := Time.get_ticks_usec()
	var snap := _sample()
	# Attribute our own poll cost so the F3 overlay shows it under WATER.
	var elapsed := Time.get_ticks_usec() - t0
	var prof := get_node_or_null("/root/Profiler")
	if prof != null:
		prof.record("WATER", "WaterDiag", elapsed)
	if get_node_or_null("/root/HUDOverlay") != null:
		HUDOverlay.profile_record("WaterDiag", elapsed)

	_label.text = _format(snap)

	_sec_accum += delta
	if _sec_accum >= 1.0:
		_sec_accum = 0.0
		# Roll the water_changed window.
		_water_changed_per_sec = _water_changed_window_count
		_water_changed_window_count = 0
		print("[WaterDiag] " + _format(snap).replace("\n", "  |  "))


# ============================================================
# Sampling — the single source the panel + log + inspector share
# ============================================================

func _sample() -> Dictionary:
	var d := {
		"ok": false, "pos": Vector3.ZERO, "in_water": false,
		"submerged": false, "level": 0, "surf_y": NAN, "surf_dist": NAN,
		"sea_y_world": NAN, "horizon_y": NAN, "flow_sim": false,
		"dbg": -1, "query_us": 0.0, "cam_dist": NAN, "exp_lod": -1,
	}
	var player := _find_player()
	var vp := get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp != null else null
	if player == null and cam == null:
		return d
	var pos: Vector3 = player.global_position if player != null else cam.global_position
	d["pos"] = pos

	var wfm := get_node_or_null("/root/WaterFlowManager")
	if wfm != null:
		var qt0 := Time.get_ticks_usec()
		d["in_water"] = wfm.is_position_in_water(pos)
		var qus := float(Time.get_ticks_usec() - qt0)
		# EMA so the panel number doesn't strobe frame to frame.
		_query_us_ema = qus if _query_us_ema == 0.0 else lerpf(_query_us_ema, qus, 0.1)
		d["query_us"] = _query_us_ema
		d["submerged"] = wfm.is_position_in_water(pos + Vector3(0, HEAD_OFFSET_M, 0))
		d["level"] = wfm.get_water_level_at(pos)
		if wfm.has_method("get_sea_level_voxel_y"):
			d["sea_y_world"] = float(wfm.get_sea_level_voxel_y()) / VOXELS_PER_METER
		if wfm.has_method("get_horizon_plane_y"):
			d["horizon_y"] = wfm.get_horizon_plane_y()
		# _FLOW_SIM_ENABLED is a GDScript const, not a property — read it
		# from the script's constant map (Object.get() returns null for
		# consts). Tells you whether flow ticks are even live.
		var wscript = wfm.get_script()  # Variant — untyped on purpose
		if wscript != null and wscript.has_method("get_script_constant_map"):
			var cmap: Dictionary = wscript.get_script_constant_map()
			d["flow_sim"] = bool(cmap.get("_FLOW_SIM_ENABLED", false))

	var surf := _find_surface_y(pos)
	d["surf_y"] = surf
	if not is_nan(surf):
		d["surf_dist"] = surf - pos.y

	if cam != null:
		d["cam_dist"] = pos.distance_to(cam.global_position) if player != null else 0.0
		d["exp_lod"] = _expected_lod(cam.global_position.distance_to(pos))

	d["dbg"] = _get_shader_debug_mode()
	d["ok"] = true
	return d


func _format(d: Dictionary) -> String:
	if not d.get("ok", false):
		return "WATER DIAG\n(no player/camera yet)"
	var p: Vector3 = d["pos"]
	var surf_y = d["surf_y"]
	var surf_txt := ("%.2f (Δ%.2f m)" % [surf_y, d["surf_dist"]]) if not is_nan(surf_y) else "none ±%d vox" % SURFACE_SCAN_VOXELS
	return "WATER DIAG  (F4 panel · F5 inspect · F6 shader · ` look-ray · Shift+` force-fill)\n" + \
		"pos        %.1f, %.1f, %.1f\n" % [p.x, p.y, p.z] + \
		"in_water   %s    submerged %s\n" % [str(d["in_water"]), str(d["submerged"])] + \
		"level      %d / 8\n" % int(d["level"]) + \
		"surface Y  %s\n" % surf_txt + \
		"sea level  Y=%.2f world   horizon Y=%.2f\n" % [d["sea_y_world"], d["horizon_y"]] + \
		"flow sim   %s   water_changed/s %d\n" % [str(d["flow_sim"]), _water_changed_per_sec] + \
		"shader dbg %d   (0 norm 1 depth 2 fres 3 thick 4 face 5 flow 6 mag 7 ALPHA 8 LOD)\n" % int(d["dbg"]) + \
		"query      %.1f us   expected LOD %d @ %.0f m" % [d["query_us"], int(d["exp_lod"]), (0.0 if is_nan(d["cam_dist"]) else d["cam_dist"])]


# ============================================================
# F5 — one-shot chunk/column inspector (the dark-grid measurer)
# ============================================================

func _dump_inspector() -> void:
	# Collect every line so it goes to BOTH the Output log (prefixed) and
	# the on-screen transient overlay.
	#
	# Evaluates whatever water is NEAR THE CHARACTER (designer ask
	# 2026-05-17): a bounded radial scan around the player finds the
	# nearest water body + an aggregate, instead of only reporting the
	# single column you happen to stand on. The vertical scan band
	# centres on the PLAYER's Y, not sea level — elevated ponds (the
	# test pond sits ~vox 128 vs sea 72) were invisible before.
	var lines: Array[String] = []

	var tool := _get_tool()
	if tool == null:
		_emit(lines, "no VoxelTool yet (terrain still loading) — try again in a moment")
		_show_inspect(lines)
		return
	# Anchor on the PLAYER ("near character"); camera only as fallback.
	var player := _find_player()
	var cam := get_viewport().get_camera_3d()
	var origin: Vector3 = player.global_position if player != null else (cam.global_position if cam != null else Vector3.ZERO)
	var pv := _world_to_voxel(origin)
	var cy: int = pv.y
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	var sea_y := _sea_voxel_y()

	_emit(lines, "player world=%.1f,%.1f,%.1f vox=%s cy=%d sea_voxY=%d" % [
		origin.x, origin.y, origin.z, str(pv), cy, sea_y])

	# Water in the player's own column (band around cy).
	var here_top: int = _water_top_y(tool, pv.x, pv.z, cy)
	if here_top != -2147483648:
		_emit(lines, "  AT PLAYER: water-top voxelY=%d (worldY=%.2f) — standing in/over water" % [
			here_top, float(here_top + 1) / VOXELS_PER_METER])
	else:
		_emit(lines, "  AT PLAYER: dry column (no water within ±%d vox of cy)" % SURFACE_SCAN_VOXELS)

	# --- Bounded radial scan: nearest water body near the character ---
	var steps: int = int(RADIAL_SCAN_RADIUS_M / RADIAL_SCAN_STRIDE_M)
	var r2_max: float = RADIAL_SCAN_RADIUS_M * RADIAL_SCAN_RADIUS_M
	var scanned: int = 0
	var hits: int = 0
	var min_top: int = 0x7fffffff
	var max_top: int = -0x7fffffff
	var best_d2: float = INF
	var best_world := Vector3.ZERO
	var best_top: int = -2147483648
	for ix in range(-steps, steps + 1):
		for iz in range(-steps, steps + 1):
			var ox: float = float(ix) * RADIAL_SCAN_STRIDE_M
			var oz: float = float(iz) * RADIAL_SCAN_STRIDE_M
			var d2: float = ox * ox + oz * oz
			if d2 > r2_max:
				continue
			scanned += 1
			var sworld := origin + Vector3(ox, 0.0, oz)
			var sv := _world_to_voxel(sworld)
			var t: int = _water_top_y(tool, sv.x, sv.z, cy)
			if t == -2147483648:
				continue
			hits += 1
			min_top = min(min_top, t)
			max_top = max(max_top, t)
			if d2 < best_d2:
				best_d2 = d2
				best_world = Vector3(sworld.x, float(t + 1) / VOXELS_PER_METER, sworld.z)
				best_top = t

	if hits == 0:
		_emit(lines, "  NEAREST WATER: none within %.0f m of the player." % RADIAL_SCAN_RADIUS_M)
		_emit(lines, "  scanned %d cols @ %.0fm stride — try moving closer to a sea/lake/pond." % [
			scanned, RADIAL_SCAN_STRIDE_M])
		_show_inspect(lines)
		return

	var dx_m: float = best_world.x - origin.x
	var dz_m: float = best_world.z - origin.z
	var dist_m: float = sqrt(best_d2)
	_emit(lines, "  NEAREST WATER: %.1f m %s → world (%.1f, %.2f, %.1f) surfaceVoxY=%d" % [
		dist_m, _compass(dx_m, dz_m), best_world.x, best_world.y, best_world.z, best_top])
	_emit(lines, "  scan: %d cols, %d had water; surfaceVoxY %d..%d (Δ=%d) within %.0f m" % [
		scanned, hits, min_top, max_top, max_top - min_top, RADIAL_SCAN_RADIUS_M])

	# Detailed 3×3 mesh-block Δ grid at the nearest water (or the player
	# column if already over water) — keeps the coplanar/LOD-seam read.
	var gx: int = pv.x if here_top != -2147483648 else _world_to_voxel(best_world).x
	var gz: int = pv.z if here_top != -2147483648 else _world_to_voxel(best_world).z
	var gcy: int = cy if here_top != -2147483648 else best_top
	var step: int = 16
	var center_top: int = _water_top_y(tool, gx, gz, gcy)
	for dz: int in [-1, 0, 1]:
		var row: String = ""
		for dx: int in [-1, 0, 1]:
			var sx: int = gx + dx * step
			var sz: int = gz + dz * step
			var top := _water_top_y(tool, sx, sz, gcy)
			var cnt := _water_count_in_block(tool, sx, sz, gcy)
			var delta_txt := "  ----"
			if top != -2147483648 and center_top != -2147483648:
				delta_txt = "  Δ%+d" % (top - center_top)
			row += "[top=%s n=%d%s] " % [
				("--" if top == -2147483648 else str(top)), cnt, delta_txt]
		_emit(lines, "  grid dz=%+d  %s" % [dz, row])
	_emit(lines, "  READ: equal 'top=' across the grid = coplanar (good); nonzero Δ at a block step = LOD-seam mismatch.")
	_show_inspect(lines)


func _compass(dx_m: float, dz_m: float) -> String:
	# World +X = East, world -Z = North (Godot forward = -Z).
	var ns := ("N" if dz_m < -0.5 else ("S" if dz_m > 0.5 else ""))
	var ew := ("E" if dx_m > 0.5 else ("W" if dx_m < -0.5 else ""))
	var s := ns + ew
	return s if s != "" else "here"


func _emit(lines: Array[String], s: String) -> void:
	print("[WaterInspect] " + s)
	lines.append(s)


func _show_inspect(lines: Array[String]) -> void:
	_inspect_text = "[F5 WaterInspect]\n" + "\n".join(lines)
	_inspect_until_ms = Time.get_ticks_msec() + int(INSPECT_SHOW_SECONDS * 1000.0)
	if _inspect_label != null:
		_inspect_label.text = _inspect_text
	if _inspect_root != null:
		_inspect_root.visible = true


func _water_top_y(tool: Object, vx: int, vz: int, cy: int) -> int:
	# Highest water voxel Y in this column within ±SURFACE_SCAN_VOXELS of
	# cy. cy is the PLAYER/anchor voxel Y, NOT sea level — elevated
	# ponds live well above sea level (the test pond is ~vox 128 vs sea
	# 72), so a sea-anchored band missed them entirely. Returns INT_MIN
	# sentinel if no water in the band.
	var hi := cy + SURFACE_SCAN_VOXELS
	var lo := cy - SURFACE_SCAN_VOXELS
	for vy in range(hi, lo - 1, -1):
		if WaterMaterial.is_water_type(tool.get_voxel(Vector3i(vx, vy, vz))):
			return vy
	return -2147483648


func _water_count_in_block(tool: Object, vx: int, vz: int, cy: int) -> int:
	# Count TYPE-5 voxels in the 16-wide column slab around cy at this XZ
	# block. Cheap proxy for "what the generator/mesher produced here"
	# (no C++ rebuild). Band centred on cy (player/anchor Y), not sea.
	var bx := (vx >> 4) << 4
	var bz := (vz >> 4) << 4
	var n := 0
	var y_lo := cy - 20
	var y_hi := cy + 4
	for ox in range(0, 16, 4):          # 4-stride sample = 64 reads, fast
		for oz in range(0, 16, 4):
			for vy in range(y_lo, y_hi):
				if WaterMaterial.is_water_type(tool.get_voxel(Vector3i(bx + ox, vy, bz + oz))):
					n += 1
	return n


# ============================================================
# F6 — live water shader debug_mode cycle
# ============================================================

func _cycle_shader_debug_mode() -> void:
	if _water_mat == null:
		_water_mat = load(WATER_MATERIAL_PATH) as ShaderMaterial
	if _water_mat == null:
		print("[WaterDiag] cannot cycle debug_mode — water_material.tres not loaded")
		return
	var cur := _get_shader_debug_mode()
	# 0..8 (was % 7; modes 7+8 added 2026-05-27 for the LOD-gap-band
	# diagnosis: 7 = raw ALPHA grayscale, 8 = LOD-distance band).
	var nxt := (cur + 1) % 9
	_water_mat.set_shader_parameter("debug_mode", nxt)
	var names := ["0 normal", "1 depth_t", "2 fresnel", "3 thickness",
		"4 surface-facing", "5 flow-vector", "6 MAGENTA proof-of-life",
		"7 RAW ALPHA grayscale", "8 LOD-distance band"]
	print("[WaterDiag] water shader debug_mode → %s" % names[nxt])


func _get_shader_debug_mode() -> int:
	if _water_mat == null:
		return -1
	var v = _water_mat.get_shader_parameter("debug_mode")
	return int(v) if v != null else -1


# ============================================================
# Helpers
# ============================================================

func _find_player() -> Node3D:
	var ps := get_tree().get_nodes_in_group("player")
	for p in ps:
		if p is Node3D:
			return p as Node3D
	return null


func _get_tool() -> Object:
	if get_node_or_null("/root/VoxelEditManager") == null:
		return null
	var terrain = VoxelEditManager.get_terrain()
	if terrain == null:
		return null
	return terrain.get_voxel_tool()


func _world_to_voxel(world_pos: Vector3) -> Vector3i:
	if get_node_or_null("/root/VoxelEditManager") != null:
		return VoxelEditManager.world_to_voxel(world_pos)
	return Vector3i(
		floori(world_pos.x * VOXELS_PER_METER),
		floori(world_pos.y * VOXELS_PER_METER),
		floori(world_pos.z * VOXELS_PER_METER))


func _sea_voxel_y() -> int:
	var wfm := get_node_or_null("/root/WaterFlowManager")
	if wfm != null and wfm.has_method("get_sea_level_voxel_y"):
		return int(wfm.get_sea_level_voxel_y())
	return 72


func _find_surface_y(world_pos: Vector3) -> float:
	# World-Y of the topmost water voxel in the player's column, scanning
	# a band around the PLAYER's Y (not sea level — elevated ponds were
	# invisible before). Drives the panel surface-Y / Δ readout that #3
	# (flow-Y) and #4 (waterline jitter) need.
	var tool := _get_tool()
	if tool == null:
		return NAN
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	var v := _world_to_voxel(world_pos)
	var top := _water_top_y(tool, v.x, v.z, v.y)
	if top == -2147483648:
		return NAN
	# Top of the water block = (voxelY + 1) / vox-per-m in world space.
	return float(top + 1) / VOXELS_PER_METER


func _expected_lod(dist_m: float) -> int:
	# Best-effort: VoxelLodTerrain doesn't cleanly expose the LOD of an
	# arbitrary mesh block from outside, but the dark grid is gated by
	# the LOD rings, so report the expected LOD from distance vs
	# lod_distance (each LOD ring doubles). Honest approximation.
	if get_node_or_null("/root/VoxelEditManager") == null:
		return -1
	var terrain = VoxelEditManager.get_terrain()
	if terrain == null or not ("lod_distance" in terrain):
		return -1
	var ld := float(terrain.get("lod_distance"))
	if ld <= 0.0 or dist_m < ld:
		return 0
	return int(floor(log(dist_m / ld) / log(2.0))) + 1


# ============================================================
# F8 — LOOK-RAY PROBE
# ============================================================
# Walk a ray from the camera through screen-centre out to 250 m,
# sampling the voxel TYPE at fixed distances. For each sample reports:
#   d_m     — distance along the ray from camera (metres)
#   wpos    — world position of the sample
#   voxel   — voxel-grid coord at that world position
#   TYPE    — CHANNEL_TYPE value at that voxel (raw id)
#   wat     — Y if WaterMaterial.is_water_type(TYPE), N otherwise
#   col3x3  — 3×3 cluster water-count at (vx-1..+1, vz-1..+1) around the
#             sample column (vy fixed) — guards against the ray skimming
#             between voxel centres and producing a false N
#   expLOD  — expected Zylann LOD ring at this distance (lod_distance
#             ring-doubling approximation)
#
# Purpose: when the screen shows a "transparent gap" at LOD-distance,
# this directly answers "is the WATER VOXEL THERE in the buffer at that
# distance?" If voxel data shows wat=Y across all samples but the
# screen shows a gap → fluid mesher is dropping the mesh at LOD>0
# (shipping bug in Zylann fluid). If voxel data shows wat=N at the gap
# distance but Y close to camera → C++ generator isn't emitting water
# at that LOD (regression in heightmap_generator_base.cpp). Either
# way, this probe DECIDES which file owns the fix.

# v1 (2026-05-27) walked a ray from the camera and called
# VoxelTool.get_voxel at each step. Crashed the editor with zero stdout
# even with view_distance guards and is_area_editable pre-flights.
# v2 dropped the raw VoxelTool path entirely and probes via
# WaterFlowManager.is_position_in_water / .get_water_level_at — public
# APIs Player3D already hits every physics frame. No raw tool calls,
# no look-ray walk, no AABB construction. LOOKRAY_DISTANCES is gone.


func _dump_lookray_probe() -> void:
	# v2 (2026-05-27): EVERYTHING is routed through stderr (printerr)
	# because v1's stdout prints were being buffered and lost on the
	# crash. Every potentially-failing call gets a "BEFORE" line so the
	# last surviving log line tells us exactly which step died.
	printerr("[WaterLookRay] v2 BEGIN")
	var lines: Array[String] = []

	# Step 1: get a Player Node3D (group "player"). Avoid the camera —
	# v1 used cam.global_basis.z which depends on first-person vs third-
	# person camera state. Player position is unambiguous.
	printerr("[WaterLookRay] step 1: find player")
	var player := _find_player()
	if player == null:
		printerr("[WaterLookRay] FAIL: no player node in 'player' group")
		_emit_lookray(lines, "no player node (group 'player') — cannot probe")
		_show_inspect(lines)
		return
	var ppos: Vector3 = player.global_position
	printerr("[WaterLookRay] player world=(%s, %s, %s)" % [ppos.x, ppos.y, ppos.z])

	# Step 2: get terrain. Bypass VoxelTool entirely (v1's get_voxel
	# was the prime crash suspect) and use the SAME read path the rest
	# of WaterDiag already uses successfully (WaterFlowManager queries).
	printerr("[WaterLookRay] step 2: resolve WaterFlowManager")
	var wfm := get_node_or_null("/root/WaterFlowManager")
	if wfm == null:
		printerr("[WaterLookRay] FAIL: no WaterFlowManager autoload")
		_emit_lookray(lines, "no WaterFlowManager — cannot probe")
		_show_inspect(lines)
		return

	# Step 3: probe a small XZ grid at sea level around the player. Use
	# WaterFlowManager.is_position_in_water and .get_water_level_at —
	# both are PUBLIC API designed to be called from anywhere safely
	# (Player3D hits them every physics frame). No raw VoxelTool calls.
	printerr("[WaterLookRay] step 3: probe 5x5 grid at sea level")
	var sea_voxY: int = _sea_voxel_y()
	var sea_world_y: float = float(sea_voxY) / VOXELS_PER_METER
	_emit_lookray(lines, "F8 PROBE at player (%.1f, %.1f, %.1f) sea_voxY=%d (worldY=%.2f)" % [
		ppos.x, ppos.y, ppos.z, sea_voxY, sea_world_y])
	_emit_lookray(lines, "  5x5 grid at sea-level world Y=%.2f, stride 4 m (= 24 voxels)" % sea_world_y)
	# Grid header
	var header: String = "       "
	for ix in [-2, -1, 0, 1, 2]:
		header += "  x%+3d " % (int(ix) * 4)
	_emit_lookray(lines, header)
	for iz in [-2, -1, 0, 1, 2]:
		var row: String = "z%+3d   " % (int(iz) * 4)
		for ix in [-2, -1, 0, 1, 2]:
			var probe_pos := Vector3(
				ppos.x + float(ix) * 4.0,
				sea_world_y + 0.1,   # just above sea level so query lands on a water voxel
				ppos.z + float(iz) * 4.0,
			)
			var in_water: bool = bool(wfm.is_position_in_water(probe_pos))
			var lvl: int = int(wfm.get_water_level_at(probe_pos))
			# "W" = is_position_in_water true; "." = false; level appended.
			var cell: String = ("W%d" % lvl) if in_water else (". " if lvl == 0 else "?%d" % lvl)
			row += "  %4s" % cell
		_emit_lookray(lines, row)
	_emit_lookray(lines, "  KEY: W8 = full water, W1-7 = partial, . = no water")
	_emit_lookray(lines, "  READ: all 'W' cells visible on screen as continuous water surface = mesher OK.")
	_emit_lookray(lines, "        any '.' cells inside a body shown as continuous water = mesher emits geometry")
	_emit_lookray(lines, "          where buffer says no water (= over-mesh, not the gap bug).")
	_emit_lookray(lines, "        all 'W' but gap-lines still visible = mesher MISSING faces at chunk boundaries")
	_emit_lookray(lines, "          (= the chunk-mesh-stitching diagnosis — fix in mesher/cull layer).")
	printerr("[WaterLookRay] v2 END — probe printed %d lines" % lines.size())
	_show_inspect(lines)


func _emit_lookray(lines: Array[String], s: String) -> void:
	print("[WaterLookRay] " + s)
	lines.append(s)


# ============================================================
# F9 — FORCE-FILL (developer)
# ============================================================
# Brute-force write WaterByteCodec.SOURCE_BYTE (level 8 + source bit)
# into every voxel in a ±32 m XZ box around the player, clipped to
# Y <= sea level. queue_set_water_box writes BOTH CHANNEL_TYPE (id 23
# fluid full) AND CHANNEL_DATA5 (SOURCE_BYTE) so the fluid mesher and
# the sim both see "full source water" everywhere in the box. Bypasses
# the connectivity fill, settle pass, retry queue — anything that
# might be leaving holes from the sim side.
#
# Bisection: AFTER force-fill, if the LOD-distance gap bands SURVIVE
# (still visible in mode 0 or mode 7), the bug is structural at the
# mesher/generator layer (Zylann fluid LOD-stitching). If they
# VANISH, the bug is the sim leaving partial fills (settle/fill rate
# too slow). The two layers are testable in isolation.
const FORCE_FILL_RADIUS_M: float = 32.0
const FORCE_FILL_DEPTH_M: float = 16.0


func _force_fill_around_player() -> void:
	var player := _find_player()
	if player == null:
		print("[WaterForceFill] no player found; aborting")
		return
	if get_node_or_null("/root/VoxelEditManager") == null \
			or get_node_or_null("/root/WaterFlowManager") == null:
		print("[WaterForceFill] water autoloads missing; aborting")
		return
	var pos: Vector3 = player.global_position
	var sea_y: int = _sea_voxel_y()
	var pv: Vector3i = _world_to_voxel(pos)
	var half: int = int(FORCE_FILL_RADIUS_M * VOXELS_PER_METER)
	var depth: int = int(FORCE_FILL_DEPTH_M * VOXELS_PER_METER)
	var vox_min := Vector3i(pv.x - half, pv.y - depth, pv.z - half)
	var vox_max := Vector3i(pv.x + half, sea_y + 1, pv.z + half)  # excl on max
	# Clamp Y so we never fill above sea level (the water TYPE block
	# above sea is the LOD-gap-band the test is trying to characterise;
	# filling above would mask the symptom).
	if vox_max.y <= vox_min.y:
		print("[WaterForceFill] player above sea level (pv.y=%d, sea_y=%d) — nothing to fill" % [pv.y, sea_y])
		return
	var ok: bool = VoxelEditManager.queue_set_water_box(vox_min, vox_max, WaterByteCodec.SOURCE_BYTE)
	var vol: int = (vox_max.x - vox_min.x) * (vox_max.y - vox_min.y) * (vox_max.z - vox_min.z)
	print("[WaterForceFill] queue_set_water_box %s..%s (~%d voxels, ~%.1f m³ at %.1f vox/m)  ok=%s" % [
		str(vox_min), str(vox_max), vol,
		(vox_max - vox_min).x / VOXELS_PER_METER * (vox_max - vox_min).y / VOXELS_PER_METER * (vox_max - vox_min).z / VOXELS_PER_METER,
		VOXELS_PER_METER, str(ok)])
	if not ok:
		print("[WaterForceFill] queue REJECTED — NoEditZone or queue-full. Move player away from settlement / wait a tick / retry.")
	else:
		print("[WaterForceFill] WATCH: if the LOD-distance gap bands SURVIVE after this fills (give the mesher a few seconds), the bug is in the fluid MESHER at LOD>0, not the fill sim.")
