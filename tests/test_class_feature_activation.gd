extends SceneTree
const Runtime = preload("res://vtt/class_feature_activation.gd")
const Meta = preload("res://vtt/spell_metamagic.gd")
const Fixtures = preload("res://tests/fixtures/creature_record.gd")
const Attacks = preload("res://vtt/creature_attack_data.gd")
func _initialize() -> void:
	call_deferred("run")
func make_record(name: String, level: int, book: String = "PHB") -> Dictionary:
	var record := Fixtures.character()
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
	assert(JSON.parse_string(JSON.stringify(raging)).active_class_features.has("rage"))
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
	# Every selected Metamagic option is its own source-owned trait;
	# disabling either the choice or the granting class trait removes it.
	var meta_actions: Array[Dictionary] = Runtime.entries(sorcerer)
	var distant: Dictionary = {}
	for action: Dictionary in meta_actions:
		if String(action.get("name", "")) == "Distant Spell":
			distant = action
	assert(not distant.is_empty() and String(distant.get("origin_id", "")).begins_with("feature:optional|"))
	var muted_metamagic := sorcerer.duplicate(true)
	muted_metamagic["origin_enabled"] = {String(distant.origin_id): false}
	assert(not Runtime.metamagic_options(muted_metamagic).any(func(option: Dictionary) -> bool:
		return String(option.get("name", "")) == "Distant Spell"))
	var other_options := Runtime.metamagic_options(muted_metamagic)
	assert(other_options.any(func(option: Dictionary) -> bool:
		return String(option.get("name", "")) == "Quickened Spell"))
	var muted_owner := sorcerer.duplicate(true)
	for feature: Dictionary in preload("res://vtt/creature_features.gd").collect_features(sorcerer):
		if String(feature.get("name", "")) == "Metamagic" and String(feature.get("class_name", "")) == "Sorcerer":
			muted_owner["origin_enabled"] = {"feature:" + String(feature.get("key", "")): false}
			break
	assert(Runtime.metamagic_options(muted_owner).is_empty())
	# Models, attacks and Guardian powers derive from the same state catalog
	# and must disappear when their armor or granting trait is unavailable.
	var armorer := make_record("Artificer", 10, "TCE")
	armorer["classes"][0]["subclass"] = "Armorer"
	armorer["classes"][0]["subclass_source"] = "TCE"
	armorer["inventory"] = [{"id": "armor_test", "name": "Scale Mail", "type": "MA",
		"ac": 14, "quantity": 1, "equipped_slots": ["body"]}]
	assert(not Runtime.entries(armorer).any(func(action: Dictionary) -> bool:
		return String(action.get("mode", "")) == "armor_model"), "Unmodified armor must not grant Armor Models")
	armorer["power_applications"] = {"arcane_armor": [{"id": "arcane_armor", "target_item_id": "armor_test"}]}
	var model_actions := Runtime.entries(armorer)
	assert(model_actions.any(func(action: Dictionary) -> bool:
		return String(action.get("key", "")) == "armor_guardian"), "Missing eligible Guardian model")
	assert(model_actions.any(func(action: Dictionary) -> bool:
		return String(action.get("key", "")) == "armor_infiltrator"), "Missing eligible Infiltrator model")
	assert(Runtime.armorer_weapons(armorer).is_empty(), "An unselected model grants no weapons")
	var stale_model: Dictionary = armorer.duplicate(true)
	stale_model["artificer_armor_model"] = "guardian"
	assert(Runtime.armorer_weapons(stale_model).is_empty(), "Removed legacy fields cannot select a model")
	var guardian := Runtime.activate(armorer, "class_feature:armor_guardian")
	assert(guardian.ok)
	assert(guardian.record.trait_state_selection.get("armor_model") == "armor_model:guardian")
	var deselected := Runtime.activate(guardian.record, "class_feature:armor_guardian")
	assert(deselected.ok and Runtime.armorer_weapons(deselected.record).is_empty(), "Deselecting the model removes its weapons")
	assert(Runtime.armorer_weapons(guardian.record).any(func(attack: Dictionary) -> bool:
		return String(attack.get("name", "")) == "Thunder Gauntlets"))
	var switched := Runtime.activate(guardian.record, "class_feature:armor_infiltrator")
	assert(switched.ok, str(switched))
	assert(switched.record.trait_state_selection.get("armor_model") == "armor_model:infiltrator")
	assert(switched.record.active_class_features.has("trait_state:armor_model:infiltrator"))
	assert(Runtime.armorer_weapons(switched.record).any(func(attack: Dictionary) -> bool:
		return String(attack.get("name", "")) == "Lightning Launcher"))
	assert(not Runtime.armorer_weapons(switched.record).any(func(attack: Dictionary) -> bool:
		return String(attack.get("name", "")) == "Thunder Gauntlets"))
	var unequipped: Dictionary = switched.record.duplicate(true)
	unequipped["inventory"][0]["equipped_slots"] = []
	assert(Runtime.armorer_weapons(unequipped).is_empty())
	assert(not Runtime.entries(unequipped).any(func(action: Dictionary) -> bool:
		return String(action.get("mode", "")) == "armor_model"))
	var disabled_model: Dictionary = switched.record.duplicate(true)
	for feature: Dictionary in preload("res://vtt/creature_features.gd").collect_features(disabled_model):
		if String(feature.get("name", "")) == "Armor Model":
			disabled_model["origin_enabled"] = {"feature:" + String(feature.get("key", "")): false}
			break
	assert(Runtime.armorer_weapons(disabled_model).is_empty())
	assert(not Runtime.entries(disabled_model).any(func(action: Dictionary) -> bool:
		return String(action.get("mode", "")) == "armor_model"))
	var wizard := make_record("Wizard", 5)
	wizard["spell_slots_spent"] = [0, 2, 1, 0, 0, 0, 0, 0, 0, 0]
	assert(Runtime.recover_slots(wizard, [1, 2]).ok)
	assert(not Runtime.recover_slots(wizard, [2, 2]).ok)
	sorcerer["spell_slots_total"] = [0, 4, 3, 3, 0, 0, 0, 0, 0, 0]
	var converted := Runtime.convert_slots(sorcerer, 2, true)
	assert(converted.ok and int(converted.record.created_spell_slots[2]) == 1)
	assert(int(converted.record.resource_tracker_spent.values()[0]) == 3)
	var normalized: Dictionary = JSON.parse_string(JSON.stringify(converted.record))
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
	var paladin := make_record("Paladin", 3)
	paladin["kind"] = "character"
	var heal := Runtime.activate(paladin, "class_feature:lay_on_hands", {"amount": 5, "apply_to_self": false})
	assert(heal.ok and heal.record.current_hp == paladin.current_hp)
	print("PASS: class activations, independent payments, Rage editions, defenses, healing, normalization and metamagic plans")
	quit()
