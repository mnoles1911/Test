extends Node
# MultiplayerManager — autoload, owns the SceneTree's multiplayer_peer.
#
# WHAT THIS IS (plain English):
#
#   The thing gameplay code asks "are we in multiplayer? am I the
#   host?" Sits between NetTransport (which knows how to make a
#   MultiplayerPeer) and the SceneTree's MultiplayerAPI (which
#   actually delivers RPCs and replicates nodes).
#
#   Three modes:
#     • OFFLINE — no multiplayer_peer assigned. Single-player.
#                 is_host() returns true (so existing code paths that
#                 ask "am I authoritative?" work without modification).
#     • HOST    — we created the session. peer_id 1 is us.
#     • CLIENT  — we joined someone else's session.
#
#   Lifecycle:
#     IDLE → host_session(N) → LOBBY_CREATING → LOBBY_READY
#       → (peers connect) → PLAYING
#     IDLE → join_session(target) → PEER_CONNECTING → HANDSHAKING
#       → (handshake completes — MP-6) → PLAYING
#     PLAYING → leave_session() → DISCONNECTING → IDLE
#
#   Right now (MP-1) the handshake is a stub: the moment a peer is
#   connected, we mark them as PLAYING. The protocol-version and
#   character-record exchange land in MP-6 (portable characters),
#   when handshake_hello / handshake_accept RPCs get added here.
#
# WHY THIS OWNS multiplayer_peer (and not NetTransport):
#
#   NetTransport's job ends when it produces a MultiplayerPeer. Wiring
#   it into the SceneTree, tracking peer connections, and exposing
#   "am I the host" is gameplay-state policy, not transport policy.
#   Splitting these means a future server-only build of NetTransport
#   doesn't need a SceneTree at all.
#
# AUTOLOAD LOAD ORDER (critical):
#
#   NetTransport must load BEFORE MultiplayerManager (we resolve it
#   in our _ready). MultiplayerManager must load BEFORE every
#   gameplay autoload that gates on `MultiplayerManager.is_host()`
#   in its own _ready — most importantly VoxelEditManager,
#   VoxelGravityManager, WaterFlowManager, WeatherManager.
#
#   Project.godot puts NetTransport + MultiplayerManager right after
#   PauseMenu, before Settings.
#
# OFFLINE-IS-HOST POLICY:
#
#   When no session is active (`_mode == OFFLINE`), `is_host()` returns
#   true and `local_peer_id()` returns 1. This is intentional: the
#   single-player game spent its entire history believing it was the
#   sole authority. Returning true preserves the existing behavior of
#   the autoloads we'll later gate (VoxelEditManager, etc.) so they
#   keep doing exactly what they did before MP existed. The MP-aware
#   gates only matter once `_mode != OFFLINE`.


# =============================================================
# ENUMS
# =============================================================

enum MP_MODE {
	OFFLINE,
	HOST,
	CLIENT,
}

enum LIFECYCLE {
	IDLE,                ## No session active.
	LOBBY_CREATING,      ## host_session called; waiting on backend.
	LOBBY_READY,         ## We have a peer, are listening for joins.
	PEER_CONNECTING,     ## join_session called; waiting on backend.
	HANDSHAKING,         ## Connected to host, exchanging hello/accept (MP-6+).
	PLAYING,             ## Normal play. RPCs flowing.
	DISCONNECTING,       ## Tear-down in progress.
}


# =============================================================
# CONSTANTS
# =============================================================

const HOST_PEER_ID: int = 1
const DEFAULT_MAX_PEERS: int = 10


# =============================================================
# STATE
# =============================================================

var _mode: MP_MODE = MP_MODE.OFFLINE
var _state: LIFECYCLE = LIFECYCLE.IDLE

## peer_id (int) -> Dictionary { display_name, joined_at_ms }
## Local peer is in the dict too (under HOST_PEER_ID for the host,
## or our assigned ID for a client). Includes the local entry so UI
## code can iterate one collection.
var peers: Dictionary = {}


# =============================================================
# SIGNALS
# =============================================================

signal session_started(mode: MP_MODE)
signal session_failed(reason: String)
signal session_ended(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal lifecycle_changed(state: LIFECYCLE)


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# We need NetTransport to be loaded before us — that's why
	# project.godot lists NetTransport first in the autoload order.
	# Crash early with a clear message if the order got broken.
	if get_node_or_null("/root/NetTransport") == null:
		push_error("[MultiplayerManager] /root/NetTransport not found. "
			+ "Check autoload order in project.godot — NetTransport must load FIRST.")
		return

	NetTransport.session_ready.connect(_on_transport_session_ready)
	NetTransport.session_failed.connect(_on_transport_session_failed)
	NetTransport.session_ended.connect(_on_transport_session_ended)

	# Hook the SceneTree's MultiplayerAPI for peer connect/disconnect
	# events. These fire whenever a remote peer joins or leaves —
	# regardless of which transport is underneath.
	multiplayer.peer_connected.connect(_on_mp_peer_connected)
	multiplayer.peer_disconnected.connect(_on_mp_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_mp_connected_to_server)
	multiplayer.connection_failed.connect(_on_mp_connection_failed)
	multiplayer.server_disconnected.connect(_on_mp_server_disconnected)


# =============================================================
# PUBLIC API — gameplay-facing predicates
# =============================================================

func is_offline() -> bool:
	return _mode == MP_MODE.OFFLINE


func is_host() -> bool:
	# OFFLINE counts as host so existing single-player gates that ask
	# "am I authoritative?" keep returning true without changes.
	# See OFFLINE-IS-HOST POLICY at top of file.
	return _mode != MP_MODE.CLIENT


func is_client() -> bool:
	return _mode == MP_MODE.CLIENT


func mode() -> MP_MODE:
	return _mode


func lifecycle() -> LIFECYCLE:
	return _state


func local_peer_id() -> int:
	if _mode == MP_MODE.OFFLINE:
		return HOST_PEER_ID
	return multiplayer.get_unique_id()


func remote_peer_count() -> int:
	# Excludes the local peer.
	return peers.size() - (1 if peers.has(local_peer_id()) else 0)


# =============================================================
# PUBLIC API — session control
# =============================================================

func host_session(max_peers: int = DEFAULT_MAX_PEERS) -> Error:
	if _state != LIFECYCLE.IDLE:
		push_warning("[MultiplayerManager] host_session called in state %s — ignoring" % LIFECYCLE.keys()[_state])
		return ERR_ALREADY_IN_USE
	_set_state(LIFECYCLE.LOBBY_CREATING)
	var err: Error = NetTransport.start_host(max_peers)
	if err != OK:
		# NetTransport will emit session_failed via its async path; we
		# return the sync error code too so the caller can show an
		# immediate hint without waiting for the signal.
		return err
	return OK


func join_session(target: Variant) -> Error:
	if _state != LIFECYCLE.IDLE:
		push_warning("[MultiplayerManager] join_session called in state %s — ignoring" % LIFECYCLE.keys()[_state])
		return ERR_ALREADY_IN_USE
	_set_state(LIFECYCLE.PEER_CONNECTING)
	var err: Error = NetTransport.join(target)
	if err != OK:
		return err
	return OK


## MP-8 — host-only. Disconnects a specific peer from the session.
## No-op on guests, in OFFLINE, or if peer_id isn't currently
## connected. The kicked peer receives the standard
## server_disconnected event and bounces to their main menu via
## NetTestWorldBootstrap (or whatever world they're in).
##
## A friendly note: the underlying disconnect_peer doesn't give
## the recipient a reason string. If you need to tell them WHY they
## got kicked, RPC a kick_reason message first, then disconnect on
## a short delay so the message has time to deliver.
func kick_peer(peer_id: int, reason: String = "") -> bool:
	if not is_host():
		push_warning("[MultiplayerManager] kick_peer called on non-host; ignoring")
		return false
	if peer_id == HOST_PEER_ID:
		push_warning("[MultiplayerManager] cannot kick the host (peer_id 1); ignoring")
		return false
	if not peers.has(peer_id):
		push_warning("[MultiplayerManager] kick_peer: peer %d not in peers dict; ignoring" % peer_id)
		return false
	# Send a courtesy "you got kicked" RPC first so the recipient can
	# show a message before the disconnect. We don't yet have a UI
	# slot for this; printing on the kicked peer's machine is fine
	# for MP-8. Reliable channel — dropping this would be confusing.
	if not reason.is_empty():
		_rpc_kick_notice.rpc_id(peer_id, reason)
	# disconnect_peer is exposed on both ENetMultiplayerPeer and
	# SteamMultiplayerPeer in Godot 4. Defensive check anyway.
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null:
		return false
	if peer.has_method("disconnect_peer"):
		peer.call("disconnect_peer", peer_id)
		print("[MultiplayerManager] kicked peer %d (reason: %s)" % [peer_id, reason if not reason.is_empty() else "(none)"])
		return true
	push_warning("[MultiplayerManager] active peer doesn't expose disconnect_peer")
	return false


## Reads the round-trip latency to a peer if the underlying transport
## supports it. ENetMultiplayerPeer exposes
## `get_peer().peer.get_packet_loss_pct()` and timing through the
## ENetConnection; GodotSteam's SteamMultiplayerPeer has a
## `get_peer_latency` method. Returns -1 if unknown.
##
## Used by MPDevMenu's per-peer ping display.
func get_peer_latency_ms(peer_id: int) -> int:
	if peer_id == local_peer_id():
		return 0
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null:
		return -1
	# GodotSteam SteamMultiplayerPeer
	if peer.has_method("get_peer_latency"):
		return int(peer.call("get_peer_latency", peer_id))
	# Generic ENet path — return -1; MP-8 doesn't add a custom
	# heartbeat-RPC ping mechanism for the ENet backend yet, that's
	# a polish item. A future RPC-based ping (send timestamp, peer
	# echoes, compute delta) would work for any backend.
	return -1


# MP-8 RPC — host sends a courtesy disconnect-reason to a kicked peer
# before yanking their connection. The recipient just prints (the
# disconnect happens within ~one frame so any UI handler would barely
# render anyway).
@rpc("authority", "reliable")
func _rpc_kick_notice(reason: String) -> void:
	print("[MultiplayerManager] You were kicked by host. Reason: %s" % reason)


func leave_session(reason: String = "") -> void:
	if _state == LIFECYCLE.IDLE:
		return
	_set_state(LIFECYCLE.DISCONNECTING)
	NetTransport.disconnect_now()
	# Drop the SceneTree peer immediately so further RPCs no-op
	# rather than queueing into nothing.
	multiplayer.multiplayer_peer = null
	_clear_peers()
	_mode = MP_MODE.OFFLINE
	_set_state(LIFECYCLE.IDLE)
	session_ended.emit(reason)


# =============================================================
# NetTransport SIGNAL HANDLERS
# =============================================================

func _on_transport_session_ready(peer: MultiplayerPeer) -> void:
	# The backend has produced a usable peer. Hand it to the SceneTree.
	multiplayer.multiplayer_peer = peer

	if _state == LIFECYCLE.LOBBY_CREATING:
		_mode = MP_MODE.HOST
		_set_state(LIFECYCLE.LOBBY_READY)
		# Add ourselves to the peers dict so UI shows "1 connected"
		# even when no guests have joined yet.
		_add_peer(HOST_PEER_ID, _local_display_name())
		session_started.emit(_mode)
		# Hosts move straight to PLAYING — no waiting required.
		_set_state(LIFECYCLE.PLAYING)
	elif _state == LIFECYCLE.PEER_CONNECTING:
		# Client side: wait for connected_to_server to fire (the SceneTree
		# multiplayer API delivers that once the connection is fully up).
		_set_state(LIFECYCLE.HANDSHAKING)


func _on_transport_session_failed(reason: String) -> void:
	push_warning("[MultiplayerManager] transport reported session_failed: %s" % reason)
	# Clean rollback to IDLE regardless of which lifecycle stage we
	# were in.
	multiplayer.multiplayer_peer = null
	_clear_peers()
	_mode = MP_MODE.OFFLINE
	_set_state(LIFECYCLE.IDLE)
	session_failed.emit(reason)


func _on_transport_session_ended(reason: String) -> void:
	# Fired by the backend when it tears itself down (e.g. Steam
	# lobby leave). leave_session() already handles the local
	# cleanup; this is just for backend-initiated tear-downs.
	if _state == LIFECYCLE.IDLE:
		return
	multiplayer.multiplayer_peer = null
	_clear_peers()
	_mode = MP_MODE.OFFLINE
	_set_state(LIFECYCLE.IDLE)
	session_ended.emit(reason)


# =============================================================
# SceneTree.MultiplayerAPI SIGNAL HANDLERS
# =============================================================

func _on_mp_peer_connected(peer_id: int) -> void:
	# Fires on host when a guest connects, AND on guest when other
	# guests connect (the host's id 1 is also delivered to clients).
	_add_peer(peer_id, "peer_%d" % peer_id)
	peer_joined.emit(peer_id)


func _on_mp_peer_disconnected(peer_id: int) -> void:
	_remove_peer(peer_id)
	peer_left.emit(peer_id)


func _on_mp_connected_to_server() -> void:
	# Client-only — fired once we have a confirmed connection. Add
	# ourselves to the peers dict.
	_mode = MP_MODE.CLIENT
	_add_peer(local_peer_id(), _local_display_name())
	session_started.emit(_mode)
	# Move into HANDSHAKING; the handshake hello RPC drives the
	# transition to PLAYING (or back to IDLE if host rejects).
	_set_state(LIFECYCLE.HANDSHAKING)
	_send_handshake_hello()


# PR-A handshake — client sends hello with their CharacterRecord;
# host runs CharacterValidator and replies with accept/reject.
#
# For this milestone the handshake is INFORMATIONAL — even on
# validation failure the session proceeds (with default inventory
# on the failing client). Hard rejection (host disconnects the
# peer + shows reason) is a future polish item; it requires also
# wiring a brief UI delay so the kicked client can see the reason
# before the disconnect lands.

const PROTOCOL_VERSION: int = 1

func _send_handshake_hello() -> void:
	# Wrap in a try-style guard — CharacterStore may not be loaded
	# in degraded environments (test harnesses).
	var record_dict: Dictionary = {}
	if get_node_or_null("/root/CharacterStore") != null:
		var rec = CharacterStore.get_active_character()
		if rec != null:
			# Serialize the record to a Dictionary for safe transport.
			# Resources marshal natively in Godot 4 RPC, but Dictionary
			# is more tolerant of future schema additions.
			record_dict = _serialize_character(rec)
	_rpc_handshake_hello.rpc_id(HOST_PEER_ID, PROTOCOL_VERSION, record_dict)


# Client → host. Host validates and replies via _rpc_handshake_accept
# or _rpc_handshake_reject. The hello is sent to peer 1 (host) only.
@rpc("any_peer", "reliable")
func _rpc_handshake_hello(protocol_v: int, record_dict: Dictionary) -> void:
	if not is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if protocol_v != PROTOCOL_VERSION:
		_rpc_handshake_reject.rpc_id(sender, "protocol mismatch: server=%d, client=%d" % [PROTOCOL_VERSION, protocol_v])
		return
	# Validate the character record. We deserialize back to a
	# CharacterRecord, run the validator, and send back a sanitized
	# Dictionary the client adopts.
	var record = _deserialize_character(record_dict)
	if record == null:
		# Client didn't send a record (or it was corrupt). Accept
		# without character data — they'll use InventoryManager defaults.
		_rpc_handshake_accept.rpc_id(sender, {})
		print("[MultiplayerManager] handshake_hello from %d: no character, accepting with defaults" % sender)
		return
	# Run validator (RefCounted, host-side only — no autoload).
	var validator_class = load("res://scripts/net/CharacterValidator.gd")
	var result: Dictionary = validator_class.validate(record, {})
	if not bool(result.get("ok", false)):
		_rpc_handshake_reject.rpc_id(sender, String(result.get("reason", "validation failed")))
		print("[MultiplayerManager] handshake_hello from %d REJECTED: %s" % [sender, result.get("reason", "?")])
		return
	# Accept with the sanitized record so the client can adopt any
	# clamps the validator applied (over-cap skills, illegal items).
	var sanitized = result.get("sanitized", record)
	_rpc_handshake_accept.rpc_id(sender, _serialize_character(sanitized))
	if (result.get("warnings", PackedStringArray()) as PackedStringArray).size() > 0:
		print("[MultiplayerManager] handshake_hello from %d accepted with warnings: %s" % [sender, result["warnings"]])
	else:
		print("[MultiplayerManager] handshake_hello from %d accepted clean" % sender)


# Host → client. Carries the sanitized record back to the client so
# they can adopt the validator's clamps. Empty dict means accept
# with defaults (no character data sent).
@rpc("authority", "reliable")
func _rpc_handshake_accept(sanitized_record: Dictionary) -> void:
	if not sanitized_record.is_empty() and get_node_or_null("/root/CharacterStore") != null:
		var adopted = _deserialize_character(sanitized_record)
		if adopted != null:
			CharacterStore.select_character(adopted)
			if get_node_or_null("/root/InventoryManager") != null:
				InventoryManager.load_from_character_record(adopted)
	_set_state(LIFECYCLE.PLAYING)


# Host → client. Validation failed; PR-A leaves the session running
# (just logs). Future: surface to UI + leave_session.
@rpc("authority", "reliable")
func _rpc_handshake_reject(reason: String) -> void:
	push_warning("[MultiplayerManager] host rejected handshake: %s" % reason)
	# PR-A informational behavior: keep playing with default inventory.
	# A future polish PR adds a UI hook + leave_session on hard reject.
	_set_state(LIFECYCLE.PLAYING)


# Serialize CharacterRecord → Dictionary for transport. Mirrors
# CharacterRecord's @export schema. Future schema_version bumps
# add fields here without breaking older clients (extra keys
# tolerated by _deserialize_character via .get).
func _serialize_character(rec) -> Dictionary:
	return {
		"schema_version":   rec.schema_version,
		"steam_id":         rec.steam_id,
		"character_id":     rec.character_id,
		"display_name":     rec.display_name,
		"created_unix":     rec.created_unix,
		"last_played_unix": rec.last_played_unix,
		"appearance":       rec.appearance,
		"skill_levels":     rec.skill_levels,
		"perks":            rec.perks,
		"inventory_items":  rec.inventory_items,
		"equipped":         rec.equipped,
		"gold":             rec.gold,
		"play_time_seconds": rec.play_time_seconds,
	}


func _deserialize_character(d: Dictionary):
	if d.is_empty():
		return null
	var record_class = load("res://scripts/net/CharacterRecord.gd")
	var rec = record_class.new()
	rec.schema_version    = int(d.get("schema_version", 1))
	rec.steam_id          = int(d.get("steam_id", 0))
	rec.character_id      = String(d.get("character_id", ""))
	rec.display_name      = String(d.get("display_name", "Wanderer"))
	rec.created_unix      = int(d.get("created_unix", 0))
	rec.last_played_unix  = int(d.get("last_played_unix", 0))
	rec.appearance        = d.get("appearance", {})
	rec.skill_levels      = d.get("skill_levels", {})
	rec.perks             = d.get("perks", PackedStringArray())
	rec.inventory_items   = d.get("inventory_items", [])
	rec.equipped          = d.get("equipped", {})
	rec.gold              = int(d.get("gold", 0))
	rec.play_time_seconds = int(d.get("play_time_seconds", 0))
	return rec


func _on_mp_connection_failed() -> void:
	# Client-side: tried to connect, never got there (timeout, host
	# refused, transport unavailable).
	_on_transport_session_failed("connection failed (host unreachable or refused)")


func _on_mp_server_disconnected() -> void:
	# Client-side: we were connected, the host went away.
	_on_transport_session_ended("host disconnected")


# =============================================================
# INTERNAL — peer dict management
# =============================================================

func _add_peer(peer_id: int, display_name: String) -> void:
	peers[peer_id] = {
		"display_name": display_name,
		"joined_at_ms": Time.get_ticks_msec(),
	}


func _remove_peer(peer_id: int) -> void:
	peers.erase(peer_id)


func _clear_peers() -> void:
	peers.clear()


# =============================================================
# INTERNAL — state machine
# =============================================================

func _set_state(s: LIFECYCLE) -> void:
	if _state == s:
		return
	_state = s
	lifecycle_changed.emit(s)


# =============================================================
# INTERNAL — display name resolution
# =============================================================

func _local_display_name() -> String:
	# Prefer the Steam persona name if the Steam backend is active and
	# initialized. Falls back to "Player" otherwise (will be replaced
	# in MP-6 once CharacterStore lands and we have a chosen
	# character with a display_name).
	if NetTransport.backend_id() == NetTransport.BACKEND_STEAM:
		var sid: int = NetTransport.get_steam_id_for_peer(local_peer_id())
		if sid != 0:
			# We have a steam id; steam persona name comes via the
			# Steam singleton directly (NetTransport doesn't expose
			# it because it's a Steam-specific concept).
			if Engine.has_singleton("Steam"):
				var steam_obj: Object = Engine.get_singleton("Steam")
				if steam_obj.has_method("getPersonaName"):
					return String(steam_obj.call("getPersonaName"))
	return "Player"
