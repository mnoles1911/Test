extends Node
# CatchupCoordinator — late-join state transfer for new peers (MP-5).
#
# WHAT THIS IS (plain English):
#
#   When a guest joins a session that's already in progress, their
#   freshly-loaded world matches the procedural baseline + scene
#   defaults — not whatever the host has been playing through for
#   the last hour. WorldClock has advanced; weather has rolled to
#   overcast; GameState flags have flipped from quest progress.
#   Without explicit catch-up, the guest is in a parallel reality
#   until the next state change happens to broadcast.
#
#   This autoload runs on every peer; on HOST it listens to
#   MultiplayerManager.peer_joined and ships a one-shot snapshot
#   payload to the joining peer's id. On GUEST it ignores the
#   peer_joined signal (their own join is handled differently and
#   other peers' joins are irrelevant to them).
#
# WHAT'S IN THE SNAPSHOT (MP-5 v1):
#
#   1. WorldClock — current_day, current_hour, current_minute. The
#      guest's clock skips forward to match the host's. Re-firing
#      the hour_changed signal is intentionally NOT done in v1 — a
#      late-joiner doesn't need to retroactively trigger every bark
#      and weather roll that happened before they were there.
#
#   2. WeatherManager — current_state + intensity. Guest snaps to
#      that state without going through the 30-second transition
#      animation (which is purely cosmetic for the joining peer).
#
#   3. GameState flags — a curated subset relevant to MP gameplay.
#      Quest progress, faction disposition, region unlocks, etc.
#      For MP-5 v1 we ship the full flags dict; MP-6 polish trims
#      to only entries marked "networked = true".
#
# WHAT'S DELIBERATELY DEFERRED FROM MP-5 v1:
#
#   - Voxel chunk delta replay. The plan calls for streaming each
#     edited chunk's deltas from VoxelStreamSQLite over batched
#     RPCs. That's a meaningful subsystem on its own (worker-thread
#     sqlite reader, per-frame N-write throttle, progress UI for
#     the joining guest). Filed for MP-8 polish or a dedicated
#     follow-up; in this milestone late-joiners see the procedural
#     baseline without host edits applied. This is a known UX gap —
#     until the polish lands, the host can't show a guest the
#     dungeon they carved while solo.
#
#   - Enemy state push. Per-enemy state will naturally re-sync on
#     the next host-side state change via the MultiplayerSynchronizer.
#     For enemies that haven't moved or changed state in a while
#     (especially the dead ones — _is_dead = true won't re-fire),
#     this means the late-joiner sees the enemy in its scene-default
#     pose until something changes. Polish item for MP-8.
#
#   - Active throwables / falling clusters. Same as enemies — these
#     entities currently aren't spawned via MultiplayerSpawner, so
#     guests don't have local instances of host-side dynamic spawns.
#     The MultiplayerSpawner wiring is a separate task.
#
#   - Player position re-sync on join. The MP-2 PlayerSpawner handles
#     player spawn for new peers naturally. Positions thereafter
#     replicate via each Player3D's own MultiplayerSynchronizer.
#
# AUTOLOAD ORDER:
#   CatchupCoordinator must load AFTER MultiplayerManager, WorldClock,
#   WeatherManager, GameState. See project.godot — slotted right
#   after BloodVFX, at the end of the autoload list, so all sources
#   are guaranteed initialized when we hook signals.


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# All four dependencies must be loaded for catchup to work.
	# If any is missing, skip wiring — this autoload becomes inert.
	# That's safer than crashing project load when one of the
	# upstream autoloads gets renamed or reorganized.
	if get_node_or_null("/root/MultiplayerManager") == null:
		push_warning("[CatchupCoordinator] /root/MultiplayerManager missing — late-join catch-up disabled")
		return
	MultiplayerManager.peer_joined.connect(_on_peer_joined)


# =============================================================
# HOST PATH — send snapshot to joining peer
# =============================================================

func _on_peer_joined(peer_id: int) -> void:
	# Only the host builds + sends snapshots. Guests' own join is
	# delivered via the host's RPC, not this signal.
	if not MultiplayerManager.is_host():
		return
	# Don't send a snapshot to ourselves on session_started. The
	# host's local state IS the source of truth; sending it back to
	# host would just no-op the local applies.
	if peer_id == MultiplayerManager.local_peer_id():
		return

	var snapshot: Dictionary = _build_snapshot()
	# rpc_id(peer_id, ...) targets exactly one peer — only the new
	# guest receives this payload. Other peers don't need it.
	_rpc_apply_snapshot.rpc_id(peer_id, snapshot)
	print("[CatchupCoordinator] sent catchup snapshot to peer %d: %s" % [
		peer_id, _summarize_snapshot(snapshot),
	])


func _build_snapshot() -> Dictionary:
	var snap: Dictionary = {
		"schema_version": 1,
	}

	# WorldClock snapshot.
	if get_node_or_null("/root/WorldClock") != null:
		snap["clock"] = {
			"day":    int(WorldClock.current_day),
			"hour":   int(WorldClock.current_hour),
			"minute": int(WorldClock.current_minute),
		}

	# WeatherManager snapshot.
	if get_node_or_null("/root/WeatherManager") != null:
		snap["weather"] = {
			"state_id": int(WeatherManager.current_state),
		}

	# GameState flags subset. MP-5 v1 ships everything; MP-6 polish
	# will tag flags with "networked" and ship only those.
	if get_node_or_null("/root/GameState") != null and "flags" in GameState:
		# Defensive duplicate — never ship a live reference; we don't
		# want some downstream serializer mutating GameState.flags.
		snap["flags"] = (GameState.flags as Dictionary).duplicate(true)

	return snap


# =============================================================
# GUEST PATH — apply received snapshot
# =============================================================

@rpc("authority", "reliable")
func _rpc_apply_snapshot(snapshot: Dictionary) -> void:
	# Defense in depth — only run apply if we're a guest. Host
	# shouldn't receive its own snapshots, but the framework
	# enforces "authority" RPCs go to non-authors anyway.
	if get_node_or_null("/root/MultiplayerManager") != null and MultiplayerManager.is_host():
		return
	print("[CatchupCoordinator] applying catchup snapshot: %s" % _summarize_snapshot(snapshot))

	# Apply each section defensively — missing keys are tolerated so
	# future schema additions on the host don't break older guests.
	if snapshot.has("clock") and get_node_or_null("/root/WorldClock") != null:
		var clock: Dictionary = snapshot["clock"]
		WorldClock.current_day    = int(clock.get("day",    WorldClock.current_day))
		WorldClock.current_hour   = int(clock.get("hour",   WorldClock.current_hour))
		WorldClock.current_minute = int(clock.get("minute", WorldClock.current_minute))

	if snapshot.has("weather") and get_node_or_null("/root/WeatherManager") != null:
		WeatherManager.current_state = int(snapshot["weather"].get("state_id", WeatherManager.current_state))

	if snapshot.has("flags") and get_node_or_null("/root/GameState") != null:
		# Merge rather than replace — we don't want to wipe a guest's
		# local-only state with host's flag set. Host wins on
		# conflict (it's authoritative for any networked flag).
		var incoming: Dictionary = snapshot["flags"]
		for key in incoming.keys():
			(GameState.flags as Dictionary)[key] = incoming[key]


# =============================================================
# HELPERS
# =============================================================

func _summarize_snapshot(s: Dictionary) -> String:
	# Short one-line summary for the catchup print statements.
	# Walks the known sections; future additions show up as "+ N
	# more keys" so the log doesn't silently miss new payload types.
	var parts: Array[String] = []
	if s.has("clock"):
		var c: Dictionary = s["clock"]
		parts.append("clock=day %d %02d:%02d" % [c.get("day", 0), c.get("hour", 0), c.get("minute", 0)])
	if s.has("weather"):
		parts.append("weather=%d" % int(s["weather"].get("state_id", 0)))
	if s.has("flags"):
		parts.append("flags=%d" % (s["flags"] as Dictionary).size())
	return ", ".join(parts) if not parts.is_empty() else "(empty)"
