extends Node
class_name CombatXPRouter

# Child of Player3D. Attributes enemy hits + kills to the right combat
# skill based on the source weapon's `skill_tag` (set by EditToolHandler
# or ThrowableHandler when the swing/throw originates). Listens on
# Enemy3D.died and Enemy3D.damaged via the get_tree groups system —
# every enemy joins group "enemy" on _ready, and we connect their
# signals when they enter the group.
#
# XP grants (final-tuned in design/SKILLS_AND_PROGRESSION.md):
#   sword/bow/throwables non-kill hit : 5 / 5 / 8
#   sword/bow/throwables kill          : 75 / 75 / 50
#   successful parry (when wired)      : 15

const XP_HIT: Dictionary = {"sword": 5, "bow": 5, "throwables": 8}
const XP_KILL: Dictionary = {"sword": 75, "bow": 75, "throwables": 50}
const XP_PARRY: int = 15

# Set by the active weapon — defaults to sword for melee swings.
# ThrowableHandler overrides to "throwables", future bow tools to "bow".
var current_weapon_skill: String = "sword"

func _ready() -> void:
	# Watch the enemy group so we connect to enemies spawned later.
	get_tree().node_added.connect(_on_node_added)
	# Pick up any enemies that already exist in the scene.
	for n in get_tree().get_nodes_in_group("enemy"):
		_try_connect_enemy(n)

func _on_node_added(n: Node) -> void:
	# Cheap pre-filter — most additions are not enemies. We only call
	# is_in_group once the node is fully ready (deferred).
	if n is CharacterBody3D:
		n.tree_entered.connect(_try_connect_enemy.bind(n), CONNECT_ONE_SHOT)

func _try_connect_enemy(n: Node) -> void:
	if not is_instance_valid(n):
		return
	if not n.is_in_group("enemy"):
		return
	if n.has_signal("died") and not n.died.is_connected(_on_enemy_died):
		n.died.connect(_on_enemy_died.bind(n))
	if n.has_signal("damaged") and not n.damaged.is_connected(_on_enemy_damaged):
		n.damaged.connect(_on_enemy_damaged.bind(n))

func _on_enemy_damaged(_amount: int, _hit_point: Vector3, enemy: Node) -> void:
	# Read the attributing skill off the enemy if the damage call left
	# one there (Enemy3D.take_damage will set `last_hit_skill` when the
	# combat router pull request lands), else fall back to current weapon.
	var skill: String = current_weapon_skill
	if enemy != null and "last_hit_skill" in enemy:
		var tag: String = String(enemy.get("last_hit_skill"))
		if tag != "":
			skill = tag
	var amt: int = XP_HIT.get(skill, 0)
	if amt > 0:
		SkillManager.add_xp(skill, float(amt))

func _on_enemy_died(_damage_at_kill: int, enemy: Node) -> void:
	var skill: String = current_weapon_skill
	if enemy != null and "last_hit_skill" in enemy:
		var tag: String = String(enemy.get("last_hit_skill"))
		if tag != "":
			skill = tag
	var amt: int = XP_KILL.get(skill, 0)
	if amt > 0:
		SkillManager.add_xp(skill, float(amt))

func report_parry_success() -> void:
	# Called by Player3D parry hook when (and if) parry lands.
	SkillManager.add_xp("sword", float(XP_PARRY))

# External setters used by tool handlers.
func set_weapon_skill(skill_tag: String) -> void:
	if skill_tag == "sword" or skill_tag == "bow" or skill_tag == "throwables":
		current_weapon_skill = skill_tag
