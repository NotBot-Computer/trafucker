extends Control

func _ready() -> void:
	$Players1Button.pressed.connect(func(): _select(2, true))
	$Players2Button.pressed.connect(func(): _select(2))
	$Players3Button.pressed.connect(func(): _select(3))
	$Players4Button.pressed.connect(func(): _select(4))
	$BackButton.pressed.connect(_on_back)
	$Players1Button.grab_focus()

# `solo` is the single-player entry point: the mode is a race between boards,
# so there has to be something to race — it is really "two boards, one of them
# driven by BotDriver". Any other slot can still be turned over to a bot from
# SkinSelect (the 1-4 keys), including all of them at once if you just want to watch.
func _select(count: int, solo: bool = false) -> void:
	GameSettings.player_count = count
	GameSettings.clear_bots()
	if solo:
		GameSettings.set_bot(1, true)
	get_tree().change_scene_to_file("res://scenes/SkinSelect.tscn")

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
