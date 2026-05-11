extends Node
# FallingClusterNet — autoload for replicating falling voxel cluster
# spawns across peers.
#
# WHAT THIS IS (plain English):
#
#   VoxelGravityManager spawns falling clusters on the host (it's
#   host-gated since MP-3). Without replication, guests don't see
#   the in-flight cluster — they only see the final terrain delta
#   when the cluster settles + re-deposits via
#   VoxelEditManager.queue_set_voxels_bulk (which MP-3 broadcasts).
#
#   This autoload broadcasts cluster SPAWNS to guests so they
#   instantiate their own visual replicas at the same time. Each
#   replica is non-authoritative — its physics is frozen and its
#   transform is driven by the MultiplayerSynchronizer that PR-C
#   staged on the scene root. The host's cluster runs physics
#   normally; guests see the host's broadcast pose.
#
#   Wire format: spawn(voxel_snapshot, edit_origin, gravity_scale,
#                       damage_multiplier, spawn_world_pos)
#   Reliable channel because dropping a spawn would leave the
#   guest seeing a sudden terrain delta with no cluster mid-flight.
#
# WHY THIS IS ITS OWN AUTOLOAD (vs. living on VoxelGravityManager):
#
#   VGM is the spawn DECIDER (gravity scan + flood fill). The
#   network replication is a separate concern: when to spawn vs.
#   how to spawn vs. where to mount. Splitting keeps both files
#   simpler. Mirrors the ThrowableNet pattern from PR-C.
#
# PAYLOAD SIZE:
#
#   A cluster's voxel_snapshot is a Dictionary keyed by Vector3i
#   (cluster-local positions) → packed RGBA32 ints. Bounded by
#   VoxelGravityManager.MAX_VOXELS_PER_CLUSTER (= 4096). At
#   ~16 bytes per entry that's ~64KB worst case per spawn. Godot's
#   reliable channel fragments automatically; payload is fine.


# =============================================================
# CONFIG
# =============================================================

const FALLING_CLUSTER_SCENE: PackedScene = preload("res://scenes/voxel/FallingVoxelCluster.tscn")


# =============================================================
# PUBLIC API
# =============================================================

## Spawn a cluster locally (authoritative) AND broadcast to guests.
## Returns the spawned node so the caller (VoxelGravityManager) can
## track it in _active_clusters.
##
## In OFFLINE this just spawns locally with no broadcast. In a
## hosted session this spawns authoritative + broadcasts. Should
## not be called on guests (VGM is host-gated so this never fires
## guest-side, but defensive check still applies).
func spawn_authoritative(
	voxel_snapshot: Dictionary,
	edit_origin: Vector3,
	gravity_scale: float,
	damage_multiplier: float,
	spawn_world_pos: Vector3,
) -> Node:
	# Host / offline path. (Guest path: never fires here because
	# VGM is host-gated. But defensive — if a guest somehow calls
	# spawn_authoritative, fall back to local visual-only.)
	var is_auth: bool = true
	if get_node_or_null("/root/MultiplayerManager") != null \
			and not MultiplayerManager.is_offline() \
			and not MultiplayerManager.is_host():
		push_warning("[FallingClusterNet] spawn_authoritative called on guest — making visual-only replica")
		is_auth = false

	var local: Node = _spawn_local(voxel_snapshot, edit_origin, gravity_scale, damage_multiplier, spawn_world_pos, is_auth)
	# Broadcast to guests so they get a visual replica.
	if get_node_or_null("/root/MultiplayerManager") != null \
			and not MultiplayerManager.is_offline() \
			and MultiplayerManager.is_host():
		# Convert Vector3i keys to a packed array for RPC marshalling.
		# Godot 4 RPC handles Dictionary keys natively but Vector3i is
		# the cleanest pack. Send as-is.
		_rpc_replicate_cluster.rpc(voxel_snapshot, edit_origin, gravity_scale, damage_multiplier, spawn_world_pos)
	return local


# =============================================================
# RPCs
# =============================================================

# Host → guests. Non-authoritative replica. Physics frozen; sync
# drives transform.
@rpc("authority", "reliable")
func _rpc_replicate_cluster(
	voxel_snapshot: Dictionary,
	edit_origin: Vector3,
	gravity_scale: float,
	damage_multiplier: float,
	spawn_world_pos: Vector3,
) -> void:
	if get_node_or_null("/root/MultiplayerManager") != null \
			and MultiplayerManager.is_host():
		return
	_spawn_local(voxel_snapshot, edit_origin, gravity_scale, damage_multiplier, spawn_world_pos, false)


# =============================================================
# INTERNAL — local spawn
# =============================================================

func _spawn_local(
	voxel_snapshot: Dictionary,
	edit_origin: Vector3,
	gravity_scale: float,
	damage_multiplier: float,
	spawn_world_pos: Vector3,
	is_authoritative: bool,
) -> Node:
	var cluster: Node = FALLING_CLUSTER_SCENE.instantiate()
	if cluster == null:
		push_error("[FallingClusterNet] failed to instantiate FallingVoxelCluster scene")
		return null

	# Mount under the current scene's root. VGM's existing code uses
	# the terrain's parent for this; the current scene works the
	# same way and doesn't require us to look up the terrain on
	# guests (which may not have it bound to VEM yet).
	var world_root: Node = get_tree().get_current_scene()
	if world_root == null:
		push_warning("[FallingClusterNet] no current scene to mount cluster into")
		cluster.queue_free()
		return null
	world_root.add_child(cluster)
	cluster.global_position = spawn_world_pos

	# Tag MP state BEFORE configure so the cluster's _ready /
	# configure code paths can branch on _mp_is_authoritative.
	if "_mp_is_authoritative" in cluster:
		cluster._mp_is_authoritative = is_authoritative

	# Authority = HOST_PEER_ID for authoritative spawns; guest
	# replicas inherit default (= 1 = host) which is what we want
	# (the MultiplayerSynchronizer routes packets FROM host TO
	# others). Guest replicas don't need is_multiplayer_authority
	# == self anywhere; they're pure receivers.
	cluster.set_multiplayer_authority(1)

	# configure() builds the mesh + collision + physics tuning.
	# Both authoritative and replica run configure so both have
	# identical visuals; the replica freezes physics inside its
	# own _ready / _physics_process based on _mp_is_authoritative.
	cluster.configure(voxel_snapshot, edit_origin, gravity_scale, damage_multiplier)
	return cluster
