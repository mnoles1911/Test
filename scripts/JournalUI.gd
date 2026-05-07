extends CanvasLayer
# JournalUI — Roland's journal and inventory overlay.
#
# What this does in plain English:
#   Press J to open the overlay to the QUESTS tab.
#   Press I to open directly to the ITEMS tab (inventory).
#   Both open the same full-screen overlay — J and I just set the starting tab.
#
#   While open:
#     - Mouse cursor is visible: click any tab at the top to switch sections.
#     - Press TAB to cycle to the next section without clicking.
#     - Press J, I, or Escape to close and return to the game.
#
#   Six tabs:
#     QUESTS   — active and completed quest states (written in Roland's voice)
#     MAP      — current area and known location notes
#     ITEMS    — equipped items and carried inventory (InventoryManager)
#     CRAFTING — known recipes and their ingredients
#     CODEX    — background lore entries unlocked as the story progresses
#     SKILLS   — Roland's skill domains and earned perks (placeholder for Phase 9)
#
# The game tree is paused while the overlay is open (same as the pause menu).
# The CanvasLayer and all built nodes use PROCESS_MODE_ALWAYS so buttons work
# while the tree is paused.
#
# HOW TO ADD A NEW JOURNAL ENTRY:
#   QUESTS/MAP/CODEX: add a flag check block in the relevant _build_*_text() function.
#   ITEMS: automatic — driven by InventoryManager.
#   CRAFTING: define a recipe in InventoryManager.RECIPES + set its discovered_flag.
#   SKILLS: will be driven by GameState skill XP once Phase 9-3D is built.


# =============================================================
# TABS
# =============================================================

enum Tab { QUESTS, MAP, ITEMS, CRAFTING, CODEX, SKILLS }
const TAB_COUNT: int = 6
const TAB_NAMES: Array = ["QUESTS", "MAP", "ITEMS", "CRAFTING", "CODEX", "SKILLS"]


# =============================================================
# BUILT NODES (created in _build_ui, stored for refresh)
# =============================================================

var _root: Control
var _tab_buttons: Array = []
var _content_label: Label
var _current_tab: Tab = Tab.QUESTS


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	layer = 10
	# PROCESS_MODE_ALWAYS is required so the overlay works while the game
	# tree is paused (same reason PauseMenu uses it).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = false
	print("[JournalUI] Initialized.")


func _build_ui() -> void:
	# Full-screen root node. ALWAYS mode so it responds while tree is paused.
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_root)

	# Voxelmark-night backdrop covering the whole screen.
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(Colors.BG_NIGHT.r, Colors.BG_NIGHT.g, Colors.BG_NIGHT.b, 0.78)
	_root.add_child(backdrop)

	# Main frame — anchored full-rect with 80px inset on each side.
	# At 1920×1080 this gives a ~1760×960 content area.
	# Oak-gradient menu chrome from UIStyles, matching the pause menu.
	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left   =  80
	frame.offset_top    =  60
	frame.offset_right  = -80
	frame.offset_bottom = -60
	frame.add_theme_stylebox_override("panel", UIStyles.menu_body_panel())
	_root.add_child(frame)

	# Vertical layout for everything inside the frame.
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   =  24
	vbox.offset_top    =  18
	vbox.offset_right  = -24
	vbox.offset_bottom = -18
	vbox.add_theme_constant_override("separation", 10)
	frame.add_child(vbox)

	# --- Header row ---
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "ROLAND'S JOURNAL"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIStyles.apply_title_label(title, 32)
	header.add_child(title)

	var hint := Label.new()
	hint.text = "[ J / I / ESC ] close     [ TAB ] next section"
	UIStyles.apply_muted_label(hint, 14)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(hint)

	# --- Divider ---
	var div1 := ColorRect.new()
	div1.custom_minimum_size = Vector2(0, 2)
	div1.color = Colors.PANEL_OAK_EDGE
	vbox.add_child(div1)

	# --- Tab row ---
	# Six buttons, equally wide. Clicking any switches the content below.
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 6)
	vbox.add_child(tab_row)

	_tab_buttons.clear()
	for i in range(TAB_COUNT):
		var btn := Button.new()
		btn.text = TAB_NAMES[i]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 46)
		btn.process_mode = Node.PROCESS_MODE_ALWAYS
		btn.focus_mode = Control.FOCUS_NONE
		# Active styling is applied each refresh; start as inactive.
		UIStyles.apply_tab_button(btn, false)
		btn.pressed.connect(_on_tab_pressed.bind(i))
		tab_row.add_child(btn)
		_tab_buttons.append(btn)

	# --- Divider 2 ---
	var div2 := ColorRect.new()
	div2.custom_minimum_size = Vector2(0, 2)
	div2.color = Colors.PANEL_OAK_EDGE
	vbox.add_child(div2)

	# --- Scrollable content area (fills remaining vertical space) ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_content_label = Label.new()
	_content_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIStyles.apply_body_label(_content_label, 18)
	_content_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll.add_child(_content_label)


# =============================================================
# INPUT
# =============================================================

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	# Dev-scene guard — BakeWorld / CopperIslesTest / any scene in the
	# "dev_scene" group keeps the journal overlay dormant. Close it if
	# it's somehow open already.
	if get_node_or_null("/root/GameState") and GameState.is_dev_scene():
		if _root.visible:
			_close()
		return

	if _root.visible:
		# TAB cycles to the next section. This must be checked before the
		# action checks below because Tab key might also match "ui_focus_next".
		if event.physical_keycode == KEY_TAB:
			_current_tab = ((_current_tab + 1) % TAB_COUNT) as Tab
			_refresh()
			get_viewport().set_input_as_handled()
			return
		# J, I, or Escape all close the overlay.
		# set_input_as_handled() prevents Escape from also opening PauseMenu.
		if event.is_action("open_journal") or event.is_action("open_inventory") or event.is_action("pause"):
			_close()
			get_viewport().set_input_as_handled()
	else:
		# J opens to Quests, I opens to Items.
		if event.is_action("open_journal"):
			_open(Tab.QUESTS)
			get_viewport().set_input_as_handled()
		elif event.is_action("open_inventory"):
			_open(Tab.ITEMS)
			get_viewport().set_input_as_handled()


# =============================================================
# OPEN / CLOSE
# =============================================================

func _open(tab: Tab) -> void:
	_current_tab = tab
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	print("[JournalUI] Opened.")


func _close() -> void:
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("[JournalUI] Closed.")


func is_overlay_visible() -> bool:
	# Called by PauseMenu._unhandled_input to avoid opening over this overlay.
	return _root != null and _root.visible


# =============================================================
# TAB SWITCHING
# =============================================================

func _on_tab_pressed(tab_index: int) -> void:
	_current_tab = tab_index as Tab
	_refresh()


# =============================================================
# REFRESH
# =============================================================

func _refresh() -> void:
	# Active tab gets the gold-seam oak panel; inactive tabs sit flat
	# with a dimmed ink colour. Both via UIStyles.apply_tab_button so
	# the chrome stays in lockstep with PauseMenu / MainMenu palette
	# changes.
	for i in range(_tab_buttons.size()):
		UIStyles.apply_tab_button(_tab_buttons[i], i == _current_tab)

	match _current_tab:
		Tab.QUESTS:   _content_label.text = _build_quests_text()
		Tab.MAP:      _content_label.text = _build_map_text()
		Tab.ITEMS:    _content_label.text = _build_items_text()
		Tab.CRAFTING: _content_label.text = _build_crafting_text()
		Tab.CODEX:    _content_label.text = _build_codex_text()
		Tab.SKILLS:   _content_label.text = _build_skills_text()


# =============================================================
# QUEST LOG
# Written in Roland's voice. Edit as new flags are added.
# =============================================================

func _build_quests_text() -> String:
	var lines: Array = []
	lines.append("═══ MAIN ═══\n")

	if GameState.get_flag("game_one_complete"):
		lines.append("The binding is renewed. Vaeroth's counterstroke survived.\nWe leave the Ashfields. Khorumzad is next.")
	elif GameState.get_flag("binding_renewed"):
		lines.append("The Crown is assembled. The binding holds — for now.\nValeroth's forces are between us and the exit.")
	elif GameState.get_flag("pommel_piece_1_acquired"):
		var pieces: int = _count_crown_pieces()
		lines.append("Piece 1 of 7 acquired. I need the others.\n%d / 7 pieces in hand." % pieces)
	else:
		lines.append("Something is wrong at the Iron Chalice chapel.\nHenrietta had notes. I need to find them.")

	lines.append("")

	if GameState.get_flag("henrietta_dead") and not GameState.get_flag("pommel_piece_1_acquired"):
		lines.append("═══ IMMEDIATE ═══\n")
		lines.append("Henrietta is dead. Her room was searched.\nThe Archive restricted section — Tomlin knows something.")

	if GameState.get_flag("tomlin_helped") and not GameState.get_flag("pommel_piece_1_acquired"):
		lines.append("Tomlin gave me the restricted section access.\nThe pommel is in the Iron Chalice chapel.")

	var has_side: bool = false
	if GameState.get_flag("ashsteel_formula_found"):
		if not has_side:
			lines.append("\n═══ THREADS ═══\n")
			has_side = true
		lines.append("The Ashsteel formula. Orvin had part of it.\nSomeone else has the rest.")

	if lines.size() <= 2:
		lines.append("I don't know enough yet to know what I'm doing.")

	return "\n".join(lines)


# =============================================================
# MAP
# Location notes written in Roland's voice.
# Add new location blocks as areas are visited.
# =============================================================

func _build_map_text() -> String:
	var lines: Array = []
	var current: String = GameState.current_scene

	lines.append("═══ CURRENT LOCATION ═══\n")

	if "aldenholt" in current.to_lower() or current == "":
		lines.append("ALDENHOLT\n")
		lines.append("A Brotherhood city — or what passes for one this far east.\nThe Archive is north of the square. The Iron Chalice chapter is south.\n")
		if GameState.get_flag("met_henrietta"):
			lines.append("[ Archive entrance — where Henrietta found me ]")
		if GameState.get_flag("pommel_location_known"):
			lines.append("[ Iron Chalice chapel — pommel is here ]")
	else:
		lines.append("No map data for current location.")

	lines.append("\n\n═══ KNOWN LOCATIONS ═══\n")

	if GameState.get_flag("vosskara_known"):
		lines.append("VOSSKARA\nCoastal city, three days east of Aldenholt.\nYaromir operates from the docks.\n")

	if GameState.get_flag("caer_brannoch_known"):
		lines.append("CAER BRANNOCH\nBrotherhood fortress-archive. Northern Spine of Mira.\nOrion said to find him there if I needed a cartographer.\n")

	if GameState.get_flag("khorumzad_known"):
		lines.append("KHORUMZAD\nDwarven city-kingdom. Below the Spine.\nThis is where the vault is — under Khorumzad, not Drûn-Khazad.\n")

	return "\n".join(lines)


# =============================================================
# INVENTORY
# Reads directly from InventoryManager.
# =============================================================

func _build_items_text() -> String:
	var lines: Array = []

	lines.append("═══ EQUIPPED ═══\n")
	var equipped: Dictionary = InventoryManager.get_all_equipped()
	var any_equipped: bool = false
	for slot in equipped.keys():
		var item_id: String = equipped[slot]
		if item_id != "":
			any_equipped = true
			var item_name: String = _item_display_name(item_id)
			lines.append("%s   %s" % [slot.to_upper(), item_name])
	if not any_equipped:
		lines.append("Nothing equipped.")

	lines.append("\n")

	var all_items: Dictionary = InventoryManager.get_all_items()
	if all_items.is_empty():
		lines.append("═══ CARRIED ═══\n")
		lines.append("Inventory is empty.")
		return "\n".join(lines)

	var by_type: Dictionary = {}
	for item_id in all_items.keys():
		var info: Dictionary = InventoryManager.ITEM_REGISTRY.get(item_id, {})
		var type: String = info.get("type", "misc")
		if not by_type.has(type):
			by_type[type] = []
		by_type[type].append({"id": item_id, "qty": all_items[item_id], "name": info.get("name", item_id)})

	var type_order: Array = ["crown_piece", "key_item", "weapon", "armor", "crafting_mat", "misc"]
	var type_headers: Dictionary = {
		"crown_piece": "═══ CROWN PIECES ═══",
		"key_item":    "═══ KEY ITEMS ═══",
		"weapon":      "═══ WEAPONS ═══",
		"armor":       "═══ ARMOR ═══",
		"crafting_mat":"═══ MATERIALS ═══",
		"misc":        "═══ MISC ═══",
	}

	for type in type_order:
		if not by_type.has(type):
			continue
		lines.append("\n" + type_headers.get(type, "═══ %s ═══" % type.to_upper()) + "\n")
		for entry in by_type[type]:
			var qty_str: String = "" if entry["qty"] == 1 else " ×%d" % entry["qty"]
			lines.append("%s%s" % [entry["name"], qty_str])

	return "\n".join(lines)


# =============================================================
# CRAFTING
# Shows known recipes and whether they can be crafted now.
# =============================================================

func _build_crafting_text() -> String:
	var lines: Array = []
	lines.append("═══ KNOWN RECIPES ═══\n")

	var recipes: Array = InventoryManager.get_known_recipes()
	var known: Array = recipes.filter(func(r): return r["discovered"])

	if known.is_empty():
		lines.append("No recipes discovered yet.")
		return "\n".join(lines)

	for recipe in known:
		var status: String = "[CRAFT]" if recipe["can_craft"] else "[need materials]"
		lines.append("%s   %s" % [recipe["name"], status])
		for ingredient in recipe["ingredients"]:
			var have: int = InventoryManager.get_quantity(ingredient["id"])
			var need: int = ingredient["qty"]
			var item_name: String = _item_display_name(ingredient["id"])
			var ok: String = "✓" if have >= need else "✗"
			lines.append("  %s  %s  %d/%d" % [ok, item_name, have, need])
		lines.append("")

	return "\n".join(lines)


# =============================================================
# CODEX
# Background lore entries unlocked as flags are set.
# Written in-world — not in Roland's voice, but as record entries.
# Add new blocks as new flags unlock lore.
# =============================================================

func _build_codex_text() -> String:
	var lines: Array = []
	var has_entries: bool = false

	if GameState.get_flag("codex_sundered_crown"):
		has_entries = true
		lines.append("THE SUNDERED CROWN\n")
		lines.append("Seven pieces. Separated at the end of the Second Age and distributed to prevent any single power from using the binding. The binding itself is older than the Crown — the Crown is the tool used to renew it.\n")

	if GameState.get_flag("codex_ashfallen"):
		has_entries = true
		lines.append("THE ASHFALLEN\n")
		lines.append("People hollowed by exposure to Ash Throne influence. Not dead — still aware, still moving — but the will has been replaced. A soldier becomes a function: attack, hold, advance. The Ashfallen do not have tactics. They have only direction.\n")

	if GameState.get_flag("codex_vaeroth"):
		has_entries = true
		lines.append("VAEROTH\n")
		lines.append("First known name for the Ash Throne's primary agent in the Third Age. Not confirmed to be a single person. The Brotherhood believes it is a title, not an individual.\n")

	if GameState.get_flag("codex_brotherhood"):
		has_entries = true
		lines.append("THE BROTHERHOOD\n")
		lines.append("A scholarly and martial order founded in the late Second Age to maintain the binding infrastructure. Originally non-political. Currently: deeply political, internally fractured, and aware that something is wrong with the archive records.\n")

	if GameState.get_flag("codex_aelorin"):
		has_entries = true
		lines.append("THE AELORIN\n")
		lines.append("The original inhabitants of Mira. Ancient, dwindling. They do not speak to outsiders about what they know. The Greatwood is still theirs — no army has entered it and returned.\n")

	if not has_entries:
		return "No codex entries yet.\n\nLore is recorded here as it is discovered."

	return "\n".join(lines)


# =============================================================
# SKILLS
# Placeholder until GameState tracks skill XP and perk points.
# Build out in Phase 9-3D per design/SKILLS_AND_PROGRESSION.md.
# =============================================================

func _build_skills_text() -> String:
	var lines: Array = []
	lines.append("═══ SKILLS ═══\n")
	lines.append("Skill tracking is not yet implemented.\n")
	lines.append("Roland's skill domains, sub-skills, earned perks, and\n")
	lines.append("available perk points will appear here once the progression\n")
	lines.append("system is built in Phase 9-3D.\n\n")
	lines.append("Reference: design/SKILLS_AND_PROGRESSION.md")
	return "\n".join(lines)


# =============================================================
# UTILITY
# =============================================================

func _item_display_name(item_id: String) -> String:
	var info: Dictionary = InventoryManager.ITEM_REGISTRY.get(item_id, {})
	return info.get("name", item_id)


func _count_crown_pieces() -> int:
	var count: int = 0
	for flag in ["pommel_piece_1_acquired", "bronze_ring_acquired", "copper_wire_acquired",
				 "silver_clasp_acquired", "gold_coin_acquired", "copper_disc_acquired",
				 "obsidian_shard_acquired"]:
		if GameState.get_flag(flag):
			count += 1
	return count
