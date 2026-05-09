extends Node3D
# DiceTestBootstrap — root script for scenes/DiceTest.tscn
#
# Self-contained dev harness for the Bones (tavern dice) prototype.
# No player, no terrain. Press 1 to open a match against Tomlin.
#
# CONTROLS:
#   1   — Open a match against the stub opponent
#   F2  — Add 50 coin (debug)
#   Esc — Closes any open match (or quits if none)

const OPPONENT_PATH: String = "res://assets/dice/opponents/tomlin_stub.tres"
const STARTING_COIN: int = 100
const DICE_GAME_UI_SCRIPT: GDScript = preload("res://scripts/ui/DiceGameUI.gd")

var _active_ui: CanvasLayer = null
var _coin_label: Label = null


func _ready() -> void:
	add_to_group("dev_scene")

	# Seed coin so the player can actually wager. Only top up to the
	# starting amount if they're below it — keeps test sessions reproducible.
	if InventoryManager.get_coin_balance() < STARTING_COIN:
		var delta: int = STARTING_COIN - InventoryManager.get_coin_balance()
		InventoryManager.add_coin(delta)

	_build_instructions_ui()
	print("[DiceTest] Ready. Press 1 to play. Coin: %d" % InventoryManager.get_coin_balance())


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_open_match()
			KEY_F2:
				InventoryManager.add_coin(50)
				_refresh_coin_label()
				print("[DiceTest] +50 coin (total %d)" % InventoryManager.get_coin_balance())


# DEBUG: every mouse click that enters the input system. Helps diagnose
# whether clicks are reaching the UI at all vs. being eaten by a control.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed:
			print("[DiceTest] mouse_down at %s button=%d" % [mb.position, mb.button_index])


func _open_match() -> void:
	print("[DiceTest] _open_match called. _active_ui=%s" % _active_ui)
	if _active_ui != null:
		print("[DiceTest] match already active, ignoring")
		return
	if not ResourceLoader.exists(OPPONENT_PATH):
		push_error("[DiceTest] Missing opponent resource: %s" % OPPONENT_PATH)
		return
	var opponent: DiceOpponentData = load(OPPONENT_PATH) as DiceOpponentData
	if opponent == null:
		push_error("[DiceTest] Resource at %s did not load as DiceOpponentData" % OPPONENT_PATH)
		return

	_active_ui = DICE_GAME_UI_SCRIPT.new()
	get_tree().root.add_child(_active_ui)
	_active_ui.match_ended.connect(_on_match_ended)
	_active_ui.match_cancelled.connect(_on_match_cancelled)
	_active_ui.tree_exited.connect(_on_ui_freed)
	_active_ui.open(opponent)
	print("[DiceTest] match opened: %s vs %s" % [opponent.npc_id, opponent.display_name])


func _on_match_ended(net_delta: int) -> void:
	print("[DiceTest] Match ended. Net coin delta: %+d (balance now %d)" % [
		net_delta, InventoryManager.get_coin_balance()
	])
	_refresh_coin_label()


func _on_match_cancelled() -> void:
	print("[DiceTest] Match cancelled before any hands.")
	_refresh_coin_label()


func _on_ui_freed() -> void:
	_active_ui = null


# =============================================================
# INSTRUCTIONS OVERLAY
# =============================================================

func _build_instructions_ui() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)

	var label: Label = Label.new()
	label.text = (
		"BONES (TAVERN DICE) PROTOTYPE\n"
		+ "──────────────────────────────\n"
		+ "1   Open match vs Tomlin\n"
		+ "F2  +50 coin (debug)\n"
		+ "Esc Cancel / quit\n"
	)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("#f3e6c4"))
	label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	label.position = Vector2(20.0, 20.0)
	canvas.add_child(label)

	_coin_label = Label.new()
	_coin_label.add_theme_font_size_override("font_size", 13)
	_coin_label.add_theme_color_override("font_color", Color("#f0c14b"))
	_coin_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_coin_label.position = Vector2(20.0, 130.0)
	canvas.add_child(_coin_label)
	_refresh_coin_label()


func _refresh_coin_label() -> void:
	if _coin_label:
		_coin_label.text = "Coin: %d" % InventoryManager.get_coin_balance()
