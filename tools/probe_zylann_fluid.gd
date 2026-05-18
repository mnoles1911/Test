@tool
extends EditorScript
# tools/probe_zylann_fluid.gd
#
# Stage 6 native-fluid pivot — GATE 0.
#
# Verifies our installed Zylann Voxel Tools build exposes the native
# Minecraft-style fluid classes, and dumps their REAL API (property +
# method lists) so we don't guess. Run via Script Editor -> File -> Run
# (Ctrl+Shift+X) and paste the entire Output panel back.
#
# If VoxelBlockyModelFluid / VoxelBlockyFluid are "(class not
# registered)", the native-fluid pivot is blocked on a Voxel Tools
# upgrade — report that and STOP before any integration work.

func _run() -> void:
	for cls_name in ["VoxelBlockyFluid", "VoxelBlockyModelFluid", "VoxelBlockyLibrary", "VoxelBlockyModelCube"]:
		print("=== %s ===" % cls_name)
		if not ClassDB.class_exists(cls_name):
			print("  (class NOT registered — Voxel Tools build lacks it)")
			print("")
			continue
		print("  (registered)")
		var inst: Object = ClassDB.instantiate(cls_name)
		if inst == null:
			print("  (registered but could not instantiate)")
			print("")
			continue
		print("  -- properties --")
		for p in inst.get_property_list():
			var n: String = p.get("name", "")
			if n == "" or n.begins_with("script") or n.begins_with("resource_"):
				continue
			var usage: int = int(p.get("usage", 0))
			if usage & PROPERTY_USAGE_CATEGORY or usage & PROPERTY_USAGE_GROUP:
				continue
			print("  %s : %s" % [n, type_string(int(p.get("type", 0)))])
		print("  -- methods --")
		for m in inst.get_method_list():
			var mn: String = m.get("name", "")
			if mn.begins_with("_") or mn in ["set", "get", "set_script", "get_script"]:
				continue
			print("  %s()" % mn)
		print("")
