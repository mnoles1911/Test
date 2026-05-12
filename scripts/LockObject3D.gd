class_name LockObject3D
extends Area3D
# LockObject3D — an interactable locked object in the 3D world.
#
# What this does in plain English:
#   Attach this script to an Area3D node that sits on a chest, door, or any
#   lockable container. When Roland walks within range the game shows him a
#   difficulty label ("Easy / Medium / Hard / Very Hard"). Pressing E starts
#   the lockpicking minigame.
#
# HOW TO SET UP IN THE EDITOR:
#   1. Create an Area3D node. Add a CollisionShape3D child (SphereShape,
#      radius ~1.5 m — this is the interaction bubble).
#   2. Add LockObject3D.gd as the script on the Area3D.
#   3. In the Inspector, assign a LockData resource to the "Lock Data" field.
#   4. Add the Area3D to the correct collision layer/mask so Player3D's body
#      can enter it (match the layer your player uses for area detection).
#   5. Optional: assign a mesh child to represent the visual lock or chest.
#
# SIGNALS:
#   unlocked()  — fires when Roland successfully picks the lock.
#                 Wire this to whatever should happen (door opens, chest lid
#                 animates, quest flag sets, etc.)
#
# DEPENDENCIES:
#   Autoloads needed: InventoryManager, GameState, DebugOverlay
#   The LockpickingUI CanvasLayer is instanced at runtime from LockpickingUI.gd
#   (registered as a global class_name — no scene file needed).


signal unlocked()
# Wire this to the door/chest open animation or quest trigger.


@export var lock_data: LockData = null
# The LockData resource describing this lock's difficulty and identity.
# Create one inline in the Inspector ("New LockData") or load a saved .tres.


# ─── INTERNAL STATE ────────────────────────────────────────────────────────

var _player_in_range: bool = false
# True while Roland's body is overlapping our collision shape.

var _ui_open: bool = false
# True while the lockpicking overlay is on screen for this object.

var _is_unlocked: bool = false
# True once this lock has been successfully picked this session.
# (Persistent state lives in GameState via "picked_<lock_id>" flag.)


# ─── LIFECYCLE ─────────────────────────────────────────────────────────────

func _ready() -> void:
	# Validate the LockData resource so errors surface at scene load, not mid-play.
	if lock_data == null:
		push_warning("[LockObject3D] '%s' has no LockData assigned." % name)
		return

	if lock_data.lock_id == "" or lock_data.lock_id == "lock_default":
		push_warning(
			"[LockObject3D] '%s' uses the default lock_id — set a unique id!" % name
		)

	# Check if already picked in a previous session.
	if GameState.get_flag("picked_" + lock_data.lock_id):
		_is_unlocked = true

	# Connect Area3D body signals for player proximity detection.
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or _ui_open:
		return
	if lock_data == null:
		return

	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_on_interact_pressed()


# ─── PROXIMITY DETECTION ───────────────────────────────────────────────────

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = true

	if _is_unlocked:
		_show_prompt("Unlocked", "lock_icon", 1.5)
		return

	# Auto-examine: show difficulty label without any player input.
	var label: String = ["Easy", "Medium", "Hard", "Very Hard"][lock_data.tier]
	_show_prompt(label + " — E to pick", "lock_icon", 2.0)

	DebugOverlay.log_action(
		"LockObject3D — player entered range of '%s' (%s)" % [
			lock_data.lock_id, label
		]
	)


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = false
	_hide_prompt()


# ─── INTERACTION ───────────────────────────────────────────────────────────

func _on_interact_pressed() -> void:
	if _is_unlocked:
		DebugOverlay.log_action(
			"LockObject3D — '%s' already unlocked." % lock_data.lock_id
		)
		return

	# Check if the player has a key for this lock.
	if lock_data.key_item_id != "" and InventoryManager.has_item(lock_data.key_item_id):
		_use_key()
		return

	# Check for picks before opening the UI.
	if not (InventoryManager.has_item("lockpick_standard")
	        or InventoryManager.has_item("lockpick_fine")):
		_show_prompt("No picks.", "lock_icon", 2.0)
		DebugOverlay.log_action(
			"LockObject3D — no picks for '%s'." % lock_data.lock_id
		)
		return

	# Lockpicking perk auto-opens. silver_pick auto-resolves tier-1
	# locks; lock_perfect_pick auto-resolves first tier-≤2 lock per day
	# (the perk script tracks its own once-per-day state).
	if _try_perk_auto_open():
		return

	# Full examine (no picks required, press E without picks for flavour text).
	# For now, opening always goes straight to the minigame.
	_open_lockpicking_ui()


func _try_perk_auto_open() -> bool:
	# Returns true if a perk fired and the lock is now open (or about
	# to be), false to fall through to the standard minigame path.
	var tier: int = int(lock_data.tier)
	# Silver Pick: tier-1 locks open in one attempt.
	if tier == 0 and PerkQuery.has_flag("lock", "tier_1"):
		_on_lock_opened(lock_data.lock_id)
		return true
	# Perfect Pick: first tier-≤2 lock of the day auto-resolves. The
	# perk's own script tracks the daily flag so we just dispatch and
	# observe whether it sets ctx.perfect_pick_fired.
	if tier <= 1 and SkillManager != null:
		var ctx: Dictionary = {"tier": tier, "first_per_day": true}
		SkillManager.dispatch("on_lock_opened", ctx)
		if ctx.get("perfect_pick_fired", false):
			_on_lock_opened(lock_data.lock_id)
			return true
	return false


func _use_key() -> void:
	InventoryManager.remove_item(lock_data.key_item_id, 1)
	_mark_unlocked()
	_show_prompt("Unlocked.", "lock_icon", 1.5)
	DebugOverlay.log_action(
		"LockObject3D — '%s' opened with key." % lock_data.lock_id
	)


func _open_lockpicking_ui() -> void:
	_ui_open = true

	var ui := LockpickingUI.new()
	get_tree().root.add_child(ui)

	ui.lock_opened.connect(_on_lock_opened)
	ui.lock_closed.connect(_on_lock_closed)

	ui.open(lock_data)

	DebugOverlay.log_action(
		"LockObject3D — opened UI for '%s' (%s)" % [
			lock_data.lock_id,
			["Easy", "Medium", "Hard", "Very Hard"][lock_data.tier]
		]
	)


func _on_lock_opened(lock_id: String) -> void:
	_mark_unlocked()
	unlocked.emit()

	DebugOverlay.log_action(
		"LockObject3D — '%s' picked successfully." % lock_id
	)

	# Grant Lockpicking XP scaled by lock tier (Easy=1 .. Very Hard=4).
	# Dispatch on_lock_opened so perks like Double Loot can react.
	if get_node_or_null("/root/SkillManager"):
		var tier_mult: int = max(1, int(lock_data.tier) + 1)
		SkillManager.add_xp("lockpicking", 10.0 * float(tier_mult))
		SkillManager.dispatch("on_lock_opened", {
			"lock_id": lock_id,
			"tier": lock_data.tier,
		})

	# Re-show prompt so player knows the state changed.
	_show_prompt("Unlocked", "lock_icon", 1.5)


func _on_lock_closed() -> void:
	_ui_open = false


func _mark_unlocked() -> void:
	_is_unlocked = true
	# GameState flag is set by LockpickingUI on successful pick;
	# key-use marks it here so the flag is consistent.
	if lock_data:
		GameState.set_flag("picked_" + lock_data.lock_id, "true")


# ─── INTERACTION PROMPT HELPERS ────────────────────────────────────────────
# These call HUDOverlay's interaction prompt system.
# If HUDOverlay isn't in this scene (e.g. dev test scenes), they fail silently.

func _show_prompt(text: String, icon: String, duration: float) -> void:
	var hud = get_node_or_null("/root/HUDOverlay")
	if hud and hud.has_method("show_interact_prompt"):
		hud.show_interact_prompt(text, icon, duration)


func _hide_prompt() -> void:
	var hud = get_node_or_null("/root/HUDOverlay")
	if hud and hud.has_method("hide_interact_prompt"):
		hud.hide_interact_prompt()
