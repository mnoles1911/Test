extends Node
# VoxelMaterialRegistry — the central catalogue of every voxel material
# in the game.
#
# What this does in plain English:
#
# At startup, this autoload scans `assets/voxels/materials/` for every
# `.tres` file, loads each one as a VoxelMaterial Resource, and builds
# two lookup tables:
#
#   _by_id      — material_id (int 1-254) → VoxelMaterial
#   _by_string  — id_string (e.g. "stone") → VoxelMaterial
#
# Anywhere code needs to know "what is this voxel?" it queries this
# registry. Voxel buffers store the material_id directly in
# CHANNEL_TYPE — no packing, no encoding. The integer value IS the
# material id (0 = air, 1-254 = a material in the registry, 255
# reserved). The mesher (VoxelMesherBlocky) reads CHANNEL_TYPE and
# looks up the matching model in the VoxelBlockyLibrary.
#
# IMPORTANT: this autoload MUST load BEFORE VoxelEditManager (since
# EditToolHandler queries it on every swing) and AFTER InventoryManager
# (we validate yield_item_id strings against ITEM_REGISTRY at startup).
# The load order is set in project.godot.
#
# How designers see this system:
#
# At launch, this script prints a summary line to the Output panel:
#   [VoxelMaterialRegistry] loaded 4 materials: stone(1), dirt(2),
#                           grass(3), sand(4)
#
# If a designer adds a new material with a colliding ID, the script
# prints a loud push_error naming both files and refuses to register
# the colliding entry. The game still launches but the colliding
# material won't work — the designer fixes the .tres and restarts.
#
# Reference: design/3D_VOXEL_MIGRATION.md → "Voxel Material System"


# =============================================================
# CONFIGURATION
# =============================================================

const MATERIALS_DIRECTORY: String = "res://assets/voxels/materials"
# Where the registry looks for VoxelMaterial.tres files. Recursive
# scan — designers can organise materials into subdirectories
# (e.g. assets/voxels/materials/ores/iron.tres) and the registry will
# still find them. Subdirectories help only the designer's mental
# model; the registry doesn't care.


# =============================================================
# RUNTIME STATE
# =============================================================

var _by_id: Dictionary = {}
# Vector3i unused here — int (material_id 1-254) → VoxelMaterial.
# Air (id=0) is NOT in this dictionary; tests for "is this a real
# material?" should check `_by_id.has(id)`.

var _by_string: Dictionary = {}
# String (id_string, e.g. "stone") → VoxelMaterial. Same set of
# materials as _by_id, indexed differently. Used by code that knows a
# material's name but not its int ID — most importantly the heightmap
# generator.

var _loaded: bool = false
# Set true when _ready completes its scan. Defensive: code that runs
# before _ready (e.g. autoloads earlier in the load order calling us)
# can check this and bail gracefully rather than crash.


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# Scan the materials directory and build the lookup tables.
	_scan_directory(MATERIALS_DIRECTORY)
	_validate_against_inventory()
	_loaded = true
	_print_summary()


# =============================================================
# PUBLIC API — lookups
# =============================================================

func get_by_id(material_id: int) -> VoxelMaterial:
	# Returns the material with this id, or null if none found.
	# id=0 (air) always returns null.
	return _by_id.get(material_id, null)


func get_by_string(id_string: String) -> VoxelMaterial:
	# Returns the material with this id_string, or null if none found.
	# Empty string returns null.
	if id_string == "":
		return null
	return _by_string.get(id_string, null)


func get_all() -> Array[VoxelMaterial]:
	# Returns every loaded material, sorted by material_id ascending.
	# For UI, debug overlays, or tools that need to enumerate.
	var out: Array[VoxelMaterial] = []
	var ids: Array = _by_id.keys()
	ids.sort()
	for i in ids:
		out.append(_by_id[i])
	return out


func is_loaded() -> bool:
	# Did _ready finish scanning? Code that runs before this autoload
	# completes (rare but possible) can guard with this.
	return _loaded


# =============================================================
# PUBLIC API — voxel value encoding
# =============================================================
#
# After the VoxelMesherBlocky migration, voxel values in CHANNEL_TYPE
# are plain integers — the material_id itself. No packing, no
# encoding tricks. These helpers exist as a thin layer so callers
# don't sprinkle raw integer arithmetic through the codebase, and so
# we can change the encoding again later without rewriting every
# call site.

func type_value_for_material(material_id: int) -> int:
	# Returns the integer to write into CHANNEL_TYPE for a voxel of
	# this material. Currently a passthrough — material_id IS the
	# type value. Range-check and warn if the caller passed something
	# outside the valid range (0 = air; 1-254 = material; 255 reserved).
	if material_id < 0 or material_id > 254:
		push_warning("[VoxelMaterialRegistry] type_value_for_material called with material_id=%d (must be 0-254). Clamping." % material_id)
		material_id = clampi(material_id, 0, 254)
	return material_id


func material_id_from_type(type_value: int) -> int:
	# Extract the material id from a CHANNEL_TYPE voxel value.
	# Currently a passthrough. Returns 0 for air voxels.
	return type_value & 0xFF


func is_air(type_value: int) -> bool:
	# True if this voxel is air (type == 0). Convenience wrapper so
	# the encoding stays an implementation detail of the registry,
	# not knowledge spread across the codebase.
	return (type_value & 0xFF) == 0


# Legacy aliases — pre-migration call sites may still reference these
# names. Kept as thin wrappers that ignore the colour argument so old
# code works unchanged. New code should call type_value_for_material()
# and material_id_from_type() directly.

func pack_voxel(material_id: int, _color: Color = Color.WHITE) -> int:
	return type_value_for_material(material_id)


func material_id_from_packed(type_value: int) -> int:
	return material_id_from_type(type_value)


# =============================================================
# PRIVATE — directory scan
# =============================================================

func _scan_directory(path: String) -> void:
	# Recursively walk `path`, loading every .tres file we find.
	# DirAccess.open returns null if the directory doesn't exist —
	# in that case we just log and move on (an empty registry is valid;
	# the game can launch without any materials defined, though
	# anything that depends on materials will warn).
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		push_warning("[VoxelMaterialRegistry] materials directory not found: %s — registry will be empty" % path)
		return

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		# Skip the . and .. directory entries that DirAccess returns.
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue

		var full_path: String = path.path_join(entry)
		if dir.current_is_dir():
			# Recurse into subdirectories. Designers can organise
			# materials into folders (ores/, woods/, etc.) for their
			# own sanity; we don't care about the structure.
			_scan_directory(full_path)
		elif entry.ends_with(".tres"):
			_load_material_from_file(full_path)
		entry = dir.get_next()
	dir.list_dir_end()


func _load_material_from_file(path: String) -> void:
	# Load the .tres, verify it's actually a VoxelMaterial Resource,
	# validate its fields, and register it in both lookup tables.
	# Any failure logs a clear error pointing at the file and aborts
	# the registration of THAT material — other materials are
	# unaffected. Game continues to launch.
	var res: Resource = load(path)
	if res == null:
		push_error("[VoxelMaterialRegistry] could not load resource: %s" % path)
		return
	if not (res is VoxelMaterial):
		push_error("[VoxelMaterialRegistry] file is not a VoxelMaterial: %s (got %s)" % [path, res.get_class()])
		return

	var mat: VoxelMaterial = res as VoxelMaterial

	# Validate material_id range.
	if mat.material_id < 1 or mat.material_id > 254:
		push_error("[VoxelMaterialRegistry] %s: material_id=%d is out of range (must be 1-254)" % [path, mat.material_id])
		return

	# Validate id_string is non-empty.
	if mat.id_string == "":
		push_error("[VoxelMaterialRegistry] %s: id_string is empty (must be a stable identifier like 'stone')" % path)
		return

	# Check for material_id collision.
	if _by_id.has(mat.material_id):
		var existing: VoxelMaterial = _by_id[mat.material_id]
		push_error("[VoxelMaterialRegistry] material_id collision (%d): '%s' (%s) vs '%s' (already loaded). Skipping the duplicate; fix the .tres files." % [
			mat.material_id, mat.id_string, path, existing.id_string
		])
		return

	# Check for id_string collision.
	if _by_string.has(mat.id_string):
		var existing2: VoxelMaterial = _by_string[mat.id_string]
		push_error("[VoxelMaterialRegistry] id_string collision ('%s'): '%s' vs material_id=%d (already loaded). Skipping the duplicate; fix the .tres files." % [
			mat.id_string, path, existing2.material_id
		])
		return

	# Register.
	_by_id[mat.material_id] = mat
	_by_string[mat.id_string] = mat


# =============================================================
# PRIVATE — cross-validation against InventoryManager
# =============================================================

func _validate_against_inventory() -> void:
	# Each material's yield_item_id should reference a real entry in
	# InventoryManager.ITEM_REGISTRY. If it doesn't, the player can
	# never pick up the harvested item — it's dropped silently because
	# add_item warns and bails on unknown ids.
	#
	# This validation is non-fatal: we warn, the game continues. The
	# designer sees the warning and either adds the missing item to
	# InventoryManager or fixes the typo in the .tres.
	#
	# Empty yield_item_id is fine (some materials are non-harvestable).
	var inv := get_node_or_null("/root/InventoryManager")
	if inv == null:
		# InventoryManager not registered yet — autoload order issue.
		# Skip this validation rather than crash; the designer will see
		# missing items at runtime when they actually try to harvest.
		push_warning("[VoxelMaterialRegistry] InventoryManager not available; skipping yield_item_id validation")
		return

	for mat in get_all():
		if mat.yield_item_id == "":
			continue
		if not inv.ITEM_REGISTRY.has(mat.yield_item_id):
			push_warning("[VoxelMaterialRegistry] material '%s' yields '%s' but that item_id is not in InventoryManager.ITEM_REGISTRY. Add the item or fix the .tres." % [
				mat.id_string, mat.yield_item_id
			])


# =============================================================
# PRIVATE — startup logging
# =============================================================

func _print_summary() -> void:
	# Print a one-line summary of every loaded material to the Output
	# panel. Designers reference this to find which IDs are taken
	# before assigning a new one.
	var parts: Array[String] = []
	for mat in get_all():
		parts.append("%s(%d)" % [mat.id_string, mat.material_id])
	if parts.is_empty():
		print("[VoxelMaterialRegistry] loaded 0 materials (none found in %s)" % MATERIALS_DIRECTORY)
	else:
		print("[VoxelMaterialRegistry] loaded %d materials: %s" % [parts.size(), ", ".join(parts)])
