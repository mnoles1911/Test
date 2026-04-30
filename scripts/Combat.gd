extends Node2D
# Main script for the combat scene (scenes/Combat.tscn).
#
# DESIGN (from design/SYSTEMS_DESIGN.md):
#   Turn-based at its core. Player selects actions. Actions have real-time
#   timing windows that modify the outcome.
#
# FULL ROUND FLOW:
#   1. PLAYER_TURN  — action menu shows. Press SPACE to attack.
#   2. ATTACK_TIMING — a bar sweeps left→right. Press SPACE in the green zone
#                      for bonus damage. Miss = normal damage.
#   3. SHOW_RESULT  — brief pause displaying the damage dealt.
#   4. ENEMY_TURN   — enemy telegraphs. Brief pause.
#   5. BLOCK_TIMING — press SPACE in the window to reduce incoming damage.
#   6. SHOW_RESULT  — brief pause displaying damage taken.
#   7. Repeat from 1, or end if HP reaches zero.
#
# All tunable numbers are constants — adjust them without touching logic.


# =============================================================
# STATE MACHINE
# =============================================================

enum CombatState {
	PLAYER_TURN,    # Waiting for player to choose an action
	ATTACK_TIMING,  # Timing bar sweeping — Space = fire timing check
	SHOW_RESULT,    # Brief pause before next phase
	ENEMY_TURN,     # Enemy telegraphs its attack — brief pause
	BLOCK_TIMING,   # Block window open — Space = block
	BATTLE_WON,     # Player won — delay then return to world
	GAME_OVER       # Player lost — delay then return to world
}

var state: CombatState = CombatState.PLAYER_TURN

# After SHOW_RESULT, which state comes next?
# Attack result → ENEMY_TURN. Block result → PLAYER_TURN.
var next_after_result: CombatState = CombatState.ENEMY_TURN


# =============================================================
# COMBAT STATS
# =============================================================

const PLAYER_MAX_HP: int = 30
const ENEMY_MAX_HP: int = 20

var player_hp: int = PLAYER_MAX_HP
var enemy_hp: int = ENEMY_MAX_HP

# Damage values — all tunable here
const NORMAL_DAMAGE: int = 5     # Attack with missed timing
const BONUS_DAMAGE: int  = 8     # Attack with timing in the green zone
const ENEMY_DAMAGE: int  = 4     # Enemy attack, unblocked
const BLOCKED_DAMAGE: int = 1    # Enemy attack, successfully blocked


# =============================================================
# ATTACK TIMING BAR
# =============================================================
# The Indicator sprite sweeps from x=0 to x=BAR_WIDTH within the TimingBar node.
# Pressing Space checks whether the indicator overlaps the SweetSpot.

const BAR_WIDTH: float       = 200.0  # Total width of the bar in pixels
const SWEEP_SPEED: float     = 160.0  # Pixels per second the indicator travels
const SWEET_SPOT_START: float = 90.0  # Left edge of the sweet spot (local x)
const SWEET_SPOT_WIDTH: float = 40.0  # Width of the sweet spot

var sweep_x: float = 0.0  # Current indicator position (0 = bar's left edge)


# =============================================================
# BLOCK TIMING
# =============================================================

const BLOCK_WINDOW: float = 1.2  # Seconds the block prompt stays open

var block_timer: float = 0.0


# =============================================================
# DELAY TIMERS
# =============================================================

const RESULT_PAUSE: float    = 1.2  # Pause after showing attack or block result
const TELEGRAPH_PAUSE: float = 1.0  # Pause while enemy "telegraphs" before block opens
const END_PAUSE: float       = 2.5  # Pause on win/lose screen before returning to world

var delay_timer: float = 0.0


# =============================================================
# NODE REFERENCES
# These must match the node names in Combat.tscn exactly.
# =============================================================

@onready var player_hp_label: Label    = $UI/PlayerPanel/HPLabel
@onready var enemy_hp_label: Label     = $UI/EnemyPanel/HPLabel
@onready var action_menu: Control      = $UI/ActionMenu
@onready var timing_bar: Control       = $UI/TimingBar
@onready var sweep_indicator: ColorRect = $UI/TimingBar/Indicator
@onready var message_label: Label      = $UI/MessageLabel
@onready var bonus_label: Label        = $UI/BonusLabel
@onready var block_prompt: Label       = $UI/BlockPrompt
@onready var enemy_sprite: ColorRect   = $EnemySprite
@onready var enemy_flash: ColorRect    = $EnemyFlash


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	_update_hp_labels()
	_enter_player_turn()


func _process(delta: float) -> void:
	match state:
		CombatState.ATTACK_TIMING:
			_process_sweep(delta)

		CombatState.SHOW_RESULT:
			delay_timer -= delta
			if delay_timer <= 0.0:
				bonus_label.visible = false
				if next_after_result == CombatState.ENEMY_TURN:
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
				# Time ran out — player didn't press Space in the window
				_resolve_block(false)

		CombatState.BATTLE_WON, CombatState.GAME_OVER:
			delay_timer -= delta
			if delay_timer <= 0.0:
				get_tree().change_scene_to_file("res://scenes/World.tscn")


func _unhandled_input(event: InputEvent) -> void:
	# Only care about Space key presses (not releases, not repeats)
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var is_space: bool = (
		event.keycode == KEY_SPACE or event.physical_keycode == KEY_SPACE
	)
	if not is_space:
		return

	match state:
		CombatState.PLAYER_TURN:
			_start_attack_timing()
		CombatState.ATTACK_TIMING:
			_resolve_attack_timing()
		CombatState.BLOCK_TIMING:
			_resolve_block(true)


# =============================================================
# STATE: PLAYER TURN
# =============================================================

func _enter_player_turn() -> void:
	state = CombatState.PLAYER_TURN
	action_menu.visible = true
	timing_bar.visible = false
	block_prompt.visible = false
	message_label.text = "Your turn.   Press SPACE to attack."


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
	# Move the indicator rightward each frame
	sweep_x += delta * SWEEP_SPEED
	sweep_indicator.position.x = sweep_x

	# If the indicator reaches the end without player input, auto-resolve as a miss
	if sweep_x >= BAR_WIDTH:
		_resolve_attack_timing()


func _resolve_attack_timing() -> void:
	timing_bar.visible = false

	# Was the indicator inside the sweet spot when Space was pressed (or bar ended)?
	var in_zone: bool = (
		sweep_x >= SWEET_SPOT_START and
		sweep_x <= SWEET_SPOT_START + SWEET_SPOT_WIDTH
	)

	var damage: int
	if in_zone:
		damage = BONUS_DAMAGE
		message_label.text = "PERFECT! Hit for " + str(damage) + " damage!"
		bonus_label.text = "BONUS HIT!"
		bonus_label.visible = true
		_flash_enemy()  # Brief white flash on the enemy sprite
	else:
		damage = NORMAL_DAMAGE
		message_label.text = "Attack lands for " + str(damage) + " damage."

	enemy_hp = max(0, enemy_hp - damage)
	_update_hp_labels()

	if enemy_hp <= 0:
		_end_battle(true)
		return

	next_after_result = CombatState.ENEMY_TURN
	state = CombatState.SHOW_RESULT
	delay_timer = RESULT_PAUSE


# =============================================================
# STATE: ENEMY TURN (telegraph)
# =============================================================

func _enter_enemy_turn() -> void:
	state = CombatState.ENEMY_TURN
	message_label.text = "The Ashfallen advances...\nPrepare to BLOCK!"
	delay_timer = TELEGRAPH_PAUSE


# =============================================================
# STATE: BLOCK TIMING
# =============================================================

func _enter_block_timing() -> void:
	state = CombatState.BLOCK_TIMING
	block_prompt.visible = true
	block_timer = BLOCK_WINDOW
	message_label.text = "Press SPACE to block!"


func _resolve_block(pressed: bool) -> void:
	block_prompt.visible = false

	var damage: int
	if pressed:
		damage = BLOCKED_DAMAGE
		message_label.text = "Blocked!  Only " + str(damage) + " damage taken."
	else:
		damage = ENEMY_DAMAGE
		message_label.text = "Hit for " + str(damage) + " damage!"

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
		message_label.text = "The Ashfallen falls.\nBATTLE WON!\nReturning to world..."
		print("[Combat] Battle won!")
	else:
		state = CombatState.GAME_OVER
		message_label.text = "Roland falls...\nGAME OVER\nReturning to world..."
		print("[Combat] Game over.")

	delay_timer = END_PAUSE


# =============================================================
# HELPERS
# =============================================================

func _update_hp_labels() -> void:
	player_hp_label.text = "HP  " + str(player_hp) + " / " + str(PLAYER_MAX_HP)
	enemy_hp_label.text  = "HP  " + str(enemy_hp)  + " / " + str(ENEMY_MAX_HP)


func _flash_enemy() -> void:
	# Briefly overlay the enemy sprite with white to signal a solid hit.
	# Uses a Tween to hide the flash after 0.12 seconds.
	enemy_flash.visible = true
	var tween = create_tween()
	tween.tween_interval(0.12)
	tween.tween_callback(func(): enemy_flash.visible = false)
