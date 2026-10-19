extends SceneTree
const Store = preload("res://vtt/player_character_store.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Runtime = preload("res://vtt/class_feature_activation.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")
func _initialize() -> void:
	call_deferred("run")
func character(owner: String, level: int, book: String = "PHB", sub: String = "") -> Dictionary:
	var r := Store.new().create_character()
	r.classes = [{"name": owner, "source": book, "level": level, "subclass": sub, "subclass_source": book}]
	r.level = level
	r.armor_natural_formula = "10 + dex_mod"
	r.abilities = {"str": 10, "dex": 14, "con": 18, "int": 18, "wis": 18, "cha": 18}
	return r
func run() -> void:
	var barbarian := character("Barbarian", 5)
	assert(Bonuses.value(barbarian, "ac") == 16)
	var options := Bonuses.natural_armor_options(barbarian)
	assert(options.size() == 1)
	barbarian.proficiency_origins = [{"id": options[0].origin_id, "disabled": true}]
	assert(Bonuses.value(barbarian, "ac") == 12)
	barbarian.proficiency_origins = []
	var shield := {"id": "test:shield", "type": "S", "ac": 2, "quantity": 1, "equipped_slots": ["off"]}
	barbarian.inventory = [shield]
	assert(Bonuses.value(barbarian, "ac") == 18)
	var monk := character("Monk", 5)
	assert(Bonuses.value(monk, "ac") == 16)
	monk.inventory = [shield]
	assert(Bonuses.value(monk, "ac") == 14)
	monk.inventory = [{"id": "test:armor", "type": "HA", "ac": 18, "quantity": 1, "equipped_slots": ["body"]}]
	assert(Bonuses.value(monk, "ac") == 18)
	var sorcerer := character("Sorcerer", 5, "PHB", "Draconic Bloodline")
	assert(Bonuses.value(sorcerer, "ac") == 15)
	var revised := character("Sorcerer", 5, "XPHB", "Draconic Sorcery")
	assert(Bonuses.value(revised, "ac") == 16)
	var multi := character("Barbarian", 1)
	multi.classes.append({"name": "Monk", "source": "PHB", "level": 1})
	multi.level = 2
	assert(Bonuses.value(multi, "ac") == 16, "Alternative formulas must not stack")
	for subclass: String in ["Armorer", "Alchemist", "Artillerist", "Battle Smith"]:
		var artificer := character("Artificer", 15, "TCE", subclass)
		assert(Bonuses.value(artificer, "attunement_max") == 5)
		var flash := Runtime.tracker_named(artificer, "Flash of Genius", "Artificer")
		assert(flash.get("max", 0) == 4)
		assert(String(flash.origin_id).begins_with("feature:"))
		var used := Runtime.activate(artificer, "class_feature:flash_of_genius")
		assert(used.ok)
		assert(Runtime.remaining(used.record, flash) == 3)
		assert(Runtime.remaining(artificer, flash) == 4, "Source record remains unchanged")
		assert(not Trackers.spent_after_recovery(used.record, "long_rest").has(flash.id))
	var armorer := character("Artificer", 8, "TCE", "Armorer")
	assert(not Runtime.activate(armorer, "class_feature:defensive_field").ok)
	armorer.inventory = [{"id": "test:armor", "type": "HA", "ac": 18, "quantity": 1, "equipped_slots": ["body"]}]
	var field := Runtime.activate(armorer, "class_feature:defensive_field")
	assert(field.ok and int(field.record.temporary_hp) == 8)
	field.record.temporary_hp = 12
	var repeated := Runtime.activate(field.record, "class_feature:defensive_field")
	assert(repeated.ok and int(repeated.record.temporary_hp) == 12)
	assert(Runtime.armorer_weapons(armorer)[0].damage == "1d8")
	armorer.artificer_armor_model = "infiltrator"
	assert(Runtime.armorer_weapons(armorer)[0].range_feet == 90)
	assert(Bonuses.value(armorer, "speed") == 35)
	var switched := Runtime.activate(armorer, "class_feature:armor_guardian")
	assert(switched.ok and switched.record.artificer_armor_model == "guardian")
	assert(Bonuses.value(switched.record, "speed") == 30)
	assert(not Runtime.activate(armorer, "class_feature:defensive_field").ok)
	print("PASS: artificer resources, temporary HP, origin disabling, alternative AC")
	quit()
