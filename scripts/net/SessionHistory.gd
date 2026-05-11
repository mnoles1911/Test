extends Node
# SessionHistory — small autoload that remembers the last join target
# so the operator can rejoin with one click.
#
# WHAT THIS IS (plain English):
#
#   After a guest leaves a session (cleanly via Leave button, or
#   forcibly via host kick / server_disconnected), this autoload
#   stores the connection target they were last connected to:
#
#     - ENet:  "ip:port"  string  e.g. "127.0.0.1:7777"
#     - Steam: lobby_id (uint64)
#
#   The NetTest UI reads this on _ready and shows a "Rejoin Last"
#   button when present. One-click rejoin is the polished version
#   of "remember what I typed last time."
#
# WHY ITS OWN AUTOLOAD:
#
#   Could live on MultiplayerManager but MM is already large and
#   the persistence concern (file I/O on disconnect) is unrelated
#   to lifecycle. Keeping it separate makes both files easier to
#   read.
#
# FILE LOCATION:
#
#   user://session_history.cfg
#
#   ConfigFile rather than .tres so it's human-readable and edits
#   easily. Schema is tiny:
#
#     [last_session]
#     backend = "enet" | "steam"
#     target  = String | int   (ip:port or lobby_id)
#     timestamp = int unix     (so we can age out stale entries)
#
# STALENESS:
#
#   Entries older than STALE_AFTER_SECONDS (24h default) are treated
#   as absent so the operator doesn't accidentally rejoin a server
#   that's been offline overnight.


# =============================================================
# CONFIG
# =============================================================

const HISTORY_PATH: String = "user://session_history.cfg"
const STALE_AFTER_SECONDS: int = 86400  # 24 hours


# =============================================================
# STATE
# =============================================================

var _backend: String = ""
var _target: Variant = null
var _timestamp: int = 0


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	_load_from_disk()
	# Hook MultiplayerManager so we capture connection targets at the
	# moment of session_started + clear on session_ended (for now we
	# keep entries persisted; clearing on disconnect is debatable —
	# operator may want to reconnect after a crash).
	if get_node_or_null("/root/MultiplayerManager") != null:
		MultiplayerManager.session_started.connect(_on_session_started)


# =============================================================
# PUBLIC API
# =============================================================

## Record the connection target. Called by NetTest / NetTransport
## right before / right after a connect attempt. Backend is the
## NetTransport backend_id ("enet" / "steam").
func record_target(backend: String, target: Variant) -> void:
	_backend = backend
	_target = target
	_timestamp = Time.get_unix_time_from_system()
	_save_to_disk()


## Returns true if a non-stale last-target is available for rejoin.
func has_recent_target() -> bool:
	if _backend.is_empty() or _target == null:
		return false
	if Time.get_unix_time_from_system() - _timestamp > STALE_AFTER_SECONDS:
		return false
	return true


## { backend: String, target: Variant, timestamp: int } or empty dict.
func get_last_target() -> Dictionary:
	if not has_recent_target():
		return {}
	return {
		"backend": _backend,
		"target": _target,
		"timestamp": _timestamp,
	}


## Clear the persisted entry (e.g. after a hard reject — don't
## suggest rejoining a session that just refused us).
func clear_history() -> void:
	_backend = ""
	_target = null
	_timestamp = 0
	_save_to_disk()


# =============================================================
# INTERNALS
# =============================================================

func _on_session_started(mode: int) -> void:
	# Only CLIENT (joined a host) is worth recording. HOST is the
	# operator hosting their own lobby — re-clicking Host works
	# without a remembered target, so we skip.
	if mode != MultiplayerManager.MP_MODE.CLIENT:
		return
	# We don't have direct access to the join target here — NetTest
	# captures it explicitly via record_target() before/after the
	# .join call. This handler is just a safety hook in case future
	# auto-rejoin flows need it.


func _save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("last_session", "backend", _backend)
	cfg.set_value("last_session", "target", _target)
	cfg.set_value("last_session", "timestamp", _timestamp)
	var err: Error = cfg.save(HISTORY_PATH)
	if err != OK:
		push_warning("[SessionHistory] save failed: %s" % err)


func _load_from_disk() -> void:
	if not FileAccess.file_exists(HISTORY_PATH):
		return
	var cfg := ConfigFile.new()
	var err: Error = cfg.load(HISTORY_PATH)
	if err != OK:
		push_warning("[SessionHistory] load failed: %s" % err)
		return
	_backend = String(cfg.get_value("last_session", "backend", ""))
	_target = cfg.get_value("last_session", "target", null)
	_timestamp = int(cfg.get_value("last_session", "timestamp", 0))
