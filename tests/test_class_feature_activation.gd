extends SceneTree
const Runtime = preload("res://vtt/class_feature_activation.gd")
const Meta = preload("res://vtt/spell_metamagic.gd")
const Store = preload("res://vtt/player_character_store.gd")
const Defenses = preload("res://vtt/creature_damage_defenses_tab.gd")
const Attacks = preload("res://vtt/creature_attack_data.gd")
func _initialize() -> void:
	call_deferred("run")
func make_record(name: String, level: int, book: String = "PHB") -> Dictionary:
	var record := Store.new().create_character()
	record["classes"] = [{"name": name, "source": book, "level": level}]
	record["rules_version"] = "2024" if book == "XPHB" else "2014"
	record["abilities"] = {"str": 18, "dex": 20, "con": 16, "int": 14, "wis": 14, "cha": 18}
	record["max_hp_base"] = 50
	record["current_hp"] = 10
	return record
func run() -> void:
	var record := make_record("Barbarian", 9)
	var before := record.duplicate(true)
	var result := Runtime.activate(record, "class_feature:rage")
	assert(result.ok, str(result))
	assert(record == before, "Activation plans must not mutate source records")
	var raging: Dictionary = result.record
	assert(Runtime.is_active(raging, "rage"))
	assert(Runtime.rage_damage(raging, {"thrown": false}, "str") == 3)
	assert(Runtime.rage_damage(raging, {"thrown": false}, "dex") == 0)
	assert(Runtime.rage_damage(raging, {"thrown": true}, "str") == 0)
	assert(Runtime.roll_advantage(raging, "save:str"))
	assert(Runtime.roll_advantage(raging, "skill:athletics"))
	assert(not Runtime.roll_advantage(raging, "save:dex"))
	assert(Defenses.rank(raging, "slashing") == 1)
	assert(Defenses.rank(raging, "fire") == 0)
	assert(Store.new().normalize_character(raging).active_class_features.has("rage"))
	var stopped := Runtime.activate(raging, "class_feature:rage")
	assert(stopped.ok and not Runtime.is_active(stopped.record, "rage"))
	assert(stopped.record.resource_tracker_spent == raging.resource_tracker_spent)
	var revised := make_record("Barbarian", 9, "XPHB")
	revised = Runtime.activate(revised, "class_feature:rage").record
	assert(Runtime.rage_damage(revised, {"thrown": true}, "str") == 3)
	var fighter := make_record("Fighter", 4)
	var healed := Runtime.activate(fighter, "class_feature:second_wind", {"roll": 8})
	assert(healed.ok and int(healed.record.current_hp) == 22, str(healed))
	var depleted := Runtime.activate(healed.record, "class_feature:second_wind", {"roll": 8})
	assert(not depleted.ok)
	var sorcerer := make_record("Sorcerer", 6)
	sorcerer["optional_features_catalog"] = [{"name": "Distant Spell", "source": "PHB"}, {"name": "Quickened Spell", "source": "PHB"}, {"name": "Twinned Spell", "source": "PHB"}]
	var spell := {"id": "test", "level": 1, "casting_time": "1 action", "range": "60 feet", "range_feet": 60, "duration": "1 minute"}
	var plan := Meta.plan(sorcerer, spell, 1, {"names": ["Distant Spell"]})
	assert(plan.ok and plan.spell.range_feet == 120 and plan.cost == 1, str(plan))
	assert(not Meta.plan(sorcerer, spell, 1, {"names": ["Distant Spell", "Quickened Spell"]}).ok)
	assert(not Meta.plan(sorcerer, spell, 1, {"names": ["Heightened Spell"]}).ok)
	assert(not Meta.plan(sorcerer, spell, 1, {"names": ["Twinned Spell"]}).ok)
	assert(sorcerer.resource_tracker_spent.is_empty(), "Planning/cancelling casts must not spend points")
	var paid := sorcerer.duplicate(true)
	assert(Runtime.spend(paid, plan.tracker, plan.cost))
	assert(paid.resource_tracker_spent.values()[0] == 1)
	print("PASS: class activations, independent payments, Rage editions, defenses, healing, normalization and metamagic plans")
	quit()
