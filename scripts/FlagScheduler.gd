extends Node
# FlagScheduler — Autoload. Schedule flags to be set after a delay or on an event.
#
# What this does in plain English:
#   Sometimes a story beat should happen "a little while after" an event,
#   not instantly. For example: "three seconds after Roland reads the letter,
#   set a flag that makes Henrietta's expression change." Or: "the next time
#   the player opens the journal after meeting Tomlin, unlock a new quest entry."
#
#   This script lets you schedule those without writing timer logic every time.
#
# TWO TYPES:
#
#   1. TIMED — fires after X seconds of real game time.
#      FlagScheduler.after(3.0, "henrietta_reacts", true)
#
#   2. DEFERRED (event-based) — fires the next time a specific event is emitted.
#      FlagScheduler.on_event("journal_opened", "tomlin_quest_unlocked", true)
#      Then somewhere: FlagScheduler.emit_event("journal_opened")
#
# Both types call GameState.set_flag() when they fire.
# Scheduled flags are NOT saved to disk — they're in-memory only for the session.
# If the player saves and loads, any pending scheduled flags are lost. That's
# intentional: use narrative script logic to re-create them at scene load if needed.


# =============================================================
# SIGNAL
# =============================================================

signal game_event(event_name: String)
# Emit this to trigger any deferred flags waiting for that event name.
# Use FlagScheduler.emit_event("journal_opened") rather than calling emit() directly
# so it prints a debug log.


# =============================================================
# INTERNAL STORAGE
# =============================================================

# Each timed entry: { "flag": String, "value": Variant, "remaining": float, "id": int }
var _timed: Array = []

# Each deferred entry: { "flag": String, "value": Variant, "event": String, "id": int }
var _deferred: Array = []

var _next_id: int = 0


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	print("[FlagScheduler] Initialized.")


func _process(delta: float) -> void:
	# Tick all timed flags.
	if _timed.is_empty():
		return

	var fired: Array = []
	for entry in _timed:
		entry["remaining"] -= delta
		if entry["remaining"] <= 0.0:
			fired.append(entry)

	for entry in fired:
		_timed.erase(entry)
		_fire(entry["flag"], entry["value"], "timed (id=%d)" % entry["id"])


# =============================================================
# PUBLIC API
# =============================================================

func after(seconds: float, flag_name: String, value = true) -> int:
	# Schedule a flag to be set after `seconds` real game time.
	# Returns an ID you can use to cancel it with cancel(id).
	var id: int = _next_id
	_next_id += 1
	_timed.append({
		"flag": flag_name,
		"value": value,
		"remaining": seconds,
		"id": id,
	})
	print("[FlagScheduler] Timed flag '%s' = %s in %.1fs (id=%d)" % [flag_name, str(value), seconds, id])
	return id


func on_event(event_name: String, flag_name: String, value = true) -> int:
	# Schedule a flag to be set the next time emit_event(event_name) is called.
	# Returns an ID you can use to cancel it with cancel(id).
	var id: int = _next_id
	_next_id += 1
	_deferred.append({
		"event": event_name,
		"flag": flag_name,
		"value": value,
		"id": id,
	})
	print("[FlagScheduler] Deferred flag '%s' = %s on event '%s' (id=%d)" % [flag_name, str(value), event_name, id])
	return id


func emit_event(event_name: String) -> void:
	# Call this to trigger all deferred flags waiting for this event name.
	# E.g. FlagScheduler.emit_event("journal_opened")
	print("[FlagScheduler] Event: '%s'" % event_name)

	var fired: Array = []
	for entry in _deferred:
		if entry["event"] == event_name:
			fired.append(entry)

	for entry in fired:
		_deferred.erase(entry)
		_fire(entry["flag"], entry["value"], "event '%s' (id=%d)" % [event_name, entry["id"]])

	emit_signal("game_event", event_name)


func cancel(id: int) -> bool:
	# Cancel a scheduled flag by its ID. Returns true if found and removed.
	for entry in _timed:
		if entry["id"] == id:
			_timed.erase(entry)
			print("[FlagScheduler] Cancelled timed id=%d" % id)
			return true
	for entry in _deferred:
		if entry["id"] == id:
			_deferred.erase(entry)
			print("[FlagScheduler] Cancelled deferred id=%d" % id)
			return true
	return false


func cancel_all_for_flag(flag_name: String) -> void:
	# Cancel all scheduled entries that would set a given flag name.
	_timed = _timed.filter(func(e): return e["flag"] != flag_name)
	_deferred = _deferred.filter(func(e): return e["flag"] != flag_name)


func pending_count() -> int:
	return _timed.size() + _deferred.size()


# =============================================================
# INTERNAL
# =============================================================

func _fire(flag_name: String, value, reason: String) -> void:
	print("[FlagScheduler] Firing '%s' = %s  [reason: %s]" % [flag_name, str(value), reason])
	GameState.set_flag(flag_name, value)
