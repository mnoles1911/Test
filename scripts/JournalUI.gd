extends CanvasLayer
# JournalUI — Roland's journal overlay.
#
# What this does in plain English:
#   When the player presses J, a journal panel slides over the screen.
#   It shows three tabs of information populated from GameState:
#     QUESTS — active and completed quest states
#     PEOPLE — brief notes on everyone Roland has met
#     CROWN  — which pieces of the Sundered Crown are known / acquired
#
#   The journal is written in Roland's voice — partial, sometimes wrong,
#   updated as flags change. The text shown in each tab is built by
#   _build_quests_text(), _build_people_text(), and _build_crown_text()
#   at the bottom of this file. Edit those functions as new content is added.
#
# DESIGN NOTE (from design/SYSTEMS_DESIGN.md):
#   The journal is the player's primary navigation tool — there are no quest
#   markers in this game. NPCs will tell the player where to go if asked.
#
# HOW TO ADD A NEW JOURNAL ENTRY:
#   1. Set a GameState flag when the event happens (e.g. set_flag("met_yaromir", true))
#   2. Add a block to the relevant _build_*_text() function below that checks
#      that flag and appends the right text

# The layer number is set in the .tscn (layer = 10). Here we just handle logic.

# =============================================================
# TAB ENUM
# =============================================================

enum Tab { QUESTS, PEOPLE, CROWN }
var current_tab: Tab = Tab.QUESTS


# =============================================================
# NODE REFERENCES
# Paths assume the structure defined in scenes/ui/Journal.tscn
# =============================================================

@onready var root_control: Control   = $JournalRoot
@onready var quests_btn: Button      = $JournalRoot/Frame/VBox/TabRow/QuestsBtn
@onready var people_btn: Button      = $JournalRoot/Frame/VBox/TabRow/PeopleBtn
@onready var crown_btn: Button       = $JournalRoot/Frame/VBox/TabRow/CrownBtn
@onready var content_label: Label    = $JournalRoot/Frame/VBox/ContentScroll/ContentText
@onready var close_hint: Label       = $JournalRoot/Frame/VBox/Header/CloseHint


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# Journal starts hidden.
	root_control.visible = false

	# Connect tab buttons.
	quests_btn.pressed.connect(_on_quests_pressed)
	people_btn.pressed.connect(_on_people_pressed)
	crown_btn.pressed.connect(_on_crown_pressed)

	print("[JournalUI] Initialized.")


func _unhandled_input(event: InputEvent) -> void:
	# Toggle journal open/close with J key.
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
	_refresh()
	print("[JournalUI] Journal opened.")

func _close() -> void:
	root_control.visible = false
	print("[JournalUI] Journal closed.")


# =============================================================
# TAB BUTTONS
# =============================================================

func _on_quests_pressed() -> void:
	current_tab = Tab.QUESTS
	_refresh()

func _on_people_pressed() -> void:
	current_tab = Tab.PEOPLE
	_refresh()

func _on_crown_pressed() -> void:
	current_tab = Tab.CROWN
	_refresh()


# =============================================================
# REFRESH — rebuilds content for the current tab
# =============================================================

func _refresh() -> void:
	# Highlight the active tab button (grey = inactive, white = active).
	quests_btn.modulate = Color(1, 1, 1) if current_tab == Tab.QUESTS else Color(0.6, 0.6, 0.6)
	people_btn.modulate = Color(1, 1, 1) if current_tab == Tab.PEOPLE else Color(0.6, 0.6, 0.6)
	crown_btn.modulate  = Color(1, 1, 1) if current_tab == Tab.CROWN  else Color(0.6, 0.6, 0.6)

	match current_tab:
		Tab.QUESTS: content_label.text = _build_quests_text()
		Tab.PEOPLE: content_label.text = _build_people_text()
		Tab.CROWN:  content_label.text = _build_crown_text()


# =============================================================
# CONTENT BUILDERS
# Each function reads GameState flags and assembles journal text.
# Write in Roland's voice — first person, observational, sometimes uncertain.
# Add new blocks here as new flags are defined.
# =============================================================

func _build_quests_text() -> String:
	var lines: Array = []

	# --- Main quest ---
	lines.append("═══ MAIN ═══\n")

	if GameState.get_flag("game_one_complete"):
		lines.append("The binding is renewed. Vaeroth's counterstroke survived.\nWe leave the Ashfields. Khorumzad is next.")
	elif GameState.get_flag("binding_renewed"):
		lines.append("The Crown is assembled. The binding holds — for now.\nValeroth's forces are between us and the exit.")
	elif GameState.get_flag("pommel_piece_1_acquired"):
		var pieces = _count_crown_pieces()
		lines.append("Piece 1 of 7 acquired. I need the others.\n%d / 7 pieces in hand." % pieces)
	else:
		lines.append("Something is wrong at the Iron Chalice chapel.\nHenrietta had notes. I need to find them.")

	lines.append("\n")

	# --- Act I flags ---
	if GameState.get_flag("henrietta_dead") and not GameState.get_flag("pommel_piece_1_acquired"):
		lines.append("═══ IMMEDIATE ═══\n")
		lines.append("Henrietta is dead. Her room was searched.\nThe Archive restricted section — Tomlin knows something.")

	if GameState.get_flag("tomlin_helped") and not GameState.get_flag("pommel_piece_1_acquired"):
		lines.append("Tomlin gave me the restricted section access.\nThe pommel is in the Iron Chalice chapel.")

	# --- Side quest hooks ---
	var has_side = false
	if GameState.get_flag("ashsteel_formula_found"):
		if not has_side:
			lines.append("\n═══ THREADS ═══\n")
			has_side = true
		lines.append("The Ashsteel formula. Orvin had part of it.\nSomeone else has the rest.")

	if lines.size() == 0 or (lines.size() == 1 and lines[0].contains("═══ MAIN ═══")):
		lines.append("I don't know enough yet to know what I'm doing.")

	return "\n".join(lines)


func _build_people_text() -> String:
	var lines: Array = []
	var has_entries = false

	if GameState.get_flag("met_henrietta") or GameState.get_flag("henrietta_dead"):
		has_entries = true
		lines.append("HENRIETTA\n")
		if GameState.get_flag("henrietta_dead"):
			lines.append("Dead. Room searched before I got there.\nShe passed me something at the door. That was the last I saw her.\n")
		else:
			lines.append("Archive scholar. Knows where everything is and refuses to write any of it down.\nShe found something. She was careful about who she told.\n")

	if GameState.get_flag("met_tomlin"):
		has_entries = true
		lines.append("TOMLIN\n")
		if GameState.get_flag("tomlin_helped"):
			lines.append("Archive assistant. Gave me access. He was afraid, but he did it.\n")
		else:
			lines.append("Archive assistant. Careful. Won't move without reason.\n")

	if GameState.get_flag("met_dame_calla"):
		has_entries = true
		lines.append("DAME CALLA THRESH\n")
		lines.append("Grandmaster of the Iron Chalice. Expelled me three years ago.\nShe was right to do it. That doesn't make this easier.\n")

	if GameState.get_flag("aldric_vane_name_logged"):
		has_entries = true
		lines.append("ALDRIC VANE\n")
		lines.append("A name in the Archive records. Henrietta had been tracing it.\nI don't know why yet. I wrote it down anyway.\n")

	if GameState.get_flag("orion_joined"):
		has_entries = true
		lines.append("ORION FARR\n")
		lines.append("Brotherhood cartographer. Found me at the docks before I found him.\nHe watches the exits in every room. I've started doing it too.\n")

	if GameState.get_flag("dagna_joined"):
		has_entries = true
		lines.append("DAGNA IRONTRACK\n")
		lines.append("Dragon-Watcher. Her records were falsified by someone above her.\nShe came the same direction as me. We're solving the same problem.\n")

	if not has_entries:
		return "No entries yet.\n\nNames get recorded here as I meet people."

	return "\n".join(lines)


func _build_crown_text() -> String:
	var lines: Array = []
	lines.append("THE SUNDERED CROWN\n")
	lines.append("Seven pieces. Separated at the end of the Second Age\nand distributed to keep anyone from using the binding.\n\n")

	# Piece 1 — Iron pommel
	if GameState.get_flag("pommel_piece_1_acquired"):
		lines.append("[✓] IRON POMMEL — acquired\n    Iron Chalice chapel, Aldenholt\n")
	elif GameState.get_flag("pommel_location_known"):
		lines.append("[ ] IRON POMMEL — known location\n    Iron Chalice chapel\n")
	else:
		lines.append("[ ] PIECE 1 — unknown\n")

	# Piece 2 — Bronze ring (Vosskara)
	if GameState.get_flag("bronze_ring_acquired"):
		lines.append("[✓] BRONZE RING — acquired\n    Yaromir gave it freely\n")
	elif GameState.get_flag("vosskara_committed"):
		lines.append("[ ] BRONZE RING — Yaromir has it\n    He'll give it once committed\n")

	# Piece 3 — Copper wire (Caer Brannoch)
	if GameState.get_flag("copper_wire_acquired"):
		lines.append("[✓] COPPER WIRE — acquired\n    Brotherhood Archive\n")

	# Piece 4 — Silver clasp (Aelorin Greatwood)
	if GameState.get_flag("silver_clasp_acquired"):
		lines.append("[✓] SILVER CLASP — acquired\n    The Second Glade\n")

	# Piece 5 — Gold coin (Solgrade)
	if GameState.get_flag("gold_coin_acquired"):
		lines.append("[✓] GOLD COIN — acquired\n    House Korvath\n")

	# Piece 6 — Copper disc (Karaz-Dûn)
	if GameState.get_flag("copper_disc_acquired"):
		lines.append("[✓] COPPER DISC — acquired\n    Thrarin's treasury, Karaz-Dûn\n")

	# Piece 7 — Obsidian shard (Mor-Vethrin)
	if GameState.get_flag("obsidian_shard_acquired"):
		lines.append("[✓] OBSIDIAN SHARD — acquired\n    Serethi's vault, Mor-Vethrin\n")

	var pieces = _count_crown_pieces()
	lines.append("\n%d / 7 pieces in hand." % pieces)

	if GameState.get_flag("crown_assembled"):
		lines.append("\n\nThe Crown is assembled.\nIt is not what it was — reassembled, not restored.\nSomething in how the pieces fit is different now.")

	return "\n".join(lines)


# =============================================================
# UTILITY
# =============================================================

func _count_crown_pieces() -> int:
	var count = 0
	var piece_flags = [
		"pommel_piece_1_acquired", "bronze_ring_acquired", "copper_wire_acquired",
		"silver_clasp_acquired", "gold_coin_acquired", "copper_disc_acquired",
		"obsidian_shard_acquired"
	]
	for flag in piece_flags:
		if GameState.get_flag(flag):
			count += 1
	return count
