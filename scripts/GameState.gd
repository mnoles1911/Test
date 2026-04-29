extends Node
# GameState is an Autoload singleton.
#
# What that means in plain English:
#   Godot loads this script once when the game starts and keeps it alive
#   for the entire session — it never gets deleted when scenes change.
#   Every scene can access it by typing: GameState.variable_name
#
# This is where we store anything that needs to survive scene transitions:
#   - Where the player is in the world
#   - Which quests are done
#   - Which companions are in the party
#   - Save/load data
#
# This file is a stub for Milestone 1. Real data will be added as each
# system is built.


# --- Player state ---
# Updated by Player.gd before any scene transition.
var player_position: Vector2 = Vector2.ZERO
var current_scene: String = ""


# --- Quest flags ---
# Each quest gets one boolean. Set it to true when the quest is resolved.
# Example (uncomment and fill in as quests are built):
#
# var quest_pommel_complete: bool = false
# var quest_henriettas_thread_complete: bool = false
# var quest_gold_coin_complete: bool = false


# --- Companion roster ---
# Each companion gets one boolean. True = currently in the party.
# Example:
#
# var companion_orion_active: bool = false
# var companion_dagna_active: bool = false


func _ready() -> void:
	# This fires once when the game starts.
	# Useful for confirming the autoload is working during development.
	print("[GameState] Initialized.")
