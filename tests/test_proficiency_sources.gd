extends SceneTree

const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")
const ProficiencyTab = preload("res://vtt/creature_proficiencies_tab.gd")
const Attacks = preload("res://vtt/creature_attack_data.gd")
const PlayerStore = preload("res://vtt/player_character_store.gd")


func _initialize() -> void:
	call_deferred("run")


func _weapon() -> Dictionary:
	return {
		"id": "weapon:rapier|phb|m", "name": "Rapier", "type": "M",
		"source": "PHB", "weapon_category": "martial",
		"damage": "1d8", "damage_type": "P", "properties": ["F"],
		"quantity": 1, "equipped_slots": ["main"]
	}


func _record() -> Dictionary:
	return {
		"kind": "character", "rules_version": "2014",
		"class": "Fighter", "class_source": "PHB",
		"classes": [{"name": "Fighter", "source": "PHB", "level": 1}],
		"abilities": {"str": 14, "dex": 18}, "ability_bonuses": {},
		"attack_ability": "dex", "inventory": [_weapon()],
		"attack_overrides": {"item:weapon:rapier|phb|m": {"proficient": true}},
		"skill_proficiencies": ["athletics"], "skill_expertise": [],
		"saving_throw_proficiencies": [],
		"proficiency_choices": []
	}


func run() -> void:
	var record := _record()
	var skilled: Array[Dictionary] = Proficiencies.suggest_origins(record, "skill", "athletics")
	assert(not skilled.is_empty() and int(skilled[0]["certainty"]) == 1,
		"Fighter's structured choose-2 skill set is a suggestion, not automatic training")
	assert(Proficiencies.suggest_origins(record, "weapon", "martial")[0].certainty == 2,
		"Fighter's fixed martial weapons proficiency is a structured grant")
	assert(Proficiencies.suggest_origins(record, "save", "str")[0].certainty == 2,
		"Fighter's STR saving throw proficiency is structured")
	assert(Proficiencies.suggest_origins(record, "save", "cha").is_empty(),
		"Unlisted saving throw must not be inferred from text")
	var required: Array[Dictionary] = Proficiencies.missing_structured(record)
	assert(not required.is_empty(), "Missing fixed grants produce only a hint")

	var weapon: Dictionary = Attacks.definitions(record)[0]
	assert(weapon.source == "item", "Equipped weapon comes before unarmed strike")
	assert(Attacks.attack_bonus(record, weapon, 2) == 4,
		"Legacy per-attack proficiency is ignored in favor of creature choices")
	var rows: Array[Dictionary] = Proficiencies.choices(record)
	assert(Proficiencies.has_choice(rows, "skill", "athletics"))
	rows.append({"kind": "weapon", "key": "martial",
		"origin_id": "class|phb|fighter", "origin_name": "Classe · Fighter (iniziale)"})
	Proficiencies.sync_legacy_fields(record, rows)
	assert(Attacks.attack_bonus(record, weapon, 2) == 6,
		"Martial competence applies to every equipped martial weapon")
	assert(record.skill_proficiencies == ["athletics"], "Legacy skill arrays remain synchronized")
	assert(Proficiencies.unassigned_count(record) == 1,
		"Unassigned pre-existing skill proficiency remains visible")

	var feat_record := _record()
	feat_record["feats_catalog"] = [{"name": "Lightly Armored", "source": "PHB", "id": "feat:lightly armored|phb|"}]
	assert(not Proficiencies.suggest_origins(feat_record, "armor", "light").is_empty(),
		"An acquired feat with structured armor proficiency is a suggested origin")
	assert(Proficiencies.suggest_origins(feat_record, "armor", "heavy").is_empty(),
		"The feat does not grant proficiency with all armor")

	var legacy := _record()
	legacy.erase("proficiency_choices")
	legacy["skill_proficiencies"] = []
	legacy = PlayerStore.new().normalize_character(legacy)
	assert(Proficiencies.has_proficiency(legacy, "weapon", "rapier"),
		"Legacy per-attack item proficiency migrates to shared weapon-name training")

	var tab := ProficiencyTab.new()
	root.add_child(tab)
	var changed: Array = []
	tab.setup(func(profs: Array, feats: Array) -> void:
		changed.append({"profs": profs, "feats": feats}))
	tab.load_record(record)
	tab._group.select(0)
	tab._entry_text.text = "longsword"
	tab._add_choice()
	assert(not changed.is_empty() and Proficiencies.has_choice(changed.back().profs, "weapon", "longsword"),
		"Users can explicitly add a weapon proficiency")
	var last: int = tab._rows.size() - 1
	tab._owned.select(last)
	tab._owned.item_selected.emit(last)
	assert(tab._origin.item_count >= 2, "Source selector lists matching or available traits")
	tab.queue_free()
	await process_frame
	print("PASS: structured proficiency hints, feat grants, shared weapon bonus, migration and origin selector")
	quit()
