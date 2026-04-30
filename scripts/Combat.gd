extends Node2D
# Main script for the combat scene (scenes/Combat.tscn).
#
# DESIGN (from design/SYSTEMS_DESIGN.md):
#   Turn-based at its core. Player selects actions. Actions have real-time
#   timing windows that modify the outcome.
#
# FULL ROUND FLOW:
#   1. PLAYER_TURN   — action menu shows. SPACE = attack, A = analyze.
#   2. ATTACK_TIMING — bar sweeps left→right. SPACE in green zone = bonus damage.
#   3. ANALYZING     — brief pause showing Roland's observation of the enemy.
#   4. SHOW_RESULT   — brief pause after attack or block result.
#   5. ENEMY_TURN    — enemy telegraphs. Brief pause.
#   6. BLOCK_TIMING  — SPACE to block in the window.
#   7. Repeat from 1, or end if HP reaches zero.
#
# ENEMY DATA:
#   All enemy stats come from an EnemyData resource set in GameState.current_enemy_data
#   before transitioning to this scene. If nothing is set, Ashfallen defaults are used.
#   See scripts/EnemyData.gd for the full list of configurable fields.


# =============================================================
# STATE MACHINE
# =============================================================

enum CombatState {
	PLAYER_TURN,    # Waiting for player to choose an action
	ATTACK_TIMING,  # Timing bar sweeping — Space = fire timing check
	ANALYZING,      # Roland observes the enemy — brief informational pause
	SHOW_RESULT,    # Brief pause before next phase
	ENEMY_TURN,     # Enemy telegraphs its attack — brief pause
	BLOCK_TIMING,   # Block window open — Space = block
	BATTLE_WON,     # Player won — delay then return to world
	GAME_OVER       # Player lost — delay then return to world
}

var state: CombatState = CombatState.PLAYER_TURN

# After SHOW_RESULT, which state comes next?
var next_after_result: CombatState = CombatState.ENEMY_TURN


# =============================================================
# ENEMY DATA
# =============================================================
# Loaded from GameState.current_enemy_data in _ready().
# If nothing is set, the Ashfallen soldier defaults are used.

var enemy_data: EnemyData = null

# Has the player already used Analyze on this enemy this combat?
# Analyze can only be used once — it's an observation, not a repeating ability.
var already_analyzed: bool = false


# =============================================================
# COMBAT STATS
# =============================================================
# These start as defaults and get overwritten by enemy_data in _ready().

const PLAYER_MAX_HP: int = 30

var player_hp: int = PLAYER_MAX_HP
var enemy_hp: int = 20       # Overwritten from enemy_data.max_hp

# Damage values — loaded from enemy_data in _ready(), defaults shown here
var normal_damage: int = 5   # Player attack, missed timing
var bonus_damage: int = 8    # Player attack, sweet-spot timing
var enemy_damage: int = 4    # Enemy hit, unblocked
var blocked_damage: int = 1  # Enemy hit, successfully blocked


# =============================================================
# ATTACK TIMING BAR
# =============================================================

const BAR_WIDTH: float        = 200.0
const SWEEP_SPEED: float      = 160.0
const SWEET_SPOT_START: float = 90.0
const SWEET_SPOT_WIDTH: float = 40.0

var sweep_x: float = 0.0


# =============================================================
# BLOCK TIMING
# =============================================================

var block_window: float = 1.2  # Overwritten from enemy_data in _ready()
var block_timer: float = 0.0


# =============================================================
# DELAY TIMERS
# =============================================================

const RESULT_PAUSE: float    = 1.2
const TELEGRAPH_PAUSE: float = 1.0
const ANALYZE_PAUSE: float   = 3.5  # Longer — give the player time to read the observation
const END_PAUSE: float       = 2.5

var delay_timer: float = 0.0


# =============================================================
# NODE REFERENCES
# =============================================================

@onready var player_hp_label: Label     = $UI/PlayerPanel/HPLabel
@onready var enemy_hp_label: Label      = $UI/EnemyPanel/HPLabel
@onready var enemy_name_label: Label    = $UI/EnemyPanel/EnemyName
@onready var action_menu: Control       = $UI/ActionMenu
@onready var attack_label: Label        = $UI/ActionMenu/AttackLabel
@onready var analyze_label: Label       = $UI/ActionMenu/ItemLabel
@onready var timing_bar: Control        = $UI/TimingBar
@onready var sweep_indicator: ColorRect = $UI/TimingBar/Indicator
@onready var message_label: Label       = $UI/MessageLabel
@onready var bonus_label: Label         = $UI/BonusLabel
@onready var block_prompt: Label        = $UI/BlockPrompt
@onready var enemy_sprite: ColorRect    = $EnemySprite
@onready var enemy_flash: ColorRect     = $EnemyFlash


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	_load_enemy_data()
	_configure_ui()
	_update_hp_labels()
	_enter_player_turn()


func _load_enemy_data() -> void:
	# Read enemy stats from GameState. If none was set, use the default Ashfallen.
	if GameState.current_enemy_data != null:
		enemy_data = GameState.current_enemy_data
	else:
		# Fallback: creates the default Ashfallen soldier in code.
		# This is how Milestone 3 still works without any setup.
		enemy_data = EnemyData.ashfallen_soldier()

	# Apply the enemy stats to our working variables.
	enemy_hp        = enemy_data.max_hp
	enemy_damage    = enemy_data.attack_damage
	blocked_damage  = enemy_data.blocked_damage
	normal_damage   = enemy_data.normal_player_damage
	bonus_damage    = enemy_data.bonus_player_damage
	block_window    = enemy_data.block_window_duration


func _configure_ui() -> void:
	# Update the enemy name panel with whoever we're fighting.
	enemy_name_label.text = enemy_data.display_name.to_upper()

	# The "ITEM" label from Milestone 3 is now the ANALYZE prompt.
	# We rename it via script so the .tscn file doesn't need to change.
	if already_analyzed:
		analyze_label.text = "[ - - - ]  ANALYZE  (done)"
		analyze_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	else:
		analyze_label.text = "[ A ]  ANALYZE"
		analyze_label.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))


# =============================================================
# INPUT
# =============================================================

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	match state:
		CombatState.PLAYER_TURN:
			if event.keycode == KEY_SPACE or event.physical_keycode == KEY_SPACE:
				_start_attack_timing()
			elif (event.keycode == KEY_A or event.physical_keycode == KEY_A) and not already_analyzed:
				_start_analyze()

		CombatState.ATTACK_TIMING:
			if event.keycode == KEY_SPACE or event.physical_keycode == KEY_SPACE:
				_resolve_attack_timing()

		CombatState.BLOCK_TIMING:
			if event.keycode == KEY_SPACE or event.physical_keycode == KEY_SPACE:
				_resolve_block(true)


# =============================================================
# PROCESS
# =============================================================

func _process(delta: float) -> void:
	match state:
		CombatState.ATTACK_TIMING:
			_process_sweep(delta)

		CombatState.ANALYZING, CombatState.SHOW_RESULT:
			delay_timer -= delta
			if delay_timer <= 0.0:
				bonus_label.visible = false
				if state == CombatState.ANALYZING:
					_finish_analyze()
				elif next_after_result == CombatState.ENEMY_TURN:
					_enter_enemy_turn()
				else:
					_enter_player_turn()

		CombatState.ENEMY_TURN:
			delay_timer -= delta
			if delay_timer <= 0.0:
				_enter_block_timing()

		CombatState.BLOCK_TIMING:
			block_timer -= delta
			if block_timer <= 0.0:
				_resolve_block(false)

		CombatState.BATTLE_WON, CombatState.GAME_OVER:
			delay_timer -= delta
			if delay_timer <= 0.0:
				# Return to world. Use TransitionManager if available; fall back to direct load.
				var tm = get_node_or_null("/root/TransitionManager")
				if tm:
					tm.change_scene("res://scenes/World.tscn", "")
				else:
					get_tree().change_scene_to_file("res://scenes/World.tscn")


# =============================================================
# STATE: PLAYER TURN
# =============================================================

func _enter_player_turn() -> void:
	state = CombatState.PLAYER_TURN
	action_menu.visible = true
	timing_bar.visible = false
	block_prompt.visible = false
	message_label.text = "Your turn.   SPACE = Attack    A = Analyze"
	# Refresh analyze label in case it was just used.
	_configure_ui()


# =============================================================
# STATE: ATTACK TIMING
# =============================================================

func _start_attack_timing() -> void:
	state = CombatState.ATTACK_TIMING
	action_menu.visible = false
	timing_bar.visible = true
	sweep_x = 0.0
	sweep_indicator.position.x = 0.0
	message_label.text = "Press SPACE in the green zone!"


func _process_sweep(delta: float) -> void:
	sweep_x += delta * SWEEP_SPEED
	sweep_indicator.position.x = sweep_x
	if sweep_x >= BAR_WIDTH:
		_resolve_attack_timing()


func _resolve_attack_timing() -> void:
	timing_bar.visible = false
	var in_zone: bool = (
		sweep_x >= SWEET_SPOT_START and
		sweep_x <= SWEET_SPOT_START + SWEET_SPOT_WIDTH
	)
	var damage: int
	if in_zone:
		damage = bonus_damage
		message_label.text = "PERFECT! Hit for %d damage!" % damage
		bonus_label.text = "BONUS HIT!"
		bonus_label.visible = true
		_flash_enemy()
	else:
		damage = normal_damage
		message_label.text = "Attack lands for %d damage." % damage

	enemy_hp = max(0, enemy_hp - damage)
	_update_hp_labels()

	if enemy_hp <= 0:
		_end_battle(true)
		return

	next_after_result = CombatState.ENEMY_TURN
	state = CombatState.SHOW_RESULT
	delay_timer = RESULT_PAUSE


# =============================================================
# STATE: ANALYZE
# =============================================================

func _start_analyze() -> void:
	# Roland observes the enemy. One-use per combat.
	state = CombatState.ANALYZING
	action_menu.visible = false
	already_analyzed = true

	# Store that this enemy has been analyzed in GameState so the journal can show it.
	GameState.set_flag("analyzed_" + enemy_data.display_name.to_lower().replace(" ", "_"), true)
	GameState.set_flag("weak_point_" + enemy_data.display_name.to_lower().replace(" ", "_"), enemy_data.weak_point)

	# Show Roland's observation in the message area.
	# If no analyze text is written yet, show a placeholder.
	if enemy_data.analyze_description.is_empty():
		message_label.text = "Roland watches carefully. No obvious weakness presents itself."
	else:
		message_label.text = enemy_data.analyze_description

	delay_timer = ANALYZE_PAUSE
	print("[Combat] Analyze used on: " + enemy_data.display_name)


func _finish_analyze() -> void:
	# After the pause, return to the player's turn.
	# The enemy does NOT get a free attack — Analyze costs the attack action,
	# not a full turn. Player still has their turn after observing.
	_enter_player_turn()


# =============================================================
# STATE: ENEMY TURN (telegraph)
# =============================================================

func _enter_enemy_turn() -> void:
	state = CombatState.ENEMY_TURN
	message_label.text = enemy_data.telegraph_text
	delay_timer = TELEGRAPH_PAUSE


# =============================================================
# STATE: BLOCK TIMING
# =============================================================

func _enter_block_timing() -> void:
	state = CombatState.BLOCK_TIMING
	block_prompt.visible = true
	block_timer = block_window
	message_label.text = "Press SPACE to block!"


func _resolve_block(pressed: bool) -> void:
	block_prompt.visible = false
	var damage: int
	if pressed:
		damage = blocked_damage
		message_label.text = "Blocked!  Only %d damage taken." % damage
	else:
		damage = enemy_damage
		message_label.text = "Hit for %d damage!" % damage

	player_hp = max(0, player_hp - damage)
	_update_hp_labels()

	if player_hp <= 0:
		_end_battle(false)
		return

	next_after_result = CombatState.PLAYER_TURN
	state = CombatState.SHOW_RESULT
	delay_timer = RESULT_PAUSE


# =============================================================
# END CONDITIONS
# =============================================================

func _end_battle(player_won: bool) -> void:
	action_menu.visible = false
	timing_bar.visible = false
	block_prompt.visible = false

	if player_won:
		state = CombatState.BATTLE_WON
		message_label.text = "The %s falls.\nBATTLE WON!\nReturning to world..." % enemy_data.display_name
		print("[Combat] Battle won vs: " + enemy_data.display_name)
	else:
		state = CombatState.GAME_OVER
		message_label.text = "Roland falls...\nGAME OVER\nReturning to world..."
		print("[Combat] Game over.")

	delay_timer = END_PAUSE


# =============================================================
# HELPERS
# =============================================================

func _update_hp_labels() -> void:
	player_hp_label.text = "HP  %d / %d" % [player_hp, PLAYER_MAX_HP]
	enemy_hp_label.text  = "HP  %d / %d" % [enemy_hp, enemy_data.max_hp]


func _flash_enemy() -> void:
	enemy_flash.visible = true
	var tween = create_tween()
	tween.tween_interval(0.12)
	tween.tween_callback(func(): enemy_flash.visible = false)
