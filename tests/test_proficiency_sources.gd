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
	assert(Proficiencies.suggest_origins(record, "weapon", "rapier")[0].certainty == 2,
		"Individual martial weapons inherit the fixed category-level class suggestion")
	assert(Proficiencies.suggest_origins(record, "save", "cha").is_empty(),
		"Unlisted saving throw must not be inferred from text")
	var sources: Array[Dictionary] = Proficiencies.origins(record)
	var fighter: Dictionary = {}
	for candidate: Dictionary in sources:
		if String(candidate.get("id", "")) == "class|phb|fighter":
			fighter = candidate
	assert(not fighter.is_empty() and not fighter.get("requirements", []).is_empty(),
		"Starting Fighter has a source with missing structured choose skills")
	var rows: Array[Dictionary] = Proficiencies.choices(record)
	assert(Proficiencies.has_choice(rows, "weapon", "martial")
		and Proficiencies.has_choice(rows, "armor", "heavy")
		and Proficiencies.has_choice(rows, "save", "str"),
		"Mandatory class grants are created before the editor opens")
	assert(not Proficiencies.has_choice(rows, "skill", "perception"),
		"Choose-2 never silently selects a skill")
	assert(not Proficiencies.requirement_missing(fighter, rows, {"class|phb|fighter": true}).is_empty(),
		"Unresolved skill choices show a warning")
	var weapon: Dictionary = Attacks.definitions(record)[0]
	assert(weapon.source == "item", "Equipped weapon comes before unarmed strike")
	assert(Attacks.attack_bonus(record, weapon, 2) == 6,
		"Starting Fighter martial training applies automatically, per creature")
	record["proficiency_origins"] = [{"id": "class|phb|fighter", "name": "Starting Fighter", "automatic": true, "disabled": true}]
	assert(Attacks.attack_bonus(record, weapon, 2) == 4,
		"Disabling the origin removes its whole category bonus without deleting choices")
	record["proficiency_origins"][0]["disabled"] = false
	assert(Attacks.attack_bonus(record, weapon, 2) == 6, "Re-enabling an origin restores its grants")
	Proficiencies.sync_legacy_fields(record, rows)
	assert(record.skill_proficiencies == ["athletics"], "Legacy skill arrays remain synchronized")
	assert(Proficiencies.unassigned_count(record) == 1,
		"Unassigned pre-existing skill proficiency remains visible")

	var background_record := _record()
	background_record["background"] = "Acolyte"
	# Legacy character sheets keep only a background name.
	var background_sources: Array[Dictionary] = Proficiencies.suggest_origins(background_record, "skill", "insight")
	var has_acolyte := false
	for suggestion: Dictionary in background_sources:
		if String(suggestion.get("group", "")) == "background" and int(suggestion.get("certainty", 0)) == 2:
			has_acolyte = true
	assert(has_acolyte, "Structured background proficiencies are suggested without a stored source book")

	var feat_record := _record()
	feat_record["feats_catalog"] = [{"name": "Lightly Armored", "source": "PHB", "id": "feat:lightly armored|phb|"}]
	var lightly_grants := false
	for suggestion: Dictionary in Proficiencies.suggest_origins(feat_record, "armor", "light"):
		if String(suggestion.get("group", "")) == "feat":
			lightly_grants = int(suggestion.get("certainty", 0)) == 2
	assert(lightly_grants, "Acquired Lightly Armored offers its structured light armor grant")
	var feat_grants_heavy := false
	for suggestion: Dictionary in Proficiencies.suggest_origins(feat_record, "armor", "heavy"):
		if String(suggestion.get("group", "")) == "feat":
			feat_grants_heavy = true
	assert(not feat_grants_heavy, "Lightly Armored feat does not grant heavy armor; the Fighter class does")
	feat_record["feats_catalog"] = [{"name": "Weapon Master", "source": "PHB", "id": "feat:weapon master|phb|"}]
	var master_suggestions: Array[Dictionary] = Proficiencies.suggest_origins(feat_record, "weapon", "rapier")
	var feat_is_optional := false
	for suggestion: Dictionary in master_suggestions:
		if String(suggestion.get("group", "")) == "feat" and int(suggestion.get("certainty", 0)) == 1:
			feat_is_optional = true
	assert(feat_is_optional, "Weapon Master structured selectable martial weapon is only an optional source")

	var legacy := _record()
	legacy.erase("proficiency_choices")
	legacy["skill_proficiencies"] = []
	legacy = PlayerStore.new().normalize_character(legacy)
	assert(Proficiencies.has_proficiency(legacy, "weapon", "rapier"),
		"Legacy per-attack item proficiency migrates to shared weapon-name training")
	for old_attack_id: String in ["item:off:weapon:rapier|phb|m", "item:throw:main:weapon:rapier|phb|m"]:
		var old_record := _record()
		old_record.erase("proficiency_choices")
		old_record["skill_proficiencies"] = []
		old_record["attack_overrides"] = {old_attack_id: {"proficient": true}}
		old_record = PlayerStore.new().normalize_character(old_record)
		assert(Proficiencies.has_proficiency(old_record, "weapon", "rapier"),
			"Legacy offhand and thrown proficiencies must migrate to shared weapon training")

	var tab := ProficiencyTab.new()
	root.add_child(tab)
	var changed: Array = []
	tab.setup(func(profs: Array, feats: Array, origin_rows: Array) -> void:
		changed.append({"profs": profs, "feats": feats, "origins": origin_rows}))
	tab.load_record(record)
	assert(tab._origins.size() > 0, "Source list is populated by eligible structured origins")
	tab._select_origin("class|phb|fighter")
	assert(tab._selected_id == "class|phb|fighter", "Clicking an origin selects/highlights its proficiencies")
	tab._select_origin("class|phb|fighter")
	assert(tab._selected_id == "~none~", "Clicking the same origin clears the highlight")
	tab._select_origin("class|phb|fighter")
	tab._kind_picker.select(0)
	tab._proficiency_name.text = "longsword"
	tab._add_competence()
	assert(not changed.is_empty() and Proficiencies.has_choice(changed.back().profs, "weapon", "longsword"),
		"Users can explicitly add a proficiency to a selected origin")
	var last: int = tab._rows.size() - 1
	tab._toggle_competence(false, last)
	assert(bool(tab._rows[last].get("disabled", false)), "Individual competence can be disabled")
	tab._kind_picker.select(2)
	tab._proficiency_name.text = "perception"
	tab._add_competence()
	last = tab._rows.size() - 1
	tab._set_expertise(true, last)
	assert(Proficiencies.has_choice(tab._rows, "expertise", "perception"), "Switch upgrades a skill to expertise")
	tab._toggle_origin(false, "class|phb|fighter")
	assert(not Proficiencies.has_proficiency(tab._effective_record(), "weapon", "martial"),
		"Disabling a source suppresses all its linked proficiencies")
	tab.queue_free()
	await process_frame
	print("PASS: automatically granted structured proficiencies, choose warnings, toggles, source highlights and migration")
	quit()
