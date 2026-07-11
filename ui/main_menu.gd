extends Control
## Main menu. Title text plus a Start button into room_01 and an optional Quit.

func _ready() -> void:
	$Center/VBox/StartButton.pressed.connect(_on_start)
	$Center/VBox/QuitButton.pressed.connect(_on_quit)

func _on_start() -> void:
	get_tree().change_scene_to_file("res://rooms/room_01.tscn")

func _on_quit() -> void:
	get_tree().quit()
