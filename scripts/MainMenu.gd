extends Control

## Mode picker. GameSettings.mode is set here and then read by PlayerSelect
## (which hides the race-only single-player option) and by SkinSelect (which
## decides which scene to hand off to). Nothing downstream re-derives it.

func _ready() -> void:
	$RaceButton.pressed.connect(func(): _play(GameSettings.MODE_RACE))
	$TowerButton.pressed.connect(func(): _play(GameSettings.MODE_TOWER))
	$RaceButton.grab_focus()

func _play(mode: int) -> void:
	GameSettings.mode = mode
	get_tree().change_scene_to_file("res://scenes/PlayerSelect.tscn")
