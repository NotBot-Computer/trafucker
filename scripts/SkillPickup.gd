extends Area2D
class_name SkillPickup

## Glowing collectible that scrolls down the road like a fixed road marking
## (PlayerBoard gives it speed_mult = 1.0, not a vehicle's own pace). Purely
## visual/collision — it doesn't know what skill it grants; PlayerBoard
## decides that after collection. All procedural (concentric circles +
## a rotating sparkle), no texture/art asset, matching Car.gd's placeholder
## shape and the flame/trail effects elsewhere in this codebase.

const GLOW_COLOR := Color(1.0, 0.87, 0.35)
const PULSE_SPEED := 3.2 # radians/sec fed into sin() for the breathing glow
const SPIN_SPEED := 1.4 # radians/sec, rotates the sparkle glyph

var radius: float = 22.0
# Randomized so multiple pickups on screen don't all pulse in lockstep.
var _pulse_t: float = randf() * TAU

@onready var collision: CollisionShape2D = $CollisionShape2D

func set_radius(r: float) -> void:
	radius = r
	var shape := CircleShape2D.new()
	shape.radius = r
	collision.shape = shape
	queue_redraw()

func _process(delta: float) -> void:
	_pulse_t += delta * PULSE_SPEED
	rotation += delta * SPIN_SPEED
	queue_redraw()

func _draw() -> void:
	var pulse: float = 0.85 + 0.15 * sin(_pulse_t)
	draw_circle(Vector2.ZERO, radius * 1.9 * pulse, Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.08))
	draw_circle(Vector2.ZERO, radius * 1.4 * pulse, Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.16))
	draw_circle(Vector2.ZERO, radius * pulse, Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.9))
	draw_circle(Vector2.ZERO, radius * 0.55, Color(1.0, 1.0, 1.0, 0.95))

	# Four-pointed sparkle glyph, rotates for free via the node's own
	# `rotation` (set in _process) rather than transforming points by hand.
	var pts := PackedVector2Array([
		Vector2(0, -radius * 0.5), Vector2(radius * 0.13, -radius * 0.13),
		Vector2(radius * 0.5, 0), Vector2(radius * 0.13, radius * 0.13),
		Vector2(0, radius * 0.5), Vector2(-radius * 0.13, radius * 0.13),
		Vector2(-radius * 0.5, 0), Vector2(-radius * 0.13, -radius * 0.13),
	])
	draw_colored_polygon(pts, Color(1.0, 0.95, 0.7, 0.95))
