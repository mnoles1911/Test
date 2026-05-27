extends Node3D
# LodBoxOverlay — filled, coloured LOD0 box per VoxelViewer.
#
# Zylann's built-in `debug_draw_viewer_clipboxes` is wireframe-only and
# all viewers share a magenta-pink colour fading by LOD, which makes it
# hard to tell (a) which box belongs to which viewer and (b) where the
# LOD0 volumes actually sit when they overlap. This overlay sits on top
# of that and renders ONE translucent, no-depth-test filled cube per
# active VoxelViewer, each in its own colour:
#   * Main player viewer  → magenta
#   * Inner train viewer 0 → green
#   * Inner train viewer 1 → yellow
#   * Inner train viewer 2 → cyan
#
# Box size = 2 × lod_distance (in voxels) × terrain world scale, which
# matches Zylann's actual LOD0 ring radius (see CLAUDE.md note: ring
# radius is the terrain's lod_distance, not each viewer's view_distance).
#
# Visibility is toggled by World3DBootstrap on F12 alongside the
# built-in debug draws (call set_visible_overlay()). When invisible the
# script does no per-frame work.

const TERRAIN_PATH := "/root/World3D/VoxelLodTerrain"

# Colour palette — by ARRAY POSITION inside the discovered viewer set.
# Index 0 = main player viewer (it's always the first one discovered
# because it sits directly under Player3D). Subsequent indices = the
# PrefetchViewer train's inner viewers in spawn order.
const COLOURS: Array[Color] = [
	Color(1.00, 0.20, 0.85, 0.18),   # magenta — main
	Color(0.20, 1.00, 0.30, 0.18),   # green   — inner 0
	Color(1.00, 0.95, 0.10, 0.18),   # yellow  — inner 1
	Color(0.10, 0.85, 1.00, 0.18),   # cyan    — inner 2
	Color(1.00, 0.55, 0.10, 0.18),   # orange  — inner 3 (if user bumps count)
	Color(0.85, 0.30, 1.00, 0.18),   # purple  — inner 4
	Color(1.00, 1.00, 1.00, 0.18),   # white   — inner 5
	Color(0.60, 0.60, 0.60, 0.18),   # grey    — inner 6
]

var _terrain: Node = null
var _meshes: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _overlay_visible: bool = false


func _ready() -> void:
	# Mirror the lookup pattern other diag overlays use — by group, then
	# by absolute path as fallback. The script is added by
	# World3DBootstrap so absolute path is fine here.
	_terrain = get_node_or_null(TERRAIN_PATH)
	if _terrain == null:
		push_warning("[LodBoxOverlay] no terrain at %s; overlay will idle." % TERRAIN_PATH)
	visible = false  # invisible until F12 toggles us on


func set_visible_overlay(on: bool) -> void:
	_overlay_visible = on
	visible = on
	if not on:
		# Hide all our pool entries too so they don't render in nested
		# viewport renders (water reflection probe etc).
		for m in _meshes:
			m.visible = false


func _process(_delta: float) -> void:
	if not _overlay_visible:
		return
	if _terrain == null:
		return

	# Discover live VoxelViewers each frame. Cheap — there are typically
	# ≤4 of them and `get_nodes_in_group` is O(group size). We also
	# avoid caching them because the PrefetchViewer creates its inner
	# viewers AFTER our _ready() ran.
	var viewers: Array = []
	_collect_viewers(get_tree().get_root(), viewers)

	# LOD0 ring half-extent. terrain.lod_distance is in VOXELS; the
	# terrain Node3D scale converts voxels → world meters (e.g. 1/6 for
	# the project's 6 vox/m).
	var lod_distance_vox: float = 128.0
	if _terrain.has_method("get") and "lod_distance" in _terrain:
		lod_distance_vox = float(_terrain.get("lod_distance"))
	var world_scale: float = 1.0
	if _terrain is Node3D:
		# Voxel→world scale is uniform; take .x.
		world_scale = (_terrain as Node3D).global_basis.x.length()
	var half_extent_m: float = lod_distance_vox * world_scale
	var box_size: Vector3 = Vector3.ONE * (2.0 * half_extent_m)

	# Grow the pool if needed (rare — only triggers when PrefetchViewer
	# count is bumped at runtime).
	while _meshes.size() < viewers.size():
		_spawn_pool_entry()

	# Drive each pool entry to its viewer.
	for i in viewers.size():
		var v: Node = viewers[i]
		var mi: MeshInstance3D = _meshes[i]
		mi.visible = true
		# Position cube centre on the viewer's global position.
		if v is Node3D:
			mi.global_position = (v as Node3D).global_position
		# Resize the box to the current LOD0 ring (lod_distance may be
		# tuned live in the Inspector).
		var bm: BoxMesh = mi.mesh as BoxMesh
		if bm.size != box_size:
			bm.size = box_size
		# Recolour by index.
		var col: Color = COLOURS[i % COLOURS.size()]
		var mat: StandardMaterial3D = _materials[i]
		if mat.albedo_color != col:
			mat.albedo_color = col

	# Hide unused pool entries (e.g. PrefetchViewer disabled).
	for j in range(viewers.size(), _meshes.size()):
		_meshes[j].visible = false


func _collect_viewers(node: Node, out: Array) -> void:
	# Walk the tree once per frame collecting every Zylann VoxelViewer.
	# ClassDB check, not is — godot-cpp classes don't always pass `is`.
	if node.get_class() == "VoxelViewer":
		out.append(node)
	for c in node.get_children():
		_collect_viewers(c, out)


func _spawn_pool_entry() -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE  # gets resized on first _process tick
	mi.mesh = bm
	# Material: translucent, double-sided, no depth test so the box is
	# visible even when the player is inside it (the entire point —
	# you should be standing INSIDE the main LOD0 box, and the
	# camera shouldn't get culled by its back face).
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.albedo_color = Color(1.0, 0.2, 0.85, 0.18)
	mi.material_override = mat
	add_child(mi)
	_meshes.append(mi)
	_materials.append(mat)
