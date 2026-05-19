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
		"spike", "phase2":
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
		quit(_phase2_report() if _spike_mode == "phase2" else _spike_report())
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
		if WM.map_legacy_id(id) != id:
			fails += 1
			push_error("[WMatParity] map_legacy_id(%d) not identity" % id)
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
