extends Node2D
class_name PlayerBoard

signal crashed

const CAR_SCENE := preload("res://scenes/Car.tscn")

@export var board_width: float = 360.0
@export var board_height: float = 620.0
@export var lane_count: int = 5
@export var body_color: Color = Color(0.231, 0.435, 0.878)
@export var window_color: Color = Color(0.55, 0.65, 0.7)
@export var key_left: Key = KEY_A
@export var key_right: Key = KEY_D
@export var player_name: String = "P1"

const BASE_SPEED := 160.0
const SPEED_PER_SECOND := 6.0
const SPAWN_INTERVAL_START := 0.85
const SPAWN_INTERVAL_MIN := 0.35
const MAX_STEER_SPEED := 460.0
const STEER_RESPONSE := 9.0
const MAX_TILT := 0.32

const SEDAN_COLORS := [
	Color(0.914, 0.914, 0.914), Color(0.169, 0.169, 0.169), Color(0.780, 0.800, 0.820),
	Color(0.365, 0.427, 0.494), Color(0.788, 0.651, 0.420), Color(0.478, 0.180, 0.180),
]
const TRUCK_COLORS := [
	Color(0.933, 0.933, 0.933), Color(0.847, 0.827, 0.769), Color(0.812, 0.839, 0.863),
]

@onready var road: Road = $Road
@onready var obstacle_container: Node2D = $ObstacleContainer
@onready var player_car: Car = $PlayerCar

var car_x: float
var car_vx: float = 0.0
var elapsed: float = 0.0
var distance: float = 0.0
var spawn_timer: float = 0.0
var alive: bool = true
var active: bool = false

func _ready() -> void:
	road.width = board_width
	road.height = board_height
	road.lane_count = lane_count
	player_car.area_entered.connect(_on_player_area_entered)

func start_round() -> void:
	for child in obstacle_container.get_children():
		child.queue_free()

	player_car.body_color = body_color
	player_car.window_color = window_color
	var sz := _car_size(false)
	player_car.set_size(sz.x, sz.y)
	player_car.rotation = 0.0
	player_car.modulate.a = 1.0

	car_x = board_width * 0.5
	car_vx = 0.0
	elapsed = 0.0
	distance = 0.0
	spawn_timer = spawn_interval()
	alive = true
	active = true
	player_car.position = Vector2(car_x, board_height - sz.y * 0.5 - 24.0)
	road.distance = 0.0
	road.queue_redraw()

func _car_size(is_truck: bool) -> Vector2:
	var lw := road.lane_width()
	if is_truck:
		var w := lw * 0.56
		return Vector2(w, w * 2.6)
	var w := lw * 0.62
	return Vector2(w, w * 1.7)

func current_speed() -> float:
	return BASE_SPEED + elapsed * SPEED_PER_SECOND

func spawn_interval() -> float:
	return max(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_START - elapsed * 0.015)

func _process(delta: float) -> void:
	if not active or not alive:
		return

	var left := Input.is_physical_key_pressed(key_left)
	var right := Input.is_physical_key_pressed(key_right)
	var target_vx := 0.0
	if left and not right:
		target_vx = -MAX_STEER_SPEED
	elif right and not left:
		target_vx = MAX_STEER_SPEED
	var approach := 1.0 - exp(-STEER_RESPONSE * delta)
	car_vx += (target_vx - car_vx) * approach

	var sz := _car_size(false)
	var shoulder := board_width * 0.06
	var min_x := shoulder + sz.x * 0.5
	var max_x := board_width - shoulder - sz.x * 0.5
	var next_x := car_x + car_vx * delta
	if next_x < min_x:
		car_x = min_x
		car_vx = 0.0
	elif next_x > max_x:
		car_x = max_x
		car_vx = 0.0
	else:
		car_x = next_x

	var tilt: float = clamp(car_vx / MAX_STEER_SPEED, -1.0, 1.0) * MAX_TILT
	player_car.rotation = tilt
	player_car.position = Vector2(car_x, board_height - sz.y * 0.5 - 24.0)

	elapsed += delta
	distance += current_speed() * delta
	road.distance = distance
	road.queue_redraw()

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = spawn_interval()
		_spawn_obstacle()

	for child in obstacle_container.get_children():
		child.position.y += current_speed() * delta
		if child.position.y > board_height + 140.0:
			child.queue_free()

func _spawn_obstacle() -> void:
	var used_lanes: Array = []
	for child in obstacle_container.get_children():
		if child.position.y < 190.0:
			used_lanes.append(child.get_meta("lane"))
	var available: Array = []
	for lane in range(lane_count):
		if not used_lanes.has(lane):
			available.append(lane)
	if available.is_empty():
		return

	var lane: int = available[randi() % available.size()]
	var is_truck := randf() < 0.25
	var obstacle: Car = CAR_SCENE.instantiate()
	obstacle_container.add_child(obstacle)
	obstacle.body_color = _random_color(is_truck)
	obstacle.window_color = Color(0.55, 0.65, 0.7)
	var sz := _car_size(is_truck)
	obstacle.set_size(sz.x, sz.y)
	obstacle.set_meta("lane", lane)
	obstacle.position = Vector2(road.lane_center_x(lane), -sz.y - 40.0)

func _random_color(is_truck: bool) -> Color:
	if is_truck:
		return TRUCK_COLORS[randi() % TRUCK_COLORS.size()]
	return SEDAN_COLORS[randi() % SEDAN_COLORS.size()]

func _on_player_area_entered(_area: Area2D) -> void:
	if not alive:
		return
	alive = false
	active = false
	player_car.modulate.a = 0.35
	crashed.emit()
