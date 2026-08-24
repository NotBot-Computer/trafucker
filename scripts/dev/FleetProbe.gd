extends Node2D
# THROWAWAY harness (session P precedent): a clean `godot --headless --quit` proved
# nothing about NITRO_STAGE_FRAMES either — it compiled and threw on every frame at
# runtime. This drives PlayerBoard's real _spawn_obstacle() path and looks at what
# comes out: right art, right size, no placeholder polygon leaking through.
#
# It force-spawns rather than watching a live round because an unattended board
# crashes within seconds and stops spawning entirely (measured: 10 cars in 100s).

const SAMPLES := 4000

func _ready() -> void:
	var bad: Array[String] = []

	print("=== 1. texture table ===")
	var tex_to_kind := {}
	for k in GameSettings.TRAFFIC_KINDS:
		var hf: float = k["height_frac"]
		var worst := 0.0
		for t in k["textures"]:
			if t == null:
				bad.append("%s: NULL texture" % k["kind"]); continue
			var sz: Vector2 = t.get_size()
			if sz.x <= 0.0 or sz.y <= 0.0:
				bad.append("%s: zero-size texture" % k["kind"]); continue
			tex_to_kind[t] = k["kind"]
			worst = max(worst, abs((sz.y / sz.x) - hf) / hf)
		print("  %-11s %2d textures  height_frac=%.2f  worst stretch=%.1f%%"
			% [k["kind"], k["textures"].size(), hf, worst * 100.0])
		if worst > 0.08:
			bad.append("%s: %.1f%% stretch — height_frac does not match the art" % [k["kind"], worst * 100.0])

	var main: Node = preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var board: Node = main.get_node("BoardsContainer").get_child(0)

	print("=== 2. %d spawns through PlayerBoard._spawn_obstacle() ===" % SAMPLES)
	var seen := {}
	var tex_seen := {}
	for i in range(SAMPLES):
		board._spawn_obstacle()
		for child in board.obstacle_container.get_children():
			if child is Car:
				var c: Car = child
				if c.sprite.texture == null:
					if not bad.has("spawned Car with no texture"):
						bad.append("spawned Car with no texture")
				else:
					var kind: String = tex_to_kind.get(c.sprite.texture, "<UNKNOWN>")
					seen[kind] = int(seen.get(kind, 0)) + 1
					tex_seen[c.sprite.texture.resource_path] = true
					if c.width <= 0.0 or c.height <= 0.0:
						bad.append("%s: bad size %.1f x %.1f" % [kind, c.width, c.height])
					if c.body.visible or c.windshield.visible:
						bad.append("%s: placeholder polygon still visible under real art" % kind)
					if not c.has_meta("lane") or not c.has_meta("speed_mult"):
						bad.append("%s: missing lane/speed_mult meta (breaks the §7 shared scans)" % kind)
					var sm: float = c.get_meta("speed_mult", 0.0)
					if sm >= 1.0:
						bad.append("%s: speed_mult %.2f >= 1.0 — the §7 'driving backward' invariant" % [kind, sm])
			child.free()

	var total := 0
	for k in GameSettings.TRAFFIC_KINDS:
		total += int(seen.get(k["kind"], 0))
	var lw: float = board.road.lane_width()
	print("  lane_width = %.2f px, %d cars inspected" % [lw, total])
	for k in GameSettings.TRAFFIC_KINDS:
		var name: String = k["kind"]
		var n: int = int(seen.get(name, 0))
		var w: float = lw * float(k["width_frac"])
		print("    %-11s %4d  %5.1f%% (weight %2d%%)   on-road %.0f x %.0f px"
			% [name, n, 100.0 * float(n) / float(max(total, 1)), k["weight"], w, w * float(k["height_frac"])])
		if n == 0:
			bad.append("%s: never spawned" % name)

	var art_total := 0
	for k in GameSettings.TRAFFIC_KINDS:
		art_total += k["textures"].size()
	print("  distinct textures actually used: %d of %d" % [tex_seen.size(), art_total])
	if tex_seen.size() != art_total:
		bad.append("only %d of %d textures ever appeared" % [tex_seen.size(), art_total])

	print("=== 3. verdict ===")
	if bad.is_empty():
		print("  OK — every kind and every texture spawned with real art at a sane size.")
	else:
		for b in bad:
			print("  FAIL: " + b)
	get_tree().quit()
