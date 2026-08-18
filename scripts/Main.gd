extends Node2D

const BOARD_GAP := 8.0

@onready var board1: PlayerBoard = $BoardsContainer/PlayerBoard1
@onready var board2: PlayerBoard = $BoardsContainer/PlayerBoard2
@onready var status_label: Label = $HUD/StatusLabel
@onready var overlay: Control = $HUD/Overlay
@onready var overlay_title: Label = $HUD/Overlay/OverlayTitle
@onready var overlay_body: Label = $HUD/Overlay/OverlayBody

var boards: Array[PlayerBoard] = []
var state := "playing"

func _ready() -> void:
	var skins := GameSettings.skins

	board1.player_name = "P1"
	board1.key_left = KEY_A
	board1.key_right = KEY_D
	board1.body_color = skins[0] if skins.size() > 0 else Color(0.231, 0.435, 0.878)

	board2.position.x = board1.board_width + BOARD_GAP
	board2.player_name = "P2"
	board2.key_left = KEY_LEFT
	board2.key_right = KEY_RIGHT
	board2.body_color = skins[1] if skins.size() > 1 else Color(0.878, 0.278, 0.231)

	boards = [board1, board2]
	for b in boards:
		b.crashed.connect(_on_board_crashed)

	status_label.text = "P1: A / D      P2: Left / Right      ESC: menu"
	_start_round()

func _start_round() -> void:
	state = "playing"
	overlay.visible = false
	for b in boards:
		b.start_round()

func _on_board_crashed() -> void:
	for b in boards:
		if b.alive:
			return
	_end_round()

func _end_round() -> void:
	state = "gameover"
	var winner: PlayerBoard = boards[0]
	var lines := ""
	for b in boards:
		if b.distance > winner.distance:
			winner = b
		lines += "%s: %dm in %.1fs\n" % [b.player_name, int(b.distance), b.elapsed]
	overlay_title.text = "%s WINS" % winner.player_name
	overlay_body.text = lines.strip_edges()
	overlay.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		return
	if state != "gameover":
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		_start_round()
