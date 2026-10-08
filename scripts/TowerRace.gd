extends Control

## Pile Up's TEAM RACE — two towers side by side, one team building each, at
## the same time. First team to settle its tower over the line wins; a team
## that runs out of lives first loses. Hexes cast on one tower land on the
## other (TowerMode.receive_hex), on that tower's next brick.
##
## ## Why two TowerModes rather than one with two platforms
##
## A TowerMode is one turn loop: one brick in the air, one settle, one
## resolve. Two teams building *at once* is two of those loops, and the
## mode's whole fault rule is built on there being exactly one — so the race
## is two complete, unmodified-in-spirit TowerModes, not a TowerMode taught to
## juggle. Each sits in its own SubViewport, and a SubViewport has its own
## World2D: its own physics space, its own current camera, its own canvas
## layers. A brick on the left tower cannot touch the right one because they
## are not in the same world, not because anything checks.
##
## What a hosted tower does differently is small and lives behind
## `TowerMode.host`: it takes no input of its own (this script forwards every
## key to both, so neither depends on which viewport Godot would deliver an
## event to), shows no game-over overlay, and reports its result here the
## frame it is known.
##
## ## Why TextureRects and not SubViewportContainers
##
## The project stretches its 1500x800 canvas to the window ("canvas_items"),
## so on a high-DPI screen the root renders at the window's real resolution. A
## SubViewport renders at whatever size it is given, and a container sizes it
## in the root's *logical* pixels — so both towers would be drawn at 750x800
## and scaled up, visibly softer than everything else in the game. Instead
## each viewport is sized to the window's real pixels and told, through
## size_2d_override, to lay its 2D out at 750x800 anyway; a TextureRect
## shows it. The tower cannot tell the difference — get_visible_rect() reports
## the override — and it renders as sharp as the other modes.

const TOWER := preload("res://scenes/TowerMode.tscn")

# The seam between the towers: a dark divider carrying each team's progress
# to the line, so neither team has to look across the screen to know whether
# it is winning. Sits in the 24px margins both HUDs already leave at their
# outer edges.
const SEAM_W := 30.0
const SEAM_BG := Color(0.05, 0.06, 0.14, 0.85)
const METER_W := 8.0
const METER_TOP := 120.0
const METER_BOTTOM_UP := 90.0 # from the bottom of the screen
const METER_EMPTY := Color(1.0, 1.0, 1.0, 0.12)

@onready var screens: Control = $Screens
@onready var seam: Control = $Seam
@onready var overlay: Control = $Layer/Overlay
@onready var overlay_title: Label = $Layer/Overlay/OverlayTitle
@onready var overlay_body: Label = $Layer/Overlay/OverlayBody

var towers: Array = [] # [left, right]; untyped, TowerMode has no class_name
var viewports: Array[SubViewport] = []
var over := false

func _ready() -> void:
	seam.draw.connect(_draw_seam)
	var half := Vector2(size.x * 0.5, size.y)
	if half.x <= 0.0:
		var full: Vector2 = get_viewport().get_visible_rect().size
		half = Vector2(full.x * 0.5, full.y)
	var deal: int = _new_deal()
	for side in range(2):
		var vp := SubViewport.new()
		vp.size_2d_override = Vector2i(half)
		vp.size_2d_override_stretch = true
		vp.size = _pixel_size(half)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)

		var view := TextureRect.new()
		view.texture = vp.get_texture()
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.stretch_mode = TextureRect.STRETCH_SCALE
		view.position = Vector2(half.x * float(side), 0.0)
		view.size = half
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screens.add_child(view)

		# Everything the tower reads in _ready() is set before it enters the
		# tree: which variant, who builds on it, how far back the camera sits.
		var tower = TOWER.instantiate()
		tower.host = self
		tower.variant = GameSettings.TOWER_RACE
		tower.visible_cells = tower.RACE_VISIBLE_CELLS
		tower.brick_seed = deal
		var crew: Array[int] = []
		for s in range(GameSettings.player_count):
			if GameSettings.tower_team_of(s, GameSettings.TOWER_RACE) == side:
				crew.append(s)
		tower.members = crew
		vp.add_child(tower)
		towers.append(tower)
		viewports.append(vp)
	get_tree().root.size_changed.connect(_on_window_resized)

# The window's real pixels behind `logical` — see the header. At least the
# logical size, so a window smaller than 1500x800 is never rendered below it.
func _pixel_size(logical: Vector2) -> Vector2i:
	var s: float = maxf(1.0, get_tree().root.get_final_transform().get_scale().x)
	return Vector2i(ceili(logical.x * s), ceili(logical.y * s))

func _on_window_resized() -> void:
	for vp in viewports:
		vp.size = _pixel_size(Vector2(vp.size_2d_override))

func _process(_delta: float) -> void:
	seam.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		return
	if over:
		if event.keycode == KEY_ENTER:
			_restart()
		return
	# Both towers hear every key; each only acts on its own builders' keys.
	for t in towers:
		t.handle_key(event)

func _restart() -> void:
	over = false
	overlay.visible = false
	var deal: int = _new_deal()
	for t in towers:
		t.brick_seed = deal
		t._start_match()

# Both towers get the same bricks in the same order (TowerMode.brick_seed),
# and a fresh order every race. Never 0, which means "no deal".
func _new_deal() -> int:
	return (randi() & 0x7fffffff) | 1

# --- Called by the towers ---------------------------------------------------

# A hex cast on `from`, handed to the other tower. Returns who it landed on.
func relay_hex(from, id: String, caster: int) -> Array[int]:
	var i: int = towers.find(from)
	if i < 0 or over:
		var none: Array[int] = []
		return none
	return towers[1 - i].receive_hex(id, caster)

# A tower's match is decided — it reached the line, or ran out of lives. The
# first report decides the race; both towers are then stopped where they are.
func tower_finished(tower) -> void:
	if over:
		return
	over = true
	var side: int = towers.find(tower)
	var reached: bool = tower.winner_team >= 0
	var winner_side: int = side if reached else 1 - side
	for t in towers:
		t.halt()

	var winner_name: String = GameSettings.tower_team_name(winner_side, GameSettings.TOWER_RACE)
	var loser_name: String = GameSettings.tower_team_name(1 - winner_side, GameSettings.TOWER_RACE)
	overlay_title.text = "%s WINS" % winner_name
	var why: String
	if reached:
		why = "%s reached the line first" % winner_name
	else:
		why = "%s ran out of lives" % loser_name
	overlay_body.text = "%s\n\n%s\n%s" % [why, towers[0].team_summary(), towers[1].team_summary()]
	overlay.visible = true

# --- The seam ---------------------------------------------------------------

func _draw_seam() -> void:
	var cx: float = size.x * 0.5
	seam.draw_rect(Rect2(cx - SEAM_W * 0.5, 0.0, SEAM_W, size.y), SEAM_BG, true)
	if towers.size() < 2:
		return
	var goal: float = towers[0].goal_cells
	if goal <= 0.0:
		return
	var top: float = METER_TOP
	var bottom: float = size.y - METER_BOTTOM_UP
	for side in range(2):
		var t = towers[side]
		var x: float = cx - METER_W - 2.0 if side == 0 else cx + 2.0
		var frac: float = clampf(t._height_cells() / goal, 0.0, 1.0)
		var team_col: Color = t._team_color(side)
		seam.draw_rect(Rect2(x, top, METER_W, bottom - top), METER_EMPTY, true)
		var fill_h: float = (bottom - top) * frac
		seam.draw_rect(Rect2(x, bottom - fill_h, METER_W, fill_h), team_col, true)
	var gc: Color = towers[0].GOAL_COLOR
	seam.draw_rect(Rect2(cx - SEAM_W * 0.5 + 3.0, top - 3.0, SEAM_W - 6.0, 3.0), gc, true)
	seam.draw_string(ThemeDB.fallback_font, Vector2(cx - SEAM_W * 0.5, top - 10.0), "%d" % int(goal),
		HORIZONTAL_ALIGNMENT_CENTER, SEAM_W, 14, gc)
