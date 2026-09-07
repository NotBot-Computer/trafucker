extends RefCounted
class_name TowerSkillCatalog

## The one place that says what Pile Up skills exist — assembled from three
## PACKS rather than written here, on purpose.
##
## Don't Crash's `SkillCatalog` is a single table, and adding a skill means
## editing it. That is fine for one author. Pile Up's skills were built by
## three sessions working at the same time, and docs/PROJECT_STATE.md §12
## records exactly what happens when two of them read-modify-write one file:
## an edit is silently lost and neither git status nor the compile check
## notices. So each author owns one pack file under packs/ and nothing else
## in the catalogue, and this file only merges them. A pack is a RefCounted
## with one `const SKILLS := {...}` in the same row format as SkillCatalog:
##
##   "id": {
##       "category": "self" | "opponent",
##       "title":    "SHORT CAPS NAME",     # what the HUD and the toast say
##       "blurb":    "one line, for the card and the docs",
##       "script":   preload("res://scripts/tower_skills/SomeSkill.gd"),
##       "glyph":    preload("res://sprites/skills/tower_some.png"),
##   },
##
## Ids are global across packs; two packs claiming one id is reported at
## load and the second is dropped, so it cannot be papered over. Merged on
## every call rather than cached in a `static var` — §12: a static var on a
## script makes headless runs report leaked ObjectDB instances at exit — and
## the merge is nine entries, so nothing here is worth caching anyway.

const PACKS: Array[Script] = [
	preload("res://scripts/tower_skills/packs/TowerSkillsA.gd"),
	preload("res://scripts/tower_skills/packs/TowerSkillsB.gd"),
	preload("res://scripts/tower_skills/packs/TowerSkillsC.gd"),
]

static func skills() -> Dictionary:
	var out := {}
	for pack: Script in PACKS:
		var table: Dictionary = pack.get_script_constant_map().get("SKILLS", {})
		for id in table.keys():
			if out.has(id):
				push_error("TowerSkillCatalog: skill id '%s' is claimed by two packs; keeping the first" % id)
				continue
			out[id] = table[id]
	return out

static func has_skill(id: String) -> bool:
	return skills().has(id)

static func ids_in(category: String) -> Array[String]:
	var out: Array[String] = []
	var table: Dictionary = skills()
	for id in table.keys():
		if table[id].get("category", "") == category:
			out.append(id)
	out.sort() # Dictionary order is insertion order, which is pack order; sorted so a draw is not biased by which pack loaded first
	return out

static func category_of(id: String) -> String:
	return skills().get(id, {}).get("category", "")

static func title_of(id: String) -> String:
	return skills().get(id, {}).get("title", id)

static func blurb_of(id: String) -> String:
	return skills().get(id, {}).get("blurb", "")

static func glyph_of(id: String) -> Texture2D:
	return skills().get(id, {}).get("glyph", null)

# Builds an effect already wired to its mode. Returns null for an unknown id.
static func make(id: String, mode, caster: int, target: int) -> TowerSkill:
	var entry: Dictionary = skills().get(id, {})
	if entry.is_empty():
		return null
	var scr: Script = entry["script"]
	var effect: TowerSkill = scr.new()
	effect.setup(mode, id, caster, target)
	return effect
