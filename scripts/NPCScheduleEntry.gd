# NPCScheduleEntry.gd
# One time-block in an NPC's daily schedule.
#
# HOW TO USE:
#   1. Create NPCScheduleEntry resources inside an NPCData.tres file.
#      In the Inspector: click the "schedule" Array → Add Element → New NPCScheduleEntry.
#   2. Set time_start, time_end, and location_id for each block.
#   3. The NPC.gd script calls get_schedule_entry_for_hour() each time the
#      world clock advances, then moves the NPC to the matching SpawnPoint3D.
#
# COVERAGE RULE:
#   Entries don't have to cover every hour. If no entry matches the current hour,
#   the NPC stays in its last known position (or home position on scene load).
#
# EXAMPLE SCHEDULE for a market vendor (Aldenholt):
#   06:00–08:00  location: "vendor_home_door"    activity: IDLE
#   08:00–18:00  location: "vendor_stall"         activity: WORKING
#   18:00–20:00  location: "tavern_common"         activity: SOCIALIZING
#   20:00–06:00  location: "vendor_home_bed"       activity: SLEEPING

class_name NPCScheduleEntry
extends Resource

# ── Activity Enum ─────────────────────────────────────────────────────────────
# Describes what the NPC is doing during this time block.
# Used by bark triggers ("long_idle while SLEEPING should not bark PLAYER_NEARBY").

enum Activity {
	SLEEPING,
	EATING,
	WORKING,
	WANDERING,
	SOCIALIZING,
	GUARDING,
	IDLE
}

# ── Fields ────────────────────────────────────────────────────────────────────

## Hour (0–23) when this schedule block begins (inclusive).
@export_range(0, 23) var time_start: int = 8

## Hour (0–23) when this schedule block ends (exclusive).
## A block from 8 to 18 covers 08:00 through 17:59.
@export_range(0, 23) var time_end: int = 18

## The name of a SpawnPoint3D node in the NPC's home scene.
## The NPC will move to (or teleport to, on scene load) this point.
## Example: "vendor_stall", "chapel_pew_left", "archive_front_desk"
@export var location_id: String = ""

## What the NPC is doing during this block. Affects idle bark filtering.
@export var activity: Activity = Activity.IDLE

## Optional: override the NPC's default dialogue_timeline during this block.
## Useful for time-sensitive dialogue ("the shop is closed, come back tomorrow").
## Leave empty to use the NPCData.dialogue_timeline default.
@export var dialogue_override: String = ""
