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
	# DIAGNOSTIC dump — surfaces vital stats to Output so we can see
	# whether the loaded skirt has the expected shape (vertex count,
	# AABB extent, surface count) and confirm the new bake was
	# actually loaded (not a cached stale .res).
	var aabb: AABB = (loaded as Mesh).get_aabb()
	var surface_count: int = (loaded as Mesh).get_surface_count()
	var total_verts: int = 0
	var total_indices: int = 0
	for s in surface_count:
		var arrays: Array = (loaded as Mesh).surface_get_arrays(s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx = arrays[Mesh.ARRAY_INDEX]
		total_verts += v.size()
		if idx != null:
			total_indices += (idx as PackedInt32Array).size()
	print("[HorizonSkirt] loaded %s" % mesh_path)
	print("[HorizonSkirt]   surfaces=%d verts=%d tris=%d" % [
		surface_count, total_verts, total_indices / 3,
	])
	print("[HorizonSkirt]   aabb pos=(%.0f, %.0f, %.0f) size=(%.0f, %.0f, %.0f)" % [
		aabb.position.x, aabb.position.y, aabb.position.z,
		aabb.size.x, aabb.size.y, aabb.size.z,
	])
	# Spot-check a centre vertex's colour so we can tell whether the
	# new gradient/jitter palette landed (vs a stale flat-grey bake).
	if surface_count > 0:
		var arrays0: Array = (loaded as Mesh).surface_get_arrays(0)
		var colors_arr = arrays0[Mesh.ARRAY_COLOR]
		if colors_arr != null and (colors_arr as PackedColorArray).size() > 0:
			var pca: PackedColorArray = colors_arr
			var sample_idx: int = pca.size() / 2  # roughly mesh centre
			var sc: Color = pca[sample_idx]
			print("[HorizonSkirt]   sample vertex colour idx=%d → r=%.2f g=%.2f b=%.2f a=%.2f" % [
				sample_idx, sc.r, sc.g, sc.b, sc.a,
			])
		else:
			print("[HorizonSkirt]   ⚠ NO vertex colours on surface 0 — material will fall back to white")
	# Material setup — opaque, double-sided, lit. Tuned so distant
	# terrain reads as actual terrain instead of a flat grey wall:
	#   - roughness 0.7 (was 0.95) lets the directional sun produce
	#     subtle highlights on slopes facing the light. 0.95 is
	#     near-perfectly-matte — visually dead.
	#   - cull_mode DISABLED renders both sides — defeats winding bugs.
	#   - shadows on (cast + receive) so the CSM splits we just enabled
	#     in the scene actually project onto the skirt.
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.7
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Reverted to CULL_DISABLED. With CULL_BACK + the fixed winding
	# the player saw the far-side faces but the near-side faces were
	# transparent — winding-from-above and winding-from-camera don't
	# agree for steep-sloped terrain seen from arbitrary angles. A
	# horizon skirt is fundamentally a viewed-from-anywhere mesh, so
	# double-sided rendering is the right call. Slight loss of
	# diffuse shading nuance is the price.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.albedo_color = Color(1, 1, 1, 1)  # full alpha guard
	mat.no_depth_test = false
	mat.disable_receive_shadows = false
	material_override = mat
	# Mesh receives directional sun shadow + casts its own shadow onto
	# closer terrain. Cast is cheap because the skirt has wide flat
	# slopes and no fine detail.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Explicitly leave render_priority at 0 — the export at the top
	# of this file is now unused but kept to avoid breaking any
	# .tscn that already serialised it.

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
