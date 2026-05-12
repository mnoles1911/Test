extends Node
class_name AlchemyStation

# Minimal Alchemy crafting service. Attach to an alchemy station scene
# in the world; future minigame UI calls craft() with a recipe id and
# ingredient inventory. This v1 scaffolding fires Alchemy XP +
# on_potion_drunk hook dispatch but does NOT yet validate ingredient
# combinations against a recipe table — that polish ships when the
# alchemy recipe library lands (see design/ITEM_LIBRARY.md
# "Alchemy Recipes").

const XP_PER_CRAFT: float = 15.0

signal potion_crafted(potion_id: String)

# Public entry point. `recipe_id` is the produced potion's item_id;
# `consumed_ingredients` is { ingredient_id: count } the caller has
# already verified the player can pay. The station withdraws them.
func craft(recipe_id: String, consumed_ingredients: Dictionary) -> bool:
	if not get_node_or_null("/root/InventoryManager"):
		return false
	for ing_id in consumed_ingredients.keys():
		var count: int = int(consumed_ingredients[ing_id])
		if InventoryManager.has_method("remove_item"):
			InventoryManager.call("remove_item", ing_id, count)
	if InventoryManager.has_method("add_item"):
		InventoryManager.call("add_item", recipe_id, 1)
	if get_node_or_null("/root/SkillManager"):
		SkillManager.add_xp("alchemy", XP_PER_CRAFT)
	potion_crafted.emit(recipe_id)
	return true


# Called when the player drinks a potion (InventoryManager will route
# here once consumable use is wired). Dispatches the perk hook so
# perks like alch_field_medic / alch_versatility can adjust effects.
func on_potion_drunk(potion_id: String) -> void:
	if get_node_or_null("/root/SkillManager"):
		SkillManager.dispatch("on_potion_drunk", {"potion_id": potion_id})
