extends RefCounted
class_name SpeedRamp

## The single source of truth for the round's difficulty ramp — how fast the
## road scrolls and how thick traffic gets, as a function of how long the
## round has been running.
##
## This used to live as copy-pasted `BASE_SPEED`/`SPEED_PER_SECOND` constants
## in both `PlayerBoard.gd` and `LaneDivider.gd`, which had to be kept
## numerically identical by hand or the road and the tree median would scroll
## at different rates (that desync has already been shipped once — see
## PROJECT_STATE §5 "LaneDivider never reset across rounds"). The ramp is no
## longer two numbers you can eyeball for equality, so it lives in one place
## and both callers ask it. Nothing here holds state: `elapsed` is passed in,
## because each board and each divider still owns its own round timer.
##
## ## The curve, and why it is not a straight line
##
## The ramp was `160 + 6 * elapsed` — dead linear and unbounded. That put the
## board at double its starting speed 30 seconds in and kept climbing without
## limit, which is what "gets too fast too soon" was describing: the opening
## of a round had no room to breathe, and a long round eventually became
## unreadable rather than hard.
##
## Now speed eases along `progress ^ RAMP_CURVE` toward `TOP_SPEED`. With an
## exponent above 1 the curve starts nearly flat and steepens, so the first
## half-minute stays close to the (already signed-off) starting feel and the
## pressure arrives as the round matures:
##
##     t=0s   160   t=45s  286
##     t=15s  186   t=60s  351
##     t=30s  230   t=100s 560  (ramp complete)
##
## For comparison the old line was already at 340 by t=30 and 520 by t=60.
##
## Past `RAMP_DURATION` speed does not simply stop: this is a
## last-one-driving competitive mode, so a round has to stay guaranteed to
## end. It keeps creeping at `OVERTIME_SPEED_PER_SECOND`, which is a fifth of
## the old slope — enough that a stalemate still resolves, gentle enough that
## surviving a long time doesn't turn into a blur.
const BASE_SPEED := 160.0
const TOP_SPEED := 560.0
const RAMP_DURATION := 100.0 # seconds to reach TOP_SPEED
const RAMP_CURVE := 1.45 # >1 = gentle early, steepening later; 1.0 would restore the old straight line
const OVERTIME_SPEED_PER_SECOND := 1.2 # slow creep past TOP_SPEED so a round always eventually ends

## Traffic density tightens on the same shape but over a shorter window than
## speed. Deliberately separate: thicker traffic makes a board harder to read
## without making it faster, so density is the knob that should lead. Letting
## it finish first means the mid-round difficulty comes from having to pick a
## line through real traffic, and only the late round is about raw pace.
##
## The old spawn ramp bottomed out at 33 seconds, which is the other half of
## "too fast too soon" — maximum traffic density arrived before the player
## had settled in.
const SPAWN_INTERVAL_START := 0.85
const SPAWN_INTERVAL_MIN := 0.35
const SPAWN_RAMP_DURATION := 70.0 # seconds to reach SPAWN_INTERVAL_MIN

# Eased 0→1 progress along a ramp of `duration` seconds. Shared by both ramps
# so speed and density always have the same character, only a different pace.
static func _progress(elapsed: float, duration: float) -> float:
	return pow(clamp(elapsed / duration, 0.0, 1.0), RAMP_CURVE)

# The road's scroll rate at `elapsed` seconds into the round, before any
# per-board multipliers (boost, tank recoil) that only PlayerBoard knows about.
static func speed_at(elapsed: float) -> float:
	var speed := BASE_SPEED + (TOP_SPEED - BASE_SPEED) * _progress(elapsed, RAMP_DURATION)
	if elapsed > RAMP_DURATION:
		speed += (elapsed - RAMP_DURATION) * OVERTIME_SPEED_PER_SECOND
	return speed

# Seconds between obstacle spawns at `elapsed` seconds into the round.
static func spawn_interval_at(elapsed: float) -> float:
	var t := _progress(elapsed, SPAWN_RAMP_DURATION)
	return SPAWN_INTERVAL_START + (SPAWN_INTERVAL_MIN - SPAWN_INTERVAL_START) * t
