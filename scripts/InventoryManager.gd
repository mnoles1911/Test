extends Node
# InventoryManager — Autoload. Tracks items, equipment, and crafting recipes.
#
# What this does in plain English:
#   A central record of everything Roland is carrying and wearing.
#   Items have an id (string), a display name, a type (weapon/armor/misc/crafting),
#   and a quantity. Equipment slots track what's currently equipped.
#   Crafting recipes are defined here and checked against inventory contents.
#
# HOW TO ADD AN ITEM TO ROLAND'S INVENTORY:
#   InventoryManager.add_item("iron_pommel", 1)
#
# HOW TO CHECK IF HE HAS AN ITEM:
#   InventoryManager.has_item("iron_pommel")         ← true/false
#   InventoryManager.get_quantity("iron_pommel")     ← int
#
# HOW TO EQUIP AN ITEM:
#   InventoryManager.equip("weapon", "iron_sword")
#
# HOW TO DEFINE A RECIPE (at the bottom of this file):
#   Add an entry to RECIPES — it will appear in the journal Crafting tab
#   automatically once the player has discovered it.


# =============================================================
# ITEM REGISTRY
# =============================================================
# The master list of all items in the game.
# Format: { "id": { "name": String, "type": String, "description": String,
#                   ...optional fields per item type } }
# Types: "weapon", "armor", "misc", "crafting_mat", "key_item",
#        "crown_piece", "tool", "throwable"
#
# Optional fields used by specific item types:
#   tools: tool_target_materials (Array[String]), combat_damage (int)
#   throwables: voxel_aoe_radius (float), combat_damage (int)
#   raw materials: voxel_material (String) — what voxel tag yielded it
#
# This is a static definition — it doesn't change. The inventory tracks
# which items the player actually has and in what quantity.

const ITEM_REGISTRY: Dictionary = {
	# Crown pieces
	"iron_pommel":     {"name": "Iron Pommel",     "type": "crown_piece", "description": "The pommel of the Sundered Crown. Iron, ancient, cold to the touch."},
	"bronze_ring":     {"name": "Bronze Ring",     "type": "crown_piece", "description": "A ring of worn bronze. It fits no finger."},
	"copper_wire":     {"name": "Copper Wire",     "type": "crown_piece", "description": "A coil of copper wire wound around itself. It hums faintly."},
	"silver_clasp":    {"name": "Silver Clasp",    "type": "crown_piece", "description": "A tarnished silver clasp from the Second Glade."},
	"gold_coin":       {"name": "Gold Coin",       "type": "crown_piece", "description": "Not a coin — it just looks like one. House Korvath's mark is worn off."},
	"copper_disc":     {"name": "Copper Disc",     "type": "crown_piece", "description": "A flat disc with no markings. Thrarin's treasury, Karaz-Dûn."},
	"obsidian_shard":  {"name": "Obsidian Shard",  "type": "crown_piece", "description": "Black glass. Cold. Serethi's vault."},

	# Key items
	"archive_key":     {"name": "Archive Key",     "type": "key_item",   "description": "Opens the restricted section of the Brotherhood Archive."},
	"henrietta_notes": {"name": "Henrietta's Notes","type": "key_item",  "description": "Folded paper, handwriting small and fast. She knew more than she said."},

	# Weapons
	"iron_sword":      {"name": "Iron Sword",      "type": "weapon",     "description": "Standard Brotherhood blade. Better maintained than most."},
	"ashsteel_blade":  {"name": "Ashsteel Blade",  "type": "weapon",     "description": "Forged from Ashsteel. Burns cold. The edge never dulls."},

	# Edit-verb tools — go in the weapon slot. tool_target_materials is
	# the list of voxel-material tags this tool can affect; using the
	# wrong tool on the wrong material is a no-op.
	"iron_pickaxe":    {"name": "Iron Pickaxe",    "type": "tool", "description": "Wood-hafted iron pick. For stone, ore, and patient work.",                      "tool_target_materials": ["stone", "ore"], "combat_damage": 8},
	"iron_axe":        {"name": "Iron Axe",        "type": "tool", "description": "A felling axe. Lighter than it looks; bites trees and armor in equal measure.", "tool_target_materials": ["wood"],         "combat_damage": 12},
	"iron_shovel":     {"name": "Iron Shovel",     "type": "tool", "description": "Iron blade on a hardwood haft. Earth, sand, ash — anything that yields.",        "tool_target_materials": ["dirt", "sand", "clay", "ash"], "combat_damage": 6},

	# Raw materials — yielded when player removes a voxel of the
	# matching material with the right tool.
	"raw_stone":       {"name": "Raw Stone",       "type": "crafting_mat", "description": "A chunk of stone, fresh from the strike of a pick.",  "voxel_material": "stone"},
	"raw_log":         {"name": "Raw Log",         "type": "crafting_mat", "description": "A length of green wood. Will need seasoning.",         "voxel_material": "wood"},
	"raw_dirt":        {"name": "Raw Dirt",        "type": "crafting_mat", "description": "Loose earth. Good for filling, less so for building.", "voxel_material": "dirt"},

	# Crafting materials
	"ashsteel_ingot":  {"name": "Ashsteel Ingot",  "type": "crafting_mat","description": "Raw Ashsteel. Required to forge Ashsteel weapons."},
	"binding_ash":     {"name": "Binding Ash",     "type": "crafting_mat","description": "Ash from the Drûn-Khazad slopes. Used in binding rituals."},
	"iron_ore":        {"name": "Iron Ore",        "type": "crafting_mat","description": "Common ore. Found throughout the Spine of Mira."},
}


# =============================================================
# INVENTORY
# =============================================================

var _inventory: Dictionary = {}
# item_id → quantity (int)

func add_item(item_id: String, quantity: int = 1) -> void:
	if not ITEM_REGISTRY.has(item_id):
		push_warning("[Inventory] Unknown item id: '%s'" % item_id)
		return
	_inventory[item_id] = _inventory.get(item_id, 0) + quantity
	print("[Inventory] Added %d × %s. Total: %d" % [quantity, item_id, _inventory[item_id]])
	GameState.set_flag("has_item_" + item_id, true)

func remove_item(item_id: String, quantity: int = 1) -> bool:
	var current: int = _inventory.get(item_id, 0)
	if current < quantity:
		return false
	_inventory[item_id] = current - quantity
	if _inventory[item_id] == 0:
		_inventory.erase(item_id)
		GameState.set_flag("has_item_" + item_id, false)
	print("[Inventory] Removed %d × %s." % [quantity, item_id])
	return true

func has_item(item_id: String) -> bool:
	return _inventory.get(item_id, 0) > 0

func get_quantity(item_id: String) -> int:
	return _inventory.get(item_id, 0)

func get_all_items() -> Dictionary:
	return _inventory.duplicate()

func get_items_of_type(type_filter: String) -> Array:
	var result: Array = []
	for item_id in _inventory.keys():
		if ITEM_REGISTRY.has(item_id) and ITEM_REGISTRY[item_id]["type"] == type_filter:
			result.append({"id": item_id, "quantity": _inventory[item_id]})
	return result


# =============================================================
# EQUIPMENT SLOTS
# =============================================================

var _equipped: Dictionary = {
	"weapon": "",    # item_id of the equipped weapon, or ""
	"armor":  "",
	"accessory": "",
}

func equip(slot: String, item_id: String) -> void:
	if not _equipped.has(slot):
		push_warning("[Inventory] Unknown equipment slot: '%s'" % slot)
		return
	_equipped[slot] = item_id
	print("[Inventory] Equipped '%s' in slot '%s'" % [item_id, slot])

func unequip(slot: String) -> void:
	if _equipped.has(slot):
		_equipped[slot] = ""

func get_equipped(slot: String) -> String:
	return _equipped.get(slot, "")

func get_all_equipped() -> Dictionary:
	return _equipped.duplicate()


# =============================================================
# CRAFTING RECIPES
# =============================================================
# Format: { "recipe_id": { "name": String, "result_id": String, "result_qty": int,
#                          "ingredients": [ {"id": String, "qty": int}, ... ],
#                          "discovered": bool } }
#
# discovered = false means the player has the recipe in the codex but doesn't
# know it yet (it's shown greyed out). Set to true when Roland learns it.
# discovered = true means it's visible and craftable.

const RECIPES: Dictionary = {
	"ashsteel_blade_forge": {
		"name": "Ashsteel Blade",
		"result_id": "ashsteel_blade",
		"result_qty": 1,
		"discovered_flag": "ashsteel_formula_found",
		"ingredients": [
			{"id": "ashsteel_ingot", "qty": 2},
			{"id": "iron_ore",       "qty": 1},
		],
	},
}

func can_craft(recipe_id: String) -> bool:
	if not RECIPES.has(recipe_id):
		return false
	var recipe: Dictionary = RECIPES[recipe_id]
	if not GameState.get_flag(recipe.get("discovered_flag", ""), false):
		return false
	for ingredient in recipe["ingredients"]:
		if get_quantity(ingredient["id"]) < ingredient["qty"]:
			return false
	return true

func craft(recipe_id: String) -> bool:
	if not can_craft(recipe_id):
		return false
	var recipe: Dictionary = RECIPES[recipe_id]
	for ingredient in recipe["ingredients"]:
		remove_item(ingredient["id"], ingredient["qty"])
	add_item(recipe["result_id"], recipe["result_qty"])
	print("[Inventory] Crafted: %s" % recipe["name"])
	return true

func get_known_recipes() -> Array:
	var result: Array = []
	for recipe_id in RECIPES.keys():
		var recipe: Dictionary = RECIPES[recipe_id]
		var discovered: bool = GameState.get_flag(recipe.get("discovered_flag", ""), false)
		result.append({
			"id": recipe_id,
			"name": recipe["name"],
			"result_id": recipe["result_id"],
			"discovered": discovered,
			"can_craft": can_craft(recipe_id),
			"ingredients": recipe["ingredients"],
		})
	return result


# =============================================================
# SAVE / LOAD
# =============================================================
# The inventory state is saved as part of GameState's save_game().
# These helpers serialize and restore it.

func get_save_data() -> Dictionary:
	return {
		"inventory": _inventory.duplicate(),
		"equipped": _equipped.duplicate(),
	}

func load_save_data(data: Dictionary) -> void:
	if data.has("inventory"):
		_inventory = data["inventory"]
	if data.has("equipped"):
		for slot in data["equipped"]:
			_equipped[slot] = data["equipped"][slot]


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	print("[InventoryManager] Initialized.")
	# DEBUG: give Roland a starter pickaxe so the edit-verb pipeline
	# can be exercised without first wiring up loot / vendors / a
	# story-driven tool acquisition. Remove (or guard with a debug
	# flag) when the game opens onto the Iron Chalice scene with
	# the canon starting inventory.
	add_item("iron_pickaxe", 1)
	equip("weapon", "iron_pickaxe")
