extends Node
class_name TaxiProbe

## Dev-only measurement harness for taxi behaviour. Not part of the game —
## nothing in the shipped scene flow references this, it is run explicitly:
##
##   godot --headless --fixed-fps 120 res://scenes/dev/TaxiProbe.tscn
##   TT_SEED=3 TT_PLAYERS=4 TT_WAVE=3 godot --headless --fixed-fps 120 res://scenes/dev/TaxiProbe.tscn
##
## Why this exists as a committed file rather than a throwaway: the taxi's
## whole job is a *feel* ("cause chaos in the traffic"), and the complaints
## it gets are about behaviour no compile check can see — "it sticks to the
## side of the road", "it doesn't do much". Those turned out to be precisely
## measurable, and the measurements contradicted careful reasoning twice
## (see PROJECT_STATE §5 session L). Rebuilding this from scratch each time
## also means re-learning its two traps the hard way:
##
##   1. **An unattended PlayerBoard crashes in ~1.3 seconds**, and a crash
##      freezes that board's entire _process. Metrics then come off a frozen
##      board and look perfectly plausible. Bots are enabled below for this
##      reason, plus a revive as a backstop.
##   2. **Traffic spawning is random.** Unseeded runs vary wildly enough to
##      prove anything you like — one showed a flattering 92% board coverage
##      that could not be reproduced. Always compare like-for-like seeds, and
##      note that a change altering how many randf() calls happen per frame
##      shifts the whole sequence — per-seed numbers stop being comparable
##      across such a change, so compare the aggregate over several seeds.
##
## The overlap section reports *why* a taxi intersects another vehicle, not
## just that it does, because the answer has been counter-intuitive: the
## obvious guess (traffic merging into it) was wrong, and it was `taxi_y` in
## the onset dump that revealed taxis spawning inside cars queued below the
## bottom edge. Classification happens at episode onset, since an overlap
## long outlives whatever motion caused it — sampling every frame just
## reports that nobody was moving.
##
## Comparing a change against the previous version means running this,
## stashing the change, running it again on the same seeds, and restoring.

const MAIN := preload("res://scenes/Main.tscn")

@export var duration: float = 17.0

var board: PlayerBoard = null
var t := 0.0
var seeded := false
var tracks := {}
var order := []
var players := 2
var wave := 2
var frames := 0
# Overlap accounting, split by cause — a taxi overlapping another vehicle is
# either the taxi driving into someone or someone merging into the taxi, and
# the two have completely different fixes.
var ov_frames := 0
var ov_traffic_merging := 0
var ov_taxi_steering := 0
var ov_worst := 0.0
var ov_pairs := {} # pair-key -> true while that specific overlap episode is ongoing
var ov_onsets := [] # context captured the frame each episode began

func _env(name: String, fallback: int) -> int:
	return int(OS.get_environment(name)) if OS.has_environment(name) else fallback

func _ready() -> void:
	players = _env("TT_PLAYERS", 2)
	wave = _env("TT_WAVE", 2)
	seed(_env("TT_SEED", 1))
	GameSettings.player_count = players
	GameSettings.clear_bots()
	for i in range(players):
		GameSettings.set_bot(i, true) # see trap 1 in the header
	add_child(MAIN.instantiate())

func _process(delta: float) -> void:
	t += delta
	if board == null:
		var main := get_child(0)
		if main.boards.size() > 0:
			board = main.boards[0]
		return
	if not board.alive: # backstop for trap 1 — the taxi doesn't care if the player is alive
		board.alive = true
		board.active = true
	if not seeded and t > 0.5:
		seeded = true
		for i in range(wave): # `wave` rivals spending the skill in the same moment
			board.receive_opponent_skill("taxi")

	frames += 1
	var overlapped_this_frame := false
	var ongoing := {} # overlap episodes still live this frame; replaces ov_pairs at the end
	for taxi in board.active_taxis:
		if not is_instance_valid(taxi):
			continue
		if not tracks.has(taxi):
			tracks[taxi] = {"lanes": {}, "ymin": INF, "ymax": -INF, "frames": 0,
				"changes": 0, "last_lane": -1, "onboard": 0, "blocked": 0}
			order.append(taxi)
		var r: Dictionary = tracks[taxi]
		var ln: int = board._nearest_lane(taxi.position.x)
		if r["last_lane"] >= 0 and ln != r["last_lane"]:
			r["changes"] += 1
		r["last_lane"] = ln
		r["lanes"][ln] = true
		r["ymin"] = min(r["ymin"], taxi.position.y)
		r["ymax"] = max(r["ymax"], taxi.position.y)
		r["frames"] += 1
		if taxi.position.y < board.board_height and taxi.position.y > 0.0:
			r["onboard"] += 1
		if bool(taxi.get_meta("tx_blocked", false)):
			r["blocked"] += 1

		for other in board.obstacle_container.get_children():
			if other == taxi or not (other is Car):
				continue
			var ox: float = (taxi.width + other.width) * 0.5 - abs(other.position.x - taxi.position.x)
			var oy: float = (taxi.height + other.height) * 0.5 - abs(other.position.y - taxi.position.y)
			if ox <= 0.0 or oy <= 0.0:
				continue
			overlapped_this_frame = true
			ov_worst = max(ov_worst, min(ox, oy))
			ongoing["%d:%d" % [taxi.get_instance_id(), other.get_instance_id()]] = true
			# Classify at the ONSET of each episode, not every frame: an
			# overlap persists long after whatever caused it has stopped
			# moving, so per-frame sampling reports "nobody was moving".
			var key := "%d:%d" % [taxi.get_instance_id(), other.get_instance_id()]
			if not ov_pairs.has(key):
				ov_pairs[key] = true
				var merging := String(other.get_meta("lc_state", "idle")) == "moving"
				var steering: bool = abs(float(taxi.get_meta("tx_vx", 0.0))) > 20.0
				if merging:
					ov_traffic_merging += 1
				elif steering:
					ov_taxi_steering += 1
				if ov_onsets.size() < 8:
					ov_onsets.append("dx=%.0f signed_dy=%+.0f (need %.0f/%.0f) taxi_vx=%.0f taxi_mult=%+.2f other_mult=%+.2f other_is_taxi=%s other_lc=%s taxi_state=%s taxi_y=%.0f" % [
						abs(other.position.x - taxi.position.x), other.position.y - taxi.position.y,
						(taxi.width + other.width) * 0.5, (taxi.height + other.height) * 0.5,
						float(taxi.get_meta("tx_vx", 0.0)), float(taxi.get_meta("speed_mult", 0.0)),
						float(other.get_meta("speed_mult", 0.0)),
						"YES" if bool(other.get_meta("is_taxi", false)) else "no",
						String(other.get_meta("lc_state", "idle")),
						String(taxi.get_meta("tx_state", "?")), taxi.position.y])
	if overlapped_this_frame:
		ov_frames += 1
	# Episodes not seen this frame have ended, so a later re-overlap of the
	# same pair counts as a new one.
	ov_pairs = ongoing

	if t > duration:
		_report()
		get_tree().quit()

func _report() -> void:
	var n: float = max(float(order.size()), 1.0)
	var cov := 0.0
	var onb := 0.0
	var lanes := 0.0
	var chg := 0.0
	var blk := 0.0
	var left := 0
	for taxi in order:
		var r: Dictionary = tracks[taxi]
		var f: float = float(r["frames"])
		cov += 100.0 * (r["ymax"] - r["ymin"]) / board.board_height
		onb += 100.0 * float(r["onboard"]) / f
		lanes += r["lanes"].size()
		chg += r["changes"]
		blk += 100.0 * float(r["blocked"]) / f
		if not is_instance_valid(taxi):
			left += 1
	print("seed=%d P=%d wave=%d taxis=%d | onboard=%.0f%% coverage=%.0f%% lanes=%.1f/%d changes=%.1f blocked=%.0f%% left=%d" % [
		_env("TT_SEED", 1), players, wave, order.size(),
		onb / n, cov / n, lanes / n, board.lane_count, chg / n, blk / n, left])
	print("        overlap: %.2f%% of frames, deepest %.1fpx | traffic-merging-in=%d taxi-steering-in=%d" % [
		100.0 * float(ov_frames) / float(frames), ov_worst, ov_traffic_merging, ov_taxi_steering])
	for line in ov_onsets:
		print("        onset: %s" % line)
