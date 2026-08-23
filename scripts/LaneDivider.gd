extends Node2D
class_name LaneDivider

## A grass-and-trees median (same source art as the road), used to separate
## one player's road from the next so the boards read as clearly distinct
## lanes.
##
## It does not scroll itself — it *follows* a neighbouring board's odometer.
## That is the whole design, and it is worth stating plainly because the
## obvious alternative has now failed twice: this used to keep its own
## `elapsed` timer and integrate `SpeedRamp.speed_at(elapsed)` every frame,
## the theory being that running the same ramp from the same start time is
## the same thing as being in sync. It is not, for two reasons that no amount
## of keeping the constants equal can fix:
##
##   1. **Boost and tank recoil.** `PlayerBoard.current_speed()` multiplies
##      the ramp by per-board state the ramp knows nothing about, so the road
##      surges and the median doesn't. The offset is *permanent* — distance
##      gained during a boost is never given back — so a single boost slides
##      the trees against the road for the rest of the round. Measured at
##      -1.69 median tiles after one boost.
##   2. **A crashed or inactive board.** `PlayerBoard._process` early-returns
##      when `not active or not alive`, freezing its road. Nothing froze the
##      median, so it scrolled on beside a dead board forever, drift growing
##      every second without bound. This is the one that reads as the game
##      having glitched rather than merely looking off.
##
## Following an odometer makes both impossible by construction rather than by
## agreement: there is only one number now, and the median is downstream of
## it.
##
## The unavoidable residue: one strip of scenery sits between two boards that
## can legitimately scroll at different rates (one player boosting, the
## other not), and it cannot match both. It matches `neighbors[0]` — its left
## board — and falls back to the right one only when the left has stopped
## scrolling, so it is always locked to *some* live road rather than to none.

@export var width: float = 48.0
@export var height: float = 620.0
# Same purpose as Road.render_margin — extends tile coverage past [0, height]
# so the median doesn't show bare background in the letterboxed strip that
# appears when Main zooms the camera out to fit more players. Set directly
# by Main._build_boards() (dividers have no PlayerBoard wrapper to go through).
@export var render_margin: float = 0.0

const MEDIAN_TEXTURE := preload("res://sprites/road/median_tile.png")

# The boards flanking this median, left first. Set by Main._build_boards().
# Order is the preference order: the first one still scrolling wins.
var neighbors: Array = []

var distance: float = 0.0

# Which board we are currently following, and its odometer reading as of last
# frame. We integrate the *delta* rather than copying `distance` outright so
# that switching sources (the left board crashes mid-round) carries no jump —
# copying would teleport the trees by the whole difference between the two
# boards' odometers, which after a boost is over a tile.
var _source: Node = null
var _source_distance: float = 0.0

func _ready() -> void:
	# Dividers must sample boards *after* the boards have advanced this frame,
	# and DividersContainer sits above BoardsContainer in Main.tscn, so tree
	# order alone would leave the median reading a one-frame-stale odometer.
	# Higher priority = processed later in Godot.
	process_priority = 10

# Main._start_round() resets every board before it resets the dividers, so the
# odometer we prime from here is already back at 0. Priming rather than
# nulling matters: a null source makes the first frame establish its baseline
# from an odometer that has *already* advanced once, which silently drops one
# frame of distance (measured: 2.7px) and leaves the median permanently that
# far out of phase with the road for the whole round.
func reset() -> void:
	distance = 0.0
	_source = _scrolling_neighbor()
	_source_distance = _source.distance if _source != null else 0.0
	queue_redraw()

func _process(_delta: float) -> void:
	var src := _scrolling_neighbor()
	if src == null:
		return # every neighbour is crashed or inactive; the road beside us is frozen, so we are too
	if src != _source:
		_source = src
		_source_distance = src.distance
	var step: float = src.distance - _source_distance
	_source_distance = src.distance
	if is_zero_approx(step):
		return
	distance += step
	queue_redraw()

# The first flanking board whose road is actually moving. `active`/`alive` are
# exactly the two flags PlayerBoard._process early-returns on, so this is a
# direct read of "is that road scrolling right now", not a guess at it.
func _scrolling_neighbor() -> Node:
	for b in neighbors:
		if is_instance_valid(b) and b.active and b.alive:
			return b
	return null

func _draw() -> void:
	var scale_factor := width / MEDIAN_TEXTURE.get_width()
	var tile_h := MEDIAN_TEXTURE.get_height() * scale_factor
	var scroll := fmod(distance, tile_h)

	# Same anchoring as Road._draw(): slide toward +y (down, toward the
	# player) so the median matches the direction traffic moves in. See
	# Road._draw() for why the bounds are extended by render_margin.
	var top_edge := -render_margin
	var bottom_edge := height + render_margin
	var y := scroll - tile_h
	while y > top_edge:
		y -= tile_h
	while y < bottom_edge:
		draw_texture_rect(MEDIAN_TEXTURE, Rect2(0, y, width, tile_h), false)
		y += tile_h
