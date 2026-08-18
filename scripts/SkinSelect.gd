extends Control

const SKIN_NAMES := ["Blue", "Red", "Green", "Yellow", "Purple", "Orange"]

var index1 := 0
var index2 := 1
var ready1 := false
var ready2 := false

@onready var swatch1: ColorRect = $P1Panel/Swatch
@onready var swatch2: ColorRect = $P2Panel/Swatch
@onready var name1: Label = $P1Panel/NameLabel
@onready var name2: Label = $P2Panel/NameLabel
@onready var status1: Label = $P1Panel/StatusLabel
@onready var status2: Label = $P2Panel/StatusLabel
@onready var hint: Label = $Hint

func _ready() -> void:
	index2 = min(1, GameSettings.default_skins.size() - 1)
	_refresh()

func _cycle(current: int, other: int, delta: int) -> int:
	var count := GameSettings.default_skins.size()
	var next := (current + delta + count) % count
	if next == other:
		next = (next + delta + count) % count
	return next

func _refresh() -> void:
	swatch1.color = GameSettings.default_skins[index1]
	swatch2.color = GameSettings.default_skins[index2]
	name1.text = SKIN_NAMES[index1]
	name2.text = SKIN_NAMES[index2]
	status1.text = "READY!" if ready1 else "A / D to change, W to lock in"
	status2.text = "READY!" if ready2 else "Left / Right to change, Up to lock in"
	hint.text = "Starting..." if (ready1 and ready2) else "Choose your car color"

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = event.keycode

	if not ready1:
		if key == KEY_A:
			index1 = _cycle(index1, index2, -1)
		elif key == KEY_D:
			index1 = _cycle(index1, index2, 1)
		elif key == KEY_W:
			ready1 = true

	if not ready2:
		if key == KEY_LEFT:
			index2 = _cycle(index2, index1, -1)
		elif key == KEY_RIGHT:
			index2 = _cycle(index2, index1, 1)
		elif key == KEY_UP:
			ready2 = true

	_refresh()

	if ready1 and ready2:
		GameSettings.skins = [GameSettings.default_skins[index1], GameSettings.default_skins[index2]]
		await get_tree().create_timer(0.4).timeout
		get_tree().change_scene_to_file("res://scenes/Main.tscn")
