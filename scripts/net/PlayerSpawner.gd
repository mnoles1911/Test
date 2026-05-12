extends Node
class_name PlayerSpawner

# MP-2: tracks remote-peer presence and spawns/despawns RemotePlayer
# nodes for every other connected peer. Attach this as a child of the
# scene root (or any node under the active world); the spawner finds
# the MultiplayerManager autoload, listens to its peer events, and
# parents RemotePlayer instances to the configured world_root.
#
# Local peer: NOT spawned by this script. The local player is whatever
# Player3D the scene already contains (or no player at all in dev
# scenes). PlayerSpawner only handles OTHERS.

const REMOTE_PLAYER_SCENE := preload("res://scenes/player/RemotePlayer.tscn")

@export var world_root_path: NodePath = NodePath("..")
@export var spawn_position: Vector3 = Vector3.ZERO

# peer_id -> RemotePlayer instance
var _remote_players: Dictionary = {}


func _ready() -> void:
	var mp: Node = get_node_or_null("/root/MultiplayerManager")
	if mp == null:
		push_warning("[PlayerSpawner] MultiplayerManager autoload missing.")
		return
	# MultiplayerManager exposes peer_joined / peer_left signals
	# (re-broadcasts of the raw multiplayer.peer_connected /
	# peer_disconnected events). Subscribe and replay current peers
	# so a spawner added mid-session still catches up.
	if mp.has_signal("peer_joined"):
		mp.peer_joined.connect(_on_peer_joined)
	elif mp.has_signal("peer_connected"):
		mp.peer_connected.connect(_on_peer_joined)
	if mp.has_signal("peer_left"):
		mp.peer_left.connect(_on_peer_left)
	elif mp.has_signal("peer_disconnected"):
		mp.peer_disconnected.connect(_on_peer_left)
	# Catch up: any peer already in MultiplayerManager.peers that
	# isn't us gets a RemotePlayer right now.
	if "peers" in mp:
		var local: int = int(mp.local_peer_id()) if mp.has_method("local_peer_id") else 1
		for pid in (mp.get("peers") as Dictionary).keys():
			if int(pid) != local:
				_spawn_remote(int(pid))


func _on_peer_joined(peer_id: int) -> void:
	if get_node_or_null("/root/MultiplayerManager"):
		var local: int = int(MultiplayerManager.local_peer_id())
		if peer_id == local:
			return  # local peer is handled by Player3D, not this spawner
	_spawn_remote(peer_id)


func _on_peer_left(peer_id: int) -> void:
	if _remote_players.has(peer_id):
		var node: Node = _remote_players[peer_id]
		if is_instance_valid(node):
			node.queue_free()
		_remote_players.erase(peer_id)


func _spawn_remote(peer_id: int) -> void:
	if _remote_players.has(peer_id):
		return
	var inst: Node = REMOTE_PLAYER_SCENE.instantiate()
	inst.name = "RemotePlayer_%d" % peer_id
	if "peer_id" in inst:
		inst.set("peer_id", peer_id)
	# Authority is the remote peer's id — their Player3D owns the
	# data; we just receive replication.
	inst.set_multiplayer_authority(peer_id)
	var root: Node = get_node_or_null(world_root_path)
	if root == null:
		root = get_parent()
	root.add_child(inst)
	if "global_position" in inst:
		inst.set("global_position", spawn_position)
	_remote_players[peer_id] = inst
	print("[PlayerSpawner] Spawned RemotePlayer for peer %d at %s" % [peer_id, spawn_position])


# Public accessor for dev UI.
func get_remote_player_count() -> int:
	return _remote_players.size()
