extends CharacterBody3D
class_name RemotePlayer

# MP-2: lightweight scene that represents another connected peer.
# This script does NOT read input, does NOT carry CombatXPRouter /
# VitalityXPRouter / EditToolHandler / ThrowableHandler / CameraRig
# — none of that should run for a remote player.
#
# Position + rotation come from the network via a child
# MultiplayerSynchronizer. The script itself just exposes the peer_id
# it represents and surfaces a couple of public accessors for UI
# (nametag, etc.) when that lands.

@export var peer_id: int = 0
@export var display_name: String = "Adventurer"

# Replicated by the MultiplayerSynchronizer that's added at runtime.
# Mirror Player3D's flags so a future animation system can read them
# without an extra RPC.
var is_sprinting: bool = false
var is_crouching: bool = false


func _ready() -> void:
	# A remote player is authoritative on the host, not on the local
	# peer (unless the host == local peer, in which case Player3D
	# handles it). The spawner sets the authority via
	# set_multiplayer_authority before adding to the tree; this _ready
	# only joins the group so other systems can find remote players.
	add_to_group("remote_player")
	add_to_group("player")  # tagged so existing range checks work
	_attach_sync_node()


func _attach_sync_node() -> void:
	if get_node_or_null("MPSync") != null:
		return
	var sync := MultiplayerSynchronizer.new()
	sync.name = "MPSync"
	sync.replication_interval = 0.05
	var cfg := SceneReplicationConfig.new()
	cfg.add_property(NodePath(".:position"))
	cfg.property_set_spawn(NodePath(".:position"), true)
	cfg.property_set_replication_mode(NodePath(".:position"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	cfg.add_property(NodePath(".:rotation:y"))
	cfg.property_set_spawn(NodePath(".:rotation:y"), true)
	cfg.property_set_replication_mode(NodePath(".:rotation:y"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	cfg.add_property(NodePath(".:is_sprinting"))
	cfg.property_set_replication_mode(NodePath(".:is_sprinting"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	cfg.add_property(NodePath(".:is_crouching"))
	cfg.property_set_replication_mode(NodePath(".:is_crouching"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	sync.replication_config = cfg
	add_child(sync)
