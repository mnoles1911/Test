extends Object
class_name PerkQuery

# Static helper for combat / voxel / dialog code to ask "what's my
# effective multiplier / flat bonus / proc chance for X right now?"
# Walks the player's owned perks, checks each perk's effect_target +
# condition against the supplied context, and returns the aggregated
# value.
#
# Most "passive" perks in PERK_LIBRARY.md flow through here. Hand-
# rolled active perk scripts (Riposte, Bleed, etc.) use it too when
# they need to e.g. look up an existing damage multiplier before
# applying their own.

# Sum every owned perk's effect_value where:
#   - perk's effect_type matches `effect_type`
#   - perk's effect_target matches `effect_target` (or "all" / "")
#   - perk's condition matches `ctx` (see _condition_matches)
# Returns the sum. For "damage_mult" semantics this is a delta you
# add to 1.0 to get the final multiplier (so +0.10 + +0.15 = 1.25x).
static func sum(effect_type: String, effect_target: String, ctx: Dictionary = {}) -> float:
	if Engine.get_main_loop() == null:
		return 0.0
	var registry: Node = Engine.get_main_loop().root.get_node_or_null("PerkRegistry")
	if registry == null:
		return 0.0
	var owned: PackedStringArray = []
	var state: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	if state != null and state.has_method("get_owned_perks"):
		owned = state.call("get_owned_perks")
	var total: float = 0.0
	for pid in owned:
		var pd: PerkData = registry.call("get_perk", pid)
		if pd == null:
			continue
		if pd.effect_type != effect_type:
			continue
		if not _target_matches(pd.effect_target, effect_target):
			continue
		if not _condition_matches(pd.condition, ctx):
			continue
		total += pd.effect_value
	return total

# Convenience: returns 1.0 + sum, the conventional "multiplier" form.
static func mult(effect_type: String, effect_target: String, ctx: Dictionary = {}) -> float:
	return 1.0 + sum(effect_type, effect_target, ctx)

# True if any owned perk has the given flag (effect_type = "flag",
# effect_value = 1.0) matching target + condition.
static func has_flag(effect_target: String, condition: String = "", ctx: Dictionary = {}) -> bool:
	if Engine.get_main_loop() == null:
		return false
	var registry: Node = Engine.get_main_loop().root.get_node_or_null("PerkRegistry")
	if registry == null:
		return false
	var state: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	if state == null or not state.has_method("get_owned_perks"):
		return false
	for pid in state.call("get_owned_perks"):
		var pd: PerkData = registry.call("get_perk", pid)
		if pd == null:
			continue
		if pd.effect_type != "flag":
			continue
		if not _target_matches(pd.effect_target, effect_target):
			continue
		if condition != "" and pd.condition != condition:
			continue
		if not _condition_matches(pd.condition, ctx):
			continue
		return true
	return false

# Target match logic. Allows perks tagged "all" to apply universally
# and treats empty target as universal too. Otherwise strict equality.
static func _target_matches(perk_target: String, query_target: String) -> bool:
	if perk_target == "" or perk_target == "all":
		return true
	if query_target == "" or query_target == "all":
		return true
	return perk_target == query_target

# Condition match logic. Empty condition always matches. Otherwise the
# caller must have supplied a ctx key whose value is truthy for the
# matching condition token.
#
# The token vocabulary is open and shared by perk authors + gameplay
# systems. Common tokens:
#   target_full_hp           ctx.target_full_hp == true
#   target_low_hp            ctx.target_low_hp == true
#   on_power_attack          ctx.power_attack == true
#   on_headshot              ctx.headshot == true
#   on_charged               ctx.charged == true
#   lone_target              ctx.enemies_nearby <= 1
#   per_extra_enemy          ctx.enemies_nearby >= 2 (caller scales)
#   short_range              ctx.range <= 10
#   long_range               ctx.range >= 30
#   first_hit_combat         ctx.first_hit == true
#   rhythm_stack             ctx.stacks > 0 (caller scales)
#   while_sword              ctx.weapon == "sword"
#   while_moving             ctx.moving == true
#   standing_still           ctx.moving == false
#   stealth                  ctx.stealth == true
#   self_full_hp             ctx.self_full_hp == true
#   self_low_hp              ctx.self_low_hp == true
#   self_high_hp             ctx.self_high_hp == true
#   passive / ""             always
#   periodic_per_act, daily, etc. - gameplay-specific gates, default true
static func _condition_matches(condition: String, ctx: Dictionary) -> bool:
	if condition == "" or condition == "passive":
		return true
	# Conditions read from ctx directly. We support a small alias map
	# so perk authors don't have to memorize ctx keys.
	var aliases: Dictionary = {
		"on_power_attack":  "power_attack",
		"on_headshot":      "headshot",
		"on_charged":       "charged",
		"on_hit":           "on_hit",
		"on_kill":          "on_kill",
		"on_break":         "on_break",
		"on_draw_hold":     "draw_hold",
		"first_hit_combat": "first_hit",
		"first_per_day":    "first_per_day",
		"first_throw":      "first_throw",
		"lone_target":      "lone_target",
		"per_extra_enemy":  "extra_enemies",
		"rhythm_stack":     "rhythm_stack",
		"stacking_arrows":  "stacking_arrows",
		"target_full_hp":   "target_full_hp",
		"target_low_hp":    "target_low_hp",
		"target_beast":     "target_beast",
		"while_moving":     "moving",
		"standing_still":   "standing_still",
		"while_sword":      "while_sword",
		"while_pickaxe":    "while_pickaxe",
		"while_axe":        "while_axe",
		"while_shovel":     "while_shovel",
		"while_pick":       "while_pick",
		"while_mining":     "while_mining",
		"while_craft":      "while_craft",
		"while_aim":        "while_aim",
		"high_hp":          "self_high_hp",
		"self_high_hp":     "self_high_hp",
		"self_low_hp":      "self_low_hp",
		"self_full_hp":     "self_full_hp",
		"short_range":      "short_range",
		"long_range":       "long_range",
		"stealth":          "stealth",
		"deep":             "deep",
		"near_water":       "near_water",
		"city":             "city",
		"tavern_song":      "tavern_song",
		"in_combat":        "in_combat",
		"oil_or_tincture":  "oil_or_tincture",
		"healing":          "healing",
		"vs_enemy":         "vs_enemy",
		"vs_wall":          "vs_wall",
		"vs_wood":          "vs_wood",
		"vs_structure":     "vs_structure",
		"tall_column":      "tall_column",
		"cone_forward":     "cone_forward",
		"on_corpse":        "on_corpse",
		"perfect_rhythm":   "perfect_rhythm",
		"build_mode":       "build_mode",
		"self_made":        "self_made",
		"on_tree_break":    "on_tree_break",
		"on_craft":         "on_craft",
		"on_detonate":      "on_detonate",
		"on_dud":           "on_dud",
		"near_charge":      "near_charge",
		"self_explosion":   "self_explosion",
		"on_gather":        "on_gather",
		"first_per_act":    "first_per_act",
		"passive_per_act":  "passive_per_act",
		"on_land":          "on_land",
		"on_open":          "on_open",
		"on_use":           "on_use",
		"on_enter":         "on_enter",
		"on_fail":          "on_fail",
		"on_lose":          "on_lose",
		"climb":            "climbing",
		"hunger":           "hunger_active",
		"cold":             "cold",
		"heat":             "heat",
		"physical":         "physical",
		"negative":         "negative_status",
		"truth":            "telling_truth",
		"deception":        "lying",
		"hostile":          "hostile_check",
		"friendly":         "friendly_check",
		"neutral":          "neutral_check",
		"noble":            "target_noble",
		"peaceful_resolve": "peaceful_resolve",
		"active_ability":   "active_ability",
		"quest_reward":     "quest_reward",
		"lodging":          "lodging",
		"rested":           "rested",
		"tier_1":           "tier_1",
		"tier_2":           "tier_2",
		"iron_pick":        "iron_pick",
		"silver_pick":      "silver_pick",
		"daily":            "daily_gate",
		"lethal_damage":    "lethal_damage",
		"stamina_zero":     "stamina_zero",
		"post_parry_2s":    "post_parry_2s",
		"post_hit":         "post_hit",
	}
	var key: String = aliases.get(condition, condition)
	return bool(ctx.get(key, false))
