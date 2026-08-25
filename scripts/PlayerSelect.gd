extends Control

## Player count, plus the race-only single-player entry point. Which mode we
## are heading into was decided on the main menu (GameSettings.mode).

func _ready() -> void:
	$Players1Button.pressed.connect(func(): _select(2, true))
	$Players2Button.pressed.connect(func(): _select(2))
	$Players3Button.pressed.connect(func(): _select(3))
	$Players4Button.pressed.connect(func(): _select(4))
	$BackButton.pressed.connect(_on_back)

	# Pile Up has no AI: BotDriver plays a PlayerBoard — it senses traffic in
	# an obstacle_container and steers between lane centres, none of which
	# exists in the tower mode. So both the solo option and the bot hints are
	# race-only until a tower bot exists (docs/PROJECT_STATE.md §9).
	var race: bool = GameSettings.mode == GameSettings.MODE_RACE
	$Players1Button.visible = race
	$Hint.visible = race
	$Title.text = "HOW MANY PLAYERS?" if race else "HOW MANY BUILDERS?"
	($Players1Button if race else $Players2Button).grab_focus()

# `solo` is the race's single-player entry point: that mode is a race between
# boards, so there has to be something to race — it is really "two boards, one
# of them driven by BotDriver". Any other slot can still be turned over to a
# bot from SkinSelect (the 1-4 keys), including all of them at once if you
# just want to watch.
func _select(count: int, solo: bool = false) -> void:
	GameSettings.player_count = count
	GameSettings.clear_bots()
	if solo and GameSettings.mode == GameSettings.MODE_RACE:
		GameSettings.set_bot(1, true)
	get_tree().change_scene_to_file("res://scenes/SkinSelect.tscn")

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
