@tool
extends EditorScript
# tools/build_blocky_library.gd
#
# One-shot library builder. Run this from the Godot editor with the
# project open:
#
#   1. Open Script Editor.
#   2. File -> Open Script -> res://tools/build_blocky_library.gd
#   3. Press Ctrl+Shift+X (or File -> Run).
#
# What it does:
#
#   1. Loads the atlas texture from
#      res://assets/voxels/texture_packs/default/atlas.png.
#   2. Builds a single shared StandardMaterial3D with the atlas as
#      albedo, alpha-scissor enabled (so leaves cut out the white
#      background that the atlas builder color-keyed to alpha), and
#      nearest-neighbour texture filtering for crisp tile edges.
#   3. Creates a VoxelBlockyLibrary with 13 entries (slot 0 = air,
#      slots 1..12 = active materials matching VoxelMaterialRegistry).
#   4. Each entry is a VoxelBlockyModelCube with:
#        - per-face tile_top / tile_bottom / tile_left/right/front/back
#          coords pointing into the atlas
#        - atlas_size_in_tiles set so Zylann can compute UVs
#        - material_override_0 set to the shared atlas material
#   5. Bakes the library and saves it to
#      res://assets/voxels/blocky_library.tres.
#
# Re-run any time:
#   - the material list changes (added/removed materials)
#   - the atlas layout in tools/build_texture_atlas.py changes
#   - the active texture pack changes (edit DEFAULT_PACK below)
#
# Plugin dependency: Zylann's Voxel Tools must be installed and
# enabled, otherwise VoxelBlockyLibrary and VoxelBlockyModelCube
# don't exist and this script will error out at the first instantiate.

# =============================================================
# CONFIGURATION
# =============================================================

const DEFAULT_PACK: String = "default"
const PACKS_DIR: String = "res://assets/voxels/texture_packs"
const LIBRARY_PATH: String = "res://assets/voxels/blocky_library.tres"

# Per-material face tile coordinates. (col, row) indexes into the
# atlas grid where each tile is `tile_size` px (read from pack.json).
# Mirrors MATERIAL_FACES + ATLAS_LAYOUT from tools/build_texture_atlas.py.
# Air (slot 0) is omitted -- VoxelBlockyLibrary treats slot 0 as the
# default empty entry.
const MATERIAL_TILES: Dictionary = {
	1:  {"top": Vector2i(0, 0),  "side": Vector2i(0, 0),  "bottom": Vector2i(0, 0)},   # stone
	2:  {"top": Vector2i(1, 0),  "side": Vector2i(1, 0),  "bottom": Vector2i(1, 0)},   # dirt
	3:  {"top": Vector2i(2, 0),  "side": Vector2i(3, 0),  "bottom": Vector2i(1, 0)},   # grass
	4:  {"top": Vector2i(4, 0),  "side": Vector2i(4, 0),  "bottom": Vector2i(4, 0)},   # sand
	# 5 = water — handled by WaterChunkMesher, no library entry needed.
	6:  {"top": Vector2i(4, 1),  "side": Vector2i(4, 1),  "bottom": Vector2i(4, 1)},   # bedrock
	7:  {"top": Vector2i(5, 0),  "side": Vector2i(5, 0),  "bottom": Vector2i(5, 0)},   # gravel
	8:  {"top": Vector2i(6, 0),  "side": Vector2i(6, 0),  "bottom": Vector2i(6, 0)},   # clay
	9:  {"top": Vector2i(7, 0),  "side": Vector2i(7, 0),  "bottom": Vector2i(7, 0)},   # marble
	10: {"top": Vector2i(0, 1),  "side": Vector2i(1, 1),  "bottom": Vector2i(0, 1)},   # log
	11: {"top": Vector2i(2, 1),  "side": Vector2i(2, 1),  "bottom": Vector2i(2, 1)},   # leaves
	12: {"top": Vector2i(3, 1),  "side": Vector2i(3, 1),  "bottom": Vector2i(3, 1)},   # copper_ore
	13: {"top": Vector2i(8, 0),  "side": Vector2i(8, 0),  "bottom": Vector2i(8, 0)},   # snow (Tier 2)
	14: {"top": Vector2i(9, 0),  "side": Vector2i(9, 0),  "bottom": Vector2i(9, 0)},   # stone_dark (Tier 3)
	15: {"top": Vector2i(10, 0), "side": Vector2i(10, 0), "bottom": Vector2i(10, 0)},  # iron_ore (Tier 4)
	# Tree-asset palette (ids 24-28) from tools/voxel_tree_studio. Placeholder
	# tiles; replace with real pixel art. ids 16-23 are native fluid models.
	24: {"top": Vector2i(5, 1),  "side": Vector2i(5, 1),  "bottom": Vector2i(5, 1)},   # bark
	25: {"top": Vector2i(6, 1),  "side": Vector2i(6, 1),  "bottom": Vector2i(6, 1)},   # heartwood
	26: {"top": Vector2i(7, 1),  "side": Vector2i(7, 1),  "bottom": Vector2i(7, 1)},   # deadwood
	27: {"top": Vector2i(8, 1),  "side": Vector2i(8, 1),  "bottom": Vector2i(8, 1)},   # leaf_dark
	28: {"top": Vector2i(9, 1),  "side": Vector2i(9, 1),  "bottom": Vector2i(9, 1)},   # leaf_light
	# Vegetation (ids 29-31) — grass blades + fern fronds. Placeholder tiles.
	29: {"top": Vector2i(10, 1), "side": Vector2i(10, 1), "bottom": Vector2i(10, 1)},  # grass_blade
	30: {"top": Vector2i(11, 1), "side": Vector2i(11, 1), "bottom": Vector2i(11, 1)},  # grass_dry
	31: {"top": Vector2i(12, 1), "side": Vector2i(12, 1), "bottom": Vector2i(12, 1)},  # fern_frond
}

# Material IDs that should NOT cull adjacent block faces. Leaves are
# the canonical example -- the canopy needs to look dense from outside,
# so each leaf voxel keeps its faces visible even when surrounded by
# other leaves.
const NON_CULLING_MATERIALS: Array[int] = [11, 27, 28, 29, 30, 31]   # leaves + tree leaf shades + grass/fern

# Material IDs that should render as transparent. Different
# transparency_index values mean Zylann groups faces into separate
# render passes for correct alpha sorting. 1 = leaves' alpha-cutout
# group.
const TRANSPARENT_MATERIALS: Array[int] = [11, 27, 28, 29, 30, 31]   # leaves + tree leaf shades + grass/fern


# =============================================================
# ENTRY POINT
# =============================================================

func _run() -> void:
	print("[build_blocky_library] starting…")

	# Verify the Zylann plugin is loaded by checking the class.
	if not ClassDB.class_exists("VoxelBlockyLibrary"):
		printerr("[build_blocky_library] VoxelBlockyLibrary class not found -- is Zylann's Voxel Tools plugin installed and enabled?")
		return
	if not ClassDB.class_exists("VoxelBlockyModelCube"):
		printerr("[build_blocky_library] VoxelBlockyModelCube class not found -- plugin too old?")
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
	var atlas_grid: Vector2i = Vector2i(tiles_per_row, tiles_per_row)
	print("[build_blocky_library] pack=%s tile=%dpx atlas=%dpx (%dx%d tile grid)" % [
		DEFAULT_PACK, tile_size, atlas_size_px, tiles_per_row, tiles_per_row
	])

	if not FileAccess.file_exists(atlas_path):
		printerr("[build_blocky_library] atlas.png missing at %s -- run `python tools/build_texture_atlas.py default` first" % atlas_path)
		return
	var atlas_tex: Texture2D = load(atlas_path) as Texture2D
	if atlas_tex == null:
		printerr("[build_blocky_library] failed to load atlas: %s" % atlas_path)
		return
	print("[build_blocky_library] loaded atlas: %s (%dx%d)" % [
		atlas_path, atlas_tex.get_width(), atlas_tex.get_height()
	])

	# Build the shared atlas material. One material drives every cube
	# face; alpha-scissor handles the leaves' chroma-keyed gaps without
	# needing a second material or messy depth sorting.
	var atlas_mat: StandardMaterial3D = StandardMaterial3D.new()
	atlas_mat.resource_name = "atlas_default"
	atlas_mat.albedo_texture = atlas_tex
	atlas_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	atlas_mat.alpha_scissor_threshold = 0.5
	atlas_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	atlas_mat.roughness = 0.85
	atlas_mat.metallic = 0.0
	atlas_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	print("[build_blocky_library] built shared atlas material (alpha-scissor, nearest filter)")

	# Build the library. Pre-size the models array so slot indices
	# match material IDs (slot 0 = air = null).
	var library: Resource = ClassDB.instantiate("VoxelBlockyLibrary")
	if library == null:
		printerr("[build_blocky_library] could not instantiate VoxelBlockyLibrary")
		return

	var max_id: int = 0
	for k in MATERIAL_TILES.keys():
		max_id = max(max_id, int(k))
	var models: Array = []
	models.resize(max_id + 1)

	# Zylann Cube SIDE enum (from voxel/util/godot/classes/cube.h):
	#   0 = SIDE_NEGATIVE_X (left / west)
	#   1 = SIDE_POSITIVE_X (right / east)
	#   2 = SIDE_NEGATIVE_Y (bottom / down)
	#   3 = SIDE_POSITIVE_Y (top / up)
	#   4 = SIDE_NEGATIVE_Z (front / north)
	#   5 = SIDE_POSITIVE_Z (back / south)
	const SIDE_NEG_X: int = 0
	const SIDE_POS_X: int = 1
	const SIDE_NEG_Y: int = 2
	const SIDE_POS_Y: int = 3
	const SIDE_NEG_Z: int = 4
	const SIDE_POS_Z: int = 5

	for mat_id in MATERIAL_TILES.keys():
		var faces: Dictionary = MATERIAL_TILES[mat_id]
		var model: Resource = ClassDB.instantiate("VoxelBlockyModelCube")
		if model == null:
			printerr("[build_blocky_library] could not instantiate cube for slot %d" % mat_id)
			continue

		# Atlas grid size on every cube so Zylann knows how to compute
		# per-face UVs from the integer tile coords below. This DOES
		# work via direct .set() because it's a simple property.
		model.set("atlas_size_in_tiles", atlas_grid)

		# Per-face tile coords MUST be set via the set_tile() method.
		# Direct property assignment via .set("tile_top", v) silently
		# no-ops because Zylann's serializer routes property storage
		# through set_tile/get_tile pair.
		model.call("set_tile", SIDE_POS_Y, faces["top"])
		model.call("set_tile", SIDE_NEG_Y, faces["bottom"])
		model.call("set_tile", SIDE_NEG_X, faces["side"])
		model.call("set_tile", SIDE_POS_X, faces["side"])
		model.call("set_tile", SIDE_NEG_Z, faces["side"])
		model.call("set_tile", SIDE_POS_Z, faces["side"])

		# Each cube carries the atlas material on its single surface.
		# `material_override_0` is a dynamic per-surface property name
		# — must use the set_material_override(surface_idx, mat) method.
		model.call("set_material_override", 0, atlas_mat)

		# Transparency / culling. transparency_index is a real property
		# (it's the only one that previously persisted), so .set() works.
		if int(mat_id) in TRANSPARENT_MATERIALS:
			model.set("transparency_index", 1)
		if int(mat_id) in NON_CULLING_MATERIALS:
			model.set("culls_neighbors", false)

		# Read-back verification — confirms set_tile actually stuck
		# before we try to save. If these don't match, the build is
		# broken before serialization gets involved.
		var rb_top: Vector2i = model.call("get_tile", SIDE_POS_Y)
		var rb_mat = model.call("get_material_override", 0)
		var ok: bool = rb_top == (faces["top"] as Vector2i) and rb_mat != null
		var status: String = "OK" if ok else "FAIL"
		print("  slot %d [%s]: top=%s side=%s bottom=%s mat=%s" % [
			mat_id, status, faces["top"], faces["side"], faces["bottom"],
			"yes" if rb_mat != null else "MISSING"
		])

		models[mat_id] = model

	# Assign models array onto the library.
	library.set("models", models)

	# Bake the library so Zylann compiles its internal LUTs.
	if library.has_method("bake"):
		library.bake()
		print("[build_blocky_library] library.bake() called")

	# Save. Use FLAG_BUNDLE_RESOURCES so the embedded models AND the
	# shared StandardMaterial3D ride along inside the .tres file
	# instead of being saved as orphaned external resources.
	var err: int = ResourceSaver.save(
		library,
		LIBRARY_PATH,
		ResourceSaver.FLAG_BUNDLE_RESOURCES
	)
	if err != OK:
		printerr("[build_blocky_library] save failed: %d" % err)
		return
	print("[build_blocky_library] wrote %s" % LIBRARY_PATH)
	print("[build_blocky_library] DONE -- run World3D.tscn to verify textured terrain.")


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
