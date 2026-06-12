extends RefCounted
class_name VoxelTreeImporter
# scripts/_dev/VoxelTreeImporter.gd
#
# Imports a tree authored in tools/voxel_tree_studio (a JSON file of voxels)
# and stamps it into the live world.
#
# WHAT IT DOES (plain English)
#   The studio exports a tree as a list of voxels { x, y, z, m } where `m` is a
#   material id (rich palette 24-28, or collapsed 10/11). This reads that file
#   and writes each voxel into the terrain through VoxelEditManager — the single
#   legal gateway for voxel writes (NoEditZone gate + MP routing). The world
#   uses VoxelMesherBlocky, so a voxel's value in CHANNEL_TYPE *is* its
#   material_id (see VoxelEditManager header).
#
# REQUIRES THE RUNNING GAME — VoxelEditManager is an autoload, so call this at
# runtime (e.g. from a dev key in World3DBootstrap or the debug console), NOT
# from an EditorScript. `validate()` below is data-only and is safe anywhere.
#
# USAGE (runtime):
#   var n := VoxelTreeImporter.stamp("res://exports/tree_oak.json", Vector3i(0, 40, 0))
#   print("stamped %d voxels" % n)
#   # base_grid = the engine voxel-grid cell where the TRUNK BASE should sit.
#
# SCALE NOTE: the studio authors at 10 voxels/m; the live engine is currently
# 6 vox/m (VOXELS_PER_METER below). We place ONE studio voxel per ONE engine
# grid cell (1:1), so the tree comes out ~67% larger than designed until the
# engine migrates to 10 vox/m (DESIGNER_TODO §8). Pass a different
# `voxels_per_meter` if your build has migrated.

const VOXELS_PER_METER: float = 6.0

# When a studio palette id has no registered material in-engine, collapse it to
# the nearest base material (wood -> 10 log, leaves -> 11 leaves).
const COLLAPSE: Dictionary = {
	24: 10, 25: 10, 26: 10,   # bark / heartwood / deadwood -> log
	27: 11, 28: 11,           # leaf shades -> leaves
}


# Parse + validate a studio export. Returns {} on failure (with push_error).
# Pure data — safe to call from anywhere (tests, editor, runtime).
static func validate(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("[VoxelTreeImporter] file not found: %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[VoxelTreeImporter] cannot open: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[VoxelTreeImporter] not a JSON object: %s" % path)
		return {}
	var tree: Dictionary = parsed
	var fmt: String = str(tree.get("format", ""))
	# Accept any mira-thal voxel asset (trees, rocks, ...) — the import path is
	# identical: a list of {x,y,z,m} voxels written through VoxelEditManager.
	if fmt != "mira-thal-voxel-tree" and fmt != "mira-thal-voxel-rock":
		push_error("[VoxelTreeImporter] unexpected format: %s" % fmt)
		return {}
	if not (tree.get("voxels") is Array) or (tree["voxels"] as Array).is_empty():
		push_error("[VoxelTreeImporter] no voxels in file")
		return {}
	return tree


# Resolve the live VoxelMaterialRegistry autoload, or null outside the game.
static func _registry() -> Object:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null("/root/VoxelMaterialRegistry")


# Map a studio material id to the CHANNEL_TYPE value to write. If the id is a
# registered material, keep it; otherwise collapse to a base material (10/11).
# Routes through type_value_for_material so the encoding stays the registry's
# business (currently a passthrough).
static func _type_value_for(studio_id: int) -> int:
	var reg := _registry()
	var mat_id: int = studio_id
	if reg != null and reg.has_method("get_by_id"):
		if reg.call("get_by_id", studio_id) == null:
			mat_id = int(COLLAPSE.get(studio_id, studio_id))
	else:
		# No registry (e.g. data-only validation) — collapse the rich palette
		# so build_writes is still meaningful without the game running.
		mat_id = int(COLLAPSE.get(studio_id, studio_id))
	if reg != null and reg.has_method("type_value_for_material"):
		return int(reg.call("type_value_for_material", mat_id))
	return mat_id


# Build the world-space write list. base_grid = engine grid cell of the trunk
# base. Returns Array of { "pos": Vector3 (world), "value": int (material_id) }.
static func build_writes(tree: Dictionary, base_grid: Vector3i, voxels_per_meter: float = VOXELS_PER_METER) -> Array:
	var writes: Array = []
	var inv: float = 1.0 / voxels_per_meter
	for v in tree["voxels"]:
		var gx: int = base_grid.x + int(v["x"])
		var gy: int = base_grid.y + int(v["y"])
		var gz: int = base_grid.z + int(v["z"])
		# Grid cell -> world meters so VoxelEditManager lands on that exact cell.
		writes.append({
			"pos": Vector3(gx, gy, gz) * inv,
			"value": _type_value_for(int(v["m"])),
		})
	return writes


# Stamp a tree file into the live world. Returns the number of voxels queued,
# or -1 on failure. RUNTIME ONLY (needs the VoxelEditManager autoload).
static func stamp(path: String, base_grid: Vector3i, voxels_per_meter: float = VOXELS_PER_METER) -> int:
	var tree := validate(path)
	if tree.is_empty():
		return -1
	var vem = Engine.get_main_loop().root.get_node_or_null("/root/VoxelEditManager")
	if vem == null:
		push_error("[VoxelTreeImporter] VoxelEditManager autoload not found — run in-game, not the editor")
		return -1
	var writes := build_writes(tree, base_grid, voxels_per_meter)
	var ok: bool = vem.queue_set_voxels_bulk(writes, "tree_import:%s" % path.get_file())
	if not ok:
		push_warning("[VoxelTreeImporter] queue rejected the bulk write (queue full?)")
		return -1
	print("[VoxelTreeImporter] queued %d voxels from %s at %s" % [writes.size(), path.get_file(), str(base_grid)])
	return writes.size()
