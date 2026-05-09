extends CanvasLayer
# DiceGameUI — Bones (tavern dice) mini-game overlay.
#
# Built programmatically; no .tscn file. Mirrors the LockpickingUI pattern:
# instance at runtime, call open(opponent), wait for match_ended.
#
# Usage:
#   var ui := preload("res://scripts/ui/DiceGameUI.gd").new()
#   add_child(ui)
#   ui.match_ended.connect(_on_dice_match_ended)
#   ui.open(opponent_data)
#
# Public API:
#   open(opponent: DiceOpponentData) — show overlay, start at ANTE phase
#   close() — tear down, free self
#
# Signals:
#   match_ended(net_coin_delta: int) — emitted when player presses Leave;
#                                       net_coin_delta is signed (negative = lost)
#   match_cancelled() — Esc-cancel before any hand was played

signal match_ended(net_coin_delta: int)
signal match_cancelled()

const TABLE_SCENE: PackedScene = preload("res://scenes/dice/DiceTable3D.tscn")
const HUD_LAYER: int = 10
const MAX_REROLLS: int = 2

# --- Optional art paths (JPG; missing files fall back to plain styling) ---
const TEX_LOCK_INDICATOR: String = "res://assets/dice/lock_indicator.jpg"
const TEX_COIN: String = "res://assets/dice/coin.jpg"
const TEX_WAGER_CARD_BG: String = "res://assets/dice/wager_card_bg.jpg"
const TEX_REVEAL_BANNER: String = "res://assets/dice/reveal_banner.jpg"
const TEX_WIN_GLOW: String = "res://assets/dice/win_glow.jpg"

# --- Audio paths ---
const SFX_DICE_SHAKE: String = "res://assets/audio/dice/dice_shake.ogg"
const SFX_DICE_THROW: String = "res://assets/audio/dice/dice_throw.ogg"
const SFX_DICE_SETTLE: String = "res://assets/audio/dice/dice_settle.ogg"
const SFX_DICE_LOCK: String = "res://assets/audio/dice/dice_lock.ogg"
const SFX_COIN_CLINK: String = "res://assets/audio/dice/coin_clink.ogg"
const SFX_WIN_CHIME: String = "res://assets/audio/dice/win_chime.ogg"
const SFX_LOSE_THUD: String = "res://assets/audio/dice/lose_thud.ogg"
const SFX_TAVERN_AMBIENT: String = "res://assets/audio/dice/tavern_ambient.ogg"

enum State {
	IDLE,
	ANTE,
	PLAYER_ROLL,
	PLAYER_LOCK,
	OPPONENT_ROLL,
	REVEAL,
}

var _opponent: DiceOpponentData
var _player_hand: DiceHand = DiceHand.new()
var _opponent_hand: DiceHand = DiceHand.new()
var _player_result: DiceHandResult
var _opponent_result: DiceHandResult
var _player_rerolls_used: int = 0
var _opponent_rerolls_used: int = 0
var _wager: int = 5
var _pot: int = 0
var _net_delta: int = 0
var _hands_played: int = 0
var _state: State = State.IDLE
var _table_owner: String = "player"   # whose dice are currently in the viewport
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _table: Node = null

# --- UI nodes ---
var _dim: ColorRect
var _root_panel: PanelContainer
var _opponent_label: Label
var _balance_label: Label
var _pot_label: Label
var _rerolls_label: Label
var _state_label: Label
var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _die_card_buttons: Array[Button] = []
var _die_card_value_labels: Array[Label] = []
var _die_card_lock_overlays: Array[ColorRect] = []
var _ante_hbox: HBoxContainer
var _wager_slider: HSlider
var _wager_value_label: Label
var _confirm_wager_btn: Button
var _lock_hbox: HBoxContainer
var _reroll_btn: Button
var _reveal_now_btn: Button
var _reveal_vbox: VBoxContainer
var _reveal_player_label: Label
var _reveal_opponent_label: Label
var _reveal_banner_label: Label
var _continue_btn: Button
var _leave_btn: Button

# --- Optional art TextureRects (only present if the JPG was found) ---
var _die_card_lock_textures: Array[TextureRect] = []   # wax-seal scrap on each card
var _balance_coin_icon: TextureRect
var _pot_coin_icon: TextureRect
var _wager_card_bg_rect: TextureRect
var _reveal_banner_bg_rect: TextureRect
var _win_glow_overlay: TextureRect

# --- Audio players (pre-built, reused) ---
var _sfx_throw: AudioStreamPlayer
var _sfx_settle: AudioStreamPlayer
var _sfx_shake: AudioStreamPlayer
var _sfx_lock: AudioStreamPlayer
var _sfx_coin: AudioStreamPlayer
var _sfx_win: AudioStreamPlayer
var _sfx_lose: AudioStreamPlayer
var _ambient_player: AudioStreamPlayer


func _init() -> void:
	layer = HUD_LAYER


func _ready() -> void:
	_rng.randomize()
	_build_ui()
	_build_audio()
	_apply_optional_art()
	_set_state(State.IDLE)


# =============================================================
# PUBLIC API
# =============================================================

func open(opponent: DiceOpponentData) -> void:
	if opponent == null:
		push_error("[DiceGameUI] open() called with null opponent")
		return
	_opponent = opponent
	_player_hand = DiceHand.new()
	_opponent_hand = DiceHand.new()
	_player_rerolls_used = 0
	_opponent_rerolls_used = 0
	_pot = 0
	_net_delta = 0
	_hands_played = 0
	_wager = opponent.min_wager

	_opponent_label.text = opponent.display_name
	_wager_slider.min_value = opponent.min_wager
	_wager_slider.max_value = opponent.max_wager
	_wager_slider.step = 1
	_wager_slider.value = opponent.min_wager
	_wager_value_label.text = "%d" % opponent.min_wager
	_refresh_balance_label()
	_refresh_pot_label()
	_refresh_rerolls_label()

	# Pause world clock so a live tavern doesn't tick during a match.
	if get_node_or_null("/root/WorldClock"):
		WorldClock.set_paused(true)

	# Spawn the 3D table inside the viewport.
	if _table != null:
		_table.queue_free()
	_table = TABLE_SCENE.instantiate()
	_viewport.add_child(_table)
	# Wait one frame for _ready in DiceTable3D to run before connecting.
	await get_tree().process_frame
	if _table != null and _table.has_signal("roll_settled"):
		_table.roll_settled.connect(_on_table_roll_settled)

	visible = true
	_play_ambient()
	_set_state(State.ANTE)


func close() -> void:
	if get_node_or_null("/root/WorldClock"):
		WorldClock.set_paused(false)
	if _table != null:
		_table.queue_free()
		_table = null
	_stop_ambient()
	visible = false
	queue_free()


# =============================================================
# UI CONSTRUCTION
# =============================================================

func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.82)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_root_panel = PanelContainer.new()
	_root_panel.add_theme_stylebox_override("panel", UIStyles.menu_body_panel())
	_root_panel.custom_minimum_size = Vector2(1000, 760)
	_root_panel.set_anchors_preset(Control.PRESET_CENTER)
	_root_panel.position = Vector2(-500, -380)
	add_child(_root_panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	_root_panel.add_child(vbox)

	_build_header(vbox)
	_build_viewport(vbox)
	_build_dice_cards(vbox)
	_build_state_controls(vbox)

	# Win-glow overlay sits above the panel so a winning hand briefly
	# washes the whole UI in warm light. JPG with no alpha so we use
	# additive-style modulate (alpha 0..1 fades the glow brightness).
	_win_glow_overlay = TextureRect.new()
	_win_glow_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_win_glow_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_win_glow_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_win_glow_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_win_glow_overlay.modulate = Color(1, 1, 1, 0)
	# Additive blend so dark areas of the JPG don't gray out the panel.
	var glow_mat: CanvasItemMaterial = CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_win_glow_overlay.material = glow_mat
	_win_glow_overlay.visible = false
	add_child(_win_glow_overlay)


func _build_header(parent: VBoxContainer) -> void:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	parent.add_child(hbox)

	_opponent_label = Label.new()
	_opponent_label.text = "Opponent"
	UIStyles.apply_title_label(_opponent_label, 28)
	hbox.add_child(_opponent_label)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	_balance_coin_icon = TextureRect.new()
	_balance_coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_balance_coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_balance_coin_icon.custom_minimum_size = Vector2(24, 24)
	_balance_coin_icon.visible = false
	hbox.add_child(_balance_coin_icon)

	_balance_label = Label.new()
	UIStyles.apply_body_label(_balance_label, 18)
	hbox.add_child(_balance_label)

	_pot_coin_icon = TextureRect.new()
	_pot_coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pot_coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pot_coin_icon.custom_minimum_size = Vector2(24, 24)
	_pot_coin_icon.visible = false
	hbox.add_child(_pot_coin_icon)

	_pot_label = Label.new()
	UIStyles.apply_body_label(_pot_label, 18)
	_pot_label.add_theme_color_override("font_color", Colors.GOLD)
	hbox.add_child(_pot_label)

	_rerolls_label = Label.new()
	UIStyles.apply_dim_label(_rerolls_label, 16)
	hbox.add_child(_rerolls_label)

	_state_label = Label.new()
	UIStyles.apply_body_label(_state_label, 16)
	_state_label.add_theme_color_override("font_color", Colors.INK_DIM)
	parent.add_child(_state_label)


func _build_viewport(parent: VBoxContainer) -> void:
	_viewport_container = SubViewportContainer.new()
	_viewport_container.custom_minimum_size = Vector2(960, 380)
	_viewport_container.stretch = true
	parent.add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(960, 380)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	_viewport_container.add_child(_viewport)


func _build_dice_cards(parent: VBoxContainer) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)

	for i in DiceHand.DIE_COUNT:
		# Each card: a Button that holds a centered Label and a tinted
		# overlay rect for the lock-state hint. Buttons accept clicks
		# even when nested controls are present.
		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(140, 110)
		btn.text = ""
		_apply_card_style(btn, false)
		btn.pressed.connect(_on_die_card_pressed.bind(i))
		row.add_child(btn)
		_die_card_buttons.append(btn)

		var inner: Control = Control.new()
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(inner)

		var value_label: Label = Label.new()
		value_label.text = "?"
		value_label.set_anchors_preset(Control.PRESET_CENTER)
		value_label.position = Vector2(-30, -30)
		value_label.size = Vector2(60, 60)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UIStyles.apply_title_label(value_label, 44)
		inner.add_child(value_label)
		_die_card_value_labels.append(value_label)

		var lock_overlay: ColorRect = ColorRect.new()
		lock_overlay.color = Color(0.65, 0.18, 0.18, 0.30)
		lock_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		lock_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_overlay.visible = false
		inner.add_child(lock_overlay)
		_die_card_lock_overlays.append(lock_overlay)

		# Wax-seal scrap, top-right corner badge. Small + offset so the
		# value digit underneath stays readable. The JPG is opaque
		# (no alpha) so we modulate slightly to soften it.
		var lock_tex: TextureRect = TextureRect.new()
		lock_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lock_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lock_tex.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		lock_tex.position = Vector2(-38, 4)
		lock_tex.size = Vector2(34, 34)
		lock_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_tex.modulate = Color(1, 1, 1, 0.92)
		lock_tex.visible = false
		inner.add_child(lock_tex)
		_die_card_lock_textures.append(lock_tex)


func _apply_card_style(btn: Button, locked: bool) -> void:
	# Cards reuse the slot palette — iron base, gold border when locked.
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Colors.PANEL_OAK_2
	normal.border_color = Colors.GOLD if locked else Colors.PANEL_OAK_EDGE
	normal.set_border_width_all(2 if not locked else 3)
	normal.set_content_margin_all(0)

	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.border_color = Colors.GOLD

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("disabled", normal)


func _build_state_controls(parent: VBoxContainer) -> void:
	# Three sub-rows / panels — only one visible per state.

	# --- ANTE row: wager slider + Confirm Wager
	_ante_hbox = HBoxContainer.new()
	_ante_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_ante_hbox.add_theme_constant_override("separation", 16)
	parent.add_child(_ante_hbox)

	var wager_label: Label = Label.new()
	wager_label.text = "Wager:"
	UIStyles.apply_body_label(wager_label, 18)
	_ante_hbox.add_child(wager_label)

	_wager_slider = HSlider.new()
	_wager_slider.custom_minimum_size = Vector2(360, 32)
	_wager_slider.min_value = 5
	_wager_slider.max_value = 50
	_wager_slider.step = 1
	UIStyles.apply_slider(_wager_slider)
	_wager_slider.value_changed.connect(_on_wager_slider_changed)
	_ante_hbox.add_child(_wager_slider)

	# Wager value sits on a parchment card. The card is a sibling
	# TextureRect anchored behind the label inside a fixed-size Control.
	var wager_card_holder: Control = Control.new()
	wager_card_holder.custom_minimum_size = Vector2(140, 50)
	_ante_hbox.add_child(wager_card_holder)

	_wager_card_bg_rect = TextureRect.new()
	_wager_card_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wager_card_bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_wager_card_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wager_card_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wager_card_bg_rect.visible = false
	wager_card_holder.add_child(_wager_card_bg_rect)

	_wager_value_label = Label.new()
	_wager_value_label.text = "5"
	UIStyles.apply_title_label(_wager_value_label, 26)
	_wager_value_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wager_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wager_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wager_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wager_card_holder.add_child(_wager_value_label)

	_confirm_wager_btn = Button.new()
	_confirm_wager_btn.text = "Ante Up"
	UIStyles.apply_menu_button(_confirm_wager_btn)
	_confirm_wager_btn.pressed.connect(_on_confirm_wager_pressed)
	_ante_hbox.add_child(_confirm_wager_btn)

	# --- LOCK row: Reroll, Reveal Now
	_lock_hbox = HBoxContainer.new()
	_lock_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_lock_hbox.add_theme_constant_override("separation", 16)
	parent.add_child(_lock_hbox)

	_reroll_btn = Button.new()
	_reroll_btn.text = "Reroll Unlocked"
	UIStyles.apply_menu_button(_reroll_btn)
	_reroll_btn.pressed.connect(_on_reroll_pressed)
	_lock_hbox.add_child(_reroll_btn)

	_reveal_now_btn = Button.new()
	_reveal_now_btn.text = "Reveal Now"
	UIStyles.apply_menu_button(_reveal_now_btn)
	_reveal_now_btn.pressed.connect(_on_reveal_now_pressed)
	_lock_hbox.add_child(_reveal_now_btn)

	# --- REVEAL row: rank labels + banner + Continue
	_reveal_vbox = VBoxContainer.new()
	_reveal_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_reveal_vbox.add_theme_constant_override("separation", 8)
	parent.add_child(_reveal_vbox)

	# Banner — parchment ribbon behind a centered title label.
	var banner_holder: Control = Control.new()
	banner_holder.custom_minimum_size = Vector2(640, 96)
	banner_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_reveal_vbox.add_child(banner_holder)

	_reveal_banner_bg_rect = TextureRect.new()
	_reveal_banner_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_reveal_banner_bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_reveal_banner_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reveal_banner_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal_banner_bg_rect.visible = false
	banner_holder.add_child(_reveal_banner_bg_rect)

	_reveal_banner_label = Label.new()
	_reveal_banner_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reveal_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reveal_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reveal_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyles.apply_title_label(_reveal_banner_label, 36)
	banner_holder.add_child(_reveal_banner_label)

	_reveal_player_label = Label.new()
	_reveal_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyles.apply_body_label(_reveal_player_label, 18)
	_reveal_vbox.add_child(_reveal_player_label)

	_reveal_opponent_label = Label.new()
	_reveal_opponent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyles.apply_body_label(_reveal_opponent_label, 18)
	_reveal_vbox.add_child(_reveal_opponent_label)

	var reveal_btns: HBoxContainer = HBoxContainer.new()
	reveal_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	reveal_btns.add_theme_constant_override("separation", 16)
	_reveal_vbox.add_child(reveal_btns)

	_continue_btn = Button.new()
	_continue_btn.text = "Continue"
	UIStyles.apply_menu_button(_continue_btn)
	_continue_btn.pressed.connect(_on_continue_pressed)
	reveal_btns.add_child(_continue_btn)

	# --- Always-present Leave button at the bottom
	_leave_btn = Button.new()
	_leave_btn.text = "Leave Table"
	UIStyles.apply_menu_button(_leave_btn)
	_leave_btn.pressed.connect(_on_leave_pressed)
	parent.add_child(_leave_btn)


# =============================================================
# STATE MACHINE
# =============================================================

func _set_state(new_state: State) -> void:
	_state = new_state
	_update_state_visibility()
	_update_state_label()


func _update_state_visibility() -> void:
	_ante_hbox.visible = _state == State.ANTE
	_lock_hbox.visible = _state == State.PLAYER_LOCK
	_reveal_vbox.visible = _state == State.REVEAL

	# Reroll / Reveal-Now enabled only when the player can act.
	if _state == State.PLAYER_LOCK:
		var can_reroll: bool = _player_rerolls_used < MAX_REROLLS and _player_hand.unlocked_count() > 0
		_reroll_btn.disabled = not can_reroll
		_reveal_now_btn.disabled = false

	# Leave button is enabled in ANTE / REVEAL but not mid-roll.
	_leave_btn.disabled = (_state == State.PLAYER_ROLL or _state == State.OPPONENT_ROLL)

	# Confirm-wager enabled only if player can afford it.
	if _state == State.ANTE:
		var balance: int = _coin_balance()
		_confirm_wager_btn.disabled = balance < _wager
		_confirm_wager_btn.text = ("Ante Up — %d coin" % _wager) if balance >= _wager else "Insufficient coin"


func _update_state_label() -> void:
	match _state:
		State.IDLE:
			_state_label.text = ""
		State.ANTE:
			_state_label.text = "Place your wager."
		State.PLAYER_ROLL:
			_state_label.text = "Rolling..."
		State.PLAYER_LOCK:
			_state_label.text = "Click dice to lock. Reroll up to %d more time%s." % [
				MAX_REROLLS - _player_rerolls_used,
				"" if MAX_REROLLS - _player_rerolls_used == 1 else "s"
			]
		State.OPPONENT_ROLL:
			_state_label.text = "%s rolls..." % _opponent.display_name
		State.REVEAL:
			_state_label.text = ""


# =============================================================
# WAGER PHASE
# =============================================================

func _on_wager_slider_changed(value: float) -> void:
	_wager = int(value)
	_wager_value_label.text = "%d" % _wager
	_update_state_visibility()


func _on_confirm_wager_pressed() -> void:
	if _state != State.ANTE:
		return
	var balance: int = _coin_balance()
	if balance < _wager:
		return  # button shouldn't be reachable, but guard anyway
	if not _spend_coin(_wager):
		return
	_pot = _wager * 2   # opponent matches
	_net_delta -= _wager
	_refresh_balance_label()
	_refresh_pot_label()
	_play_sfx(_sfx_coin)

	# Reset hand state for the new round.
	_player_hand = DiceHand.new()
	_opponent_hand = DiceHand.new()
	_player_rerolls_used = 0
	_opponent_rerolls_used = 0
	_refresh_rerolls_label()
	_clear_die_card_visuals()

	_table_owner = "player"
	_set_state(State.PLAYER_ROLL)
	# Roll all 5 player dice. _roll_table_for syncs lock visuals from
	# hand.locked, which is freshly-zero for a new hand.
	_roll_table_for(_player_hand, PackedInt32Array([0, 1, 2, 3, 4]))


# =============================================================
# DICE ROLL / SETTLE
# =============================================================

func _roll_table_for(hand: DiceHand, indices: PackedInt32Array) -> void:
	# Delegates to DiceTable3D. _on_table_roll_settled will read back values.
	if _table == null:
		return
	# Sync visual lock markers in the 3D scene with hand.locked.
	for i in DiceHand.DIE_COUNT:
		_table.set_die_lock_visual(i, hand.locked[i])
	_play_sfx(_sfx_throw)
	_table.roll(indices)


func _on_table_roll_settled(face_values: PackedInt32Array) -> void:
	# face_values has 5 ints. We only adopt values for dice that were
	# rolled — locked dice keep their previous face.
	_play_sfx(_sfx_settle)
	if _table_owner == "player":
		_apply_face_values_to_hand(_player_hand, face_values)
		_refresh_die_card_visuals(_player_hand)
		_set_state(State.PLAYER_LOCK)
	else:
		_apply_face_values_to_hand(_opponent_hand, face_values)
		_refresh_die_card_visuals(_opponent_hand)
		# AI loop: decide locks, reroll until done, then reveal.
		_continue_opponent_turn()


func _apply_face_values_to_hand(hand: DiceHand, face_values: PackedInt32Array) -> void:
	for i in DiceHand.DIE_COUNT:
		if not hand.locked[i]:
			hand.dice[i] = face_values[i]


# =============================================================
# PLAYER LOCK / REROLL
# =============================================================

func _on_die_card_pressed(idx: int) -> void:
	if _state != State.PLAYER_LOCK:
		return
	_player_hand.toggle_lock(idx)
	_refresh_die_card_lock_visual(idx, _player_hand.locked[idx])
	if _table != null:
		_table.set_die_lock_visual(idx, _player_hand.locked[idx])
	_play_sfx(_sfx_lock)
	_update_state_visibility()


func _on_reroll_pressed() -> void:
	if _state != State.PLAYER_LOCK:
		return
	if _player_rerolls_used >= MAX_REROLLS:
		return
	_player_rerolls_used += 1
	_refresh_rerolls_label()
	var unlocked: PackedInt32Array = PackedInt32Array()
	for i in DiceHand.DIE_COUNT:
		if not _player_hand.locked[i]:
			unlocked.append(i)
	if unlocked.size() == 0:
		return
	_set_state(State.PLAYER_ROLL)
	_roll_table_for(_player_hand, unlocked)


func _on_reveal_now_pressed() -> void:
	if _state != State.PLAYER_LOCK:
		return
	_begin_opponent_turn()


# =============================================================
# OPPONENT TURN
# =============================================================

func _begin_opponent_turn() -> void:
	_table_owner = "opponent"
	# Clear any visual lock markers from the player's turn.
	if _table != null:
		for i in DiceHand.DIE_COUNT:
			_table.set_die_lock_visual(i, false)
	_opponent_hand = DiceHand.new()
	_opponent_rerolls_used = 0
	_clear_die_card_visuals()
	_set_state(State.OPPONENT_ROLL)
	# Opening roll — all 5 dice.
	_roll_table_for(_opponent_hand, PackedInt32Array([0, 1, 2, 3, 4]))


func _continue_opponent_turn() -> void:
	# Called after each opponent settle. AI decides locks, then re-rolls
	# unlocked dice — until rerolls run out or AI keeps everything.
	var aggression: float = 0.5 if _opponent == null else _opponent.ai_aggression
	var locks: Array[bool] = DiceAI.decide_locks(_opponent_hand, _opponent_rerolls_used, aggression)
	for i in DiceHand.DIE_COUNT:
		_opponent_hand.locked[i] = locks[i]
		if _table != null:
			_table.set_die_lock_visual(i, locks[i])

	if _opponent_rerolls_used >= MAX_REROLLS or _opponent_hand.unlocked_count() == 0:
		_resolve_reveal()
		return

	_opponent_rerolls_used += 1
	var unlocked: PackedInt32Array = PackedInt32Array()
	for i in DiceHand.DIE_COUNT:
		if not _opponent_hand.locked[i]:
			unlocked.append(i)
	# Small delay so the player can see the AI's lock decision before re-rolling.
	# Fill it with the rattle sound — sells the moment.
	_play_sfx(_sfx_shake)
	await get_tree().create_timer(0.6).timeout
	_set_state(State.OPPONENT_ROLL)
	_roll_table_for(_opponent_hand, unlocked)


# =============================================================
# REVEAL & SETTLE
# =============================================================

func _resolve_reveal() -> void:
	_player_result = _player_hand.evaluate()
	_opponent_result = _opponent_hand.evaluate()
	var cmp: int = _player_result.compare(_opponent_result)

	var banner_text: String = ""
	var banner_color: Color = Colors.INK
	var bark_trigger: String = ""
	if cmp > 0:
		banner_text = "YOU WIN"
		banner_color = Colors.GOLD
		bark_trigger = "DICE_REVEAL_PLAYER_WIN"
		_add_coin(_pot)
		_net_delta += _pot
		_play_sfx(_sfx_win)
		_play_sfx(_sfx_coin)   # coins sliding to the player
		_flash_win_glow()
	elif cmp < 0:
		banner_text = "YOU LOSE"
		banner_color = Colors.HP_BRIGHT
		bark_trigger = "DICE_REVEAL_OPPONENT_WIN"
		_play_sfx(_sfx_lose)
		# Opponent takes pot — player already paid the ante; nothing more to do.
	else:
		banner_text = "PUSH"
		banner_color = Colors.INK_DIM
		bark_trigger = "DICE_REVEAL_PUSH"
		# Refund the player's ante. Opponent's ante is fictional here.
		_add_coin(_wager)
		_net_delta += _wager
		_play_sfx(_sfx_coin)

	_pot = 0
	_refresh_pot_label()
	_refresh_balance_label()

	_reveal_banner_label.text = banner_text
	_reveal_banner_label.add_theme_color_override("font_color", banner_color)
	_reveal_player_label.text = "You: %s   (%s)" % [
		_format_dice(_player_hand.dice), _player_result.rank_label()
	]
	_reveal_opponent_label.text = "%s: %s   (%s)" % [
		_opponent.display_name, _format_dice(_opponent_hand.dice), _opponent_result.rank_label()
	]

	_hands_played += 1

	# Fire NPC bark if BarkManager is available and the opponent has an npc_id.
	if _opponent.npc_id != "" and get_node_or_null("/root/BarkManager"):
		BarkManager.fire(_opponent.npc_id, bark_trigger, Vector3.ZERO)

	_set_state(State.REVEAL)


func _on_continue_pressed() -> void:
	if _state != State.REVEAL:
		return
	# Disable continue if player is broke.
	if _coin_balance() < _opponent.min_wager:
		_set_state(State.REVEAL)   # stay; let them Leave
		_state_label.text = "You're out of coin to ante. Leave the table."
		_continue_btn.disabled = true
		return
	_set_state(State.ANTE)
	_clear_die_card_visuals()
	_update_state_visibility()


func _on_leave_pressed() -> void:
	if _state == State.PLAYER_ROLL or _state == State.OPPONENT_ROLL:
		return  # mid-roll: ignore
	# Fire a parting bark if the opponent has one.
	if _opponent != null and _opponent.npc_id != "" and get_node_or_null("/root/BarkManager"):
		var trigger: String = "DICE_MATCH_LEAVE"
		if _coin_balance() < _opponent.min_wager:
			trigger = "DICE_MATCH_LEAVE_BROKE"
		BarkManager.fire(_opponent.npc_id, trigger, Vector3.ZERO)

	if _hands_played == 0:
		match_cancelled.emit()
	else:
		match_ended.emit(_net_delta)
	close()


# =============================================================
# DIE CARD VISUALS
# =============================================================

func _clear_die_card_visuals() -> void:
	for i in DiceHand.DIE_COUNT:
		_die_card_value_labels[i].text = "?"
		_refresh_die_card_lock_visual(i, false)


func _refresh_die_card_visuals(hand: DiceHand) -> void:
	for i in DiceHand.DIE_COUNT:
		_die_card_value_labels[i].text = "%d" % hand.dice[i]
		_refresh_die_card_lock_visual(i, hand.locked[i])


func _refresh_die_card_lock_visual(idx: int, locked: bool) -> void:
	_die_card_lock_overlays[idx].visible = locked
	# Wax seal TextureRect — only visible when the texture has been
	# loaded (i.e., the JPG was present at startup) AND the die is locked.
	if idx < _die_card_lock_textures.size() and _die_card_lock_textures[idx].texture != null:
		_die_card_lock_textures[idx].visible = locked
	_apply_card_style(_die_card_buttons[idx], locked)


# =============================================================
# COIN HELPERS (route through InventoryManager)
# =============================================================

func _coin_balance() -> int:
	if get_node_or_null("/root/InventoryManager"):
		return InventoryManager.get_coin_balance()
	return 0


func _spend_coin(amount: int) -> bool:
	if get_node_or_null("/root/InventoryManager"):
		return InventoryManager.spend_coin(amount)
	return false


func _add_coin(amount: int) -> void:
	if get_node_or_null("/root/InventoryManager"):
		InventoryManager.add_coin(amount)


# =============================================================
# HEADER REFRESHES
# =============================================================

func _refresh_balance_label() -> void:
	_balance_label.text = "Coin: %d" % _coin_balance()


func _refresh_pot_label() -> void:
	_pot_label.text = "Pot: %d" % _pot


func _refresh_rerolls_label() -> void:
	_rerolls_label.text = "Rerolls: %d/%d" % [_player_rerolls_used, MAX_REROLLS]


func _format_dice(dice: PackedInt32Array) -> String:
	var parts: Array[String] = []
	for v in dice:
		parts.append(str(v))
	return " ".join(parts)


# =============================================================
# INPUT
# =============================================================

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _state == State.PLAYER_ROLL or _state == State.OPPONENT_ROLL:
			return  # ignore mid-roll
		_on_leave_pressed()


# =============================================================
# OPTIONAL ART (lazy-loaded; missing files leave defaults in place)
# =============================================================

func _apply_optional_art() -> void:
	# Coin icons — appear next to balance and pot labels.
	var coin_tex: Texture2D = _try_load_tex(TEX_COIN)
	if coin_tex != null:
		_balance_coin_icon.texture = coin_tex
		_balance_coin_icon.visible = true
		_pot_coin_icon.texture = coin_tex
		_pot_coin_icon.visible = true

	# Lock indicators — wax-seal scrap on each die card.
	var lock_tex: Texture2D = _try_load_tex(TEX_LOCK_INDICATOR)
	if lock_tex != null:
		for tr in _die_card_lock_textures:
			tr.texture = lock_tex

	var wager_bg: Texture2D = _try_load_tex(TEX_WAGER_CARD_BG)
	if wager_bg != null:
		_wager_card_bg_rect.texture = wager_bg
		_wager_card_bg_rect.visible = true

	var banner_bg: Texture2D = _try_load_tex(TEX_REVEAL_BANNER)
	if banner_bg != null:
		_reveal_banner_bg_rect.texture = banner_bg
		_reveal_banner_bg_rect.visible = true

	var glow: Texture2D = _try_load_tex(TEX_WIN_GLOW)
	if glow != null:
		_win_glow_overlay.texture = glow


func _try_load_tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


# =============================================================
# AUDIO
# =============================================================

func _build_audio() -> void:
	# All players are children of the CanvasLayer (which is fine for
	# non-spatial UI sound). Streams are loaded lazily; missing files
	# leave the player silent (set_stream(null)).
	_sfx_throw   = _make_sfx_player(SFX_DICE_THROW)
	_sfx_settle  = _make_sfx_player(SFX_DICE_SETTLE)
	_sfx_shake   = _make_sfx_player(SFX_DICE_SHAKE)
	_sfx_lock    = _make_sfx_player(SFX_DICE_LOCK)
	_sfx_coin    = _make_sfx_player(SFX_COIN_CLINK)
	_sfx_win     = _make_sfx_player(SFX_WIN_CHIME)
	_sfx_lose    = _make_sfx_player(SFX_LOSE_THUD)

	# Tavern ambient is a quiet looping bed for the whole match.
	_ambient_player = AudioStreamPlayer.new()
	add_child(_ambient_player)
	if ResourceLoader.exists(SFX_TAVERN_AMBIENT):
		var stream: AudioStream = load(SFX_TAVERN_AMBIENT)
		# Force loop on OggVorbis streams — Godot sometimes loads them
		# with loop=false depending on import settings.
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		_ambient_player.stream = stream
		_ambient_player.volume_db = -14.0


func _make_sfx_player(path: String) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	add_child(p)
	if ResourceLoader.exists(path):
		p.stream = load(path)
	return p


func _play_sfx(player: AudioStreamPlayer) -> void:
	if player == null or player.stream == null:
		return
	# Stop-then-play guarantees re-trigger if already playing.
	player.stop()
	player.play()


func _play_ambient() -> void:
	if _ambient_player and _ambient_player.stream:
		_ambient_player.play()


func _stop_ambient() -> void:
	if _ambient_player:
		_ambient_player.stop()


func _flash_win_glow() -> void:
	if _win_glow_overlay == null or _win_glow_overlay.texture == null:
		return
	_win_glow_overlay.visible = true
	_win_glow_overlay.modulate = Color(1, 1, 1, 0)
	var tw: Tween = create_tween()
	tw.tween_property(_win_glow_overlay, "modulate:a", 0.55, 0.18)
	tw.tween_interval(0.45)
	tw.tween_property(_win_glow_overlay, "modulate:a", 0.0, 0.7)
	tw.tween_callback(func(): _win_glow_overlay.visible = false)
