extends Node

# Autoload. The single entry point for skill XP, level-ups, perk picks,
# Legendary resets, and active-perk event dispatch.
#
# Persistence lives on GameState (see GameState._skill_levels etc.).
# When CharacterRecord lands (MP-6), this manager migrates to writing
# through CharacterRecord without changing its public API.
#
# Load order: AFTER PerkRegistry, BEFORE JournalUI (the Skills tab reads
# us in _ready).

# --- Canonical 12 skills ---
const SKILLS: PackedStringArray = [
	"sword", "throwables", "bow",
	"mining", "felling", "excavation", "demolition",
	"lockpicking", "alchemy", "smithing",
	"vitality", "speech",
]

# UI grouping for the Journal Skills tab.
const SKILL_GROUPS: Dictionary = {
	"Combat":      ["sword", "throwables", "bow"],
	"Crafting":    ["smithing", "alchemy"],
	"Survival":    ["mining", "felling", "excavation", "demolition", "vitality"],
	"Subterfuge": ["lockpicking"],
	"Social":      ["speech"],
}

# Maps the legacy GameState SkillDomain enum + sub_skill to a flat skill name.
# Used by the deprecation shim. Will be deleted in Commit 6.
const LEGACY_DOMAIN_MAP: Dictionary = {
	# Crafting domain (enum int 2)
	"2/mining":      "mining",
	"2/felling":     "felling",
	"2/excavation": "excavation",
	"2/demolition": "demolition",
	"2/smithing":   "smithing",
	"2/alchemy":    "alchemy",
	# Combat domain (enum int 0)
	"0/sword":      "sword",
	"0/bow":        "bow",
	"0/throwables": "throwables",
	# Vitality domain (enum int 1)
	"1/vitality":   "vitality",
	# Exploration (enum int 3)
	"3/lockpicking": "lockpicking",
	"3/speech":     "speech",
}

# --- Signals ---
signal xp_gained(skill: String, amount: float, total_level: int, progress: float)
signal level_up(skill: String, new_level: int)
signal perk_milestone_unlocked(skill: String, milestone_index: int, perk_points_unspent: int)
signal perk_picked(perk_id: String, skill: String)
signal legendary_reset(skill: String, total_resets: int)

# --- Owned active perks, per skill, instantiated lazily.
# perk_id -> Perk instance. Survives until a Legendary reset on the perk's skill.
var _active_instances: Dictionary = {}

# Cached hook->[perk_id] for fast dispatch. Rebuilt on perk pick/unpick.
# hook_name -> Array[String]
var _hook_index: Dictionary = {}

const ACTIVE_HOOK_NAMES: PackedStringArray = [
	"on_attack", "on_parry", "on_kill", "on_take_damage",
	"on_voxel_broken", "on_xp_gained", "on_potion_drunk", "on_lock_opened",
]

func _ready() -> void:
	# Make sure GameState has the 12 skills initialized (idempotent).
	for skill in SKILLS:
		GameState.ensure_skill_initialized(skill)
	# Build active instance pool for already-owned perks (post-load).
	_rebuild_active_instances()

# =============================================================
# XP + leveling
# =============================================================

func add_xp(skill: String, amount: float) -> void:
	if amount <= 0.0:
		return
	if not _is_valid_skill(skill):
		push_warning("[SkillManager] Unknown skill '%s' — XP ignored." % skill)
		return
	var current_level: int = GameState.get_skill_level(skill)
	if current_level >= SkillCurve.MAX_LEVEL:
		return  # capped; ignore further XP
	var progress: float = GameState.get_skill_xp_progress(skill)
	var result: Array = SkillCurve.apply_xp(current_level, progress, amount)
	var new_level: int = result[0]
	var new_progress: float = result[1]
	GameState.set_skill_state(skill, new_level, new_progress)
	xp_gained.emit(skill, amount, new_level, new_progress)
	# Fire on_xp_gained hook (lets perks like "scholar" reward extra Speech XP).
	_dispatch_event("on_xp_gained", {"skill": skill, "amount": amount})
	# Handle level-ups (possibly multiple at once for huge grants).
	while current_level < new_level:
		current_level += 1
		level_up.emit(skill, current_level)
		var milestone: int = SkillCurve.milestone_for_level(current_level)
		if milestone >= 0:
			GameState.set_perk_points_unspent(GameState.get_perk_points_unspent() + 1)
			perk_milestone_unlocked.emit(skill, milestone, GameState.get_perk_points_unspent())

# Convenience for callers that don't track current level.
func get_level(skill: String) -> int:
	return GameState.get_skill_level(skill)

func get_xp_progress(skill: String) -> float:
	return GameState.get_skill_xp_progress(skill)

func get_xp_to_next(skill: String) -> float:
	return SkillCurve.xp_to_next_level(GameState.get_skill_level(skill))

# =============================================================
# Perks
# =============================================================

func owned_perks(skill: String = "") -> PackedStringArray:
	# Pass "" for all owned perks across all skills.
	var all: PackedStringArray = GameState.get_owned_perks()
	if skill == "":
		return all
	var out: PackedStringArray = PackedStringArray()
	for pid in all:
		var pd: PerkData = PerkRegistry.get_perk(pid)
		if pd != null and pd.skill == skill:
			out.append(pid)
	return out

func can_pick_perk(perk_id: String) -> bool:
	var pd: PerkData = PerkRegistry.get_perk(perk_id)
	if pd == null:
		return false
	if GameState.has_perk(perk_id):
		return false
	if GameState.get_perk_points_unspent() <= 0:
		return false
	if GameState.get_skill_level(pd.skill) < pd.level_required:
		return false
	# Exclusive group: only one perk per group per skill.
	if pd.exclusive_group != "":
		for owned_id in owned_perks(pd.skill):
			var owned_pd: PerkData = PerkRegistry.get_perk(owned_id)
			if owned_pd != null and owned_pd.exclusive_group == pd.exclusive_group:
				return false
	return true

func pick_perk(perk_id: String) -> bool:
	if not can_pick_perk(perk_id):
		return false
	var pd: PerkData = PerkRegistry.get_perk(perk_id)
	GameState.add_owned_perk(perk_id)
	GameState.set_perk_points_unspent(GameState.get_perk_points_unspent() - 1)
	if PerkRegistry.is_active(perk_id):
		var inst: Perk = PerkRegistry.instantiate_active(perk_id)
		if inst != null:
			_active_instances[perk_id] = inst
			inst.on_picked()
	_rebuild_hook_index()
	perk_picked.emit(perk_id, pd.skill)
	return true

# =============================================================
# Legendary reset
# =============================================================

func can_make_legendary(skill: String) -> bool:
	return _is_valid_skill(skill) and GameState.get_skill_level(skill) >= SkillCurve.MAX_LEVEL

func make_legendary(skill: String) -> bool:
	if not can_make_legendary(skill):
		return false
	# Refund every owned perk in this skill.
	var refunded: int = 0
	for pid in owned_perks(skill):
		GameState.remove_owned_perk(pid)
		if _active_instances.has(pid):
			(_active_instances[pid] as Perk).on_unpicked()
			_active_instances.erase(pid)
		refunded += 1
	GameState.set_perk_points_unspent(GameState.get_perk_points_unspent() + refunded)
	GameState.set_skill_state(skill, SkillCurve.LEGENDARY_RESET_LEVEL, 0.0)
	var count: int = GameState.increment_legendary_reset(skill)
	_rebuild_hook_index()
	legendary_reset.emit(skill, count)
	return true

# =============================================================
# Event dispatch (active perks)
# =============================================================

# Public dispatch. Call from gameplay code when a relevant event fires.
# ctx is a Dictionary the caller and perks share; perks can mutate values.
func dispatch(hook_name: String, ctx: Dictionary) -> Dictionary:
	_dispatch_event(hook_name, ctx)
	return ctx

func _dispatch_event(hook_name: String, ctx: Dictionary) -> void:
	var ids: Array = _hook_index.get(hook_name, [])
	for pid in ids:
		var inst: Perk = _active_instances.get(pid, null)
		if inst == null:
			continue
		inst.call(hook_name, ctx)

func _rebuild_active_instances() -> void:
	_active_instances.clear()
	for pid in GameState.get_owned_perks():
		if PerkRegistry.is_active(pid):
			var inst: Perk = PerkRegistry.instantiate_active(pid)
			if inst != null:
				_active_instances[pid] = inst
	_rebuild_hook_index()

func _rebuild_hook_index() -> void:
	_hook_index.clear()
	for hook in ACTIVE_HOOK_NAMES:
		_hook_index[hook] = []
	for pid in _active_instances.keys():
		var inst: Perk = _active_instances[pid]
		# Index a perk under a hook only if it actually overrides it.
		# Checking has_method works because every Perk has these methods
		# from the base class, so we instead check if the script declares
		# its own version. Cheap workaround: use get_script() + get_script_method_list.
		var script: Script = inst.get_script()
		if script == null:
			continue
		for m in script.get_script_method_list():
			var mname: String = m.get("name", "")
			if mname in ACTIVE_HOOK_NAMES:
				(_hook_index[mname] as Array).append(pid)

# =============================================================
# Internals
# =============================================================

func _is_valid_skill(skill: String) -> bool:
	return skill in SKILLS

# Called by the GameState deprecation shim. Routes legacy
# (domain, sub_skill) tuples to the new flat add_xp.
func legacy_route(domain: int, sub_skill: String, amount: int) -> void:
	var key: String = "%d/%s" % [domain, sub_skill]
	var skill: String = LEGACY_DOMAIN_MAP.get(key, "")
	if skill == "":
		push_warning("[SkillManager] No legacy mapping for %s — XP dropped." % key)
		return
	add_xp(skill, float(amount))
