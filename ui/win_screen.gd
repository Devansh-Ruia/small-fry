extends Control
## Win screen shown after room_02's exit. Text plus a button back to the menu.

func _ready() -> void:
	$Center/VBox/MenuButton.pressed.connect(_on_menu)

func _on_menu() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
