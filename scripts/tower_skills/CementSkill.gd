extends TowerSkill

## CEMENT — the caster's brick sets to whatever it touches.
##
## Pile Up's bricks hold together by weight and friction alone, which is
## what makes an overhang a gamble: a brick hung a cell past the one below
## it stays only while its centre of mass is over something. This skill
## removes that gamble for one brick. The instant it is handed to the
## physics engine, every body it is in contact with — the brick beneath, a
## neighbour flush against its flank, the platform itself — is pinned to it
## with joints, and the pair move as one lump from then on. The player can
## hang a brick off the side of the tower and it stays there, a cantilever,
## and every player after them has to build around it.
##
## The joints are the whole mechanic and they are deliberately left in the
## tower when the effect ends: TowerSkill's header allows exactly this ("a
## joint it added between two landed bricks may stay"), and a weld that
## dissolved at the end of the turn would be a weld nobody could plan
## around. So would one nobody could *see*, which is why the seam is also
## left behind, as a Line2D child of the brick — under mode.pieces, so it
## rides with the brick and dies with it. The table needs to know which
## bricks are one lump: building on a glued cantilever is safer than it
## looks, and knocking it is worse.
##
## Why two pins per neighbour and not one. A PinJoint2D constrains a
## point, so one pin lets the brick swing about it like a hinge, and a
## hinged overhang is just an overhang with extra steps. Two pins at two
## different points fix both position and angle by geometry alone, with no
## reliance on the joint's angular-limit feature — whose zero reference
## this author could not verify without the engine source to hand, and
## which if measured from the wrong angle would spin a rotated brick round
## to "align" it. They sit at the two ends of the contact seam when the
## seam is long enough; a corner touch gets one pin at the corner and one
## half a cell inside the brick. A pin does not have to lie on a surface,
## it only has to be a point both bodies agree on.
##
## What the glue does NOT do is hold the *lump* up. A brick welded to a
## neighbour that was itself balanced near its edge moves that neighbour's
## centre of mass, and the pair go over together, on the caster's clock.
## That risk is what keeps this from being a free placement.
##
## Nothing here is undone in deactivate(): before the release there is only
## a timer and a drawing, and after it there is only tower state. The rest
## of this file is the contact query that finds the seams, and the two
## visuals — wet cement carried down on the brick, then the seam curing
## once it has landed.

# --- Tuning ----------------------------------------------------------------

# How far past the brick's own faces the contact query reaches. A landed
# brick touches what it landed on with a gap of literally zero (see
# TowerMode.QUERY_SKIN for why the lattice makes that the ordinary case),
# and Godot counts a zero gap as a hit, so any reach at all finds the brick
# below; the extra is for a flank neighbour that settled a pixel or two
# away. Kept under TowerPiece.FOOT_INSET so it can never reach a brick that
# is merely near.
const REACH := 4.0
# A contact seam shorter than this is a corner touch, not a face: the second
# pin goes inside the brick instead (see the header).
const MIN_SPAN := 8.0
const INSIDE := 19.0 # half a cell; where that interior pin goes
# A brick at rest cannot be touching more than this and still be a brick
# in a tower; anything beyond it is the query finding debris in flight.
const MAX_NEIGHBOURS := 4

# --- Visuals ---------------------------------------------------------------
# All procedural, derived from _t (advanced in tick) and _set_at — the
# CompactSkill rule: no Tween, no node of the skill's own to leak. The one
# node this file creates for the look, the seam Line2D, is tower state.

# Wet cement. Deliberately drab: every brick in the set is saturated, so the one
# thing on the tower that is not a colour reads as the cement between them.
const CEMENT := Color(0.64, 0.62, 0.57)
const WET := Color(0.86, 0.86, 0.84) # the sheen while it is still setting
const SEAM_WIDTH := 8.0 # world px; ~6 on screen after the VISIBLE_CELLS zoom, which is what it takes to read as a bead of cement and not a hairline
const COAT_WIDTH := 5.0 # screen px, the wet outline on the descending brick — wider than the art's own dark outline, or it hides behind it
const SET_TIME := 1.1 # seconds from landing until the seam reads as cured
const CURE_FLASH := 0.22 # the rim flash at the end of that
const BREATHE_HZ := 1.6
const DRIP_SPEED := 44.0 # world px/s a drip falls
const DRIP_LEN := 16.0 # how far it falls before the next one forms

var _t := 0.0
var _set_at := -1.0 # _t at the release; < 0 while the brick is still descending
var _piece = null # the released brick, untyped: the tower can free it under us
var _seams: Array[PackedVector2Array] = [] # two points each, in the brick's own frame
var _welds := 0 # neighbours actually pinned; 0 means the cement found nothing to grab

func hud_tag() -> String:
	return "CEMENT"

# --- Lifecycle -------------------------------------------------------------

func activate() -> void:
	_t = 0.0
	_set_at = -1.0
	_piece = null
	_seams = []
	_welds = 0

func tick(delta: float) -> void:
	_t += delta

# The brick is an ordinary rigid body now, at rest, exactly where it touched.
# Everything it is touching gets pinned to it. This runs inside
# TowerMode._land(), which runs inside _physics_process, so the space
# queries below are valid (they are not from _process).
func on_release(piece) -> void:
	_set_at = _t
	_piece = piece
	_seams = []
	_welds = 0
	var p := piece as TowerPiece
	if p == null or p.doomed:
		return # steered clean off the platform: nothing down there to set to

	var space: PhysicsDirectSpaceState2D = mode.get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	q.collision_mask = 1
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.margin = 0.0
	# One grown copy of each collision box. Grown rather than margined so the
	# contact points collide_shape() hands back are the real seam and not a
	# margin's worth inside it.
	var probes: Array[RectangleShape2D] = []
	for b: Rect2 in p.boxes:
		var r := RectangleShape2D.new()
		r.size = b.size * p.cell + Vector2(REACH, REACH) * 2.0
		probes.append(r)

	# 1. Who is the brick touching? Bodies only, itself excluded, debris and
	# anything still held ignored.
	var self_rid: Array[RID] = [p.get_rid()]
	q.exclude = self_rid
	var neighbours: Array = []
	for i in range(probes.size()):
		q.shape = probes[i]
		q.transform = p.global_transform * p.body_xforms[i]
		for hit in space.intersect_shape(q, 8):
			var body = hit["collider"]
			if body == null or neighbours.has(body):
				continue
			if body is TowerPiece and (body.held or body.doomed):
				continue
			neighbours.append(body)
	if neighbours.size() > MAX_NEIGHBOURS:
		neighbours.resize(MAX_NEIGHBOURS)

	# 2. Where, exactly? collide_shape() returns contact points but not who
	# they belong to, so it is asked once per neighbour with every other
	# neighbour excluded. For a face-on contact between two rectangles it
	# returns the two ends of the overlap, which is precisely the seam.
	for body in neighbours:
		var other: PhysicsBody2D = body
		var ex: Array[RID] = [p.get_rid()]
		for n in neighbours:
			if n != other:
				ex.append(n.get_rid())
		q.exclude = ex
		var pts: Array[Vector2] = []
		for i in range(probes.size()):
			q.shape = probes[i]
			q.transform = p.global_transform * p.body_xforms[i]
			var pairs: PackedVector2Array = space.collide_shape(q, 8)
			var box_pts: Array[Vector2] = []
			for k in range(0, pairs.size() - 1, 2):
				box_pts.append((pairs[k] + pairs[k + 1]) * 0.5)
			if box_pts.is_empty():
				continue
			var ends: Array[Vector2] = _extremes(box_pts)
			if ends[0].distance_to(ends[1]) < 1.0:
				# A corner: give the seam a little length so it draws as a
				# dab rather than vanishing.
				ends[0] += Vector2(-3.0, 0.0)
				ends[1] += Vector2(3.0, 0.0)
			_seams.append(PackedVector2Array([p.to_local(ends[0]), p.to_local(ends[1])]))
			pts.append_array(box_pts)
		if pts.is_empty():
			continue
		var span: Array[Vector2] = _extremes(pts)
		var a: Vector2 = span[0]
		var b: Vector2 = span[1]
		if a.distance_to(b) < MIN_SPAN:
			var inward: Vector2 = p.global_position - a
			b = a + (inward.normalized() if inward.length() > 0.5 else Vector2.UP) * INSIDE
		_pin(p, other, a)
		_pin(p, other, b)
		_welds += 1

	# 3. The permanent seam, one Line2D per contact, on the brick itself so
	# it goes wherever the brick goes — including off the tower, if the
	# lump it belongs to tips.
	for s: PackedVector2Array in _seams:
		var line := Line2D.new()
		line.points = s
		line.width = SEAM_WIDTH
		line.default_color = CEMENT
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		p.add_child(line)

# One pin between the brick and a neighbour at a world point. The joint
# lives under mode.pieces, which is the one place a skill may leave a node,
# and it takes itself out when either body leaves the tower: Joint2D
# already disconnects itself when a body exits the tree, so this is
# tidiness, not correctness — an empty joint node is inert.
func _pin(brick: TowerPiece, other: PhysicsBody2D, at: Vector2) -> void:
	var j := PinJoint2D.new()
	mode.pieces.add_child(j) # before the paths: they are relative to the joint
	j.global_position = at
	j.disable_collision = true # welded bodies do not also fight through contacts
	j.node_a = j.get_path_to(brick)
	j.node_b = j.get_path_to(other)
	brick.tree_exiting.connect(j.queue_free)
	other.tree_exiting.connect(j.queue_free)

# The two points farthest apart in a set. n is tiny (contact points of a
# few boxes), so the quadratic is fine.
func _extremes(pts: Array[Vector2]) -> Array[Vector2]:
	var best_a: Vector2 = pts[0]
	var best_b: Vector2 = pts[0]
	var best_d := -1.0
	for i in range(pts.size()):
		for k in range(i + 1, pts.size()):
			var d: float = pts[i].distance_squared_to(pts[k])
			if d > best_d:
				best_d = d
				best_a = pts[i]
				best_b = pts[k]
	return [best_a, best_b]

# Nothing to put back — see the header. Cleared so a retired effect holds
# no reference to a brick the tower may free.
func deactivate() -> void:
	_piece = null
	_seams = []

# --- Drawing ---------------------------------------------------------------

func _px(width: float) -> float:
	return width / mode.cam_zoom

# World space, above the bricks. Before the release: the brick comes down
# wearing wet cement. After it: the seams cure.
func draw_over(canvas: CanvasItem) -> void:
	if mode == null or mode.active_slot != target:
		return
	if _set_at < 0.0:
		_draw_wet_brick(canvas)
	else:
		_draw_curing(canvas)

# A cement outline hugging the brick's real silhouette (box_outlines, the
# same source the dash ghost uses, so an L wears cement the shape of an L),
# breathing slowly, with drips forming under the lowest edge of each box
# and falling away. The drips hang off each box separately: an L's short
# arm has its own underside.
func _draw_wet_brick(canvas: CanvasItem) -> void:
	var p = mode.active_piece
	if p == null or not p.held:
		return
	var pulse: float = 0.5 + 0.5 * sin(_t * TAU * BREATHE_HZ)
	var coat := Color(CEMENT.r, CEMENT.g, CEMENT.b, 0.7 + 0.3 * pulse)
	var loops: Array[PackedVector2Array] = p.box_outlines(p.global_transform)
	for loop: PackedVector2Array in loops:
		canvas.draw_polyline(loop, coat, _px(COAT_WIDTH))
	var n := 0
	for loop: PackedVector2Array in loops:
		var lo: float = INF
		var hi: float = -INF
		var bottom: float = -INF
		for i in range(4):
			lo = minf(lo, loop[i].x)
			hi = maxf(hi, loop[i].x)
			bottom = maxf(bottom, loop[i].y)
		for f: float in [0.3, 0.7]:
			var phase: float = float(n) * 0.37 * DRIP_LEN
			var d: float = fmod(_t * DRIP_SPEED + phase, DRIP_LEN)
			var frac: float = d / DRIP_LEN
			canvas.draw_circle(
				Vector2(lerpf(lo, hi, f), bottom + d),
				lerpf(4.5, 2.0, frac), # world px; smaller than this is sub-pixel after the zoom
				Color(CEMENT.r, CEMENT.g, CEMENT.b, 0.9 * (1.0 - frac))
			)
			n += 1

# The wet sheen over each seam fading out over SET_TIME, then a rim flash
# on the brick at the moment it reads as cured. The seam itself is the
# Line2D under this and needs no drawing. Nothing is drawn for a brick the
# cement found nothing to grab — there is no seam to cure.
func _draw_curing(canvas: CanvasItem) -> void:
	if _welds == 0 or _piece == null or not is_instance_valid(_piece):
		return
	var p: TowerPiece = _piece
	if not p.is_inside_tree():
		return
	var age: float = _t - _set_at
	var k: float = clampf(age / SET_TIME, 0.0, 1.0)
	if k < 1.0:
		var sheen := Color(WET.r, WET.g, WET.b, 0.9 * (1.0 - k))
		for s: PackedVector2Array in _seams:
			canvas.draw_line(p.to_global(s[0]), p.to_global(s[1]), sheen, SEAM_WIDTH + 2.0)
	elif age < SET_TIME + CURE_FLASH:
		var a: float = 1.0 - (age - SET_TIME) / CURE_FLASH
		for loop: PackedVector2Array in p.box_outlines(p.global_transform):
			canvas.draw_polyline(loop, Color(1.0, 1.0, 1.0, 0.8 * a), _px(3.0))
