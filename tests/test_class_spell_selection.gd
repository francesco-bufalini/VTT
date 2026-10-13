extends SceneTree
const Selections = preload("res://vtt/class_spell_selection.gd")
const Catalog = preload("res://vtt/spells/spell_catalog.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var record: Dictionary = {"rules_version": "2014", "abilities": {"int": 16, "cha": 16},
		"classes": [{"name": "Wizard", "source": "PHB", "level": 3}, {"name": "Bard", "source": "PHB", "level": 3}]}
	var members: Array[Dictionary] = Selections.classes(record)
	assert(members.size() == 2 and members[0].limit == 6 and members[1].limit == 6)
	var spell: Dictionary = {}
	for candidate: Dictionary in Catalog.all_spells_for_rules("2014"):
		if Selections.eligible(candidate, members[0]) and Selections.eligible(candidate, members[1]):
			spell = candidate
			break
	assert(not spell.is_empty())
	var saved: Array = Selections.apply(record, [], members[0], [spell.id])
	saved = Selections.apply(record, saved, members[1], [spell.id])
	assert(saved.size() == 1 and saved[0].casting_classes.size() == 2)
	saved = Selections.apply(record, saved, members[0], [])
	assert(saved.size() == 1 and saved[0].casting_classes == [members[1].id])
	record.rules_version = "2024"
	record.classes = [{"name": "Wizard", "source": "XPHB", "level": 3}]
	assert(Selections.classes(record)[0].limit == 6)
	print("PASS class spell capacity, edition separation and shared-spell ownership")
	quit()
