extends Node
# SyncRateConfig — autoload exposing all MP sync rates as a single
# source of truth, read from ProjectSettings at startup.
#
# WHAT THIS IS (plain English):
#
#   Every MP system (Player3D, Enemy3D, FallingVoxelCluster,
#   ProximityCutsceneManager, MultiplayerManager's ping) has its
#   own update cadence. Hardcoding those rates in each script made
#   it impossible to tune from one place; this autoload reads them
#   from project.godot's [multiplayer] section and exposes them via
#   simple getters.
#
#   Each consumer system reads on _ready (one-shot at startup).
#   Live runtime tuning (changing rates mid-session via dev menu)
#   is documented but not yet wired — operator restarts after
#   editing project.godot for now.
#
# PROJECT SETTINGS (all under [multiplayer]):
#
#   player_sync_interval         float, seconds — MultiplayerSynchronizer
#                                replication_interval for Player3D + RemotePlayer.
#                                Default 0.0 = every physics tick (~16ms).
#                                Bump to 0.05 (20Hz) if bandwidth is tight.
#
#   enemy_sync_interval          float, seconds — MultiplayerSynchronizer
#                                replication_interval for Enemy3D subclasses.
#                                Default 0.1 (10Hz). Enemy movement is slow
#                                enough that this is plenty.
#
#   cluster_sync_interval        float, seconds — MultiplayerSynchronizer
#                                replication_interval for FallingVoxelCluster.
#                                Default 0.066 (~15Hz). Mid-flight clusters
#                                move fast; this trades some bandwidth for
#                                smooth visual sync.
#
#   cutscene_membership_seconds  float, seconds — ProximityCutsceneManager
#                                re-evaluates in-radius guests at this rate.
#                                Default 0.5. Lower = snappier wander-in /
#                                wander-out at the cost of more queries.
#
#   cutscene_text_poll_seconds   float, seconds — ProximityCutsceneManager
#                                polls Dialogic state at this rate for line
#                                + speaker broadcast. Default 0.25.
#                                Lower = snappier line updates on guests.
#
#   ping_interval_seconds        (PR-F, already wired) — host's per-peer
#                                RTT ping cadence for non-Steam backends.
#                                Default 2.0.
#
#   edit_log_max_entries         (PR-F, already wired) — bound on
#                                VoxelEditManager's session log size.
#                                Default 50000.
#
# WHY ITS OWN AUTOLOAD (vs. each script reading ProjectSettings):
#
#   Single source of truth. Each consumer reading ProjectSettings
#   independently risks inconsistent defaults across files. One
#   autoload with explicit defaults + clear types simplifies
#   audits and tuning.


# =============================================================
# CONFIG (read from ProjectSettings in _ready, cached here)
# =============================================================

var player_sync_interval: float = 0.0
var enemy_sync_interval: float = 0.1
var cluster_sync_interval: float = 0.066
var cutscene_membership_seconds: float = 0.5
var cutscene_text_poll_seconds: float = 0.25


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# Read each setting with a typed default. Casting through float()
	# tolerates int values in ProjectSettings (e.g. operator typed
	# "1" instead of "1.0").
	player_sync_interval = float(ProjectSettings.get_setting(
		"multiplayer/player_sync_interval", player_sync_interval))
	enemy_sync_interval = float(ProjectSettings.get_setting(
		"multiplayer/enemy_sync_interval", enemy_sync_interval))
	cluster_sync_interval = float(ProjectSettings.get_setting(
		"multiplayer/cluster_sync_interval", cluster_sync_interval))
	cutscene_membership_seconds = float(ProjectSettings.get_setting(
		"multiplayer/cutscene_membership_seconds", cutscene_membership_seconds))
	cutscene_text_poll_seconds = float(ProjectSettings.get_setting(
		"multiplayer/cutscene_text_poll_seconds", cutscene_text_poll_seconds))

	print("[SyncRateConfig] loaded: player=%.3fs enemy=%.3fs cluster=%.3fs cutscene_member=%.3fs cutscene_text=%.3fs" % [
		player_sync_interval, enemy_sync_interval, cluster_sync_interval,
		cutscene_membership_seconds, cutscene_text_poll_seconds,
	])


# =============================================================
# HELPERS — apply per-node
# =============================================================

## Apply player_sync_interval to a MultiplayerSynchronizer node.
## Returns true if applied, false if node was null or wrong type.
func apply_to_player_synchronizer(sync_node: MultiplayerSynchronizer) -> bool:
	if sync_node == null:
		return false
	sync_node.replication_interval = player_sync_interval
	return true


## Apply enemy_sync_interval to a MultiplayerSynchronizer.
func apply_to_enemy_synchronizer(sync_node: MultiplayerSynchronizer) -> bool:
	if sync_node == null:
		return false
	sync_node.replication_interval = enemy_sync_interval
	return true


## Apply cluster_sync_interval to a MultiplayerSynchronizer.
func apply_to_cluster_synchronizer(sync_node: MultiplayerSynchronizer) -> bool:
	if sync_node == null:
		return false
	sync_node.replication_interval = cluster_sync_interval
	return true


# =============================================================
# RUNTIME TUNING (deferred — operator edits project.godot for now)
# =============================================================
#
# A live-tuning UI in MPDevMenu would be the natural next step:
#   - Sliders for each rate
#   - Apply button that walks the scene tree and calls the per-node
#     setter on every matching MultiplayerSynchronizer
# Deferred from PR J — the static read-on-_ready path covers the
# documented "configurable via ProjectSettings" deliverable. Live
# adjustment is a follow-up if scope demands it.
