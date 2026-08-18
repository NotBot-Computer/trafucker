extends Node2D

const BOARD_GAP := 48.0
const CAMERA_ZOOM := 1.15
const PLAYER_BOARD_SCENE := preload("res://scenes/PlayerBoard.tscn")
const LANE_DIVIDER_SCENE := preload("res://scenes/LaneDivider.tscn")

@onready var camera: Camera2D = $Camera2D
@onready var boards_container: Node2D = $BoardsContainer
@onready var dividers_container: Node2D = $DividersContainer
@onready var status_label: Label = $HUD/StatusLabel
@onready var overlay: Control = $HUD/Overlay
@onready var overlay_title: Label = $HUD/Overlay/OverlayTitle
@onready var overlay_body: Label = $HUD/Overlay/OverlayBody

var boards: Array[PlayerBoard] = []
var state := "playing"

func _ready() -> void:
	_build_boards()
	status_label.text = _status_text()
	_start_round()

func _build_boards() -> void:
	for child in boards_container.get_children():
		child.queue_free()
	for child in dividers_container.get_children():
		child.queue_free()
	boards = []

	var count: int = GameSettings.player_count
	var board_width := 0.0
	var board_height := 0.0

	for i in range(count):
		var board: PlayerBoard = PLAYER_BOARD_SCENE.instantiate()
		var cfg: Dictionary = GameSettings.PLAYER_CONFIGS[i]
		board.player_name = cfg["name"]
		board.key_left = cfg["left"]
		board.key_right = cfg["right"]
		board.body_color = GameSettings.skins[i] if i < GameSettings.skins.size() else Color.WHITE
		boards_container.add_child(board)
		board.crashed.connect(_on_board_crashed)
		boards.append(board)
		board_width = board.board_width
		board_height = board.board_height

	var total_width: float = count * board_width + (count - 1) * BOARD_GAP
	var viewport_width: float = get_viewport().get_visible_rect().size.x
	var start_x: float = max(0.0, (viewport_width - total_width) / 2.0)

	var x := start_x
	for i in range(boards.size()):
		boards[i].position.x = x
		x += board_width
		if i < boards.size() - 1:
			var divider: Node2D = LANE_DIVIDER_SCENE.instantiate()
			divider.width = BOARD_GAP
			divider.height = board_height
			dividers_container.add_child(divider)
			divider.position = Vector2(x, 0)
			x += BOARD_GAP

	camera.position = Vector2(start_x + total_width / 2.0, board_height / 2.0)
	camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	camera.make_current()

func _status_text() -> String:
	var parts: Array[String] = []
	for i in range(boards.size()):
		var cfg: Dictionary = GameSettings.PLAYER_CONFIGS[i]
		parts.append("%s: %s" % [cfg["name"], cfg["steer_label"]])
	parts.append("ESC: menu")
	return "      ".join(parts)

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
