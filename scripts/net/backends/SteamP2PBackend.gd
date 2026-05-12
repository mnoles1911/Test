class_name SteamP2PBackend extends NetBackend
# SteamP2PBackend — wraps GodotSteam's SteamMultiplayerPeer + lobby flow
# to satisfy the NetBackend interface.
#
# WHAT THIS IS (plain English):
#
#   The shipping multiplayer transport. Steam handles NAT traversal
#   via its relay servers (no port forwarding ever needed), the
#   friends list is the lobby browser (no custom server-finder UI),
#   and the Steam overlay handles invites. Friends-only lobbies mean
#   strangers can't join uninvited.
#
#   Hosting a session goes through TWO Steam concepts at once:
#     1. A Steam LOBBY — Steam's matchmaking primitive. Friends find
#        the host via this. We create one with createLobby, accept
#        invites with joinLobby. Lobby IDs are uint64.
#     2. A Steam P2P CONNECTION — Steam's actual data channel. The
#        SteamMultiplayerPeer (provided by GodotSteam) implements
#        Godot's MultiplayerPeer interface using Steam's networking
#        sockets under the hood.
#
#   Hosting flow:
#     start_host →
#       Steam.createLobby(FRIENDS_ONLY, max) →
#         async lobby_created callback →
#           SteamMultiplayerPeer.create_host() →
#             session_ready emitted with the peer
#
#   Joining flow:
#     join(lobby_id) →
#       Steam.joinLobby(lobby_id) →
#         async lobby_joined callback →
#           Steam.getLobbyOwner(lobby_id) → host's Steam ID →
#             SteamMultiplayerPeer.create_client(host_steam_id) →
#               session_ready emitted with the peer
#
# DEFENSIVE LOADING:
#
#   The GodotSteam GDExtension is NOT vendored in the repo (see
#   addons/godotsteam/INSTALL.md). This backend MUST parse and
#   instantiate cleanly even when the plugin isn't installed,
#   because:
#     - The autoload (NetTransport) tries to construct it at startup.
#     - We can't have project load fail because somebody hasn't run
#       the GodotSteam download yet.
#
#   So we do everything via reflection:
#     - `Engine.get_singleton("Steam")` resolves the Steam autoload.
#       Returns null if absent.
#     - All Steam calls go through `_steam.call("methodName", args)`.
#       Never reference `Steam.XYZ` symbols at parse time — that
#       would fail script compilation when the plugin is missing.
#     - `ClassDB.instantiate("SteamMultiplayerPeer")` creates the peer
#       without a parse-time class reference. Returns null if the
#       class isn't registered.
#     - All Steam constants are hardcoded as integers (sourced from
#       GodotSteam docs) since we can't reference Steam.LOBBY_TYPE_*
#       at parse time either.
#
#   `is_available()` returns false until the plugin is installed,
#   so MultiplayerManager will refuse host/join with a clear error.


# =============================================================
# CONSTANTS (hardcoded — see HelloSteam.gd for the same approach)
# =============================================================

# Steam lobby visibility.
const LOBBY_TYPE_PRIVATE: int = 0
const LOBBY_TYPE_FRIENDS_ONLY: int = 1
const LOBBY_TYPE_PUBLIC: int = 2
const LOBBY_TYPE_INVISIBLE: int = 3

# Steam EResult enum — 1 = OK, anything else = error.
const STEAM_RESULT_OK: int = 1

# Spacewar test app id. Real App ID gets swapped in via Steamworks
# partner setup once Mira-Thal is provisioned.
const APP_ID_SPACEWAR: int = 480

# GodotSteam createLobby result virtual port — we don't use a virtual
# port for our SteamMultiplayerPeer.create_host call; 0 means "default
# Steam channel."
const STEAM_VIRTUAL_PORT: int = 0


# =============================================================
# STATE
# =============================================================

var _steam: Object = null            # Steam singleton or null.
var _steam_initialized: bool = false # Has Steam.steamInitEx returned OK.
var _peer: MultiplayerPeer = null    # SteamMultiplayerPeer once created.
var _is_host: bool = false
var _current_lobby_id: int = 0       # 0 = no lobby. Non-zero = our lobby.
var _pending_max_peers: int = 0      # Stashed across the async createLobby.

# Tracks which signals we've connected so we don't double-connect when
# multiple sessions happen in one application run.
var _signals_wired: bool = false


# =============================================================
# CONSTRUCTION
# =============================================================

func _init() -> void:
	# Resolve the Steam singleton at construction time. NetTransport
	# instantiates this backend during its _ready, so the Engine
	# singleton table is already populated by then if the plugin is
	# loaded.
	if Engine.has_singleton("Steam"):
		_steam = Engine.get_singleton("Steam")
	# Don't initialize Steam yet — wait until host_session/join_session
	# is actually called. Initializing eagerly would slow project boot
	# for solo-play users who never touch multiplayer.


# =============================================================
# NetBackend OVERRIDES
# =============================================================

func is_available() -> bool:
	# The plugin must be present AND the SteamMultiplayerPeer class
	# must be registered. Both conditions are required because some
	# half-broken installs have one without the other.
	return _steam != null and ClassDB.class_exists("SteamMultiplayerPeer")


func backend_name() -> String:
	return "Steam P2P"


func start_host(max_peers: int) -> Error:
	disconnect_now()
	if not _ensure_initialized():
		return ERR_UNAVAILABLE

	_pending_max_peers = max_peers
	_wire_steam_signals()

	# createLobby is async — Steam will fire lobby_created once it has
	# allocated a lobby ID. We continue in _on_lobby_created.
	_steam.call("createLobby", LOBBY_TYPE_FRIENDS_ONLY, max_peers)
	return OK


func join(target: Variant) -> Error:
	disconnect_now()
	if not _ensure_initialized():
		return ERR_UNAVAILABLE

	# Lobby IDs are uint64 packed into Godot's int. Accept either int
	# or string-of-int (the dev UI's join box passes a string).
	var lobby_id: int = 0
	if typeof(target) == TYPE_INT:
		lobby_id = int(target)
	elif typeof(target) == TYPE_STRING:
		lobby_id = int(String(target).strip_edges())
	else:
		_emit_failed_deferred("Steam join target must be lobby_id (int) or stringified int, got: %s" % typeof(target))
		return ERR_INVALID_PARAMETER
	if lobby_id == 0:
		_emit_failed_deferred("Steam join: lobby_id is zero / unparseable")
		return ERR_INVALID_PARAMETER

	_wire_steam_signals()
	_steam.call("joinLobby", lobby_id)
	return OK


func disconnect_now() -> void:
	# Leave the Steam lobby first (so other members get a clean
	# leave callback), then tear down the peer.
	if _steam != null and _current_lobby_id != 0:
		_steam.call("leaveLobby", _current_lobby_id)
	_current_lobby_id = 0

	if _peer != null:
		if _peer.has_method("close"):
			_peer.close()
		_peer = null
	_is_host = false


func get_peer_ids() -> PackedInt32Array:
	# Same reasoning as ENetBackend — the SceneTree's MultiplayerAPI
	# is the source of truth; MultiplayerManager exposes it.
	return PackedInt32Array()


func get_steam_id_for_peer(peer_id: int) -> int:
	# GodotSteam's SteamMultiplayerPeer maps Godot peer_ids to Steam
	# IDs internally; the public method is `get_steam64_from_peer_id`.
	# When the plugin isn't loaded we return 0.
	if _peer == null:
		return 0
	if _peer.has_method("get_steam64_from_peer_id"):
		return int(_peer.call("get_steam64_from_peer_id", peer_id))
	return 0


# =============================================================
# STEAM INIT (lazy)
# =============================================================

func _ensure_initialized() -> bool:
	if _steam == null:
		_emit_failed_deferred("GodotSteam plugin not installed (see addons/godotsteam/INSTALL.md)")
		return false
	if _steam_initialized:
		return true
	# steamInitEx(app_id, embed_callbacks) returns Dict { status, verbal }.
	var result: Variant = _steam.call("steamInitEx", APP_ID_SPACEWAR, true)
	if typeof(result) != TYPE_DICTIONARY:
		_emit_failed_deferred("Steam.steamInitEx returned unexpected type: %s" % typeof(result))
		return false
	var status: int = int((result as Dictionary).get("status", -1))
	if status != 0:
		var verbal: String = String((result as Dictionary).get("verbal", "(no verbal)"))
		_emit_failed_deferred("Steam.steamInitEx failed: status=%d verbal=%s" % [status, verbal])
		return false
	_steam_initialized = true
	return true


# =============================================================
# STEAM SIGNAL WIRING
# =============================================================

func _wire_steam_signals() -> void:
	if _signals_wired or _steam == null:
		return
	if _steam.has_signal("lobby_created"):
		_steam.connect("lobby_created", _on_lobby_created)
	if _steam.has_signal("lobby_joined"):
		_steam.connect("lobby_joined", _on_lobby_joined)
	if _steam.has_signal("lobby_chat_update"):
		_steam.connect("lobby_chat_update", _on_lobby_chat_update)
	_signals_wired = true


# =============================================================
# STEAM SIGNAL HANDLERS
# =============================================================

func _on_lobby_created(connect_result: int, lobby_id: int) -> void:
	# Host path. connect_result is Steam's EResult — 1 = OK.
	if connect_result != STEAM_RESULT_OK:
		session_failed.emit("Steam.createLobby failed: EResult=%d" % connect_result)
		return
	_current_lobby_id = lobby_id

	# Now create the SteamMultiplayerPeer in host mode. The lobby
	# itself is matchmaking; the peer is the data channel.
	var peer_obj: Object = ClassDB.instantiate("SteamMultiplayerPeer")
	if peer_obj == null:
		session_failed.emit("ClassDB.instantiate(SteamMultiplayerPeer) returned null")
		return
	# create_host(virtual_port) returns Error. We use 0 as the virtual
	# port (Steam's default channel).
	var err: int = int(peer_obj.call("create_host", STEAM_VIRTUAL_PORT))
	if err != OK:
		session_failed.emit("SteamMultiplayerPeer.create_host failed: %s" % error_string(err))
		return
	_peer = peer_obj as MultiplayerPeer
	_is_host = true
	session_ready.emit(_peer)


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	# Client path. `response` is Steam's chat-room-enter response code;
	# 1 = success, anything else = some flavor of "no."
	if response != 1:
		session_failed.emit("Steam.joinLobby failed: response=%d" % response)
		return
	_current_lobby_id = lobby_id

	# Find the host's Steam ID via getLobbyOwner, then connect to it.
	var host_steam_id: int = 0
	if _steam.has_method("getLobbyOwner"):
		host_steam_id = int(_steam.call("getLobbyOwner", lobby_id))
	if host_steam_id == 0:
		session_failed.emit("Steam.getLobbyOwner returned 0")
		return

	var peer_obj: Object = ClassDB.instantiate("SteamMultiplayerPeer")
	if peer_obj == null:
		session_failed.emit("ClassDB.instantiate(SteamMultiplayerPeer) returned null")
		return
	var err: int = int(peer_obj.call("create_client", host_steam_id, STEAM_VIRTUAL_PORT))
	if err != OK:
		session_failed.emit("SteamMultiplayerPeer.create_client(host=%d) failed: %s" % [host_steam_id, error_string(err)])
		return
	_peer = peer_obj as MultiplayerPeer
	_is_host = false
	session_ready.emit(_peer)


func _on_lobby_chat_update(_lobby_id: int, changed_user: int, _making_change_user: int, chat_state: int) -> void:
	# Steam's lobby_chat_update fires on member join/leave/disconnect.
	# We forward as a backend_message so MultiplayerManager can use
	# Steam IDs for richer presence info than the bare Godot peer_id.
	# chat_state values (Steam enum): 1=joined, 2=left, 4=disconnected,
	# 8=kicked, 16=banned.
	backend_message.emit("lobby_chat_update", {
		"changed_user_steam_id": changed_user,
		"chat_state": chat_state,
	})


# =============================================================
# LIFECYCLE PUMP
# =============================================================
# GodotSteam's documentation recommends pumping run_callbacks() every
# frame so async Steam events deliver promptly. NetTransport (the
# autoload) calls our pump method from _process, since RefCounteds
# don't get their own _process tick.

func pump_callbacks() -> void:
	if _steam != null and _steam_initialized and _steam.has_method("run_callbacks"):
		_steam.call("run_callbacks")
