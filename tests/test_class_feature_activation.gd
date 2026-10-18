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
	# The same typed effect must power the sheet state, the actual damage and
	# the modifier breakdown. A status entry cannot quietly change the total.
	var effects := Runtime.active_effects(raging)
	assert(effects.size() == 1 and effects[0].key == "rage")
	assert(effects[0].name == "Ira" and effects[0].effective)
	assert(not String(effects[0].origin_id).is_empty())
	var attack := {"id": "unarmed", "source": "unarmed", "melee": true, "damage": ""}
	var breakdown := Attacks.damage_modifier_breakdown(raging, attack)
	assert(int(breakdown.total) == 7, str(breakdown))
	assert(breakdown.parts.any(func(part: Dictionary) -> bool:
		return part.get("name", "") == "Ira" and int(part.get("amount", 0)) == 3))
	assert("Ira: +3" in Attacks.damage_modifier_description(raging, attack))
	assert(Attacks.damage_label(raging, attack) == "8 contundenti")
	var suspended := raging.duplicate(true)
	suspended["conditions"] = ["unconscious"]
	assert(not Runtime.is_active(suspended, "rage"))
	assert(Runtime.active_effects(suspended).size() == 1)
	assert(not Runtime.active_effects(suspended)[0].effective)
	assert(Runtime.rage_damage(suspended, {"thrown": false}, "str") == 0)
	var cleared := Runtime.deactivate(raging, "rage")
	assert(cleared.ok and not Runtime.is_active(cleared.record, "rage"))
	assert(Runtime.active_effects(cleared.record).is_empty())
	assert(Attacks.damage_modifier_breakdown(cleared.record, attack).total == 4)
	assert(cleared.record.resource_tracker_spent == raging.resource_tracker_spent)
	var stopped := Runtime.activate(raging, "class_feature:rage")
	assert(stopped.ok and not Runtime.is_active(stopped.record, "rage"))
	assert(stopped.record.resource_tracker_spent == raging.resource_tracker_spent)
	var novice := make_record("Barbarian", 1)
	var novice_rage: Dictionary = Runtime.activate(novice, "class_feature:rage").record
	assert(Runtime.rage_damage(novice_rage, {"thrown": false}, "str") == 2)
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
	sorcerer.optional_features_catalog.append({"name": "Empowered Spell", "source": "PHB"})
	assert(not Meta.plan(sorcerer, spell, 1, {"names": ["Empowered Spell"]}).ok)
	assert(Meta.reroll_plan(sorcerer, "Empowered Spell", 4, 6).ok)
	assert(not Meta.reroll_plan(sorcerer, "Empowered Spell", 5, 6).ok)
	var wizard := make_record("Wizard", 5)
	wizard["spell_slots_spent"] = [0, 2, 1, 0, 0, 0, 0, 0, 0, 0]
	assert(Runtime.recover_slots(wizard, [1, 2]).ok)
	assert(not Runtime.recover_slots(wizard, [2, 2]).ok)
	sorcerer["spell_slots_total"] = [0, 4, 3, 3, 0, 0, 0, 0, 0, 0]
	var converted := Runtime.convert_slots(sorcerer, 2, true)
	assert(converted.ok and int(converted.record.created_spell_slots[2]) == 1)
	assert(int(converted.record.resource_tracker_spent.values()[0]) == 3)
	var normalized := Store.new().normalize_character(converted.record)
	assert(normalized.created_spell_slots[2] == 1)
	var point_recovery := Runtime.convert_slots(converted.record, 1, false)
	assert(point_recovery.ok and int(point_recovery.record.spell_slots_spent[1]) == 1)
	var rest := preload("res://vtt/structured_resource_trackers.gd").recovery_patch(converted.record, "long_rest")
	assert(rest.created_spell_slots.is_empty() and rest.active_class_features.is_empty())
	var revised_sorc := make_record("Sorcerer", 6, "XPHB")
	var innate := Runtime.activate(revised_sorc, "class_feature:innate_sorcery")
	assert(innate.ok)
	assert(Runtime.active_effects(innate.record).any(func(effect: Dictionary) -> bool:
		return effect.get("key", "") == "innate_sorcery"))
	assert(Runtime.deactivate(innate.record, "innate_sorcery").ok)
	var monk := make_record("Monk", 4, "XPHB")
	var monk_options := Runtime.entries(monk)
	assert(monk_options.any(func(row: Dictionary) -> bool: return row.key == "patient_defense"))
	var old_twin := Meta.apply_to_spell(spell, 3, {"names": ["Twinned Spell"], "eligible_targeting": true}, false)
	assert(old_twin.ok and old_twin.spell.base_target_clicks == 2)
	var revised_twin := Meta.apply_to_spell(spell, 3, {"names": ["Twinned Spell"], "eligible_targeting": true}, true)
	assert(revised_twin.ok and revised_twin.spell.metamagic_effective_level == 4)
	var extended := Meta.apply_to_spell({"duration": "Concentration, up to 1 minute"}, 1, {"names": ["Extended Spell"]}, false)
	assert(extended.ok and extended.spell.requires_concentration and extended.spell.metamagic_duration_seconds == 120)
	var archive = preload("res://vtt/creature_archive.gd").new()
	archive.setup()
	archive._storage.path = "user://class_feature_atomic_%d.json" % Time.get_ticks_usec()
	var a := make_record("Paladin", 3)
	a["kind"] = "character"
	var b := make_record("Fighter", 3)
	b["kind"] = "character"
	assert(archive.save(a) == OK and archive.save(b) == OK)
	var original := FileAccess.get_file_as_string(archive._storage.path)
	var invalid := b.duplicate(true)
	invalid["id"] = "missing_target"
	assert(archive.update_owned_many([a, invalid]) == ERR_DOES_NOT_EXIST)
	assert(FileAccess.get_file_as_string(archive._storage.path) == original)
	var heal := Runtime.activate(a, "class_feature:lay_on_hands", {"amount": 5, "apply_to_self": false})
	assert(heal.ok and heal.record.current_hp == a.current_hp)
	b["current_hp"] = int(b.current_hp) + 5
	assert(archive.update_owned_many([heal.record, b]) == OK)
	assert(archive.list_owned().size() == 2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(archive._storage.path))
	print("PASS: class activations, independent payments, Rage editions, defenses, healing, normalization and metamagic plans")
	quit()
