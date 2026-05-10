class_name DiceOpponentData
extends Resource
# DiceOpponentData — per-NPC dice game configuration. One .tres per opponent.
#
# Place files at: assets/dice/opponents/<npc_id>.tres
#
# v1 reads npc_id, display_name, min_wager, max_wager. ai_aggression is
# read but unused — it's a slot for future tuning when the AI grows
# beyond the single naive heuristic.

@export var npc_id: String = ""
@export var display_name: String = ""
@export_range(1, 1000) var min_wager: int = 5
@export_range(1, 10000) var max_wager: int = 50
@export_range(0.0, 1.0) var ai_aggression: float = 0.5
