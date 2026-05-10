class_name UIMenuTabBar
extends HBoxContainer

# Tab bar shared by Inventory / Map / Journal / Codex / Skills (the five
# .menu-tabs HTMLs in assets/ui/html/). Tabs + a spacer + a close button.
#
# Children built programmatically in _ready() so callers don't need to wire
# them up — they just set `active_tab` and connect to `tab_changed` /
# `close_pressed`.

enum Tab {
	INVENTORY = 0,
	MAP = 1,
	JOURNAL = 2,
	CODEX = 3,
	SKILLS = 4,
}

const TAB_LABELS := {
	Tab.INVENTORY: "INVENTORY",
	Tab.MAP: "MAP",
	Tab.JOURNAL: "JOURNAL",
	Tab.CODEX: "CODEX",
	Tab.SKILLS: "SKILLS",
}

signal tab_changed(tab: int)
signal close_pressed

@export var active_tab: int = Tab.INVENTORY :
	set(value):
		active_tab = value
		_refresh_tab_styles()

var _tab_buttons: Dictionary = {}  # Tab enum -> Button
var _close_button: Button


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	_build_tabs()
	_build_spacer_and_close()
	_refresh_tab_styles()


func _build_tabs() -> void:
	for tab_id in [Tab.INVENTORY, Tab.MAP, Tab.JOURNAL, Tab.CODEX, Tab.SKILLS]:
		var btn := Button.new()
		btn.text = TAB_LABELS[tab_id]
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_tab_pressed.bind(tab_id))
		add_child(btn)
		_tab_buttons[tab_id] = btn


func _build_spacer_and_close() -> void:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(spacer)

	_close_button = Button.new()
	_close_button.text = "CLOSE [ESC]"
	_close_button.focus_mode = Control.FOCUS_NONE
	UIStyles.apply_menu_button(_close_button)
	_close_button.pressed.connect(func(): close_pressed.emit())
	add_child(_close_button)


func _refresh_tab_styles() -> void:
	for tab_id in _tab_buttons.keys():
		var btn: Button = _tab_buttons[tab_id]
		UIStyles.apply_tab_button(btn, tab_id == active_tab)


func _on_tab_pressed(tab_id: int) -> void:
	if tab_id == active_tab:
		return
	active_tab = tab_id
	tab_changed.emit(tab_id)
