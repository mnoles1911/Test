@tool
extends EditorScript
# tools/probe_zylann_blocky.gd
#
# One-shot diagnostic. Prints the full property list of:
#   - VoxelBlockyLibrary
#   - VoxelBlockyModelCube
#   - VoxelMesherBlocky
#
# Run via Script Editor -> File -> Run (Ctrl+Shift+X) and paste the
# Output panel back to Claude. We use the property names this prints
# to fix tools/build_blocky_library.gd.

func _run() -> void:
	for cls_name in ["VoxelBlockyLibrary", "VoxelBlockyModelCube", "VoxelMesherBlocky"]:
		print("=== %s ===" % cls_name)
		if not ClassDB.class_exists(cls_name):
			print("  (class not registered — plugin missing or disabled)")
			continue
		var inst: Object = ClassDB.instantiate(cls_name)
		if inst == null:
			print("  (could not instantiate)")
			continue
		for p in inst.get_property_list():
			# Skip Object base + the meta categories with empty names.
			var n: String = p.get("name", "")
			if n == "" or n.begins_with("script") or n.begins_with("resource_"):
				continue
			# Skip the per-class header rows (usage 128/64).
			var usage: int = int(p.get("usage", 0))
			if usage & PROPERTY_USAGE_CATEGORY:
				continue
			if usage & PROPERTY_USAGE_GROUP:
				continue
			var t: int = int(p.get("type", 0))
			print("  %s : %s" % [n, type_string(t)])
		print("")
		print("  -- methods --")
		for m in inst.get_method_list():
			var mn: String = m.get("name", "")
			if mn.begins_with("_") or mn in ["set", "get", "set_script", "get_script"]:
				continue
			print("  %s()" % mn)
		print("")
