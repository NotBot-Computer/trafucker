extends Node2D
class_name PlayerBoard

signal crashed
# Emitted when this board's player picks the "opponent" skill-choice option.
# PlayerBoard has no direct reference to sibling boards, so it can't apply an
# opponent skill itself — Main relays this to every OTHER board's
# receive_opponent_skill() (see Main._on_opponent_skill_triggered). This is
# the first and only cross-board communication path in the project.
signal opponent_skill_triggered(skill: String)

const CAR_SCENE := preload("res://scenes/Car.tscn")
const SKILL_PICKUP_SCENE := preload("res://scenes/SkillPickup.tscn")

@export var board_width: float = 360.0
@export var board_height: float = 620.0
@export var lane_count: int = 5
@export var body_color: Color = Color(0.231, 0.435, 0.878) # fallback if player_texture is null
@export var key_left: Key = KEY_A
@export var key_right: Key = KEY_D
@export var key_confirm: Key = KEY_W
@export var key_skill_opponent: Key = KEY_Q
@export var key_skill_self: Key = KEY_E
@export var player_name: String = "P1"

# --- Bot control -----------------------------------------------------------
# While `bot` is non-null this board is driven by BotDriver instead of the
# keyboard: _steer_held() reads bot_steer instead of the real keys, and
# _unhandled_input ignores this player's bindings outright. It can be switched
# on or off at any moment, including mid-round (Main's 1-4 keys) — that is the
# whole point of it, both as a way to watch a change play out hands-free and
# as the single-player opponent.
@export var is_bot: bool = false
var bot: BotDriver = null
var bot_steer: int = 0 # -1 / 0 / 1, the bot's virtual steering hold

var player_texture: Texture2D = null
# How far past [0, board_height] the camera can currently see (set by
# Main._build_boards() via set_vertical_margin() whenever it has to zoom the
# camera out to fit more players — see Road.render_margin for why). Used to
# push obstacle spawn/despawn points out past whatever the camera can
# actually see, so cars still pop in/out off-screen instead of appearing
# already inside the letterboxed strip.
var vertical_margin: float = 0.0

# The road-speed and traffic-density ramp lives in SpeedRamp.gd — see
# current_speed()/spawn_interval() below. It used to be four constants here
# with two of them copy-pasted into LaneDivider.gd; tune the curve there.
# How far past the bottom edge a vehicle travels before the shared obstacle
# loop culls it. Named because the taxi's spawn has to stay inside it — see
# TAXI_SPAWN_STAGGER_Y.
const OBSTACLE_DESPAWN_MARGIN := 140.0
const MAX_STEER_SPEED := 460.0
const STEER_RESPONSE := 9.0
const MAX_TILT := 0.32

# Traffic lane changes: a random slice of spawned obstacles will, partway
# down the board, signal and merge one lane over — real chaos instead of
# every car holding a perfectly straight line. Kept fair (not just chaotic)
# by three constraints: it only *arms* while the obstacle is still high up
# the board (LANE_CHANGE_TRIGGER_*_FRAC), so the player always has reaction
# room; the target lane must be clear of other traffic near the same y
# (_lane_clear_near) before it commits, so it never pops through another
# car; and the indicator blinks for a full warning window before any motion
# starts, same as a real turn signal, so the move is always telegraphed.
const LANE_CHANGE_CHANCE := 0.22 # fraction of spawned obstacles that may change lanes at all
const LANE_CHANGE_TRIGGER_Y_MIN_FRAC := 0.12 # earliest point (fraction of board_height) a change may arm
const LANE_CHANGE_TRIGGER_Y_MAX_FRAC := 0.5 # latest point — stays well above the player for reaction time
const LANE_CHANGE_INDICATOR_WARNING := 1.3 # seconds of blinking before the car actually moves
const LANE_CHANGE_DURATION := 0.5 # seconds spent sliding into the new lane
const LANE_CHANGE_INDICATOR_TAIL := 0.3 # keeps blinking this long after settling, like a real signal
const LANE_CHANGE_SAFE_GAP := 200.0 # min |dy| to another car already claiming the target lane

# Skill pickups: a rare glowing collectible (see SkillPickup.gd) that scrolls
# down the road at exactly the road's own scroll rate (speed_mult 1.0 — it's
# a fixed marking, not a vehicle with its own pace). Driving over one doesn't
# grant an actual skill yet — no skills are implemented — this is just the
# pickup + choice plumbing. The round never pauses for it: two glowing choice
# icons appear flanking the car (left = a skill that affects opponents, right
# = a skill that benefits the player themself) and the player taps a
# dedicated key (key_skill_opponent / key_skill_self, deliberately separate
# from steering) to pick one while still driving normally. The choice does
# not expire — it stays up indefinitely until picked, and only ever changes
# by driving over a new pickup (which currently just re-triggers the same
# generic choice; once real skills exist this is where a fresh pair would
# replace the old one). See _resolve_skill_choice for the (currently stub)
# hook where real skill effects belong once they're designed.
const SKILL_PICKUP_INTERVAL_MIN := 9.0
const SKILL_PICKUP_INTERVAL_MAX := 15.0
const SKILL_PICKUP_RADIUS_FRAC := 0.34 # fraction of lane width
const SKILL_ICON_RADIUS_FRAC := 0.4 # fraction of lane width
const SKILL_ICON_OFFSET_FRAC := 1.15 # fraction of car width, icon distance from car center

# Self skills: benefit the player who picks them. Only one exists today
# (Tank Mode), so _resolve_skill_choice's "self" branch always grants it —
# but it's picked from this pool rather than hardcoded so a future addition
# just means appending another entry here, matching the random-pick-from-pool
# pattern already used for TRAFFIC_KINDS (_pick_traffic_kind).
const SELF_SKILLS := ["tank"]

# Tank Mode: transform into an invincible tank for a limited time. The
# player's own confirm key (key_confirm) is repurposed from boost to firing
# a cannon shot at the nearest vehicle ahead in roughly the same lane, and
# any traffic the tank body touches is crushed instead of ending the round.
const TANK_TEXTURE := preload("res://sprites/cars/tank.png")
const TANK_KIND := {"width_frac": 0.75, "height_frac": 2.06} # matches the cropped sprite's own aspect ratio, wider than a normal car
const TANK_MODE_DURATION := 6.0
const TANK_BAR_HEIGHT := 6.0
const TANK_BAR_GAP := 4.0 # gap below the boost bar
const TANK_STEER_SPEED_MULT := 0.72 # a tank steers noticeably slower/heavier than a normal car
const TANK_DEBRIS_COUNT := 6
const TANK_DEBRIS_DURATION := 0.28

# Cannon fire animation: the muzzle flash/smoke are separate overlay sprites
# (cropped from tank_animasyon.png, tank hull excluded) positioned at the
# barrel tip by _fire_cannon/_play_fire_animation, rather than a single
# composite "tank body mid-animation" texture — the source sheet's tank
# render isn't pixel-aligned across its own cells, so treating the effect as
# an independent layer anchored at its own bottom-center sidesteps that
# entirely instead of fighting it. The shell (tank_shell.png) is a real
# sprite that travels from the muzzle to its target instead of an instant
# hit, and firing kicks the tank back with a brief speed dip (recoil) so it
# reads as a weapon, not a free action.
const TANK_FLASH_FRAMES := [preload("res://sprites/cars/tank_flash_1.png"), preload("res://sprites/cars/tank_flash_2.png")]
const TANK_SMOKE_FRAMES := [preload("res://sprites/cars/tank_smoke_1.png"), preload("res://sprites/cars/tank_smoke_2.png")]
const TANK_SHELL_TEXTURE := preload("res://sprites/cars/tank_shell.png")
# The tank's own width, in source pixels, within the sheet these overlay
# frames were cropped from (measured by inspection, same convention as
# Road.SHOULDER_RATIO) — keeps the flash/smoke sized proportionate to
# whatever the in-game tank's actual world width currently is.
const TANK_EFFECT_SOURCE_TANK_WIDTH := 188.0
const TANK_FLASH_FRAME_DURATION := 0.05
const TANK_SMOKE_FRAME_DURATION := 0.09
const TANK_SMOKE_FADE_DURATION := 0.22
const TANK_SHELL_SPEED := 1400.0 # px/sec, how fast the fired shell sprite travels
const TANK_SHELL_MIN_TRAVEL := 0.06
const TANK_SHELL_MAX_TRAVEL := 0.4
const TANK_RECOIL_KICK := 16.0 # world px the tank visually punches back on fire
const TANK_RECOIL_RECOVERY_SPEED := 90.0 # px/sec the kick offset recovers at
const TANK_RECOIL_DURATION := 0.3 # brief current_speed() dip synced with the kick
const TANK_RECOIL_SPEED_MULT := 0.55

# Opponent skills: picked from this pool but applied to every OTHER player's
# board, never the one who picked — mirrors SELF_SKILLS' pool-of-strings
# pattern, just resolved on the receiving end (see receive_opponent_skill)
# instead of locally.
const OPPONENT_SKILLS := ["taxi"]

# Taxi (the first opponent skill): a reckless cab barges onto a rival's board
# from behind — spawning past the bottom edge, since "behind" in this game's
# fiction is larger y (traffic spawns ahead at small y and closes in, so
# anything starting beyond board_height hasn't reached the player yet from
# their own point of view — it's tailgating them, see CLAUDE.md's
# +y-is-down/forward convention). It runs riot through the traffic for
# TAXI_CHAOS_DURATION, cutting across lanes and surging up the road or
# braking hard, before flooring it and driving off the top.
#
# **It roams the whole board; it does not chase the player.** The first
# version biased every speed roll to keep it near the player's y, which made
# it a tailgater with a small range rather than a hazard loose in the
# traffic. It now picks a destination anywhere up or down the board
# (tx_roam_y) and drives there, so it sweeps past the player, up ahead into
# the traffic they are about to reach, and back down again. Being dangerous
# to the player is a consequence of where the chaos happens to be, not the
# target it steers toward.
#
# **It is an ordinary traffic vehicle, and moves through the exact same line
# as every other car** (`position.y += speed * speed_mult * delta` in
# _process's obstacle loop). The only thing the taxi's AI does is *set* its
# own speed_mult and steer laterally each frame; it does not move itself.
# An earlier version drove its own y directly, chasing the player's position
# — which made it phase straight through any car between them, the exact
# opposite of belonging to the traffic. Everything erratic about it is
# therefore expressed within the traffic model rather than as an exception to
# it: acceleration/braking is speed_mult easing toward a new target
# (TAXI_SPEED_RESPONSE), and since speed_mult is a *closing fraction* of road
# speed, a negative value simply means "driving faster than the player" —
# which is what legitimately lets it overtake and come up from behind, with
# no need to break the sub-1.0 invariant in GameSettings.TRAFFIC_KINDS.
#
# What it must never do is drive through other traffic: _taxi_follow_limit
# clamps its speed_mult so it can't close on a car ahead of it in its own
# lane (it tailgates instead), and _taxi_target_clear gates every lane change
# on the target actually being free — re-checked continuously, not just at
# decision time. It is only ever ruthless toward the *player*.
# The taxi art is a *derivative of the fleet's own sedan sprite* (checker
# band + roof lamp painted onto sprites/cars/sedan_yellow.png), not an
# independently-sourced asset. Two earlier attempts used standalone taxi art
# and both read as pasted-on rather than as traffic — the mismatch was art
# lineage, not size or placement: the fleet sprites are soft-shaded rounded
# renders with gray-blue tinted glass, while the source taxi art was
# hard-outlined flat pixel art of a boxy vehicle, at ~2.5x the fleet's
# brightness. Deriving from a fleet sprite makes belonging structural
# instead of something to be matched by eye. If this art is ever regenerated,
# regenerate it from a fleet sedan the same way.
const TAXI_TEXTURE := preload("res://sprites/cars/taxi.png")
const TAXI_KIND := {"width_frac": 0.62, "height_frac": 1.6962} # identical footprint to TRAFFIC_KINDS' sedan (0.62/1.69) — it must never read as bigger than ordinary traffic
const TAXI_CHAOS_DURATION := 11.0
# speed_mult bounds. Negative = driving faster than the player (overtakes,
# travels up the screen); positive = slower than the player (falls back).
# Kept away from 1.0 for the same reason every TRAFFIC_KINDS entry is.
# Both ends are wider than the first version's (-0.5/0.85): the taxi has to
# cross the whole board in either direction within its window, and a surge
# that reads as reckless has to clearly out-run the traffic around it.
const TAXI_SPEED_MULT_MIN := -0.75
const TAXI_SPEED_MULT_MAX := 0.9
const TAXI_SPEED_RESPONSE := 2.2 # how fast speed_mult eases toward its target — this easing *is* the accelerating/braking
const TAXI_LEAVE_SPEED_MULT := -0.95 # floors it away up the road once the chaos window ends

# Roaming: where on the board the taxi is currently driving to. This replaces
# the old player-relative speed bias — see the header comment. Expressed as
# fractions of board_height, kept inside the visible board so the taxi never
# roams itself off the top edge into the shared despawn.
#
# TAXI_ROAM_GAIN converts "how far away that destination is" into a
# speed_mult, and is re-evaluated *every frame* rather than only at decision
# time. That continuous evaluation is load-bearing: it eases off as the taxi
# closes on its destination, which is what stops a full-throttle surge from
# sailing straight past the top of the board between two decisions.
const TAXI_ROAM_Y_MIN_FRAC := 0.1
const TAXI_ROAM_Y_MAX_FRAC := 0.85
const TAXI_ROAM_GAIN := 1.6 # 1/seconds — roughly how fast it wants to close the remaining distance
const TAXI_URGENCY_MIN := 0.5 # per-decision scalar on that gain, so some runs are a lunge and others a cruise
const TAXI_URGENCY_MAX := 1.0
const TAXI_FOLLOW_GAP := 30.0 # clear px it insists on keeping from the car ahead before it has to lift off
const TAXI_SIDE_GAP := 18.0 # clear px needed alongside before it'll merge — far tighter than traffic's LANE_CHANGE_SAFE_GAP, this driver squeezes
const TAXI_X_RESPONSE := 7.0 # in MAX_STEER_SPEED's ballpark — smooth, player-like lane changes, never an instant snap
const TAXI_MAX_STEER_SPEED := 520.0 # noticeably more aggressive than the player's own MAX_STEER_SPEED (460)
const TAXI_X_GAIN := 3.0
const TAXI_DECISION_INTERVAL_MIN := 0.45 # how often it re-rolls a new lane target, destination and signal behavior
const TAXI_DECISION_INTERVAL_MAX := 1.0
const TAXI_LANE_SWEEP_MAX := 3 # it may cut this many lanes across in one move, not just to the neighbouring one
# How far up its own lane the taxi looks when hunting for somewhere to go.
# Picking a lane at random is what left the first version tailgating: it
# spawns *behind* all the traffic and may not overtake within a lane (see
# _taxi_follow_limit), so its only way up the road is through the gaps
# between cars — and a driver looking for a gap aims at the gap. Scored
# lanes, not random ones, is what actually gets it onto the board.
const TAXI_HEADROOM_SCAN := 520.0
const TAXI_HEADROOM_RANDOM := 0.3 # of the time it ignores the best lane and just picks one, so gap-hunting never looks robotic
# Multiple taxis can land on one board at once (two rivals spending the skill
# in the same moment — see Main._on_opponent_skill_triggered, which is
# deliberately cumulative). They all spawn at the same y just off the bottom
# edge, so without a stagger they arrive overlapping each other, and each
# one's own car-following clamp then reads the other as a car it must not
# close on — both lift off and sit there, which looks exactly like the skill
# doing nothing. Each additional taxi in a wave is pushed a further
# TAXI_SPAWN_STAGGER_Y back and starts in a different lane.
# Small, and clamped against the despawn line below — the window between the
# taxi's spawn y and that line is only about 50px, and a stagger that
# overshoots it means the second taxi of a wave is culled by the shared
# obstacle loop on its very first frame, i.e. one rival's skill silently does
# nothing. Distinct spawn lanes are what actually keeps a wave from
# overlapping; this is only cosmetic separation on top of that.
const TAXI_SPAWN_STAGGER_Y := 22.0
const TAXI_SPAWN_CLEARANCE := 24.0 # breathing room at the spawn slot, so it doesn't arrive nose-to-tail either
const TAXI_SIGNAL_WARNING := 0.35 # short and erratic vs. real traffic's LANE_CHANGE_INDICATOR_WARNING (1.3s) — this driver barely warns at all
const TAXI_SIGNAL_TAIL := 0.2
const TAXI_TILT_MAX := 0.4

# Shared "a car just got destroyed" animation — used for the player's own
# crash and for a vehicle killed by tank crush/cannon fire (see
# _play_destruction_effect). Frames are cropped from a single spark ->
# fireball -> smoke reference sheet; a future skill that destroys cars a new
# way should pass its own frames/peak-width into _play_destruction_effect
# rather than editing this one, so each destruction method can look distinct.
const EXPLOSION_FRAMES := [
	preload("res://sprites/cars/explosion_1.png"),
	preload("res://sprites/cars/explosion_2.png"),
	preload("res://sprites/cars/explosion_3.png"),
	preload("res://sprites/cars/explosion_4.png"),
	preload("res://sprites/cars/explosion_5.png"),
	preload("res://sprites/cars/explosion_6.png"),
]
# Width, in source pixels, of the widest frame above (same
# measured-by-inspection convention as TANK_EFFECT_SOURCE_TANK_WIDTH) — the
# reference EXPLOSION_WORLD_SCALE is expressed against, so every frame's own
# varying size (small spark growing into a full fireball, then settling into
# smoke) scales proportionally instead of every frame filling the same
# on-screen size.
const EXPLOSION_SOURCE_PEAK_WIDTH := 313.0
const EXPLOSION_WORLD_SCALE := 1.5 # peak frame's on-screen width, relative to the destroyed vehicle's own width
const EXPLOSION_FRAME_DURATION := 0.055
const EXPLOSION_FADE_DURATION := 0.2

const TAP_WINDOW := 0.28 # max gap between taps to count as back-to-back

const DASH_DURATION := 0.14
const DASH_COOLDOWN := 0.18
const DASH_TILT := 0.55
const DASH_GHOST_INTERVAL := 0.03

const REVERSAL_THRESHOLD := 140.0 # |car_vx| needed before an opposite key-press counts as a drift
const DRIFT_COOLDOWN := 0.3
const DRIFT_GRIP_MULT := 0.48 # car_vx (actual momentum) approaches target this much slower
const DRIFT_NOSE_RESPONSE := 14.0 # how fast the car's facing/tilt snaps to the input direction
const DRIFT_MAX_TILT := 0.46 # nose can point further off than normal steering, but not extreme
const DRIFT_MARK_OFFSET := 0.22 # fraction of car width, rear-wheel track spacing
const DRIFT_TRAIL_WIDTH_FRAC := 0.16 # fraction of car width
const DRIFT_TRAIL_FADE_DELAY := 0.5
const DRIFT_TRAIL_FADE_DURATION := 0.6
# Grip (not the whole drift session) resolves once actual momentum has
# caught back up to the steering input, same as a real slide ending when
# traction returns — not just when you let go of the key. Without this,
# holding one direction after a flick keeps grip reduced forever, which
# reads as sticky/broken rather than a deliberate, catchable slide. This
# only affects `drift_sliding` (grip); the drift *session* (`is_drifting` —
# trail, nose lead) still persists across direction switches and only ends
# when both keys release, so a fresh reversal instantly re-catches the
# slide without a cooldown gap.
const DRIFT_CONVERGE_FRAC := 0.88 # car_vx / target_vx ratio at which grip returns to normal
# On a real keyboard, switching steering direction is almost never a single
# frame — there's a brief instant where both keys are released while a
# finger moves from one key to the other. Ending the session the moment
# target_vx hits 0 killed the trail/nose-lead every time a player tried to
# weave, which read as "drift stops when I change direction." This grace
# window lets the session survive a short release before actually ending it.
const DRIFT_RELEASE_GRACE := 0.14

# Boost charges while actively drifting (is_drifting, the whole session —
# not just drift_sliding grip loss, so weaving through a long S-turn keeps
# charging even during the brief moments grip has already caught up).
# Unlike a single "press to burn the whole bar" ability, boost is a
# hold-to-drain resource: holding key_confirm drains boost_charge at
# BOOST_DRAIN_PER_SECOND for as long as it's held and charge remains,
# letting the player spend anywhere from a quick tap to the whole bar and
# bank the rest for later. The speed multiplier is re-evaluated every frame
# from the *current* charge tier (see _boost_speed_mult), so a long burn
# starting from a full bar gets progressively weaker as it drains through
# the tiers — the fire dying down as the tank empties. Applied to
# current_speed() only, not elapsed itself, so the permanent difficulty
# ramp (spawn interval, base speed growth) is unaffected once boost ends.
const BOOST_FILL_PER_SECOND := 0.22 # ~4.5s of continuous drifting to fill from empty
const BOOST_DRAIN_PER_SECOND := 0.35 # a full bar sustains boost for ~2.9s held continuously
# Bar is split into three equal sections; a fuller bar gives a stronger
# boost. Multiplier is picked by _boost_speed_mult() from boost_charge.
const BOOST_TIER_LOW_MAX := 1.0 / 3.0
const BOOST_TIER_MID_MAX := 2.0 / 3.0
const BOOST_SPEED_MULT_LOW := 1.3
const BOOST_SPEED_MULT_MID := 1.5
const BOOST_SPEED_MULT_HIGH := 1.8
const BOOST_FLAME_INTERVAL := 0.035
const BOOST_BAR_WIDTH_FRAC := 0.5 # fraction of board_width
const BOOST_BAR_HEIGHT := 9.0
const BOOST_BAR_MARGIN_TOP := 14.0

# Sits just below the boost bar and the tank timer that tucks under it, so
# the bot tag never lands on top of either readout.
const BOT_TAG_Y := 49.0

@onready var road: Road = $Road
@onready var obstacle_container: Node2D = $ObstacleContainer
@onready var player_car: Car = $PlayerCar

const PLAYER_KIND := {"width_frac": 0.62, "height_frac": 1.69}

var car_x: float
var car_vx: float = 0.0
var elapsed: float = 0.0
var distance: float = 0.0
var spawn_timer: float = 0.0
var alive: bool = true
var active: bool = false

var last_tap_time: float = -999.0
var last_tap_direction: int = 0
# On a quick direction switch, players commonly press the new key slightly
# before releasing the old one — both keys read held for a frame or two.
# Treating that overlap as neutral zeroes out target_vx, which decelerates
# the car to a dead stop mid-switch instead of carrying into the new
# direction (this is what "drift stops when I change direction" actually
# was). Tie-break with whichever direction was pressed most recently.
var steer_priority: int = 0

var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_from: float = 0.0
var dash_to: float = 0.0
var dash_direction: int = 0
var dash_cooldown_timer: float = 0.0
var dash_ghost_timer: float = 0.0

var is_drifting: bool = false # whole drift session: trail + nose lead, persists across direction switches
var drift_sliding: bool = false # grip currently reduced within the session; resolves on convergence, re-arms on a fresh reversal
var drift_release_timer: float = 0.0 # counts down while both keys are released mid-session before the session actually ends
var drift_cooldown_timer: float = 0.0
var drift_trails: Array = [] # Line2D trails currently on screen (drifting or fading out)
var drift_trail_sides: Dictionary = {} # side(-1.0/1.0) -> Line2D, populated only while actively drifting

var boost_charge: float = 0.0 # 0..1, fills while is_drifting, drains while boost_active
var boost_active: bool = false # true while key_confirm is held and charge remains
var boost_flame_timer: float = 0.0

var skill_pickup_timer: float = 0.0
var choosing_skill: bool = false # true while a skill choice is up (round keeps running)
var skill_choice_pulse: float = 0.0 # drives the choice icons' breathing glow

var tank_mode_active: bool = false
var tank_mode_timer: float = 0.0
var cannon_ready: bool = true # false while a fired shell is still in flight — the shell's own travel time is the reload
var recoil_offset: float = 0.0 # world px currently punched back along y; decays toward 0 every frame
var recoil_timer: float = 0.0 # while > 0, current_speed() is dipped (see TANK_RECOIL_SPEED_MULT)
var fire_anim_tween: Tween = null

var active_taxis: Array[Car] = [] # taxis currently running riot on / leaving this board — see _spawn_taxi/_update_taxis. More than one at a time is normal: simultaneous rivals stack (see Main._on_opponent_skill_triggered).

const BOOST_TIER_BOUNDS: Array[float] = [0.0, BOOST_TIER_LOW_MAX, BOOST_TIER_MID_MAX, 1.0]

func _draw() -> void:
	var bar_w := board_width * BOOST_BAR_WIDTH_FRAC
	var bar_h := BOOST_BAR_HEIGHT
	var bar_x := (board_width - bar_w) * 0.5
	var bar_y := BOOST_BAR_MARGIN_TOP
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.0, 0.0, 0.0, 0.35), true)

	if boost_active:
		# While actively draining, the whole filled portion glows with the
		# current tier's heat — this is the "spend" readout, distinct from
		# the segmented "charge" readout below, so it reads as one flame
		# rather than three separate blocks mid-burn.
		var heat: float = (_boost_speed_mult() - BOOST_SPEED_MULT_LOW) / (BOOST_SPEED_MULT_HIGH - BOOST_SPEED_MULT_LOW)
		var fill_color: Color = Color(1.0, 0.55, 0.1, 0.95).lerp(Color(1.0, 0.9, 0.35, 0.95), heat)
		if boost_charge > 0.0:
			draw_rect(Rect2(bar_x, bar_y, bar_w * boost_charge, bar_h), fill_color, true)
	else:
		# Charging: each third of the bar is its own visibly distinct block
		# (progressively brighter shades of the player's own car color) so
		# the three unlockable speed tiers read as actual sections, not
		# just a plain fill with a couple of thin divider lines.
		var tier_shades: Array[Color] = [body_color.darkened(0.15), body_color.lightened(0.2), body_color.lightened(0.55)]
		var gap := 2.0
		for i in range(3):
			var seg_start: float = BOOST_TIER_BOUNDS[i]
			var seg_end: float = BOOST_TIER_BOUNDS[i + 1]
			var filled: float = clamp(boost_charge, seg_start, seg_end) - seg_start
			if filled <= 0.0:
				continue
			var seg_x: float = bar_x + bar_w * seg_start + (0.0 if i == 0 else gap * 0.5)
			var seg_w: float = bar_w * filled - (0.0 if i == 0 else gap * 0.5)
			draw_rect(Rect2(seg_x, bar_y, max(seg_w, 0.0), bar_h), tier_shades[i], true)

	for frac: float in [BOOST_TIER_LOW_MAX, BOOST_TIER_MID_MAX]:
		var divider_x: float = bar_x + bar_w * frac
		draw_line(Vector2(divider_x, bar_y - 1.0), Vector2(divider_x, bar_y + bar_h + 1.0), Color(0.0, 0.0, 0.0, 0.6), 1.5)
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(1.0, 1.0, 1.0, 0.25), false, 1.5)

	if tank_mode_active:
		_draw_tank_timer(bar_x, bar_y + bar_h, bar_w)

	if choosing_skill:
		_draw_skill_choice()

	if bot != null:
		var tag: String = "BOT · %s" % bot.difficulty_name()
		draw_string(ThemeDB.fallback_font, Vector2(0.0, BOT_TAG_Y), tag, HORIZONTAL_ALIGNMENT_CENTER, board_width, 13, Color(1.0, 1.0, 1.0, 0.45))

func _draw_tank_timer(bar_x: float, bar_top: float, bar_w: float) -> void:
	var bar_y := bar_top + TANK_BAR_GAP
	draw_rect(Rect2(bar_x, bar_y, bar_w, TANK_BAR_HEIGHT), Color(0.0, 0.0, 0.0, 0.35), true)
	var frac: float = clamp(tank_mode_timer / TANK_MODE_DURATION, 0.0, 1.0)
	draw_rect(Rect2(bar_x, bar_y, bar_w * frac, TANK_BAR_HEIGHT), Color(0.42, 0.5, 0.22, 0.95), true)
	draw_rect(Rect2(bar_x, bar_y, bar_w, TANK_BAR_HEIGHT), Color(1.0, 1.0, 1.0, 0.25), false, 1.5)

func _draw_skill_choice() -> void:
	var sz := car_size()
	var icon_r: float = road.lane_width() * SKILL_ICON_RADIUS_FRAC
	var offset_x: float = sz.x * SKILL_ICON_OFFSET_FRAC + icon_r
	var center_y: float = player_car.position.y
	var pulse: float = 0.9 + 0.1 * sin(skill_choice_pulse * 4.0)

	var left_x: float = clamp(player_car.position.x - offset_x, icon_r, board_width - icon_r)
	var right_x: float = clamp(player_car.position.x + offset_x, icon_r, board_width - icon_r)
	# A bot has no keys to prompt for, so it gets the icons without the key
	# captions — the pulse alone still reads as "a choice is live here".
	var opponent_label: String = "" if bot != null else OS.get_keycode_string(key_skill_opponent)
	var self_label: String = "" if bot != null else OS.get_keycode_string(key_skill_self)
	_draw_skill_icon(Vector2(left_x, center_y), icon_r * pulse, Color(0.92, 0.28, 0.28), opponent_label, false)
	_draw_skill_icon(Vector2(right_x, center_y), icon_r * pulse, Color(0.32, 0.82, 0.42), self_label, true)

func _draw_skill_icon(center: Vector2, r: float, color: Color, key_label: String, is_self: bool) -> void:
	draw_circle(center, r * 1.6, Color(color.r, color.g, color.b, 0.18))
	draw_circle(center, r, Color(color.r, color.g, color.b, 0.95))
	draw_circle(center, r, Color(1.0, 1.0, 1.0, 0.55), false, 2.0)
	if is_self:
		# Tank Mode is the only self skill so far, so its own pixel art
		# doubles as the choice glyph — once SELF_SKILLS has more than one
		# entry, this should show whichever skill the pool would actually
		# grant rather than always the tank.
		var tex_size: Vector2 = TANK_TEXTURE.get_size()
		var icon_h: float = r * 1.5
		var icon_w: float = icon_h * (tex_size.x / tex_size.y)
		var icon_rect := Rect2(center - Vector2(icon_w, icon_h) * 0.5, Vector2(icon_w, icon_h))
		draw_texture_rect(TANK_TEXTURE, icon_rect, false)
	else:
		# Taxi is the only opponent skill so far, so its own pixel art
		# doubles as the choice glyph — once OPPONENT_SKILLS has more than
		# one entry, this should show whichever skill the pool would
		# actually grant, same as the self/tank icon above.
		var tex_size: Vector2 = TAXI_TEXTURE.get_size()
		var icon_h: float = r * 1.5
		var icon_w: float = icon_h * (tex_size.x / tex_size.y)
		var icon_rect := Rect2(center - Vector2(icon_w, icon_h) * 0.5, Vector2(icon_w, icon_h))
		draw_texture_rect(TAXI_TEXTURE, icon_rect, false)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(center.x - 40.0, center.y + r + 22.0), key_label, HORIZONTAL_ALIGNMENT_CENTER, 80.0, 14, Color.WHITE)

func _ready() -> void:
	road.width = board_width
	road.height = board_height
	road.lane_count = lane_count
	player_car.area_entered.connect(_on_player_area_entered)
	if is_bot and bot == null:
		set_bot(true)

func set_vertical_margin(margin: float) -> void:
	vertical_margin = margin
	road.render_margin = margin
	road.queue_redraw()

func start_round() -> void:
	for child in obstacle_container.get_children():
		child.queue_free()

	player_car.body_color = body_color
	var sz := _car_size(PLAYER_KIND)
	player_car.set_size(sz.x, sz.y)
	if player_texture != null:
		player_car.set_texture(player_texture)
	player_car.rotation = 0.0
	player_car.modulate.a = 1.0

	car_x = board_width * 0.5
	car_vx = 0.0
	elapsed = 0.0
	distance = 0.0
	spawn_timer = spawn_interval()
	alive = true
	active = true
	last_tap_time = -999.0
	last_tap_direction = 0
	steer_priority = 0
	is_dashing = false
	dash_cooldown_timer = 0.0
	is_drifting = false
	drift_sliding = false
	drift_release_timer = 0.0
	drift_cooldown_timer = 0.0
	for line in drift_trails:
		if is_instance_valid(line):
			line.queue_free()
	drift_trails.clear()
	drift_trail_sides.clear()
	boost_charge = 0.0
	boost_active = false
	boost_flame_timer = 0.0
	skill_pickup_timer = randf_range(SKILL_PICKUP_INTERVAL_MIN, SKILL_PICKUP_INTERVAL_MAX)
	choosing_skill = false
	skill_choice_pulse = 0.0
	tank_mode_active = false
	tank_mode_timer = 0.0
	cannon_ready = true
	recoil_offset = 0.0
	recoil_timer = 0.0
	if fire_anim_tween != null and fire_anim_tween.is_valid():
		fire_anim_tween.kill()
	if fire_effect_sprite != null and is_instance_valid(fire_effect_sprite):
		fire_effect_sprite.queue_free()
	fire_effect_sprite = null
	# Any taxis in flight are already freed by the obstacle_container wipe
	# above (they're children of it, see _spawn_taxi) — just drop the stale
	# references so _update_taxis doesn't iterate freed nodes next round.
	active_taxis.clear()
	player_car.position = Vector2(car_x, board_height - sz.y * 0.5 - 24.0)
	road.distance = 0.0
	road.queue_redraw()
	# Otherwise the bot carries last round's target line (and a held
	# steering direction) into the first frame of this one.
	if bot != null:
		bot.reset()
	queue_redraw()

# Hands this board to BotDriver, or takes it back. Safe to call at any
# point in a round — the board itself is stateless about who is driving it,
# every input path below already goes through the same three functions.
func set_bot(enabled: bool, level: int = -1) -> void:
	is_bot = enabled
	# There is no key-up event coming for a virtual press, and a real key-up
	# won't be delivered to a bot-driven board either (see _unhandled_input),
	# so whoever was holding confirm has to be made to let go right here or
	# boost stays stuck on, draining with nothing able to stop it.
	_release_confirm()
	bot_steer = 0
	steer_priority = 0
	if enabled:
		bot = BotDriver.new(self, level if level >= 0 else GameSettings.bot_difficulty)
	else:
		bot = null
	queue_redraw()

# The one place "is this player steering left/right right now?" is answered,
# so a bot-driven board and a human-driven one run identical physics below —
# the only difference is where the two booleans came from.
func _steer_held(direction: int) -> bool:
	if bot != null:
		return bot_steer == direction
	return Input.is_physical_key_pressed(key_left if direction < 0 else key_right)

# What a steering key going down does, shared by the keyboard path and the
# bot. `register_tap` is what turns a double-tap into a dash; the bot passes
# false because it asks for dashes outright (see BotDriver._update_actions)
# and its own lane corrections would otherwise keep tripping the double-tap
# window by accident.
func _press_steer(direction: int, register_tap: bool = true) -> void:
	steer_priority = direction
	# Once a session is already running, any press keeps it going — the
	# REVERSAL_THRESHOLD gate only guards the *first* entry from normal
	# driving, where real built-up momentum is what "reversing against" means.
	if is_drifting or car_vx * float(direction) < -REVERSAL_THRESHOLD:
		_try_start_drift()
	if register_tap:
		_register_tap(direction)

func _press_confirm() -> void:
	# Tank Mode repurposes the confirm key entirely: it fires the cannon
	# instead of spending boost charge for the whole time the transform is
	# active (see _fire_cannon / _activate_tank_mode).
	if tank_mode_active:
		_fire_cannon()
	else:
		_try_activate_boost()

func _release_confirm() -> void:
	boost_active = false

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.echo:
		return
	# A bot-driven board ignores this player's bindings outright — BotDriver
	# owns every input path for it (see set_bot / _steer_held), and letting
	# stray keys through would mean the two fighting over the same car.
	if bot != null:
		return
	# Boost release is handled unconditionally, bypassing the gates below —
	# if it were gated behind is_dashing like everything else, releasing
	# key_confirm mid-dash would get swallowed and leave boost_active stuck
	# on (draining charge with no way to let go) until the next input event.
	if event.keycode == key_confirm and not event.pressed:
		_release_confirm()
		return
	if not active or not alive:
		return
	if not event.pressed:
		return
	# Skill-choice keys are deliberately separate from steering (key_left/
	# key_right) so picking one never interrupts driving — the round keeps
	# running the whole time, this is just a second input the player can tap
	# whenever it's convenient. Checked before the is_dashing gate below
	# since there's no reason a dash in progress should block a skill pick.
	if choosing_skill and event.keycode == key_skill_opponent:
		_resolve_skill_choice("opponent")
		return
	if choosing_skill and event.keycode == key_skill_self:
		_resolve_skill_choice("self")
		return
	if is_dashing:
		return
	if event.keycode == key_left:
		_press_steer(-1)
	elif event.keycode == key_right:
		_press_steer(1)
	elif event.keycode == key_confirm:
		_press_confirm()

func _register_tap(direction: int) -> void:
	# Same-direction double-tap triggers a dash. Drift is triggered
	# separately, straight off the car's actual momentum (see above).
	if direction == last_tap_direction and elapsed - last_tap_time <= TAP_WINDOW:
		_try_start_dash(direction)
		last_tap_time = -999.0
		return
	last_tap_time = elapsed
	last_tap_direction = direction

func _try_start_dash(direction: int) -> void:
	if is_dashing or is_drifting or dash_cooldown_timer > 0.0:
		return
	var bounds := steer_bounds()
	dash_from = car_x
	dash_to = clamp(car_x + direction * road.lane_width(), bounds.x, bounds.y)
	dash_direction = direction
	dash_timer = 0.0
	dash_ghost_timer = 0.0
	is_dashing = true
	car_vx = 0.0

func _try_start_drift() -> void:
	if is_dashing:
		return
	if is_drifting:
		# Already mid-session (e.g. weaving through an S-turn) — a fresh
		# reversal just re-catches the slide, no cooldown needed since the
		# trail/session never stopped.
		drift_sliding = true
		drift_release_timer = DRIFT_RELEASE_GRACE
		return
	if drift_cooldown_timer > 0.0:
		return
	is_drifting = true
	drift_sliding = true
	drift_release_timer = DRIFT_RELEASE_GRACE
	_begin_drift_trails()

func _collect_skill_pickup(pickup: SkillPickup) -> void:
	pickup.queue_free()
	# Also covers running over a second pickup before resolving the first —
	# the choice just re-triggers (resets the glow pulse) rather than
	# stacking or being ignored, since it never expired in the first place.
	choosing_skill = true
	skill_choice_pulse = 0.0

# category is "opponent" (left icon/key) or "self" (right icon/key). Self
# skills are picked from SELF_SKILLS and applied directly. Opponent skills
# are picked from OPPONENT_SKILLS but can't be applied here — this board has
# no reference to its rivals — so it just broadcasts the pick and lets Main
# relay it to everyone else (see the opponent_skill_triggered signal comment
# and receive_opponent_skill below).
func _resolve_skill_choice(category: String) -> void:
	choosing_skill = false
	if category == "self":
		var skill: String = SELF_SKILLS[randi() % SELF_SKILLS.size()]
		if skill == "tank":
			_activate_tank_mode()
	else:
		var skill: String = OPPONENT_SKILLS[randi() % OPPONENT_SKILLS.size()]
		opponent_skill_triggered.emit(skill)

# Entry point for an opponent skill some OTHER player picked, relayed here by
# Main (see opponent_skill_triggered). A crashed/inactive board still gets
# the signal but has nothing left to menace, so it's a no-op.
func receive_opponent_skill(skill: String) -> void:
	if not alive:
		return
	if skill == "taxi":
		_spawn_taxi()

func _try_activate_boost() -> void:
	if boost_active or boost_charge <= 0.0:
		return
	boost_active = true
	boost_flame_timer = 0.0

func _boost_speed_mult() -> float:
	if boost_charge > BOOST_TIER_MID_MAX:
		return BOOST_SPEED_MULT_HIGH
	elif boost_charge > BOOST_TIER_LOW_MAX:
		return BOOST_SPEED_MULT_MID
	else:
		return BOOST_SPEED_MULT_LOW

func _activate_tank_mode() -> void:
	# Re-triggering while already active (e.g. picking "self" again before
	# the timer runs out) just refreshes the full duration rather than
	# stacking — same "re-trigger, don't stack" rule the pickup itself
	# already follows for a re-collected choice (see _collect_skill_pickup).
	tank_mode_active = true
	tank_mode_timer = TANK_MODE_DURATION
	var sz := _car_size(TANK_KIND)
	player_car.set_size(sz.x, sz.y)
	player_car.set_texture(TANK_TEXTURE)

func _deactivate_tank_mode() -> void:
	tank_mode_active = false
	cannon_ready = true
	recoil_offset = 0.0
	recoil_timer = 0.0
	if fire_anim_tween != null and fire_anim_tween.is_valid():
		fire_anim_tween.kill()
	# Killing the tween above skips its final callback (_fade_out_fire_effect),
	# so if the transform ends mid-flash/mid-smoke the sprite would otherwise
	# never get freed — it'd just sit on screen forever, surviving even a
	# round restart, since nothing else ever revisits a stray child node here.
	if fire_effect_sprite != null and is_instance_valid(fire_effect_sprite):
		fire_effect_sprite.queue_free()
	fire_effect_sprite = null
	var sz := _car_size(PLAYER_KIND)
	player_car.set_size(sz.x, sz.y)
	if player_texture != null:
		player_car.set_texture(player_texture)

func _muzzle_position() -> Vector2:
	return player_car.position + Vector2(0.0, -_car_size(TANK_KIND).y * 0.5)

# Cannon fire: destroys the nearest vehicle ahead (smaller y — the direction
# traffic scrolls in from) roughly in the same lane as the player. "Roughly"
# because the player's own steering is momentum-based, not lane-snapped (see
# CLAUDE.md/PROJECT_STATE), so there's no lane index to match against
# directly — a half-lane-width x tolerance stands in for "same lane" instead.
# Gated by cannon_ready (cleared here, restored once the fired shell lands —
# see _spawn_shell) so mashing the key can't overlap shots.
func _fire_cannon() -> void:
	if not cannon_ready:
		return
	var target := _find_cannon_target()
	cannon_ready = false
	recoil_offset = TANK_RECOIL_KICK
	recoil_timer = TANK_RECOIL_DURATION
	_play_fire_animation()
	_spawn_shell(target)

func _find_cannon_target() -> Car:
	var half_lane: float = road.lane_width() * 0.5
	var target: Car = null
	var best_dy := INF
	for child in obstacle_container.get_children():
		if not (child is Car):
			continue
		if child.position.y >= player_car.position.y:
			continue
		if abs(child.position.x - player_car.position.x) > half_lane:
			continue
		var dy: float = player_car.position.y - child.position.y
		if dy < best_dy:
			best_dy = dy
			target = child
	return target

# Shared by cannon hits and tank-mode collisions ("crushed" instead of
# ending the round) — both are just "this traffic Car goes away with a
# burst of debris", the only difference is what triggers it.
func _destroy_vehicle(vehicle: Car) -> void:
	_play_destruction_effect(vehicle.position, vehicle.width)
	_spawn_debris(vehicle.position, vehicle.width)
	vehicle.queue_free()

# The shared "car destroyed" burst: cycles EXPLOSION_FRAMES centered on `pos`
# then fades, same standalone-overlay-sprite technique as the tank's fire
# effect (see _show_fire_effect_frame) rather than swapping a body texture.
# `frames`/`source_peak_width` default to the standard explosion so every
# current destruction path (crash, crush, cannon) looks the same today, but a
# future skill that destroys a car a different way can pass its own frame set
# here to get a distinct animation without touching this sequencing logic.
func _play_destruction_effect(pos: Vector2, vehicle_w: float, frames: Array = EXPLOSION_FRAMES, source_peak_width: float = EXPLOSION_SOURCE_PEAK_WIDTH) -> void:
	var sprite := Sprite2D.new()
	sprite.z_index = 6
	sprite.position = pos
	add_child(sprite)
	var world_scale: float = (vehicle_w * EXPLOSION_WORLD_SCALE) / source_peak_width
	var tw := create_tween()
	for frame: Texture2D in frames:
		tw.tween_callback(_show_destruction_frame.bind(sprite, frame, world_scale))
		tw.tween_interval(EXPLOSION_FRAME_DURATION)
	tw.tween_property(sprite, "modulate:a", 0.0, EXPLOSION_FADE_DURATION)
	tw.tween_callback(sprite.queue_free)

func _show_destruction_frame(sprite: Sprite2D, frame: Texture2D, world_scale: float) -> void:
	if not is_instance_valid(sprite):
		return
	sprite.texture = frame
	sprite.scale = Vector2(world_scale, world_scale)

# Muzzle flash -> smoke, played as a sequence of standalone overlay sprites
# (not part of the tank's own texture — see the TANK_FLASH_FRAMES/
# TANK_SMOKE_FRAMES comment) positioned at the barrel tip every step, so it
# stays glued to the tank through the recoil kick and fades out on its own
# rather than blocking the next shot.
func _play_fire_animation() -> void:
	if fire_anim_tween != null and fire_anim_tween.is_valid():
		fire_anim_tween.kill()
	fire_anim_tween = create_tween()
	for frame in TANK_FLASH_FRAMES:
		fire_anim_tween.tween_callback(_show_fire_effect_frame.bind(frame))
		fire_anim_tween.tween_interval(TANK_FLASH_FRAME_DURATION)
	for frame in TANK_SMOKE_FRAMES:
		fire_anim_tween.tween_callback(_show_fire_effect_frame.bind(frame))
		fire_anim_tween.tween_interval(TANK_SMOKE_FRAME_DURATION)
	fire_anim_tween.tween_callback(_fade_out_fire_effect)

var fire_effect_sprite: Sprite2D = null

func _show_fire_effect_frame(frame: Texture2D) -> void:
	if not tank_mode_active:
		return
	if fire_effect_sprite == null or not is_instance_valid(fire_effect_sprite):
		fire_effect_sprite = Sprite2D.new()
		fire_effect_sprite.z_index = 5
		add_child(fire_effect_sprite)
	var tex_size: Vector2 = frame.get_size()
	var fire_scale: float = _car_size(TANK_KIND).x / TANK_EFFECT_SOURCE_TANK_WIDTH
	fire_effect_sprite.texture = frame
	fire_effect_sprite.scale = Vector2(fire_scale, fire_scale)
	fire_effect_sprite.modulate.a = 1.0
	# Anchors the frame's own bottom-center (where it meets the barrel) at
	# the node's position instead of the frame's geometric center — offset
	# is in local pre-scale pixels, so this holds regardless of fire_scale.
	fire_effect_sprite.offset = Vector2(0.0, -tex_size.y * 0.5)
	fire_effect_sprite.position = _muzzle_position()

func _fade_out_fire_effect() -> void:
	if fire_effect_sprite == null or not is_instance_valid(fire_effect_sprite):
		return
	var sprite := fire_effect_sprite
	fire_effect_sprite = null
	var tw := create_tween()
	tw.tween_property(sprite, "modulate:a", 0.0, TANK_SMOKE_FADE_DURATION)
	tw.tween_callback(sprite.queue_free)

# The shell is a real traveling sprite, not an instant hit — it flies from
# the muzzle to the target (or off the top of the board if the cannon
# whiffed) and only destroys the target on arrival, so cause and effect read
# clearly instead of the vehicle vanishing the instant the key is pressed.
# cannon_ready is restored here (not when the fire animation ends), so the
# shell's own travel time is effectively the cannon's reload.
func _spawn_shell(target: Car) -> void:
	var shell := Sprite2D.new()
	shell.texture = TANK_SHELL_TEXTURE
	var tex_size: Vector2 = TANK_SHELL_TEXTURE.get_size()
	var shell_world_h: float = _car_size(TANK_KIND).x * 0.5
	var shell_scale: float = shell_world_h / tex_size.y
	shell.scale = Vector2(shell_scale, shell_scale)
	shell.z_index = 4
	shell.position = _muzzle_position()
	add_child(shell)

	var end_pos: Vector2
	if target != null and is_instance_valid(target):
		end_pos = target.position
	else:
		end_pos = Vector2(player_car.position.x, -_car_size(TANK_KIND).y - 40.0 - vertical_margin)

	# The shell's own art points "up" (angle -PI/2), so rotate it to face
	# wherever it's actually travelling rather than always straight up —
	# matters when the target isn't perfectly x-aligned with the muzzle.
	var travel_dir: Vector2 = end_pos - shell.position
	if travel_dir.length() > 0.001:
		shell.rotation = travel_dir.angle() + PI * 0.5

	var travel_dist: float = shell.position.distance_to(end_pos)
	var duration: float = clamp(travel_dist / TANK_SHELL_SPEED, TANK_SHELL_MIN_TRAVEL, TANK_SHELL_MAX_TRAVEL)
	var tw := create_tween()
	tw.tween_property(shell, "position", end_pos, duration)
	tw.tween_callback(_on_shell_arrived.bind(shell, target))

func _on_shell_arrived(shell: Sprite2D, target: Car) -> void:
	shell.queue_free()
	cannon_ready = true
	if target != null and is_instance_valid(target):
		_destroy_vehicle(target)

# Small procedural debris burst (same technique as the boost exhaust flames:
# a handful of tweened Polygon2D chips, no particle system/new art) fired
# outward from wherever a vehicle was destroyed.
func _spawn_debris(pos: Vector2, vehicle_w: float) -> void:
	for i in range(TANK_DEBRIS_COUNT):
		var s: float = vehicle_w * randf_range(0.12, 0.22)
		var chip := Polygon2D.new()
		chip.polygon = PackedVector2Array([Vector2(-s, -s), Vector2(s, -s), Vector2(0.0, s)])
		chip.color = Color(0.25, 0.22, 0.2, 0.95).lerp(Color(1.0, 0.55, 0.15, 0.95), randf())
		chip.position = pos
		chip.rotation = randf_range(0.0, TAU)
		chip.z_index = 6
		add_child(chip)
		var dir := Vector2.from_angle(randf_range(0.0, TAU))
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(chip, "position", pos + dir * vehicle_w * 1.4, TANK_DEBRIS_DURATION).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(chip, "modulate:a", 0.0, TANK_DEBRIS_DURATION)
		tw.tween_property(chip, "scale", Vector2(0.2, 0.2), TANK_DEBRIS_DURATION)
		tw.set_parallel(false)
		tw.tween_callback(chip.queue_free)

# Spawns one taxi behind the player (see the TAXI_ constants comment for why
# that means past board_height) and registers it in active_taxis so
# _update_taxis picks it up every frame from here on. It sets the same
# "lane"/"speed_mult" meta keys every other obstacle_container child sets —
# that's what makes the rest of the traffic systems (_lanes_used_near_top's
# spawn blocking, _lane_clear_near's merge check) see and avoid it like any
# other car, rather than it being an invisible exception weaving through them.
func _spawn_taxi() -> void:
	var sz := _car_size(TAXI_KIND)
	var taxi: Car = CAR_SCENE.instantiate()
	obstacle_container.add_child(taxi)
	taxi.set_meta("is_taxi", true)
	taxi.set_size(sz.x, sz.y)
	taxi.set_texture(TAXI_TEXTURE)
	taxi.z_index = 2 # reads clearly above ordinary traffic while it's actively weaving through it

	# Enters in a lane the player isn't in, so it never spawns already
	# overlapping them the instant it appears — and, when a whole wave of
	# taxis arrives at once, in a lane no taxi already queued behind is
	# using either. Lane-snapped rather than "player_x ± a lane width":
	# offsetting from the player put it at arbitrary x, which is half of how
	# the old one ended up loitering against a shoulder with no lane to call
	# its own.
	# Just far enough down to be fully off-screen (its top edge clears
	# board_height) without eating into the slack it has before the shared
	# loop's bottom despawn threshold — it needs room to weave up through
	# traffic, not to spawn already on the edge of being culled. Each taxi
	# already inbound pushes this one further back so a simultaneous wave
	# arrives as a string of cars rather than a single stack (see
	# TAXI_SPAWN_STAGGER_Y).
	var base_y: float = board_height + sz.y * 0.6 + 24.0 + vertical_margin
	var stagger: float = float(active_taxis.size()) * TAXI_SPAWN_STAGGER_Y
	var despawn_y: float = board_height + OBSTACLE_DESPAWN_MARGIN + vertical_margin
	var spawn_y: float = min(base_y + stagger, despawn_y - 30.0)

	# Which lane to come up in. Lane-snapped rather than "player_x ± a lane
	# width": offsetting from the player put the taxi at arbitrary x, which
	# is half of how the old one ended up loitering against a shoulder with
	# no lane to call its own.
	#
	# Scored rather than filtered, so there is always an answer — on a busy
	# board something has to give, and the weights are which constraint to
	# drop last. Clearance outranks avoiding another taxi's lane because the
	# strip the taxi spawns into is *below* the board, full of traffic on its
	# way to being culled, and spawning inside one of those cars is a visible
	# overlap from the very first frame; another taxi's registered lane may
	# be nowhere near the spawn point at all.
	var lanes: Array = []
	for i in range(lane_count):
		lanes.append(i)
	lanes.shuffle() # ties below break randomly rather than always favouring lane 0
	var player_lane := _nearest_lane(player_car.position.x)
	var taken := {}
	for other in active_taxis:
		if is_instance_valid(other):
			taken[int(other.get_meta("lane", -1))] = true
	var spawn_lane := 0
	var best_score := -1
	for l: int in lanes:
		var score := 0
		if l != player_lane:
			score += 4
		if _spawn_slot_clear(road.lane_center_x(l), spawn_y, sz):
			score += 2
		if not taken.has(l):
			score += 1
		if score > best_score:
			best_score = score
			spawn_lane = l
	var spawn_x: float = road.lane_center_x(spawn_lane)

	taxi.position = Vector2(spawn_x, spawn_y)

	taxi.set_meta("lane", spawn_lane)
	# Comes in already flat out, which is what "arrives from behind" means in
	# closing-fraction terms: negative = travelling faster than the player.
	taxi.set_meta("speed_mult", TAXI_SPEED_MULT_MIN)
	taxi.set_meta("tx_target_speed_mult", TAXI_SPEED_MULT_MIN)
	taxi.set_meta("tx_state", "chaos")
	taxi.set_meta("tx_chaos_timer", TAXI_CHAOS_DURATION)
	# First destination is well up the board, so it comes in overtaking and
	# immediately drives up into the traffic instead of settling on the
	# player's bumper.
	taxi.set_meta("tx_roam_y", board_height * TAXI_ROAM_Y_MIN_FRAC)
	taxi.set_meta("tx_urgency", TAXI_URGENCY_MAX)
	taxi.set_meta("tx_target_x", spawn_x)
	taxi.set_meta("tx_vx", 0.0)
	taxi.set_meta("tx_decision_timer", 0.0) # picks its first real move almost immediately
	taxi.set_meta("tx_signal_phase", "none") # none | warning | tail — see _update_taxi_signal
	taxi.set_meta("tx_signal_timer", 0.0)
	taxi.set_meta("tx_pending_target_x", spawn_x)
	active_taxis.append(taxi)

# Is the spawn slot at (x, y) free of any vehicle? Used only by _spawn_taxi.
# The taxi enters below the bottom edge, which is exactly where traffic on
# its way to the despawn line is sitting, and nothing else was stopping it
# from materialising inside one of those cars.
func _spawn_slot_clear(x: float, y: float, sz: Vector2) -> bool:
	for other in obstacle_container.get_children():
		if not (other is Car):
			continue
		if abs(other.position.x - x) >= (sz.x + other.width) * 0.5:
			continue
		if abs(other.position.y - y) < (sz.y + other.height) * 0.5 + TAXI_SPAWN_CLEARANCE:
			return false
	return true

func _nearest_lane(x: float) -> int:
	var best := 0
	var best_d := INF
	for lane in range(lane_count):
		var d: float = abs(road.lane_center_x(lane) - x)
		if d < best_d:
			best_d = d
			best = lane
	return best

# Runs each taxi's AI once per frame. Called from _process immediately BEFORE
# the shared obstacle-movement loop, because all this does is decide the
# taxi's speed_mult and lateral position for this frame — the actual forward
# movement is then performed by that shared loop, identically to every other
# vehicle on the board.
func _update_taxis(delta: float) -> void:
	for taxi in active_taxis:
		if is_instance_valid(taxi):
			_update_taxi_ai(taxi, delta)
	# Prunes both natural despawns (see _update_taxi_ai's off-the-top check)
	# and anything freed some other way (e.g. a tanked player crushing it via
	# the normal _destroy_vehicle collision path — see _on_player_area_entered
	# — which needs no special-casing here since it just frees the node).
	active_taxis = active_taxis.filter(func(t): return is_instance_valid(t))

func _update_taxi_ai(taxi: Car, delta: float) -> void:
	var sz := _car_size(TAXI_KIND)
	var state: String = taxi.get_meta("tx_state", "chaos")

	if state == "chaos":
		var timer: float = taxi.get_meta("tx_chaos_timer", 0.0) - delta
		if timer <= 0.0:
			taxi.set_meta("tx_state", "leaving")
			taxi.set_meta("tx_target_speed_mult", TAXI_LEAVE_SPEED_MULT)
			taxi.set_meta("tx_signal_phase", "none")
			taxi.stop_indicator()
		else:
			taxi.set_meta("tx_chaos_timer", timer)
			_update_taxi_decision(taxi, delta, sz)
			# Re-derived every frame, not just at decision time — see
			# TAXI_ROAM_GAIN for why that matters.
			taxi.set_meta("tx_target_speed_mult", _roam_speed_mult(taxi))
	else:
		# Leaving still has to pick lanes. Flooring it is not enough on its
		# own: the taxi may no more drive through the car in front on its way
		# out than it could on the way in, so an exit that only sets a speed
		# gets pinned behind traffic and the taxi loiters on the board until
		# the round kills it, with the "and then it screams off up the road"
		# beat simply never happening. It keeps gap-hunting; only the roam
		# destination is dropped, in favour of a flat full-throttle target.
		_update_taxi_decision(taxi, delta, sz)
		taxi.set_meta("tx_target_speed_mult", TAXI_LEAVE_SPEED_MULT)

	_update_taxi_signal(taxi, delta)
	_update_taxi_steering(taxi, delta, sz)

	# Ease speed_mult toward its target (the accelerate/decelerate), then let
	# the car-following limit have the final say — so however aggressive the
	# AI's intent is, it can never result in closing on the car in front.
	var mult: float = taxi.get_meta("speed_mult", 0.0)
	var target_mult: float = taxi.get_meta("tx_target_speed_mult", 0.0)
	mult += (target_mult - mult) * (1.0 - exp(-TAXI_SPEED_RESPONSE * delta))
	taxi.set_meta("speed_mult", _taxi_follow_limit(taxi, mult, sz))
	taxi.set_meta("lane", _nearest_lane(taxi.position.x))

	# Stuck behind someone: go looking for a gap now rather than waiting out
	# the rest of the decision interval. Without this the taxi patiently
	# tailgates whatever it caught up to — and since that car is itself
	# drifting back past the player, patience means being carried off the
	# bottom of the board and despawned, i.e. the skill quietly fizzling.
	if state == "chaos" and taxi.get_meta("tx_blocked", false):
		taxi.set_meta("tx_decision_timer", min(float(taxi.get_meta("tx_decision_timer", 0.0)), 0.15))

	if taxi.position.y < -sz.y - 80.0 - vertical_margin:
		taxi.queue_free()

# Car-following: the taxi may not close on a vehicle occupying the space it's
# moving into. speed_mult is a closing fraction of road speed, so "not
# closing" is just a bound on the mult relative to that other vehicle's own —
# match its mult and the gap between them stops shrinking (it tailgates).
# Lower mult = travelling further up the screen, hence the asymmetry below.
func _taxi_follow_limit(taxi: Car, mult: float, sz: Vector2) -> float:
	var blocked := false
	for other in obstacle_container.get_children():
		if other == taxi or not (other is Car):
			continue
		var other_w: float = other.width
		# 0.5, matching the actual sprite half-widths. This was 0.45, which
		# left a ~2.5px band where two cars genuinely overlap on screen but
		# the follow limit declined to see each other at all — so the taxi
		# would close longitudinally right through a car it was fractionally
		# offset from. Any lane-squeezing latitude has to come from
		# TAXI_SIDE_GAP, which is about *sideways* room; buying it here just
		# buys permission to overlap.
		if abs(other.position.x - taxi.position.x) > (sz.x + other_w) * 0.5:
			continue
		var other_mult: float = other.get_meta("speed_mult", 1.0)
		var dy: float = other.position.y - taxi.position.y
		var gap: float = abs(dy) - (sz.y + other.height) * 0.5
		if gap > TAXI_FOLLOW_GAP:
			continue
		if dy < 0.0:
			if other_mult > mult:
				blocked = true # having to lift off for a car ahead is what "stuck" means here
			mult = max(mult, other_mult) # something ahead (up the road) — can't travel up into it
		else:
			mult = min(mult, other_mult) # something behind — can't drop back into it
	taxi.set_meta("tx_blocked", blocked)
	return mult

# Periodically (every TAXI_DECISION_INTERVAL_MIN..MAX seconds while causing
# chaos) re-rolls what the taxi does next: somewhere new on the board to
# drive to (tx_roam_y + tx_urgency, which _roam_speed_mult turns into the
# accelerate/decelerate feel every frame) and a new lane, where it also picks
# one of three signal behaviors so the lane change doesn't always look the same:
# an honest warning, no warning at all, or a fakeout (signals one way, goes
# the other). The real target only ever lands in tx_target_x once the signal
# phase (if any) resolves — see _update_taxi_signal — so a fakeout's
# indicator is genuinely lit before the car commits to the opposite move.
func _update_taxi_decision(taxi: Car, delta: float, sz: Vector2) -> void:
	var t: float = taxi.get_meta("tx_decision_timer", 0.0) - delta
	if t > 0.0:
		taxi.set_meta("tx_decision_timer", t)
		return
	taxi.set_meta("tx_decision_timer", randf_range(TAXI_DECISION_INTERVAL_MIN, TAXI_DECISION_INTERVAL_MAX))
	# New destination up or down the board, and how hard it drives to get
	# there. The speed itself is derived from these every frame in
	# _roam_speed_mult, not rolled here.
	taxi.set_meta("tx_roam_y", _pick_taxi_roam_y())
	taxi.set_meta("tx_urgency", randf_range(TAXI_URGENCY_MIN, TAXI_URGENCY_MAX))

	var cur_x: float = taxi.position.x
	var cur_lane := _nearest_lane(cur_x)
	# Any lane within TAXI_LANE_SWEEP_MAX, not just the neighbouring one, and
	# always a real lane centre. The first version could only ever target
	# `cur_x ± one lane width` and then clamped that to the shoulder, so a
	# taxi that drifted wide had a target that resolved to roughly where it
	# already was — it would sit against the edge of the road looking parked.
	# Cutting three lanes at once is also just more alarming to be near.
	var candidates: Array = []
	for l in range(lane_count):
		if l != cur_lane and abs(l - cur_lane) <= TAXI_LANE_SWEEP_MAX:
			candidates.append(l)
	if candidates.is_empty():
		return
	candidates.shuffle()

	# Aim at the lane with the most open road ahead, most of the time. The
	# taxi may not drive through the car in front of it, so when it is
	# hemmed in, a randomly chosen lane is usually just a different car to
	# sit behind — which is exactly how the first version spent its whole
	# life pinned at the bottom edge of the board. TAXI_HEADROOM_RANDOM of
	# the time it picks arbitrarily anyway, so the weaving stays erratic
	# rather than looking like a solver.
	var target_lane: int = candidates[0]
	if randf() >= TAXI_HEADROOM_RANDOM:
		var best: float = -1.0
		for l: int in candidates:
			var room: float = _taxi_lane_headroom(taxi, l)
			if room > best:
				best = room
				target_lane = l

	# Committing to a lane that is momentarily blocked is fine and
	# deliberate: the steering gate re-checks safety every frame and simply
	# refuses to move sideways while something is actually alongside, so the
	# taxi ends up leaning on the gap and taking it the instant it opens,
	# instead of standing down for a whole decision cycle.
	var real_target_x: float = road.lane_center_x(target_lane)
	var real_dir: int = int(sign(real_target_x - cur_x))
	if real_dir == 0:
		return

	var roll := randf()
	if roll < 0.35:
		# Honest signal: warn, then actually go that way.
		_arm_taxi_signal(taxi, real_target_x, real_dir)
	elif roll < 0.65:
		# No signal at all — the lane change just starts immediately, no
		# warning, "switches lanes without any indicator."
		taxi.set_meta("tx_target_x", real_target_x)
		taxi.set_meta("tx_signal_phase", "none")
		taxi.stop_indicator()
	else:
		# The fakeout: light the OPPOSITE lamp, then actually go real_dir —
		# "signals right, turns left."
		_arm_taxi_signal(taxi, real_target_x, -real_dir)

# The speed the taxi wants *right now* in order to reach wherever it has
# decided to drive to (tx_roam_y). This is the whole up/down half of its
# behaviour, and it replaced a version that rolled a random speed biased to
# keep the taxi near the player's y — which is why the old one never went
# anywhere: every roll pulled it back to the same band of board.
#
# speed_mult is a closing fraction of road speed, so converting a distance
# into one is just "what fraction of the road's speed closes this gap in
# about 1/(gain*urgency) seconds". Negative = up the screen, matching the
# sign convention everywhere else. The clamp to the mult bounds is what makes
# a distant destination read as a flat-out surge, and the un-clamped tail as
# it arrives is what makes it settle instead of overshooting.
func _roam_speed_mult(taxi: Car) -> float:
	var dy: float = float(taxi.get_meta("tx_roam_y", taxi.position.y)) - taxi.position.y
	var urgency: float = taxi.get_meta("tx_urgency", TAXI_URGENCY_MAX)
	var speed: float = max(current_speed(), 1.0)
	return clamp(dy * TAXI_ROAM_GAIN * urgency / speed, TAXI_SPEED_MULT_MIN, TAXI_SPEED_MULT_MAX)

# Picks the next place on the board to drive to. Deliberately unweighted by
# where the player is: the taxi's job is to be loose in the traffic, and
# biasing this toward them is exactly what made the first version a
# tailgater. It ends up threatening them often regardless, because the
# player sits at the bottom of a board it now crosses end to end.
func _pick_taxi_roam_y() -> float:
	return board_height * randf_range(TAXI_ROAM_Y_MIN_FRAC, TAXI_ROAM_Y_MAX_FRAC)

func _arm_taxi_signal(taxi: Car, real_target_x: float, lamp_dir: int) -> void:
	taxi.set_meta("tx_pending_target_x", real_target_x)
	taxi.set_meta("tx_signal_phase", "warning")
	taxi.set_meta("tx_signal_timer", TAXI_SIGNAL_WARNING)
	taxi.start_indicator(lamp_dir)

# Clear road ahead (up the board, toward smaller y) in the given lane,
# measured from the taxi's own y and capped at TAXI_HEADROOM_SCAN. This is
# the taxi's "where can I actually get to" sense — see the call site in
# _update_taxi_decision. Cars behind it are irrelevant here: it is trying to
# make progress up the road, and something it has already passed cannot
# block that.
func _taxi_lane_headroom(taxi: Car, lane: int) -> float:
	var lane_x: float = road.lane_center_x(lane)
	var room: float = TAXI_HEADROOM_SCAN
	for other in obstacle_container.get_children():
		if other == taxi or not (other is Car):
			continue
		if abs(other.position.x - lane_x) > (taxi.width + other.width) * 0.5:
			continue
		var dy: float = taxi.position.y - other.position.y # >0 = other is ahead, up the road
		if dy < 0.0:
			continue
		room = min(room, max(0.0, dy - (taxi.height + other.height) * 0.5))
	return room

# Same spirit as _lane_clear_near, but measured against a target x and real
# sprite dimensions rather than a discrete lane index, since the taxi isn't
# lane-snapped. Uses TAXI_SIDE_GAP rather than traffic's much roomier
# LANE_CHANGE_SAFE_GAP (200px) deliberately: the taxi should squeeze into
# gaps a polite driver wouldn't touch, so the bar is "geometrically cannot
# overlap", not "comfortably clear". The taxi is only ever exempt from this
# with respect to the player — never toward the rest of the traffic.
func _taxi_target_clear(taxi: Car, target_x: float) -> bool:
	for other in obstacle_container.get_children():
		if other == taxi or not (other is Car):
			continue
		if abs(other.position.x - target_x) > (taxi.width + other.width) * 0.5:
			continue
		if abs(other.position.y - taxi.position.y) < (taxi.height + other.height) * 0.5 + TAXI_SIDE_GAP:
			return false
	return true

# warning -> commit the pending target (tx_target_x) and keep the lamp on for
# a short tail, same as it would after a real move; tail -> lamp off, done.
func _update_taxi_signal(taxi: Car, delta: float) -> void:
	var phase: String = taxi.get_meta("tx_signal_phase", "none")
	if phase == "none":
		return
	var t: float = taxi.get_meta("tx_signal_timer", 0.0) - delta
	if t > 0.0:
		taxi.set_meta("tx_signal_timer", t)
		return
	if phase == "warning":
		taxi.set_meta("tx_target_x", taxi.get_meta("tx_pending_target_x", taxi.position.x))
		taxi.set_meta("tx_signal_phase", "tail")
		taxi.set_meta("tx_signal_timer", TAXI_SIGNAL_TAIL)
	else:
		taxi.stop_indicator()
		taxi.set_meta("tx_signal_phase", "none")

# Lateral only — forward motion belongs to the shared obstacle loop (see the
# TAXI_ constants comment). Steering chases the current target through the
# same exponential velocity-approach shape the player's own steering uses
# (compare to the `car_vx += (target_vx - car_vx) * approach` line in
# _process) rather than the discrete eased t-over-duration slide ordinary
# lane-changing traffic uses — that continuous, momentum-carrying weave is
# what still makes it read as a car being driven at you rather than scenery.
func _update_taxi_steering(taxi: Car, delta: float, sz: Vector2) -> void:
	var shoulder := board_width * 0.06
	var min_x := shoulder + sz.x * 0.5
	var max_x := board_width - shoulder - sz.x * 0.5

	var target_x: float = clamp(taxi.get_meta("tx_target_x", taxi.position.x), min_x, max_x)

	var vx: float = taxi.get_meta("tx_vx", 0.0)
	var target_vx: float = clamp((target_x - taxi.position.x) * TAXI_X_GAIN, -TAXI_MAX_STEER_SPEED, TAXI_MAX_STEER_SPEED)
	vx += (target_vx - vx) * (1.0 - exp(-TAXI_X_RESPONSE * delta))
	var next_x: float = clamp(taxi.position.x + vx * delta, min_x, max_x)

	# Safety is a veto on *this frame's* sideways movement, checked against
	# where the taxi would actually end up — it is NOT a cancellation of
	# where it was going. The first version, on any blocked frame, wrote its
	# current x back into tx_target_x and gave up on the move until the next
	# decision. Traffic streams past a taxi doing -0.5 constantly, so almost
	# every lane change got aborted part-way, leaving it stranded between
	# lanes with no intent; that is most of what "it doesn't do much" was.
	# Holding the intent and only refusing the individual frame means it
	# leans on a closed gap and takes it the moment it opens.
	#
	# Checking next_x rather than the final target also covers the multi-lane
	# sweeps added in _update_taxi_decision: the car it must not hit while
	# crossing three lanes is the one in the middle lane, which never appears
	# at the target x at all.
	if _taxi_lateral_blocked(taxi, next_x):
		vx = 0.0
		next_x = taxi.position.x

	taxi.position.x = next_x
	taxi.set_meta("tx_vx", vx)

	taxi.rotation = clamp(vx / TAXI_MAX_STEER_SPEED, -1.0, 1.0) * TAXI_TILT_MAX

# True only if moving to next_x would *close on* a vehicle currently
# alongside — sharing this stretch of road longitudinally, so a sideways move
# could actually touch it.
#
# The "closes on it" half is what makes this safe to apply as a hard per-frame
# veto: a taxi that gets boxed in between two cars is already overlapping
# their lateral bands, and a plain "is this x clear" test would then veto
# every direction including its way out, welding it in place. Comparing the
# new separation against the current one means escaping is always permitted
# and only closing is refused.
func _taxi_lateral_blocked(taxi: Car, next_x: float) -> bool:
	for other in obstacle_container.get_children():
		if other == taxi or not (other is Car):
			continue
		if abs(other.position.y - taxi.position.y) >= (taxi.height + other.height) * 0.5 + TAXI_SIDE_GAP:
			continue # not alongside — there is nothing here to hit sideways
		var need: float = (taxi.width + other.width) * 0.5
		var cur_dx: float = abs(other.position.x - taxi.position.x)
		var next_dx: float = abs(other.position.x - next_x)
		if next_dx < need and next_dx < cur_dx:
			return true
	return false

func _car_size(kind_cfg: Dictionary) -> Vector2:
	var lw := road.lane_width()
	var w: float = lw * kind_cfg["width_frac"]
	return Vector2(w, w * kind_cfg["height_frac"])

# Whichever kind_cfg the player's own car currently is — TANK_KIND while
# transformed, PLAYER_KIND otherwise. Positioning/effects code that used to
# assume a fixed player size (dash clamp, drift trails, the skill-choice
# icon offset) reads this instead so they stay correct against the tank's
# larger footprint too.
func _current_kind() -> Dictionary:
	return TANK_KIND if tank_mode_active else PLAYER_KIND

# The player car's footprint right now. Was spelled out as
# _car_size(_current_kind()) in four places; BotDriver needs it too, to work
# out what actually fits in a gap.
func car_size() -> Vector2:
	return _car_size(_current_kind())

# The x range the player car is allowed to occupy, shoulders excluded — the
# clamp the steering block and the dash both land on. BotDriver aims inside
# the same range so it never commits to a line the car cannot hold.
func steer_bounds() -> Vector2:
	var shoulder := board_width * 0.06
	var half := car_size().x * 0.5
	return Vector2(shoulder + half, board_width - shoulder - half)

# Steering top speed in force right now — MAX_STEER_SPEED, cut down while
# transformed (a tank handles heavier). One function so the bot's sense of
# its own agility cannot drift out of sync with the physics it is driving.
func steer_top_speed() -> float:
	return MAX_STEER_SPEED * (TANK_STEER_SPEED_MULT if tank_mode_active else 1.0)

# How long the car keeps coasting sideways after the input stops: car_vx
# eases toward its target at STEER_RESPONSE per second, so 1/STEER_RESPONSE
# is the time constant. BotDriver steers against the position this predicts
# rather than the current one, which is what stops it hunting around a lane.
func steer_coast_time() -> float:
	return 1.0 / STEER_RESPONSE

# The shared ramp sets the baseline for how far into the round we are; the
# multipliers below it are this board's own temporary state, which is why
# they are applied here and not in SpeedRamp. Neither touches `elapsed`, so
# boosting or taking recoil never moves the permanent difficulty ramp.
func current_speed() -> float:
	var s := SpeedRamp.speed_at(elapsed)
	if boost_active:
		s *= _boost_speed_mult()
	if recoil_timer > 0.0:
		s *= TANK_RECOIL_SPEED_MULT
	return s

func spawn_interval() -> float:
	return SpeedRamp.spawn_interval_at(elapsed)

func _process(delta: float) -> void:
	if not active or not alive:
		return

	# The bot decides before anything below reads its decision: it sets
	# bot_steer (picked up by _steer_held in the steering block) and fires
	# off whatever dash/boost/skill action it wants, landing at exactly the
	# point in the frame a human's key events would already have landed.
	if bot != null:
		bot.tick(delta)

	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta
	if drift_cooldown_timer > 0.0:
		drift_cooldown_timer -= delta
	if choosing_skill:
		# The round never pauses for a skill choice and it never expires —
		# only the icons' glow keeps animating here; steering, traffic, and
		# everything else below runs exactly as normal for the rest of this
		# function. choosing_skill only clears in _resolve_skill_choice, once
		# the player actually picks one.
		skill_choice_pulse += delta
	if tank_mode_active:
		tank_mode_timer -= delta
		if tank_mode_timer <= 0.0:
			_deactivate_tank_mode()
	if recoil_timer > 0.0:
		recoil_timer -= delta
	recoil_offset = move_toward(recoil_offset, 0.0, TANK_RECOIL_RECOVERY_SPEED * delta)

	var sz := car_size()
	var tilt: float
	var max_steer_speed := steer_top_speed()

	if is_dashing:
		dash_timer += delta
		var t: float = clamp(dash_timer / DASH_DURATION, 0.0, 1.0)
		var eased: float = 1.0 - pow(1.0 - t, 3)
		car_x = lerp(dash_from, dash_to, eased)
		tilt = DASH_TILT * dash_direction * (1.0 - t)

		dash_ghost_timer -= delta
		if dash_ghost_timer <= 0.0:
			dash_ghost_timer = DASH_GHOST_INTERVAL
			_spawn_dash_ghost()

		if t >= 1.0:
			is_dashing = false
			dash_cooldown_timer = DASH_COOLDOWN
	else:
		# Steering top speed never changes — drifting is about losing grip,
		# not going faster. Only how quickly the car's actual momentum
		# (car_vx) can catch up to the input direction changes.
		var left := _steer_held(-1)
		var right := _steer_held(1)
		var target_vx := 0.0
		if left and right:
			# Both keys read held during the brief overlap of a fast
			# direction switch — go with whichever was pressed last instead
			# of treating it as neutral (see steer_priority above).
			target_vx = float(steer_priority) * max_steer_speed
		elif left:
			target_vx = -max_steer_speed
		elif right:
			target_vx = max_steer_speed

		# The drift session persists as long as you keep steering in some
		# direction — switching left/right mid-drift keeps it going. It ends
		# once both keys have stayed released for DRIFT_RELEASE_GRACE, not
		# the instant they do — a brief release while a finger travels from
		# one key to the other shouldn't cut the session short.
		if is_drifting:
			if target_vx == 0.0:
				drift_release_timer -= delta
				if drift_release_timer <= 0.0:
					_end_drift()
			else:
				drift_release_timer = DRIFT_RELEASE_GRACE

		var grip := STEER_RESPONSE * (DRIFT_GRIP_MULT if drift_sliding else 1.0)
		var approach := 1.0 - exp(-grip * delta)
		car_vx += (target_vx - car_vx) * approach

		# Grip alone (not the session) returns to normal once actual
		# momentum has caught back up to the steering input — a slide
		# that's been caught snaps back to precise control instead of
		# staying loose for as long as you keep holding the key. If you
		# reverse again, _try_start_drift() re-arms drift_sliding without
		# ending the session, so the trail/nose lead never interrupts.
		if drift_sliding and target_vx != 0.0 and sign(car_vx) == sign(target_vx) and abs(car_vx) >= abs(target_vx) * DRIFT_CONVERGE_FRAC:
			drift_sliding = false

		var bounds := steer_bounds()
		var next_x := car_x + car_vx * delta
		if next_x < bounds.x:
			car_x = bounds.x
			car_vx = 0.0
		elif next_x > bounds.y:
			car_x = bounds.y
			car_vx = 0.0
		else:
			car_x = next_x

		if is_drifting:
			# Nose points where you're steering, well ahead of where the car
			# is actually still travelling — that gap is the slide.
			var nose_target: float = sign(target_vx) * DRIFT_MAX_TILT if target_vx != 0.0 else player_car.rotation
			tilt = move_toward(player_car.rotation, nose_target, DRIFT_NOSE_RESPONSE * delta)

			_update_drift_trails(sz.x)
		else:
			tilt = clamp(car_vx / max_steer_speed, -1.0, 1.0) * MAX_TILT

	player_car.rotation = tilt
	player_car.position = Vector2(car_x, board_height - sz.y * 0.5 - 24.0 + recoil_offset)

	elapsed += delta
	distance += current_speed() * delta
	road.distance = distance
	road.queue_redraw()

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = spawn_interval()
		_spawn_obstacle()

	skill_pickup_timer -= delta
	if skill_pickup_timer <= 0.0:
		skill_pickup_timer = randf_range(SKILL_PICKUP_INTERVAL_MIN, SKILL_PICKUP_INTERVAL_MAX)
		_spawn_skill_pickup()

	var speed := current_speed()
	# Taxis only *decide* here — they set their own speed_mult and steer
	# laterally, then get moved forward by the shared loop below on the exact
	# same line as every other vehicle. Deliberately not a separate movement
	# path: see the TAXI_ constants comment for why driving their own y made
	# them phase through traffic.
	_update_taxis(delta)

	for child in obstacle_container.get_children():
		var speed_mult: float = child.get_meta("speed_mult", 1.0)
		child.position.y += speed * speed_mult * delta
		_update_obstacle_lane_change(child, delta)
		if child.position.y > board_height + OBSTACLE_DESPAWN_MARGIN + vertical_margin:
			child.queue_free()

	for line in drift_trails:
		if is_instance_valid(line):
			for i in line.get_point_count():
				line.set_point_position(i, line.get_point_position(i) + Vector2(0, speed * delta))
	drift_trails = drift_trails.filter(func(l): return is_instance_valid(l))

	if boost_active:
		boost_charge = max(0.0, boost_charge - BOOST_DRAIN_PER_SECOND * delta)
		boost_flame_timer -= delta
		if boost_flame_timer <= 0.0:
			# Higher tiers burn hotter, so flames spawn more often too.
			boost_flame_timer = BOOST_FLAME_INTERVAL / _boost_speed_mult()
			_spawn_boost_flame(sz)
		if boost_charge <= 0.0:
			boost_active = false # ran out of charge; holding key_confirm does nothing further
	elif is_drifting:
		boost_charge = min(1.0, boost_charge + BOOST_FILL_PER_SECOND * delta)

	queue_redraw()

func _spawn_dash_ghost() -> void:
	if player_car.sprite.texture == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = player_car.sprite.texture
	ghost.scale = player_car.sprite.scale
	ghost.rotation = player_car.rotation
	ghost.position = player_car.position
	ghost.modulate = Color(1.0, 1.0, 1.0, 0.4)
	ghost.z_index = -1
	add_child(ghost)
	var tw := create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, 0.22)
	tw.tween_callback(ghost.queue_free)

func _spawn_boost_flame(sz: Vector2) -> void:
	# Small procedural flame tris (no particle system, matching the rest of
	# this project's effects) shot out from the rear of the car, tinted
	# toward the player's own car color rather than a flat fire palette so
	# the exhaust reads as "this player's" boost, not a generic effect.
	# Size and heat scale with the current tier (see _boost_speed_mult) so
	# the flame visibly dies down as a long burn drains through the tiers.
	# The hot core is the player's own hue pushed to full brightness (not a
	# fixed fire-orange) so e.g. the yellow car's boost reads as yellow, the
	# blue car's as blue, etc. — each player's flame stays recognizably theirs.
	var heat: float = (_boost_speed_mult() - BOOST_SPEED_MULT_LOW) / (BOOST_SPEED_MULT_HIGH - BOOST_SPEED_MULT_LOW)
	var flame := Polygon2D.new()
	var flame_w: float = sz.x * randf_range(0.18, 0.28) * (1.0 + heat * 0.6)
	var flame_h: float = flame_w * randf_range(1.5, 2.1)
	flame.polygon = PackedVector2Array([
		Vector2(-flame_w * 0.5, 0.0), Vector2(flame_w * 0.5, 0.0), Vector2(0.0, flame_h),
	])
	var hot_core: Color = Color.from_hsv(body_color.h, body_color.s, 1.0)
	flame.color = body_color.lerp(hot_core, 0.35 + heat * 0.35)
	var offset_x: float = randf_range(-sz.x * 0.18, sz.x * 0.18)
	flame.position = player_car.position + Vector2(offset_x, sz.y * 0.42)
	flame.rotation = player_car.rotation + randf_range(-0.12, 0.12)
	flame.z_index = -1
	add_child(flame)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(flame, "position:y", flame.position.y + flame_h * 2.4, 0.26).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(flame, "scale", Vector2(0.25, 0.25), 0.26)
	tw.tween_property(flame, "modulate:a", 0.0, 0.26)
	tw.set_parallel(false)
	tw.tween_callback(flame.queue_free)

func _end_drift() -> void:
	is_drifting = false
	drift_sliding = false
	drift_cooldown_timer = DRIFT_COOLDOWN
	for side in drift_trail_sides.keys():
		var line: Line2D = drift_trail_sides[side]
		var tw := create_tween()
		tw.tween_interval(DRIFT_TRAIL_FADE_DELAY)
		tw.tween_property(line, "modulate:a", 0.0, DRIFT_TRAIL_FADE_DURATION)
		tw.tween_callback(line.queue_free)
	drift_trail_sides.clear()

func _begin_drift_trails() -> void:
	var sz := _car_size(_current_kind())
	for side in [-1.0, 1.0]:
		var line := Line2D.new()
		line.width = sz.x * DRIFT_TRAIL_WIDTH_FRAC
		line.default_color = Color(0.05, 0.05, 0.05, 0.7)
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.antialiased = true
		line.z_index = -2
		add_child(line)
		drift_trails.append(line)
		drift_trail_sides[side] = line
	# Lay down the first point immediately so a drift that ends within a
	# single frame still leaves a visible dot rather than a bare line with
	# no points.
	_update_drift_trails(sz.x)

func _update_drift_trails(car_w: float) -> void:
	var sz := _car_size(_current_kind())
	var rear_y: float = player_car.position.y + sz.y * 0.28
	for side in drift_trail_sides.keys():
		var line: Line2D = drift_trail_sides[side]
		var mark_x: float = player_car.position.x + side * car_w * DRIFT_MARK_OFFSET
		line.add_point(Vector2(mark_x, rear_y))

# Shared by traffic spawning and skill-pickup spawning so neither ever drops
# a new node into a lane something else already occupies near the top of the
# board — pickups and traffic both live in obstacle_container and both set
# a "lane" meta key, so this one scan covers both kinds of children.
func _lanes_used_near_top() -> Array:
	var used: Array = []
	for child in obstacle_container.get_children():
		if child.position.y < 190.0:
			used.append(child.get_meta("lane"))
	return used

func _spawn_obstacle() -> void:
	var used_lanes := _lanes_used_near_top()
	var available: Array = []
	for lane in range(lane_count):
		if not used_lanes.has(lane):
			available.append(lane)
	if available.is_empty():
		return

	var lane: int = available[randi() % available.size()]
	var kind_cfg := _pick_traffic_kind()
	var obstacle: Car = CAR_SCENE.instantiate()
	obstacle_container.add_child(obstacle)
	var sz := _car_size(kind_cfg)
	obstacle.set_size(sz.x, sz.y)
	var textures: Array = kind_cfg["textures"]
	obstacle.set_texture(textures[randi() % textures.size()])
	var frac_min: float = kind_cfg.get("speed_frac_min", 0.55)
	var frac_max: float = kind_cfg.get("speed_frac_max", 0.85)
	obstacle.set_meta("lane", lane)
	obstacle.set_meta("speed_mult", randf_range(frac_min, frac_max))
	obstacle.position = Vector2(road.lane_center_x(lane), -sz.y - 40.0 - vertical_margin)
	_maybe_flag_lane_change(obstacle)

func _spawn_skill_pickup() -> void:
	var used_lanes := _lanes_used_near_top()
	var available: Array = []
	for lane in range(lane_count):
		if not used_lanes.has(lane):
			available.append(lane)
	if available.is_empty():
		return

	var lane: int = available[randi() % available.size()]
	var pickup: SkillPickup = SKILL_PICKUP_SCENE.instantiate()
	obstacle_container.add_child(pickup)
	pickup.set_radius(road.lane_width() * SKILL_PICKUP_RADIUS_FRAC)
	pickup.set_meta("lane", lane)
	# Scrolls at exactly the road's own rate (a fixed marking), not a
	# vehicle's own forward speed — see the TRAFFIC_KINDS speed_frac comment
	# in GameSettings.gd for why 1.0 would be wrong for an actual vehicle,
	# but is exactly right for something painted on/embedded in the road.
	pickup.set_meta("speed_mult", 1.0)
	pickup.position = Vector2(road.lane_center_x(lane), -pickup.radius - 40.0 - vertical_margin)

func _maybe_flag_lane_change(obstacle) -> void:
	if lane_count <= 1:
		return
	if randf() > LANE_CHANGE_CHANCE:
		return
	var min_y: float = board_height * LANE_CHANGE_TRIGGER_Y_MIN_FRAC
	var max_y: float = board_height * LANE_CHANGE_TRIGGER_Y_MAX_FRAC
	obstacle.set_meta("lc_state", "pending")
	obstacle.set_meta("lc_trigger_y", randf_range(min_y, max_y))

# Small state machine driven once per frame per obstacle from the movement
# loop above: pending (waiting to reach its trigger y) -> warning (indicator
# blinking, not yet moving) -> moving (sliding to the new lane center) ->
# settled (still blinking briefly after arriving, like a real signal) -> idle.
func _update_obstacle_lane_change(obstacle, delta: float) -> void:
	var state: String = obstacle.get_meta("lc_state", "idle")
	if state == "idle":
		return

	if state == "pending":
		if obstacle.position.y >= obstacle.get_meta("lc_trigger_y", 0.0):
			var cur_lane: int = obstacle.get_meta("lane", 0)
			var dir := _pick_lane_change_direction(obstacle, cur_lane)
			if dir == 0:
				obstacle.set_meta("lc_state", "idle") # no safe lane right now; skip this one
				return
			var new_lane: int = cur_lane + dir
			# Reserve the target lane immediately (not just once the slide
			# finishes) so other spawns/lane-changes treat it as taken for
			# the whole maneuver, matching how _spawn_obstacle already reads
			# the "lane" meta for its own used-lane check.
			obstacle.set_meta("lane", new_lane)
			obstacle.set_meta("lc_from_x", obstacle.position.x)
			obstacle.set_meta("lc_to_x", road.lane_center_x(new_lane))
			obstacle.set_meta("lc_timer", 0.0)
			obstacle.set_meta("lc_state", "warning")
			obstacle.start_indicator(dir)
		return

	if state == "warning":
		var t: float = obstacle.get_meta("lc_timer", 0.0) + delta
		if t >= LANE_CHANGE_INDICATOR_WARNING:
			obstacle.set_meta("lc_timer", 0.0)
			obstacle.set_meta("lc_state", "moving")
		else:
			obstacle.set_meta("lc_timer", t)
		return

	if state == "moving":
		var t: float = obstacle.get_meta("lc_timer", 0.0) + delta
		var frac: float = clamp(t / LANE_CHANGE_DURATION, 0.0, 1.0)
		var eased: float = frac * frac * (3.0 - 2.0 * frac) # smoothstep, eases in and out of the merge
		var from_x: float = obstacle.get_meta("lc_from_x", obstacle.position.x)
		var to_x: float = obstacle.get_meta("lc_to_x", obstacle.position.x)
		obstacle.position.x = lerp(from_x, to_x, eased)
		if frac >= 1.0:
			obstacle.set_meta("lc_state", "settled")
			obstacle.set_meta("lc_timer", 0.0)
		else:
			obstacle.set_meta("lc_timer", t)
		return

	if state == "settled":
		var t: float = obstacle.get_meta("lc_timer", 0.0) + delta
		if t >= LANE_CHANGE_INDICATOR_TAIL:
			obstacle.stop_indicator()
			obstacle.set_meta("lc_state", "idle")
		else:
			obstacle.set_meta("lc_timer", t)
		return

func _pick_lane_change_direction(obstacle, cur_lane: int) -> int:
	var candidates: Array = []
	if cur_lane > 0:
		candidates.append(-1)
	if cur_lane < lane_count - 1:
		candidates.append(1)
	candidates.shuffle()
	for dir in candidates:
		var target_lane: int = cur_lane + dir
		if _lane_clear_near(obstacle, target_lane):
			return dir
	return 0

func _lane_clear_near(obstacle, lane: int) -> bool:
	for other in obstacle_container.get_children():
		if other == obstacle:
			continue
		if int(other.get_meta("lane", -1)) != lane:
			continue
		if abs(other.position.y - obstacle.position.y) < LANE_CHANGE_SAFE_GAP:
			return false
	return true

func _pick_traffic_kind() -> Dictionary:
	var kinds: Array = GameSettings.TRAFFIC_KINDS
	var total := 0
	for k in kinds:
		total += int(k["weight"])
	var r := randi() % total
	for k in kinds:
		r -= int(k["weight"])
		if r < 0:
			return k
	return kinds[0]

func _on_player_area_entered(area: Area2D) -> void:
	if area is SkillPickup:
		_collect_skill_pickup(area)
		return
	if tank_mode_active:
		# Invincible: a vehicle the tank body touches is crushed instead of
		# ending the round — the same "vehicle goes away" outcome as a
		# cannon hit, just triggered by a collision instead of a shot.
		_destroy_vehicle(area as Car)
		return
	if not alive:
		return
	alive = false
	active = false
	_play_destruction_effect(player_car.position, car_size().x)
	player_car.modulate.a = 0.35
	crashed.emit()
