extends Control
class_name TowerHUD

## Pile Up's heads-up display: one card per player (colour, name, lives), the
## next brick, the controls for whoever is on the clock, and the transient
## "-1 LIFE" toast.
##
## Lives are the whole state of a Pile Up match, and on a shared tower they
## are the only thing on screen that says who is who — every landed brick
## looks the same regardless of who dropped it, by design. So this is drawn
## rather than laid out with Labels: TowerMode pushes its state into the
## fields below and calls queue_redraw(), same pattern as PlayerBoard's own
## _draw()-based bars.
##
## ## Why it lives in the side columns
##
## The playfield is inherently a tall narrow shaft — a tower is five cells
## wide — while the viewport is 1500x800. Laid out as a strip across the top
## (the first version) the HUD left roughly 600px of empty background down
## each side and also squeezed the drop zone, forcing the held brick low
## enough that a vertical I piece collided with the player cards. Moving the
## panels into the columns the tower was never going to use fixes both at
## once: the dead space carries something worth reading, and the entire top
## of the screen goes back to being drop headroom.

const COL_W := 224.0
const COL_MARGIN := 24.0

const CARD_H := 74.0
const CARD_GAP := 10.0
const CARDS_Y := 96.0
const STRIPE_W := 6.0

const PIP_R := 7.0
const PIP_GAP := 22.0

const NEXT_H := 124.0
const PANEL_PAD := 14.0

const MESSAGE_HOLD := 1.6
const MESSAGE_FADE := 0.7

# Panels are dark plates, not white washes. They sit over a bright pixel-art
# sky now (TowerBackground), and the first version's white-at-5%-alpha fills
# were invisible against it — a HUD that only exists on a dark background is
# a HUD that stops existing the moment the background changes.
const CARD_BG := Color(0.05, 0.06, 0.14, 0.62)
const CARD_BG_ACTIVE := Color(0.07, 0.08, 0.20, 0.86)
const PANEL_BG := Color(0.05, 0.06, 0.14, 0.62)
const DIM_TEXT := Color(1.0, 1.0, 1.0, 0.72)
const LABEL_TEXT := Color(1.0, 1.0, 1.0, 0.5)
const OUT_TEXT := Color(1.0, 0.45, 0.42, 0.85)
# Backing plate for the centred toast, which has no panel of its own.
const MESSAGE_BG := Color(0.05, 0.06, 0.14, 0.72)

var slots: Array[Dictionary] = [] # {name: String, color: Color, lives: int}
var max_lives: int = 3
var active_slot: int = 0
var waiting: bool = false # true between the drop and the next turn, when nobody is on the clock
# Who the baton is passing to, set alongside `waiting`. The banner used to
# read "settling..." through the whole hand-off, which is a word the player
# cannot act on and which made every gap between turns read as the game
# stopping. Naming the next player instead turns the same gap into a hand-off
# they can see coming — the tower resolving is already visible on screen and
# does not need captioning.
var next_slot: int = 0
var next_index: int = 0
var controls: String = ""

var _message: String = ""
var _message_color: Color = Color.WHITE
var _message_timer: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func show_message(text: String, color: Color) -> void:
	_message = text
	_message_color = color
	_message_timer = MESSAGE_HOLD + MESSAGE_FADE

func clear_message() -> void:
	_message = ""
	_message_timer = 0.0

func tick(delta: float) -> void:
	if _message_timer <= 0.0:
		return
	_message_timer = maxf(0.0, _message_timer - delta)
	queue_redraw()

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var right_x: float = size.x - COL_MARGIN - COL_W

	draw_rect(Rect2(COL_MARGIN - 10.0, 16.0, COL_W + 20.0, 62.0), PANEL_BG, true)
	draw_string(font, Vector2(COL_MARGIN, 44.0), "PILE UP", HORIZONTAL_ALIGNMENT_LEFT, COL_W, 26, Color(1, 1, 1, 0.95))
	draw_string(font, Vector2(COL_MARGIN, 66.0), "one tower, three lives each", HORIZONTAL_ALIGNMENT_LEFT, COL_W, 13, LABEL_TEXT)

	for i in range(slots.size()):
		_draw_card(font, i)
	_draw_next(font, right_x)
	_draw_controls(font, right_x)
	_draw_turn_banner(font)
	_draw_message(font)

func _draw_card(font: Font, i: int) -> void:
	var slot: Dictionary = slots[i]
	var color: Color = slot["color"]
	var alive: bool = slot["lives"] > 0
	var is_active: bool = (i == active_slot) and alive and not waiting

	var y: float = CARDS_Y + float(i) * (CARD_H + CARD_GAP)
	var box := Rect2(COL_MARGIN, y, COL_W, CARD_H)
	draw_rect(box, CARD_BG_ACTIVE if is_active else CARD_BG, true)
	if is_active:
		draw_rect(box, Color(color.r, color.g, color.b, 0.9), false, 2.0)
	draw_rect(
		Rect2(COL_MARGIN, y, STRIPE_W, CARD_H),
		color if alive else Color(color.r, color.g, color.b, 0.25), true
	)

	var tx: float = COL_MARGIN + STRIPE_W + PANEL_PAD
	draw_string(
		font, Vector2(tx, y + 30.0), slot["name"], HORIZONTAL_ALIGNMENT_LEFT, COL_W, 20,
		Color.WHITE if alive else OUT_TEXT
	)
	if not alive:
		draw_string(font, Vector2(tx + 48.0, y + 30.0), "OUT", HORIZONTAL_ALIGNMENT_LEFT, COL_W, 15, OUT_TEXT)

	# Lives as filled/hollow pips rather than a number — from across a couch,
	# "two left" should not need reading.
	for h in range(max_lives):
		var c := Vector2(tx + PIP_R + float(h) * PIP_GAP, y + CARD_H - 22.0)
		if h < slot["lives"]:
			draw_circle(c, PIP_R, color)
			draw_circle(c, PIP_R * 0.4, Color(1.0, 1.0, 1.0, 0.55))
		else:
			draw_arc(c, PIP_R, 0.0, TAU, 20, Color(1.0, 1.0, 1.0, 0.18), 1.5)


func _draw_next(font: Font, x: float) -> void:
	var data: Dictionary = GameSettings.TETROMINOES[next_index]
	var tex: Texture2D = data["texture"]
	var color: Color = data["color"]

	draw_rect(Rect2(x, CARDS_Y, COL_W, NEXT_H), PANEL_BG, true)
	draw_string(font, Vector2(x + PANEL_PAD, CARDS_Y + 24.0), "NEXT BRICK", HORIZONTAL_ALIGNMENT_LEFT, COL_W, 14, LABEL_TEXT)

	# Fit inside the panel without distorting it — the sprites run from 4:1 to
	# 2:3, so a single flat scale would clip half of them.
	var avail := Vector2(COL_W - PANEL_PAD * 2.0, NEXT_H - 52.0)
	var tex_size: Vector2 = tex.get_size()
	var s: float = minf(avail.x / tex_size.x, avail.y / tex_size.y)
	var draw_size: Vector2 = tex_size * s
	var at := Vector2(x + (COL_W - draw_size.x) * 0.5, CARDS_Y + 38.0 + (avail.y - draw_size.y) * 0.5)
	draw_texture_rect(tex, Rect2(at, draw_size), false, Color(1.0, 1.0, 1.0, 0.95))
	draw_rect(Rect2(x, CARDS_Y + NEXT_H - 3.0, COL_W, 3.0), Color(color.r, color.g, color.b, 0.85), true)

func _draw_controls(font: Font, x: float) -> void:
	if controls == "" or slots.is_empty():
		return
	var y: float = CARDS_Y + NEXT_H + 26.0
	draw_rect(Rect2(x, y - 24.0, COL_W, 132.0), PANEL_BG, true)
	draw_string(font, Vector2(x + PANEL_PAD, y), "YOUR KEYS", HORIZONTAL_ALIGNMENT_LEFT, COL_W, 14, LABEL_TEXT)
	# One line per action: the column is too narrow for the single-line form,
	# and this is the only place a player can look up their own bindings.
	var line: float = y + 26.0
	for part: String in controls.split("\n"):
		draw_string(font, Vector2(x + PANEL_PAD, line), part, HORIZONTAL_ALIGNMENT_LEFT, COL_W, 15, DIM_TEXT)
		line += 22.0

# Deliberately in the left column rather than across the top centre: that
# strip is the descending brick's headroom now, and a banner there collided
# with a vertical I piece.
func _draw_turn_banner(font: Font) -> void:
	if slots.is_empty():
		return
	var y: float = CARDS_Y + float(slots.size()) * (CARD_H + CARD_GAP) + 20.0
	draw_rect(Rect2(COL_MARGIN, y - 24.0, COL_W, 36.0), PANEL_BG, true)
	if waiting:
		var up: Dictionary = slots[clampi(next_slot, 0, slots.size() - 1)]
		draw_string(
			font, Vector2(COL_MARGIN + PANEL_PAD, y), "%s — GET READY" % up["name"],
			HORIZONTAL_ALIGNMENT_LEFT, COL_W, 18,
			Color(up["color"].r, up["color"].g, up["color"].b, 0.75)
		)
		return
	var slot: Dictionary = slots[active_slot]
	draw_string(
		font, Vector2(COL_MARGIN + PANEL_PAD, y), "%s — YOUR BRICK" % slot["name"],
		HORIZONTAL_ALIGNMENT_LEFT, COL_W, 20, slot["color"]
	)

func _draw_message(font: Font) -> void:
	if _message_timer <= 0.0 or _message == "":
		return
	var a: float = clampf(_message_timer / MESSAGE_FADE, 0.0, 1.0)
	var c := Color(_message_color.r, _message_color.g, _message_color.b, a)
	var y: float = size.y * 0.5 - 30.0
	draw_rect(
		Rect2(0.0, y - 34.0, size.x, 52.0),
		Color(MESSAGE_BG.r, MESSAGE_BG.g, MESSAGE_BG.b, MESSAGE_BG.a * a), true
	)
	draw_string(font, Vector2(0.0, y), _message, HORIZONTAL_ALIGNMENT_CENTER, size.x, 32, c)
