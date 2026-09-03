extends RefCounted
class_name SkillEffect

## Base class for a Don't Crash skill written as its own file.
##
## Tank Mode, Nitro and the Taxi predate this and still live inline in
## PlayerBoard.gd (see docs/PROJECT_STATE.md §5 sessions G/P/I). Everything
## added after them is a subclass of this instead, for one blunt reason:
## PlayerBoard.gd is already 2500+ lines and six more skills written into it
## would be both unreadable and impossible to build in parallel — §12 records
## what happens when two sessions read-modify-write the same file at once.
##
## A skill is a plain RefCounted, not a Node. It never ticks itself and never
## draws itself: PlayerBoard owns the clock and the canvas and calls the hooks
## below at the points in its own frame where they are correct. That is the
## same reasoning Countdown.gd is built on (§2) — the thing that has state
## about a round is the thing that must drive it.
##
## LIFECYCLE, in the order PlayerBoard calls it (see _apply_skill_effect):
##   setup(board, id) -> time_left = duration() -> ADDED to board.active_effects
##   -> activate()
##   ... every frame:   time_left -= delta -> tick(delta) -> draw hooks
##   ... when is_done(): REMOVED from board.active_effects -> deactivate()
## The two capitalised steps are the contract that makes the hooks usable
## from the lifecycle calls: inside activate() and tick() the board already
## sees this effect (so board.refresh_car_size() after a car_kind() claim
## lands the new size), and inside deactivate() it no longer does (so the
## same call there puts the old size back, with no flag needed to retract
## the claim first).
## A duration() of 0.0 means an instant skill: activate() runs and the effect
## is finished in the same call — it passes through the list and is out of
## it again before _apply_skill_effect returns.
##
## Re-picking a skill that is already running does NOT stack it — time_left is
## reset to duration() and refresh() is called. That is the rule Tank Mode and
## the pickup itself already follow (see _activate_tank_mode).
##
## `board` is deliberately untyped, for the same reason BotDriver.board is
## (§7): PlayerBoard names this class, so naming PlayerBoard back would be a
## cyclic class reference. Reach whatever you need off it dynamically.

var board = null # PlayerBoard — untyped on purpose, see above
var id: String = ""
var time_left: float = 0.0

# Called by PlayerBoard immediately after .new(), before activate(). Kept
# separate from _init so a subclass never has to redeclare a constructor
# signature just to exist.
func setup(p_board, p_id: String) -> void:
	board = p_board
	id = p_id

# How long this skill lasts, in seconds. 0.0 = instant (activate() and then
# done, in one call, never ticked).
func duration() -> float:
	return 0.0

# Everything the skill does at the moment it lands. Runs exactly once.
func activate() -> void:
	pass

# Per-frame, from PlayerBoard._process, after the board's own timers and
# before its steering block. time_left has already been decremented.
func tick(_delta: float) -> void:
	pass

# Re-picked while already running: refresh rather than stack. time_left has
# already been put back to duration() by the time this is called.
func refresh() -> void:
	pass

# Put back anything activate() changed. MUST be idempotent and MUST leave the
# board exactly as it found it: start_round() calls this on every live effect
# when a round restarts, and a skill that leaks a node or a modified constant
# leaks it into the next round (the §5 session G tank-smoke leak, exactly).
func deactivate() -> void:
	pass

func is_done() -> bool:
	return time_left <= 0.0

# --- Hooks into the board's own physics. Each is combined by multiplying
# --- every live effect's value together, so two effects can overlap without
# --- either one having to know about the other.

# Multiplies current_speed() — the road, the traffic closing on the player,
# and the distance they are scored on, all at once. This is the same lever
# boost, tank recoil and the post-crash crawl already pull.
func road_speed_mult() -> float:
	return 1.0

# Multiplies steer_top_speed(). BotDriver reads that same function, so a bot
# on this board stays honest about its own agility for free.
func steer_speed_mult() -> float:
	return 1.0

# Multiplies STEER_RESPONSE — how fast the car's real momentum catches up to
# the steering input. Below 1.0 the car goes floaty and overshoots; this is
# the same lever DRIFT_GRIP_MULT pulls during a slide.
func grip_mult() -> float:
	return 1.0

# Return a non-empty {"width_frac": float, "height_frac": float} to change
# the player car's footprint (see PlayerBoard.PLAYER_KIND / TANK_KIND). Only
# the first live effect returning one wins, and Tank Mode outranks all of
# them. Call board.refresh_car_size() from activate()/deactivate() so the
# sprite is resized to match the moment it changes.
func car_kind() -> Dictionary:
	return {}

# Return a Texture2D to re-skin the player's car for the duration. Like
# car_kind() the first live effect that claims one wins, and Tank Mode
# outranks all of them. Call board.refresh_car_texture() from
# activate()/deactivate() so the sprite changes the moment the claim does.
#
# This is a SKIN, not a size: the texture is stretched to whatever
# car_size() currently says (Car._rebuild scales each axis independently),
# so a texture at any aspect but the one car_kind() implies will look
# squashed. Authoring the art to fit the existing footprint is the cheap
# side of that trade; claiming car_kind() as well is the expensive one,
# because it changes the hitbox.
func car_texture() -> Texture2D:
	return null

# How big to draw that skin, as a multiple of the footprint. This is the one
# way to change the *size* of the player's car without changing the car: it
# scales the Sprite2D only (Car.sprite_scale_mult), so the hitbox, the
# steering bounds, the dash clamp and what the bot thinks fits in a gap all
# stay exactly what car_kind() says they are.
#
# It is here because replacement art is not obliged to fill its canvas the
# way the stock art does, and the texture is stretched to the canvas: a
# cruiser drawn 56px wide inside the sedans' 78x132 canvas, which they fill
# to 67px, arrives on screen 16% narrower than the car it replaced. That
# reads as the player shrinking. Use this to put the art back at the size it
# should look, NOT to make a skill's car genuinely bigger or smaller — a
# sprite that no longer matches its own hitbox is a lie about where the
# crashes are, and car_kind() is the honest way to change a footprint.
#
# Read off the same effect that won car_texture(), so a skin and the scale it
# is drawn at can never be resolved from two different skills.
func car_texture_scale() -> float:
	return 1.0

# Return true to swallow a crash that would otherwise cost a life. `vehicle`
# is the Car that was hit — destroy it yourself if that is what should happen
# to it (board._destroy_vehicle), the caller will not.
func absorbs_crash(_vehicle) -> bool:
	return false

# --- Drawing. Both run in the board's own local space (0,0 is the board's
# --- top-left corner, board_width x board_height its extent), and both are
# --- called from inside a real _draw() — but NOT the same one, and that
# --- decides which object the draw_* calls go to. Godot only accepts draw_*
# --- calls on the CanvasItem that is currently inside its own _draw(); a
# --- call on any other node is refused at runtime ("Drawing is only allowed
# --- inside NOTIFICATION_DRAW") and paints nothing.

# Called from PlayerBoard._draw(): draw on `board` — board.draw_circle(),
# board.draw_rect(), board.draw_texture_rect() and friends.
# Lands ABOVE the road and BELOW the traffic and the player car — the road
# surface. Tyre marks, a spill, painted markings.
func draw_board() -> void:
	pass

# Called from SkillOverlay._draw(): draw on `board.skill_overlay`, e.g.
#   var canvas: CanvasItem = board.skill_overlay
#   canvas.draw_circle(...)
# The overlay is a child of the board at its origin, so the coordinates are
# the same board-local ones draw_board() uses.
# Lands ABOVE everything, including Nitro's energy — the air between the
# player and the screen. Smoke, glare, a flash.
func draw_overlay() -> void:
	pass

# --- The HUD timer bar, stacked under the boost bar with Tank's and Nitro's.

# Return a colour with alpha > 0 to get a bar. Instant skills want no bar.
func bar_color() -> Color:
	return Color(0.0, 0.0, 0.0, 0.0)

func bar_fraction() -> float:
	var total: float = duration()
	if total <= 0.0:
		return 0.0
	return clamp(time_left / total, 0.0, 1.0)
