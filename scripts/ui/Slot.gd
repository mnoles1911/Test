class_name UISlot
extends PanelContainer

# Reusable inventory tile — used by Inventory pack grid, Inventory equipment
# slots, HUD hotbar, future buff/debuff tray. 56×56 by default (the
# `--tile` size in menus_shared.css).
#
# Children built programmatically in _ready() — Icon (TextureRect),
# QtyLabel (Label), DurabilityBar (ColorRect strip). No scene tree edit
# required.
#
# Drag-drop uses Godot's built-in _get_drag_data / _can_drop_data /
# _drop_data API. Drop is forwarded to parent via the
# `slot_drop_received(target_slot, data)` signal so the parent inventory
# script owns swap logic (it knows about both the source and target slots).

const TILE_SIZE := 56

signal slot_clicked(slot: UISlot)
signal slot_right_clicked(slot: UISlot)
signal slot_hovered(slot: UISlot, is_hover: bool)
signal slot_drop_received(target_slot: UISlot, data: Variant)

@export var item_id: String = ""
@export var quantity: int = 0
# Range 0..1; -1 means "no condition tracked" (hide the bar).
@export var condition: float = -1.0
@export var rarity: String = "common"
@export var slot_index: int = -1  # caller-assigned, used to identify slot
# Optional category restriction — e.g. equipment "weapon" slot only accepts
# items where ITEM_REGISTRY[item_id].type == "weapon". Empty = accept all.
@export var accepts_type: String = ""
# Hotbar slot displays a hotkey number in the top-left corner.
@export var hotkey_label: String = ""

var _icon: TextureRect
var _qty_label: Label
var _dura_bar: ColorRect
var _hotkey_label_node: Label
var _is_hover := false


func _ready() -> void:
	custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_style()
	_build_children()
	_refresh_visuals()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)


func _build_children() -> void:
	# Icon — 44×44 centered.
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	# Quantity label — bottom-right, hidden if qty <= 1.
	_qty_label = Label.new()
	_qty_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_qty_label.offset_left = -22
	_qty_label.offset_top  = -16
	_qty_label.offset_right = -2
	_qty_label.offset_bottom = -2
	_qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_qty_label.add_theme_color_override("font_color", Colors.INK)
	_qty_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_qty_label.add_theme_constant_override("shadow_offset_x", 1)
	_qty_label.add_theme_constant_override("shadow_offset_y", 1)
	UIStyles.apply_body_label(_qty_label, 12)
	_qty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_qty_label)

	# Durability bar — 3px tall along the bottom.
	_dura_bar = ColorRect.new()
	_dura_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_dura_bar.offset_top = -4
	_dura_bar.offset_left = 2
	_dura_bar.offset_right = -2
	_dura_bar.offset_bottom = -2
	_dura_bar.color = Colors.RARE_UNCOMMON
	_dura_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dura_bar)

	# Hotkey label — top-left corner, only on hotbar slots.
	_hotkey_label_node = Label.new()
	_hotkey_label_node.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_hotkey_label_node.offset_left = 2
	_hotkey_label_node.offset_top  = 0
	UIStyles.apply_kbd_label(_hotkey_label_node)
	_hotkey_label_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hotkey_label_node)


func _apply_style() -> void:
	var sb := UIStyles.slot_panel_hover(rarity) if _is_hover else UIStyles.slot_panel(rarity)
	add_theme_stylebox_override("panel", sb)


func _refresh_visuals() -> void:
	if _qty_label:
		_qty_label.text = str(quantity) if quantity > 1 else ""
		_qty_label.visible = quantity > 1
	if _dura_bar:
		_dura_bar.visible = condition >= 0.0
		if condition >= 0.0:
			_dura_bar.size_flags_horizontal = 0
			# Recolor by condition: green > yellow > red.
			if condition > 0.6:
				_dura_bar.color = Colors.RARE_UNCOMMON
			elif condition > 0.3:
				_dura_bar.color = Colors.STAM
			else:
				_dura_bar.color = Colors.HP
			# Width via offset_right relative to total slot interior.
			var interior_w := float(TILE_SIZE - 4)
			_dura_bar.offset_right = -2 - int(interior_w * (1.0 - condition))
	if _hotkey_label_node:
		_hotkey_label_node.text = hotkey_label
		_hotkey_label_node.visible = hotkey_label != ""
	if _icon:
		# Icon texture is set externally via set_icon(). Just toggle visibility
		# based on whether an item is held.
		_icon.visible = item_id != "" and _icon.texture != null


# --- Public API ----------------------------------------------------------

func set_item(p_item_id: String, p_quantity: int = 1, p_condition: float = -1.0, p_rarity: String = "common") -> void:
	item_id = p_item_id
	quantity = p_quantity
	condition = p_condition
	rarity = p_rarity
	_apply_style()
	_refresh_visuals()

func set_icon(tex: Texture2D) -> void:
	if _icon:
		_icon.texture = tex
		_icon.visible = tex != null and item_id != ""

func clear() -> void:
	item_id = ""
	quantity = 0
	condition = -1.0
	rarity = "common"
	if _icon:
		_icon.texture = null
		_icon.visible = false
	_apply_style()
	_refresh_visuals()

func is_empty() -> bool:
	return item_id == ""


# --- Input ---------------------------------------------------------------

func _on_mouse_entered() -> void:
	_is_hover = true
	_apply_style()
	slot_hovered.emit(self, true)

func _on_mouse_exited() -> void:
	_is_hover = false
	_apply_style()
	slot_hovered.emit(self, false)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			slot_clicked.emit(self)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			slot_right_clicked.emit(self)


# --- Drag-drop -----------------------------------------------------------

func _get_drag_data(_at_position: Vector2) -> Variant:
	if is_empty():
		return null
	# Build a small preview Control so the user sees the icon under the cursor.
	var preview := TextureRect.new()
	preview.texture = _icon.texture if _icon else null
	preview.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	preview.modulate = Color(1, 1, 1, 0.7)
	set_drag_preview(preview)
	return {
		"from_slot": self,
		"item_id": item_id,
		"quantity": quantity,
		"condition": condition,
		"rarity": rarity,
		"slot_index": slot_index,
	}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if not data.has("item_id"):
		return false
	if data.from_slot == self:
		return false
	# If this slot has a type restriction, validate the dropped item's type.
	if accepts_type != "":
		var item_type := _lookup_item_type(data.item_id)
		if item_type != accepts_type:
			return false
	return true

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	slot_drop_received.emit(self, data)


# Look up an item's type from InventoryManager.ITEM_REGISTRY without
# depending on a class — kept defensive in case the registry shape changes.
func _lookup_item_type(p_item_id: String) -> String:
	var inv := get_node_or_null("/root/InventoryManager")
	if inv == null:
		return ""
	if not inv.has_method("get_item_type"):
		# Fall back to direct dict access if the helper isn't there yet.
		var registry: Variant = inv.get("ITEM_REGISTRY")
		if registry is Dictionary and registry.has(p_item_id):
			return String(registry[p_item_id].get("type", ""))
		return ""
	return String(inv.call("get_item_type", p_item_id))
