extends Resource
class_name EnemyData
# EnemyData — A reusable data container for one enemy type.
#
# What "Resource" means in plain English:
#   A Resource is a data file you can create in the Godot editor and fill in
#   using the Inspector panel — no code required. Think of it like a form with
#   fields. Each enemy type gets its own form (a .tres file). Combat.gd reads
#   whichever form was set in GameState.current_enemy_data before the fight.
#
# HOW TO CREATE A NEW ENEMY:
#   1. In Godot: FileSystem panel → right-click res://resources/enemies/
#   2. New Resource → choose EnemyData → name it (e.g. hollow_soldier.tres)
#   3. Fill in the fields in the Inspector
#   4. Before triggering combat, set: GameState.current_enemy_data = <resource>
#
# This separates enemy STATS from combat LOGIC — you can add new enemies
# without touching Combat.gd at all.


# =============================================================
# DISPLAY
# =============================================================

@export var display_name: String = "Enemy"
# Shown in the enemy name panel at the top of the combat screen.


# =============================================================
# HP AND DAMAGE
# =============================================================

@export var max_hp: int = 20
# Enemy's starting hit points.

@export var attack_damage: int = 4
# Damage dealt to Roland on an unblocked hit.

@export var blocked_damage: int = 1
# Damage dealt to Roland on a successfully blocked hit.
# (A perfect block could reduce this to 0 — implement that later.)

@export var normal_player_damage: int = 5
# Damage Roland deals on an attack that missed the timing window.

@export var bonus_player_damage: int = 8
# Damage Roland deals on an attack that hit the timing sweet spot.
# Separate from normal_player_damage so each enemy can have different
# reward for perfect timing.


# =============================================================
# TIMING
# =============================================================

@export var block_window_duration: float = 1.2
# Seconds the block window stays open before it closes automatically.
# Shorter = harder to block = more dangerous enemy.
# Hollow enemies: 0.8 (implacable pressure, tight window)
# Ashfallen soldiers: 1.2 (standard)
# Untrained fighters: 1.5 (easier)


# =============================================================
# NARRATIVE TEXT
# =============================================================

@export_multiline var telegraph_text: String = "The enemy readies an attack..."
# This line appears when the enemy's turn begins, before the block window opens.
# Should describe HOW the enemy attacks — Roland notices the windup.
# Keep it short (one line). It appears in the MessageLabel.

@export_multiline var analyze_description: String = ""
# What Roland observes when the player uses ANALYZE.
# Should be written in Roland's voice and hint at the weak point
# without stating it outright. Two or three sentences maximum.
# Example: "This was a person once. The stance is wrong — weight back,
# not forward. Whatever hollowed him didn't fix his footwork."

@export var weak_point: String = ""
# Short label for the weak point. Stored in GameState after analysis.
# Shown in Roland's journal. Used by future abilities that exploit it.
# Examples: "hesitation", "overextension", "fear", "imbalance"


# =============================================================
# COMPANION INTERACTIONS
# =============================================================
# Some enemies hesitate when a specific companion is present —
# Ashfallen who were once allies, for instance. This is the
# "recognition pressure" from SYSTEMS_DESIGN.md.

@export var hesitates_with_companion: bool = false
# If true, check hesitation_companion below.

@export var hesitation_companion: String = ""
# The companion whose presence triggers hesitation.
# E.g. "dagna" means the enemy hesitates if Dagna is in the party.
# (Not used in Act I — Roland is alone. Framework for Act III onward.)

@export_multiline var hesitation_text: String = ""
# The message shown when the enemy hesitates.
# E.g. "The Ashfallen pauses. He looks at Dagna as if he knows her."


# =============================================================
# STATIC FACTORY METHODS
# =============================================================
# These create enemy data in GDScript without needing a .tres file.
# Useful for testing and for the tutorial/Milestone 3 Ashfallen.
# Production enemies should be .tres files created in the editor.

static func ashfallen_soldier() -> EnemyData:
	# The standard enemy for Act I. A hollowed person who was once a soldier.
	var d := EnemyData.new()
	d.display_name = "Ashfallen"
	d.max_hp = 20
	d.attack_damage = 4
	d.blocked_damage = 1
	d.normal_player_damage = 5
	d.bonus_player_damage = 8
	d.block_window_duration = 1.2
	d.telegraph_text = "The Ashfallen advances — Prepare to BLOCK!"
	d.analyze_description = (
		"This was a person once. The stance is wrong — weight back, not forward, "
		+ "like someone who learned to hold a weapon but never learned to use one. "
		+ "Whatever hollowed him didn't fix his footwork. The block window opens earlier than it should."
	)
	d.weak_point = "hesitation"
	d.hesitates_with_companion = false
	return d

static func hollow() -> EnemyData:
	# A Hollow — slow, implacable, no windup. Tight block window.
	# Per SYSTEMS_DESIGN.md: "their attacks do not stagger — they press."
	var d := EnemyData.new()
	d.display_name = "Hollow"
	d.max_hp = 30
	d.attack_damage = 7
	d.blocked_damage = 2
	d.normal_player_damage = 5
	d.bonus_player_damage = 8
	d.block_window_duration = 0.8
	d.telegraph_text = "The Hollow presses forward. There is no windup. There is only arrival."
	d.analyze_description = (
		"There is nothing to read. No fear. No hesitation. No tactical tell. "
		+ "It moves because moving is what it does now. "
		+ "The block window is narrow because it doesn't commit — it just arrives."
	)
	d.weak_point = "relentlessness"
	return d
