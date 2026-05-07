class_name LockData
extends Resource
# LockData — a Resource that describes a single lock in the world.
#
# What this does in plain English:
#   Every locked chest, door, or container has a LockData resource assigned
#   to it in the Inspector. This resource tells the lockpicking system how
#   hard the lock is, how many pins it has, whether a key exists, and what
#   Roland says when he examines it up close.
#
# HOW TO USE IN THE EDITOR:
#   1. Select a LockObject3D node in your scene.
#   2. In the Inspector, find the "Lock Data" export.
#   3. Click the dropdown → "New LockData" to create one inline,
#      OR click the folder icon to load a saved .tres file.
#   4. Fill in the fields below.
#
# HOW TO SAVE AS A REUSABLE .tres FILE:
#   After creating a LockData inline, click the floppy disk icon next to
#   the resource in the Inspector and save it to /assets/locks/.
#   That way the same lock difficulty can be shared across many objects.


# ─── CORE FIELDS ───────────────────────────────────────────────────────────

@export var lock_id: String = "lock_default"
# A unique string that identifies this specific lock across saves.
# The game stores "picked_<lock_id>" as a flag so it knows which locks
# Roland has already opened (no XP awarded for the same lock twice).
# Convention: "chest_caer_001", "door_archive_north", etc.

@export_enum("Easy", "Medium", "Hard", "Very Hard") var tier: int = 0
# How difficult this lock is.
#   Easy     — 1 pin, wide resonance zone (~40°). Novice Roland can do this.
#   Medium   — 2 pins, narrower zones (~25°). A bit of practice required.
#   Hard     — 3 pins, narrow zones (~15°), 1 false resonance.
#   Very Hard — 3 pins, very narrow zones (~8°), 2 false resonances.
# Skill tier widens forgiveness (hold timer), but not the zone itself.

@export var pin_count: int = 1
# Number of real pins to find and set. Normally set automatically by tier
# (Easy=1, Medium=2, Hard=3, Very Hard=3), but you can override here.
# Valid range: 1–3.

# ─── OPTIONAL FIELDS ───────────────────────────────────────────────────────

@export var key_item_id: String = ""
# If a key exists for this lock, put its item_id here (e.g. "archive_key").
# Leave blank if the lock can only be picked. A key opens the lock instantly
# and silently — no minigame. The key is consumed on use.

@export var quest_critical: bool = false
# If true, the lock is always pickable regardless of Roland's skill level.
# Story will never gate the player behind a lock they cannot attempt.
# (The attempt will still be difficult — just guaranteed to be possible.)

@export_multiline var examine_bark: String = ""
# Optional: What Roland says when the player examines this lock with E
# (without picks equipped). Leave blank to use the tier default:
#   Easy:      "Cheap iron. I could open this with a bent nail."
#   Medium:    "Standard work. Two pins, maybe."
#   Hard:      "Three pins at least. Someone put thought into this."
#   Very Hard: "Masterwork cylinder. Fine tolerances. Steady hands and luck."
