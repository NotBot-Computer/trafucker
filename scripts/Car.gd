extends Area2D
class_name Car

## Drop your own texture on the Sprite2D child (in the editor Inspector, or via
## code with set_texture) and it will be used instead of the placeholder shape.

@export var body_color: Color = Color(0.231, 0.435, 0.878)
@export var window_color: Color = Color(0.55, 0.65, 0.7)

@onready var body: Polygon2D = $Body
@onready var windshield: Polygon2D = $Windshield
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

var width: float = 32.0
var height: float = 54.0

# Draws the texture bigger or smaller than the footprint, without touching
# the footprint. width/height are the car's real size — the hitbox, the
# steering bounds, what the bot thinks fits in a gap — and nothing here may
# move them; this only scales the Sprite2D on top of them.
#
# It exists because a skill can re-skin the player's car (SkillEffect.
# car_texture) and the replacement art is not obliged to fill its canvas the
# same way the stock art does. Make Way's cruiser is drawn 56px wide inside
# the same 78x132 canvas the sedans fill to 67px, so at 1.0 the player
# visibly shrinks the moment the skin lands — a size change nobody asked for,
# out of a costume. Scaling the sprite is the correction that leaves every
# number the round is played on exactly where it was.
var sprite_scale_mult: float = 1.0

# Turn signal: two small lamps built procedurally (no scene/art changes
# needed) so any Car — placeholder shape or real cropped-photo texture alike
# — can show a blinking indicator before a lane change. `indicator_side`
# drives a simple on/off blink in _process; PlayerBoard is responsible for
# calling start_indicator()/stop_indicator() as part of its lane-change
# state machine, this node only owns the blink animation itself.
const INDICATOR_COLOR := Color(1.0, 0.78, 0.05, 1.0)
const INDICATOR_BLINK_INTERVAL := 0.16

var indicator_left: Polygon2D
var indicator_right: Polygon2D
var indicator_side: int = 0 # -1 = left blinking, 1 = right blinking, 0 = off
var indicator_timer: float = 0.0

func set_size(w: float, h: float) -> void:
	width = w
	height = h
	_rebuild()

func set_texture(tex: Texture2D) -> void:
	sprite.texture = tex
	_rebuild()

func set_sprite_scale_mult(m: float) -> void:
	sprite_scale_mult = m
	_rebuild()

func start_indicator(side: int) -> void:
	indicator_side = side
	indicator_timer = INDICATOR_BLINK_INTERVAL
	if indicator_left:
		indicator_left.visible = (side == -1)
	if indicator_right:
		indicator_right.visible = (side == 1)

func stop_indicator() -> void:
	indicator_side = 0
	if indicator_left:
		indicator_left.visible = false
	if indicator_right:
		indicator_right.visible = false

func _ready() -> void:
	indicator_left = _make_indicator_lamp()
	indicator_right = _make_indicator_lamp()
	add_child(indicator_left)
	add_child(indicator_right)
	_position_indicators()

func _make_indicator_lamp() -> Polygon2D:
	var lamp := Polygon2D.new()
	lamp.color = INDICATOR_COLOR
	lamp.z_index = 5
	lamp.visible = false
	return lamp

func _process(delta: float) -> void:
	if indicator_side == 0:
		return
	indicator_timer -= delta
	if indicator_timer <= 0.0:
		indicator_timer = INDICATOR_BLINK_INTERVAL
		var lamp: Polygon2D = indicator_left if indicator_side == -1 else indicator_right
		lamp.visible = not lamp.visible

func _position_indicators() -> void:
	if indicator_left == null or indicator_right == null:
		return
	var light_w: float = max(4.0, width * 0.12)
	var light_h: float = max(4.0, height * 0.05)
	var shape := PackedVector2Array([
		Vector2(-light_w * 0.5, -light_h * 0.5), Vector2(light_w * 0.5, -light_h * 0.5),
		Vector2(light_w * 0.5, light_h * 0.5), Vector2(-light_w * 0.5, light_h * 0.5),
	])
	indicator_left.polygon = shape
	indicator_right.polygon = shape
	# Mounted near the front corners like a real car's turn signals, just
	# outside the body silhouette so the blink reads clearly against both
	# the placeholder shape and real cropped-photo textures alike.
	indicator_left.position = Vector2(-width * 0.56, -height * 0.32)
	indicator_right.position = Vector2(width * 0.56, -height * 0.32)

func _rebuild() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width * 0.8, height * 0.85)
	collision.shape = shape
	_position_indicators()

	if sprite.texture != null:
		body.visible = false
		windshield.visible = false
		var tex_size: Vector2 = sprite.texture.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			sprite.scale = Vector2(width / tex_size.x, height / tex_size.y) * sprite_scale_mult
		return

	body.visible = true
	windshield.visible = true
	var w := width
	var h := height
	body.polygon = PackedVector2Array([
		Vector2(-w * 0.5, -h * 0.46), Vector2(-w * 0.3, -h * 0.5), Vector2(w * 0.3, -h * 0.5),
		Vector2(w * 0.5, -h * 0.46), Vector2(w * 0.5, h * 0.46), Vector2(w * 0.3, h * 0.5),
		Vector2(-w * 0.3, h * 0.5), Vector2(-w * 0.5, h * 0.46),
	])
	body.color = body_color
	windshield.polygon = PackedVector2Array([
		Vector2(-w * 0.28, -h * 0.32), Vector2(w * 0.28, -h * 0.32),
		Vector2(w * 0.24, -h * 0.05), Vector2(-w * 0.24, -h * 0.05),
	])
	windshield.color = window_color
