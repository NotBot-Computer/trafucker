extends Control

## Player count, plus the race-only single-player entry point. Which mode we
## are heading into was decided on the main menu (GameSettings.mode), and for
## Pile Up which variant on TowerVariantSelect (GameSettings.tower_variant).

func _ready() -> void:
	$Players1Button.pressed.connect(func(): _select(1 if _tower() else 2, not _tower()))
	$Players2Button.pressed.connect(func(): _select(2))
	$Players3Button.pressed.connect(func(): _select(3))
	$Players4Button.pressed.connect(func(): _select(4))
	$BackButton.pressed.connect(_on_back)

	# Pile Up has no AI: BotDriver plays a PlayerBoard — it senses traffic in
	# an obstacle_container and steers between lane centres, none of which
	# exists in the tower mode. So the bot hints are race-only until a tower
	# bot exists (docs/PROJECT_STATE.md §9). The one-player button is reused
	# by the tower for something else entirely: co-op is the only variant with
	# no opponent, so it is the only one a person can play alone.
	if not _tower():
		$Players1Button.visible = true
		$Hint.visible = true
		$Title.text = "HOW MANY PLAYERS?"
		$Players1Button.grab_focus()
		return

	var info: Dictionary = GameSettings.tower_pick_info()
	var counts: Array = info["counts"]
	var buttons: Array[Button] = [$Players1Button, $Players2Button, $Players3Button, $Players4Button]
	$Players1Button.text = "1 BUILDER"
	for i in range(buttons.size()):
		buttons[i].visible = counts.has(i + 1)
	$Title.text = "%s — HOW MANY BUILDERS?" % info["title"]
	$Hint.visible = true
	$Hint.text = _cup_hint() if GameSettings.tower_cup != GameSettings.TOWER_CUP_NONE else _seating_hint(GameSettings.tower_variant)
	for b in buttons:
		if b.visible:
			b.grab_focus()
			break

func _tower() -> bool:
	return GameSettings.mode == GameSettings.MODE_TOWER

# Teams are seats (GameSettings.tower_team_of), so the count screen is where a
# group finds out who they are playing with — before they pick colours.
func _seating_hint(variant: int) -> String:
	match variant:
		GameSettings.TOWER_TEAMS:
			return "Left team: P1 + P3      Right team: P2 + P4  (with three, P2 holds the right alone)"
		GameSettings.TOWER_COPILOT:
			return "Left crew: P1 + P3      Right crew: P2 + P4 — you swap steering and turning every brick"
		GameSettings.TOWER_COOP:
			return "Everyone builds one tower together, sharing one pool of lives"
		GameSettings.TOWER_RACE:
			return "Left tower: P1 (+ P3)      Right tower: P2 (+ P4)"
		GameSettings.TOWER_RACE_SOLO:
			return "A tower each, side by side, in seat order — and a hex always lands on whoever is highest"
	return "Every builder for themselves"

# A cup is several variants, so the line says what it is made of instead of
# how one of them is seated — and, in the team cup, the seats, which do not
# change between its rounds.
func _cup_hint() -> String:
	if GameSettings.tower_cup == GameSettings.TOWER_CUP_TEAM:
		return "Left team: P1 + P3      Right team: P2 + P4 — winning a round is 3 trophies, losing it none, first to %d" % GameSettings.CUP_TARGET
	return "Free for all, then a race, and round again — 1st 3 trophies, 2nd 2, 3rd 1, first to %d" % GameSettings.CUP_TARGET

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
	if _tower():
		get_tree().change_scene_to_file("res://scenes/TowerVariantSelect.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
