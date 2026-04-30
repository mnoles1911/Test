extends CanvasLayer
# JournalUI — Roland's journal overlay. KCD2-style five-tab layout.
#
# What this does in plain English:
#   When the player presses J, the journal slides over the screen.
#   Five tabs of information, all populated from GameState and InventoryManager:
#     QUESTS   — active and completed quest states (written in Roland's voice)
#     MAP      — current area description and known location notes
#     ITEMS    — equipped items and stored inventory
#     CRAFTING — known recipes and their ingredients
#     CODEX    — background lore entries (unlocked as the story progresses)
#
#   The journal is the player's primary navigation tool — no quest markers.
#   NPCs will tell the player where to go if asked.
#
# HOW TO ADD A NEW JOURNAL ENTRY:
#   QUESTS/MAP/CODEX: add a flag check block in the relevant _build_*_text() function
#   ITEMS: automatic — driven by InventoryManager
#   CRAFTING: define a recipe in InventoryManager.RECIPES + set its discovered_flag


# =============================================================
# TAB ENUM
# =============================================================

enum Tab { QUESTS, MAP, ITEMS, CRAFTING, CODEX }
var current_tab: Tab = Tab.QUESTS

const TAB_LABELS: Array = ["QUESTS", "MAP", "ITEMS", "CRAFTING", "CODEX"]


# =============================================================
# NODE REFERENCES
# =============================================================

@onready var root_control: Control   = $JournalRoot
@onready var tab_row: HBoxContainer  = $JournalRoot/Frame/VBox/TabRow
@onready var content_label: Label    = $JournalRoot/Frame/VBox/ContentScroll/ContentText
@onready var close_hint: Label       = $JournalRoot/Frame/VBox/Header/CloseHint


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	root_control.visible = false

	# Connect tab buttons (built from TAB_LABELS in the .tscn).
	var btns: Array = tab_row.get_children()
	for i in range(btns.size()):
		if btns[i] is Button:
			btns[i].pressed.connect(_on_tab_pressed.bind(i))

	print("[JournalUI] Initialized.")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_J or event.physical_keycode == KEY_J:
			if root_control.visible:
				_close()
			else:
				_open()
			get_viewport().set_input_as_handled()


# =============================================================
# OPEN / CLOSE
# =============================================================

func _open() -> void:
	root_control.visible = true
	current_tab = Tab.QUESTS
	FlagScheduler.emit_event("journal_opened")
	_refresh()
	print("[JournalUI] Opened.")

func _close() -> void:
	root_control.visible = false
	print("[JournalUI] Closed.")


# =============================================================
# TAB SWITCHING
# =============================================================

func _on_tab_pressed(tab_index: int) -> void:
	current_tab = tab_index as Tab
	_refresh()


# =============================================================
# REFRESH
# =============================================================

func _refresh() -> void:
	# Highlight the active tab button.
	var btns: Array = tab_row.get_children()
	for i in range(btns.size()):
		if btns[i] is Button:
			btns[i].modulate = Color(1, 1, 1) if i == current_tab else Color(0.55, 0.55, 0.55)

	match current_tab:
		Tab.QUESTS:   content_label.text = _build_quests_text()
		Tab.MAP:      content_label.text = _build_map_text()
		Tab.ITEMS:    content_label.text = _build_items_text()
		Tab.CRAFTING: content_label.text = _build_crafting_text()
		Tab.CODEX:    content_label.text = _build_codex_text()


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

	# Equipped items.
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

	# Stored inventory grouped by type.
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
