extends Node
# PlayerSpawner — manages player-node instantiation across peers.
#
# WHAT THIS IS (plain English):
#
#   Sits in the world scene tree (typically under a "Players" Node).
#   Listens to MultiplayerManager and ensures that on EVERY peer's
#   machine, there is exactly one player node per active peer:
#
#     • Local peer's node is a full Player3D.tscn (camera, input,
#       full controller).
#     • Each remote peer's node is a lightweight RemotePlayer.tscn
#       (mesh + collision + MultiplayerSynchronizer, no camera or
#       input).
#
#   The set_multiplayer_authority(peer_id) call right after instantiate
#   tells Godot which peer is allowed to drive that node's synced
#   state. Once the local Player3D moves, its MultiplayerSynchronizer
#   broadcasts new positions, and the corresponding RemotePlayer
#   puppets on other machines snap to the new transform.
#
# WHY NOT MultiplayerSpawner:
#
#   Godot's MultiplayerSpawner replicates spawn operations — one
#   call on the authoritative peer fans out to all other peers. That
#   would be a fine fit here EXCEPT it spawns the same scene type
#   everywhere, which conflicts with our local-Player3D /
#   remote-RemotePlayer asymmetry. We'd have to spawn a placeholder
#   and locally swap, which is more ceremony than just having each
#   peer listen to peer_connected and instantiate the right scene
#   for itself.
#
#   The trade-off: this script needs to be in the scene on every
#   peer. PlayerSpawner.gd is added to NetTestWorld.tscn (and any
#   future MP world scenes) so every peer's tree runs it on _ready.
#
# LIFECYCLE:
#
#   _ready              → connect to MultiplayerManager signals.
#                         If a session is already active when we
#                         load (we entered the world scene AFTER
#                         host/join completed), spawn for everyone
#                         we know about right now.
#   session_started     → spawn local player + every already-known
#                         remote peer.
#   peer_joined(X)      → spawn a RemotePlayer for X (or no-op if
#                         X is us).
#   peer_left(X)        → free the node for X.
#   session_ended       → free everything we spawned.
#
# WHY MATCHING NODE PATHS MATTER:
#
#   Each player node is named "Player_<peer_id>" (e.g. "Player_1",
#   "Player_2147483647"). The MultiplayerSynchronizer on the
#   authoritative peer's Player3D broadcasts to peers — Godot routes
#   the packet by the synchronizer's full node path. So the puppet
#   on the receiver MUST live at the same path. Both Player3D and
#   RemotePlayer add under "<this PlayerSpawner>/Player_<id>" so the
#   path is `.../PlayerSpawner/Player_<id>` everywhere.
#
# OFFLINE BEHAVIOR:
#
#   If MultiplayerManager.is_offline() is true at _ready, we still
#   spawn a local Player3D so single-player tests work in this scene
#   without needing to start a session. set_multiplayer_authority(1)
#   matches the OFFLINE-IS-HOST policy.


# =============================================================
# CONFIG
# =============================================================

## Scene to instantiate for the local peer. Defaults to Player3D.tscn
## but can be swapped via the inspector for variant test scenes.
@export var local_player_scene: PackedScene = preload("res://scenes/Player3D.tscn")

## Scene to instantiate for remote peers. Defaults to the lightweight
## RemotePlayer.tscn. Same swap freedom for tests.
@export var remote_player_scene: PackedScene = preload("res://scenes/player/RemotePlayer.tscn")

## Spawn position for new players. Set in the inspector or via
## set_spawn_point() before session_started fires. All peers spawn
## at the same point in MP-2; spawn-spreading lands in MP-8.
@export var spawn_point: Vector3 = Vector3.ZERO


# =============================================================
# STATE
# =============================================================

## peer_id -> Node instance currently in the tree.
var _player_nodes: Dictionary = {}


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# Defensive guard — if MultiplayerManager isn't loaded for any
	# reason (autoload order broken, running this scene in isolation),
	# fall back to OFFLINE behavior: spawn a local player at the
	# spawn point and call it a day.
	if get_node_or_null("/root/MultiplayerManager") == null:
		push_warning("[PlayerSpawner] /root/MultiplayerManager not found — spawning local player in OFFLINE fallback mode")
		_spawn_player_for(1)
		return

	MultiplayerManager.session_started.connect(_on_session_started)
	MultiplayerManager.session_ended.connect(_on_session_ended)
	MultiplayerManager.peer_joined.connect(_on_peer_joined)
	MultiplayerManager.peer_left.connect(_on_peer_left)

	# Catch up if we entered the scene AFTER host/join completed —
	# session_started won't fire a second time, so re-derive from
	# current state.
	if MultiplayerManager.is_offline():
		# Single-player or pre-session — spawn ourselves at peer 1.
		_spawn_player_for(1)
	else:
		_on_session_started(int(MultiplayerManager.mode()))


# =============================================================
# SIGNAL HANDLERS
# =============================================================

func _on_session_started(_mode: int) -> void:
	var me: int = MultiplayerManager.local_peer_id()
	_spawn_player_for(me)
	for pid in MultiplayerManager.peers.keys():
		if pid != me:
			_spawn_player_for(pid)


func _on_session_ended(_reason: String) -> void:
	for n in _player_nodes.values():
		if is_instance_valid(n):
			n.queue_free()
	_player_nodes.clear()


func _on_peer_joined(peer_id: int) -> void:
	# peer_joined fires for every peer including ourselves; skip self
	# to avoid double-spawning the local player.
	if peer_id == MultiplayerManager.local_peer_id():
		return
	_spawn_player_for(peer_id)


func _on_peer_left(peer_id: int) -> void:
	if not _player_nodes.has(peer_id):
		return
	var n: Node = _player_nodes[peer_id]
	if is_instance_valid(n):
		n.queue_free()
	_player_nodes.erase(peer_id)


# =============================================================
# SPAWN
# =============================================================

func _spawn_player_for(peer_id: int) -> void:
	if _player_nodes.has(peer_id):
		return  # idempotent — already spawned for this peer

	var is_local: bool = peer_id == _resolve_local_peer_id()
	var scene: PackedScene = local_player_scene if is_local else remote_player_scene
	if scene == null:
		push_error("[PlayerSpawner] No scene configured for %s player" % ["local" if is_local else "remote"])
		return

	var node: Node = scene.instantiate()
	# Naming is load-bearing — MultiplayerSynchronizer routes packets by
	# full node path, so all peers must agree on the path. See header.
	node.name = "Player_%d" % peer_id

	# Authority must be set BEFORE add_child so MultiplayerSynchronizer's
	# initial spawn packet carries the correct authority. Otherwise the
	# remote puppet briefly believes the local peer is authoritative and
	# the first sync packet from the real authority gets rejected.
	node.set_multiplayer_authority(peer_id)

	add_child(node)

	# Position the spawn. Only the authority writes — for remote
	# puppets, the first sync packet from the owning peer will overwrite
	# this immediately, but we still set it to avoid one frame of
	# being-at-origin flicker.
	if node is Node3D:
		(node as Node3D).global_position = spawn_point

	_player_nodes[peer_id] = node
	print("[PlayerSpawner] spawned %s for peer %d at %s" % [
		"Player3D" if is_local else "RemotePlayer",
		peer_id,
		spawn_point,
	])


# =============================================================
# HELPERS
# =============================================================

func _resolve_local_peer_id() -> int:
	# When MultiplayerManager is loaded, defer to its local_peer_id().
	# Falls back to multiplayer.get_unique_id() (which is 1 in OFFLINE
	# mode by default) when running this scene in isolation.
	if get_node_or_null("/root/MultiplayerManager") != null:
		return MultiplayerManager.local_peer_id()
	return multiplayer.get_unique_id()


## Public API — useful for dev scripts that want to override the
## spawn point after the world scene loads. Has no effect on already-
## spawned players (they keep their current transform).
func set_spawn_point(p: Vector3) -> void:
	spawn_point = p
