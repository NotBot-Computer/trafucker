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

func set_size(w: float, h: float) -> void:
	width = w
	height = h
	_rebuild()

func set_texture(tex: Texture2D) -> void:
	sprite.texture = tex
	_rebuild()

func _rebuild() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width * 0.8, height * 0.85)
	collision.shape = shape

	if sprite.texture != null:
		body.visible = false
		windshield.visible = false
		var tex_size: Vector2 = sprite.texture.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			sprite.scale = Vector2(width / tex_size.x, height / tex_size.y)
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
