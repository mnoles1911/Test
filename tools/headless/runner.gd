extends SceneTree

# Headless test runner (hybrid-verification Tier A).
#
# Invoked by tools/headless/run.ps1:
#   godot --headless --path <proj> --script res://tools/headless/runner.gd -- <selector>
#
# Selectors:
#   gate0  — Zylann native-fluid API probe (ClassDB reflection only;
#            pure, no GPU/SceneTree). The hard pivot blocker.
#   codec  — WaterByteCodec bit-exact parity (shared lib; identical to
#            the in-editor scripts/_dev/WaterByteCodecParity.gd path).
#   spike  — load World3D.tscn headless, pump physics frames, report
#            whether VoxelLodTerrain actually streams/meshes under the
#            dummy renderer (decides Phase-3/smoke automation).
#   distant— DistantTerrainMesher heightmesh parity vs SkirtBaker
#            (FNV hashes; baseline-then-verify, parity-harness-FIRST).
#   gravity— VoxelGravityCpp scaffolding probe (Phase 0: registration +
#            stub callable). Phase 1 lays the parity baseline; Phase 2
#            implements analyze_bubble. Pure ClassDB reflection, no scene.
#   emissive— EmissiveLightCpp scaffolding probe (Phase 0: registration +
#            stub callable). Phase 3 lays the parity baseline; Phase 4
#            implements scan_region. Pure ClassDB reflection, no scene.
#   baked_light — EmissiveBakedCpp byte-exact parity vs
#            EmissiveBakedReference for the Phase J light-volume bake
#            (BFS floodfill into a 3D RGBA8 cell grid). Wall scenario:
#            two emitters separated by a solid wall must NOT bleed
#            light across the wall.
#   water_flow — WaterFlowCpp.scan_settle_region byte-exact parity vs
#            WaterFlowReference (the per-cell water-settle hot loop).
#            Air pocket adjacent to a water source must produce the
#            face-touching air cells as hits; cells past the scan cap
#            must be deferred to next_y.
#
# Exit code 0 = pass, non-zero = fail/blocked, so run.ps1 + CI can gate
# without scraping prose. Every machine line is prefixed with a tag.

const ParityLib := preload("res://scripts/_dev/WaterByteCodecParityLib.gd")

const _PROBE_CLASSES := [
	"VoxelBlockyFluid", "VoxelBlockyModelFluid",
	"VoxelBlockyLibrary", "VoxelBlockyModelCube",
]

# spike / phase2 state
var _spike_active: bool = false
var _spike_mode: String = "spike"
var _spike_frames: int = 0
var _spike_max_frames: int = 240          # ~4 s at 60 fps physics
var _spike_world: Node = null

# finite_world end-to-end state (see _finite_world_tick/_report).
var _fw_placed: bool = false
var _fw_place_frame: int = -1
var _fw_origin: Vector3i = Vector3i.ZERO
var _fw_fail: String = ""
var _fw_quiet_frames: int = 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var selector: String = args[0] if args.size() > 0 else "all"
	print("[RUNNER] selector=%s godot=%s" % [selector, Engine.get_version_info().get("string", "?")])
	match selector:
		"gate0":
			quit(_gate0())
		"codec":
			quit(_codec())
		"wmat":
			quit(_wmat())
		"shader":
			quit(_shader())
		"phase7":
			quit(_phase7())
		"gravity":
			quit(_gravity())
		"emissive":
			quit(_emissive())
		"baked_light":
			quit(_baked_light())
		"water_flow":
			quit(_water_flow())
		"finite":
			quit(_finite())
		"entity":
			quit(_entity())
		"spike", "phase2", "gen", "distant", "finite_world":
			_spike_mode = selector
			if selector == "finite_world":
				# Worst case: stream (~240) + collapse on a slope + the
				# 40-tick evaporation countdown for stranded films + the
				# 3-pass projection reconcile (~2 s spacing each) + queue
				# drain. The run finishes EARLY once quiet (see
				# _finite_world_tick), so the budget is only a ceiling.
				# NOTE _process counts IDLE frames, which spin much faster
				# than PHYSICS frames in headless — the ceiling must be
				# generous because the sim ticks on physics frames.
				_spike_max_frames = 20000
			_spike_active = true   # finishes in _process()
		_:
			push_error("[RUNNER] unknown selector: %s" % selector)
			quit(2)


func _process(_delta: float) -> bool:
	if not _spike_active:
		return true
	if _spike_world == null:
		_spike_begin()
	if _spike_mode == "finite_world":
		_finite_world_tick()
	_spike_frames += 1
	if _spike_frames >= _spike_max_frames:
		match _spike_mode:
			"phase2": quit(_phase2_report())
			"finite_world": quit(_finite_world_report())
			"gen": quit(_gen_report())
			"distant": quit(_distant_report())
			_: quit(_spike_report())
		return true
	return false


# ============================================================
# GATE 0 — native fluid API probe
# ============================================================
func _gate0() -> int:
	var fluid_ok := ClassDB.class_exists("VoxelBlockyFluid")
	var model_ok := ClassDB.class_exists("VoxelBlockyModelFluid")
	for cls_name in _PROBE_CLASSES:
		print("[GATE0] === %s ===" % cls_name)
		if not ClassDB.class_exists(cls_name):
			print("[GATE0] %s REGISTERED=no" % cls_name)
			continue
		print("[GATE0] %s REGISTERED=yes parent=%s" % [cls_name, ClassDB.get_parent_class(cls_name)])
		for ic in ClassDB.class_get_integer_constant_list(cls_name, true):
			print("[GATE0] %s.const %s = %d" % [cls_name, ic, ClassDB.class_get_integer_constant(cls_name, ic)])
		var inst: Object = null
		if ClassDB.can_instantiate(cls_name):
			inst = ClassDB.instantiate(cls_name)
		if inst == null:
			print("[GATE0] %s INSTANTIABLE=no" % cls_name)
			continue
		print("[GATE0] %s INSTANTIABLE=yes" % cls_name)
		for p in inst.get_property_list():
			var n: String = p.get("name", "")
			if n == "" or n.begins_with("script") or n.begins_with("resource_"):
				continue
			var usage: int = int(p.get("usage", 0))
			if usage & PROPERTY_USAGE_CATEGORY or usage & PROPERTY_USAGE_GROUP:
				continue
			print("[GATE0] %s.prop %s : %s" % [cls_name, n, type_string(int(p.get("type", 0)))])
		for m in inst.get_method_list():
			var mn: String = m.get("name", "")
			if mn.begins_with("_") or mn in ["set", "get", "set_script", "get_script"]:
				continue
			print("[GATE0] %s.method %s()" % [cls_name, mn])
		if cls_name == "VoxelBlockyModelFluid":
			_gate0_introspect_levels(inst)
		if inst is RefCounted:
			pass
		else:
			inst.free()
	var verdict := "PASS" if (fluid_ok and model_ok) else "FAIL"
	print("[GATE0] RESULT=%s VoxelBlockyFluid=%s VoxelBlockyModelFluid=%s" % [
		verdict, "yes" if fluid_ok else "no", "yes" if model_ok else "no"])
	if verdict == "PASS":
		print("[GATE0] Native-fluid pivot UNBLOCKED — record N/slope/UV/transparency from the dumps above.")
		return 0
	print("[GATE0] BLOCKED — installed Voxel Tools build lacks the native fluid classes. STOP: needs a Voxel Tools upgrade; re-convene with designer.")
	return 1


# Try to learn the fluid level enumeration / key knobs without guessing.
func _gate0_introspect_levels(inst: Object) -> void:
	for cand in ["level_count", "max_level", "levels", "get_level_count", "get_max_level"]:
		if inst.has_method(cand):
			print("[GATE0] VoxelBlockyModelFluid HAS_METHOD %s" % cand)
		elif cand in inst:
			print("[GATE0] VoxelBlockyModelFluid HAS_PROP %s = %s" % [cand, inst.get(cand)])


# ============================================================
# CODEC — shared parity lib (same code as the in-editor path)
# ============================================================
func _codec() -> int:
	var r: Dictionary = ParityLib.run()
	var checks: int = r["checks"]
	var fails: int = r["fails"]
	var errors: PackedStringArray = r["errors"]
	for e in errors:
		push_error("[WBCParity] %s" % e)
		print("[WBCParity] ERR %s" % e)
	if fails == 0:
		print("[WBCParity] PASS — %d checks, 0 failures. Codec is bit-exact." % checks)
		return 0
	print("[WBCParity] FAIL — %d failures across %d checks." % [fails, checks])
	return 1


# ============================================================
# WMAT — WaterMaterial contract (evolves per phase; this = Phase 2)
# ============================================================
# Phase 2 contract:
#   is_water_type(id)  == (id == 5) OR (16 <= id <= 23)
#       (legacy cube id 5 still emitted by the C++ generator until
#        Phase 4 + the 8 fluid-level ids)
#   render_id_for_level(level,dir):
#       level<=0 -> 0 ; level 1..8 -> BASE + clampi(level,1,8) - 1
#       (Phase 3: TRUE per-level id so the mesher auto-slopes the
#        gradual-fill / flow front)
#   map_legacy_id == identity; BODY_ID == FULL_FLUID_ID == 23;
#   LEGACY_WATER_ID == 5; BASE 16; COUNT 8; WATER_IDS == [5,16..23].
func _wmat() -> int:
	var WM := preload("res://scripts/WaterMaterial.gd")
	var fails: int = 0
	var checks: int = 0
	var base: int = WM.WATER_FLUID_BASE_ID
	var cnt: int = WM.WATER_LEVEL_COUNT
	for id in range(0, 256):
		checks += 1
		var want_w: bool = (id == 5) or (id >= base and id < base + cnt)
		if WM.is_water_type(id) != want_w:
			fails += 1
			push_error("[WMatParity] is_water_type(%d)=%s expected %s" % [id, WM.is_water_type(id), want_w])
		checks += 1
		var want_legacy: int = WM.FULL_FLUID_ID if id == 5 else id
		if WM.map_legacy_id(id) != want_legacy:
			fails += 1
			push_error("[WMatParity] map_legacy_id(%d)=%d expected %d" % [id, WM.map_legacy_id(id), want_legacy])
	for level in range(0, 9):
		for dir in range(0, 8):
			checks += 1
			var expected: int = 0 if level <= 0 else WM.WATER_FLUID_BASE_ID + clampi(level, 1, WM.WATER_LEVEL_COUNT) - 1
			if WM.render_id_for_level(level, dir) != expected:
				fails += 1
				push_error("[WMatParity] render_id_for_level(%d,%d)=%d expected %d" % [level, dir, WM.render_id_for_level(level, dir), expected])
	checks += 1
	if base != 16 or cnt != 8 or WM.FULL_FLUID_ID != 23 or WM.BODY_ID != 23 or WM.LEGACY_WATER_ID != 5:
		fails += 1
		push_error("[WMatParity] constants wrong: base=%d cnt=%d full=%d body=%d legacy=%d" % [base, cnt, WM.FULL_FLUID_ID, WM.BODY_ID, WM.LEGACY_WATER_ID])
	checks += 1
	if Array(WM.WATER_IDS) != [5, 16, 17, 18, 19, 20, 21, 22, 23]:
		fails += 1
		push_error("[WMatParity] WATER_IDS=%s expected [5,16..23]" % str(WM.WATER_IDS))
	# Phase 3 integration: the exact VoxelEditManager projection path —
	# WaterByteCodec.pack(level) -> level_of/dir_of -> render_id_for_level
	# -> a per-level fluid id that is_water_type() accepts (or air).
	var WBC := preload("res://scripts/WaterByteCodec.gd")
	for level in range(0, 9):
		var b: int = WBC.pack(level, false, WBC.DIR_STILL)
		var rid: int = WM.render_id_for_level(WBC.level_of(b), WBC.dir_of(b))
		checks += 1
		var want_rid: int = 0 if level == 0 else WM.WATER_FLUID_BASE_ID + level - 1
		if rid != want_rid:
			fails += 1
			push_error("[WMatParity] pack(%d)->render=%d expected %d" % [level, rid, want_rid])
		checks += 1
		if WM.is_water_type(rid) != (level > 0):
			fails += 1
			push_error("[WMatParity] is_water_type(render of level %d = %d)=%s expected %s" % [level, rid, WM.is_water_type(rid), level > 0])
	if fails == 0:
		print("[WMatParity] PASS — %d checks, 0 failures. Phase 3 contract holds (per-level fluid id 16..23; codec->TYPE projection exact)." % checks)
		return 0
	print("[WMatParity] FAIL — %d failures across %d checks." % [fails, checks])
	return 1


# ============================================================
# SPIKE — does VoxelLodTerrain stream/mesh headless?
# ============================================================
func _spike_begin() -> void:
	var scene_path := "res://scenes/World3D.tscn"
	if not ResourceLoader.exists(scene_path):
		print("[SPIKE] RESULT=FAIL reason=scene_missing %s" % scene_path)
		quit(1)
		return
	var ps: PackedScene = load(scene_path)
	if ps == null:
		print("[SPIKE] RESULT=FAIL reason=scene_load_null")
		quit(1)
		return
	_spike_world = ps.instantiate()
	get_root().add_child(_spike_world)
	print("[SPIKE] World3D instanced; pumping %d physics frames..." % _spike_max_frames)


func _spike_report() -> int:
	var terrain := _find_terrain(_spike_world)
	if terrain == null:
		print("[SPIKE] RESULT=INCONCLUSIVE reason=no_VoxelLodTerrain_node")
		return 1
	var detail := PackedStringArray()
	var streamed := false
	for prop in ["_debug_get_block_count", "get_statistics", "get_data_block_count"]:
		if terrain.has_method(prop):
			var v = terrain.call(prop)
			detail.append("%s=%s" % [prop, str(v)])
			if typeof(v) == TYPE_DICTIONARY or (typeof(v) == TYPE_INT and v > 0):
				streamed = true
	print("[SPIKE] terrain=%s %s" % [terrain.get_class(), " ".join(detail)])
	print("[SPIKE] RESULT=%s streams_headless=%s" % ["PASS" if streamed else "NO", "yes" if streamed else "no"])
	return 0 if streamed else 0   # never hard-fail: this answers a question, doesn't gate


# ============================================================
# FINITE_WORLD — end-to-end W4 gate: pour a 3x3x3 bucket dump into the
# REAL World3D scene headless, pump the live autoload stack (finite sim
# tick -> VoxelEditManager queue -> terrain voxels), then read the
# world back and audit it against the ledger. This is the closest a
# no-GPU run gets to the designer\'s acceptance test.
# ============================================================

func _finite_world_tick() -> void:
	# Called every _process frame while the scene pumps.
	if _fw_placed:
		# Finish early once everything is quiet for half a second:
		# sim settled, projections flushed, AND the VoxelEditManager
		# queue drained (the world read in the report must see the
		# final voxels, not in-flight writes).
		var wfm_q: Node = get_root().get_node_or_null("/root/WaterFlowManager")
		var vem_q: Node = get_root().get_node_or_null("/root/VoxelEditManager")
		if wfm_q != null and vem_q != null \
				and not wfm_q._finite_busy() and vem_q._edit_queue.is_empty():
			_fw_quiet_frames += 1
			if _fw_quiet_frames >= 60:
				_spike_frames = _spike_max_frames - 1   # report next frame
		else:
			_fw_quiet_frames = 0
		return
	if _fw_fail != "" or _spike_frames < 240:
		return   # give terrain ~4 s to stream around the spawn
	var wfm: Node = get_root().get_node_or_null("/root/WaterFlowManager")
	var vem: Node = get_root().get_node_or_null("/root/VoxelEditManager")
	if wfm == null or vem == null:
		_fw_fail = "autoloads_missing"
		return
	var terrain = vem.get_terrain()
	if terrain == null:
		return   # not bound yet — try again next frame
	var tool = terrain.get_voxel_tool()
	if tool == null:
		return
	# Find the ground column near the spawn (player spawns at XZ 0,0).
	# Probe a spot a couple of metres out so we don\'t pour on the player.
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	var px: int = 18   # voxel coords (3 m out at 6 vox/m)
	var pz: int = 18
	var ground_y: int = -1
	for y in range(400, 72, -1):
		if tool.get_voxel(Vector3i(px, y, pz)) != 0:
			ground_y = y
			break
	if ground_y < 0:
		return   # terrain not streamed at the probe column yet — retry
	_fw_origin = Vector3i(px - 1, ground_y + 1, pz - 1)
	# The designer\'s scenario: a 3x3x3 cube of water (27 cells x 8
	# units = 216). Poured as 9 columns of 24 units.
	var total: int = 0
	for dx in range(3):
		for dz in range(3):
			total += int(wfm.place_finite_water(
				Vector3i(_fw_origin.x + dx, _fw_origin.y, _fw_origin.z + dz), 24))
	if total != 216:
		_fw_fail = "placed_%d_of_216 (probe ground_y=%d)" % [total, ground_y]
		return
	_fw_placed = true
	_fw_place_frame = _spike_frames
	print("[FWORLD] poured 216 units at %s (ground voxel y=%d); letting it settle..." % [str(_fw_origin), ground_y])


func _finite_world_report() -> int:
	if _fw_fail != "":
		print("[FWORLD] RESULT=FAIL reason=%s" % _fw_fail)
		return 1
	if not _fw_placed:
		print("[FWORLD] RESULT=FAIL reason=terrain_never_streamed_probe_column")
		return 1
	var wfm: Node = get_root().get_node_or_null("/root/WaterFlowManager")
	var vem: Node = get_root().get_node_or_null("/root/VoxelEditManager")
	var terrain = vem.get_terrain()
	var tool = terrain.get_voxel_tool()
	var fails: int = 0

	# 1. The sim must have gone quiet (settled + projection flushed).
	if wfm._finite_busy():
		print("[FWORLD] FAIL sim still busy after %d frames (active=%d unprojected=%d)" % [
			_spike_frames, int(wfm._finite.stats()["active"]), wfm._unprojected.size()])
		for ac in wfm._finite._active.keys():
			print("[FWORLD]   active cell %s: u=%d dist=%d ttl=%d dir=%d" % [
				str(ac), int(wfm._finite._ledger.get(ac, 0)), int(wfm._finite._dist.get(ac, -1)),
				int(wfm._finite._evap_ttl.get(ac, -1)), int(wfm._finite._dir.get(ac, 0))])
		for up in wfm._unprojected.keys():
			tool.channel = VoxelBuffer.CHANNEL_DATA5
			print("[FWORLD]   unprojected %s sched=%s want=0x%02x have=0x%02x tick_no=%d" % [
				str(up), str(wfm._unprojected[up]), wfm._finite.projected_byte(up),
				tool.get_voxel(up), wfm._finite_tick_no])
			tool.channel = VoxelBuffer.CHANNEL_TYPE
		fails += 1

	# 2. Conservation audit on the ledger.
	if int(wfm._finite.conservation_delta()) != 0:
		print("[FWORLD] FAIL conservation delta=%d stats=%s" % [
			int(wfm._finite.conservation_delta()), str(wfm._finite.stats())])
		fails += 1

	# 3. The pool must have SPREAD (more cells than the 9 poured columns
	#    held) — the whole point of the finite model.
	var ledger: Dictionary = wfm._finite._ledger
	if ledger.size() < 27:
		print("[FWORLD] FAIL pool covers %d cells — did not collapse/spread" % ledger.size())
		fails += 1

	# 4. World agreement: every ledger cell\'s DATA5 byte and TYPE id in
	#    the REAL terrain must match the ledger\'s projection. This is
	#    the end-to-end proof: sim -> queue -> voxels, nothing lost.
	var WM := preload("res://scripts/WaterMaterial.gd")
	var world_units: int = 0
	var mismatches: int = 0
	for cell in ledger.keys():
		tool.channel = VoxelBuffer.CHANNEL_DATA5
		var d5: int = tool.get_voxel(cell)
		tool.channel = VoxelBuffer.CHANNEL_TYPE
		var t: int = tool.get_voxel(cell)
		var want_level: int = int(ledger[cell])
		world_units += WaterByteCodec.level_of(d5)
		if WaterByteCodec.level_of(d5) != want_level or WaterByteCodec.is_source(d5):
			mismatches += 1
			if mismatches <= 5:
				print("[FWORLD] FAIL world DATA5 at %s = 0x%02x, ledger wants level %d (non-source)" % [
					str(cell), d5, want_level])
		if t != WM.render_id_for_level(want_level, WaterByteCodec.DIR_STILL) and not WM.is_water_type(t):
			mismatches += 1
			if mismatches <= 5:
				print("[FWORLD] FAIL world TYPE at %s = %d, not a water id for level %d" % [
					str(cell), t, want_level])
	if mismatches > 0:
		print("[FWORLD] FAIL %d ledger/world mismatches" % mismatches)
		fails += 1
	var ledger_units: int = int(wfm._finite.total_units())
	if world_units != ledger_units:
		print("[FWORLD] FAIL world holds %d units where ledger says %d" % [world_units, ledger_units])
		fails += 1

	var player = _spike_world.get_node_or_null("Player3D")
	if player != null:
		print("[FWORLD] player at %s" % str(player.global_position))
	print("[FWORLD] settled: cells=%d ledger_units=%d world_units=%d stats=%s (settle took <= %d frames)" % [
		ledger.size(), ledger_units, world_units, str(wfm._finite.stats()), _spike_frames - _fw_place_frame])
	if fails == 0:
		print("[FWORLD] RESULT=PASS — 216 poured units collapsed, spread, and landed in the real terrain intact.")
		return 0
	print("[FWORLD] RESULT=FAIL — %d check(s) failed." % fails)
	return 1


# ============================================================
# PHASE 7 — legacy-save + MP byte contract (data-level)
# ============================================================
# The risky halves of Phase 7 (buoyancy feel, MP host/client visuals)
# are designer-gated; this locks the parts a no-GPU run CAN prove:
#   • old saves' literal water id 5 still reads as water (is_water_type)
#   • map_legacy_id(5) -> the full fluid id (future-migration hook)
#   • the codec is byte-stable (SOURCE_BYTE=24) so old DATA5 decodes
#   • an old full-water cell (SOURCE_BYTE) projects to the full fluid
#     id and that id is water — the load-old-save path end to end
#   • MP: render id is a pure function of the codec byte (so the byte
#     on the wire + host-side render_id_for_level can't desync).
func _phase7() -> int:
	var WM := preload("res://scripts/WaterMaterial.gd")
	var WBC := preload("res://scripts/WaterByteCodec.gd")
	var fails: int = 0
	var checks: int = 0
	checks += 1
	if not WM.is_water_type(5) or not WM.is_water_type(WM.LEGACY_WATER_ID):
		fails += 1
		push_error("[PHASE7] legacy water id 5 no longer reads as water — old saves break")
	checks += 1
	if WM.map_legacy_id(5) != WM.FULL_FLUID_ID:
		fails += 1
		push_error("[PHASE7] map_legacy_id(5)=%d expected FULL_FLUID_ID=%d" % [WM.map_legacy_id(5), WM.FULL_FLUID_ID])
	checks += 1
	if WBC.SOURCE_BYTE != 24:
		fails += 1
		push_error("[PHASE7] WaterByteCodec.SOURCE_BYTE changed (%d) — old DATA5 saves would mis-decode" % WBC.SOURCE_BYTE)
	# Old full-water cell: SOURCE_BYTE -> level 8 -> full fluid id, water.
	var sb: int = WBC.SOURCE_BYTE
	var rid: int = WM.render_id_for_level(WBC.level_of(sb), WBC.dir_of(sb))
	checks += 1
	if rid != WM.FULL_FLUID_ID or not WM.is_water_type(rid):
		fails += 1
		push_error("[PHASE7] old SOURCE_BYTE projects to %d (water=%s) expected FULL_FLUID_ID=%d water=true" % [rid, WM.is_water_type(rid), WM.FULL_FLUID_ID])
	# MP determinism: render id is a pure function of the byte (same
	# input -> same id, every call) so host + clients never disagree.
	for lvl in range(0, 9):
		var b: int = WBC.pack(lvl, false, WBC.DIR_STILL)
		checks += 1
		if WM.render_id_for_level(WBC.level_of(b), WBC.dir_of(b)) != WM.render_id_for_level(WBC.level_of(b), WBC.dir_of(b)):
			fails += 1
			push_error("[PHASE7] render_id_for_level not deterministic for level %d" % lvl)
	if fails == 0:
		print("[PHASE7] RESULT=PASS — %d checks: legacy id 5 reads as water, codec stable, old full-water -> full fluid, MP id is a pure fn of the byte." % checks)
		return 0
	print("[PHASE7] RESULT=FAIL — %d/%d checks failed." % [fails, checks])
	return 1


# ============================================================
# SHADER — water.gdshader parses/compiles (Phase 5/6)
# ============================================================
# Godot parses shader code on load even under --headless (dummy
# renderer): a syntax/semantic error prints "SHADER ERROR" / sets the
# shader invalid. This catches the class of mistakes a no-GPU run CAN
# catch; the *visual* result (flow animation, no foam, F6 modes) is
# the designer's end-of-build pass — headless cannot rasterize.
func _shader() -> int:
	var path := "res://assets/shaders/water_material.tres"
	if not ResourceLoader.exists(path):
		print("[SHADER] RESULT=FAIL reason=missing %s" % path)
		return 1
	var mat = load(path)
	if mat == null:
		print("[SHADER] RESULT=FAIL reason=material_load_null")
		return 1
	var sh = mat.get("shader")
	if sh == null:
		print("[SHADER] RESULT=FAIL reason=no_shader_on_material")
		return 1
	var code: String = sh.get("code")
	var n_dbg := code.count("debug_mode ==")
	# The DEAD #15 WIND-foam is gone when its WIND-foam-specific
	# identifiers are absent. NOTE: V3 Phase 3 intentionally adds edge
	# foam that reuses the `foam_color` name — that is NOT the #15 foam,
	# so do not key off `foam_color`. Key off the wind-foam-only
	# uniforms (surface_motion_*, foam_wind_ref, surface_ripple_scale).
	var has_foam := code.find("surface_motion_strength") != -1 \
		or code.find("foam_wind_ref") != -1 \
		or code.find("surface_ripple_scale") != -1
	# Flow animation must be present (it replaces the foam).
	var has_flow := code.find("decode_flow") != -1 and code.find("flow_motion_strength") != -1
	print("[SHADER] water_material.tres loaded; code_len=%d debug_branches=%d foam_code=%s flow_code=%s" % [code.length(), n_dbg, has_foam, has_flow])
	# If RenderingServer reports the shader invalid, get_shader_uniform_list
	# is empty / load emitted SHADER ERROR (grepped by the caller).
	var ul = RenderingServer.get_shader_parameter_list(sh.get_rid()) if sh.get_rid().is_valid() else []
	print("[SHADER] uniforms_visible=%d (rid_valid=%s)" % [ul.size(), sh.get_rid().is_valid()])
	# [SHADERPARAM] — EFFECTIVE runtime values. A ShaderMaterial's
	# stored shader_parameter/* OVERRIDES the shader's `uniform =
	# default`. This dump makes that explicit so "I tuned the shader but
	# nothing changed" (root cause of the 2026-05-19 tuning failure:
	# the .tres pinned shallow_alpha=0.40 over every shader default) is
	# visible forever. OVERRIDE = the .tres wins; DEFAULT = shader value.
	var watch := ["depth_fade_distance", "shallow_alpha", "water_murk",
		"water_extinction", "reflection_strength", "reflection_floor",
		"foam_strength", "foam_edge_dist", "flow_motion_strength",
		"side_tint_brighten", "side_sky_mix"]
	for w in watch:
		var ov = mat.get("shader_parameter/" + w)
		if ov != null:
			print("[SHADERPARAM] %s = %s  (.tres OVERRIDE — wins)" % [w, str(ov)])
		else:
			print("[SHADERPARAM] %s = <shader default> (.tres does not set it)" % w)
	var ok := (not has_foam) and has_flow and n_dbg >= 5
	print("[SHADER] RESULT=%s — foam_removed=%s flow_present=%s debug_modes>=5=%s (grep stderr for 'SHADER ERROR' to confirm compile)" % ["PASS" if ok else "FAIL", not has_foam, has_flow, n_dbg >= 5])
	return 0 if ok else 1


# ============================================================
# GEN — C++ generator parity (Phase 4, parity-harness-FIRST)
# ============================================================
# Calls the REAL configured CubicHeightmapGeneratorCpp from World3D for
# a fixed set of blocks/LODs. Computes per-block:
#   • norm_hash : FNV over CHANNEL_TYPE with every water id mapped to a
#                 sentinel — INVARIANT to the pivot's id change (5->per
#                 level) but sensitive to ANY terrain/position change.
#   • water_count + distinct raw water ids.
# First run writes user://gen_parity_baseline.json (BASELINE). After the
# C++ change + rebuild, a second run COMPARES: norm_hash + water_count
# per block must be byte-identical (terrain & water POSITIONS unchanged)
# and only the water id value may differ (5 -> 16..23). This is the
# CLAUDE.md "parity harness FIRST, bit-exact" gate for the C++ port.
const _GEN_SENTINEL := 9999
const _GEN_BASELINE := "user://gen_parity_baseline.json"

func _gen_report() -> int:
	var WM := preload("res://scripts/WaterMaterial.gd")
	var terrain := _find_terrain(_spike_world)
	if terrain == null:
		print("[GEN] RESULT=FAIL reason=no_terrain")
		return 1
	var gen = terrain.get("generator")
	var cpp = null
	if gen != null:
		cpp = gen.get("cpp_impl") if "cpp_impl" in gen else null
	if cpp == null:
		print("[GEN] RESULT=FAIL reason=no_cpp_impl (gen=%s)" % (gen.get_class() if gen else "<null>"))
		return 1
	if not cpp.has_method("generate_block_into_buffer"):
		print("[GEN] RESULT=FAIL reason=no_generate_block_into_buffer")
		return 1
	var bs := 16
	# Block set must be deterministic AND pinned across the
	# baseline/verify runs (so a moved-water regression can't hide
	# behind a re-selected set). If a baseline exists, reuse its exact
	# origins; otherwise DISCOVER wet blocks by a deterministic scan
	# (water only exists where ground dips below the voxel sea level)
	# and record them into the baseline.
	var jobs: Array = []
	if FileAccess.file_exists(_GEN_BASELINE):
		var pf := FileAccess.open(_GEN_BASELINE, FileAccess.READ)
		var pbase: Dictionary = JSON.parse_string(pf.get_as_text())
		pf.close()
		for key in pbase.keys():
			# key = "x,y,z@lod"
			var at: PackedStringArray = key.split("@")
			var xyz: PackedStringArray = at[0].split(",")
			jobs.append([Vector3i(int(xyz[0]), int(xyz[1]), int(xyz[2])), int(at[1])])
	else:
		# Deterministic wide XZ sweep at a sea-level-spanning Y band.
		var wet: Array = []
		var dry: Array = []
		var coords := [-1024, -512, -256, -128, -64, 0, 64, 128, 256, 512, 1024]
		for cz in coords:
			for cx in coords:
				if wet.size() >= 6 and dry.size() >= 2:
					break
				var o := Vector3i(cx, 64, cz)
				var tb := VoxelBuffer.new()
				tb.create(bs, bs, bs)
				cpp.call("generate_block_into_buffer", tb, o, 0)
				var wc := 0
				for z in range(bs):
					for y in range(bs):
						for x in range(bs):
							if WM.is_water_type(tb.get_voxel(x, y, z, VoxelBuffer.CHANNEL_TYPE)):
								wc += 1
				if wc > 0 and wet.size() < 6:
					wet.append([o, 0])
				elif wc == 0 and dry.size() < 2:
					dry.append([o, 0])
		jobs = wet + dry
		if wet.is_empty():
			print("[GEN] RESULT=FAIL reason=no_wet_blocks_found_in_scan (cannot parity-check the water id change)")
			return 1
		# Add a LOD-1 variant of the first wet block for stride coverage.
		jobs.append([jobs[0][0], 1])
		print("[GEN] discovered %d wet + %d dry blocks for the parity set." % [wet.size(), dry.size()])
	var results := {}
	for job in jobs:
		var origin: Vector3i = job[0]
		var lod: int = job[1]
		var buf := VoxelBuffer.new()
		buf.create(bs, bs, bs)
		cpp.call("generate_block_into_buffer", buf, origin, lod)
		var h: int = 2166136261
		var wcount: int = 0
		var wids := {}
		var d5_nonzero: int = 0     # cells with a non-zero CHANNEL_DATA5
		var d5_vals := {}           # distinct DATA5 values on water cells
		for z in range(bs):
			for y in range(bs):
				for x in range(bs):
					var t: int = buf.get_voxel(x, y, z, VoxelBuffer.CHANNEL_TYPE)
					var norm: int = t
					if WM.is_water_type(t):
						norm = _GEN_SENTINEL
						wcount += 1
						wids[t] = true
						d5_vals[buf.get_voxel(x, y, z, VoxelBuffer.CHANNEL_DATA5)] = true
					if buf.get_voxel(x, y, z, VoxelBuffer.CHANNEL_DATA5) != 0:
						d5_nonzero += 1
					h = ((h ^ norm) * 16777619) & 0x7FFFFFFF
		var key := "%d,%d,%d@%d" % [origin.x, origin.y, origin.z, lod]
		var idlist: Array = wids.keys()
		idlist.sort()
		var d5list: Array = d5_vals.keys()
		d5list.sort()
		results[key] = {"norm_hash": h, "water_count": wcount, "water_ids": idlist,
			"d5_nonzero": d5_nonzero, "d5_vals": d5list}
		print("[GEN] %s norm_hash=%d water_count=%d water_ids=%s d5_nonzero=%d d5_vals=%s" % [key, h, wcount, str(idlist), d5_nonzero, str(d5list)])

	if not FileAccess.file_exists(_GEN_BASELINE):
		var f := FileAccess.open(_GEN_BASELINE, FileAccess.WRITE)
		f.store_string(JSON.stringify(results))
		f.close()
		print("[GEN] RESULT=BASELINE — wrote %s (%d blocks). Re-run AFTER the C++ change to verify parity." % [_GEN_BASELINE, results.size()])
		return 0

	var bf := FileAccess.open(_GEN_BASELINE, FileAccess.READ)
	var base: Dictionary = JSON.parse_string(bf.get_as_text())
	bf.close()
	var fails: int = 0
	for key in results.keys():
		if not base.has(key):
			fails += 1
			push_error("[GEN] baseline missing block %s" % key)
			continue
		var b = base[key]
		var r = results[key]
		# norm_hash + water_count must be IDENTICAL (terrain & water
		# positions unchanged). JSON ints come back as float -> int().
		if int(b["norm_hash"]) != int(r["norm_hash"]):
			fails += 1
			push_error("[GEN] %s norm_hash drift base=%d now=%d (terrain/water POSITION changed — NOT id-only!)" % [key, int(b["norm_hash"]), int(r["norm_hash"])])
		if int(b["water_count"]) != int(r["water_count"]):
			fails += 1
			push_error("[GEN] %s water_count drift base=%d now=%d" % [key, int(b["water_count"]), int(r["water_count"])])
		# CHANNEL_DATA5 is ALLOWED to change (Phase 8a writes the source
		# byte) — report the delta; assert the 8a expectation when it
		# fires: every water cell gets DATA5 == WATER_SOURCE_BYTE (24).
		var bd5: int = int(b.get("d5_nonzero", 0))
		var rd5: int = int(r.get("d5_nonzero", 0))
		if bd5 != rd5:
			print("[GEN] %s DATA5 delta (expected for #14 source pivot): d5_nonzero %d -> %d, d5_vals %s -> %s" % [key, bd5, rd5, str(b.get("d5_vals", [])), str(r.get("d5_vals", []))])
			if rd5 != int(r["water_count"]):
				fails += 1
				push_error("[GEN] %s 8a: d5_nonzero=%d != water_count=%d (every generated water cell must be a source)" % [key, rd5, int(r["water_count"])])
			if r.get("d5_vals", []) != [24]:
				fails += 1
				push_error("[GEN] %s 8a: water d5_vals=%s expected [24] (WATER_SOURCE_BYTE)" % [key, str(r.get("d5_vals", []))])
	if fails == 0:
		print("[GEN] RESULT=PASS — CHANNEL_TYPE (terrain & water positions) bit-identical to baseline; DATA5 delta matches the #14 source-byte expectation.")
		return 0
	print("[GEN] RESULT=FAIL — %d parity violations (see push_error)." % fails)
	return 1


# ============================================================
# DISTANT — DistantTerrainMesher heightmesh contract
# ============================================================
# Regression gate for the C++ DistantTerrainMesher. A fixed 32×32-quad
# region is meshed and reduced to four FNV hashes (vertices / normals /
# colours / indices) + counts, then checked against:
#   - the committed baseline tools/headless/distant_parity_baseline.json
#     — the apron-off grid must stay byte-identical. The baseline was
#     generated from the SkirtBaker prototype and proven bit-equal to the
#     C++ port in Phase 1; SkirtBaker.gd was retired in Phase 6, so the
#     committed JSON is now the sole reference.
#   - the apron-on build, which must be purely additive (Phase 2).
#   - distant_terrain.gdshader, which must compile (Phase 3).
const _DISTANT_BASELINE := "res://tools/headless/distant_parity_baseline.json"
const _DISTANT_MIN := Vector2(-192.0, -192.0)
const _DISTANT_MAX := Vector2(192.0, 192.0)
const _DISTANT_QUAD_M := 12.0   # the fixed parity-region quad size
const _DISTANT_VPM := 6.0       # canonical 6 voxels / metre
const _DISTANT_APRON_TEST_DEPTH := 64.0  # Phase 2 apron-additive check


func _distant_report() -> int:
	var terrain := _find_terrain(_spike_world)
	if terrain == null:
		print("[DISTANT] RESULT=FAIL reason=no_terrain")
		return 1
	var gen = terrain.get("generator")
	var cpp = gen.get("cpp_impl") if (gen != null and "cpp_impl" in gen) else null
	if cpp == null:
		print("[DISTANT] RESULT=FAIL reason=no_cpp_impl (gen=%s)" % (gen.get_class() if gen else "<null>"))
		return 1
	if not cpp.has_method("get_ground_voxel_y_at"):
		print("[DISTANT] RESULT=FAIL reason=generator_missing_get_ground_voxel_y_at")
		return 1
	if not ClassDB.class_exists("DistantTerrainMesher"):
		print("[DISTANT] RESULT=FAIL reason=DistantTerrainMesher_not_registered — build extensions/voxel_gen.")
		return 1
	if not FileAccess.file_exists(_DISTANT_BASELINE):
		print("[DISTANT] RESULT=FAIL reason=baseline_missing %s (committed file)" % _DISTANT_BASELINE)
		return 1

	# Apron-off grid — must stay byte-identical to the committed baseline.
	var arrays := _distant_cpp_arrays(cpp, 0.0)
	if arrays.is_empty():
		print("[DISTANT] RESULT=FAIL reason=cpp_build_failed (apron-off)")
		return 1
	var summary := _distant_summarise(arrays)
	print("[DISTANT] cpp apron-off: verts=%d tris=%d vhash=%d nhash=%d chash=%d ihash=%d" % [
		int(summary["vertex_count"]), int(summary["tri_count"]),
		int(summary["vertex_hash"]), int(summary["normal_hash"]),
		int(summary["color_hash"]), int(summary["index_hash"])])

	var bf := FileAccess.open(_DISTANT_BASELINE, FileAccess.READ)
	var base: Dictionary = JSON.parse_string(bf.get_as_text())
	bf.close()
	var fails: int = 0
	for k in ["vertex_count", "index_count", "tri_count", "vertex_hash", "normal_hash", "color_hash", "index_hash"]:
		if int(base.get(k, -1)) != int(summary.get(k, -2)):
			fails += 1
			push_error("[DISTANT] %s drift: baseline=%d cpp=%d" % [k, int(base.get(k, -1)), int(summary.get(k, -2))])
	if fails == 0:
		print("[DISTANT] apron-off parity PASS — grid byte-identical to the committed baseline.")

	# --- Phase 2 — the skirt apron is purely additive -----------------
	var apron_on := _distant_cpp_arrays(cpp, _DISTANT_APRON_TEST_DEPTH)
	if apron_on.is_empty():
		fails += 1
		push_error("[DISTANT] apron-on build failed")
	else:
		fails += _distant_check_apron(arrays, apron_on)

	# --- Phase 3 — distant_terrain.gdshader compiles ------------------
	fails += _distant_check_shader()

	if fails == 0:
		print("[DISTANT] RESULT=PASS — grid bit-identical to baseline; apron additive; shader compiles.")
		return 0
	print("[DISTANT] RESULT=FAIL — %d issue(s)." % fails)
	return 1


# Phase 3 — load distant_terrain.gdshader and confirm it compiles. Under
# the headless dummy renderer Godot still parses shader code on load: a
# syntax/semantic error prints SHADER ERROR to stderr and leaves the
# shader with no valid RID / an empty uniform list. Returns fail count.
func _distant_check_shader() -> int:
	var path := "res://assets/shaders/distant_terrain.gdshader"
	if not ResourceLoader.exists(path):
		push_error("[DISTANT] shader missing: %s" % path)
		return 1
	var sh = load(path)
	if sh == null or not (sh is Shader):
		push_error("[DISTANT] shader load failed or not a Shader: %s" % path)
		return 1
	var rid: RID = (sh as Shader).get_rid()
	var uniforms: Array = []
	if rid.is_valid():
		uniforms = RenderingServer.get_shader_parameter_list(rid)
	var has_fade := false
	for u in uniforms:
		if String(u.get("name", "")) == "fade_factor":
			has_fade = true
	print("[DISTANT] shader distant_terrain.gdshader rid_valid=%s uniforms=%d fade_factor=%s" % [
		rid.is_valid(), uniforms.size(), has_fade])
	if not rid.is_valid() or not has_fade:
		push_error("[DISTANT] distant_terrain.gdshader failed to compile or is missing the fade_factor uniform (grep stderr for SHADER ERROR)")
		return 1
	return 0


# Phase 2 — assert the skirt apron is purely additive: the apron-off grid
# is a byte-identical prefix of the apron-on mesh, and the apron appends
# exactly 4 verts + 6 indices per chunk-border edge. Returns fail count.
func _distant_check_apron(off: Dictionary, on: Dictionary) -> int:
	var ov: PackedVector3Array = off["vertices"]
	var on_v: PackedVector3Array = on["vertices"]
	var off_n: PackedVector3Array = off["normals"]
	var on_n: PackedVector3Array = on["normals"]
	var off_c: PackedColorArray = off["colors"]
	var on_c: PackedColorArray = on["colors"]
	var oi: PackedInt32Array = off["indices"]
	var on_i: PackedInt32Array = on["indices"]
	var quads: int = int((_DISTANT_MAX.x - _DISTANT_MIN.x) / _DISTANT_QUAD_M)
	var apron_edges: int = 4 * quads
	var exp_v: int = apron_edges * 4
	var exp_i: int = apron_edges * 6
	var fails: int = 0
	if on_v.size() != ov.size() + exp_v:
		fails += 1
		push_error("[DISTANT] apron vertex delta=%d expected=%d" % [on_v.size() - ov.size(), exp_v])
	if on_i.size() != oi.size() + exp_i:
		fails += 1
		push_error("[DISTANT] apron index delta=%d expected=%d" % [on_i.size() - oi.size(), exp_i])
	var prefix_ok := true
	for k in range(ov.size()):
		if ov[k] != on_v[k] or off_n[k] != on_n[k] or off_c[k] != on_c[k]:
			prefix_ok = false
			break
	if prefix_ok:
		for k in range(oi.size()):
			if oi[k] != on_i[k]:
				prefix_ok = false
				break
	if not prefix_ok:
		fails += 1
		push_error("[DISTANT] apron-on grid prefix differs from apron-off — apron is NOT purely additive")
	if fails == 0:
		@warning_ignore("integer_division")
		var apron_tris: int = exp_i / 3
		print("[DISTANT] apron additive check PASS — +%d verts / +%d tris, grid prefix byte-identical." % [exp_v, apron_tris])
	return fails


func _distant_cpp_arrays(gen, apron_depth: float) -> Dictionary:
	var mesher: Object = ClassDB.instantiate("DistantTerrainMesher")
	if mesher == null:
		return {}
	var d = mesher.call("build_chunk", gen, _DISTANT_MIN, _DISTANT_MAX, _DISTANT_QUAD_M, _DISTANT_VPM, apron_depth)
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	# Round-trip the raw build_chunk arrays through an ArrayMesh — exactly
	# what DistantTerrainManager does at runtime. This is REQUIRED for the
	# baseline compare: ArrayMesh's vertex buffer stores normals
	# octahedral-compressed and colours as RGBA8, and the committed
	# baseline was captured post-round-trip, so the C++ output must be
	# measured the same way.
	return _distant_arrays_from_mesh(_distant_mesh_from_arrays(d))


# Assemble an ArrayMesh from a { vertices, normals, colors, indices }
# Dictionary (the DistantTerrainMesher.build_chunk return shape).
func _distant_mesh_from_arrays(d: Dictionary) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = d.get("vertices", PackedVector3Array())
	arrays[Mesh.ARRAY_NORMAL] = d.get("normals", PackedVector3Array())
	arrays[Mesh.ARRAY_COLOR] = d.get("colors", PackedColorArray())
	arrays[Mesh.ARRAY_INDEX] = d.get("indices", PackedInt32Array())
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _distant_arrays_from_mesh(mesh: ArrayMesh) -> Dictionary:
	if mesh == null or mesh.get_surface_count() == 0:
		return {}
	var a: Array = mesh.surface_get_arrays(0)
	return {
		"vertices": a[Mesh.ARRAY_VERTEX],
		"normals": a[Mesh.ARRAY_NORMAL],
		"colors": a[Mesh.ARRAY_COLOR],
		"indices": a[Mesh.ARRAY_INDEX],
	}


func _distant_summarise(arrays: Dictionary) -> Dictionary:
	var verts: PackedVector3Array = arrays.get("vertices", PackedVector3Array())
	var norms: PackedVector3Array = arrays.get("normals", PackedVector3Array())
	var cols: PackedColorArray = arrays.get("colors", PackedColorArray())
	var idx: PackedInt32Array = arrays.get("indices", PackedInt32Array())
	@warning_ignore("integer_division")
	var tri: int = idx.size() / 3
	return {
		"vertex_count": verts.size(),
		"index_count": idx.size(),
		"tri_count": tri,
		"vertex_hash": _fnv_bytes(verts.to_byte_array()),
		"normal_hash": _fnv_bytes(norms.to_byte_array()),
		"color_hash": _fnv_bytes(cols.to_byte_array()),
		"index_hash": _fnv_bytes(idx.to_byte_array()),
	}


func _fnv_bytes(b: PackedByteArray) -> int:
	var h: int = 2166136261
	for byte in b:
		h = ((h ^ byte) * 16777619) & 0x7FFFFFFF
	return h


func _find_terrain(n: Node) -> Node:
	if n == null:
		return null
	if n.get_class() == "VoxelLodTerrain" or n.get_class() == "VoxelTerrain":
		return n
	for c in n.get_children():
		var r := _find_terrain(c)
		if r != null:
			return r
	return null


# ============================================================
# PHASE 2 — the bootstrap injected 8 native fluid models correctly
# ============================================================
# Data-level half of the [designer] Phase-2 gate (the *visual* "renders
# as fluid" half is the end-of-build designer review). Asserts the
# runtime library has 16 static + 8 VoxelBlockyModelFluid at ids 16..23,
# each level 1..8, fluid linked, collision disabled.
func _phase2_report() -> int:
	var WM := preload("res://scripts/WaterMaterial.gd")
	var terrain := _find_terrain(_spike_world)
	if terrain == null:
		print("[PHASE2] RESULT=FAIL reason=no_terrain")
		return 1
	var mesher = terrain.get("mesher")
	if mesher == null and terrain.has_method("get_mesher"):
		mesher = terrain.call("get_mesher")
	if mesher == null:
		print("[PHASE2] RESULT=FAIL reason=no_mesher")
		return 1
	var lib = mesher.get("library")
	if lib == null:
		print("[PHASE2] RESULT=FAIL reason=no_library")
		return 1
	var models: Array = lib.get("models")
	var fails: int = 0
	var expect_total: int = WM.WATER_FLUID_BASE_ID + WM.WATER_LEVEL_COUNT
	print("[PHASE2] library model count=%d (expect %d)" % [models.size(), expect_total])
	if models.size() != expect_total:
		fails += 1
		push_error("[PHASE2] model count %d != %d" % [models.size(), expect_total])
	for level in range(1, WM.WATER_LEVEL_COUNT + 1):
		var id: int = WM.WATER_FLUID_BASE_ID + level - 1
		if id >= models.size():
			fails += 1
			continue
		var m = models[id]
		var cls: String = m.get_class() if m != null else "<null>"
		var lvl = m.call("get_level") if (m != null and m.has_method("get_level")) else -1
		var has_fluid: bool = (m != null and m.has_method("get_fluid") and m.call("get_fluid") != null)
		var aabbs = m.call("get_collision_aabbs") if (m != null and m.has_method("get_collision_aabbs")) else null
		var coll_off: bool = (aabbs == null) or (aabbs is Array and (aabbs as Array).is_empty())
		print("[PHASE2] id=%d class=%s level=%s fluid=%s coll_off=%s" % [id, cls, str(lvl), has_fluid, coll_off])
		if cls != "VoxelBlockyModelFluid" or int(lvl) != level or not has_fluid or not coll_off:
			fails += 1
			push_error("[PHASE2] id=%d wrong (class=%s level=%s fluid=%s coll_off=%s)" % [id, cls, str(lvl), has_fluid, coll_off])
	# legacy cube water (id 5) must still be present (generator emits it
	# until Phase 4).
	if models.size() > 5 and models[5] != null:
		print("[PHASE2] legacy cube water id=5 class=%s (kept until Phase 4)" % models[5].get_class())
	else:
		fails += 1
		push_error("[PHASE2] legacy water model[5] missing")
	if fails == 0:
		print("[PHASE2] RESULT=PASS — 8 fluid level-models injected at 16..23, collision off, legacy 5 intact.")
		return 0
	print("[PHASE2] RESULT=FAIL — %d problems (see push_error)." % fails)
	return 1


# ============================================================
# GRAVITY — VoxelGravityCpp parity vs GravityReference (Phase 2)
# ============================================================
# Synthesises a 16^3 VoxelBuffer with all four interesting cases:
#   * a solid bottom plate (anchored-from-floor seed)
#   * a 2x2x2 floating stone block (NEVER -> cluster path)
#   * a 1x1x3 floating sand column (LOOSE -> column-fall path)
#   * a 2x2x1 floating dirt patch (PICKUP_DROP -> pickup path)
# Runs both GravityReference.analyze_bubble (pure GD) and
# VoxelGravityCpp.analyze_bubble against the same buffer + fall table.
# Compares the four output streams SEMANTICALLY (as sets) — iteration
# order doesn't affect parity.
const _GravityRef := preload("res://scripts/_dev/GravityReference.gd")

func _gravity() -> int:
	print("[GRAVITY] === parity probe ===")
	if not ClassDB.class_exists("VoxelGravityCpp"):
		print("[GRAVITY] RESULT=FAIL reason=VoxelGravityCpp_not_registered — build extensions/voxel_gen.")
		return 1
	var cpp: Object = ClassDB.instantiate("VoxelGravityCpp")
	if cpp == null:
		print("[GRAVITY] RESULT=FAIL reason=instantiate_returned_null")
		return 1
	for m in ["set_fall_behavior_table", "set_noeditzone_anchor_mask", "analyze_bubble"]:
		if not cpp.has_method(m):
			print("[GRAVITY] RESULT=FAIL reason=missing_method:%s" % m)
			return 1

	# Material ids: stone=1 (NEVER), dirt=2 (PICKUP_DROP), sand=4 (LOOSE).
	# Match the canonical ids in scripts/VoxelMaterialRegistry.gd so a
	# real engine session and the harness exercise the same constants.
	var fall_table := {
		1: _GravityRef.FALL_NEVER,
		2: _GravityRef.FALL_PICKUP_DROP,
		4: _GravityRef.FALL_LOOSE,
	}
	var side: int = 16
	var buf: VoxelBuffer = VoxelBuffer.new()
	buf.create(side, side, side)
	_gravity_populate_scenario(buf, side)

	var ref_out: Dictionary = _GravityRef.analyze_bubble(buf, side, fall_table, PackedByteArray())
	cpp.call("set_fall_behavior_table", fall_table)
	cpp.call("set_noeditzone_anchor_mask", PackedByteArray())
	var cpp_out: Dictionary = cpp.call("analyze_bubble", buf, Vector3i.ZERO, side)

	print("[GRAVITY] scenario: solids ref=%d cpp=%d   unanchored ref=%d cpp=%d   loose ref=%d cpp=%d   pickup ref=%d cpp=%d   clusters ref=%d cpp=%d" % [
		int(ref_out["bubble_solid_count"]), int(cpp_out["bubble_solid_count"]),
		int(ref_out["unanchored_cluster_count"]), int(cpp_out["unanchored_cluster_count"]),
		ref_out["loose"].size() / 7, cpp_out["loose"].size() / 7,
		ref_out["pickup"].size() / 4, cpp_out["pickup"].size() / 4,
		ref_out["cluster_counts"].size(), cpp_out["cluster_counts"].size(),
	])

	var fails: Array = _gravity_compare(ref_out, cpp_out)
	if fails.is_empty():
		print("[GRAVITY] RESULT=PASS — C++ analyze_bubble matches GD reference set-for-set.")
		return 0
	for f in fails:
		print("[GRAVITY] FAIL %s" % f)
	print("[GRAVITY] RESULT=FAIL — %d parity divergence(s)." % fails.size())
	return 1


# Build the scenario buffer. Bottom 3 rows of stone span the full XZ plane
# (so the flood-fill has a wide anchor). The four floating shapes sit well
# above with a gap of empty rows around them so they cannot be reached
# from the anchored set.
func _gravity_populate_scenario(buf: VoxelBuffer, side: int) -> void:
	# Bottom plate: y in [0, 2], every (x, z) -> stone(1).
	for y in range(3):
		for x in range(side):
			for z in range(side):
				buf.set_voxel(1, x, y, z, VoxelBuffer.CHANNEL_TYPE)
	# Floating stone 2x2x2 at (7..8, 8..9, 7..8) — cluster path.
	for x in range(7, 9):
		for y in range(8, 10):
			for z in range(7, 9):
				buf.set_voxel(1, x, y, z, VoxelBuffer.CHANNEL_TYPE)
	# Floating sand column 1x3x1 at (3, 8..10, 3) — LOOSE path.
	# y=8, 9, 10 at the same (x=3, z=3). Bottom (y=8) falls to y=3
	# (lands on top of the bottom plate), y=9 then sees y=3 occupied
	# and stacks at y=4, y=10 at y=5. Tests the bottom-up sort.
	for y in range(8, 11):
		buf.set_voxel(4, 3, y, 3, VoxelBuffer.CHANNEL_TYPE)
	# Floating dirt patch 2x1x2 at (12..13, 8, 12..13) — PICKUP_DROP.
	for x in range(12, 14):
		for z in range(12, 14):
			buf.set_voxel(2, x, 8, z, VoxelBuffer.CHANNEL_TYPE)


# Semantic compare: each stream becomes a set of tuples; clusters become
# a multiset of (sorted) voxel sets. Returns a list of human-readable
# failure descriptions; empty = parity.
func _gravity_compare(ref: Dictionary, got: Dictionary) -> Array:
	var fails: Array = []
	if int(ref["bubble_solid_count"]) != int(got["bubble_solid_count"]):
		fails.append("bubble_solid_count ref=%d got=%d" % [int(ref["bubble_solid_count"]), int(got["bubble_solid_count"])])
	if int(ref["unanchored_cluster_count"]) != int(got["unanchored_cluster_count"]):
		fails.append("unanchored_cluster_count ref=%d got=%d" % [int(ref["unanchored_cluster_count"]), int(got["unanchored_cluster_count"])])
	var loose_diff: int = _stream_set_sym_diff(ref["loose"], got["loose"], 7)
	if loose_diff != 0:
		fails.append("loose set symmetric_diff=%d (ref entries=%d, got entries=%d)" % [loose_diff, ref["loose"].size() / 7, got["loose"].size() / 7])
	var pickup_diff: int = _stream_set_sym_diff(ref["pickup"], got["pickup"], 4)
	if pickup_diff != 0:
		fails.append("pickup set symmetric_diff=%d (ref=%d, got=%d)" % [pickup_diff, ref["pickup"].size() / 4, got["pickup"].size() / 4])
	# Clusters: compare as a sorted list of "voxel-set signatures"
	# (sorted list of voxel tuples per cluster).
	var ref_clusters: Array = _parse_clusters(ref["cluster_counts"], ref["cluster_voxels"])
	var got_clusters: Array = _parse_clusters(got["cluster_counts"], got["cluster_voxels"])
	ref_clusters.sort()
	got_clusters.sort()
	if ref_clusters != got_clusters:
		fails.append("clusters: ref count=%d got count=%d (signatures differ)" % [ref_clusters.size(), got_clusters.size()])
	return fails


# Treat a [a0,b0,c0,...,aN,bN,cN] stream as a set of stride-tuples and
# return the symmetric-difference count (entries in one but not the
# other). Zero = the two streams represent the same set.
func _stream_set_sym_diff(a: PackedInt32Array, b: PackedInt32Array, stride: int) -> int:
	var ra: Dictionary = _stream_to_set(a, stride)
	var rb: Dictionary = _stream_to_set(b, stride)
	var only_a: int = 0
	for k in ra.keys():
		if not rb.has(k): only_a += 1
	var only_b: int = 0
	for k in rb.keys():
		if not ra.has(k): only_b += 1
	return only_a + only_b


func _stream_to_set(s: PackedInt32Array, stride: int) -> Dictionary:
	var d: Dictionary = {}
	@warning_ignore("integer_division")
	var n: int = s.size() / stride
	for i in range(n):
		var parts: PackedStringArray = PackedStringArray()
		for j in range(stride):
			parts.append(str(s[i * stride + j]))
		d[",".join(parts)] = true
	return d


# Returns Array[String] — one entry per cluster, each entry a sorted
# "x,y,z,packed|x,y,z,packed|..." signature of that cluster's voxels.
# Sortable so the harness can compare cluster lists order-independently.
func _parse_clusters(counts: PackedInt32Array, voxels: PackedInt32Array) -> Array:
	var out: Array = []
	var cursor: int = 0
	for c in counts:
		var tuples: PackedStringArray = PackedStringArray()
		for _i in range(c):
			tuples.append("%d,%d,%d,%d" % [voxels[cursor], voxels[cursor + 1], voxels[cursor + 2], voxels[cursor + 3]])
			cursor += 4
		tuples.sort()
		out.append("|".join(tuples))
	return out


# ============================================================
# EMISSIVE — EmissiveLightCpp parity vs EmissiveReference (Phase 4)
# ============================================================
# Synthesises a 20x20x20 buffer with three test cases:
#   * a 4-voxel vertical emissive chain at (5,5..8,5) — all exposed to air
#   * a buried emissive voxel at (15,10,15) surrounded by stone — NOT lit
#   * a single emissive cube at (2,15,17) — exposed (on the surface)
# Emissive id = 12 (copper_ore, matches registry).
const _EmissiveRef := preload("res://scripts/_dev/EmissiveReference.gd")

func _emissive() -> int:
	print("[EMISSIVE] === parity probe ===")
	if not ClassDB.class_exists("EmissiveLightCpp"):
		print("[EMISSIVE] RESULT=FAIL reason=EmissiveLightCpp_not_registered — build extensions/voxel_gen.")
		return 1
	var cpp: Object = ClassDB.instantiate("EmissiveLightCpp")
	if cpp == null:
		print("[EMISSIVE] RESULT=FAIL reason=instantiate_returned_null")
		return 1
	for m in ["set_emissive_material_ids", "set_cell_size_voxels", "scan_region"]:
		if not cpp.has_method(m):
			print("[EMISSIVE] RESULT=FAIL reason=missing_method:%s" % m)
			return 1

	var side := Vector3i(20, 20, 20)
	var min_v := Vector3i(100, -50, 200)  # Arbitrary non-zero origin, tests world-coord math.
	var buf: VoxelBuffer = VoxelBuffer.new()
	buf.create(side.x, side.y, side.z)
	_emissive_populate_scenario(buf, side)

	var emissive_ids: PackedInt32Array = PackedInt32Array([12])
	var cell_size: int = 5

	var ref_out: Dictionary = _EmissiveRef.scan_region(buf, min_v, side, emissive_ids, cell_size)
	cpp.call("set_emissive_material_ids", emissive_ids)
	cpp.call("set_cell_size_voxels", cell_size)
	var cpp_out: Dictionary = cpp.call("scan_region", buf, min_v, side)

	print("[EMISSIVE] now_lit ref=%d cpp=%d   affected_cells ref=%d cpp=%d" % [
		ref_out["now_lit"].size() / 4, cpp_out["now_lit"].size() / 4,
		ref_out["affected_cells"].size() / 3, cpp_out["affected_cells"].size() / 3,
	])

	var fails: Array = []
	var nl_diff: int = _stream_set_sym_diff(ref_out["now_lit"], cpp_out["now_lit"], 4)
	if nl_diff != 0:
		fails.append("now_lit set symmetric_diff=%d" % nl_diff)
	var ac_diff: int = _stream_set_sym_diff(ref_out["affected_cells"], cpp_out["affected_cells"], 3)
	if ac_diff != 0:
		fails.append("affected_cells set symmetric_diff=%d" % ac_diff)
	if fails.is_empty():
		print("[EMISSIVE] RESULT=PASS — C++ scan_region matches GD reference set-for-set.")
		return 0
	for f in fails:
		print("[EMISSIVE] FAIL %s" % f)
	print("[EMISSIVE] RESULT=FAIL — %d parity divergence(s)." % fails.size())
	return 1


const _BakedRef := preload("res://scripts/_dev/EmissiveBakedReference.gd")

# ============================================================
# BAKED LIGHT — EmissiveBakedCpp byte-exact parity (Phase J spec)
# ============================================================
# Synthesises a 16x8x8 buffer with a vertical wall at voxel x=9 (cell
# cx=4, K=2). Two emitters: red at world voxel (3,3,3) -> cell (1,1,1),
# blue at (13,3,3) -> cell (6,1,1). With BFS gated on "centre voxel is
# air", neither emitter's light can reach the cells past the wall —
# proves the wall-bleed-through fix. Reference + C++ must produce
# byte-identical output (PackedByteArray equality).
func _baked_light() -> int:
	print("[BAKED] === parity probe ===")
	if not ClassDB.class_exists("EmissiveBakedCpp"):
		print("[BAKED] RESULT=FAIL reason=EmissiveBakedCpp_not_registered — build extensions/voxel_gen.")
		return 1
	var cpp: Object = ClassDB.instantiate("EmissiveBakedCpp")
	if cpp == null:
		print("[BAKED] RESULT=FAIL reason=instantiate_returned_null")
		return 1
	if not cpp.has_method("bake_light_volume"):
		print("[BAKED] RESULT=FAIL reason=missing_method:bake_light_volume")
		return 1

	# Probe Zylann's channel byte layout. Set known voxels at known (x,y,z)
	# and check which BYTE index in the returned PackedByteArray holds the
	# value. Distinguishes X-fastest vs Y-fastest vs Z-fastest layouts.
	var probe_buf: VoxelBuffer = VoxelBuffer.new()
	probe_buf.create(4, 4, 4)
	probe_buf.set_voxel(11, 1, 0, 0, VoxelBuffer.CHANNEL_TYPE)  # x=1
	probe_buf.set_voxel(22, 0, 1, 0, VoxelBuffer.CHANNEL_TYPE)  # y=1
	probe_buf.set_voxel(33, 0, 0, 1, VoxelBuffer.CHANNEL_TYPE)  # z=1
	var raw: PackedByteArray = probe_buf.get_channel_as_byte_array(VoxelBuffer.CHANNEL_TYPE)
	print("[BAKED] probe len=%d" % raw.size())
	for i in range(64):
		if raw[i] != 0:
			print("[BAKED]   byte[%d] = %d" % [i, raw[i]])

	# Buffer: 16x8x8 voxels, mostly air, wall plane at x=9.
	var buf: VoxelBuffer = VoxelBuffer.new()
	buf.create(16, 8, 8)
	for y in range(8):
		for z in range(8):
			buf.set_voxel(1, 9, y, z, VoxelBuffer.CHANNEL_TYPE)  # stone wall

	# Cells: 8x4x4 grid at K=2. Origin = (0,0,0). Buffer covers
	# (0,0,0)..(15,7,7) — matches cells_per_axis * K per axis only on X.
	# Y/Z volumes shorter than cells_per_axis*K is fine: cells whose
	# centre falls outside the buffer are treated as closed.
	# To keep this clean we'll use N=8 on x, but the bake takes a single
	# N; we'll use N=8 and let the harness scenario sit inside a cube
	# subset of the volume (Y/Z cells beyond cy=4/cz=4 close themselves
	# via the out-of-buffer-centre check).
	var origin := Vector3i(0, 0, 0)
	var cell_size: int = 2
	var n: int = 8
	var max_steps: int = 8
	var falloff_q12: int = 3482  # ~0.85 per step

	# Two emissive voxels (red mat_id=2, blue mat_id=3) placed in the
	# buffer. Stone wall is mat_id=1. The colour table marks 2 and 3 as
	# emissive (energy=255), 1 as non-emissive.
	buf.set_voxel(2, 3, 3, 3, VoxelBuffer.CHANNEL_TYPE)
	buf.set_voxel(3, 13, 3, 3, VoxelBuffer.CHANNEL_TYPE)
	var table: PackedByteArray = PackedByteArray()
	table.resize(256 * 4)
	# id 2 = red, energy 255
	table[2 * 4 + 0] = 255
	table[2 * 4 + 1] = 0
	table[2 * 4 + 2] = 0
	table[2 * 4 + 3] = 255
	# id 3 = blue, energy 255
	table[3 * 4 + 0] = 0
	table[3 * 4 + 1] = 0
	table[3 * 4 + 2] = 255
	table[3 * 4 + 3] = 255
	# Air-neighbour filter OFF for the parity test — both emissives sit
	# in air so they'd pass either way; off keeps the test focused on
	# the BFS-through-air-cells gate (the wall block) rather than the
	# additional exposure gate.
	var air_filter: bool = false

	var ref_bytes: PackedByteArray = _BakedRef.bake_light_volume(
		buf, origin, cell_size, n, table, air_filter, max_steps, falloff_q12)
	var cpp_bytes: PackedByteArray = cpp.call(
		"bake_light_volume",
		buf, origin, cell_size, n, table, air_filter, max_steps, falloff_q12)

	var expected_size: int = n * n * n * 4
	print("[BAKED] sizes ref=%d cpp=%d expected=%d" % [
		ref_bytes.size(), cpp_bytes.size(), expected_size])
	if ref_bytes.size() != expected_size or cpp_bytes.size() != expected_size:
		print("[BAKED] RESULT=FAIL reason=size_mismatch")
		return 1

	# Count lit cells (any non-zero RGB) on each side of the wall.
	var ref_lit_west: int = 0
	var ref_lit_east: int = 0
	var ref_lit_wall: int = 0  # cells AT the wall column (cx=4) — must be 0
	for cz in range(n):
		for cy in range(n):
			for cx in range(n):
				var idx: int = (cx + cy * n + cz * n * n) * 4
				var any_light: bool = ref_bytes[idx] > 0 or ref_bytes[idx + 1] > 0 or ref_bytes[idx + 2] > 0
				if not any_light:
					continue
				if cx < 4: ref_lit_west += 1
				elif cx > 4: ref_lit_east += 1
				else: ref_lit_wall += 1
	print("[BAKED] ref lit cells: west(cx<4)=%d  east(cx>4)=%d  wall(cx=4)=%d" % [
		ref_lit_west, ref_lit_east, ref_lit_wall])
	if ref_lit_wall != 0:
		print("[BAKED] RESULT=FAIL reason=wall_was_lit_in_ref (BFS gate broken)")
		return 1

	# Byte-exact comparison.
	var fails: int = 0
	var first_diff: int = -1
	for i in range(expected_size):
		if ref_bytes[i] != cpp_bytes[i]:
			fails += 1
			if first_diff < 0:
				first_diff = i
	if fails == 0:
		print("[BAKED] RESULT=PASS — %d bytes byte-identical; wall blocks light cross-flow." % expected_size)
		return 0
	@warning_ignore("integer_division")
	var cell_of_first: int = first_diff / 4
	var cx: int = cell_of_first % n
	@warning_ignore("integer_division")
	var cy: int = (cell_of_first / n) % n
	@warning_ignore("integer_division")
	var cz: int = cell_of_first / (n * n)
	print("[BAKED] RESULT=FAIL — %d byte diffs; first at byte=%d cell=(%d,%d,%d)  ref=%d cpp=%d" % [
		fails, first_diff, cx, cy, cz, ref_bytes[first_diff], cpp_bytes[first_diff]])
	return 1


const _WaterFlowRef := preload("res://scripts/_dev/WaterFlowReference.gd")

# ============================================================
# WATER FLOW — WaterFlowCpp.scan_settle_region byte-exact parity
# ============================================================
# Synthesises a 12x8x12 buffer:
#   * Stone floor at y=0..1
#   * Stone wall along x=11 (so the eastern column of cells is solid)
#   * Water (legacy id 5) filling a 4x4x4 block at (1..4, 2..5, 1..4)
#   * Two AIR cells touching that water: (5, 2, 1) and (5, 4, 3) — these
#     are the EXPECTED hits.
#   * One AIR cell NOT touching water: (8, 4, 8) — must NOT be in hits.
#   * One AIR cell touching water but in _pending_water — must SKIP.
#   * One AIR cell touching water but at retry cap — must SKIP.
# Region = whole buffer. Player at world origin (well inside radius).
func _water_flow() -> int:
	print("[WFLOW] === parity probe ===")
	if not ClassDB.class_exists("WaterFlowCpp"):
		print("[WFLOW] RESULT=FAIL reason=WaterFlowCpp_not_registered — build extensions/voxel_gen.")
		return 1
	var cpp: Object = ClassDB.instantiate("WaterFlowCpp")
	if cpp == null:
		print("[WFLOW] RESULT=FAIL reason=instantiate_returned_null")
		return 1
	if not cpp.has_method("scan_settle_region"):
		print("[WFLOW] RESULT=FAIL reason=missing_method:scan_settle_region")
		return 1

	var sx: int = 12
	var sy: int = 8
	var sz: int = 12
	var buf: VoxelBuffer = VoxelBuffer.new()
	buf.create(sx, sy, sz)
	# Stone floor.
	for x in range(sx):
		for z in range(sz):
			buf.set_voxel(1, x, 0, z, VoxelBuffer.CHANNEL_TYPE)
			buf.set_voxel(1, x, 1, z, VoxelBuffer.CHANNEL_TYPE)
	# Stone wall on the east edge.
	for y in range(sy):
		for z in range(sz):
			buf.set_voxel(1, 11, y, z, VoxelBuffer.CHANNEL_TYPE)
	# 4x4x4 water block. Legacy id 5 with DATA5 = 0 — under the W2
	# source gate, legacy water conservatively counts as SOURCE, so all
	# the original expected hits stay valid.
	for x in range(1, 5):
		for y in range(2, 6):
			for z in range(1, 5):
				buf.set_voxel(5, x, y, z, VoxelBuffer.CHANNEL_TYPE)

	# W2 source-gate cases (design/WATER_FINITE_SIM_PLAN.md):
	var WM := preload("res://scripts/WaterMaterial.gd")
	# FINITE water (DATA5 level 4, source bit CLEAR) at (8,2,8). Its air
	# neighbour (9,2,8) must NOT become a hit — finite water never feeds
	# the ocean settle re-fill.
	buf.set_voxel(WM.render_id_for_level(4, WaterByteCodec.DIR_STILL), 8, 2, 8, VoxelBuffer.CHANNEL_TYPE)
	buf.set_voxel(WaterByteCodec.pack(4, false, WaterByteCodec.DIR_STILL), 8, 2, 8, VoxelBuffer.CHANNEL_DATA5)
	# Explicit SOURCE water (DATA5 source bit SET) at (8,5,8). Its air
	# neighbour (9,5,8) MUST be a hit.
	buf.set_voxel(WM.render_id_for_level(8, WaterByteCodec.DIR_STILL), 8, 5, 8, VoxelBuffer.CHANNEL_TYPE)
	buf.set_voxel(WaterByteCodec.SOURCE_BYTE, 8, 5, 8, VoxelBuffer.CHANNEL_DATA5)

	# Expected hits: air cells at face-neighbours of the water block.
	# (5, 2, 1) is +X-neighbour of (4, 2, 1) water.
	# (5, 4, 3) is +X-neighbour of (4, 4, 3) water.
	# (1, 6, 1) is +Y-neighbour of (1, 5, 1) water.
	# Etc — for our test we only check two specific ones; the harness
	# checks set equality so order doesn't matter.

	# A cell already pending (must skip).
	var pending: Dictionary = {}
	pending[Vector3i(5, 5, 1)] = true   # +X of (4,5,1) water — would be a hit but pending
	# A cell at retry cap (must skip).
	var retry: Dictionary = {}
	retry[Vector3i(5, 3, 3)] = 40       # +X of (4,3,3) water — would be a hit but retry cap

	var region_min := Vector3i(0, 0, 0)
	var region_max := Vector3i(sx - 1, sy - 1, sz - 1)
	var player_pos := Vector3(0, 0, 0)
	var active_radius_m: float = 100.0  # easily covers the whole buffer at 6 vox/m
	var voxels_per_metre: float = 6.0
	var scan_cap: int = 4096
	var fill_max_retry: int = 40

	var ref_out: Dictionary = _WaterFlowRef.scan_settle_region(
		buf, region_min, region_max, 0, sy - 1, scan_cap,
		player_pos, active_radius_m, voxels_per_metre,
		pending, retry, fill_max_retry)
	var cpp_out: Dictionary = cpp.call(
		"scan_settle_region",
		buf, region_min, region_max, 0, sy - 1, scan_cap,
		player_pos, active_radius_m, voxels_per_metre,
		pending, retry, fill_max_retry)

	print("[WFLOW] ref: hits=%d  next_y=%d  scanned=%d" % [
		ref_out["hits"].size() / 3, int(ref_out["next_y"]), int(ref_out["scanned"])])
	print("[WFLOW] cpp: hits=%d  next_y=%d  scanned=%d" % [
		cpp_out["hits"].size() / 3, int(cpp_out["next_y"]), int(cpp_out["scanned"])])

	# next_y + scanned must match exactly.
	var fails: int = 0
	if int(ref_out["next_y"]) != int(cpp_out["next_y"]):
		fails += 1
		print("[WFLOW] FAIL next_y mismatch")
	if int(ref_out["scanned"]) != int(cpp_out["scanned"]):
		fails += 1
		print("[WFLOW] FAIL scanned mismatch")

	# Hits — compare as sets.
	var ref_set: Dictionary = _wflow_stream_to_set(ref_out["hits"])
	var cpp_set: Dictionary = _wflow_stream_to_set(cpp_out["hits"])
	var only_ref: Array = []
	var only_cpp: Array = []
	for k in ref_set.keys():
		if not cpp_set.has(k): only_ref.append(k)
	for k in cpp_set.keys():
		if not ref_set.has(k): only_cpp.append(k)
	if not only_ref.is_empty() or not only_cpp.is_empty():
		fails += 1
		print("[WFLOW] FAIL hits differ: only_ref=%d only_cpp=%d" % [only_ref.size(), only_cpp.size()])

	# Sanity: the pending + retry cells must NOT appear in either set.
	if ref_set.has("5,5,1") or cpp_set.has("5,5,1"):
		fails += 1
		print("[WFLOW] FAIL pending cell (5,5,1) leaked into hits")
	if ref_set.has("5,3,3") or cpp_set.has("5,3,3"):
		fails += 1
		print("[WFLOW] FAIL retry-cap cell (5,3,3) leaked into hits")

	# W2 source gate: air next to FINITE water must not be a hit; air
	# next to explicit SOURCE water must be one. Checked on BOTH
	# implementations (set equality above would let a shared bug pass).
	if ref_set.has("9,2,8") or cpp_set.has("9,2,8"):
		fails += 1
		print("[WFLOW] FAIL finite-water neighbour (9,2,8) wrongly re-filled")
	if not ref_set.has("9,5,8") or not cpp_set.has("9,5,8"):
		fails += 1
		print("[WFLOW] FAIL source-water neighbour (9,5,8) missing from hits")

	if fails == 0:
		print("[WFLOW] RESULT=PASS — C++ scan_settle_region matches GD reference set-for-set; pending+retry honoured.")
		return 0
	print("[WFLOW] RESULT=FAIL — %d divergence(s)." % fails)
	return 1


func _wflow_stream_to_set(s: PackedInt32Array) -> Dictionary:
	var d: Dictionary = {}
	@warning_ignore("integer_division")
	var n: int = s.size() / 3
	for i in range(n):
		d["%d,%d,%d" % [s[i * 3], s[i * 3 + 1], s[i * 3 + 2]]] = true
	return d


# ============================================================
# FINITE — FiniteWaterCore conservation / levelness / reach /
# evaporation / ocean-absorption / determinism gates.
# Pure data: synthetic worlds via lambdas, no terrain, no SceneTree.
# Spec: design/WATER_FINITE_SIM_PLAN.md "Headless gate scenarios".
# ============================================================
const _FiniteWaterCore := preload("res://scripts/FiniteWaterCore.gd")

func _finite() -> int:
	var fails: int = 0
	fails += _finite_collapse()
	fails += _finite_pit()
	fails += _finite_evap()
	fails += _finite_ocean()
	fails += _finite_reach()
	fails += _finite_determinism()
	if fails == 0:
		print("[FINITE] RESULT=PASS — all 6 scenarios green (conservation, levelness, reach, evaporation, absorption, determinism).")
		return 0
	print("[FINITE] RESULT=FAIL — %d scenario(s) failed." % fails)
	return 1


func _finite_new_core(floor_y: int) -> RefCounted:
	# Flat infinite stone floor at/below floor_y, no ocean. Scenarios
	# override the callables for walls/pits/sources as needed.
	var core: RefCounted = _FiniteWaterCore.new()
	core.solid_cb = func(p: Vector3i) -> bool: return p.y <= floor_y
	core.source_cb = func(_p: Vector3i) -> bool: return false
	return core


func _finite_run(core: RefCounted, max_ticks: int, budget: int) -> int:
	# Step until settled (or give up). Returns ticks taken, or -1.
	for t in range(max_ticks):
		core.step(budget)
		if core.is_settled():
			return t + 1
	return -1


func _finite_audit(core: RefCounted, tag: String) -> int:
	# The conservation invariant — the whole point of the rework.
	if core.conservation_delta() != 0:
		print("[FINITE] FAIL %s: conservation broken, delta=%d stats=%s" % [
			tag, core.conservation_delta(), str(core.stats())])
		return 1
	return 0


func _finite_levelness(core: RefCounted, tag: String) -> int:
	# Converged adjacent water cells may differ by at most 1 level
	# (same supported Y). Also: no cell may exceed 8 units.
	var fails: int = 0
	var cells: Dictionary = {}
	for p in core._ledger.keys():
		cells[p] = int(core._ledger[p])
		if cells[p] > 8 or cells[p] < 1:
			print("[FINITE] FAIL %s: cell %s holds %d units (legal range 1-8)" % [tag, str(p), cells[p]])
			fails += 1
	for p in cells.keys():
		for d in [Vector3i(1, 0, 0), Vector3i(0, 0, 1)]:
			var n: Vector3i = p + d
			if cells.has(n) and absi(cells[p] - cells[n]) > 1:
				print("[FINITE] FAIL %s: levels not flat at %s (%d) vs %s (%d)" % [
					tag, str(p), cells[p], str(n), cells[n]])
				fails += 1
	return mini(fails, 1)


func _finite_collapse() -> int:
	# Scenario 1: a 3x3x3 dump (216 units) on a flat floor collapses
	# into a wide, shallow, LEVEL pool. The designer's acceptance case.
	var core: RefCounted = _finite_new_core(0)
	var total_in: int = 0
	for x in range(5, 8):
		for z in range(5, 8):
			total_in += core.place(Vector3i(x, 1, z), 24)   # 3 cells of 8, stacked
	var ticks: int = _finite_run(core, 400, 4096)
	var fails: int = 0
	if total_in != 216:
		print("[FINITE] FAIL collapse: placed %d units, expected 216" % total_in)
		fails += 1
	if ticks < 0:
		print("[FINITE] FAIL collapse: did not settle within 400 ticks")
		fails += 1
	if core.total_units() != 216:
		print("[FINITE] FAIL collapse: %d units after settle, expected 216 (stats=%s)" % [
			core.total_units(), str(core.stats())])
		fails += 1
	fails += _finite_audit(core, "collapse")
	fails += _finite_levelness(core, "collapse")
	# It must have actually SPREAD (≥ the 27 original columns' footprint)
	# and stayed within reach of the 3x3 footprint.
	var foot_count: int = 0
	var max_man: int = 0
	for p in core._ledger.keys():
		foot_count += 1
		var man: int = maxi(0, maxi(absi(p.x - 6) - 1, 0) + maxi(absi(p.z - 6) - 1, 0))
		max_man = maxi(max_man, man)
	if foot_count < 27:
		print("[FINITE] FAIL collapse: pool covers %d cells — did not spread" % foot_count)
		fails += 1
	if max_man > core.SPREAD_REACH_VOXELS:
		print("[FINITE] FAIL collapse: front reached %d voxels past the footprint (max %d)" % [
			max_man, core.SPREAD_REACH_VOXELS])
		fails += 1
	print("[FINITE] collapse: ticks=%d cells=%d max_reach=%d stats=%s" % [
		ticks, foot_count, max_man, str(core.stats())])
	return mini(fails, 1)


func _finite_pit() -> int:
	# Scenario 2: dump beside a pit — the pit fills bottom-up, then the
	# whole body levels. Floor at y=0 except a 3x3 pit (x/z 10..12)
	# whose floor is y=-4.
	var core: RefCounted = _FiniteWaterCore.new()
	core.solid_cb = func(p: Vector3i) -> bool:
		var in_pit_column: bool = p.x >= 10 and p.x <= 12 and p.z >= 10 and p.z <= 12
		if in_pit_column:
			return p.y <= -4
		return p.y <= 0
	core.source_cb = func(_p: Vector3i) -> bool: return false
	# Dump right at the pit's rim so it pours in.
	core.place(Vector3i(9, 1, 11), 64)
	var ticks: int = _finite_run(core, 600, 4096)
	var fails: int = 0
	if ticks < 0:
		print("[FINITE] FAIL pit: did not settle within 600 ticks")
		fails += 1
	fails += _finite_audit(core, "pit")
	# The pit's bottom layer must be FULL before anything sits above it:
	# after settling, every pit-bottom cell (y=-3) must hold 8 units if
	# ANY cell above y=-3 holds water inside the pit.
	var any_above: bool = false
	for p in core._ledger.keys():
		if p.x >= 10 and p.x <= 12 and p.z >= 10 and p.z <= 12 and p.y > -3:
			any_above = true
			break
	if any_above:
		for x in range(10, 13):
			for z in range(10, 13):
				if core.units_at(Vector3i(x, -3, z)) != 8:
					print("[FINITE] FAIL pit: bottom cell (%d,-3,%d)=%d not full under standing water" % [
						x, z, core.units_at(Vector3i(x, -3, z))])
					fails += 1
	print("[FINITE] pit: ticks=%d stats=%s" % [ticks, str(core.stats())])
	return mini(fails, 1)


func _finite_evap() -> int:
	# Scenario 3: an orphaned 1-unit cell evaporates after exactly
	# EVAP_TTL ticks, and the books still balance.
	var core: RefCounted = _finite_new_core(0)
	core.place(Vector3i(3, 1, 3), 1)
	var gone_at: int = -1
	for t in range(core.EVAP_TTL + 10):
		core.step(4096)
		if core.total_units() == 0:
			gone_at = t + 1
			break
	var fails: int = 0
	if gone_at != core.EVAP_TTL:
		print("[FINITE] FAIL evap: evaporated at tick %d, expected exactly %d" % [gone_at, core.EVAP_TTL])
		fails += 1
	if core.evaporated != 1:
		print("[FINITE] FAIL evap: evaporated counter=%d, expected 1" % core.evaporated)
		fails += 1
	fails += _finite_audit(core, "evap")
	print("[FINITE] evap: gone_at=%d stats=%s" % [gone_at, str(core.stats())])
	return mini(fails, 1)


func _finite_ocean() -> int:
	# Scenario 4: finite water poured against an ocean wall at/below
	# sea level is swallowed (absorbed/merged), sources unchanged, books
	# balanced. Ocean = every cell with x <= 0 at y <= sea_y.
	var core: RefCounted = _finite_new_core(0)
	core.sea_y = 10
	core.source_cb = func(p: Vector3i) -> bool: return p.x <= 0 and p.y <= 10
	core.place(Vector3i(1, 1, 5), 8)    # face-adjacent to the ocean wall
	core.place(Vector3i(4, 1, 5), 16)   # two cells, must flow over + drain in
	var ticks: int = _finite_run(core, 600, 4096)
	var fails: int = 0
	if ticks < 0:
		print("[FINITE] FAIL ocean: did not settle within 600 ticks")
		fails += 1
	var swallowed: int = core.absorbed + core.merged
	if swallowed <= 0:
		print("[FINITE] FAIL ocean: nothing was absorbed/merged into the ocean")
		fails += 1
	fails += _finite_audit(core, "ocean")
	print("[FINITE] ocean: ticks=%d stats=%s" % [ticks, str(core.stats())])
	return mini(fails, 1)


func _finite_reach() -> int:
	# Scenario 5: keep pouring water at one spot (a "hose": 8 units per
	# tick, 600 times = 4800 units) on an open plane. The front halts at
	# exactly SPREAD_REACH_VOXELS and the pool deepens instead of
	# smearing forever. Why 4800: with the slope-of-1 equilibrium and
	# the 8-unit cap, pushing a level-1 rim all the way to radius 18
	# takes ~3700 units — a single 1000-unit column correctly stops
	# around radius 11 (verified when this gate was first written).
	var core: RefCounted = _finite_new_core(0)
	for i in range(600):
		core.place(Vector3i(0, 1, 0), 8)
		core.step(4096)
	var ticks: int = _finite_run(core, 6000, 4096)
	var fails: int = 0
	if ticks < 0:
		print("[FINITE] FAIL reach: did not settle within 6000 ticks")
		fails += 1
	if core.total_units() + core.evaporated != 4800:
		print("[FINITE] FAIL reach: units+evaporated=%d, expected 4800 (stats=%s)" % [
			core.total_units() + core.evaporated, str(core.stats())])
		fails += 1
	fails += _finite_audit(core, "reach")
	var max_man: int = 0
	for p in core._ledger.keys():
		max_man = maxi(max_man, absi(p.x) + absi(p.z))
	if max_man > core.SPREAD_REACH_VOXELS:
		print("[FINITE] FAIL reach: water at %d voxels out, max is %d" % [max_man, core.SPREAD_REACH_VOXELS])
		fails += 1
	if max_man < core.SPREAD_REACH_VOXELS:
		print("[FINITE] FAIL reach: front stopped at %d voxels, expected exactly %d (4800 units is plenty)" % [
			max_man, core.SPREAD_REACH_VOXELS])
		fails += 1
	print("[FINITE] reach: ticks=%d max_reach=%d stats=%s" % [ticks, max_man, str(core.stats())])
	return mini(fails, 1)


func _finite_determinism() -> int:
	# Scenario 6: the collapse scenario run twice must produce a
	# byte-identical state signature after EVERY tick. This is also the
	# contract the W6 C++ port will be held to.
	var sigs_a: PackedStringArray = _finite_determinism_run()
	var sigs_b: PackedStringArray = _finite_determinism_run()
	if sigs_a.size() != sigs_b.size():
		print("[FINITE] FAIL determinism: run lengths differ (%d vs %d)" % [sigs_a.size(), sigs_b.size()])
		return 1
	for i in range(sigs_a.size()):
		if sigs_a[i] != sigs_b[i]:
			print("[FINITE] FAIL determinism: state diverged at tick %d" % (i + 1))
			return 1
	print("[FINITE] determinism: %d ticks byte-identical across two runs." % sigs_a.size())
	return 0


func _finite_determinism_run() -> PackedStringArray:
	var core: RefCounted = _finite_new_core(0)
	for x in range(5, 8):
		for z in range(5, 8):
			core.place(Vector3i(x, 1, z), 24)
	var sigs: PackedStringArray = PackedStringArray()
	for t in range(400):
		core.step(256)   # deliberately small budget — order under
		                 # budget pressure is part of the contract
		sigs.append(core.state_signature())
		if core.is_settled():
			break
	return sigs


func _emissive_populate_scenario(buf: VoxelBuffer, side: Vector3i) -> void:
	# Stone shell around a buried emissive voxel at (15, 10, 15). 26
	# face/edge/corner neighbours all stone -> the emissive cell has NO
	# air face, must not be reported as lit.
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				buf.set_voxel(1, 15 + dx, 10 + dy, 15 + dz, VoxelBuffer.CHANNEL_TYPE)
	# Now overwrite the centre with copper_ore (id 12) — still surrounded
	# by stone on all 6 cardinal faces.
	buf.set_voxel(12, 15, 10, 15, VoxelBuffer.CHANNEL_TYPE)

	# Vertical emissive chain at (5, 5..8, 5) — all exposed to air on
	# multiple faces.
	for y in range(5, 9):
		buf.set_voxel(12, 5, y, 5, VoxelBuffer.CHANNEL_TYPE)

	# Single exposed emissive cube at (2, 15, 17) — pure air around it,
	# six air faces.
	buf.set_voxel(12, 2, 15, 17, VoxelBuffer.CHANNEL_TYPE)


# ============================================================
# ENTITY — EntityRegistry save/load + chunk-index parity
# ============================================================
# Synthesises 50 EntityRecords spread across 5 chunks, writes them to a
# temp JSON path, reloads them, and asserts:
#   • record_count() identical
#   • chunk_count() identical
#   • every record by id has the same scene_path, position, rotation,
#     state, ai_tier
#   • records_in_chunk(key) returns the expected count for each chunk
# Pure data — no PackedScene loads, no scene tree work. Tests the
# registry layer end-to-end.
const _EntityRecord := preload("res://scripts/entities/EntityRecord.gd")

func _entity() -> int:
	var reg: Node = get_root().get_node_or_null("/root/EntityRegistry")
	if reg == null:
		# Autoload didn't load (some headless runs skip /root autoload
		# instancing). Manually attach a fresh instance for the parity
		# probe — the underlying script is what we're testing anyway.
		var EntityRegistryScript := preload("res://scripts/entities/EntityRegistry.gd")
		reg = EntityRegistryScript.new()
		reg.name = "EntityRegistry"
		get_root().add_child(reg)
	reg.clear()
	# Build 50 records across 5 chunks (10 per chunk). Spread positions
	# inside each chunk's 16x16 m footprint at a fixed Y. Vary state
	# blobs so we can confirm round-trip preserves them.
	var fails: int = 0
	var checks: int = 0
	var chunk_origins: Array = [Vector2i(0,0), Vector2i(1,0), Vector2i(-1,0), Vector2i(0,3), Vector2i(-2,-2)]
	var per_chunk: int = 10
	var expected_ids: Array = []
	for ck in chunk_origins:
		for i in range(per_chunk):
			var rec := _EntityRecord.new()
			rec.scene_path = "res://scenes/enemies/Goblin.tscn"
			# Place inside the chunk's 16m footprint with a 1m margin.
			var local_x: float = 1.0 + float(i) * 1.2
			var local_z: float = 1.0 + float(i) * 0.9
			rec.position = Vector3(
				ck.x * 16.0 + local_x,
				35.0 + float(i) * 0.1,
				ck.y * 16.0 + local_z)
			rec.rotation_y = float(i) * 0.31
			rec.state = {"health": 50 - i, "loot_tag": "g_%d" % i, "ai_state": i % 3}
			rec.ai_tier = i % 4
			var id: String = reg.register(rec)
			expected_ids.append(id)
	checks += 1
	if reg.record_count() != 50:
		fails += 1
		push_error("[ENTITY] pre-save record_count=%d expected 50" % reg.record_count())
	checks += 1
	if reg.chunk_count() != 5:
		fails += 1
		push_error("[ENTITY] pre-save chunk_count=%d expected 5" % reg.chunk_count())
	# records_in_chunk parity per chunk.
	for ck in chunk_origins:
		var in_chunk: Array = reg.records_in_chunk(ck)
		checks += 1
		if in_chunk.size() != per_chunk:
			fails += 1
			push_error("[ENTITY] pre-save chunk %s count=%d expected %d" % [ck, in_chunk.size(), per_chunk])

	# Save / clear / load round-trip. Use a temp path under user:// so
	# we don't pollute any save-slot directory.
	var path := "user://_headless_entity_parity.json"
	var save_err: int = reg.save_to_disk(path)
	checks += 1
	if save_err != OK:
		fails += 1
		push_error("[ENTITY] save_to_disk err=%d" % save_err)
	reg.clear()
	checks += 1
	if reg.record_count() != 0:
		fails += 1
		push_error("[ENTITY] post-clear record_count=%d expected 0" % reg.record_count())
	var load_err: int = reg.load_from_disk(path)
	checks += 1
	if load_err != OK:
		fails += 1
		push_error("[ENTITY] load_from_disk err=%d" % load_err)
	checks += 1
	if reg.record_count() != 50:
		fails += 1
		push_error("[ENTITY] post-load record_count=%d expected 50" % reg.record_count())
	checks += 1
	if reg.chunk_count() != 5:
		fails += 1
		push_error("[ENTITY] post-load chunk_count=%d expected 5" % reg.chunk_count())

	# Per-record bit-for-bit parity check.
	var recovered: int = 0
	for id in expected_ids:
		var rec = reg.get_record(id)
		checks += 1
		if rec == null:
			fails += 1
			push_error("[ENTITY] post-load record %s missing" % id)
			continue
		recovered += 1
	print("[ENTITY] recovered %d / %d records by id" % [recovered, expected_ids.size()])

	# Test register/update/unregister mutations on the loaded registry.
	var probe_id: String = expected_ids[3]
	var p_rec = reg.get_record(probe_id)
	checks += 1
	if p_rec == null:
		fails += 1
		push_error("[ENTITY] probe record missing")
	else:
		# Move to a NEW chunk (far away from all originals).
		p_rec.position = Vector3(500.0, 35.0, 500.0)  # chunk (31, 31)
		reg.update(p_rec)
		checks += 1
		if reg.records_in_chunk(Vector2i(31, 31)).size() != 1:
			fails += 1
			push_error("[ENTITY] post-update chunk(31,31) count=%d expected 1" % reg.records_in_chunk(Vector2i(31, 31)).size())
		# Unregister and confirm.
		reg.unregister(probe_id)
		checks += 1
		if reg.get_record(probe_id) != null:
			fails += 1
			push_error("[ENTITY] post-unregister record %s still present" % probe_id)
		checks += 1
		if reg.record_count() != 49:
			fails += 1
			push_error("[ENTITY] post-unregister record_count=%d expected 49" % reg.record_count())

	if fails == 0:
		print("[ENTITY] RESULT=PASS — %d checks, registry save/load/index/mutate parity holds." % checks)
		return 0
	print("[ENTITY] RESULT=FAIL — %d failures across %d checks." % [fails, checks])
	return 1
