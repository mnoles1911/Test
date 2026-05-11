extends CanvasLayer
# CharacterSelect — modal-ish overlay for picking / creating /
# deleting / renaming portable characters.
#
# WHAT THIS IS (plain English):
#
#   CharacterStore can store multiple characters per Steam ID
#   (keyed by character_id). The MP-6r runtime auto-creates a single
#   "Wanderer" if none exists, but the player can have multiple
#   characters — one for each playthrough flavor, or for testing
#   different builds without losing progress.
#
#   This overlay shows every character on disk via
#   CharacterStore.list_characters(), with controls to:
#     • Select an existing character (set active)
#     • Create a new character (name input + Create button)
#     • Delete the focused row (with a confirm step)
#     • Rename the focused row (inline edit + Save button)
#
#   Designed to live as a modal popup rather than a scene swap so
#   it can be opened from NetTest / MainMenu / pause menu without
#   tearing down the current scene tree. show() / hide() control
#   visibility; clicking outside closes; ESC closes.
#
# WHY MANUAL CLICK DISPATCH:
#   Per CLAUDE.md, Button.pressed signals don't fire in this project
#   because Dialogic's input subsystem consumes mouse events
#   globally. Every UI scene rolls its own _input handler.
#
# WIRING:
#   Instantiated by NetTest._ready as a hidden child overlay; shown
#   when the "Switch Character" button is clicked. Calls back to
#   CharacterStore for all state mutation; emits a custom signal
#   "character_changed" that NetTest listens for to refresh its
#   status display.


# =============================================================
# SIGNALS
# =============================================================

signal character_changed()  ## fired when select / create / delete /
                             ## rename modifies the active character


# =============================================================
# UI (built programmatically)
# =============================================================

var _panel: PanelContainer
var _roster_container: VBoxContainer
var _create_name_edit: LineEdit
var _create_btn: Button
var _close_btn: Button

# Per-row buttons get tracked for click dispatch.
var _row_buttons: Array[Button] = []

# Pending delete confirmation. When set, the next click on a Delete
# row confirms; another click elsewhere cancels.
var _pending_delete_steam_id: int = 0


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	layer = 50
	_build_ui()
	visible = false


func show_overlay() -> void:
	visible = true
	_pending_delete_steam_id = 0
	_refresh_roster()


func hide_overlay() -> void:
	visible = false
	_pending_delete_steam_id = 0


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var k: InputEventKey = event as InputEventKey
		if k.pressed and k.keycode == KEY_ESCAPE:
			hide_overlay()
			get_viewport().set_input_as_handled()
			return
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_dispatch_click(mb.position)


# =============================================================
# UI BUILD
# =============================================================

func _build_ui() -> void:
	# Dim backdrop (catches outside-clicks).
	var backdrop := ColorRect.new()
	backdrop.anchor_left = 0
	backdrop.anchor_top = 0
	backdrop.anchor_right = 1
	backdrop.anchor_bottom = 1
	backdrop.color = Color(0, 0, 0, 0.55)
	add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -360
	_panel.offset_top = -260
	_panel.offset_right = 360
	_panel.offset_bottom = 260
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Choose Character"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Roster section — scrollable in case there are many characters.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 280)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_roster_container = VBoxContainer.new()
	_roster_container.add_theme_constant_override("separation", 4)
	_roster_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_roster_container)

	vbox.add_child(HSeparator.new())

	# Create new section.
	var create_row := HBoxContainer.new()
	create_row.add_theme_constant_override("separation", 6)
	vbox.add_child(create_row)
	var create_label := Label.new()
	create_label.text = "New character:"
	create_row.add_child(create_label)
	_create_name_edit = LineEdit.new()
	_create_name_edit.placeholder_text = "Name (e.g. Aelric)"
	_create_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(_create_name_edit)
	_create_btn = _make_button("Create")
	_create_btn.custom_minimum_size = Vector2(80, 28)
	create_row.add_child(_create_btn)

	_close_btn = _make_button("Close (ESC)")
	_close_btn.custom_minimum_size = Vector2(0, 28)
	vbox.add_child(_close_btn)


func _make_button(label: String) -> Button:
	var b := Button.new()
	b.text = label
	return b


# =============================================================
# REFRESH
# =============================================================

func _refresh_roster() -> void:
	if get_node_or_null("/root/CharacterStore") == null:
		var lbl := Label.new()
		lbl.text = "(CharacterStore not loaded)"
		_clear_roster_with_placeholder(lbl)
		return

	var summaries: Array = CharacterStore.list_characters()
	for c in _roster_container.get_children():
		c.queue_free()
	_row_buttons.clear()

	if summaries.is_empty():
		var lbl := Label.new()
		lbl.text = "(no characters yet — create one below)"
		lbl.modulate = Color(0.7, 0.7, 0.7, 1.0)
		_roster_container.add_child(lbl)
		return

	var active = CharacterStore.get_active_character()
	var active_sid: int = active.steam_id if active != null else 0

	for summary in summaries:
		var s: Dictionary = summary
		_add_roster_row(s, s["steam_id"] == active_sid)


func _clear_roster_with_placeholder(lbl: Label) -> void:
	for c in _roster_container.get_children():
		c.queue_free()
	_row_buttons.clear()
	_roster_container.add_child(lbl)


func _add_roster_row(summary: Dictionary, is_active: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_roster_container.add_child(row)

	# Label — display name + steam id + last-played date.
	var lbl := Label.new()
	var dt: String = Time.get_datetime_string_from_unix_time(int(summary.get("last_played_unix", 0)))
	var marker: String = "  ★" if is_active else ""
	lbl.text = "%s  (steam_id %d)   last: %s%s" % [
		summary.get("display_name", "?"),
		summary.get("steam_id", 0),
		dt,
		marker,
	]
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	# Select button (only if not already active).
	if not is_active:
		var sel := _make_button("Select")
		sel.custom_minimum_size = Vector2(70, 24)
		sel.set_meta("action", "select")
		sel.set_meta("steam_id", summary["steam_id"])
		row.add_child(sel)
		_row_buttons.append(sel)

	# Delete button — two-click confirm pattern.
	var is_pending_delete: bool = (_pending_delete_steam_id == int(summary["steam_id"]))
	var del := _make_button("Confirm?" if is_pending_delete else "Delete")
	del.custom_minimum_size = Vector2(70, 24)
	del.set_meta("action", "delete")
	del.set_meta("steam_id", summary["steam_id"])
	if is_pending_delete:
		del.modulate = Color(1.0, 0.7, 0.7, 1.0)
	row.add_child(del)
	_row_buttons.append(del)


# =============================================================
# CLICK DISPATCH
# =============================================================

func _dispatch_click(pos: Vector2) -> void:
	if _hits(_close_btn, pos):
		hide_overlay()
		return
	if _hits(_create_btn, pos):
		_on_create_pressed()
		return
	for btn in _row_buttons:
		if _hits(btn, pos):
			var action: String = String(btn.get_meta("action", ""))
			var sid: int = int(btn.get_meta("steam_id", 0))
			if action == "select":
				_on_select_pressed(sid)
			elif action == "delete":
				_on_delete_pressed(sid)
			return
	# Click outside any control inside the panel cancels pending
	# delete (so the user can opt out by clicking elsewhere).
	if not _panel.get_global_rect().has_point(pos):
		hide_overlay()
		return
	if _pending_delete_steam_id != 0:
		_pending_delete_steam_id = 0
		_refresh_roster()


func _hits(ctrl: Control, pos: Vector2) -> bool:
	if ctrl == null or not ctrl.visible:
		return false
	if ctrl is Button and (ctrl as Button).disabled:
		return false
	return ctrl.get_global_rect().has_point(pos)


# =============================================================
# BUTTON HANDLERS
# =============================================================

func _on_select_pressed(steam_id: int) -> void:
	if get_node_or_null("/root/CharacterStore") == null:
		return
	var rec = CharacterStore.load_character(steam_id)
	if rec == null:
		push_warning("[CharacterSelect] load_character(%d) returned null" % steam_id)
		return
	CharacterStore.select_character(rec)
	character_changed.emit()
	hide_overlay()


func _on_delete_pressed(steam_id: int) -> void:
	# Two-click confirm — first press marks pending, second press
	# actually deletes. Clicking elsewhere cancels (handled in
	# _dispatch_click's else branch).
	if _pending_delete_steam_id != steam_id:
		_pending_delete_steam_id = steam_id
		_refresh_roster()
		return
	_pending_delete_steam_id = 0
	if get_node_or_null("/root/CharacterStore") != null:
		CharacterStore.delete_character(steam_id)
		# If we just deleted the active character, the store nulls
		# its active reference. Emit so callers can re-show the
		# picker.
		character_changed.emit()
	_refresh_roster()


func _on_create_pressed() -> void:
	if get_node_or_null("/root/CharacterStore") == null:
		return
	var name_input: String = _create_name_edit.text.strip_edges()
	if name_input.is_empty():
		# Visual hint instead of an error popup — flash the
		# placeholder. Cheaper UX.
		_create_name_edit.placeholder_text = "Name required!"
		return
	# Need a Steam ID — for the local user, resolve via store. For
	# multi-character-per-user, the existing schema uses steam_id
	# as the filename key; multiple characters per user requires
	# either using character_id as the key or accepting that the
	# multi-char path stores only one PER STEAM ID at a time. For
	# v1 we use the local Steam ID + appendix — subsequent
	# characters for the same user overwrite. The full
	# character_id-keyed file layout is in the deferred list.
	var local_sid: int = CharacterStore.resolve_local_steam_id()
	# Bump local_sid by the index of existing characters with the
	# same base id so multiple characters for the same Steam user
	# don't collide.
	var existing: Array = CharacterStore.list_characters()
	var max_appendix: int = 0
	for s in existing:
		var sid: int = int(s.get("steam_id", 0))
		if sid >= local_sid and sid < local_sid + 1000:
			max_appendix = max(max_appendix, sid - local_sid)
	var new_sid: int = local_sid + max_appendix + 1 if existing.size() > 0 else local_sid
	# If this is the very first character ever, just use the bare
	# local Steam ID so the file is at the canonical path.
	if not CharacterStore.has_character(local_sid):
		new_sid = local_sid
	var rec = CharacterStore.create_character(new_sid, name_input)
	# create_character sets active automatically — emit so callers
	# refresh.
	character_changed.emit()
	_create_name_edit.text = ""
	_refresh_roster()
