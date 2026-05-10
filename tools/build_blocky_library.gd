@tool
extends EditorScript
# tools/build_blocky_library.gd
#
# One-shot library builder. Run this from the Godot editor with the
# project open:
#
#   1. Open Script Editor.
#   2. File → Open Script → res://tools/build_blocky_library.gd
#   3. Press Ctrl+Shift+X (or File → Run).
#
# What it does:
#
#   1. Creates a VoxelBlockyLibrary with 13 entries (slot 0 = air,
#      slots 1..12 = active materials matching VoxelMaterialRegistry).
#   2. Each entry is a VoxelBlockyModelCube with per-face tile
#      indices into the texture atlas (top/side/bottom).
#   3. Loads the atlas texture from
#      res://assets/voxels/texture_packs/default/atlas.png and
#      assigns it as the library's material albedo.
#   4. Saves the library to res://assets/voxels/blocky_library.tres.
#
# Re-run any time:
#   - the material list changes (added/removed materials)
#   - the atlas layout in tools/build_texture_atlas.py changes
#   - the active texture pack changes (edit DEFAULT_PACK below)
#
# Why an EditorScript (and not a regular tool script): EditorScripts
# run once on demand without needing to be attached to a scene, and
# they have full editor APIs. This is the canonical Godot pattern for
# "configure this resource from code on demand."
#
# Plugin dependency: Zylann's Voxel Tools must be installed and
# enabled, otherwise VoxelBlockyLibrary and VoxelBlockyModelCube
# don't exist and this script will error out at the first new() call.
# See DESIGNER_TODO.md for plugin install steps.


# =============================================================
# CONFIGURATION
# =============================================================

const DEFAULT_PACK: String = "default"
const PACKS_DIR: String = "res://assets/voxels/texture_packs"
const LIBRARY_PATH: String = "res://assets/voxels/blocky_library.tres"

# Per-material face tile coordinates. (col, row) indexes into the
# atlas grid where each tile is `tile_size` px (read from pack.json).
# Mirrors MATERIAL_FACES + ATLAS_LAYOUT from tools/build_texture_atlas.py.
# Format: material_id -> { "top": Vector2i, "side": Vector2i, "bottom": Vector2i }
# Air (slot 0) is omitted — VoxelBlockyLibrary treats slot 0 as the
# default empty entry.
const MATERIAL_TILES: Dictionary = {
	1:  {"top": Vector2i(0, 0), "side": Vector2i(0, 0), "bottom": Vector2i(0, 0)},   # stone
	2:  {"top": Vector2i(1, 0), "side": Vector2i(1, 0), "bottom": Vector2i(1, 0)},   # dirt
	3:  {"top": Vector2i(2, 0), "side": Vector2i(3, 0), "bottom": Vector2i(1, 0)},   # grass
	4:  {"top": Vector2i(4, 0), "side": Vector2i(4, 0), "bottom": Vector2i(4, 0)},   # sand
	# 5 = water — handled by WaterChunkMesher, no library entry needed.
	#     We still register an empty cube so the slot index stays
	#     reserved (writing material_id 5 to TYPE channel will render
	#     nothing, which matches design intent).
	6:  {"top": Vector2i(4, 1), "side": Vector2i(4, 1), "bottom": Vector2i(4, 1)},   # bedrock
	7:  {"top": Vector2i(5, 0), "side": Vector2i(5, 0), "bottom": Vector2i(5, 0)},   # gravel
	8:  {"top": Vector2i(6, 0), "side": Vector2i(6, 0), "bottom": Vector2i(6, 0)},   # clay
	9:  {"top": Vector2i(7, 0), "side": Vector2i(7, 0), "bottom": Vector2i(7, 0)},   # marble
	10: {"top": Vector2i(0, 1), "side": Vector2i(1, 1), "bottom": Vector2i(0, 1)},   # log
	11: {"top": Vector2i(2, 1), "side": Vector2i(2, 1), "bottom": Vector2i(2, 1)},   # leaves
	12: {"top": Vector2i(3, 1), "side": Vector2i(3, 1), "bottom": Vector2i(3, 1)},   # copper_ore
}

# Material IDs that should render as transparent / partial-face
# blocks. Leaves are the canonical example — adjacent leaf voxels
# should NOT cull each other's faces, otherwise the canopy looks
# solid from outside and hollow from inside.
const TRANSPARENT_MATERIALS: Array[int] = [11]   # leaves


# =============================================================
# ENTRY POINT
# =============================================================

func _run() -> void:
	print("[build_blocky_library] starting…")

	# Verify the Zylann plugin is loaded by checking the class.
	if not ClassDB.class_exists("VoxelBlockyLibrary"):
		printerr("[build_blocky_library] VoxelBlockyLibrary class not found — is Zylann's Voxel Tools plugin installed and enabled?")
		return
	if not ClassDB.class_exists("VoxelBlockyModelCube"):
		printerr("[build_blocky_library] VoxelBlockyModelCube class not found — plugin version too old? Need a recent Zylann build with Blocky model classes.")
		return

	# Resolve the active texture pack.
	var pack_dir: String = PACKS_DIR.path_join(DEFAULT_PACK)
	var pack_meta_path: String = pack_dir.path_join("pack.json")
	var atlas_path: String = pack_dir.path_join("atlas.png")

	if not FileAccess.file_exists(pack_meta_path):
		printerr("[build_blocky_library] pack.json missing: %s" % pack_meta_path)
		return
	var pack_meta: Dictionary = _load_json(pack_meta_path)
	var tile_size: int = int(pack_meta.get("tile_size", 32))
	var atlas_size_px: int = int(pack_meta.get("atlas_size", 2048))
	@warning_ignore("integer_division")
	var tiles_per_row: int = atlas_size_px / tile_size
	print("[build_blocky_library] pack=%s tile=%dpx atlas=%dpx (%dx%d tile grid)" % [
		DEFAULT_PACK, tile_size, atlas_size_px, tiles_per_row, tiles_per_row
	])

	# Load the atlas texture (may not exist yet if the user hasn't run
	# the atlas builder — warn but continue; library will work once the
	# texture lands and Godot re-imports it).
	var atlas_tex: Texture2D = null
	if FileAccess.file_exists(atlas_path):
		atlas_tex = load(atlas_path) as Texture2D
		print("[build_blocky_library] loaded atlas: %s" % atlas_path)
	else:
		push_warning("[build_blocky_library] atlas.png missing at %s — library will be saved without a texture. Run `python tools/build_texture_atlas.py` first." % atlas_path)

	# Build the library.
	var library: Resource = ClassDB.instantiate("VoxelBlockyLibrary")
	if library == null:
		printerr("[build_blocky_library] could not instantiate VoxelBlockyLibrary")
		return

	# Configure each material slot. We build a fresh model per slot
	# (cube model with tile coordinates set from MATERIAL_TILES) and
	# add it to the library. Slot 0 (air) is left as default empty.
	#
	# Plugin API note: Zylann's library exposes either an `add_model`
	# method or a direct `models` array depending on plugin version.
	# We try the method first, fall back to array assignment.
	var max_id: int = 0
	for k in MATERIAL_TILES.keys():
		max_id = max(max_id, int(k))

	# Pre-populate the models array with empty entries up to max_id+1
	# so slot indices match material IDs. Air at slot 0 stays default.
	var models: Array = []
	models.resize(max_id + 1)

	for mat_id in MATERIAL_TILES.keys():
		var faces: Dictionary = MATERIAL_TILES[mat_id]
		var model: Resource = ClassDB.instantiate("VoxelBlockyModelCube")
		if model == null:
			printerr("[build_blocky_library] could not instantiate VoxelBlockyModelCube for slot %d" % mat_id)
			continue

		# Set per-face tile coordinates. The exact property names depend
		# on the Zylann plugin version. We try common names; whichever
		# exists takes effect, the others silently no-op.
		_try_set(model, "tiles_top", faces["top"])
		_try_set(model, "tiles_bottom", faces["bottom"])
		# All four side faces share the same side tile. Some plugin
		# versions have a single "tiles_side" property; others have
		# four (left/right/front/back). We try both.
		_try_set(model, "tiles_side", faces["side"])
		_try_set(model, "tiles_left", faces["side"])
		_try_set(model, "tiles_right", faces["side"])
		_try_set(model, "tiles_front", faces["side"])
		_try_set(model, "tiles_back", faces["side"])

		# Transparency / face culling. Leaves should not cull adjacent
		# leaf faces.
		if int(mat_id) in TRANSPARENT_MATERIALS:
			_try_set(model, "transparency_index", 1)

		models[mat_id] = model
		print("  slot %d: top=%s side=%s bottom=%s" % [
			mat_id, faces["top"], faces["side"], faces["bottom"]
		])

	# Assign the models array onto the library. Try direct assignment
	# first (most plugin versions expose `models` as an Array property);
	# fall back to per-entry add_model() if the direct assign fails.
	if not _try_set(library, "models", models):
		if library.has_method("add_model"):
			for i in range(models.size()):
				var m = models[i]
				if m != null:
					library.add_model(m)
		else:
			push_warning("[build_blocky_library] could not assign models — plugin API mismatch. Open the .tres in the editor and configure manually using assets/voxels/texture_packs/default/README.md.")

	# Atlas size hint — older plugin versions expose `atlas_size`; we
	# set it if present so per-face tile lookups can compute UVs.
	_try_set(library, "atlas_size", tiles_per_row)

	# Bake / refresh the library if the plugin requires it.
	if library.has_method("bake"):
		library.bake()
		print("[build_blocky_library] library.bake() called")

	# Save.
	var err: int = ResourceSaver.save(library, LIBRARY_PATH)
	if err != OK:
		printerr("[build_blocky_library] save failed: %d" % err)
		return
	print("[build_blocky_library] wrote %s" % LIBRARY_PATH)
	print("[build_blocky_library] DONE — open the library in the inspector to verify, then point VoxelLodTerrain at it in World3D.tscn.")


# =============================================================
# Helpers
# =============================================================

func _load_json(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _try_set(obj: Object, prop: String, value: Variant) -> bool:
	# Attempt to set `prop` on `obj` only if the property exists on
	# this object (avoids "Invalid set index" errors for plugin API
	# differences across versions). Returns true if set, false if the
	# property doesn't exist.
	for p in obj.get_property_list():
		if p.get("name", "") == prop:
			obj.set(prop, value)
			return true
	return false
