extends Node
class_name ScrollSyncProbe

## Dev-only. Measures whether the tree median actually scrolls with the road
## beside it, which is invisible to every compile check and easy to argue
## about from the constants alone:
##
##   godot --headless --fixed-fps 120 res://scenes/dev/ScrollSyncProbe.tscn
##
## Reports the *drift* — divider.distance minus the neighbouring board's
## distance — in px and in median tiles, since a drift of one whole tile is
## the point at which the trees have visibly slid a full period against the
## road. Scripts a boost and a crash, because those are the two events that
## are supposed to move a board's road without the divider hearing about it.

const MAIN := preload("res://scenes/Main.tscn")
const MEDIAN := preload("res://sprites/road/median_tile.png")

var main: Node = null
var t := 0.0
var next_report := 0.0
var boosted := false
var crashed := false
var tile_h := 0.0
var _last_div := 0.0

func _ready() -> void:
	GameSettings.player_count = 2
	GameSettings.clear_bots()
	for i in range(2):
		GameSettings.set_bot(i, true)
	main = MAIN.instantiate()
	add_child(main)

func _process(delta: float) -> void:
	t += delta
	if main.boards.size() < 2 or main.dividers_container.get_child_count() < 1:
		return
	var b0: PlayerBoard = main.boards[0]
	var b1: PlayerBoard = main.boards[1]
	var d: LaneDivider = main.dividers_container.get_child(0)
	if tile_h == 0.0:
		tile_h = MEDIAN.get_height() * (d.width / MEDIAN.get_width())
		print("median tile height = %.1fpx, board_height = %.0f" % [tile_h, b0.board_height])

	# Scripted boost on board 0 at t=3s: 2.5s at full charge.
	if not boosted and t > 3.0:
		b0.boost_charge = 1.0
		b0.boost_active = true
	if not boosted and t > 5.5:
		boosted = true
		print("[t=%.1f] scripted boost window on board 0 over" % t)

	# Scripted crash on board 1 at t=9s — its road freezes, and we watch
	# whether the divider beside it does too.
	if not crashed and t > 9.0:
		crashed = true
		var victim: int = int(OS.get_environment("TT_CRASH")) if OS.has_environment("TT_CRASH") else 1
		var v: PlayerBoard = main.boards[victim]
		v.alive = false
		v.active = false
		print("[t=%.1f] board %d crashed (its _process now early-returns)" % [t, victim])

	var jump: float = d.distance - _last_div
	if _last_div > 0.0 and abs(jump) > 12.0:
		print("[t=%.2f] !! divider jumped %+.1fpx in one frame" % [t, jump])
	_last_div = d.distance

	if t >= next_report:
		next_report += 1.0
		print("t=%4.1f  board0=%7.1f  board1=%7.1f  divider=%7.1f  |  drift vs b0 = %+8.1fpx (%+.2f tiles)  vs b1 = %+8.1fpx" % [
			t, b0.distance, b1.distance, d.distance,
			d.distance - b0.distance, (d.distance - b0.distance) / tile_h,
			d.distance - b1.distance])

	if t > 14.0:
		get_tree().quit()
