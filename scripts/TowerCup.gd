extends Control

## Pile Up's cup standings — the screen between the rounds of a cup
## (GameSettings.tower_cup), and the one a cup opens on.
##
## One row per competitor: a player in the solo cup, a side in the team cup,
## marked by their own car and colour on the left. A trophy is drawn as a car
## too, parked in a row that ends at a finish flag at CUP_TARGET — and the car
## is the *round winner's* (GameSettings.cup_trophy_cars): when blue wins a
## round, blue's row takes three blue cars, 2nd place's two blue cars and 3rd
## place's one. So every row reads left to right as the cup's history, in the
## colours of whoever won each round. A winning team's cars take turns between
## its two members. The empty slots up to the flag are dark silhouettes, so
## how far everyone has to go is as visible as how far they have come.
##
## After a round the row first shows what it had, then this round's trophies
## pop into it one at a time — every row at once, so the screen takes about a
## second however many are playing — and the place and the award appear
## beside it. Then it names the next round's mode, which is a different one
## (GameSettings.cup_variant) — or, once somebody has reached the target, the
## champion. Enter skips the animation, then moves on.
##
## Drawn rather than built from Labels, same as TowerHUD: the rows are
## made of textures, and the animation is a function of one clock.

const BG := Color(0.078, 0.086, 0.165, 1.0) # the menus' own navy
const ROW_BG := Color(1.0, 1.0, 1.0, 0.045)
const STRIPE_W := 6.0
const TEXT := Color(1.0, 1.0, 1.0, 0.95)
const DIM := Color(1.0, 1.0, 1.0, 0.62)
const FAINT := Color(1.0, 1.0, 1.0, 0.38)
const GOLD := Color(1.0, 0.80, 0.22, 1.0)
# A slot not yet earned: the car's own shape, nearly black. Darker than the
# row behind it rather than lighter, so it reads as a hole to be filled and
# never as a faded trophy somebody already has.
const GHOST := Color(0.0, 0.0, 0.03, 0.55)

const ROWS_TOP := 178.0
const ROWS_BOTTOM := 652.0
const ROW_MAX_H := 128.0
const ROW_GAP := 12.0
const MARGIN_X := 60.0
const BADGE_W := 290.0 # the competitor's cars and name, left of the place
const PLACE_W := 86.0 # "1st" and "+3", between the badge and the track
const TOTAL_W := 120.0 # the running count, right of the flag
const FLAG_W := 16.0
const FLAG_CELL := 8.0
# A trophy car stands upright, nose up like every car in the game, and is as
# tall as TROPHY_H of its row — unless that would make it wider than CAR_FILL
# of its slot, which only happens once a total past the target squeezes the
# slots. Upright rather than on its side facing the flag, which was tried
# first: a slot is ~56px wide, so a car lying in one is under 30px tall and
# reads as a dash rather than as somebody's car.
const TROPHY_H := 0.62
const CAR_FILL := 0.86

const POP_START := 0.55 # the old standings on their own first, so the new ones read as arriving
const POP_STEP := 0.30 # between one trophy and the next in a row
const POP_TIME := 0.32
const POP_SCALE := 0.65 # how much bigger a trophy lands than it settles
const RING_RADIUS := 34.0
const MIN_BEFORE_LEAVING := 0.4 # a stray second Enter from the result screen must not skip a round

const ORDINALS := ["1st", "2nd", "3rd", "4th"]

var t := 0.0
var competitors: int = 0
var before: Array[int] = [] # per competitor, the total going into this screen's animation
var award: Array[int] = [] # per competitor, what this screen adds (all zero on the intro)
var place_of: Array[int] = [] # per competitor, 0-based place in the round just played; -1 on the intro
var champion: int = -1
var _done_at := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Run on its own (from the editor, or a probe) there is no cup yet.
	if GameSettings.tower_cup == GameSettings.TOWER_CUP_NONE:
		GameSettings.tower_cup = GameSettings.TOWER_CUP_SOLO
	if GameSettings.cup_scores.size() != GameSettings.cup_competitors():
		GameSettings.cup_reset()
	_begin()

# The standings as GameSettings has them, with the last round's trophies
# split back out so they can be shown arriving.
func _begin() -> void:
	t = 0.0
	competitors = GameSettings.cup_competitors()
	before = []
	award = []
	place_of = []
	var after_round: bool = GameSettings.cup_round > 0 and GameSettings.cup_last_awards.size() == competitors
	var most := 0
	for c in range(competitors):
		var got: int = GameSettings.cup_last_awards[c] if after_round else 0
		award.append(got)
		before.append(GameSettings.cup_scores[c] - got)
		place_of.append(GameSettings.cup_last_order.find(c) if after_round else -1)
		most = maxi(most, got)
	champion = GameSettings.cup_champion()
	_done_at = POP_START + float(maxi(0, most - 1)) * POP_STEP + POP_TIME if most > 0 else 0.0
	queue_redraw()

func _process(delta: float) -> void:
	t += delta
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = event.keycode
	if key == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		return
	if key != KEY_ENTER and key != KEY_KP_ENTER:
		return
	if t < _done_at:
		t = _done_at
		return
	if t < MIN_BEFORE_LEAVING:
		return
	if champion >= 0:
		# Same players, same colours, every count back to zero.
		GameSettings.cup_reset()
		_begin()
		return
	GameSettings.tower_variant = GameSettings.cup_variant(GameSettings.cup_round)
	get_tree().change_scene_to_file(GameSettings.tower_scene())

# --- Who is who ----------------------------------------------------------------

func _members(c: int) -> Array[int]:
	return GameSettings.cup_members(c)

func _skin(slot: int) -> Texture2D:
	if slot < GameSettings.skins.size():
		return GameSettings.skins[slot]
	return GameSettings.PLAYER_SKINS[slot % GameSettings.PLAYER_SKINS.size()]["texture"]

func _color(slot: int) -> Color:
	if slot < GameSettings.skin_colors.size():
		return GameSettings.skin_colors[slot]
	return GameSettings.PLAYER_SKINS[slot % GameSettings.PLAYER_SKINS.size()]["color"]

func _competitor_color(c: int) -> Color:
	var m: Array[int] = _members(c)
	return _color(m[0]) if not m.is_empty() else TEXT

# --- Drawing ---------------------------------------------------------------------

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), BG, true)
	_draw_heading(font)

	var n: int = maxi(1, competitors)
	var row_h: float = minf(ROW_MAX_H, (ROWS_BOTTOM - ROWS_TOP - ROW_GAP * float(n - 1)) / float(n))
	var block: float = row_h * float(n) + ROW_GAP * float(n - 1)
	var y: float = ROWS_TOP + (ROWS_BOTTOM - ROWS_TOP - block) * 0.5
	for c in range(competitors):
		_draw_row(font, c, Rect2(MARGIN_X, y, size.x - MARGIN_X * 2.0, row_h))
		y += row_h + ROW_GAP

	_draw_footer(font)

func _draw_heading(font: Font) -> void:
	var cup: Dictionary = GameSettings.tower_cup_info()
	var title: String
	var sub: String
	var title_color: Color = TEXT
	if champion >= 0 and t >= _done_at:
		title = "%s WIN%s THE %s!" % [GameSettings.cup_name(champion),
			"" if GameSettings.tower_cup == GameSettings.TOWER_CUP_TEAM else "S", cup["title"]]
		sub = "%d trophies after %d rounds" % [GameSettings.cup_scores[champion], GameSettings.cup_round]
		var c: Color = _competitor_color(champion)
		title_color = Color(c.r, c.g, c.b, 1.0).lightened(0.15)
	elif GameSettings.cup_round == 0:
		title = "THE %s" % cup["title"]
		sub = "first to %d trophies wins — 1st place 3, 2nd 2, 3rd 1, 4th none" % GameSettings.CUP_TARGET
	else:
		var played: int = GameSettings.cup_variant(GameSettings.cup_round - 1)
		title = "ROUND %d — %s" % [GameSettings.cup_round, GameSettings.tower_variant_info(played)["title"]]
		sub = "first to %d trophies wins the %s" % [GameSettings.CUP_TARGET, cup["title"].to_lower()]
	draw_string(font, Vector2(0.0, 96.0), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 40, title_color)
	draw_string(font, Vector2(0.0, 134.0), sub, HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, DIM)

func _draw_footer(font: Font) -> void:
	if t < _done_at:
		return
	var a: float = clampf((t - _done_at) / 0.25, 0.0, 1.0)
	if champion >= 0:
		draw_string(font, Vector2(0.0, 712.0), "ENTER for a new cup      ESC for the menu",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color(TEXT.r, TEXT.g, TEXT.b, a))
		return
	var next: Dictionary = GameSettings.tower_variant_info(GameSettings.cup_variant(GameSettings.cup_round))
	draw_string(font, Vector2(0.0, 704.0), "ENTER — round %d: %s" % [GameSettings.cup_round + 1, next["title"]],
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(GOLD.r, GOLD.g, GOLD.b, a))
	draw_string(font, Vector2(0.0, 734.0), next["hint"], HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color(DIM.r, DIM.g, DIM.b, DIM.a * a))
	draw_string(font, Vector2(0.0, 772.0), "ESC leaves the cup", HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Color(FAINT.r, FAINT.g, FAINT.b, FAINT.a * a))

func _draw_row(font: Font, c: int, r: Rect2) -> void:
	var members: Array[int] = _members(c)
	var color: Color = _competitor_color(c)
	var crowned: bool = champion == c and t >= _done_at
	var bg: Color = ROW_BG
	if crowned:
		var pulse: float = 0.5 + 0.5 * sin((t - _done_at) * 4.0)
		bg = Color(color.r, color.g, color.b, 0.12 + 0.08 * pulse)
	draw_rect(r, bg, true)
	draw_rect(Rect2(r.position, Vector2(STRIPE_W, r.size.y)), color, true)

	# The badge: each member's car standing upright, then the name.
	var mid_y: float = r.position.y + r.size.y * 0.5
	var car_len: float = r.size.y * 0.66
	var x: float = r.position.x + STRIPE_W + 22.0
	for s in members:
		var tex: Texture2D = _skin(s)
		var w: float = car_len * tex.get_size().x / tex.get_size().y
		_draw_car(tex, Vector2(x + w * 0.5, mid_y), car_len, 1.0, Color.WHITE)
		x += w + 10.0
	var label: String = GameSettings.cup_name(c)
	var name_x: float = x + 8.0
	var name_w: float = r.position.x + BADGE_W - name_x
	draw_string(font, Vector2(name_x, mid_y + (2.0 if members.size() > 1 else 10.0)), label,
		HORIZONTAL_ALIGNMENT_LEFT, name_w, 28 if members.size() == 1 else 22, Color(color.r, color.g, color.b, 1.0).lightened(0.1))
	if members.size() > 1:
		var who: Array[String] = []
		for s in members:
			who.append(GameSettings.PLAYER_CONFIGS[s]["name"])
		draw_string(font, Vector2(name_x, mid_y + 24.0), " + ".join(who), HORIZONTAL_ALIGNMENT_LEFT, name_w, 15, DIM)

	# Where it finished this round, once its first new trophy lands (or at
	# once, for a row that won nothing — that is news too).
	var px: float = r.position.x + BADGE_W
	if place_of[c] >= 0 and t >= POP_START:
		var a: float = clampf((t - POP_START) / 0.2, 0.0, 1.0)
		var ord: String = ORDINALS[place_of[c]] if place_of[c] < ORDINALS.size() else "%dth" % (place_of[c] + 1)
		draw_string(font, Vector2(px, mid_y - 2.0), ord, HORIZONTAL_ALIGNMENT_CENTER, PLACE_W, 22, Color(TEXT.r, TEXT.g, TEXT.b, a))
		var gold: Color = GOLD if award[c] > 0 else FAINT
		draw_string(font, Vector2(px, mid_y + 24.0), "+%d" % award[c], HORIZONTAL_ALIGNMENT_CENTER, PLACE_W, 20, Color(gold.r, gold.g, gold.b, gold.a * a))

	# The track: CUP_TARGET slots to the flag. A total past the target (14
	# plus a win) squeezes the slots rather than running off the row.
	var track_x: float = px + PLACE_W + 12.0
	var flag_x: float = r.end.x - TOTAL_W - FLAG_W - 10.0
	var total: int = before[c] + award[c]
	var slots: int = maxi(GameSettings.CUP_TARGET, total)
	var slot_w: float = (flag_x - 8.0 - track_x) / float(slots)
	var ref: Vector2 = _skin(members[0] if not members.is_empty() else 0).get_size()
	var trophy_len: float = minf(r.size.y * TROPHY_H, slot_w * CAR_FILL * ref.y / ref.x)
	var shown: int = before[c]
	for k in range(slots):
		var center := Vector2(track_x + slot_w * (float(k) + 0.5), mid_y)
		var car: int = _trophy_car(c, k, members)
		var tex: Texture2D = _skin(car)
		if k < before[c]:
			_draw_car(tex, center, trophy_len, 1.0, Color.WHITE)
			continue
		if k < total:
			var at: float = POP_START + float(k - before[c]) * POP_STEP
			if t >= at:
				_draw_pop(tex, center, trophy_len, t - at, _color(car))
				shown += 1
				continue
		_draw_car(tex, center, trophy_len, 1.0, GHOST)

	_draw_flag(Vector2(flag_x, mid_y - r.size.y * 0.36), r.size.y * 0.72)

	var count_color: Color = GOLD if total >= GameSettings.CUP_TARGET and shown >= total else TEXT
	var tx: float = flag_x + FLAG_W + 14.0
	draw_string(font, Vector2(tx, mid_y + 12.0), "%d" % shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, count_color)
	var num_w: float = font.get_string_size("%d" % shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	draw_string(font, Vector2(tx + num_w + 4.0, mid_y + 12.0), "/ %d" % GameSettings.CUP_TARGET, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, FAINT)

# Whose car trophy `k` of competitor `c` is: the winner of the round it was
# won in. A slot the cup has no record for — not yet won, or a total set by
# hand — falls back to the row's own members, which is only ever seen as a
# silhouette or in a hand-made test.
func _trophy_car(c: int, k: int, members: Array[int]) -> int:
	var car: int = GameSettings.cup_trophy_car(c, k)
	if car >= 0:
		return car
	return members[k % members.size()] if not members.is_empty() else 0

# A trophy arriving: it lands big and settles into its slot, with a ring in
# the round winner's colour going out from it.
func _draw_pop(tex: Texture2D, center: Vector2, length: float, dt: float, ring: Color) -> void:
	var k: float = clampf(dt / POP_TIME, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - k, 3.0)
	var alpha: float = clampf(dt / 0.1, 0.0, 1.0)
	if k < 1.0:
		draw_arc(center, lerpf(8.0, RING_RADIUS, eased), 0.0, TAU, 32, Color(ring.r, ring.g, ring.b, 0.8 * (1.0 - k)), 3.0, true)
	_draw_car(tex, center, length, 1.0 + POP_SCALE * (1.0 - eased), Color(1.0, 1.0, 1.0, alpha))

# A car `length` tall, at its own aspect, centred — scaled about its centre
# for the landing pop. The sedans face up, so it stands nose up.
func _draw_car(tex: Texture2D, center: Vector2, length: float, scale_mult: float, modulate_color: Color) -> void:
	var ts: Vector2 = tex.get_size()
	var size_px := Vector2(length * ts.x / ts.y, length) * scale_mult
	draw_texture_rect(tex, Rect2(center - size_px * 0.5, size_px), false, modulate_color)

func _draw_flag(top_left: Vector2, h: float) -> void:
	var rows: int = int(h / FLAG_CELL)
	var cols: int = int(FLAG_W / FLAG_CELL)
	for i in range(rows):
		for j in range(cols):
			var light: bool = (i + j) % 2 == 0
			draw_rect(Rect2(top_left + Vector2(float(j) * FLAG_CELL, float(i) * FLAG_CELL), Vector2(FLAG_CELL, FLAG_CELL)),
				Color(0.95, 0.95, 0.97, 0.9) if light else Color(0.02, 0.02, 0.05, 0.9), true)
