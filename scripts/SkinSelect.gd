extends Control

@onready var panels_row: HBoxContainer = $PanelsRow
@onready var hint: Label = $Hint

var indices: Array[int] = []
var ready_flags: Array[bool] = []
var panel_refs: Array[Dictionary] = []

func _ready() -> void:
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

func _refresh() -> void:
	var all_ready := true
	for i in range(panel_refs.size()):
		var ref: Dictionary = panel_refs[i]
		var skin: Dictionary = GameSettings.PLAYER_SKINS[indices[i]]
		ref["swatch"].texture = skin["texture"]
		ref["name_label"].text = skin["name"]
		var cfg: Dictionary = ref["cfg"]
		if ready_flags[i]:
			ref["status_label"].text = "READY!"
		else:
			ref["status_label"].text = "%s to change, %s to lock in" % [cfg["steer_label"], cfg["confirm_label"]]
			all_ready = false
	hint.text = "Starting..." if all_ready else "Choose your car color"

	if all_ready:
		var chosen: Array[Texture2D] = []
		var chosen_colors: Array[Color] = []
		for idx in indices:
			chosen.append(GameSettings.PLAYER_SKINS[idx]["texture"])
			chosen_colors.append(GameSettings.PLAYER_SKINS[idx]["color"])
		GameSettings.skins = chosen
		GameSettings.skin_colors = chosen_colors
		await get_tree().create_timer(0.4).timeout
		get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = event.keycode
	var changed := false

	for i in range(panel_refs.size()):
		if ready_flags[i]:
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
