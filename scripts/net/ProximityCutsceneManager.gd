extends Node
# ProximityCutsceneManager — mirrors host's Dialogic to in-radius guests.
#
# WHAT THIS IS (plain English):
#
#   Dialogic runs ONLY on the host's machine. When the host triggers
#   a dialogue scene, this autoload decides which guests are close
#   enough to participate (per the trigger's cutscene_pull_radius
#   export, default 20m) and mirrors the dialogue UI to them. Guests
#   outside the radius keep playing freely — they aren't dragged
#   into Roland's conversation just because they're online.
#
#   For pulled-in guests:
#     • Their Player3D input is suppressed (cutscene flag).
#     • A read-only CutsceneMirror.tscn overlay shows the current
#       speaker + line text as host advances through Dialogic.
#     • Only the host can advance / make choices; guests see them
#       in a grayed-out state.
#     • On timeline end, the overlay closes and input resumes.
#
# MEMBERSHIP RE-EVALUATION:
#   Every CHECK_INTERVAL_SECONDS (0.5s) host recomputes the in-radius
#   set:
#     • New entrants get cutscene_begin and the overlay fades in.
#     • Exiters get cutscene_end and the overlay fades out.
#   This is what makes "wander into a cutscene" and "walk away to
#   opt out" both work without explicit triggers.
#
# WHAT'S TRACKED PER ACTIVE CUTSCENE:
#   • timeline_id        — Dialogic timeline name (string)
#   • origin             — Vector3, captured at trigger fire time
#   • radius             — float meters, 0 = host-only, -1 = all
#   • participating      — Set of peer_id who are currently in
#
# WIRE FORMAT:
#   _rpc_cutscene_begin(timeline_id, origin, radius)
#   _rpc_cutscene_text(speaker, line)
#   _rpc_cutscene_end(timeline_id)
#
#   Bark broadcasts and proximity-cutscene line broadcasts share the
#   same unreliable channel for chat-style updates; the begin/end
#   pair is reliable because dropping it would leave the guest stuck
#   in cutscene mode forever.
#
# WHAT'S DELIBERATELY DEFERRED FROM MP-7 v1:
#
#   - Host-camera mirroring. The per-trigger `mirror_host_camera`
#     flag in the plan would sync the host's camera transform to
#     pulled-in guests at 30Hz so they share the framing. Doable
#     but adds bandwidth and a new sync vector; v1 lets guests
#     keep their free camera.
#
#   - Save lockout. Plan calls for host's save button to disable
#     while a cutscene is active. The save UI hook lands when MP
#     save flow is finalized (currently single-player saves use
#     GameState.save_game and don't query active cutscenes).
#
#   - Choices grayed-out on guest. v1 overlay is text-only —
#     speaker name + line. Choices ship when Dialogic 2 choice
#     events are wired to fire a signal we can hook.


# =============================================================
# CONFIG
# =============================================================

## Defaults. Overridden at _ready from SyncRateConfig if loaded —
## PR-J brought these under ProjectSettings control so operators
## can tune cutscene responsiveness without editing source.
const CHECK_INTERVAL_SECONDS_DEFAULT: float = 0.5
const POLL_INTERVAL_SECONDS_DEFAULT: float = 0.25
var CHECK_INTERVAL_SECONDS: float = CHECK_INTERVAL_SECONDS_DEFAULT
var POLL_INTERVAL_SECONDS: float = POLL_INTERVAL_SECONDS_DEFAULT

## Default pull radius used when DialogueTrigger3D doesn't specify
## one. 20m matches the plan's recommendation — generous enough
## that a guest standing nearby is included but not so wide that
## a guest fighting goblins across the courtyard gets pulled into
## a quiet conversation.
const DEFAULT_RADIUS_METERS: float = 20.0


# =============================================================
# STATE
# =============================================================

class ActiveCutscene:
	var timeline_id: String
	var origin: Vector3
	var radius: float
	var participating: Dictionary  # peer_id -> true

	func _init(p_timeline: String, p_origin: Vector3, p_radius: float) -> void:
		timeline_id = p_timeline
		origin = p_origin
		radius = p_radius
		participating = {}


var _active: ActiveCutscene = null
var _check_accumulator: float = 0.0
var _poll_accumulator: float = 0.0

# Last broadcast (speaker, line). Used to skip re-broadcasting the
# same Dialogic state if nothing has changed since the last poll.
var _last_speaker: String = ""
var _last_line: String = ""
# PR-B — last choices broadcast. Choices are an Array of String
# labels (e.g. ["Help her", "Walk away", "Ask why"]). Empty array
# means no choice is currently pending. Sent only on transition.
var _last_choices: PackedStringArray = PackedStringArray()


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	if get_node_or_null("/root/MultiplayerManager") == null:
		push_warning("[ProximityCutsceneManager] /root/MultiplayerManager missing — cutscene mirroring disabled")
		return
	# PR-J — pick up configurable intervals from SyncRateConfig.
	if get_node_or_null("/root/SyncRateConfig") != null:
		CHECK_INTERVAL_SECONDS = SyncRateConfig.cutscene_membership_seconds
		POLL_INTERVAL_SECONDS = SyncRateConfig.cutscene_text_poll_seconds
	# We only need physics process when an active cutscene is running;
	# but the cost of an always-on _process tick is negligible. Keep
	# enabled so the next call_when_dialogic_ends edge case (host quits
	# during a cutscene) gets handled.


func _process(delta: float) -> void:
	if _active == null:
		return
	if not _is_host():
		return
	_check_accumulator += delta
	if _check_accumulator >= CHECK_INTERVAL_SECONDS:
		_check_accumulator = 0.0
		_recompute_membership()
	_poll_accumulator += delta
	if _poll_accumulator >= POLL_INTERVAL_SECONDS:
		_poll_accumulator = 0.0
		_poll_dialogic_state_and_broadcast()


# =============================================================
# PUBLIC API — called by DialogueTrigger3D when it fires
# =============================================================

## Begin a host-side cutscene at the given origin. radius < 0 = all
## guests; 0 = host-only (no mirror). Called by DialogueTrigger3D
## after Dialogic.start succeeds. Idempotent — calling while another
## cutscene is active replaces it (Dialogic itself enforces only one
## timeline at a time).
func begin_cutscene(timeline_id: String, origin: Vector3, radius: float = DEFAULT_RADIUS_METERS) -> void:
	if not _is_host():
		return
	if _active != null:
		end_cutscene()
	_active = ActiveCutscene.new(timeline_id, origin, radius)
	_last_speaker = ""
	_last_line = ""
	_last_choices = PackedStringArray()
	_recompute_membership()
	print("[ProximityCutsceneManager] begin %s at %s r=%.1f → %d guest(s)" % [
		timeline_id, origin, radius, _active.participating.size(),
	])


## End the active cutscene (on host). All participating guests
## receive cutscene_end and dismiss their overlays. Idempotent —
## safe to call when no cutscene is active.
func end_cutscene() -> void:
	if not _is_host():
		return
	if _active == null:
		return
	var timeline_id: String = _active.timeline_id
	for peer_id in _active.participating.keys():
		_rpc_cutscene_end.rpc_id(int(peer_id), timeline_id)
	print("[ProximityCutsceneManager] end %s" % timeline_id)
	_active = null
	_last_speaker = ""
	_last_line = ""
	_last_choices = PackedStringArray()


## True if THIS peer is currently in a mirrored cutscene (drives
## input gating on Player3D and any HUD elements that need to
## dim during dialogue).
##
## Maintained by guest-side _rpc_cutscene_begin/_end handlers.
var _local_is_mirrored: bool = false
func is_local_in_cutscene() -> bool:
	return _local_is_mirrored


## True if the host machine currently has an active cutscene driving
## guest mirrors. Used by PauseMenu to gate save-during-cutscene.
## Returns false on guests (they have no host-side _active state).
func has_active_cutscene() -> bool:
	return _active != null


# =============================================================
# HOST — membership tracking
# =============================================================

func _recompute_membership() -> void:
	if _active == null:
		return
	var new_set: Dictionary = {}
	# Walk every connected peer (excluding host themselves; host's
	# Dialogic UI is the source, not a mirror).
	for peer_id in MultiplayerManager.peers.keys():
		var pid: int = int(peer_id)
		if pid == MultiplayerManager.local_peer_id():
			continue
		if _peer_in_radius(pid):
			new_set[pid] = true

	# Send begin to new entrants.
	for pid in new_set.keys():
		if not _active.participating.has(pid):
			_rpc_cutscene_begin.rpc_id(int(pid), _active.timeline_id, _active.origin, _active.radius)
			# Force re-send the current line so the entrant sees text
			# immediately, not after the next poll tick.
			if not _last_line.is_empty():
				_rpc_cutscene_text.rpc_id(int(pid), _last_speaker, _last_line)
	# Send end to exiters.
	for pid in _active.participating.keys():
		if not new_set.has(pid):
			_rpc_cutscene_end.rpc_id(int(pid), _active.timeline_id)
	_active.participating = new_set


func _peer_in_radius(peer_id: int) -> bool:
	if _active == null:
		return false
	if _active.radius < 0.0:
		return true   # -1 = all guests regardless
	if _active.radius == 0.0:
		return false  # 0 = host-only (no mirror)
	# Locate the peer's player node by the MP-2 naming convention.
	# PlayerSpawner names them "Player_<peer_id>" under whatever
	# Players parent it owns. We do a recursive search rather than
	# hardcode a path so the manager works in any world scene.
	var node_name: String = "Player_%d" % peer_id
	var node: Node = _find_player_node(get_tree().get_current_scene(), node_name)
	if node == null:
		return false
	if node is Node3D:
		var dist: float = (node as Node3D).global_position.distance_to(_active.origin)
		return dist <= _active.radius
	return false


func _find_player_node(root: Node, target_name: String) -> Node:
	if root == null:
		return null
	if root.name == target_name:
		return root
	for c in root.get_children():
		var found: Node = _find_player_node(c, target_name)
		if found != null:
			return found
	return null


# =============================================================
# HOST — Dialogic state polling
# =============================================================

func _poll_dialogic_state_and_broadcast() -> void:
	if _active == null or _active.participating.is_empty():
		return
	# We hold off on a strong contract with Dialogic 2's signal API
	# (it has shifted across plugin versions). Polling current state
	# at 4Hz is the simple, version-tolerant pattern: read whatever
	# "current speaker" + "current text" properties / methods exist,
	# broadcast on change. Costs ~4 cheap calls/sec.
	var dialogic: Node = get_node_or_null("/root/Dialogic")
	if dialogic == null:
		return
	# Dialogic 2.x exposes `current_state_info` Dictionary and various
	# subsystem nodes. Defensive lookup — tolerate missing fields so
	# this still ships if Dialogic's API evolves.
	var speaker: String = ""
	var line: String = ""
	if "current_state_info" in dialogic and dialogic.current_state_info is Dictionary:
		var info: Dictionary = dialogic.current_state_info
		# Common shapes seen in Dialogic 2 builds:
		#   info.text                       → current line
		#   info.character / info.speaker   → speaker
		# Fall through both casings so different plugin builds work.
		line = String(info.get("text", info.get("line", "")))
		speaker = String(info.get("character", info.get("speaker", "")))
	if speaker == _last_speaker and line == _last_line:
		# Even when text is unchanged, choice state can shift (a new
		# choice node has appeared, or the player just made one). Poll
		# choices separately below.
		_poll_choices(dialogic)
		return
	_last_speaker = speaker
	_last_line = line
	for peer_id in _active.participating.keys():
		_rpc_cutscene_text.rpc_id(int(peer_id), speaker, line)
	_poll_choices(dialogic)


# PR-B — poll Dialogic 2 for any pending choice node. The API surface
# varies; we look for any of the common shapes and broadcast a
# diff-aware update. Choices are grayed out on the guest side —
# only the host advances. CutsceneMirror.set_choices controls
# render; absent / empty array hides the choice panel.
func _poll_choices(dialogic: Node) -> void:
	if _active == null or _active.participating.is_empty():
		return
	var current: PackedStringArray = PackedStringArray()
	# Shape 1: Dialogic 2.x stores active choices in
	# current_state_info["choices"] as Array of Dictionary
	# { text, idx, ... }.
	if "current_state_info" in dialogic and dialogic.current_state_info is Dictionary:
		var info: Dictionary = dialogic.current_state_info
		var raw = info.get("choices", info.get("text_event_choices", null))
		if raw is Array:
			for c in raw:
				if c is Dictionary:
					current.append(String((c as Dictionary).get("text", "")))
				else:
					current.append(String(c))
	# Diff against last broadcast; only resend on change.
	if current.size() == _last_choices.size():
		var same: bool = true
		for i in range(current.size()):
			if current[i] != _last_choices[i]:
				same = false
				break
		if same:
			return
	_last_choices = current
	for peer_id in _active.participating.keys():
		_rpc_cutscene_choices.rpc_id(int(peer_id), current)


# =============================================================
# RPCs — guest receivers
# =============================================================

@rpc("authority", "reliable")
func _rpc_cutscene_begin(timeline_id: String, origin: Vector3, radius: float) -> void:
	_local_is_mirrored = true
	# Forward to the CutsceneMirror UI by group lookup so we don't
	# couple this autoload to a specific scene path.
	for receiver in get_tree().get_nodes_in_group("cutscene_mirror_overlay"):
		if receiver.has_method("show_cutscene"):
			receiver.show_cutscene(timeline_id, origin, radius)


@rpc("authority", "reliable")
func _rpc_cutscene_text(speaker: String, line: String) -> void:
	for receiver in get_tree().get_nodes_in_group("cutscene_mirror_overlay"):
		if receiver.has_method("set_line"):
			receiver.set_line(speaker, line)


@rpc("authority", "reliable")
func _rpc_cutscene_choices(choices: PackedStringArray) -> void:
	for receiver in get_tree().get_nodes_in_group("cutscene_mirror_overlay"):
		if receiver.has_method("set_choices"):
			receiver.set_choices(choices)


@rpc("authority", "reliable")
func _rpc_cutscene_end(_timeline_id: String) -> void:
	_local_is_mirrored = false
	for receiver in get_tree().get_nodes_in_group("cutscene_mirror_overlay"):
		if receiver.has_method("hide_cutscene"):
			receiver.hide_cutscene()


# =============================================================
# HELPERS
# =============================================================

func _is_host() -> bool:
	if get_node_or_null("/root/MultiplayerManager") == null:
		return false
	return MultiplayerManager.is_host()
