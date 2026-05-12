extends Node

# Autoload. Loads every PerkData .tres under assets/skills/perks/
# and every Perk subclass under scripts/skills/perks/ at startup.
# Active perks are instantiated lazily per-player on pick (so a perk
# can hold per-player state like "consecutive parries"). The registry
# itself only owns the class refs + the PerkData.
#
# Load order: AFTER InventoryManager (perk effect_target may reference
# item IDs we validate at startup). BEFORE SkillManager.

const PERK_DATA_ROOT: String = "res://assets/skills/perks/"
const PERK_SCRIPT_ROOT: String = "res://scripts/skills/perks/"

# perk_id -> PerkData
var _perks_by_id: Dictionary = {}
# skill -> Array[PerkData] sorted by level_required, then milestone_index
var _perks_by_skill: Dictionary = {}
# perk_id -> GDScript class (Perk subclass), only for is_active=true
var _active_classes: Dictionary = {}

signal registry_loaded(perk_count: int)

func _ready() -> void:
	_load_all()
	registry_loaded.emit(_perks_by_id.size())
	print("[PerkRegistry] Loaded %d perks across %d skills." % [_perks_by_id.size(), _perks_by_skill.size()])

func _load_all() -> void:
	_perks_by_id.clear()
	_perks_by_skill.clear()
	_active_classes.clear()
	_scan_dir(PERK_DATA_ROOT)
	# Index by skill, then sort.
	for pid in _perks_by_id.keys():
		var pd: PerkData = _perks_by_id[pid]
		if not _perks_by_skill.has(pd.skill):
			_perks_by_skill[pd.skill] = []
		(_perks_by_skill[pd.skill] as Array).append(pd)
	for skill in _perks_by_skill.keys():
		(_perks_by_skill[skill] as Array).sort_custom(_perk_sort)

func _perk_sort(a: PerkData, b: PerkData) -> bool:
	if a.level_required != b.level_required:
		return a.level_required < b.level_required
	return a.milestone_index < b.milestone_index

func _scan_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.begins_with("."):
			fname = dir.get_next()
			continue
		var full := path.path_join(fname)
		if dir.current_is_dir():
			_scan_dir(full)
		elif fname.ends_with(".tres"):
			_register_perk_file(full)
		fname = dir.get_next()
	dir.list_dir_end()

func _register_perk_file(path: String) -> void:
	var res: Resource = load(path)
	if not (res is PerkData):
		push_warning("[PerkRegistry] Skipped non-PerkData at %s" % path)
		return
	var pd: PerkData = res
	if pd.perk_id == "":
		push_warning("[PerkRegistry] Skipped perk with empty id at %s" % path)
		return
	if _perks_by_id.has(pd.perk_id):
		push_warning("[PerkRegistry] Duplicate perk_id '%s' at %s" % [pd.perk_id, path])
		return
	_perks_by_id[pd.perk_id] = pd
	if pd.is_active:
		var script_path := "%s%s/%s.gd" % [PERK_SCRIPT_ROOT, pd.skill, pd.perk_id]
		if ResourceLoader.exists(script_path):
			var script_res: GDScript = load(script_path)
			_active_classes[pd.perk_id] = script_res
		else:
			push_warning("[PerkRegistry] Active perk '%s' has no script at %s" % [pd.perk_id, script_path])

# --- Public API ---

func get_perk(perk_id: String) -> PerkData:
	return _perks_by_id.get(perk_id, null)

func has_perk(perk_id: String) -> bool:
	return _perks_by_id.has(perk_id)

func get_perks_for_skill(skill: String) -> Array:
	return _perks_by_skill.get(skill, [])

func get_perks_at_milestone(skill: String, milestone_index: int) -> Array:
	var out: Array = []
	for pd in get_perks_for_skill(skill):
		if pd.milestone_index == milestone_index:
			out.append(pd)
	return out

# Instantiate a fresh Perk instance for an active perk. Caller owns the
# returned RefCounted. Returns null for passive perks (no script).
func instantiate_active(perk_id: String) -> Perk:
	if not _active_classes.has(perk_id):
		return null
	var script: GDScript = _active_classes[perk_id]
	var inst: Perk = script.new()
	inst.data = _perks_by_id[perk_id]
	return inst

func is_active(perk_id: String) -> bool:
	return _active_classes.has(perk_id)
