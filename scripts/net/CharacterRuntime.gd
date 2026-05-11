extends Node
# CharacterRuntime — runtime glue between CharacterStore and the
# live game state autoloads (InventoryManager today; future
# SkillProgression, PerkRegistry, etc.).
#
# WHAT THIS IS (plain English):
#
#   CharacterStore handles file I/O. InventoryManager owns the live
#   inventory state. This autoload is the seam that copies between
#   them at the right moments in the session lifecycle:
#
#     • On session_started: if an active character is selected,
#       load it into InventoryManager (overwriting any previous
#       state).
#     • Every AUTOSAVE_SECONDS: save current state back into the
#       record + flush to disk.
#     • On session_ended (clean disconnect or host quit): save once
#       more before tearing down.
#     • On NOTIFICATION_WM_CLOSE_REQUEST (the app's quit signal):
#       last-chance save, since Godot fires this synchronously
#       before the autoloads are freed.
#
#   Sits at the END of the autoload list. Depends on:
#     CharacterStore, InventoryManager, MultiplayerManager
#
# WHY NOT FOLD INTO CharacterStore OR InventoryManager:
#
#   Each currently has a clear single responsibility (disk I/O vs.
#   inventory state). Adding the lifecycle hooks to either would
#   couple it to the OTHER, creating a circular dependency in the
#   reasoning (and load order). A separate small autoload keeps the
#   wiring obvious and testable.


# =============================================================
# CONFIG
# =============================================================

const AUTOSAVE_SECONDS: float = 60.0


# =============================================================
# STATE
# =============================================================

var _autosave_accum: float = 0.0


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# Defensive guards — if any dependency is missing, this autoload
	# becomes inert. Project still loads.
	if get_node_or_null("/root/CharacterStore") == null:
		push_warning("[CharacterRuntime] /root/CharacterStore missing — character runtime disabled")
		return
	if get_node_or_null("/root/InventoryManager") == null:
		push_warning("[CharacterRuntime] /root/InventoryManager missing — character runtime disabled")
		return
	if get_node_or_null("/root/MultiplayerManager") != null:
		MultiplayerManager.session_started.connect(_on_session_started)
		MultiplayerManager.session_ended.connect(_on_session_ended)


func _process(delta: float) -> void:
	# Autosave only while in a session AND an active character exists.
	if get_node_or_null("/root/MultiplayerManager") == null:
		return
	if MultiplayerManager.is_offline():
		return
	if CharacterStore.get_active_character() == null:
		return
	_autosave_accum += delta
	if _autosave_accum >= AUTOSAVE_SECONDS:
		_autosave_accum = 0.0
		_save_active_character("autosave")


func _notification(what: int) -> void:
	# Last-chance save on graceful quit. Godot fires NOTIFICATION_WM_
	# CLOSE_REQUEST synchronously before autoloads tear down, so the
	# save call here completes before the app exits.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_active_character("quit")


# =============================================================
# LIFECYCLE HANDLERS
# =============================================================

func _on_session_started(_mode: int) -> void:
	# Reset the autosave timer so the first autosave fires
	# AUTOSAVE_SECONDS after session start, not at session start.
	_autosave_accum = 0.0

	var record = CharacterStore.get_active_character()
	if record == null:
		# No active character — fall back to the InventoryManager's
		# default loadout (set in _ready). This is the path that runs
		# when the operator skips CharacterSelect (testing, dev path).
		print("[CharacterRuntime] session_started with no active character — keeping InventoryManager defaults")
		return
	InventoryManager.load_from_character_record(record)
	print("[CharacterRuntime] loaded character '%s' (steam_id=%d) into InventoryManager" % [
		record.display_name, record.steam_id,
	])


func _on_session_ended(_reason: String) -> void:
	_save_active_character("session_ended")


# =============================================================
# SAVE
# =============================================================

func _save_active_character(trigger: String) -> void:
	if get_node_or_null("/root/CharacterStore") == null:
		return
	if get_node_or_null("/root/InventoryManager") == null:
		return
	var record = CharacterStore.get_active_character()
	if record == null:
		return
	InventoryManager.save_to_character_record(record)
	var err: Error = CharacterStore.save_character(record)
	if err == OK:
		print("[CharacterRuntime] saved '%s' (trigger: %s)" % [record.display_name, trigger])
	else:
		push_warning("[CharacterRuntime] save failed (err %s, trigger: %s)" % [err, trigger])
