# WorldClock.gd
# Autoload singleton. Manages in-game time and drives NPC daily schedules.
#
# REGISTER AS AUTOLOAD:
#   Project Settings → Autoload → add WorldClock.gd with node name "WorldClock"
#
# HOW IN-GAME TIME WORKS:
#   The clock ticks in real seconds and converts to game minutes and hours.
#   Default rate: 120 real seconds = 1 game hour, so a full day takes 48 real minutes.
#   Change "real_seconds_per_game_hour" in the Inspector to speed up or slow down time.
#
# WHAT IT DOES EACH TICK:
#   1. Advances game minutes and hours.
#   2. On each new game hour: writes "world_hour" to GameState, calls
#      update_schedule(hour) on every node in the "scheduled_npcs" group.
#   3. On time-of-day transitions (Dawn, Dusk, etc.): emits time_of_day_changed signal
#      so bark triggers and lighting systems can react.
#   4. On a new day: emits day_changed signal.
#
# PAUSING THE CLOCK:
#   The clock pauses automatically when the game is paused (get_tree().paused == true).
#   It also pauses when Dialogic is running a timeline (checked each frame).
#   You can also pause/resume it manually: WorldClock.set_paused(true/false).
#
# SAVE AND LOAD:
#   Call WorldClock.save() before writing a save file.
#   Call WorldClock.load_from_state() after loading a save file.
#   Time is stored in GameState flags: "world_hour", "world_minute", "world_day".
#
# DEBUG:
#   Call WorldClock.set_time(hour, minute) from the GDScript REPL or DebugOverlay
#   to jump to any time instantly. The schedule update fires immediately.

extends Node

# ── Signals ───────────────────────────────────────────────────────────────────

## Fires every time the game hour advances. hour is 0–23.
signal hour_changed(hour: int)

## Fires every time the day rolls over (hour 23 → hour 0).
signal day_changed(day: int)

## Fires when the time-of-day period changes (e.g. DAWN → MORNING).
## period is one of: "DEEP_NIGHT", "DAWN", "MORNING", "AFTERNOON", "DUSK", "NIGHT"
signal time_of_day_changed(period: String)

# ── Configuration ─────────────────────────────────────────────────────────────

## How many real seconds equal one in-game hour.
## 75   = 75 real seconds per game hour → full day in 30 real minutes.
## 150  = 2.5 real minutes per game hour → full day in 60 real minutes (default).
## 240  = 4 real minutes per game hour  → full day in 96 real minutes (very slow).
## 12   = 12 real seconds per game hour → full day in ~5 real minutes (debug speed).
@export var real_seconds_per_game_hour: float = 150.0

## The hour the game starts at on a fresh save (default: 8 AM).
@export_range(0, 23) var start_hour: int = 8

## The minute the game starts at on a fresh save.
@export_range(0, 59) var start_minute: int = 0

# ── Time State ────────────────────────────────────────────────────────────────

## Current in-game hour (0–23). Read-only from outside; use set_time() to change.
var current_hour: int = 8

## Current in-game minute (0–59). Read-only from outside; use set_time() to change.
var current_minute: int = 0

## How many in-game days have passed since the start of the game (starts at 1).
var current_day: int = 1

# ── Internal ──────────────────────────────────────────────────────────────────

# Accumulated real seconds within the current game minute.
var _seconds_accumulator: float = 0.0

# Computed from real_seconds_per_game_hour — how many real seconds per game minute.
var _real_seconds_per_game_minute: float = 2.0

# Whether the clock is manually paused (separate from the game pause state).
var _manual_pause: bool = false

# The time-of-day period as of the last hour change. Compared each hour to detect transitions.
var _last_period: String = ""

# ── Time-of-Day Periods ───────────────────────────────────────────────────────
# These match the trigger categories in design/BARK_LIBRARY.md (Category 3).
# Bark lines for "Time of day (dawn, dusk, deep night)" fire on time_of_day_changed.

const TIME_OF_DAY_PERIODS: Dictionary = {
	"DEEP_NIGHT": [0, 1, 2, 3, 4],
	"DAWN":       [5, 6, 7],
	"MORNING":    [8, 9, 10, 11],
	"AFTERNOON":  [12, 13, 14, 15, 16],
	"DUSK":       [17, 18, 19],
	"NIGHT":      [20, 21, 22, 23],
}

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_real_seconds_per_game_minute = real_seconds_per_game_hour / 60.0

	# Restore time from a loaded save, or start fresh.
	# GameState.get_flag returns its default (false / bool) when a
	# flag is unset — pass "" so the type is consistent and the
	# emptiness check works as a "not yet saved" signal.
	var saved_hour: String = str(GameState.get_flag("world_hour", ""))
	if saved_hour != "":
		load_from_state()
	else:
		current_hour   = start_hour
		current_minute = start_minute
		current_day    = 1
		_write_state()

	_last_period = get_time_of_day_period()

func _process(delta: float) -> void:
	# Profiling wrapper — see CLAUDE.md pattern.
	var _t0_prof := Time.get_ticks_usec()
	_process_inner(delta)
	var prof := get_node_or_null("/root/Profiler")
	if prof != null:
		prof.record("WORLD", "WorldClock", Time.get_ticks_usec() - _t0_prof)


func _process_inner(delta: float) -> void:
	# Don't tick if paused manually, game-paused, or Dialogic is running.
	if _manual_pause:
		return
	if get_tree().paused:
		return
	if _dialogic_is_running():
		return

	_seconds_accumulator += delta

	# Check if a full game minute has passed.
	if _seconds_accumulator >= _real_seconds_per_game_minute:
		_seconds_accumulator -= _real_seconds_per_game_minute
		_advance_minute()

# ── Clock Advancement ─────────────────────────────────────────────────────────

func _advance_minute() -> void:
	current_minute += 1

	if current_minute >= 60:
		current_minute = 0
		_advance_hour()

func _advance_hour() -> void:
	current_hour += 1

	if current_hour >= 24:
		current_hour = 0
		current_day += 1
		_write_state()
		emit_signal("day_changed", current_day)
	else:
		_write_state()

	emit_signal("hour_changed", current_hour)
	_update_npc_schedules()
	_check_time_of_day_transition()

# ── NPC Schedule Dispatch ──────────────────────────────────────────────────────

func _update_npc_schedules() -> void:
	# All NPC nodes that should move on a schedule must be in the "scheduled_npcs" group.
	# Add an NPC node to the group via the Node panel → Groups tab in the Godot editor.
	var npcs := get_tree().get_nodes_in_group("scheduled_npcs")
	for npc in npcs:
		if npc.has_method("update_schedule"):
			npc.update_schedule(current_hour)

# ── Time-of-Day Transition ────────────────────────────────────────────────────

func _check_time_of_day_transition() -> void:
	var new_period := get_time_of_day_period()
	if new_period != _last_period:
		_last_period = new_period
		emit_signal("time_of_day_changed", new_period)
		# Also write the period to GameState so Dialogic conditions can read it.
		GameState.set_flag("time_of_day", new_period)

# ── GameState Persistence ─────────────────────────────────────────────────────

func _write_state() -> void:
	# These flags are read by NPC.gd (_get_active_schedule_entry) and by Dialogic conditions.
	GameState.set_flag("world_hour",   str(current_hour))
	GameState.set_flag("world_minute", str(current_minute))
	GameState.set_flag("world_day",    str(current_day))

## Call this after loading a save file to restore the saved time.
func load_from_state() -> void:
	current_hour   = int(GameState.get_flag("world_hour"))
	current_minute = int(GameState.get_flag("world_minute"))
	current_day    = int(GameState.get_flag("world_day"))
	if current_day == 0:
		current_day = 1
	_last_period = get_time_of_day_period()
	# Fire a schedule update immediately so NPCs jump to the right positions.
	_update_npc_schedules()

## Call this before writing a save file. Ensures the latest values are in GameState.
func save() -> void:
	_write_state()

# ── Public API ────────────────────────────────────────────────────────────────

## Pause or unpause the clock manually (independent of game pause).
## Use this if a cutscene or special event should freeze time.
func set_paused(paused: bool) -> void:
	_manual_pause = paused

## Returns true if the clock is currently advancing.
func is_running() -> bool:
	return not _manual_pause and not get_tree().paused

## Jump to a specific time instantly. Fires all signals as if time had advanced normally.
## Useful from the DebugOverlay or the GDScript REPL during development.
##   WorldClock.set_time(18, 0)  ← jump to 6:00 PM
func set_time(hour: int, minute: int = 0) -> void:
	current_hour   = clamp(hour, 0, 23)
	current_minute = clamp(minute, 0, 59)
	_seconds_accumulator = 0.0
	_write_state()
	emit_signal("hour_changed", current_hour)
	_update_npc_schedules()
	_check_time_of_day_transition()

## Advance time by a given number of in-game hours immediately.
## Useful for "rest until morning" or fast-travel time skips.
##   WorldClock.advance_hours(8)  ← skip 8 game hours
func advance_hours(hours: int) -> void:
	var target_hour: int = (current_hour + hours) % 24
	# Integer truncation IS what we want here — days_elapsed is the
	# whole-number count of days crossed by the time skip.
	@warning_ignore("integer_division")
	var days_elapsed: int = (current_hour + hours) / 24
	if days_elapsed > 0:
		current_day += days_elapsed
		emit_signal("day_changed", current_day)
	set_time(target_hour, current_minute)

## Returns the current time as a formatted string.
## Example: get_time_string() → "14:30"
func get_time_string() -> String:
	return "%02d:%02d" % [current_hour, current_minute]

## Returns the current time-of-day period label.
## Possible values: "DEEP_NIGHT", "DAWN", "MORNING", "AFTERNOON", "DUSK", "NIGHT"
func get_time_of_day_period() -> String:
	for period in TIME_OF_DAY_PERIODS.keys():
		if current_hour in TIME_OF_DAY_PERIODS[period]:
			return period
	return "NIGHT"

## Returns true if it is currently daytime (DAWN through DUSK, inclusive).
func is_daytime() -> bool:
	return current_hour >= 5 and current_hour <= 19

## Returns true if it is currently nighttime.
func is_nighttime() -> bool:
	return not is_daytime()

## Returns how far through the current game minute we are, as a value in [0.0, 1.0).
## Each game minute takes _real_seconds_per_game_minute real seconds, and
## _seconds_accumulator tracks how many have elapsed so far in this minute.
## DayNightCycle uses this so celestial bodies move smoothly every frame
## instead of jumping once per minute.
func get_minute_fraction() -> float:
	if _real_seconds_per_game_minute <= 0.0:
		return 0.0
	return clamp(_seconds_accumulator / _real_seconds_per_game_minute, 0.0, 1.0)

# ── Internal Helpers ──────────────────────────────────────────────────────────

func _dialogic_is_running() -> bool:
	# Dialogic sets its own paused/active state. Check if a timeline is running
	# so the clock doesn't tick during conversations.
	var dialogic := get_node_or_null("/root/Dialogic")
	if dialogic == null:
		return false
	# Dialogic 2 exposes `current_timeline` when a timeline is active.
	return dialogic.current_timeline != null
