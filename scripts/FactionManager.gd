extends Node

# Autoload. Wraps GameState faction-disposition storage. Expanded in
# commit 4 of the skill PR with the six Game One factions and trainer
# gating helpers; this stub exists for autoload registration and
# provides the canonical get/set API SkillManager + trainers call.

const FRIENDLY_THRESHOLD: int = 75   # >= 75 = Friendly (trainer access)

# Canonical factions for Game One. Sourced from design/FACTION_SYSTEM.md.
const FACTIONS: PackedStringArray = [
	"copper_guard",
	"order_of_the_white_hart",
	"shroud_circle",
	"thalvine_court",
	"brightmoor_smiths",
	"ashfallen_clans",
]

func get_disposition(faction_id: String) -> int:
	return GameState.get_faction_disposition(faction_id)

func set_disposition(faction_id: String, value: int) -> void:
	GameState.set_faction_disposition(faction_id, value)

func modify_disposition(faction_id: String, delta: int) -> int:
	return GameState.modify_faction_disposition(faction_id, delta)

func is_friendly(faction_id: String) -> bool:
	return get_disposition(faction_id) >= FRIENDLY_THRESHOLD

func disposition_label(value: int) -> String:
	# UI-facing label matching design/FACTION_SYSTEM.md scale.
	if value >= 90: return "Allied"
	if value >= 75: return "Friendly"
	if value >= 50: return "Neutral"
	if value >= 25: return "Wary"
	return "Hostile"
