class_name ENetBackend extends NetBackend
# ENetBackend — Godot's built-in ENetMultiplayerPeer wrapped to satisfy
# the NetBackend interface.
#
# WHAT THIS IS (plain English):
#
#   ENet is a UDP networking library that ships with Godot. No plugin,
#   no Steam — just open a port, listen for connections, you're a host.
#   The other machine connects to that port. Same machine to same
#   machine, LAN, or over the internet (with port forwarding or
#   Steam Remote Play tunneling).
#
#   We use ENet for two things:
#     1. Local dev iteration — you can spin up two Godot instances on
#        one machine and connect them via 127.0.0.1, no Steam client
#        running, no friend logged in. This is the fastest feedback
#        loop available.
#     2. Headless stress testing — once we want to test 10 peers, we
#        can launch headless Godot instances and ENet between them.
#        Steam P2P would require 10 Steam accounts; ENet doesn't.
#
#   Production play sessions go through SteamP2PBackend. ENet is the
#   developer's friend, not the player's.
#
# DEFAULT PORT:
#
#   7777. Picked because it's the Godot multiplayer convention and
#   isn't likely to collide with anything else on a dev machine.
#   Override at join time by passing "ip:port" instead of just "ip".
#
# WHY SYNCHRONOUS BUT STILL EMITS session_ready VIA call_deferred:
#
#   ENetMultiplayerPeer.create_server() returns immediately with a
#   usable peer. We could emit session_ready right inside start_host,
#   but then a caller that connects to the signal AFTER calling
#   start_host (the natural pattern) would miss the signal entirely.
#   Deferring the emit by one frame fixes that and matches the async
#   contract Steam needs anyway.


# =============================================================
# CONFIG
# =============================================================

const DEFAULT_PORT: int = 7777

## Maximum bandwidth caps in bytes/second. 0 = unlimited.
## ENet supports per-peer rate limiting; we leave it open since the
## bottleneck on a friends-only co-op session is usually upload at
## the host's home connection, not anything ENet can throttle.
const IN_BANDWIDTH: int = 0
const OUT_BANDWIDTH: int = 0


# =============================================================
# STATE
# =============================================================

var _peer: ENetMultiplayerPeer = null
var _is_host: bool = false


# =============================================================
# NetBackend OVERRIDES
# =============================================================

func is_available() -> bool:
	# ENet ships with Godot; always available.
	return true


func backend_name() -> String:
	return "ENet"


func start_host(max_peers: int) -> Error:
	# Synchronous — create the peer, emit session_ready next idle frame.
	disconnect_now()  # idempotent cleanup of any prior state

	_peer = ENetMultiplayerPeer.new()
	# create_server(port, max_clients, max_channels, in_bandwidth, out_bandwidth)
	# We leave channels and bandwidth at defaults.
	var err: Error = _peer.create_server(DEFAULT_PORT, max_peers)
	if err != OK:
		# Most common cause: port 7777 already in use (another running
		# Godot instance forgot to disconnect_now). Surface the errno.
		_peer = null
		_emit_failed_deferred("ENet create_server(port=%d) failed: %s" % [DEFAULT_PORT, error_string(err)])
		return err

	_is_host = true
	# Wire up ENet's underlying ConnectionStatus / disconnection so
	# we can forward peer joins/leaves through the NetBackend signal.
	# ENetMultiplayerPeer itself doesn't expose per-peer signals; the
	# SceneTree's MultiplayerAPI does, and MultiplayerManager hooks
	# THAT once we hand over the peer. We just emit session_ready and
	# let the upper layer wire its own listeners.
	call_deferred("_emit_ready_deferred", _peer)
	return OK


func join(target: Variant) -> Error:
	disconnect_now()

	var addr_str: String = str(target)
	var ip: String = addr_str
	var port: int = DEFAULT_PORT
	if ":" in addr_str:
		var parts: PackedStringArray = addr_str.split(":")
		ip = parts[0]
		# int() of a malformed port returns 0, which create_client will
		# reject — surfacing as session_failed with a clear message.
		port = int(parts[1])

	_peer = ENetMultiplayerPeer.new()
	var err: Error = _peer.create_client(ip, port)
	if err != OK:
		_peer = null
		_emit_failed_deferred("ENet create_client(%s:%d) failed: %s" % [ip, port, error_string(err)])
		return err

	_is_host = false
	call_deferred("_emit_ready_deferred", _peer)
	return OK


func disconnect_now() -> void:
	if _peer == null:
		return
	# close() flushes the queue and tears down the socket. If we're
	# the host this also disconnects all clients with a clean shutdown
	# packet (so they get a peer_disconnected signal rather than a
	# silent timeout).
	if _peer.has_method("close"):
		_peer.close()
	_peer = null
	_is_host = false


func get_peer_ids() -> PackedInt32Array:
	# ENetMultiplayerPeer doesn't expose a peer list directly; the
	# SceneTree's MultiplayerAPI is the source of truth. Returning
	# empty here keeps the method honest — MultiplayerManager has
	# the real list via its own peer_connected/peer_disconnected
	# tracking and exposes it to UI code.
	return PackedInt32Array()


func get_steam_id_for_peer(_peer_id: int) -> int:
	# ENet has no concept of Steam ID. Always 0.
	return 0


# =============================================================
# INTERNAL
# =============================================================

func _emit_ready_deferred(peer: MultiplayerPeer) -> void:
	# Guard against the rare case where disconnect_now() is called
	# between start_host and the deferred fire (e.g. operator hits
	# Cancel during a slow start). Don't emit a stale peer.
	if _peer != peer:
		return
	session_ready.emit(peer)
