extends Perk

# Double Loot  (lockpicking L36, milestone 8)
# Pick locks drop +1 random consumable.
#
# Random consumable on every lock open.



func _init() -> void:
	pass

func on_lock_opened(ctx: Dictionary) -> void:
	if Engine.get_main_loop() == null:
		return
	var inv: Node = Engine.get_main_loop().root.get_node_or_null("InventoryManager")
	if inv == null or not inv.has_method("add_item"):
		return
	var pool: PackedStringArray = ["potion_healing", "potion_stamina", "lockpick_standard"]
	inv.call("add_item", pool[randi() % pool.size()], 1)
