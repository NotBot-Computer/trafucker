extends Control

## One card of a keyboard-picked row (CardRow): a framed panel, taller than
## it is wide, with a live preview filling it and a name underneath —
## nothing else, at the user's request. The row owns the selection and sets
## `selected`; this only draws.
##
## The selected card is ringed in yellow and its preview runs. The others
## hold still and dim, so what Enter will start is never in doubt.
##
## Previews, all made of the game's own art:
##   TOWER  one BrickRain at full strength: one tower (the solo cup).
##   TOWERS `count` BrickRains side by side: two towers for the team cup;
##          with `one_at_a_time`, a brick per strip — one per player on the
##          player-count screen — each strip standing on a floor in that
##          seat's default colour.
##
## In TOWERS every strip is its own well: a dark floor inside a
## thin pixel ring (PixelUI.well), with the card's face showing between
## strips. A thin black line between them did not read as separate boards.
## On the player count each ring is in its seat's colour.
##
## Set every export before adding the card: the preview is built in _ready()
## from the card's size. Never takes the mouse.

const PixelUI := preload("res://scripts/PixelUI.gd")
const BrickRain := preload("res://scripts/BrickRain.gd")

enum Kind { TOWER, TOWERS }

const INSET := 18.0 # frame to preview
const NAME_BAND := 66.0 # under the preview, for the name
const TITLE_SIZE := 24
const DIM := Color(0.5, 0.52, 0.6, 1.0)
const SPLIT := 9.0 # the card's face between two strips
const WELL_BG := Color(0.055, 0.06, 0.13, 1.0)
const FLOOR_H := 6.0

@export var kind: Kind = Kind.TOWER
@export var title := ""
@export var count := 1
@export var one_at_a_time := false

var selected := false:
	set(v):
		selected = v
		_apply_selected()

var _font: Font
var _frame: StyleBox
var _frame_hot: StyleBox
var _preview: Control
var _rains: Array[Control] = []
var _wells: Array[StyleBox] = [] # one ring per strip
var t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_font = PixelUI.font()
	_frame = PixelUI.panel_frame()
	_frame_hot = PixelUI.panel_frame(PixelUI.HOT)

	_preview = Control.new()
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.clip_contents = true
	_preview.position = Vector2(INSET, INSET)
	_preview.size = Vector2(size.x - INSET * 2.0, size.y - INSET - NAME_BAND)
	add_child(_preview)

	if kind == Kind.TOWERS:
		for i in range(count):
			_wells.append(PixelUI.well(_seat_color(i) if one_at_a_time else Color(0, 0, 0, 0)))
		_build_towers()
	else:
		_add_rain(Rect2(Vector2.ZERO, _preview.size), 10, 6)
	_apply_selected()

func _apply_selected() -> void:
	if _preview == null:
		return
	_preview.modulate = Color.WHITE if selected else DIM
	for r in _rains:
		r.set_process(selected)
	queue_redraw()

func _process(delta: float) -> void:
	if not selected:
		return
	t += delta

func _draw() -> void:
	draw_style_box(_frame_hot if selected else _frame, Rect2(Vector2.ZERO, size))
	# The name centred in the band under the preview, at 24 if it fits and 16
	# if not.
	var fs: int = TITLE_SIZE
	if _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - INSET * 2.0:
		fs = 16
	var y: float = size.y - NAME_BAND * 0.5 + float(fs) * 0.25
	var tc: Color = PixelUI.HOT if selected else PixelUI.TEXT
	var off: float = 3.0 if fs > 16 else 2.0
	draw_string(_font, Vector2(off, y + off), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, PixelUI.SHADOW)
	draw_string(_font, Vector2(0.0, y), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, tc)

# --- Towers ---------------------------------------------------------------------

func _add_rain(r: Rect2, cell_art: int, max_rows: int) -> Control:
	var rain: Control = BrickRain.new()
	rain.cell_art = cell_art
	rain.max_rows = max_rows
	rain.prewarm_rows = int(max_rows * 0.5)
	rain.fall_alpha = 1.0
	rain.pile_alpha = 1.0
	rain.position = r.position
	rain.size = r.size
	_preview.add_child(rain)
	_rains.append(rain)
	return rain

# Inside a strip's ring.
func _inner(s: Rect2) -> Rect2:
	return s.grow(-float(PixelUI.WELL))

func _draw_wells_bg() -> void:
	for s in _strips():
		_preview.draw_rect(_inner(s), WELL_BG, true)

func _draw_wells(on: CanvasItem) -> void:
	var strips: Array[Rect2] = _strips()
	for i in range(strips.size()):
		on.draw_style_box(_wells[i], strips[i])

# The strips, left to right, with SPLIT between them.
func _strips() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var w: float = (_preview.size.x - SPLIT * float(count - 1)) / float(count)
	for i in range(count):
		out.append(Rect2(floorf(float(i) * (w + SPLIT)), 0.0, floorf(w), _preview.size.y))
	return out

func _build_towers() -> void:
	_preview.draw.connect(_draw_wells_bg)
	var strips: Array[Rect2] = _strips()
	var floor_h: float = FLOOR_H if one_at_a_time else 0.0
	for i in range(strips.size()):
		var s: Rect2 = _inner(strips[i])
		# At least three cells across a strip, so most bricks fit it standing
		# some way up; and no bigger than the main menu's.
		var cell_art: int = clampi(int(s.size.x / 3.0 / float(PixelUI.PIX)), 4, 10)
		var cell: float = float(cell_art * PixelUI.PIX)
		var rows: int = maxi(3, int((s.size.y - floor_h) / cell * 0.4))
		var rain: Control = _add_rain(Rect2(s.position, Vector2(s.size.x, s.size.y - floor_h)), cell_art, rows)
		if one_at_a_time:
			rain.max_falling = 1
			rain.fall_speed = 2.2
		if floor_h > 0.0:
			var fl := ColorRect.new()
			fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fl.color = _seat_color(i)
			fl.position = Vector2(s.position.x, s.end.y - floor_h)
			fl.size = Vector2(s.size.x, floor_h)
			_preview.add_child(fl)
	# The rings go over the bricks, so a brick at a strip's edge tucks under
	# its ring rather than drawing over it.
	var rings := Control.new()
	rings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rings.size = _preview.size
	rings.draw.connect(func(): _draw_wells(rings))
	_preview.add_child(rings)

# Seat i's colour before anyone has picked one: the colour SkinSelect starts
# them on.
func _seat_color(i: int) -> Color:
	return GameSettings.PLAYER_SKINS[i % GameSettings.PLAYER_SKINS.size()]["color"]
