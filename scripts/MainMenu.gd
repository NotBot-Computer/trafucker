extends Control

func _ready() -> void:
	$PlayButton.pressed.connect(_on_play_pressed)
	$PlayButton.grab_focus()

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/PlayerSelect.tscn")
