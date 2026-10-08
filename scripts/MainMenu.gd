extends Control

## Mode picker. GameSettings.mode is set here and then read by PlayerSelect
## (which hides the race-only single-player option) and by SkinSelect (which
## decides which scene to hand off to). Nothing downstream re-derives it.
## Pile Up goes through one more screen first — TowerVariantSelect, which
## picks free-for-all, teams, co-pilot, co-op or the race.

func _ready() -> void:
	$RaceButton.pressed.connect(func(): _play(GameSettings.MODE_RACE))
	$TowerButton.pressed.connect(func(): _play(GameSettings.MODE_TOWER))
	$RaceButton.grab_focus()

func _play(mode: int) -> void:
	GameSettings.mode = mode
	if mode == GameSettings.MODE_TOWER:
		get_tree().change_scene_to_file("res://scenes/TowerVariantSelect.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/PlayerSelect.tscn")
