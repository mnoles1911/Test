class_name NetBackend extends RefCounted
# NetBackend — abstract transport backend for multiplayer.
#
# WHAT THIS IS (plain English):
#
#   This is the interface that every transport implementation must
#   satisfy. The plan calls for three backends:
#
#     • ENetBackend     — Godot's built-in ENet UDP peer. Works on LAN
#                         out of the box. Used for dev iteration and
#                         can also tunnel over Steam Remote Play if
#                         friends-without-the-plugin ever happens.
#     • SteamP2PBackend — Wraps GodotSteam's SteamMultiplayerPeer. Steam
#                         relay handles NAT, Steam friends list is the
#                         lobby browser. The shipping path for co-op.
#     • DedicatedBackend (future) — Headless Godot server hosted on
#                         infra we control. Not implemented in the MVP.
#
#   Gameplay code never touches a backend directly. It calls
#   MultiplayerManager (host_session / join_session / leave_session)
#   which calls NetTransport (the autoload) which calls the concrete
#   backend instance through this abstract interface.
#
# WHY AN INTERFACE AT ALL:
#
#   We want to swap transports without touching the 6,000 lines of
#   gameplay code that follow. Splitting GodotSteam-specific code into
#   one .gd file behind this interface makes the rest of the codebase
#   reusable for a future dedicated server or a LAN-only fallback.
#
# THE LIFECYCLE:
#
#   1. NetTransport instantiates one concrete backend at _ready() based
#      on the multiplayer/backend project setting.
#   2. MultiplayerManager.host_session() calls backend.start_host(N).
#      The backend returns OK to mean "I have started the process"
#      (the actual peer may not be ready yet — Steam lobby creation is
#      async). The backend will emit `session_ready` once a usable
#      MultiplayerPeer exists, or `session_failed` if it gave up.
#   3. MultiplayerManager assigns the peer to the SceneTree's
#      multiplayer_peer once session_ready fires.
#   4. As remote peers join/leave, the backend emits
#      `peer_connection_changed(peer_id, connected)`. NetTransport
#      forwards this; MultiplayerManager updates its peer record.
#   5. MultiplayerManager.leave_session() calls backend.disconnect_now()
#      which tears down lobbies / sockets / Steam state and emits
#      `session_ended`.
#
# WHY return Error and emit signals (instead of returning the peer):
#
#   Steam lobby creation is asynchronous — createLobby() returns
#   immediately and Steam delivers the lobby_created callback some
#   milliseconds later. We don't want to leak that asynchrony into the
#   caller's flow. By using "start the thing now, signal when ready"
#   the same pattern works for both ENet (synchronous; signal fires
#   next idle frame) and Steam (async; signal fires whenever Steam is
#   ready). Callers always wait on `session_ready` and stop caring how
#   long it took.
#
# NOT YET HANDLED AT THIS LAYER (will land in later milestones):
#
#   • Handshake (protocol version + character record exchange) —
#     that lives on MultiplayerManager since it's transport-agnostic.
#   • Catch-up snapshot — same: MultiplayerManager / CatchupCoordinator.
#   • Reconnect / host migration — out of MVP scope.
#
# All concrete backends inherit from this class and override every
# method. Methods left as-is here just emit `session_failed` so a
# half-implemented backend doesn't silently no-op.


# =============================================================
# SIGNALS
# =============================================================

## Emitted when start_host or join has produced a usable MultiplayerPeer.
## NetTransport forwards this to MultiplayerManager which then assigns
## the peer to the SceneTree.
signal session_ready(peer: MultiplayerPeer)

## Emitted when the backend tried to start a session and failed
## (lobby creation failed, host unreachable, plugin missing, etc.).
## `reason` is a human-readable string suitable for the dev UI's
## status label.
signal session_failed(reason: String)

## Emitted when the session ends gracefully (disconnect_now or remote
## host quit). `reason` may be empty for a clean local disconnect.
signal session_ended(reason: String)

## Forwarded from the backend's underlying transport whenever a remote
## peer joins or leaves. `peer_id` is the SceneTree-level multiplayer
## ID (matches multiplayer.get_unique_id() on the remote machine).
## `connected` = true on join, false on leave/timeout/kick.
signal peer_connection_changed(peer_id: int, connected: bool)

## Backend-specific message that doesn't map to a connection event —
## e.g. Steam lobby data updated, a chat message arrived on a
## non-Godot channel. MVP just logs; later milestones may route some
## of these into MultiplayerManager.
signal backend_message(kind: String, payload: Dictionary)


# =============================================================
# PUBLIC API (override in concrete backends)
# =============================================================

## Returns true if this backend can run on the current machine. ENet
## is always available; Steam is only available if the GodotSteam
## GDExtension is installed AND steam_appid.txt is present in the
## working directory.
##
## MultiplayerManager checks this before attempting host/join so the
## dev UI can show a clear "Steam plugin not installed" message
## instead of just silently failing.
func is_available() -> bool:
	return false


## A human-readable identifier for logging. e.g. "ENet", "Steam P2P".
func backend_name() -> String:
	return "AbstractBackend"


## Start hosting a session that accepts up to `max_peers` clients.
##
## Returns OK to mean "I've started the process of becoming a host."
## The session is NOT ready yet — wait for `session_ready` or
## `session_failed`. Returning anything other than OK means the
## attempt failed synchronously (e.g. plugin missing); no signals will
## fire in that case.
##
## For ENet: synchronously creates a server peer and emits
## session_ready next idle frame. For Steam: kicks off
## Steam.createLobby and emits session_ready when the lobby_created
## callback comes back.
func start_host(_max_peers: int) -> Error:
	_emit_failed_deferred("Backend.start_host not implemented")
	return ERR_UNAVAILABLE


## Join an existing session.
##
## `target` is backend-specific:
##   • ENet:  String "ip:port" or just "ip" (default port 7777)
##   • Steam: int lobby_id (uint64 packed into Godot's int)
##
## Same async contract as start_host: returns OK to mean "process
## started", then emits session_ready or session_failed.
func join(_target: Variant) -> Error:
	_emit_failed_deferred("Backend.join not implemented")
	return ERR_UNAVAILABLE


## Tear down the current session. Closes sockets, leaves Steam
## lobbies, frees peers. Idempotent — safe to call when no session
## is active.
func disconnect_now() -> void:
	pass


## Snapshot of currently connected peer IDs (excludes local peer).
## Used by MultiplayerManager + dev UI for status display.
func get_peer_ids() -> PackedInt32Array:
	return PackedInt32Array()


## Map a SceneTree peer_id to a Steam ID (uint64). Returns 0 for
## non-Steam backends. Used by CharacterStore on host validation
## to key portable character files by Steam ID rather than per-
## session peer_id (peer_ids reset every session).
func get_steam_id_for_peer(_peer_id: int) -> int:
	return 0


# =============================================================
# INTERNAL HELPERS
# =============================================================

func _emit_failed_deferred(reason: String) -> void:
	# Async-style failure so callers always observe the same
	# "kick off → signal" flow even when the failure is synchronous.
	# Otherwise callers that connect to session_failed AFTER calling
	# start_host (the typical pattern) would miss the signal.
	call_deferred("emit_signal", "session_failed", reason)
