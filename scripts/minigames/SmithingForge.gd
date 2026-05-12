extends Node
class_name SmithingForge

# Minimal Smithing crafting service. Same shape as AlchemyStation —
# v1 scaffolding fires Smithing XP and provides the craft() entry
# point. Quality rolls, three-strike rhythm UI, and tier validation
# all land in a follow-up PR. design/CRAFTING.md is the authoritative
# spec.

const XP_PER_CRAFT_BASE: float = 20.0

signal item_smithed(item_id: String, quality: int)

# `tier`: 1..3 (iron, silver, ashsteel). XP scales tier × XP_PER_CRAFT_BASE.
# `consumed_ingredients` is the same shape AlchemyStation expects.
func craft(item_id: String, tier: int, consumed_ingredients: Dictionary) -> bool:
	if not get_node_or_null("/root/InventoryManager"):
		return false
	for ing_id in consumed_ingredients.keys():
		var count: int = int(consumed_ingredients[ing_id])
		if InventoryManager.has_method("remove_item"):
			InventoryManager.call("remove_item", ing_id, count)
	if InventoryManager.has_method("add_item"):
		InventoryManager.call("add_item", item_id, 1)
	var xp: float = XP_PER_CRAFT_BASE * float(max(1, tier))
	if get_node_or_null("/root/SkillManager"):
		SkillManager.add_xp("smithing", xp)
	item_smithed.emit(item_id, tier)
	return true
