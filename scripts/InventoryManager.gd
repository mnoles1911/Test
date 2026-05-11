extends Node
# InventoryManager — Autoload. Tracks items, equipment, and crafting recipes.

signal coin_changed(new_balance: int)
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
	"iron_pickaxe":    {"name": "Iron Pickaxe",    "type": "tool", "description": "Wood-hafted iron pick. For stone, ore, marble, and patient work.",                "tool_target_materials": ["stone", "ore", "marble"], "combat_damage": 8},
	"iron_axe":        {"name": "Iron Axe",        "type": "tool", "description": "A felling axe. Lighter than it looks; bites trees and armor in equal measure.", "tool_target_materials": ["wood", "leaves"],        "combat_damage": 12},
	"iron_shovel":     {"name": "Iron Shovel",     "type": "tool", "description": "Iron blade on a hardwood haft. Earth, sand, gravel, clay, ash — anything that yields.", "tool_target_materials": ["dirt", "sand", "gravel", "clay", "ash"], "combat_damage": 6},
	"bucket":          {"name": "Bucket",          "type": "tool", "description": "Empty bucket. Swing at water to fill it.",                                       "tool_target_materials": ["water"], "combat_damage": 0},
	"bucket_filled":   {"name": "Bucket of Water", "type": "tool", "description": "Sloshes when carried. Swing at empty space to place a water source.",            "tool_target_materials": ["water"], "combat_damage": 0},

	# Raw materials — yielded when player removes a voxel of the
	# matching material with the right tool.
	"raw_stone":       {"name": "Raw Stone",       "type": "crafting_mat", "description": "A chunk of stone, fresh from the strike of a pick.",   "voxel_material": "stone"},
	"raw_log":         {"name": "Raw Log",         "type": "crafting_mat", "description": "A length of green wood. Will need seasoning.",          "voxel_material": "wood"},
	"raw_dirt":        {"name": "Raw Dirt",        "type": "crafting_mat", "description": "Loose earth. Good for filling, less so for building.", "voxel_material": "dirt"},
	"raw_sand":        {"name": "Raw Sand",        "type": "crafting_mat", "description": "Pale grit, scooped from a riverbank or beach.",         "voxel_material": "sand"},
	"raw_gravel":      {"name": "Raw Gravel",      "type": "crafting_mat", "description": "A handful of mixed shingle and small stones.",          "voxel_material": "gravel"},
	"raw_clay":        {"name": "Raw Clay",        "type": "crafting_mat", "description": "Wet blue-grey clay from the tide-line. Shapeable.",     "voxel_material": "clay"},
	"raw_marble":      {"name": "Raw Marble",      "type": "crafting_mat", "description": "A chunk of weathered island marble, white-veined.",    "voxel_material": "marble"},
	"raw_leaves":      {"name": "Raw Leaves",      "type": "crafting_mat", "description": "A bundle of fresh-cut foliage. Kindling, mostly.",       "voxel_material": "leaves"},
	"copper_ore":      {"name": "Copper Ore",      "type": "crafting_mat", "description": "Coarse ore: orange-bronze metal striped through grey stone.", "voxel_material": "copper_ore"},

	# Crafting materials
	"ashsteel_ingot":  {"name": "Ashsteel Ingot",  "type": "crafting_mat","description": "Raw Ashsteel. Required to forge Ashsteel weapons."},
	"binding_ash":     {"name": "Binding Ash",     "type": "crafting_mat","description": "Ash from the Drûn-Khazad slopes. Used in binding rituals."},
	"iron_ore":        {"name": "Iron Ore",        "type": "crafting_mat","description": "Common ore. Found throughout the Spine of Mira."},

	# Throwables — explosives clear voxels in their AOE on detonation
	# in addition to combat damage. Routed through VoxelEditManager so
	# they respect NoEditZones (still deal damage but leave masonry
	# intact inside settlements).
	"powder_charge":   {"name": "Powder Charge",   "type": "throwable", "description": "A linen-wrapped charge of saltpeter and sulphur. Loud. Bites stone.",     "voxel_aoe_radius": 0.75, "combat_damage": 40},
	"sappers_bundle":  {"name": "Sapper's Bundle", "type": "throwable", "description": "Multiple charges bound together. Reserved for breaching, not for fights.", "voxel_aoe_radius": 1.5,  "combat_damage": 80},
	# Single-target throwable. No voxel AOE (set 0.0 so ThrowableHandler's
	# spawn-time push doesn't try to override an irrelevant field). The
	# combat_damage here is the LIGHT-throw value; charged throws scale
	# this up at the input layer in Phase 3.
	"spear":           {"name": "Throwing Spear",  "type": "throwable", "description": "A wood-shafted iron spear, balanced for the throw. Sticks where it lands.",   "voxel_aoe_radius": 0.0,  "combat_damage": 30},

	# Lockpicks — consumable tools for the lockpicking minigame.
	# One pick is consumed per failed attempt (snap). Successful picks and
	# player-cancelled attempts (Esc) do NOT consume a pick.
	# Fine picks add +1.5 s to the hold timer at any skill tier.
	"lockpick_standard": {"name": "Lockpick",       "type": "misc", "description": "A simple steel pick. Snaps under careless hands, but a steady Roland can open most locks."},
	"lockpick_fine":     {"name": "Fine Lockpick",  "type": "misc", "description": "Master-filed tolerances. Adds 1.5 seconds to the hold window — the difference between a snap and a set on Hard locks."},
}


# =============================================================
# INVENTORY
# =============================================================

var _inventory: Dictionary = {}
# item_id → quantity (int)


# =============================================================
# COIN — wager currency for tavern games and (eventually) shops
# =============================================================
# Coin is its own field, not an entry in ITEM_REGISTRY. Kept separate so
# vendor / mini-game / quest reward sites don't have to special-case
# `add_item("coin", N)` against every other inventory operation.

var _coin_balance: int = 0


func add_coin(amount: int) -> void:
	if amount <= 0:
		return
	_coin_balance += amount
	coin_changed.emit(_coin_balance)
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Coin: +%d (total %d)" % [amount, _coin_balance])


func spend_coin(amount: int) -> bool:
	# Returns true if the spend went through; false if the player can't afford it.
	# Callers should check the return value before assuming the transaction landed.
	if amount <= 0:
		return true
	if _coin_balance < amount:
		return false
	_coin_balance -= amount
	coin_changed.emit(_coin_balance)
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Coin: -%d (left %d)" % [amount, _coin_balance])
	return true


func get_coin_balance() -> int:
	return _coin_balance


func set_coin_balance(amount: int) -> void:
	# Direct setter for debug / dev-scene seeding. Avoid in gameplay code —
	# use add_coin / spend_coin so DebugOverlay logs the delta.
	_coin_balance = max(0, amount)
	coin_changed.emit(_coin_balance)


# =============================================================
# QUICK SLOTS — number keys 1-4 bind to specific inventory items
# =============================================================
#
# Designer model: each of the four slots holds an item_id (or "" for
# empty). When the player presses the corresponding `quick_slot_N`
# input action, we equip slot N's item into the "weapon" slot. Right-
# click on a slot in the HUD will eventually open a rebind picker
# (Phase 2 — stubbed for now via set_quick_slot, callable from any
# UI we build later).
#
# Default bindings cover the starting kit (pickaxe / shovel / axe /
# powder_charge). Saved to disk via to_dict / from_dict so the
# player's chosen bindings survive across sessions.

const QUICK_SLOT_COUNT: int = 4

var _quick_slots: Array[String] = ["", "", "", ""]


func set_quick_slot(idx: int, item_id: String) -> void:
	# Bind slot `idx` (0-based; the HUD displays it as N+1) to the
	# given item_id, or "" to clear. Doesn't validate that the player
	# OWNS the item — empty slots and "ghost" bindings are fine,
	# they just don't equip anything when pressed.
	if idx < 0 or idx >= QUICK_SLOT_COUNT:
		push_warning("[Inventory] set_quick_slot: idx %d out of range [0,%d)" % [idx, QUICK_SLOT_COUNT])
		return
	_quick_slots[idx] = item_id
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Quick slot %d bound to '%s'" % [idx + 1, item_id])


func get_quick_slot(idx: int) -> String:
	if idx < 0 or idx >= QUICK_SLOT_COUNT:
		return ""
	return _quick_slots[idx]


func get_quick_slots() -> Array[String]:
	# Returned by reference — callers MUST NOT mutate (use set_quick_slot
	# to keep DebugOverlay logging consistent).
	return _quick_slots


func equip_quick_slot(idx: int) -> bool:
	# Equip the item bound to slot `idx` into the "weapon" slot.
	# Returns true on success, false if slot empty / item not in
	# inventory (e.g. player threw their last powder charge).
	var item_id: String = get_quick_slot(idx)
	if item_id == "":
		return false
	if not has_item(item_id):
		# Slot binding still exists but the player doesn't have any.
		# Don't auto-clear the binding — they may pick the item up
		# again and want the slot still wired.
		if get_node_or_null("/root/DebugOverlay"):
			DebugOverlay.log_action("Quick slot %d ('%s') empty — none in inventory" % [idx + 1, item_id])
		return false
	equip("weapon", item_id)
	return true

func add_item(item_id: String, quantity: int = 1) -> void:
	if not ITEM_REGISTRY.has(item_id):
		push_warning("[Inventory] Unknown item id: '%s'" % item_id)
		return
	_inventory[item_id] = _inventory.get(item_id, 0) + quantity
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Inventory: +%d %s (total %d)" % [quantity, item_id, _inventory[item_id]])
	else:
		print("[Inventory] Added %d × %s. Total: %d" % [quantity, item_id, _inventory[item_id]])
	GameState.set_flag("has_item_" + item_id, true)

func remove_item(item_id: String, quantity: int = 1) -> bool:
	var current: int = _inventory.get(item_id, 0)
	if current < quantity:
		return false
	_inventory[item_id] = current - quantity
	var remaining: int = _inventory[item_id]
	if remaining == 0:
		_inventory.erase(item_id)
		GameState.set_flag("has_item_" + item_id, false)
	if get_node_or_null("/root/DebugOverlay"):
		DebugOverlay.log_action("Inventory: -%d %s (left %d)" % [quantity, item_id, remaining])
	else:
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
		"coin_balance": _coin_balance,
	}

func load_save_data(data: Dictionary) -> void:
	if data.has("inventory"):
		_inventory = data["inventory"]
	if data.has("equipped"):
		for slot in data["equipped"]:
			_equipped[slot] = data["equipped"][slot]
	if data.has("coin_balance"):
		_coin_balance = int(data["coin_balance"])
		coin_changed.emit(_coin_balance)


# =============================================================
# LIFECYCLE
# =============================================================

func _ready() -> void:
	print("[InventoryManager] Initialized.")
	# Initial inventory is established via reset_to_defaults so the
	# starting kit is defined in one place — same content runs at
	# autoload init AND when the player clicks NEW GAME from the
	# main menu (see GameState.reset_for_new_game).
	reset_to_defaults()


func reset_to_defaults() -> void:
	# Wipes the in-memory inventory + equipment slots and re-applies
	# the debug starting kit (pickaxe + 5 powder charges). Called
	# from _ready at autoload init, and from
	# GameState.reset_for_new_game on NEW GAME so a new playthrough
	# doesn't inherit items from the previous one.
	#
	# Remove (or guard with a debug flag) when the game opens onto
	# the Iron Chalice scene with the canon Game-One starting
	# inventory authored elsewhere.
	_inventory.clear()
	_equipped = {
		"weapon": "",
		"armor":  "",
		"accessory": "",
	}
	_coin_balance = 0
	coin_changed.emit(0)
	add_item("iron_pickaxe", 1)
	add_item("iron_shovel", 1)
	add_item("iron_axe", 1)
	equip("weapon", "iron_shovel")
	# Equip shovel by default — surface terrain at spawn is grass/dirt
	# which needs a shovel; pickaxe only breaks stone. Player can swap
	# via number keys 1-4 (quick slots, see below) once equipped.
	add_item("powder_charge", 5)
	add_item("spear", 5)
	# Spear is given here so it's available in any scene that loads
	# the autoload, but NOT bound to a quick slot — the quick-slot bar
	# is capped at 4 entries (QUICK_SLOT_COUNT) and the existing tool
	# loadout fills it. Combat-focused scenes (CombatTest, future
	# combat encounters) equip the spear directly via
	# InventoryManager.equip("weapon", "spear") in their bootstrap.

	# Default quick-slot bindings — number keys 1-4 swap to these tools.
	# Player can rebind via right-click in the HUD (Phase 2). Order
	# matches the rough usage frequency: shovel (#1) for surface dirt
	# is the most common use, pickaxe (#2) when you hit stone, axe (#3)
	# rarely-but-needed for trees, powder_charge (#4) for blasting.
	set_quick_slot(0, "iron_shovel")
	set_quick_slot(1, "iron_pickaxe")
	set_quick_slot(2, "iron_axe")
	set_quick_slot(3, "powder_charge")
