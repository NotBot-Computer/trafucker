extends RefCounted
class_name TowerSkill

## Base class for a Pile Up skill written as its own file.
##
## This is Pile Up's counterpart to Don't Crash's `SkillEffect`, built on the
## same reasoning (see that file's header): a skill is a plain RefCounted, not
## a Node. It never ticks itself and never draws itself — `TowerMode` owns the
## turn loop and the canvases and calls the hooks below at the points in its
## own frame where they are correct. What is different is the *clock*. Don't
## Crash's skills run on seconds; this mode is turn-based, so a Pile Up skill
## runs on **turns of one player**, and everything about its lifecycle is
## phrased that way.
##
## ## Two categories, two moments
##
## `TowerMode` grants a skill by *charge*: a player earns one after
## CHARGE_TO_SKILL clean placements (a brick that landed and dropped nothing),
## into whichever of their two slots is empty — one for a `self` skill, one
## for an `opponent` skill. Each slot has its own cast key
## (`GameSettings.PLAYER_CONFIGS[slot]["cast_self"]` / `["cast_opponent"]`),
## and both may only be pressed **during the caster's own piloting**, i.e.
## while their brick is in the air. What happens next depends on the category:
##
##   * **self** — the effect attaches to the *caster*, and `activate()` runs
##     immediately, mid-descent, with `mode.active_piece` being the caster's
##     own held brick. It lasts for the rest of this turn (and further turns
##     of the caster's if `duration_turns()` > 1).
##   * **opponent** — the effect is *queued* against the next living player
##     (or every other living player, if `affects_all_opponents()` is true —
##     one instance per target), and `activate()` runs at the start of that
##     player's next turn, right after their brick has been spawned and
##     `mode.active_piece` points at it. It lasts for `duration_turns()` of
##     the *target's* turns. The tower is shared and the fault rule scores a
##     turn's falls against whoever is on the clock, so a hex that lands on
##     the target's turn costs the target — that is the whole point of the
##     timing, and why an opponent skill is never applied to the tower during
##     the caster's own turn.
##
## ## LIFECYCLE, in the order TowerMode calls it
##
##   setup(mode, id, caster, target)  ->  turns_left = duration_turns()
##   ADDED to mode.active_effects  ->  activate()
##   ... every physics frame of the target's turns:  tick(delta)
##   ... when the target's brick is handed to physics:  on_release(piece)
##   ... at the start of each further turn of the target's:  on_turn_start()
##   ... when the target's turn resolves:  on_turn_end()  ->  turns_left -= 1
##   ... when turns_left reaches 0:  REMOVED from active_effects  ->  deactivate()
##
## The capitalised steps are the contract that makes the hooks usable from the
## lifecycle calls, exactly as in SkillEffect: inside activate()/tick() the
## mode already counts this effect (so a `descend_speed_mult()` claim is live
## the frame it is made), and inside deactivate() it no longer does.
##
## deactivate() is ALSO called, on every live effect and every queued one,
## when a match restarts (`_start_match`), when it ends (`_end_match`), and
## when the target is eliminated. It MUST be idempotent and MUST leave the
## mode exactly as it found it. The one thing a skill is allowed to leave
## behind is *tower state* — a brick it made heavy stays heavy, a joint it
## added between two landed bricks may stay — because the tower is the shared
## board and outlives every turn. Anything else (a node added anywhere other
## than under `mode.pieces`, a changed `Engine.time_scale`, a moved camera
## zoom, a multiplier still claimed) is a leak, and `TowerSkillProbe` checks
## for exactly those.
##
## ## What a skill may reach
##
## `mode` is the live `TowerMode`, untyped for the same cyclic-reference
## reason `SkillEffect.board` is (TowerMode names this class). The useful
## surface, all of it read freely and some of it written with care:
##
##   mode.active_piece        the held brick (TowerPiece) — null between turns
##   mode.active_slot         whose turn it is
##   mode.pieces              Node2D holding every landed brick (RigidBody2D)
##   mode.stack_top_y         the tower's highest point (world y, -up)
##   mode.aim_x / aim_steps   the commanded position and quarter-turns
##   mode._command_move(dir, cells)   steer the held brick, on the lattice —
##                            the right way to "push" it; never write its
##                            position directly (it is shape-queried)
##   mode.CELL, PLATFORM_CELLS, LOST_Y, DESCEND_SPEED ...   the constants
##   mode.camera, mode.hud    for a shake, a toast (hud.show_message)
##   mode._slot_color(slot)   a player's colour
##
## Do NOT write `active_piece.global_position` — every move a held brick makes
## is permission-checked against the tower and the lattice, and a skill that
## teleports it can put it inside the stack. Do NOT touch `Engine.time_scale`
## or `PhysicsServer2D` gravity (a leak the probe cannot fully see; and it
## affects the countdown and the HUD). Do NOT reach into another player's
## slots or charge. A landed brick under `mode.pieces` is fair game:
## `mass`, `physics_material_override`, `apply_impulse()`, joints.
##
## ## The lattice
##
## `brick_scale()` resizes the target's *next* brick at spawn. Every command
## in this mode lands on a half-cell lattice and the aim clamp assumes a
## brick's half-width is a whole number of half-cells — which holds only if
## `cols * scale` is an integer for every brick in the set. 2.0 is safe; 1.5
## and 0.5 are not (odd `cols`). If you want a smaller brick, override
## `spawn_index_override()` and hand them a small shape instead.

# The mode (TowerMode), the caster's slot, and the slot the effect is
# attached to — the caster for a self skill, the victim for an opponent one.
var mode = null
var id: String = ""
var caster: int = -1
var target: int = -1
var turns_left: int = 1

# Called by TowerMode immediately after .new(), before activate(). Kept
# separate from _init so a subclass never has to redeclare a constructor.
func setup(p_mode, p_id: String, p_caster: int, p_target: int) -> void:
	mode = p_mode
	id = p_id
	caster = p_caster
	target = p_target

# --- The clock --------------------------------------------------------------

# How many of the target's turns the effect lasts. 1 means "this turn" for a
# self skill and "their next turn" for an opponent skill. 0 is an instant:
# activate() runs and the effect is finished in the same call.
func duration_turns() -> int:
	return 1

# Opponent skills only. false (default): the next living player after the
# caster. true: every other living player, one instance each.
func affects_all_opponents() -> bool:
	return false

func is_done() -> bool:
	return turns_left <= 0

# --- Lifecycle --------------------------------------------------------------

# Everything the skill does at the moment it becomes live. Runs exactly once.
# `mode.active_piece` is the target's held brick (self: mid-descent;
# opponent: freshly spawned).
func activate() -> void:
	pass

# Per physics frame while live, during the target's turns only — piloting,
# settling and resolving alike. `mode.state` says which.
func tick(_delta: float) -> void:
	pass

# The target has started another turn under this effect (never called for
# the turn activate() ran in). `mode.active_piece` is their new brick.
func on_turn_start() -> void:
	pass

# The target's brick has just been handed to the physics engine, at rest,
# exactly where it stopped. `piece` is that brick — it is now an ordinary
# RigidBody2D in the tower. mass_mult()/friction_override()/
# gravity_scale_mult() have already been applied by the time this runs.
func on_release(_piece) -> void:
	pass

# The target's turn has resolved: the world has stopped, falls have been
# counted against them, and turns_left is about to be decremented.
func on_turn_end() -> void:
	pass

# Put back anything activate() changed. Idempotent; see the header.
func deactivate() -> void:
	pass

# --- Hooks into the descent. Multiplied across every live effect on the
# --- target, so two effects overlap without either knowing about the other.

func descend_speed_mult() -> float:
	return 1.0

func soft_drop_speed_mult() -> float:
	return 1.0

# The rate at which the brick chases the commanded position (FOLLOW_SPEED
# and DASH_FOLLOW_SPEED together).
func follow_speed_mult() -> float:
	return 1.0

# --- Hooks into the controls. Any live effect answering true wins.

# Left is right and right is left, for every steer and dash the target makes.
func steer_flipped() -> bool:
	return false

func rotation_locked() -> bool:
	return false

func dash_locked() -> bool:
	return false

func soft_drop_locked() -> bool:
	return false

# --- Hooks into the brick. First live effect to claim one wins.

# Multiplies the cell size of the target's brick at spawn. See "The lattice"
# in the header before returning anything but 1.0 or 2.0. Only consulted at
# the start of a turn, so a self skill's own claim lands on its *next* brick.
func brick_scale() -> float:
	return 1.0

# Index into GameSettings.BRICKS for the target's next brick, or -1 to leave
# the ordinary draw alone. Like brick_scale(), spawn-time only. The HUD's
# NEXT BRICK card shows what was rolled, so a claim here is a surprise by
# construction — that can be the skill.
func spawn_index_override() -> int:
	return -1

# Applied to the target's brick the instant it is released into the tower.
# Whatever these do to it is permanent — it is a landed brick now.
func mass_mult() -> float:
	return 1.0

# < 0.0 leaves TowerPiece.FRICTION alone.
func friction_override() -> float:
	return -1.0

func gravity_scale_mult() -> float:
	return 1.0

# --- Drawing. Three canvases, three layers. Each is called from inside a real
# --- _draw() on the object named, and Godot only accepts draw_* calls on the
# --- CanvasItem currently inside its own _draw() — so draw on the one you are
# --- handed and no other.

# Called from TowerMode._draw(), in WORLD space, UNDER the bricks (the mode
# draws before its children). The platform's own guides live here. Draw on
# `mode`: mode.draw_rect(...), mode.draw_line(...).
func draw_under() -> void:
	pass

# Called from TowerSkillOverlay._draw(), in WORLD space, ABOVE the bricks and
# the near ground. Draw on the canvas you are given: canvas.draw_circle(...).
func draw_over(_canvas: CanvasItem) -> void:
	pass

# Called from TowerSkillScreen._draw(), in SCREEN space (0,0 top-left,
# 1500x800), above the world and BELOW the HUD panels — fog, a vignette, a
# flash. Draw on the canvas you are given.
func draw_screen(_canvas: CanvasItem) -> void:
	pass

# --- HUD -------------------------------------------------------------------

# A short tag shown on the target's card while the effect is live, e.g.
# "MIRRORED". Empty for none. Keep it to one or two words: the card is 224px.
func hud_tag() -> String:
	return ""
