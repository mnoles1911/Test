extends Node
# HelloSteam — MP-0 acceptance test for the GodotSteam plugin.
#
# WHAT THIS DOES (plain English):
#
#   This is a tiny dev scene that proves the GodotSteam GDExtension is
#   installed and working on your machine. It does NOT do anything
#   gameplay-related. Three buttons:
#
#     1. INIT STEAM  — calls Steam.steamInitEx() and prints whether the
#                      Steam client picked us up. Shows your Steam name
#                      and ID. If this fails, nothing else will work.
#     2. CREATE LOBBY — creates a friends-only Steam lobby with max 10
#                       members and prints the lobby ID. Your friends
#                       on Steam can now see this lobby in their list
#                       AND in their Steam friends-list UI.
#     3. LIST LOBBIES — asks Steam for all visible lobbies among your
#                       friends and prints what comes back.
#
#   The MP-0 milestone is "complete" when two Godot+Steam instances
#   (on two friend Steam accounts) can run this scene and see each
#   other's lobbies. We then build MP-1 (transport abstraction +
#   connection lifecycle) on top.
#
# DEFENSIVE LOADING:
#   GodotSteam is NOT vendored in the repo — see addons/godotsteam/
#   INSTALL.md. If the plugin is missing, this script must not crash
#   the editor or prevent the rest of the project from loading. We
#   look up the `Steam` singleton at runtime via
#   `Engine.get_singleton("Steam")`. All calls go through `_steam.call(
#   "method_name", args)` so the parser never resolves Steam-specific
#   symbols at compile time.
#
#   That means we also can't reference Steam.LOBBY_TYPE_FRIENDS_ONLY
#   directly. Hardcoded as integer constants below, sourced from the
#   GodotSteam docs (https://godotsteam.com/classes/matchmaking/).
#
# WHY MANUAL CLICK DISPATCH:
#   Per CLAUDE.md "Critical GDScript patterns", Button.pressed never
#   fires in this project (Dialogic's input subsystem consumes mouse
#   events globally). Every UI scene rolls its own _input handler and
#   routes clicks via rect-checks. We follow that pattern here from
#   the first commit so we don't have to debug it later.
#
# Attached to the root Node of scenes/_dev/HelloSteam.tscn.


# =============================================================
# CONSTANTS (from GodotSteam — hardcoded because we can't reference
# Steam.* symbols at parse time if the plugin isn't installed)
# =============================================================

# Steam lobby visibility. We use FRIENDS_ONLY for co-op.
const LOBBY_TYPE_PRIVATE: int = 0
const LOBBY_TYPE_FRIENDS_ONLY: int = 1
const LOBBY_TYPE_PUBLIC: int = 2
const LOBBY_TYPE_INVISIBLE: int = 3

const MAX_LOBBY_MEMBERS: int = 10

# Spacewar — Steam's free public test App ID. We use this until the
# real Mira-Thal App ID is provisioned via Steamworks partner setup.
const APP_ID_SPACEWAR: int = 480


# =============================================================
# STATE
# =============================================================

var _steam: Object = null           # The Steam singleton, or null if not installed.
var _steam_initialized: bool = false
var _last_lobby_id: int = 0
var _last_lobbies_found: Array = []


# =============================================================
# UI (built programmatically — see _build_ui)
# =============================================================

var _ui_root: CanvasLayer
var _status_label: Label
var _output_label: Label
var _init_btn: Button
var _create_btn: Button
var _list_btn: Button
var _quit_btn: Button


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	# Dev scenes opt out of gameplay UI (HUDOverlay, PauseMenu, etc.)
	# via the dev_scene group. See CLAUDE.md "Dev-scene group
	# convention".
	add_to_group("dev_scene")

	_resolve_steam_singleton()
	_build_ui()
	_refresh_status()

	# If Steam is present and someone else already initialized it
	# earlier in the editor session, we still want this scene's signal
	# handlers connected. Always wire up — connection is idempotent.
	_connect_steam_signals()


func _process(_delta: float) -> void:
	# GodotSteam requires run_callbacks() to be pumped every frame so
	# the Steam client can deliver async results (lobby_created etc.)
	# back into Godot. Some versions of the plugin do this internally;
	# calling it here is safe either way.
	if _steam != null and _steam_initialized:
		_steam.call("run_callbacks")


func _input(event: InputEvent) -> void:
	# Manual mouse-click dispatch. Button.pressed signals never fire
	# in this project — see CLAUDE.md "Critical GDScript patterns".
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_dispatch_click(mb.position)


# =============================================================
# STEAM RESOLUTION + SIGNAL WIRING
# =============================================================

func _resolve_steam_singleton() -> void:
	# Try the Engine singleton first (how GodotSteam 4.x exposes itself
	# once the .gdextension is loaded). Fall back to a /root autoload
	# lookup in case a future plugin version switches mechanisms.
	if Engine.has_singleton("Steam"):
		_steam = Engine.get_singleton("Steam")
		return
	var node := get_node_or_null("/root/Steam")
	if node != null:
		_steam = node


func _connect_steam_signals() -> void:
	if _steam == null:
		return
	# lobby_created(connect_result, lobby_id) — fired after createLobby.
	if _steam.has_signal("lobby_created"):
		if not _steam.is_connected("lobby_created", _on_lobby_created):
			_steam.connect("lobby_created", _on_lobby_created)
	# lobby_match_list(lobbies) — fired after requestLobbyList.
	if _steam.has_signal("lobby_match_list"):
		if not _steam.is_connected("lobby_match_list", _on_lobby_match_list):
			_steam.connect("lobby_match_list", _on_lobby_match_list)


# =============================================================
# UI BUILD
# =============================================================

func _build_ui() -> void:
	_ui_root = CanvasLayer.new()
	_ui_root.layer = 10
	add_child(_ui_root)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -260
	panel.offset_top = -180
	panel.offset_right = 260
	panel.offset_bottom = 180
	_ui_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "MP-0  ·  Hello Steam"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_status_label = Label.new()
	_status_label.text = "(status)"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)

	_init_btn = _make_button("Init Steam")
	vbox.add_child(_init_btn)
	_create_btn = _make_button("Create Lobby (friends-only, 10 slots)")
	vbox.add_child(_create_btn)
	_list_btn = _make_button("List Friends' Lobbies")
	vbox.add_child(_list_btn)
	_quit_btn = _make_button("Quit")
	vbox.add_child(_quit_btn)

	var output_panel := PanelContainer.new()
	output_panel.custom_minimum_size = Vector2(0, 120)
	vbox.add_child(output_panel)
	_output_label = Label.new()
	_output_label.text = "(no output yet)"
	_output_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_output_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	output_panel.add_child(_output_label)


func _make_button(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(0, 36)
	return b


# =============================================================
# CLICK ROUTING
# =============================================================

func _dispatch_click(pos: Vector2) -> void:
	if _hits(_init_btn, pos):
		_on_init_pressed()
		return
	if _hits(_create_btn, pos):
		_on_create_pressed()
		return
	if _hits(_list_btn, pos):
		_on_list_pressed()
		return
	if _hits(_quit_btn, pos):
		get_tree().quit()
		return


func _hits(ctrl: Control, pos: Vector2) -> bool:
	if ctrl == null or not ctrl.visible:
		return false
	if ctrl is Button and (ctrl as Button).disabled:
		return false
	return ctrl.get_global_rect().has_point(pos)


# =============================================================
# BUTTON HANDLERS
# =============================================================

func _on_init_pressed() -> void:
	if _steam == null:
		_log("Steam singleton not found. The GodotSteam plugin isn't installed.\nSee addons/godotsteam/INSTALL.md.")
		return
	if _steam_initialized:
		_log("Steam was already initialized this session.")
		_refresh_status()
		return

	# steamInitEx(app_id, embed_callbacks) is the GodotSteam 4.x signature.
	# Returns a Dictionary { status, verbal } describing the result.
	var result: Variant = _steam.call("steamInitEx", APP_ID_SPACEWAR, true)
	if typeof(result) == TYPE_DICTIONARY:
		var status: int = int(result.get("status", -1))
		var verbal: String = String(result.get("verbal", "(no verbal)"))
		_log("steamInitEx → status=%d  verbal=%s" % [status, verbal])
		# Steam status 0 = OK in GodotSteam's mapping.
		_steam_initialized = (status == 0)
	else:
		_log("steamInitEx returned unexpected type: %s" % [typeof(result)])
		_steam_initialized = false

	_refresh_status()


func _on_create_pressed() -> void:
	if not _require_initialized():
		return
	_log("Calling createLobby(FRIENDS_ONLY, %d) — async, watch for lobby_created signal" % MAX_LOBBY_MEMBERS)
	_steam.call("createLobby", LOBBY_TYPE_FRIENDS_ONLY, MAX_LOBBY_MEMBERS)


func _on_list_pressed() -> void:
	if not _require_initialized():
		return
	# A friends-only lobby is normally found by adding a filter for the
	# host's friend Steam ID. For the MP-0 smoke test we just ask Steam
	# for ANY lobbies the local user can see; in practice that's
	# friends-only lobbies among the user's friends list. requestLobbyList
	# triggers the lobby_match_list signal with the result.
	_log("Calling requestLobbyList — async, watch for lobby_match_list signal")
	_steam.call("requestLobbyList")


# =============================================================
# STEAM SIGNAL HANDLERS
# =============================================================

func _on_lobby_created(connect_result: int, lobby_id: int) -> void:
	# connect_result 1 = OK in Steam's EResult enum.
	if connect_result == 1:
		_last_lobby_id = lobby_id
		_log("LOBBY CREATED: id=%d (share this ID; friends can join via overlay invite)" % lobby_id)
	else:
		_log("Lobby creation FAILED. EResult=%d (1=OK; anything else = error)" % connect_result)


func _on_lobby_match_list(lobbies: Array) -> void:
	_last_lobbies_found = lobbies
	if lobbies.is_empty():
		_log("requestLobbyList returned 0 lobbies.\nIf a friend just created a lobby and you see nothing, wait a few seconds and retry.")
		return
	var lines: Array[String] = []
	lines.append("Found %d lobby(ies):" % lobbies.size())
	for lobby in lobbies:
		# `lobby` is a lobby Steam ID (int). To get richer info we'd
		# call getLobbyData / getNumLobbyMembers etc. — out of scope
		# for MP-0.
		lines.append("  • lobby_id=%s" % str(lobby))
	_log("\n".join(lines))


# =============================================================
# HELPERS
# =============================================================

func _require_initialized() -> bool:
	if not _steam_initialized:
		_log("Press INIT STEAM first.")
		return false
	return true


func _refresh_status() -> void:
	if _steam == null:
		_status_label.text = "Steam status: PLUGIN NOT INSTALLED\n(see addons/godotsteam/INSTALL.md)"
		return
	if not _steam_initialized:
		_status_label.text = "Steam status: plugin loaded, NOT initialized\n(press INIT STEAM)"
		return
	var name_ := ""
	var sid := 0
	if _steam.has_method("getPersonaName"):
		name_ = String(_steam.call("getPersonaName"))
	if _steam.has_method("getSteamID"):
		sid = int(_steam.call("getSteamID"))
	_status_label.text = "Steam status: ONLINE — user: %s  (id %d)" % [name_, sid]


func _log(msg: String) -> void:
	print("[HelloSteam] " + msg)
	if _output_label != null:
		_output_label.text = msg
