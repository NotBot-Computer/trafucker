extends Node2D

const BOARD_GAP := 48.0
const CAMERA_ZOOM := 1.15 # preferred/maximum zoom — only ever zoomed OUT from here, never in
const BOARD_SIDE_MARGIN := 24.0 # breathing room so the outermost lane isn't flush against the screen edge
const SCREEN_MASK_BASE_PX := 24.0 # always-on top/bottom vignette thickness, even with no letterboxing to hide
const PLAYER_BOARD_SCENE := preload("res://scenes/PlayerBoard.tscn")
const LANE_DIVIDER_SCENE := preload("res://scenes/LaneDivider.tscn")

@onready var camera: Camera2D = $Camera2D
@onready var boards_container: Node2D = $BoardsContainer
@onready var dividers_container: Node2D = $DividersContainer
@onready var status_label: Label = $HUD/StatusLabel
@onready var overlay: Control = $HUD/Overlay
@onready var screen_mask: ScreenMask = $HUD/ScreenMask
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
		board.key_confirm = cfg["confirm"]
		if i < GameSettings.skins.size():
			board.player_texture = GameSettings.skins[i]
		if i < GameSettings.skin_colors.size():
			board.body_color = GameSettings.skin_colors[i]
		boards_container.add_child(board)
		board.crashed.connect(_on_board_crashed)
		boards.append(board)
		board_width = board.board_width
		board_height = board.board_height

	var total_width: float = count * board_width + (count - 1) * BOARD_GAP
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size

	# At 2-3 players everything fits comfortably inside CAMERA_ZOOM's visible
	# area. At 4 players total_width can exceed it, which used to clip the
	# outermost board's edge lanes off-screen entirely. Zoom out just enough
	# to fit every board — never zoom in past CAMERA_ZOOM, only out from it.
	var fit_zoom: float = viewport_size.x / (total_width + BOARD_SIDE_MARGIN * 2.0)
	var zoom: float = min(CAMERA_ZOOM, fit_zoom)

	# Zooming out to fit width also widens the vertical slice the camera can
	# see — board_height doesn't change, only how much of the camera's view
	# falls outside it. vertical_margin is that overhang, in each board's own
	# local space; without extending the road/median draw area and the
	# obstacle spawn/despawn points to match, that overhang shows bare
	# background above/below the track (see Road.render_margin).
	var visible_height: float = viewport_size.y / zoom
	var vertical_margin: float = max(0.0, (visible_height - board_height) / 2.0)

	var start_x: float = max(0.0, (viewport_size.x - total_width) / 2.0)

	var x := start_x
	for i in range(boards.size()):
		boards[i].position.x = x
		boards[i].set_vertical_margin(vertical_margin)
		x += board_width
		if i < boards.size() - 1:
			var divider: LaneDivider = LANE_DIVIDER_SCENE.instantiate()
			divider.width = BOARD_GAP
			divider.height = board_height
			divider.render_margin = vertical_margin
			dividers_container.add_child(divider)
			divider.position = Vector2(x, 0)
			x += BOARD_GAP

	camera.position = Vector2(start_x + total_width / 2.0, board_height / 2.0)
	camera.zoom = Vector2(zoom, zoom)
	camera.make_current()

	if screen_mask:
		# Screen-space thickness: convert vertical_margin (world/board-local
		# units) through the camera zoom back to screen pixels, plus a small
		# constant so there's always a subtle fade even at 2-3 players where
		# vertical_margin is 0 (nothing to hide, just polish).
		screen_mask.set_fade_height(vertical_margin * zoom + SCREEN_MASK_BASE_PX)

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
	for d in dividers_container.get_children():
		d.reset()

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
