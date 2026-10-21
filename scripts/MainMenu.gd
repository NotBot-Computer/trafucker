extends Control

## The title screen, and the choice it offers: alone or in teams. Both are a
## cup (GameSettings.TOWER_CUPS) — a run of rounds, a different variant every
## round, trophies by place — and nothing else is offered: every variant is
## played as one of a cup's rounds, asked for so that Pile Up is always a cup
## whichever way you play it. PlayerSelect then offers only the counts the
## chosen cup allows, and the first round's variant is set here so the count
## and colour screens seat people the way that round will.
##
## A card per cup, built from the table so the list of cups and the screen
## that offers them cannot disagree, picked like the main menu's (CardRow:
## left/right, Enter). The solo cup's preview is one tower, the
## team cup's two towers face to face. The card carries only the cup's name;
## the line under the title is the selected cup's hint.
##
## It used to list the variants themselves, with the team ones on a page of
## their own under TEAM MODES and each page's cup last; see
## docs/PROJECT_STATE.md §5 sessions AE, AG and AH. And it used to be a second
## screen, after a main menu that picked between this game and a racing game;
## that one is its own project now (docs/PROJECT_STATE.md §0), so this is
## where the game opens and where every "back to the menu" lands.

const PixelUI := preload("res://scripts/PixelUI.gd")
const ModeCard := preload("res://scripts/ModeCard.gd")

@onready var row: Control = $Cards
var _cups: Array[Dictionary] = []

func _ready() -> void:
	$Subtitle.text = "a different mode every round — first to %d trophies wins" % GameSettings.CUP_TARGET
	PixelUI.apply(self)
	add_child(PixelUI.key_badge("← →  CHOOSE   ENTER  OK", true))

	var first := 0
	for c: Dictionary in GameSettings.TOWER_CUPS:
		var card: Control = ModeCard.new()
		card.title = c["title"]
		if c["id"] == GameSettings.TOWER_CUP_TEAM:
			card.kind = ModeCard.Kind.TOWERS
			card.count = 2
		else:
			card.kind = ModeCard.Kind.TOWER
		if c["id"] == GameSettings.tower_cup:
			first = _cups.size()
		_cups.append(c)
		row.add_card(card)
	row.selection_changed.connect(func(i: int): $Hint.text = _cups[i]["hint"])
	row.chosen.connect(func(i: int): _pick_cup(_cups[i]["id"]))
	row.select(first)

# The scores themselves start when the colours are locked (SkinSelect), once
# the number of players is known.
func _pick_cup(cup: int) -> void:
	GameSettings.tower_cup = cup
	GameSettings.tower_variant = GameSettings.tower_cup_info(cup)["rounds"][0]
	get_tree().change_scene_to_file("res://scenes/PlayerSelect.tscn")
