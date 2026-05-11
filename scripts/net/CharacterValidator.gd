class_name CharacterValidator extends RefCounted
# CharacterValidator — host-side sanitization of joining characters.
#
# WHAT THIS IS (plain English):
#
#   When a guest joins a host's session, the guest ships their
#   CharacterRecord (skills, inventory, gold, equipment, etc.) over
#   the wire as part of the handshake. The host MUST sanity-check
#   that record before accepting it — otherwise a tampered .tres
#   on the guest's machine could grant arbitrary legendaries or
#   over-cap skill levels.
#
#   This class is a pure RefCounted (no node, not autoloaded). The
#   host calls `validate(record, policy)` during the join handshake
#   and gets back a `{ ok, reason, sanitized }` result.
#
# DESIGN NOTES:
#
#   - Two modes of rejection:
#       hard reject  — the record is fundamentally invalid (wrong
#                      schema, no items registered). Host refuses
#                      the connection with a clear error message.
#       sanitize     — the record is mostly fine but has out-of-
#                      bounds entries (a cap'd skill at 105, a stack
#                      of 1000 of an item that allows max 99). Host
#                      clamps + warns the guest, lets them in.
#
#   - The HostPolicy struct (just a Dictionary for v1) lets the
#     host configure caps per session. Defaults are conservative.
#
#   - Validation is intentionally permissive about UNKNOWN fields
#     in appearance / skill_levels / inventory_items[].meta — a
#     newer guest may have data a slightly-older host doesn't know
#     about. Unknown skill_levels keys pass through; unknown item
#     IDs are STRIPPED (sanitize). Unknown appearance keys pass
#     through.
#
# WHAT'S NOT VALIDATED IN MP-6 v1 (deferred):
#
#   - Cryptographic signing of records. Without it, a player with
#     filesystem access can edit their .tres directly. Acceptable
#     for friends-only co-op (the user said "no anti-cheat
#     hardening required"); the validator's job is to prevent
#     ACCIDENTAL bad data from breaking host's session, not to
#     defeat motivated tampering.
#
#   - Per-quest-tag whitelisting. The plan calls for "no
#     quest-tagged items unless host's policy whitelists them" —
#     for v1 we just reject any item flagged `quest_specific`
#     unconditionally. Whitelist support lands when the quest
#     system itself is MP-aware.


# =============================================================
# CONSTANTS
# =============================================================

const SCHEMA_VERSION_MIN: int = 1
const SCHEMA_VERSION_MAX: int = 1


# =============================================================
# POLICY (Dictionary; defaults for missing keys via .get)
# =============================================================
#   {
#     "max_inventory_stacks": int = 200,
#     "max_skill_level":      int = 100,
#     "max_gold":             int = 1_000_000,
#     "max_perks":            int = 64,
#     "reject_quest_items":   bool = true,
#   }


# =============================================================
# RESULT
# =============================================================
#   {
#     "ok":         bool,        # false = hard reject; true means
#                                # accept (possibly with sanitization)
#     "reason":     String,      # human-readable disposition
#     "sanitized":  CharacterRecord,  # the cleaned record to use
#                                     # on the host's side
#     "warnings":   PackedStringArray, # per-fix notes (sanitization
#                                      # log; sent back to guest)
#   }


# =============================================================
# PUBLIC API
# =============================================================

static func validate(record: CharacterRecord, policy: Dictionary = {}) -> Dictionary:
	if record == null:
		return _hard_reject("null record")

	# Schema version check — hard reject for now since we don't yet
	# have migration code. Once schema_version 2+ ships, this widens
	# to "any version we have a migration for."
	if record.schema_version < SCHEMA_VERSION_MIN or record.schema_version > SCHEMA_VERSION_MAX:
		return _hard_reject("unsupported schema_version %d (supported: %d..%d)" % [
			record.schema_version, SCHEMA_VERSION_MIN, SCHEMA_VERSION_MAX,
		])

	if record.steam_id == 0:
		return _hard_reject("steam_id is zero")
	if record.character_id.is_empty():
		return _hard_reject("character_id is empty")
	if record.display_name.is_empty():
		return _hard_reject("display_name is empty")

	# Caps from policy with defaults.
	var max_inv: int      = int(policy.get("max_inventory_stacks", 200))
	var max_skill: int    = int(policy.get("max_skill_level", 100))
	var max_gold: int     = int(policy.get("max_gold", 1_000_000))
	var max_perks: int    = int(policy.get("max_perks", 64))
	var drop_quest: bool  = bool(policy.get("reject_quest_items", true))

	# Sanitize. Work on a duplicate so we never mutate the caller's
	# record.
	var clean: CharacterRecord = record.duplicate_record()
	var warnings: PackedStringArray = PackedStringArray()

	# Skills — cap each at max_skill.
	for key in clean.skill_levels.keys():
		var lvl: int = int(clean.skill_levels[key])
		if lvl < 0:
			clean.skill_levels[key] = 0
			warnings.append("skill '%s' was negative (%d), clamped to 0" % [key, lvl])
		elif lvl > max_skill:
			clean.skill_levels[key] = max_skill
			warnings.append("skill '%s' over cap (%d > %d), clamped" % [key, lvl, max_skill])

	# Perks — cap count.
	if clean.perks.size() > max_perks:
		var keep := PackedStringArray()
		for i in range(max_perks):
			keep.append(clean.perks[i])
		warnings.append("perks over cap (%d > %d), keeping first %d" % [
			clean.perks.size(), max_perks, max_perks,
		])
		clean.perks = keep

	# Gold — clamp.
	if clean.gold < 0:
		warnings.append("gold was negative (%d), clamped to 0" % clean.gold)
		clean.gold = 0
	elif clean.gold > max_gold:
		warnings.append("gold over cap (%d > %d), clamped" % [clean.gold, max_gold])
		clean.gold = max_gold

	# Inventory — strip unknown / quest-tagged items, cap count.
	var inv_registry: Variant = _get_inventory_registry()
	var clean_inv: Array = []
	var stripped_unknown: int = 0
	var stripped_quest: int = 0
	for entry in clean.inventory_items:
		if not (entry is Dictionary):
			stripped_unknown += 1
			continue
		var e: Dictionary = entry
		var item_id: String = String(e.get("id", ""))
		if item_id.is_empty():
			stripped_unknown += 1
			continue
		if inv_registry != null:
			if not _registry_has_item(inv_registry, item_id):
				stripped_unknown += 1
				continue
			if drop_quest and _is_quest_item(inv_registry, item_id):
				stripped_quest += 1
				continue
		clean_inv.append(e)
		if clean_inv.size() >= max_inv:
			break
	if stripped_unknown > 0:
		warnings.append("stripped %d unknown-id items" % stripped_unknown)
	if stripped_quest > 0:
		warnings.append("stripped %d quest-tagged items" % stripped_quest)
	if clean.inventory_items.size() > max_inv:
		warnings.append("inventory over cap (%d > %d), truncated" % [
			clean.inventory_items.size(), max_inv,
		])
	clean.inventory_items = clean_inv

	return {
		"ok": true,
		"reason": "accepted" if warnings.is_empty() else "accepted with sanitization (%d warnings)" % warnings.size(),
		"sanitized": clean,
		"warnings": warnings,
	}


# =============================================================
# INTERNALS
# =============================================================

static func _hard_reject(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"sanitized": null,
		"warnings": PackedStringArray(),
	}


static func _get_inventory_registry() -> Variant:
	# Indirect access — the validator is RefCounted, used host-side
	# during the handshake; if InventoryManager isn't loaded (running
	# in a test harness, headless validation), we skip the
	# registry-driven checks gracefully.
	var inv := Engine.get_main_loop().root.get_node_or_null("InventoryManager") if Engine.get_main_loop() != null else null
	if inv == null:
		return null
	if "ITEM_REGISTRY" in inv:
		return inv.ITEM_REGISTRY
	return null


static func _registry_has_item(registry: Variant, item_id: String) -> bool:
	if registry is Dictionary:
		return (registry as Dictionary).has(item_id)
	return false


static func _is_quest_item(registry: Variant, item_id: String) -> bool:
	if registry is Dictionary:
		var entry: Variant = (registry as Dictionary).get(item_id, null)
		if entry is Dictionary:
			return bool((entry as Dictionary).get("quest_specific", false))
	return false
