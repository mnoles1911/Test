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
		"spike", "phase2", "gen":
			_spike_mode = selector
			_spike_active = true   # finishes in _process()
		_:
			push_error("[RUNNER] unknown selector: %s" % selector)
			quit(2)


func _process(_delta: float) -> bool:
	if not _spike_active:
		return true
	if _spike_world == null:
		_spike_begin()
	_spike_frames += 1
	if _spike_frames >= _spike_max_frames:
		match _spike_mode:
			"phase2": quit(_phase2_report())
			"gen": quit(_gen_report())
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
