extends Node
# NetTransport — autoload that picks and owns the active NetBackend.
#
# WHAT THIS IS (plain English):
#
#   The single seam between gameplay code and the actual transport
#   library. Gameplay never imports or instantiates a backend; it
#   talks to MultiplayerManager, which talks to NetTransport, which
#   delegates to one of:
#     • ENetBackend     — Godot's built-in UDP, used for LAN dev.
#     • SteamP2PBackend — GodotSteam, used for shipping co-op.
#     • DedicatedBackend — future, for a headless server build.
#
#   Which backend is active is a project setting:
#     multiplayer/backend = "enet" (default) | "steam"
#
#   That can be overridden at runtime by calling `select_backend("steam")`
#   before any host/join — useful for an in-game "Play with Friends"
#   button that picks Steam regardless of the dev setting.
#
# WHY ITS OWN AUTOLOAD (instead of folding into MultiplayerManager):
#
#   Two responsibilities, two scripts:
#     - NetTransport: "give me a working MultiplayerPeer using
#       <chosen transport>." Cares about Steam vs ENet vs future
#       dedicated. Doesn't care about gameplay state.
#     - MultiplayerManager: "I am hosting / joining a session,
#       these are my peers, here's the SceneTree's multiplayer_peer
#       hooked up." Cares about session state. Doesn't care which
#       library is doing the transport.
#
#   Keeping them split means a future dedicated-server build only
#   touches NetTransport (add a backend, default the project setting).
#   The existing MultiplayerManager works without modification.
#
# AUTOLOAD ORDER:
#   NetTransport must be registered BEFORE MultiplayerManager (which
#   queries it during its own _ready). Both must be BEFORE
#   VoxelEditManager (which checks MultiplayerManager.is_host() to
#   gate writes). See project.godot autoload section.
#
# WHY pump_callbacks ON _process:
#   GodotSteam's run_callbacks() must be pumped each frame so async
#   Steam events fire promptly. The Steam backend is a RefCounted
#   and doesn't get its own _process tick — we pump it from here.
#   ENetBackend doesn't need pumping; the call is a no-op.


# =============================================================
# CONSTANTS
# =============================================================

## Project-setting key. Default value lives in project.godot under
## the [multiplayer] section. Override at runtime via select_backend().
const SETTING_BACKEND_KEY: String = "multiplayer/backend"
const BACKEND_ENET: String = "enet"
const BACKEND_STEAM: String = "steam"


# =============================================================
# STATE
# =============================================================

var _backend: NetBackend = null
var _backend_id: String = ""


# =============================================================
# SIGNALS (re-broadcasts of the active backend's signals so that
# downstream listeners — primarily MultiplayerManager — can connect
# to NetTransport once and not have to re-wire every time the
# backend changes.)
# =============================================================

signal session_ready(peer: MultiplayerPeer)
signal session_failed(reason: String)
signal session_ended(reason: String)
signal peer_connection_changed(peer_id: int, connected: bool)
signal backend_message(kind: String, payload: Dictionary)


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# Pick the backend named in project.godot. If the setting is
	# missing (fresh install before MP-1 lands the project setting
	# update), default to ENet so dev work isn't blocked.
	var requested: String = String(ProjectSettings.get_setting(SETTING_BACKEND_KEY, BACKEND_ENET))
	select_backend(requested)


func _process(_delta: float) -> void:
	# Steam needs its callbacks pumped every frame. ENet doesn't.
	# Cheap to call unconditionally — the Steam backend's pump is
	# itself a no-op when Steam isn't initialized.
	if _backend != null and _backend.has_method("pump_callbacks"):
		_backend.call("pump_callbacks")


# =============================================================
# BACKEND SELECTION
# =============================================================

## Swap the active backend. Tears down any in-flight session on the
## previous backend first. Safe to call repeatedly.
func select_backend(backend_id: String) -> void:
	if _backend != null and _backend_id == backend_id:
		return
	if _backend != null:
		_backend.disconnect_now()
		_unwire_backend_signals()
		_backend = null
	_backend_id = backend_id
	_backend = _instantiate_backend(backend_id)
	if _backend == null:
		push_error("[NetTransport] Unknown backend '%s' — falling back to ENet" % backend_id)
		_backend_id = BACKEND_ENET
		_backend = ENetBackend.new()
	_wire_backend_signals()
	print("[NetTransport] backend=%s available=%s" % [_backend.backend_name(), _backend.is_available()])


func _instantiate_backend(backend_id: String) -> NetBackend:
	match backend_id:
		BACKEND_ENET:
			return ENetBackend.new()
		BACKEND_STEAM:
			return SteamP2PBackend.new()
	return null


func _wire_backend_signals() -> void:
	if _backend == null:
		return
	_backend.session_ready.connect(_on_session_ready)
	_backend.session_failed.connect(_on_session_failed)
	_backend.session_ended.connect(_on_session_ended)
	_backend.peer_connection_changed.connect(_on_peer_connection_changed)
	_backend.backend_message.connect(_on_backend_message)


func _unwire_backend_signals() -> void:
	if _backend == null:
		return
	# Disconnect-if-connected pattern. Avoids errors if select_backend
	# is called twice in a row before any session was started.
	if _backend.session_ready.is_connected(_on_session_ready):
		_backend.session_ready.disconnect(_on_session_ready)
	if _backend.session_failed.is_connected(_on_session_failed):
		_backend.session_failed.disconnect(_on_session_failed)
	if _backend.session_ended.is_connected(_on_session_ended):
		_backend.session_ended.disconnect(_on_session_ended)
	if _backend.peer_connection_changed.is_connected(_on_peer_connection_changed):
		_backend.peer_connection_changed.disconnect(_on_peer_connection_changed)
	if _backend.backend_message.is_connected(_on_backend_message):
		_backend.backend_message.disconnect(_on_backend_message)


# =============================================================
# PUBLIC API (delegates to active backend)
# =============================================================

func backend_name() -> String:
	return _backend.backend_name() if _backend != null else "(none)"


func backend_id() -> String:
	return _backend_id


func is_backend_available() -> bool:
	return _backend != null and _backend.is_available()


func start_host(max_peers: int) -> Error:
	if _backend == null:
		_emit_failed_deferred("NetTransport: no backend selected")
		return ERR_UNCONFIGURED
	if not _backend.is_available():
		_emit_failed_deferred("NetTransport: backend '%s' is not available on this machine" % backend_name())
		return ERR_UNAVAILABLE
	return _backend.start_host(max_peers)


func join(target: Variant) -> Error:
	if _backend == null:
		_emit_failed_deferred("NetTransport: no backend selected")
		return ERR_UNCONFIGURED
	if not _backend.is_available():
		_emit_failed_deferred("NetTransport: backend '%s' is not available on this machine" % backend_name())
		return ERR_UNAVAILABLE
	return _backend.join(target)


func disconnect_now() -> void:
	if _backend != null:
		_backend.disconnect_now()


func get_peer_ids() -> PackedInt32Array:
	return _backend.get_peer_ids() if _backend != null else PackedInt32Array()


func get_steam_id_for_peer(peer_id: int) -> int:
	return _backend.get_steam_id_for_peer(peer_id) if _backend != null else 0


# =============================================================
# SIGNAL FORWARDERS
# =============================================================

func _on_session_ready(peer: MultiplayerPeer) -> void:
	session_ready.emit(peer)


func _on_session_failed(reason: String) -> void:
	push_warning("[NetTransport] session_failed: %s" % reason)
	session_failed.emit(reason)


func _on_session_ended(reason: String) -> void:
	session_ended.emit(reason)


func _on_peer_connection_changed(peer_id: int, connected: bool) -> void:
	peer_connection_changed.emit(peer_id, connected)


func _on_backend_message(kind: String, payload: Dictionary) -> void:
	backend_message.emit(kind, payload)


func _emit_failed_deferred(reason: String) -> void:
	# Same async-emit pattern as NetBackend — guarantees signals fire
	# even when callers connect after the failing call.
	call_deferred("emit_signal", "session_failed", reason)
