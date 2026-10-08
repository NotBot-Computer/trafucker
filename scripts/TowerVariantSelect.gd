extends Control

## Pile Up's variant picker, between the main menu and the player count.
## Sets GameSettings.tower_variant; PlayerSelect then offers only the counts
## that variant can be played at, and SkinSelect decides which scene to hand
## off to (the race is the one variant that is not a single TowerMode).
##
## The rows are built from GameSettings.TOWER_VARIANTS rather than laid out
## in the scene, so the table that says which counts a variant allows and the
## screen that offers it are one list and cannot disagree.
##
## Two pages on one screen. The top level shows every variant whose `group`
## is empty, plus one category row per group, placed where that group's first
## member would have been; picking a category swaps the rows for that group's
## members, and BACK swaps them back. A page, not another scene, because the
## two are one decision — and BACK from the player count lands straight on
## the page the chosen variant lives on, with it focused.
##
## Each page ends with its cup, if it has one (GameSettings.TOWER_CUPS): a
## run of rounds that plays the variants above it in turn. Last on the page
## because it is made of the others, and reads as the long game once they
## have been listed.

const ROW_TOP := 170.0
const ROW_STEP := 104.0
const BUTTON_W := 340.0
const BUTTON_H := 50.0

var page: String = "" # "" = the top level, otherwise a key of GameSettings.TOWER_GROUPS
var _rows: Array[Control] = []

func _ready() -> void:
	$BackButton.pressed.connect(_on_back)
	_show(GameSettings.tower_pick_info()["group"])

# `came_from` is the group page BACK was pressed on, so the top level comes
# back with that category focused rather than the first row.
func _show(which: String, came_from: String = "") -> void:
	page = which
	for r in _rows:
		r.queue_free()
	_rows.clear()

	if page == "":
		$Title.text = "PILE UP"
		$Subtitle.text = "how are you playing?"
	else:
		var g: Dictionary = GameSettings.TOWER_GROUPS[page]
		$Title.text = g["title"]
		$Subtitle.text = g["page_hint"]

	var focus: Button = null
	var seen: Array[String] = []
	var in_cup: bool = GameSettings.tower_cup != GameSettings.TOWER_CUP_NONE
	for v: Dictionary in GameSettings.TOWER_VARIANTS:
		var group: String = v["group"]
		if page == "" and group != "":
			if seen.has(group):
				continue
			seen.append(group)
			var g: Dictionary = GameSettings.TOWER_GROUPS[group]
			var row: Button = _add_row(g["title"] + "  ›", g["hint"], func(): _show(group))
			if group == came_from or (came_from == "" and GameSettings.tower_pick_info()["group"] == group):
				focus = row
		elif group == page:
			var id: int = v["id"]
			var row: Button = _add_row(v["title"], v["hint"], func(): _pick(id))
			if came_from == "" and not in_cup and id == GameSettings.tower_variant:
				focus = row
	for c: Dictionary in GameSettings.TOWER_CUPS:
		if c["group"] != page:
			continue
		var id: int = c["id"]
		var row: Button = _add_row(c["title"], c["hint"], func(): _pick_cup(id))
		if came_from == "" and in_cup and id == GameSettings.tower_cup:
			focus = row
	if focus == null and not _rows.is_empty():
		focus = _rows[0] as Button
	if focus != null:
		focus.grab_focus()

# A button and its hint line, at the next free row.
func _add_row(title: String, hint_text: String, on_press: Callable) -> Button:
	var y: float = ROW_TOP + float(_rows.size()) * 0.5 * ROW_STEP

	var button := Button.new()
	button.text = title
	button.add_theme_font_size_override("font_size", 22)
	button.anchor_left = 0.5
	button.anchor_right = 0.5
	button.offset_left = -BUTTON_W * 0.5
	button.offset_right = BUTTON_W * 0.5
	button.offset_top = y
	button.offset_bottom = y + BUTTON_H
	button.pressed.connect(on_press)
	add_child(button)

	var hint := Label.new()
	hint.text = hint_text
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.anchor_right = 1.0
	hint.offset_top = y + BUTTON_H + 4.0
	hint.offset_bottom = y + BUTTON_H + 30.0
	add_child(hint)

	_rows.append(button)
	_rows.append(hint)
	return button

func _pick(variant: int) -> void:
	GameSettings.tower_cup = GameSettings.TOWER_CUP_NONE
	GameSettings.tower_variant = variant
	get_tree().change_scene_to_file("res://scenes/PlayerSelect.tscn")

# The cup's first round is its variant from here on, so the player count and
# the colour screen describe the seats the way that round will use them. The
# scores themselves start when the colours are locked (SkinSelect), once the
# number of players is known.
func _pick_cup(cup: int) -> void:
	GameSettings.tower_cup = cup
	GameSettings.tower_variant = GameSettings.tower_cup_info(cup)["rounds"][0]
	get_tree().change_scene_to_file("res://scenes/PlayerSelect.tscn")

func _on_back() -> void:
	if page != "":
		_show("", page)
		return
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
