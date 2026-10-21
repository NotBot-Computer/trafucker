extends Control

## A title spelled in Pile Up's bricks: each letter is one brick-shaped piece
## cut from a 5x7 grid — square and joined edge to edge, never only at a
## corner, because a cell that meets the rest only diagonally draws as a
## loose block once each letter is outlined like a brick. Drawn the way the
## bricks are (PixelUI.cells_texture), in the seven classic bricks' colours
## in turn. The letters drop in one after
## another when the screen opens and land with a small bounce.
##
## Centred horizontally in its own rect, top-aligned. Only A-Z and space;
## anything else is left out.

const PixelUI := preload("res://scripts/PixelUI.gd")

const GLYPHS := {
	"A": ["#####", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
	"B": ["#### ", "#   #", "#   #", "#####", "#   #", "#   #", "#####"],
	"C": ["#####", "#    ", "#    ", "#    ", "#    ", "#    ", "#####"],
	"D": ["#### ", "#  ##", "#   #", "#   #", "#   #", "#  ##", "#### "],
	"E": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####"],
	"F": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#    "],
	"G": ["#####", "#    ", "#    ", "#  ##", "#   #", "#   #", "#####"],
	"H": ["#   #", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
	"I": ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "#####"],
	"J": ["#####", "   # ", "   # ", "   # ", "   # ", "#  # ", "#### "],
	"K": ["#   #", "#  ##", "# ## ", "###  ", "# ## ", "#  ##", "#   #"],
	"L": ["#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####"],
	"M": ["#   #", "## ##", "#####", "# # #", "#   #", "#   #", "#   #"],
	"N": ["#   #", "##  #", "### #", "# ###", "#  ##", "#   #", "#   #"],
	"O": ["#####", "#   #", "#   #", "#   #", "#   #", "#   #", "#####"],
	"P": ["#####", "#   #", "#   #", "#####", "#    ", "#    ", "#    "],
	"Q": ["#####", "#   #", "#   #", "#   #", "# ###", "#  # ", "#####"],
	"R": ["#####", "#   #", "#   #", "#####", "#  # ", "#  ##", "#   #"],
	"S": ["#####", "#    ", "#    ", "#####", "    #", "    #", "#####"],
	"T": ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  "],
	"U": ["#   #", "#   #", "#   #", "#   #", "#   #", "#   #", "#####"],
	"V": ["#   #", "#   #", "#   #", "## ##", " # # ", " ### ", "  #  "],
	"W": ["#   #", "#   #", "#   #", "# # #", "# # #", "# # #", "#####"],
	"X": ["#   #", "## ##", " ### ", "  #  ", " ### ", "## ##", "#   #"],
	"Y": ["#   #", "## ##", " ### ", "  #  ", "  #  ", "  #  ", "  #  "],
	"Z": ["#####", "    #", "   ##", "  ## ", " ##  ", "##   ", "#####"],
}
const GLYPH_W := 5
const GLYPH_H := 7
const LETTER_GAP := 1 # cells
const SPACE_W := 3 # cells
# The classic bricks' colours, as a rainbow: S, L, O, Z, I, T, J.
const COLOR_ORDER := ["S", "L", "O", "Z", "I", "T", "J"]

const DROP_DELAY := 0.07 # between one letter starting to fall and the next
const DROP_TIME := 0.32
const BOUNCE_TIME := 0.16

@export var text := "PILE UP"
@export var cell_art := 6 # art pixels per cell; a cell is cell_art * PIX on screen
@export var animate := true

var t := 0.0
var _letters: Array[Dictionary] = [] # tex, x (cells from the left edge)
var _width_cells := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var colors: Array[Color] = []
	for id in COLOR_ORDER:
		for b: Dictionary in GameSettings.BRICKS:
			if b["name"] == id:
				colors.append(PixelUI.brick_color(b))
	var x := 0
	var n := 0
	for ch in text.to_upper():
		if ch == " ":
			x += SPACE_W - LETTER_GAP
			continue
		if not GLYPHS.has(ch):
			continue
		var occ: Array = PixelUI.cells_from_rows(PackedStringArray(GLYPHS[ch]))
		_letters.append({"tex": PixelUI.cells_texture(occ, colors[n % colors.size()], cell_art), "x": x})
		x += GLYPH_W + LETTER_GAP
		n += 1
	_width_cells = maxi(0, x - LETTER_GAP)
	custom_minimum_size.y = float(GLYPH_H * cell_art * PixelUI.PIX)
	if not animate:
		t = _end_time()

func _end_time() -> float:
	return DROP_DELAY * float(_letters.size()) + DROP_TIME + BOUNCE_TIME

func _process(delta: float) -> void:
	if t >= _end_time():
		return
	t += delta
	queue_redraw()

func _draw() -> void:
	var px: float = float(PixelUI.PIX)
	var cell: float = float(cell_art) * px
	var w: float = float(_width_cells) * cell
	var h: float = float(GLYPH_H) * cell
	var left: float = floorf((size.x - w) * 0.5 / px) * px
	# Far enough to start fully above the screen, wherever the title sits.
	var fall: float = global_position.y + h + 8.0
	for i in range(_letters.size()):
		var l: Dictionary = _letters[i]
		var lt: float = t - DROP_DELAY * float(i)
		if lt <= 0.0:
			continue
		var y := 0.0
		if lt < DROP_TIME:
			var k: float = lt / DROP_TIME
			y = -fall * (1.0 - k * k)
		elif lt < DROP_TIME + BOUNCE_TIME:
			y = -cell * 0.5 * sin((lt - DROP_TIME) / BOUNCE_TIME * PI)
		y = floorf(y / px) * px
		draw_texture_rect(l["tex"], Rect2(left + float(l["x"]) * cell, y, float(GLYPH_W) * cell, h), false)
