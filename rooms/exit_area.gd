extends Area3D
## Room-advance trigger. Sits over a room's exit pad; when the player body enters,
## loads the next scene. Reused by both rooms via the exported target path.

## Scene to load when the player reaches this exit.
@export_file("*.tscn") var next_scene: String

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	# Only the player advances rooms. The cat never reaches an exit pad, but match
	# by name so a stray body can't trigger a scene change.
	if next_scene != "" and body.name == "Player":
		get_tree().change_scene_to_file(next_scene)
