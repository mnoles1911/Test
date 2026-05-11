extends Area3D
class_name DialogueTrigger3D
# DialogueTrigger3D — invisible 3D trigger zone that fires on press-E.
#
# Direct port of DialogueTrigger.gd. The 2D version waited for the
# player to be inside an Area2D, then watched for the "interact"
# action. This is the same logic in 3D — Area3D + body_entered/exited
# signals + Input check in _process.
#
# Wire-up:
#   1. Place an Area3D in your World3D scene at the NPC's location
#   2. Attach this script
#   3. Add a CollisionShape3D child (BoxShape3D, sized to the
#      conversation reach — usually 2×2×2 m)
#   4. Set timeline_name to the Dialogic timeline this trigger plays
#
# This is a M4-3D placeholder. Until Dialogic is wired up in 3D and
# until we have a real NPC to talk to, _fire_trigger() just prints.


@export var timeline_name: String = ""
# The Dialogic timeline file (without extension) to play.
# Example: "henrietta_archive"
# If empty, the trigger just prints to the Output panel for debugging.

## MP-7 proximity cutscene radius (meters). Default 20m matches the
## plan recommendation. Special values:
##   -1.0 — pull in ALL guests regardless of distance
##    0.0 — host-only (no guest mirror; solo cutscene)
@export var cutscene_pull_radius: float = 20.0

var _player_inside: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(_delta: float) -> void:
	if _player_inside and Input.is_action_just_pressed("interact"):
		_fire_trigger()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		print("[DialogueTrigger3D] Player entered. Press E to interact.")


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = false


func _fire_trigger() -> void:
	if timeline_name == "":
		print("[DialogueTrigger3D] Fired (no timeline assigned).")
		return
	# Dialogic autoload must exist before calling start.
	# Same pattern as the 2D DialogueTrigger.
	if get_node_or_null("/root/Dialogic"):
		print("[DialogueTrigger3D] Starting timeline: %s" % timeline_name)
		Dialogic.start(timeline_name)
		# MP-7 — notify ProximityCutsceneManager so it can mirror the
		# cutscene to in-radius guests. Host-only no-ops in OFFLINE
		# (manager itself gates on is_host).
		if get_node_or_null("/root/ProximityCutsceneManager") != null:
			ProximityCutsceneManager.begin_cutscene(timeline_name, global_position, cutscene_pull_radius)
		# Connect to Dialogic's timeline_ended signal so we can close
		# the mirror when the host's dialogue actually finishes. Use
		# CONNECT_ONE_SHOT so we don't accumulate handlers across
		# repeated triggers.
		if Dialogic.has_signal("timeline_ended") and not Dialogic.timeline_ended.is_connected(_on_dialogic_timeline_ended):
			Dialogic.timeline_ended.connect(_on_dialogic_timeline_ended, CONNECT_ONE_SHOT)
	else:
		push_warning("[DialogueTrigger3D] Dialogic autoload not found.")


func _on_dialogic_timeline_ended() -> void:
	if get_node_or_null("/root/ProximityCutsceneManager") != null:
		ProximityCutsceneManager.end_cutscene()
