extends MeshInstance3D
# HorizonSkirt — runtime loader for the baked low-LOD terrain skirt.
#
# What this is for in plain English:
#
#   Zylann's view_distance is currently 250 m world. Past that radius
#   the player sees the sky meet a cliff. The skirt is a single coarse
#   mesh of the whole archipelago, baked once by the dev tool, that
#   always renders so distant peaks are visible at any distance.
#
#   Up close (inside view_distance), the live LOD0 voxel mesh draws on
#   top of the skirt — higher resolution, naturally wins the depth test
#   because the skirt sits 0.5 m below the true ground (offset baked in).
#
# Attached as a child of the VoxelLodTerrain node. Set `mesh_path` in
# the Inspector to the baked .res. If the baked mesh isn't on disk
# yet (fresh project, bake not yet run), the node hides itself
# silently — no error, just no skirt. Re-bake and re-launch to enable.

@export_file("*.res", "*.tres", "*.mesh") var mesh_path: String = "res://assets/voxel/copper_isles_skirt.res"

## Render priority. Negative values draw earlier (further back in the
## depth pipeline). Keeps the skirt below the dynamic water horizon
## plane (which uses render_priority = -1 already, so we go to -2).
@export var render_priority_offset: int = -2

## When true, scale the mesh to follow `terrain.transform.scale`. The
## skirt was baked at the canonical 1/6 terrain scale (6 vox/m); if
## the F7 hotkey ever changes the scale, this re-applies the new
## scale so the skirt continues to match the live terrain. Off by
## default — most setups stick with the baked scale.
@export var follow_terrain_scale: bool = false


func _ready() -> void:
	# Load the mesh. If it doesn't exist (e.g. fresh project before
	# any bake), hide silently and emit one info-level warning so the
	# developer can spot it in Output without ERR-screaming during
	# normal play.
	if not ResourceLoader.exists(mesh_path):
		visible = false
		print("[HorizonSkirt] Skirt mesh not found at %s — skirt hidden. Bake from scenes/_dev/BakeWorld.tscn." % mesh_path)
		return
	var loaded: Resource = load(mesh_path)
	if loaded == null or not (loaded is Mesh):
		visible = false
		push_warning("[HorizonSkirt] %s loaded but is not a Mesh; skirt disabled." % mesh_path)
		return
	mesh = loaded as Mesh
	# Material setup — vertex colours from the baker, no texture, low
	# roughness so the directional light still picks out shape.
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.render_priority = render_priority_offset
	material_override = mat

	if follow_terrain_scale:
		var terrain := get_parent() as Node3D
		if terrain != null:
			# Cancel out our own ancestor scale by inverting it; the
			# skirt was baked in WORLD metres so it should NOT inherit
			# the parent's voxel-grid scale. Set our local transform to
			# the inverse of the parent's basis to render at world scale.
			var inv: Basis = terrain.transform.basis.inverse()
			transform = Transform3D(inv, Vector3.ZERO)
		else:
			push_warning("[HorizonSkirt] follow_terrain_scale=true but parent is not Node3D")
