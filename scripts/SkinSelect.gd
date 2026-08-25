extends Control

@onready var panels_row: HBoxContainer = $PanelsRow
@onready var hint: Label = $Hint

var indices: Array[int] = []
var ready_flags: Array[bool] = []
var panel_refs: Array[Dictionary] = []
# Latched the moment every slot is ready, because _refresh() waits a beat
# before changing scene and any further keypress in that window would call it
# again — which with bot slots (which are ready the instant they are toggled)
# is far easier to hit than it used to be.
var starting: bool = false
# Pile Up has no BotDriver equivalent, so this screen drops the bot hotkeys
# and hints there rather than offering a toggle that would do nothing. It is
# still in the flow for both modes because both need a colour per player —
# in the tower it identifies whose brick is in the air and whose lives are
# whose, since every brick already on the pile looks the same.
var race: bool = true

func _ready() -> void:
	race = GameSettings.mode == GameSettings.MODE_RACE
	var count: int = GameSettings.player_count
	indices.resize(count)
	ready_flags.resize(count)
	for i in range(count):
		indices[i] = i % GameSettings.PLAYER_SKINS.size()
		ready_flags[i] = false
	_build_panels()
	_refresh()

func _build_panels() -> void:
	for child in panels_row.get_children():
		child.queue_free()
	panel_refs.clear()

	for i in range(GameSettings.player_count):
		var cfg: Dictionary = GameSettings.PLAYER_CONFIGS[i]

		var panel := VBoxContainer.new()
		panel.custom_minimum_size = Vector2(220, 0)
		panel.add_theme_constant_override("separation", 12)
		panels_row.add_child(panel)

		var name_label := Label.new()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 20)
		panel.add_child(name_label)

		var swatch_wrap := CenterContainer.new()
		panel.add_child(swatch_wrap)
		var swatch := TextureRect.new()
		swatch.custom_minimum_size = Vector2(100, 175)
		swatch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		swatch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		swatch_wrap.add_child(swatch)

		var status_label := Label.new()
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		status_label.custom_minimum_size = Vector2(220, 50)
		panel.add_child(status_label)

		panel_refs.append({
			"cfg": cfg,
			"name_label": name_label,
			"swatch": swatch,
			"status_label": status_label,
		})

func _cycle(current: int, taken: Array[int], delta: int) -> int:
	var count := GameSettings.PLAYER_SKINS.size()
	var next := current
	for _n in range(count):
		next = (next + delta + count) % count
		if not taken.has(next):
			break
	return next

# A bot slot needs nobody to lock it in — it is ready the moment it is
# switched on, keeping whatever colour it was already showing. That is what
# makes the single-player path (and an all-bot round) start on its own.
func _is_ready(slot: int) -> bool:
	return (race and GameSettings.bot_flags[slot]) or ready_flags[slot]

func _refresh() -> void:
	var all_ready := true
	for i in range(panel_refs.size()):
		var ref: Dictionary = panel_refs[i]
		var skin: Dictionary = GameSettings.PLAYER_SKINS[indices[i]]
		ref["swatch"].texture = skin["texture"]
		ref["name_label"].text = skin["name"]
		var cfg: Dictionary = ref["cfg"]
		if race and GameSettings.bot_flags[i]:
			ref["status_label"].text = "BOT (%s)\n%s to take back" % [
				BotDriver.DIFFICULTY_NAMES[GameSettings.bot_difficulty],
				OS.get_keycode_string(GameSettings.BOT_TOGGLE_KEYS[i]),
			]
		elif ready_flags[i]:
			ref["status_label"].text = "READY!"
		else:
			ref["status_label"].text = "%s to change, %s to lock in" % [cfg["steer_label"], cfg["confirm_label"]]
			all_ready = false
	if all_ready:
		hint.text = "Starting..."
	elif race:
		hint.text = "Choose your car color      1-4: bot      5: difficulty"
	else:
		hint.text = "Choose your color — it marks your brick and your lives"

	if all_ready and not starting:
		starting = true
		var chosen: Array[Texture2D] = []
		var chosen_colors: Array[Color] = []
		for idx in indices:
			chosen.append(GameSettings.PLAYER_SKINS[idx]["texture"])
			chosen_colors.append(GameSettings.PLAYER_SKINS[idx]["color"])
		GameSettings.skins = chosen
		GameSettings.skin_colors = chosen_colors
		await get_tree().create_timer(0.4).timeout
		get_tree().change_scene_to_file(
			"res://scenes/Main.tscn" if race else "res://scenes/TowerMode.tscn"
		)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if starting:
		return
	var key: int = event.keycode
	var changed := false

	# Same 1-4 / 5 hotkeys as mid-round (see GameSettings.BOT_TOGGLE_KEYS),
	# so "make P2 a bot" is one key in the same place whether you decide it
	# here or twenty seconds into the race.
	var slot: int = GameSettings.BOT_TOGGLE_KEYS.find(key) if race else -1
	if slot != -1 and slot < panel_refs.size():
		GameSettings.set_bot(slot, not GameSettings.bot_flags[slot])
		_refresh()
		return
	if race and key == GameSettings.BOT_DIFFICULTY_KEY:
		GameSettings.bot_difficulty = BotDriver.next_difficulty(GameSettings.bot_difficulty)
		_refresh()
		return

	for i in range(panel_refs.size()):
		if _is_ready(i):
			continue
		var cfg: Dictionary = panel_refs[i]["cfg"]
		var taken: Array[int] = []
		for j in range(indices.size()):
			if j != i:
				taken.append(indices[j])

		if key == cfg["left"]:
			indices[i] = _cycle(indices[i], taken, -1)
			changed = true
		elif key == cfg["right"]:
			indices[i] = _cycle(indices[i], taken, 1)
			changed = true
		elif key == cfg["confirm"]:
			ready_flags[i] = true
			changed = true

	if changed:
		_refresh()
