extends CanvasLayer
# HUDOverlay — Health and endurance bars, bottom-center of the screen.
#
# What this does in plain English:
#   During gameplay two progress bars sit near the bottom of the screen.
#   The top bar (red) shows Roland's health. The bottom bar (green) shows
#   his endurance — how much sprinting energy he has left.
#   A small status label above the bars shows "CROUCHING" or "EXHAUSTED"
#   when those states are active.
#
#   This script finds the player automatically each frame by searching for
#   nodes in the "player" group (Player3D.tscn adds itself to that group).
#   If no player exists — e.g. when the main menu is showing — the HUD
#   hides itself cleanly.
#
# HOW TO ADJUST THE LOOK:
#   Edit the constants at the top of _build_ui() below.
#   PANEL_WIDTH / PANEL_HEIGHT — overall size of the HUD container.
#   BAR_HP_HEIGHT / BAR_END_HEIGHT — thickness of each bar.
#   Fill and background colors are in the StyleBoxFlat blocks.


# =============================================================
# NODE REFERENCES (set in _build_ui, read in _process every frame)
# =============================================================

var _root: Control
var _hp_bar: ProgressBar
var _end_bar: ProgressBar
var _hp_value_label: Label
var _end_value_label: Label
var _status_label: Label

# Mining-progress bar — shown only while the player is actively
# holding LMB on a mineable voxel. Sits ABOVE the HP/endurance
# panel so it doesn't push the layout around. Updated each frame
# from EditToolHandler.mining_progress (0..1) and visibility
# follows EditToolHandler.mining_active.
var _mining_root: Control
var _mining_bar: ProgressBar
var _mining_label: Label

# Quick-slot bar — 4 small slots in a horizontal row, just below
# the mining bar. Number keys 1-4 swap the equipped weapon to that
# slot's item. Right-click on a slot will eventually open a rebind
# picker (Phase 2). Currently-equipped slot is highlighted gold.
var _quick_root: Control
var _quick_slot_panels: Array[Panel] = []   # the visual frame
var _quick_slot_labels: Array[Label] = []   # item-name display
var _quick_slot_buttons: Array[Button] = [] # transparent click target for right-click rebind

# Top-left FPS readout. Lives on the same CanvasLayer as the HUD but
# is anchored to the top-left corner — independent of `_root` (which
# is the HP/endurance panel at the bottom). Always visible during
# gameplay AND on menus, so we never hide it together with `_root`.
var _fps_label: Label

# Cached so _find_player() doesn't search every frame when the player
# hasn't changed. Invalidated when the node becomes null.
var _cached_player: Node = null


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	layer = 5
	# Layer 5: above the game world, below the journal (10) and pause (50).
	_build_ui()
	_build_fps_label()
	_build_mining_bar()
	_build_quick_slot_bar()
	print("[HUDOverlay] Initialized.")


func _build_quick_slot_bar() -> void:
	# 4 slots in a horizontal row, pinned bottom-centre but ABOVE the
	# main HP/endurance panel and BELOW the mining bar. Each slot is
	# a small panel showing the slot number (top-left), the bound
	# item name (centre), and a highlight when that slot's item is
	# the currently-equipped weapon.
	#
	# Slot panel doubles as a click target for right-click rebinding
	# (Phase 2 — the gui_input handler is wired but currently a stub).
	const SLOT_W: float       = 110.0
	const SLOT_H: float       = 56.0
	const SLOT_GAP: float     = 6.0
	const PANEL_WIDTH: float  = 4.0 * SLOT_W + 3.0 * SLOT_GAP   # 4 slots + 3 gaps
	# Sits just below the mining bar (bottom_offset 156, height 40).
	# We sit 10 px below = 156 - 10 - SLOT_H from bottom.
	const BOTTOM_OFFSET: float = 36.0 + 110.0 + 10.0 + 40.0 + 10.0   # 206

	_quick_root = Control.new()
	_quick_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quick_root.anchor_left   = 0.5
	_quick_root.anchor_right  = 0.5
	_quick_root.anchor_top    = 1.0
	_quick_root.anchor_bottom = 1.0
	_quick_root.offset_left   = -(PANEL_WIDTH * 0.5)
	_quick_root.offset_right  =  (PANEL_WIDTH * 0.5)
	_quick_root.offset_top    = -(SLOT_H + BOTTOM_OFFSET)
	_quick_root.offset_bottom = -BOTTOM_OFFSET
	# Hidden by default — _process toggles to visible only when a
	# Player3D is in the tree. Without this initial hide the bar
	# flashes for a frame on the main menu before _process runs.
	_quick_root.visible = false
	add_child(_quick_root)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", int(SLOT_GAP))
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quick_root.add_child(hbox)

	for i in 4:
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(SLOT_W, SLOT_H)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Default (un-equipped) style — dim panel.
		var sb_idle := StyleBoxFlat.new()
		sb_idle.bg_color = Color(0.0, 0.0, 0.0, 0.65)
		sb_idle.border_width_left = 1
		sb_idle.border_width_top = 1
		sb_idle.border_width_right = 1
		sb_idle.border_width_bottom = 1
		sb_idle.border_color = Color(0.3, 0.3, 0.3, 1.0)
		panel.add_theme_stylebox_override("panel", sb_idle)
		hbox.add_child(panel)
		_quick_slot_panels.append(panel)

		# Slot number label (top-left).
		var num := Label.new()
		num.text = str(i + 1)
		num.position = Vector2(6, 4)
		num.add_theme_font_size_override("font_size", 14)
		num.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(num)

		# Item name label (centred).
		var name_lbl := Label.new()
		name_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		name_lbl.offset_top = 18  # below the number
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.text = "—"
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
		name_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		name_lbl.add_theme_constant_override("shadow_offset_x", 1)
		name_lbl.add_theme_constant_override("shadow_offset_y", 1)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(name_lbl)
		_quick_slot_labels.append(name_lbl)

		# Transparent button overlay — captures right-clicks for
		# Phase 2 rebind. Left-clicks fall through (we want the
		# player to click world objects, not the HUD).
		var btn := Button.new()
		btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn.flat = true
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		# bind the slot index to the handler so each button knows
		# which slot it represents.
		btn.gui_input.connect(_on_quick_slot_gui_input.bind(i))
		panel.add_child(btn)
		_quick_slot_buttons.append(btn)


func _on_quick_slot_gui_input(event: InputEvent, slot_idx: int) -> void:
	# Right-click → open the rebind picker (Phase 2). Left-clicks
	# fall through so the player can still click through the HUD
	# at world targets if they happen to be aiming behind the bar.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_open_quick_slot_rebind_picker(slot_idx)
			# Mark handled so the click doesn't propagate to world.
			get_viewport().set_input_as_handled()


func _open_quick_slot_rebind_picker(slot_idx: int) -> void:
	# Phase 2 stub. When the inventory grid UI lands this opens a
	# small list of all OWNED items; clicking one calls
	# InventoryManager.set_quick_slot(slot_idx, item_id). For now
	# log so the wiring is verifiable.
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Quick-slot %d right-click — rebind picker not built yet" % (slot_idx + 1))
	else:
		print("[HUDOverlay] Quick-slot %d right-clicked (rebind picker pending)" % (slot_idx + 1))


func _build_mining_bar() -> void:
	# Mining-progress bar — slim panel pinned bottom-centre, ABOVE the
	# main HP/endurance panel. Visible only while the player is
	# actively mining. Bar fill ramps 0..1 over the material's
	# mining_time_seconds; on completion it snaps to 100% for one
	# frame then hides on the next _clear_target.
	const PANEL_WIDTH: float    = 360.0
	const PANEL_HEIGHT: float   = 40.0
	# Sits above the existing HP/endurance panel (which has its own
	# 36 px bottom margin + 110 px height). Stack this just above with
	# a small gap.
	const BOTTOM_OFFSET: float  = 36.0 + 110.0 + 10.0  # = 156

	_mining_root = Control.new()
	_mining_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mining_root.anchor_left   = 0.5
	_mining_root.anchor_right  = 0.5
	_mining_root.anchor_top    = 1.0
	_mining_root.anchor_bottom = 1.0
	_mining_root.offset_left   = -(PANEL_WIDTH * 0.5)
	_mining_root.offset_right  =  (PANEL_WIDTH * 0.5)
	_mining_root.offset_top    = -(PANEL_HEIGHT + BOTTOM_OFFSET)
	_mining_root.offset_bottom = -BOTTOM_OFFSET
	_mining_root.visible = false  # hidden until first mining tick
	add_child(_mining_root)

	# Translucent dark backing panel — same style language as the
	# HP/endurance panel.
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.55)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mining_root.add_child(bg)

	# Horizontal layout: [label] [bar]
	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left   = 12
	hbox.offset_top    = 8
	hbox.offset_right  = -12
	hbox.offset_bottom = -8
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mining_root.add_child(hbox)

	_mining_label = Label.new()
	_mining_label.text = "MINING"
	_mining_label.custom_minimum_size = Vector2(120, 0)
	_mining_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mining_label.add_theme_font_size_override("font_size", 14)
	_mining_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1))
	hbox.add_child(_mining_label)

	_mining_bar = ProgressBar.new()
	_mining_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mining_bar.custom_minimum_size = Vector2(0, 18)
	_mining_bar.min_value = 0.0
	_mining_bar.max_value = 1.0
	_mining_bar.value = 0.0
	_mining_bar.show_percentage = false
	# Fill colour — warm gold/orange to read as "active effort", and
	# distinct from HP red and endurance green.
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.95, 0.7, 0.2, 1)
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2
	_mining_bar.add_theme_stylebox_override("fill", fill_style)
	# Empty (background) style for contrast.
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.12, 0.08, 1)
	_mining_bar.add_theme_stylebox_override("background", bg_style)
	hbox.add_child(_mining_bar)


func _build_fps_label() -> void:
	# Top-RIGHT FPS readout. Anchored to the right edge of the
	# viewport with a small margin. Black-outlined white text so
	# it's readable against any scene background — sky, dark cave,
	# water, etc. — without burning a panel rect into the corner.
	_fps_label = Label.new()
	_fps_label.text = "FPS: --"
	_fps_label.add_theme_font_size_override("font_size", 18)
	_fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	# Outline keeps the text readable on bright (sky, snow) backgrounds.
	_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_fps_label.add_theme_constant_override("outline_size", 4)
	# Right-anchored: pin to the top-right corner with a fixed-width
	# slot so the label can grow/shrink as digits change without
	# shifting the layout. horizontal_alignment = RIGHT keeps the
	# digits flush against the right edge.
	_fps_label.anchor_left = 1.0
	_fps_label.anchor_right = 1.0
	_fps_label.anchor_top = 0.0
	_fps_label.anchor_bottom = 0.0
	_fps_label.offset_left = -120  # slot width
	_fps_label.offset_right = -12  # right-edge margin
	_fps_label.offset_top = 8
	_fps_label.offset_bottom = 32
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fps_label)


func _build_ui() -> void:
	# --- Size / position constants ---
	const PANEL_WIDTH: float    = 540.0   # Width of the HUD panel in pixels.
	const PANEL_HEIGHT: float   = 110.0   # Height of the HUD panel.
	const BOTTOM_MARGIN: float  = 36.0    # Pixels from the bottom edge of the screen.
	const LABEL_FONT: int       = 18      # "HP" / "END" label font size.
	const VALUE_FONT: int       = 16      # "80/100" value font size.
	const STATUS_FONT: int      = 16      # CROUCHING / EXHAUSTED font size.
	const BAR_HP_HEIGHT: float  = 26.0    # Height of the health bar.
	const BAR_END_HEIGHT: float = 22.0    # Height of the endurance bar.

	# Root control anchored to bottom-center of the viewport.
	# mouse_filter = IGNORE so this purely-visual HUD never
	# intercepts clicks meant for menus or the world. The HUD
	# only displays HP/endurance/status; it doesn't take input.
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.anchor_left   = 0.5
	_root.anchor_right  = 0.5
	_root.anchor_top    = 1.0
	_root.anchor_bottom = 1.0
	_root.offset_left   = -(PANEL_WIDTH * 0.5)
	_root.offset_right  =  (PANEL_WIDTH * 0.5)
	_root.offset_top    = -(PANEL_HEIGHT + BOTTOM_MARGIN)
	_root.offset_bottom = -BOTTOM_MARGIN
	add_child(_root)

	# Semi-transparent dark background so bars are readable against any scene.
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.55)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	# Vertical layout inside the panel.
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   =  14
	vbox.offset_top    =  10
	vbox.offset_right  = -14
	vbox.offset_bottom = -10
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(vbox)

	# --- Status label (CROUCHING / EXHAUSTED) ---
	# Always present in the layout; text is set to "" when not needed.
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.custom_minimum_size = Vector2(0, STATUS_FONT + 4)
	_status_label.add_theme_font_size_override("font_size", STATUS_FONT)
	_status_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.1, 1))
	vbox.add_child(_status_label)

	# --- Health row: [HP label] [bar] [80/100] ---
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	vbox.add_child(hp_row)

	var hp_lbl := Label.new()
	hp_lbl.text = "HP"
	hp_lbl.custom_minimum_size = Vector2(46, 0)
	hp_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_lbl.add_theme_font_size_override("font_size", LABEL_FONT)
	hp_lbl.add_theme_color_override("font_color", Color(0.95, 0.35, 0.35, 1))
	hp_row.add_child(hp_lbl)

	_hp_bar = ProgressBar.new()
	_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_bar.custom_minimum_size = Vector2(0, BAR_HP_HEIGHT)
	_hp_bar.min_value = 0.0
	_hp_bar.max_value = 100.0
	_hp_bar.value     = 100.0
	_hp_bar.show_percentage = false
	var hp_bg_style := StyleBoxFlat.new()
	hp_bg_style.bg_color = Color(0.20, 0.05, 0.05, 1)
	_hp_bar.add_theme_stylebox_override("background", hp_bg_style)
	var hp_fill_style := StyleBoxFlat.new()
	hp_fill_style.bg_color = Color(0.85, 0.15, 0.15, 1)
	_hp_bar.add_theme_stylebox_override("fill", hp_fill_style)
	hp_row.add_child(_hp_bar)

	_hp_value_label = Label.new()
	_hp_value_label.custom_minimum_size = Vector2(80, 0)
	_hp_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hp_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_value_label.add_theme_font_size_override("font_size", VALUE_FONT)
	_hp_value_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.75, 1))
	hp_row.add_child(_hp_value_label)

	# --- Endurance row: [END label] [bar] [50/100] ---
	var end_row := HBoxContainer.new()
	end_row.add_theme_constant_override("separation", 8)
	vbox.add_child(end_row)

	var end_lbl := Label.new()
	end_lbl.text = "END"
	end_lbl.custom_minimum_size = Vector2(46, 0)
	end_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	end_lbl.add_theme_font_size_override("font_size", LABEL_FONT)
	end_lbl.add_theme_color_override("font_color", Color(0.30, 0.90, 0.45, 1))
	end_row.add_child(end_lbl)

	_end_bar = ProgressBar.new()
	_end_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_end_bar.custom_minimum_size = Vector2(0, BAR_END_HEIGHT)
	_end_bar.min_value = 0.0
	_end_bar.max_value = 100.0
	_end_bar.value     = 100.0
	_end_bar.show_percentage = false
	var end_bg_style := StyleBoxFlat.new()
	end_bg_style.bg_color = Color(0.05, 0.18, 0.05, 1)
	_end_bar.add_theme_stylebox_override("background", end_bg_style)
	var end_fill_style := StyleBoxFlat.new()
	end_fill_style.bg_color = Color(0.20, 0.80, 0.30, 1)
	_end_bar.add_theme_stylebox_override("fill", end_fill_style)
	end_row.add_child(_end_bar)

	_end_value_label = Label.new()
	_end_value_label.custom_minimum_size = Vector2(80, 0)
	_end_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_end_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_end_value_label.add_theme_font_size_override("font_size", VALUE_FONT)
	_end_value_label.add_theme_color_override("font_color", Color(0.70, 0.85, 0.72, 1))
	end_row.add_child(_end_value_label)


# =============================================================
# UPDATE LOOP
# =============================================================

func _process(_delta: float) -> void:
	# FPS readout updates every frame regardless of player state — we
	# want it visible on the main menu too so we can spot start-up
	# stutter. Engine.get_frames_per_second() returns a smoothed
	# average that updates ~once per second internally; no need for
	# our own smoothing.
	if _fps_label != null:
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

	# Quick-slot number-key dispatch. Polls the four input actions
	# directly each frame; on just_pressed we equip that slot's bound
	# item. Polling (not _input event handling) keeps it simple and
	# robust against Dialogic / GUI input absorption.
	_process_quick_slot_input()

	var player := _find_player()

	if player == null:
		_root.visible = false
		if _mining_root != null:
			_mining_root.visible = false
		# Quick-slot bar is gameplay-only too — hide on the main menu,
		# settings, load picker, and any other scene without a player.
		if _quick_root != null:
			_quick_root.visible = false
		return

	_root.visible = true

	# Read values from the player and push them into the bars.
	_hp_bar.max_value      = player.max_health
	_hp_bar.value          = player.health
	_hp_value_label.text   = "%d / %d" % [int(player.health), int(player.max_health)]

	_end_bar.max_value     = player.max_endurance
	_end_bar.value         = player.endurance
	_end_value_label.text  = "%d / %d" % [int(player.endurance), int(player.max_endurance)]

	# Status label: "CROUCHING", "EXHAUSTED", or blank.
	_status_label.text = player.status_text

	# Mining-progress bar — only visible while EditToolHandler reports
	# active mining. EditToolHandler is a child of Player3D
	# (scenes/Player3D.tscn) and exposes mining_active / mining_progress
	# / mining_material_label as plain vars updated each tick.
	if _mining_root != null:
		var edit_tool: Node = player.get_node_or_null("EditToolHandler")
		if edit_tool != null and "mining_active" in edit_tool and edit_tool.mining_active:
			_mining_root.visible = true
			_mining_bar.value = edit_tool.mining_progress
			# Display "MINING grass" / "MINING stone" so the player
			# sees what they're hitting and can swap tools if it's
			# the wrong material.
			var mat_name: String = edit_tool.mining_material_label if "mining_material_label" in edit_tool else ""
			if mat_name == "":
				_mining_label.text = "MINING"
			else:
				_mining_label.text = "MINING " + mat_name.to_upper()
		else:
			_mining_root.visible = false

	# Quick-slot bar visible only during gameplay (player in tree).
	if _quick_root != null:
		_quick_root.visible = true
	# Refresh the quick-slot bar's text + highlight based on the
	# current InventoryManager state. Cheap (4 label writes per frame).
	_refresh_quick_slot_bar()


func _process_quick_slot_input() -> void:
	# Number keys 1-4 equip the bound item. Only fires when the mouse
	# is captured (gameplay), so the keys don't trigger while the
	# player is interacting with menus.
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if not get_node_or_null("/root/InventoryManager"):
		return
	const ACTIONS: Array[String] = ["quick_slot_1", "quick_slot_2", "quick_slot_3", "quick_slot_4"]
	for i in ACTIONS.size():
		if Input.is_action_just_pressed(ACTIONS[i]):
			InventoryManager.equip_quick_slot(i)


func _refresh_quick_slot_bar() -> void:
	# Sync the four panels' text + highlight to the current
	# InventoryManager bindings + equipped weapon. Called every frame
	# from _process — cheap (4 string writes max), idempotent.
	if _quick_slot_panels.is_empty():
		return
	if not get_node_or_null("/root/InventoryManager"):
		return
	var equipped: String = InventoryManager.get_equipped("weapon")
	for i in _quick_slot_panels.size():
		var item_id: String = InventoryManager.get_quick_slot(i)
		# Display name from the registry, with quantity for stackables.
		var label_text: String = "—"
		if item_id != "":
			var name: String = item_id
			if InventoryManager.ITEM_REGISTRY.has(item_id):
				name = InventoryManager.ITEM_REGISTRY[item_id].get("name", item_id)
			# Show count for stackables (throwables, materials).
			var count: int = InventoryManager.get_quantity(item_id)
			if count > 1:
				label_text = "%s ×%d" % [name, count]
			else:
				label_text = name
		_quick_slot_labels[i].text = label_text

		# Highlight when this slot's item is the currently-equipped weapon.
		var is_equipped: bool = (item_id != "" and item_id == equipped)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.0, 0.0, 0.0, 0.65)
		sb.border_width_left = 2 if is_equipped else 1
		sb.border_width_top = 2 if is_equipped else 1
		sb.border_width_right = 2 if is_equipped else 1
		sb.border_width_bottom = 2 if is_equipped else 1
		sb.border_color = Color(1.0, 0.85, 0.3, 1.0) if is_equipped else Color(0.3, 0.3, 0.3, 1.0)
		_quick_slot_panels[i].add_theme_stylebox_override("panel", sb)


# =============================================================
# PLAYER LOOKUP
# =============================================================

func _find_player() -> Node:
	# Use the cached reference if it's still valid.
	if is_instance_valid(_cached_player):
		return _cached_player

	# Search by group — Player3D.tscn adds itself to the "player" group.
	var players := get_tree().get_nodes_in_group("player")
	_cached_player = players[0] if not players.is_empty() else null
	return _cached_player
