extends Node
# ThrowableNet — autoload that routes throwable spawns across peers.
#
# WHAT THIS IS (plain English):
#
#   In OFFLINE / on the host, ThrowableHandler spawns a throwable
#   (spear, powder charge, future smoke bomb / oil flask) directly
#   into the world. In MP that doesn't work for guests:
#
#     • Their local ThrowableHandler is at a peer-specific path
#       (Players/PlayerSpawner/Player_<peer_id>/ThrowableHandler),
#       which doesn't exist on the host's tree (host has the guest's
#       player as a RemotePlayer.tscn without ThrowableHandler).
#       So RPCs initiated from ThrowableHandler can't route.
#
#     • Damage application must be host-authoritative — only one
#       instance of the spear should fire enemy.take_damage. If every
#       peer's spear damaged independently we'd get N× damage.
#
#   This autoload sits at a path that's identical on every peer
#   (/root/ThrowableNet) so its RPCs route cleanly. ThrowableHandler
#   calls ThrowableNet.request_throw(...) instead of instantiating
#   directly; ThrowableNet handles MP routing:
#
#     OFFLINE / HOST  →  spawn locally (authoritative);
#                        broadcast _rpc_replicate_throw so guests
#                        spawn visual replicas at the same place.
#     GUEST           →  _rpc_request_throw.rpc_id(1, ...) to host;
#                        host's path runs as above.
#
#   Damage gate: the spawned throwable's _on_body_entered fires
#   enemy.take_damage only when is_multiplayer_authority() returns
#   true on the throwable. Authoritative instances are spawned with
#   set_multiplayer_authority(1) (host); replicated visuals are
#   spawned with set_multiplayer_authority(<spawning peer's id>) so
#   they're explicitly NOT authoritative on host. (Host's own throws
#   are an exception — host's authoritative spawn IS the host, so
#   the auth flag is set to 1.)
#
#   Visual events (BloodVFX bursts, dust puffs) trigger locally on
#   every peer because each peer's physics runs the same collision
#   against their local Goblin / terrain copies. Already
#   per-peer-correct from MP-4's BloodVFX.spawn_burst_networked
#   pattern.
#
# WHY NOT MultiplayerSpawner:
#
#   Godot's MultiplayerSpawner is designed for "host spawns one,
#   everyone gets the replicated node." It works but adds a
#   scene-tree dependency (the spawner node must be in every world
#   scene at a known path) and a per-scene wiring step. The custom
#   RPC pattern here is leaner — every world scene already has the
#   throwable parent node (typically the local Player3D's parent
#   for lifetime reasons), so adding MultiplayerSpawner would mean
#   either a new node per scene or refactoring parent ownership.
#   Easier to ship the RPC pair.
#
# OPEN: the spawned throwable's local physics on each peer can
# diverge slightly across machines because RigidBody3D simulation
# isn't deterministic across clients. For MP-4-polish that's
# acceptable — visual mismatch at 20m flight distance is single-
# digit centimeters. If precision matters for a future projectile
# (sniper rifle, parry timing), MP-8 polish adds proper position
# sync via MultiplayerSynchronizer on the throwable root.


# =============================================================
# SPAWN REGISTRY (mirrors ThrowableHandler's local table so the
# host knows what to spawn from an item_id received over the wire).
# =============================================================

const THROWABLE_SCENES: Dictionary = {
	"powder_charge": preload("res://scenes/throwables/PowderCharge.tscn"),
	"spear":         preload("res://scenes/throwables/throwable_spear.tscn"),
}


# =============================================================
# PUBLIC API
# =============================================================

## Called by ThrowableHandler when the local player triggers a throw.
## Returns true if the throw was accepted (RPC sent or local spawn
## scheduled). False on bad item_id or missing transport.
##
## `inventory_data` is the dict from InventoryManager.ITEM_REGISTRY
## entry; carries voxel_aoe_radius / combat_damage which the
## throwable reads on spawn. Passed by value because RPC marshals
## dictionaries natively.
func request_throw(item_id: String, spawn_pos: Vector3, velocity: Vector3, inventory_data: Dictionary) -> bool:
	if not THROWABLE_SCENES.has(item_id):
		push_warning("[ThrowableNet] unknown item_id '%s'" % item_id)
		return false

	if get_node_or_null("/root/MultiplayerManager") == null \
			or MultiplayerManager.is_offline():
		# Offline path: pure local spawn.
		_spawn_throwable_local(item_id, spawn_pos, velocity, inventory_data, true, multiplayer.get_unique_id())
		return true

	if MultiplayerManager.is_host():
		# Host: authoritative local spawn + broadcast for guests.
		var my_peer: int = MultiplayerManager.local_peer_id()
		_spawn_throwable_local(item_id, spawn_pos, velocity, inventory_data, true, my_peer)
		_rpc_replicate_throw.rpc(item_id, spawn_pos, velocity, inventory_data, my_peer)
		return true

	# Guest: ask the host to spawn authoritatively.
	_rpc_request_throw.rpc_id(1, item_id, spawn_pos, velocity, inventory_data)
	return true


# =============================================================
# RPCs
# =============================================================

# Guest → host. Host spawns authoritatively + broadcasts to other peers.
@rpc("any_peer", "reliable")
func _rpc_request_throw(item_id: String, spawn_pos: Vector3, velocity: Vector3, inventory_data: Dictionary) -> void:
	if not MultiplayerManager.is_host():
		return
	var requester_peer: int = multiplayer.get_remote_sender_id()
	# Host spawns the authoritative throwable. Authority is set to
	# HOST (peer 1) so damage application fires from host's instance
	# only. Origin peer (the throwing guest) is tracked separately
	# for "do not damage self" filtering inside the throwable.
	_spawn_throwable_local(item_id, spawn_pos, velocity, inventory_data, true, requester_peer)
	# Broadcast to every other peer (including the guest who
	# initiated) so they spawn a visual replica.
	_rpc_replicate_throw.rpc(item_id, spawn_pos, velocity, inventory_data, requester_peer)


# Host → all other peers. Replica spawn — non-authoritative.
@rpc("authority", "reliable")
func _rpc_replicate_throw(item_id: String, spawn_pos: Vector3, velocity: Vector3, inventory_data: Dictionary, origin_peer: int) -> void:
	# Defense in depth — host shouldn't receive its own replicate.
	if MultiplayerManager.is_host():
		return
	_spawn_throwable_local(item_id, spawn_pos, velocity, inventory_data, false, origin_peer)


# =============================================================
# INTERNAL — spawn helper
# =============================================================

func _spawn_throwable_local(item_id: String, spawn_pos: Vector3, velocity: Vector3, inventory_data: Dictionary, is_authoritative: bool, origin_peer: int) -> void:
	var scene: PackedScene = THROWABLE_SCENES.get(item_id, null)
	if scene == null:
		push_warning("[ThrowableNet] scene missing for '%s'" % item_id)
		return
	var node: Node = scene.instantiate()
	if not node is RigidBody3D:
		push_error("[ThrowableNet] '%s' scene root must be RigidBody3D" % item_id)
		node.queue_free()
		return
	var rigid: RigidBody3D = node as RigidBody3D
	# Mount under the world scene root so the throwable's lifetime is
	# tied to the world (not whichever player spawned it). The
	# current_scene is the safest universal mount point.
	var world_root: Node = get_tree().get_current_scene()
	if world_root == null:
		push_warning("[ThrowableNet] no current scene to mount throwable into")
		rigid.queue_free()
		return
	world_root.add_child(rigid)
	rigid.global_position = spawn_pos

	# Apply inventory tuning. Same hooks as ThrowableHandler.
	if inventory_data.has("voxel_aoe_radius") and "aoe_radius_meters" in rigid:
		rigid.aoe_radius_meters = float(inventory_data["voxel_aoe_radius"])
	if inventory_data.has("combat_damage") and "combat_damage" in rigid:
		rigid.combat_damage = int(inventory_data["combat_damage"])

	# Authority: only the authoritative instance applies damage.
	# Use HOST_PEER_ID for authoritative spawns regardless of who
	# initiated the throw — host runs the simulation that decides
	# the hit. Replicas keep set_multiplayer_authority(origin_peer)
	# so RPC routing for any per-throwable RPC (future returning-
	# spear callbacks etc.) reaches the right peer.
	rigid.set_multiplayer_authority(1 if is_authoritative else origin_peer)
	# Tag the throwable with its is-authoritative state so its body-
	# entered handler can gate damage.
	if "_mp_is_authoritative" in rigid:
		rigid._mp_is_authoritative = is_authoritative
	else:
		# Set via meta so older throwables without the var still work.
		rigid.set_meta("_mp_is_authoritative", is_authoritative)

	rigid.linear_velocity = velocity
