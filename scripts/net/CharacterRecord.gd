class_name CharacterRecord extends Resource
# CharacterRecord — portable character data for cross-host play.
#
# WHAT THIS IS (plain English):
#
#   Each guest's character (skills, inventory, gold, equipment,
#   appearance) is saved on their OWN machine, not the host's. When
#   they join a friend's session, their character record travels
#   into that world. When they disconnect and join a different
#   host, the same character record carries forward. Same model as
#   Dark Souls / Valheim — your character is yours, the world is
#   the host's.
#
# WHY A Resource SUBCLASS:
#
#   - Godot's ResourceSaver / ResourceLoader handle .tres serialization
#     for us — no custom file format to maintain.
#   - Inspector-editable: dev / debug tooling can manually edit a
#     CharacterRecord by opening the .tres in the editor.
#   - Versioned schema via @export var schema_version; older versions
#     of the file can be detected and migrated.
#   - Cleanly serializable over RPC during the join handshake (RPC
#     supports Resource arguments natively in Godot 4).
#
# FILE LOCATION:
#
#   user://characters/{steam_id_decimal}.tres
#
#   Steam ID is uint64; we use the decimal stringification so the
#   filename is human-readable. The ID is also stored on the record
#   itself for redundancy (filename rename shouldn't break lookups).
#
# WHAT'S IN HERE:
#
#   - schema_version    int — bumped on backward-incompatible changes
#   - steam_id          int — owning Steam ID, redundant with filename
#   - character_id      String — UUID, stable across renames
#   - display_name      String — shown in lobby + dialog
#   - created_unix      int — first-creation timestamp
#   - last_played_unix  int — last save timestamp (sort key in UI)
#   - appearance        Dictionary — body color, hair, etc. (free-form)
#   - skill_levels      Dictionary[String, int] — { "mining": 12, ... }
#   - perks             PackedStringArray — earned perk ids
#   - inventory_items   Array — InventoryItemRecord dicts: { id, qty, meta }
#   - equipped          Dictionary[String, String] — slot -> item_id
#   - gold              int
#   - play_time_seconds int — cumulative time in any session
#
# HOST VALIDATION (separate file CharacterValidator.gd):
#
#   The host runs a sanitization pass on every joining record:
#   - All item IDs exist in the host's InventoryManager.ITEM_REGISTRY
#   - No items flagged unique_to_main_character
#   - No quest-tagged items unless host's policy whitelists them
#   - Inventory ≤ MAX_INVENTORY_STACKS (default 200)
#   - Skill levels ≤ MAX_SKILL_LEVEL (default 100)
#
# WHAT'S DELIBERATELY NOT HERE:
#
#   - World state (carved chunks, NPC dispositions, quest flags) —
#     that lives on the host's machine and is the host's save.
#   - Companion records (Orion, Dagna) — companions follow the host
#     since they're tied to the host's Roland-narrative.


# =============================================================
# SCHEMA
# =============================================================

const CURRENT_SCHEMA_VERSION: int = 1

@export var schema_version: int = CURRENT_SCHEMA_VERSION

@export var steam_id: int = 0
@export var character_id: String = ""

@export var display_name: String = "Wanderer"

@export var created_unix: int = 0
@export var last_played_unix: int = 0

## Free-form appearance dict. v1 keys (all optional):
##   "body_color":  Color
##   "hair_color":  Color
##   "head_variant": int
## Adding new keys is backward-compatible — older clients ignore them.
@export var appearance: Dictionary = {}

## Skill levels keyed by domain id. Example domains (per
## design/SKILLS_AND_PROGRESSION.md): "mining", "smithing",
## "swordsmanship", "alchemy". Missing key = level 0.
@export var skill_levels: Dictionary = {}

## Earned perks across all skill trees. Strings are perk ids
## (e.g. "iron_grip", "deep_breaths"); a perk id may map to any
## skill tree, so we store the flat set.
@export var perks: PackedStringArray = PackedStringArray()

## Inventory contents. Each entry is a Dictionary:
##   { "id": String, "qty": int, "meta": Dictionary }
## meta carries item-specific state (condition for equipment,
## potion potency tier, signed item authorship). InventoryManager's
## ITEM_REGISTRY validates the id and meta schema.
@export var inventory_items: Array = []

## Currently equipped items by slot. Slots match
## design/INVENTORY_AND_EQUIPMENT_SYSTEM.md:
##   "weapon_main", "weapon_off", "armor_head", "armor_torso",
##   "armor_legs", "armor_feet", "trinket_1", "trinket_2"
@export var equipped: Dictionary = {}

@export var gold: int = 0

@export var play_time_seconds: int = 0


# =============================================================
# CONSTRUCTION + COPYING
# =============================================================

## Convenience to create a fresh record for a Steam user. Generates
## a stable UUID-like character_id from the steam_id + creation
## timestamp so the same Steam user can have multiple characters
## without ID collision.
static func make_new(for_steam_id: int, name: String) -> CharacterRecord:
	var now: int = Time.get_unix_time_from_system()
	var record := CharacterRecord.new()
	record.schema_version = CURRENT_SCHEMA_VERSION
	record.steam_id = for_steam_id
	record.character_id = "%d_%d" % [for_steam_id, now]
	record.display_name = name
	record.created_unix = now
	record.last_played_unix = now
	return record


## Duplicate the record. Used when sending across RPC or sanitizing
## before persistence — never ship the live record by reference.
func duplicate_record() -> CharacterRecord:
	var copy := CharacterRecord.new()
	copy.schema_version = schema_version
	copy.steam_id = steam_id
	copy.character_id = character_id
	copy.display_name = display_name
	copy.created_unix = created_unix
	copy.last_played_unix = last_played_unix
	copy.appearance = appearance.duplicate(true)
	copy.skill_levels = skill_levels.duplicate(true)
	copy.perks = perks.duplicate()
	copy.inventory_items = inventory_items.duplicate(true)
	copy.equipped = equipped.duplicate(true)
	copy.gold = gold
	copy.play_time_seconds = play_time_seconds
	return copy
