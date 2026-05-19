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

# spike state
var _spike_active: bool = false
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
		"spike":
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
		quit(_spike_report())
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
