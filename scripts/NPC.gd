# NPC.gd
# Base script for all interactive NPCs (Tier 1 through Tier 3).
# Attach to a CharacterBody3D node. Assign an NPCData resource in the Inspector.
#
# TIER 0 (background/decoration) NPCs do NOT use this script.
# They are plain Node3D/MeshInstance3D nodes — no script overhead at all.
#
# SCENE STRUCTURE expected by this script:
#   NPCNode (CharacterBody3D + NPC.gd)
#   ├── MeshInstance3D          ← visual (voxel character or sprite)
#   ├── CollisionShape3D        ← physics body
#   ├── BarkArea (Area3D)       ← proximity trigger for barks
#   │   └── CollisionShape3D   ← sphere, radius = bark_radius
#   └── InteractArea (Area3D)   ← proximity trigger for E-press dialogue
#       └── CollisionShape3D   ← sphere, radius = interact_radius
#
# The easiest way to create a new NPC:
#   1. Duplicate the NPC_Template.tscn scene.
#   2. Set the NPCData resource on the root node.
#   3. The tier in NPCData controls which features are active.

class_name NPC
extends CharacterBody3D

# ── Exports ───────────────────────────────────────────────────────────────────

## The data resource for this NPC. Create one .tres per character in /assets/npcs/.
@export var npc_data: NPCData

## How far away (meters) the player must be to trigger proximity barks.
@export var bark_radius: float = 5.0

## How far away (meters) the player must be to see the "Press E" prompt.
@export var interact_radius: float = 2.0

# ── Node References ───────────────────────────────────────────────────────────

# These node names must match your scene structure exactly.
@onready var bark_area: Area3D = $BarkArea
@onready var interact_area: Area3D = $InteractArea

# ── Internal State ────────────────────────────────────────────────────────────

# Current disposition value (0–100). Loaded from GameState on _ready.
var current_disposition: int = 50

# Whether the player is within interact_radius right now.
var player_in_interact_range: bool = false

# Tracks cooldown timers per bark trigger.
# Format: { "TRIGGER_ID": seconds_remaining }
var _bark_cooldowns: Dictionary = {}

# Default cooldown used when NPCData.bark_triggers doesn't specify one.
const _DEFAULT_BARK_COOLDOWN: float = 45.0

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	if npc_data == null:
		push_warning("NPC '%s' has no NPCData resource. Assign one in the Inspector." % name)
		return

	# Restore persisted disposition from save data (if any).
	_load_disposition()

	# Wire up the BarkArea signal (Tier 1 and above).
	if npc_data.tier >= NPCData.Tier.BARK:
		bark_area.body_entered.connect(_on_player_entered_bark_range)

	# Wire up the InteractArea signals (Tier 2 and above).
	if npc_data.tier >= NPCData.Tier.CONVERSATIONAL:
		interact_area.body_entered.connect(_on_player_entered_interact_range)
		interact_area.body_exited.connect(_on_player_exited_interact_range)

func _process(delta: float) -> void:
	# Tick down all active bark cooldown timers.
	for trigger_id in _bark_cooldowns.keys():
		_bark_cooldowns[trigger_id] -= delta
		if _bark_cooldowns[trigger_id] <= 0.0:
			_bark_cooldowns.erase(trigger_id)

	# Check for E-press while the player is in range (Tier 2+).
	if npc_data and npc_data.tier >= NPCData.Tier.CONVERSATIONAL:
		if player_in_interact_range and Input.is_action_just_pressed("interact"):
			_start_dialogue()

# ── Bark System ───────────────────────────────────────────────────────────────
# Barks are short voiced/text lines that fire without pausing the game.
# Trigger IDs must match entries in design/BARK_LIBRARY.md.
# The BarkManager autoload picks a random variant and shows the overlay.

## Fire a bark for the given trigger. Called by this NPC or by external systems
## (e.g. the combat system fires "COMBAT_ENGAGE" on all party members).
func fire_bark(trigger_id: String) -> void:
	if npc_data == null or npc_data.tier < NPCData.Tier.BARK:
		return

	# Skip if this trigger is cooling down.
	if _bark_cooldowns.has(trigger_id):
		return

	# Ask BarkManager to display a random line from this NPC's pool.
	if get_node_or_null("/root/BarkManager"):
		BarkManager.fire(npc_data.npc_id, trigger_id, global_position)

	# Determine the cooldown for this trigger.
	var cooldown: float = _DEFAULT_BARK_COOLDOWN
	if npc_data.bark_triggers.has(trigger_id):
		cooldown = float(npc_data.bark_triggers[trigger_id])

	# 0.0 cooldown means "always fire" — don't add a timer.
	if cooldown > 0.0:
		_bark_cooldowns[trigger_id] = cooldown

func _on_player_entered_bark_range(body: Node3D) -> void:
	if body.is_in_group("player"):
		fire_bark("PLAYER_NEARBY")

# ── Dialogue System ───────────────────────────────────────────────────────────
# Uses Dialogic 2. The timeline name comes from NPCData, with an optional
# per-hour override from the active NPCScheduleEntry.

func _start_dialogue() -> void:
	if not get_node_or_null("/root/Dialogic"):
		push_warning("Dialogic autoload not found. Cannot start NPC dialogue.")
		return

	# Find the timeline to use: schedule override takes priority.
	var timeline: String = npc_data.dialogue_timeline
	var active_entry := _get_active_schedule_entry()
	if active_entry and active_entry.dialogue_override != "":
		timeline = active_entry.dialogue_override

	if timeline == "":
		push_warning("NPC '%s' has no dialogue_timeline set." % npc_data.npc_id)
		return

	# Write NPC context into GameState so Dialogic conditions can read it.
	GameState.set_flag("active_npc", npc_data.npc_id)
	GameState.set_flag("active_npc_disposition", str(current_disposition))
	GameState.set_flag("active_npc_faction", npc_data.faction)

	Dialogic.start(timeline)

func _on_player_entered_interact_range(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_interact_range = true
		# TODO: show "Press E to talk" world-space prompt (Phase 2 of UI work).

func _on_player_exited_interact_range(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_interact_range = false
		# TODO: hide the prompt.

# ── Disposition System ────────────────────────────────────────────────────────
# Disposition is a 0–100 value representing how the NPC feels about the player.
# It persists across saves via GameState flags.
#
# 0–24   = Hostile    (curt refusals, will not share information)
# 25–49  = Unfriendly (minimal responses)
# 50–74  = Neutral    (default for most civilians)
# 75–89  = Friendly   (warmer tone, more information unlocked)
# 90–100 = Trusted    (deepest dialogue branches available)

## Change disposition by delta (positive = friendlier, negative = colder).
## Clamps to 0–100 and saves immediately.
func adjust_disposition(delta: int) -> void:
	current_disposition = clamp(current_disposition + delta, 0, 100)
	GameState.set_flag("npc_disp_" + npc_data.npc_id, str(current_disposition))

## Read the correct disposition label for use in Dialogic conditions.
## Example: if GameState.get_flag("active_npc_disposition_label") == "TRUSTED"
func get_disposition_label() -> String:
	if current_disposition >= 90: return "TRUSTED"
	if current_disposition >= 75: return "FRIENDLY"
	if current_disposition >= 50: return "NEUTRAL"
	if current_disposition >= 25: return "UNFRIENDLY"
	return "HOSTILE"

func _load_disposition() -> void:
	var saved: String = GameState.get_flag("npc_disp_" + npc_data.npc_id)
	if saved != "":
		current_disposition = int(saved)
	else:
		current_disposition = npc_data.base_disposition

# ── Schedule System ───────────────────────────────────────────────────────────
# The world clock (WorldClock autoload — to be built) calls update_schedule()
# each time the in-game hour changes. The NPC teleports to the right SpawnPoint3D.

## Call this when the in-game hour changes.
## hour is an integer 0–23.
func update_schedule(hour: int) -> void:
	if npc_data == null or npc_data.tier < NPCData.Tier.CONVERSATIONAL:
		return

	var entry := _get_active_schedule_entry()
	if entry == null or entry.location_id == "":
		return

	# Find the SpawnPoint3D with this name in the current scene.
	var spawn := _find_spawn_point(entry.location_id)
	if spawn:
		global_position = spawn.global_position

## Returns the schedule entry active at the current in-game hour, or null.
func _get_active_schedule_entry() -> NPCScheduleEntry:
	if npc_data == null:
		return null
	# Read the current hour from GameState (WorldClock will write "world_hour").
	var hour: int = int(GameState.get_flag("world_hour"))
	for entry in npc_data.schedule:
		var e := entry as NPCScheduleEntry
		if e and hour >= e.time_start and hour < e.time_end:
			return e
	return null

## Search the current scene tree for a SpawnPoint3D matching the given name.
func _find_spawn_point(location_id: String) -> Node3D:
	# SpawnPoint3D nodes are expected to be in a group named "spawn_points".
	var spawns := get_tree().get_nodes_in_group("spawn_points")
	for s in spawns:
		if s.name == location_id:
			return s as Node3D
	push_warning("NPC '%s': no SpawnPoint3D named '%s' found in scene." % [npc_data.npc_id, location_id])
	return null
