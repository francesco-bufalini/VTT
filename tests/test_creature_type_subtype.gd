extends SceneTree

const Rules = preload("res://vtt/creature_rules.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var fiend: Dictionary = {
		"type": {"type": "fiend", "tags": ["demon", {"tag": "shapechanger"}]}
	}
	assert(Rules.monster_type_reference(fiend).get("name", "") == "Immondo")
	assert(Rules.monster_subtype(fiend) == "demon, shapechanger")
	assert(Rules.monster_subtype({"type": "beast"}) == "")

	var construct: Dictionary = {
		"entries": [{
			"name": "Creature Type", "entries": ["You are a Construct."]
		}]
	}
	assert(Rules.species_creature_type(construct) == "Costrutto")
	assert(Rules.species_creature_type({}) == "Umanoide")

	print("PASS: creature type and subtype are independent of class")
	quit()
