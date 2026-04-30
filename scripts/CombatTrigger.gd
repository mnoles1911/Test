extends Area2D
# Attached to a trigger zone in the world scene.
# When the player walks into this area, combat begins.
#
# This uses a simple scene change (no fade) for Milestone 3.
# Scene transitions can be wired through SceneTransition.gd in a later milestone.


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body.name == "Player":
		print("[CombatTrigger] Entering combat.")
		get_tree().change_scene_to_file("res://scenes/Combat.tscn")
