extends Node2D
class_name PlayerBoard

signal crashed

const CAR_SCENE := preload("res://scenes/Car.tscn")

@export var board_width: float = 360.0
@export var board_height: float = 620.0
@export var lane_count: int = 5
@export var body_color: Color = Color(0.231, 0.435, 0.878) # fallback if player_texture is null
@export var key_left: Key = KEY_A
@export var key_right: Key = KEY_D
@export var player_name: String = "P1"

var player_texture: Texture2D = null

const BASE_SPEED := 160.0
const SPEED_PER_SECOND := 6.0
const SPAWN_INTERVAL_START := 0.85
const SPAWN_INTERVAL_MIN := 0.35
const MAX_STEER_SPEED := 460.0
const STEER_RESPONSE := 9.0
const MAX_TILT := 0.32

const TAP_WINDOW := 0.28 # max gap between taps to count as back-to-back

const DASH_DURATION := 0.14
const DASH_COOLDOWN := 0.18
const DASH_TILT := 0.55
const DASH_GHOST_INTERVAL := 0.03

const REVERSAL_THRESHOLD := 140.0 # |car_vx| needed before an opposite key-press counts as a drift
const DRIFT_COOLDOWN := 0.3
const DRIFT_GRIP_MULT := 0.48 # car_vx (actual momentum) approaches target this much slower
const DRIFT_NOSE_RESPONSE := 14.0 # how fast the car's facing/tilt snaps to the input direction
const DRIFT_MAX_TILT := 0.46 # nose can point further off than normal steering, but not extreme
const SLIP_MARK_THRESHOLD := 90.0 # |target_vx - car_vx| above this counts as "sliding"
const DRIFT_MARK_INTERVAL := 0.05
const DRIFT_MARK_OFFSET := 0.22 # fraction of car width, rear-wheel track spacing

@onready var road: Road = $Road
@onready var obstacle_container: Node2D = $ObstacleContainer
@onready var player_car: Car = $PlayerCar

const PLAYER_KIND := {"width_frac": 0.62, "height_frac": 1.69}

var car_x: float
var car_vx: float = 0.0
var elapsed: float = 0.0
var distance: float = 0.0
var spawn_timer: float = 0.0
var alive: bool = true
var active: bool = false

var last_tap_time: float = -999.0
var last_tap_direction: int = 0

var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_from: float = 0.0
var dash_to: float = 0.0
var dash_direction: int = 0
var dash_cooldown_timer: float = 0.0
var dash_ghost_timer: float = 0.0

var is_drifting: bool = false
var drift_cooldown_timer: float = 0.0
var drift_mark_timer: float = 0.0
var drift_marks: Array = []

func _ready() -> void:
	road.width = board_width
	road.height = board_height
	road.lane_count = lane_count
	player_car.area_entered.connect(_on_player_area_entered)

func start_round() -> void:
	for child in obstacle_container.get_children():
		child.queue_free()

	player_car.body_color = body_color
	var sz := _car_size(PLAYER_KIND)
	player_car.set_size(sz.x, sz.y)
	if player_texture != null:
		player_car.set_texture(player_texture)
	player_car.rotation = 0.0
	player_car.modulate.a = 1.0

	car_x = board_width * 0.5
	car_vx = 0.0
	elapsed = 0.0
	distance = 0.0
	spawn_timer = spawn_interval()
	alive = true
	active = true
	last_tap_time = -999.0
	last_tap_direction = 0
	is_dashing = false
	dash_cooldown_timer = 0.0
	is_drifting = false
	drift_cooldown_timer = 0.0
	player_car.position = Vector2(car_x, board_height - sz.y * 0.5 - 24.0)
	road.distance = 0.0
	road.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not active or not alive or is_dashing:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == key_left:
		if car_vx > REVERSAL_THRESHOLD:
			_try_start_drift()
		_register_tap(-1)
	elif event.keycode == key_right:
		if car_vx < -REVERSAL_THRESHOLD:
			_try_start_drift()
		_register_tap(1)

func _register_tap(direction: int) -> void:
	# Same-direction double-tap triggers a dash. Drift is triggered
	# separately, straight off the car's actual momentum (see above).
	if direction == last_tap_direction and elapsed - last_tap_time <= TAP_WINDOW:
		_try_start_dash(direction)
		last_tap_time = -999.0
		return
	last_tap_time = elapsed
	last_tap_direction = direction

func _try_start_dash(direction: int) -> void:
	if is_dashing or is_drifting or dash_cooldown_timer > 0.0:
		return
	var sz := _car_size(PLAYER_KIND)
	var shoulder := board_width * 0.06
	var min_x := shoulder + sz.x * 0.5
	var max_x := board_width - shoulder - sz.x * 0.5
	dash_from = car_x
	dash_to = clamp(car_x + direction * road.lane_width(), min_x, max_x)
	dash_direction = direction
	dash_timer = 0.0
	dash_ghost_timer = 0.0
	is_dashing = true
	car_vx = 0.0

func _try_start_drift() -> void:
	if is_dashing or is_drifting or drift_cooldown_timer > 0.0:
		return
	is_drifting = true
	drift_mark_timer = 0.0

func _car_size(kind_cfg: Dictionary) -> Vector2:
	var lw := road.lane_width()
	var w: float = lw * kind_cfg["width_frac"]
	return Vector2(w, w * kind_cfg["height_frac"])

func current_speed() -> float:
	return BASE_SPEED + elapsed * SPEED_PER_SECOND

func spawn_interval() -> float:
	return max(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_START - elapsed * 0.015)

func _process(delta: float) -> void:
	if not active or not alive:
		return

	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta
	if drift_cooldown_timer > 0.0:
		drift_cooldown_timer -= delta

	var sz := _car_size(PLAYER_KIND)
	var tilt: float

	if is_dashing:
		dash_timer += delta
		var t: float = clamp(dash_timer / DASH_DURATION, 0.0, 1.0)
		var eased: float = 1.0 - pow(1.0 - t, 3)
		car_x = lerp(dash_from, dash_to, eased)
		tilt = DASH_TILT * dash_direction * (1.0 - t)

		dash_ghost_timer -= delta
		if dash_ghost_timer <= 0.0:
			dash_ghost_timer = DASH_GHOST_INTERVAL
			_spawn_dash_ghost()

		if t >= 1.0:
			is_dashing = false
			dash_cooldown_timer = DASH_COOLDOWN
	else:
		# Steering top speed never changes — drifting is about losing grip,
		# not going faster. Only how quickly the car's actual momentum
		# (car_vx) can catch up to the input direction changes.
		var left := Input.is_physical_key_pressed(key_left)
		var right := Input.is_physical_key_pressed(key_right)
		var target_vx := 0.0
		if left and not right:
			target_vx = -MAX_STEER_SPEED
		elif right and not left:
			target_vx = MAX_STEER_SPEED

		# Drift persists as long as you keep steering in some direction —
		# switching left/right mid-drift keeps it going. It only ends the
		# moment you let go of both keys.
		if is_drifting and target_vx == 0.0:
			is_drifting = false
			drift_cooldown_timer = DRIFT_COOLDOWN

		var grip := STEER_RESPONSE * (DRIFT_GRIP_MULT if is_drifting else 1.0)
		var approach := 1.0 - exp(-grip * delta)
		car_vx += (target_vx - car_vx) * approach

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

		if is_drifting:
			# Nose points where you're steering, well ahead of where the car
			# is actually still travelling — that gap is the slide.
			var nose_target: float = sign(target_vx) * DRIFT_MAX_TILT if target_vx != 0.0 else player_car.rotation
			tilt = move_toward(player_car.rotation, nose_target, DRIFT_NOSE_RESPONSE * delta)

			var slip: float = absf(target_vx - car_vx)
			drift_mark_timer -= delta
			if drift_mark_timer <= 0.0 and slip > SLIP_MARK_THRESHOLD:
				drift_mark_timer = DRIFT_MARK_INTERVAL
				_spawn_drift_mark(sz.x)
		else:
			tilt = clamp(car_vx / MAX_STEER_SPEED, -1.0, 1.0) * MAX_TILT

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

	var speed := current_speed()
	for mark in drift_marks:
		if is_instance_valid(mark):
			mark.position.y += speed * delta
	drift_marks = drift_marks.filter(func(m): return is_instance_valid(m))

func _spawn_dash_ghost() -> void:
	if player_car.sprite.texture == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = player_car.sprite.texture
	ghost.scale = player_car.sprite.scale
	ghost.rotation = player_car.rotation
	ghost.position = player_car.position
	ghost.modulate = Color(1.0, 1.0, 1.0, 0.4)
	ghost.z_index = -1
	add_child(ghost)
	var tw := create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, 0.22)
	tw.tween_callback(ghost.queue_free)

func _spawn_drift_mark(car_w: float) -> void:
	var sz := _car_size(PLAYER_KIND)
	var mark_size := Vector2(sz.x * 0.09, sz.y * 0.16)
	var rear_y: float = player_car.position.y + sz.y * 0.32
	for side in [-1.0, 1.0]:
		var mark := ColorRect.new()
		mark.color = Color(0.05, 0.05, 0.05, 0.4)
		mark.size = mark_size
		var mark_x: float = player_car.position.x + side * car_w * DRIFT_MARK_OFFSET
		mark.position = Vector2(mark_x, rear_y) - mark_size * 0.5
		mark.z_index = -2
		add_child(mark)
		drift_marks.append(mark)
		var tw := create_tween()
		tw.tween_property(mark, "modulate:a", 0.0, 0.5)
		tw.tween_callback(mark.queue_free)

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
	var kind_cfg := _pick_traffic_kind()
	var obstacle: Car = CAR_SCENE.instantiate()
	obstacle_container.add_child(obstacle)
	var sz := _car_size(kind_cfg)
	obstacle.set_size(sz.x, sz.y)
	var textures: Array = kind_cfg["textures"]
	obstacle.set_texture(textures[randi() % textures.size()])
	obstacle.set_meta("lane", lane)
	obstacle.position = Vector2(road.lane_center_x(lane), -sz.y - 40.0)

func _pick_traffic_kind() -> Dictionary:
	var kinds: Array = GameSettings.TRAFFIC_KINDS
	var total := 0
	for k in kinds:
		total += int(k["weight"])
	var r := randi() % total
	for k in kinds:
		r -= int(k["weight"])
		if r < 0:
			return k
	return kinds[0]

func _on_player_area_entered(_area: Area2D) -> void:
	if not alive:
		return
	alive = false
	active = false
	player_car.modulate.a = 0.35
	crashed.emit()
