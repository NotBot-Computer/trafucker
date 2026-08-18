extends Control

func _ready() -> void:
	$Players2Button.pressed.connect(func(): _select(2))
	$Players3Button.pressed.connect(func(): _select(3))
	$Players4Button.pressed.connect(func(): _select(4))
	$BackButton.pressed.connect(_on_back)
	$Players2Button.grab_focus()

func _select(count: int) -> void:
	GameSettings.player_count = count
	get_tree().change_scene_to_file("res://scenes/SkinSelect.tscn")

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
