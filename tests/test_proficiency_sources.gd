extends SceneTree

const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")
const ProficiencyTab = preload("res://vtt/creature_proficiencies_tab.gd")
const Attacks = preload("res://vtt/creature_attack_data.gd")
const PlayerStore = preload("res://vtt/player_character_store.gd")
const Traits = preload("res://vtt/creature_traits_tab.gd")
const Catalog = preload("res://vtt/player_5etools_catalog.gd")


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
		"proficiency_choices": [{"kind": "skill", "key": "athletics", "origin_id": "",
			"origin_name": "", "disabled": false}]
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

	var barbarian := _record()
	barbarian["class"] = "Barbarian"
	barbarian["classes"] = [{"name": "Barbarian", "source": "PHB", "level": 1}]
	var barbarian_origins: Array[Dictionary] = Proficiencies.origins(barbarian)
	var barbarian_start: Dictionary = {}
	for source: Dictionary in barbarian_origins:
		if String(source.get("id", "")) == "class|phb|barbarian":
			barbarian_start = source
	assert(not barbarian_start.is_empty(), "Starting Barbarian automatically appears among sources")
	var armor_quests: Array[Dictionary] = Proficiencies.choice_requirements(barbarian_start)
	for request: Dictionary in armor_quests:
		assert(String(request.get("kind", "")) != "armor",
			"Fixed Barbarian armor proficiency must not create phantom choose requirements")
	var barbarian_rows: Array[Dictionary] = Proficiencies.choices(barbarian)
	for key: String in ["simple", "martial"]:
		assert(Proficiencies.has_choice(barbarian_rows, "weapon", key), "Barbarian starting weapon proficiencies")
	for key: String in ["light", "medium", "shield"]:
		assert(Proficiencies.has_choice(barbarian_rows, "armor", key), "Barbarian starting armor")
	assert(Proficiencies.has_choice(barbarian_rows, "save", "con"), "Barbarian Constitution save")
	assert(not Proficiencies.has_choice(barbarian_rows, "skill", "survival"),
		"Starting Barbarian cannot preselect any choose-2 skill")
	# The Barbarian's choose field is a nested Dictionary, not a fixed
	# boolean proficiency. It must render without a runtime type error.
	var choice_summary: String = Proficiencies._readable_grants([{
		"choose": {"from": ["athletics", "survival"], "count": 1},
		"acrobatics": true, "anyStandard": 1
	}])
	assert("Choose 1" in choice_summary and "Acrobatics" in choice_summary,
		"Structured nested choices and fixed boolean grants render together")
	var no_false_grant: Array[Dictionary] = Proficiencies.fixed_grants({
		"group": "feat", "data": {"skillProficiencies": [{
			"choose": {"from": ["athletics", "survival"], "count": 1},
			"perception": true
		}]}
	})
	assert(Proficiencies.has_choice(no_false_grant, "skill", "perception")
		and not Proficiencies.has_choice(no_false_grant, "skill", "athletics"),
		"Nested structured choose data must not become an unconditional grant")
	# Smoke-test every bundled class, including optional pools and 2024
	# variants: descriptions must never assume a nested grant is a boolean.
	var index_file: FileAccess = FileAccess.open(
		"res://vtt/data/proficiency_grants_5etools.json", FileAccess.READ
	)
	assert(index_file != null, "Structured proficiency index must be bundled")
	var index_data: Variant = JSON.parse_string(index_file.get_as_text())
	index_file.close()
	assert(index_data is Dictionary, "Structured proficiency index must parse")
	var class_count := 0
	for indexed_class: Variant in (index_data as Dictionary).get("class", []):
		if not indexed_class is Dictionary:
			continue
		for mode: String in ["starting", "multiclass"]:
			var candidate: Dictionary = {"group": "class", "data": indexed_class, "mode": mode}
			var description: String = Proficiencies.starting_description(candidate)
			assert(("Core Traits" if mode == "starting" else "Multiclassing") in description,
				"Every bundled class summary must match its mode and render without type errors")
			Proficiencies.fixed_grants(candidate)
		class_count += 1
	assert(class_count >= 20, "Both PHB 2014 and PHB 2024 structured classes should be covered")
	var specific: Array[Dictionary] = Proficiencies.fixed_grants({
		"group": "class", "mode": "starting",
		"data": {"startingProficiencies": {
			"weapons": ["simple", "{@item rapier|PHB|rapiers}"],
			"toolProficiencies": [{"thieves' tools": true}]
		}}
	})
	assert(Proficiencies.has_choice(specific, "weapon", "rapier")
		and Proficiencies.has_choice(specific, "tool", "thieves' tools"),
		"Individual weapon and tool proficiencies from structured data remain visible")
	var starting_trait_found := false
	for feature_entry: Dictionary in Traits.collect_features(barbarian):
		if String(feature_entry.get("name", "")) == "Starting Barbarian" and int(feature_entry.get("level", 0)) == 1:
			starting_trait_found = "Hit Point Die: 1d12" in String(feature_entry.get("entries", ""))
	assert(starting_trait_found, "Synthetic Starting Barbarian trait includes structured hit dice and core summary")
	var secondary := _record()
	secondary["class"] = "Bard"
	secondary["class_source"] = "PHB"
	secondary["classes"] = [
		{"name": "Bard", "source": "PHB", "level": 1},
		{"name": "Barbarian", "source": "PHB", "level": 1}
	]
	var secondary_features: Array[Dictionary] = Traits.collect_features(secondary)
	var multiclass_found := false
	for feature_entry: Dictionary in secondary_features:
		if String(feature_entry.get("name", "")) == "Multiclass Barbarian":
			multiclass_found = not ("Starting Equipment" in String(feature_entry.get("entries", "")))
	assert(multiclass_found, "Secondary classes show Multiclass rather than Starting and omit starting equipment")
	var multiclass_rows: Array[Dictionary] = Proficiencies.choices(secondary)
	var barbarian_armor: Array[String] = []
	for row: Dictionary in multiclass_rows:
		if String(row.get("origin_id", "")) == "class|phb|barbarian" and String(row.get("kind", "")) == "armor":
			barbarian_armor.append(String(row.get("key", "")))
	assert(barbarian_armor == ["shield"],
		"Barbarian secondary class grants only its multiclass shield training")
	var monster_base := _record()
	monster_base["kind"] = "monster"
	monster_base["class"] = "mostro"
	monster_base["class_source"] = "BESTIARY"
	monster_base["classes"] = [
		{"name": "mostro", "source": "BESTIARY", "level": 2},
		{"name": "Barbarian", "source": "PHB", "level": 1}
	]
	var monster_multiclass_found := false
	for source: Dictionary in Proficiencies.candidate_sources(monster_base):
		if String(source.get("id", "")) == "class|phb|barbarian":
			monster_multiclass_found = String(source.get("mode", "")) == "multiclass"
	assert(monster_multiclass_found,
		"Character classes added after a monster base must use Multiclass grants")
	var revised := _record()
	revised["rules_version"] = "2024"
	revised["class"] = "Barbarian"
	revised["class_source"] = "XPHB"
	revised["classes"] = [{"name": "Barbarian", "source": "XPHB", "level": 1}]
	assert(Proficiencies.has_proficiency(revised, "weapon", "martial"),
		"XPHB 2024 Barbarian starting class also uses structured grants")

	var background_options: Array[Dictionary] = Catalog.entries("backgrounds")
	var acolyte_selectable := false
	for option: Dictionary in background_options:
		if String(option.get("name", "")) == "Acolyte" and String(option.get("source", "")) == "PHB":
			acolyte_selectable = true
	assert(acolyte_selectable, "Background dropdown must include structured Acolyte even when player catalog is empty")
	var background_record := _record()
	background_record["background"] = "Acolyte"
	# Legacy character sheets keep only a background name.
	var background_sources: Array[Dictionary] = Proficiencies.suggest_origins(background_record, "skill", "insight")
	var has_acolyte := false
	for suggestion: Dictionary in background_sources:
		if String(suggestion.get("group", "")) == "background" and int(suggestion.get("certainty", 0)) == 2:
			has_acolyte = true
	assert(has_acolyte, "Structured background proficiencies are suggested without a stored source book")
	background_record["background_source"] = "PHB"
	assert(Proficiencies.has_proficiency(background_record, "skill", "insight")
		and Proficiencies.has_proficiency(background_record, "skill", "religion"),
		"Acolyte should grant its structured background skills")
	background_record["proficiency_origins"] = Proficiencies.origins(background_record)
	background_record["proficiency_choices"] = Proficiencies.choices(background_record)
	background_record["background"] = "Folk Hero"
	assert(not Proficiencies.has_proficiency(background_record, "skill", "religion")
		and Proficiencies.has_proficiency(background_record, "skill", "survival"),
		"Changing background must replace old structured proficiencies")
	for source: Dictionary in Proficiencies.origins(background_record):
		assert(not String(source.get("id", "")).begins_with("background|phb|acolyte"),
			"Obsolete backgrounds must disappear from stored origins")
	var changed_race := _record()
	changed_race["species"] = "Elf"
	changed_race["species_source"] = "PHB"
	assert(Proficiencies.has_proficiency(changed_race, "skill", "perception"))
	changed_race["proficiency_origins"] = Proficiencies.origins(changed_race)
	changed_race["proficiency_choices"] = Proficiencies.choices(changed_race)
	changed_race["species"] = "Dwarf"
	assert(not Proficiencies.has_proficiency(changed_race, "skill", "perception"),
		"Racial proficiencies from the previous species must no longer apply")
	for source: Dictionary in Proficiencies.origins(changed_race):
		assert(not String(source.get("id", "")).begins_with("race|phb|elf"),
			"Old race must disappear rather than linger as a disabled origin")
	assert(not Proficiencies.source_has_grants({"group": "race",
		"data": {"name": "Empty Race", "skillProficiencies": [{"choose": {}}]}}),
		"Races without fixed grants or valid choices must not create automatic origins")
	# A manually attributed trait must vanish when its originating feature
	# is removed (e.g. when a race or creature trait changes).
	var trait_creature: Dictionary = {
		"kind": "monster", "stat_block": {"trait": [{"name": "Guardiano", "entries": ["Protegge gli alleati"]}]},
		"proficiency_origins": [], "proficiency_choices": []
	}
	var live_traits: Array[Dictionary] = Traits.collect_features(trait_creature)
	assert(not live_traits.is_empty(), "Monster should expose its structured trait")
	var trait_sid: String = "feature:" + String(live_traits[0].get("key", ""))
	trait_creature["proficiency_origins"] = [{"id": trait_sid, "name": "Tratto · Guardiano", "automatic": false}]
	trait_creature["proficiency_choices"] = [{"kind": "skill", "key": "stealth", "origin_id": trait_sid, "disabled": false}]
	assert(Proficiencies.has_proficiency(trait_creature, "skill", "stealth"),
		"An existing trait can explicitly grant a proficiency")
	(trait_creature["stat_block"] as Dictionary)["trait"] = []
	assert(not Proficiencies.has_proficiency(trait_creature, "skill", "stealth"),
		"Removed trait must revoke its related proficiency")
	for withdrawn: Dictionary in Proficiencies.origins(trait_creature):
		assert(String(withdrawn.get("id", "")) != trait_sid,
			"Removed feature must not persist as an orphan origin")

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
	assert(Proficiencies.grant_matches([{"any": 3}], "weapon", "martial") == 0,
		"Choosing individual weapons must not offer the whole martial weapon category")
	assert(Proficiencies.grant_matches([{"any": 3}], "weapon", "rapier") == 1,
		"Choosing individual weapons continues to offer specific weapons")

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
	assert("Hit Point Die" in tab._origin_description(tab._selected_source_record()),
		"Source hover includes the original class overview description")
	var item_record: Dictionary = _record()
	item_record["inventory"] = [{"id": "test:tool", "name": "Manuale di prova",
		"description": "Descrizione dell'oggetto origine"}]
	item_record["proficiency_origins"] = [{"id": "item:test:tool",
		"name": "Oggetto · Manuale di prova", "group": "custom", "disabled": false}]
	tab.load_record(item_record)
	var item_origin: Dictionary = {}
	for source: Dictionary in tab._origins:
		if String(source.get("id", "")) == "item:test:tool":
			item_origin = source
	assert("Descrizione dell'oggetto origine" in tab._origin_description(item_origin),
		"Origin hover must show the full description of the item")
	tab.load_record(record)
	tab._selected_id = "~none~"
	tab._select_origin("class|phb|fighter")
	tab._kind_picker.select(2)
	tab._refresh_proficiency_picker()
	var restricted: Array[String] = Proficiencies.restricted_choices(tab._selected_source_record(), "skill")
	assert("athletics" in restricted and "arcana" not in restricted,
		"Fighter choices are limited to the structured skill list")
	tab._proficiency_name.text = "arcana"
	var count_before: int = tab._rows.size()
	tab._add_competence()
	assert(tab._rows.size() == count_before, "Cannot add an unlisted skill from this source")
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
	# The same competence is shown once even if different sources grant it.
	tab._rows.append({"kind": "tool", "key": "thieves' tools", "origin_id": "custom|a", "disabled": false})
	tab._refresh_competences()
	var before_duplicate: int = tab._proficiency_cards.get_child_count()
	tab._rows.append({"kind": "tool", "key": "thieves' tools", "origin_id": "custom|b", "disabled": false})
	tab._refresh_competences()
	assert(tab._proficiency_cards.get_child_count() == before_duplicate,
		"Duplicate grants from different origins appear once in the UI")
	tab._toggle_origin(false, "class|phb|fighter")
	assert(not Proficiencies.has_proficiency(tab._effective_record(), "weapon", "martial"),
		"Disabling a source suppresses all its linked proficiencies")
	# The missing-choice warning is a separate, clickable control rather
	# than a clipped glyph at the start of a long origin name.
	tab.load_record(record)
	var warning_visible := false
	for card: Node in tab._origin_cards.get_children():
		var line: Node = card.get_child(0)
		for child: Node in line.get_children():
			if child is Button and (child as Button).text == "⚠":
				warning_visible = true
	assert(warning_visible, "Unresolved structured choices must have a visible warning button")
	tab._open_missing_choices("class|phb|fighter")
	var skill_group: Dictionary = {}
	for candidate: Dictionary in tab._choice_groups:
		if String(candidate.get("kind", "")) == "skill":
			skill_group = candidate
	assert(not skill_group.is_empty() and (skill_group.get("boxes") as Array).size() == 6,
		"Fighter's warning opens the six structured skill options")
	for entry: Dictionary in skill_group.get("boxes", []):
		if String(entry.get("key", "")) in ["athletics", "perception"]:
			(entry.get("check") as CheckBox).set_pressed_no_signal(true)
	tab._refresh_choice_limit(skill_group)
	var enabled_unchecked := 0
	for entry: Dictionary in skill_group.get("boxes", []):
		var check: CheckBox = entry.get("check")
		if not check.button_pressed and not check.disabled:
			enabled_unchecked += 1
	assert(enabled_unchecked == 0, "A full choice quota prevents selecting more proficiencies")
	tab._apply_choice_dialog()
	tab._choice_dialog.hide()
	var chosen_index := -1
	for i: int in range(tab._rows.size()):
		var grant: Dictionary = tab._rows[i]
		if String(grant.get("origin_id", "")) == "class|phb|fighter" and String(grant.get("kind", "")) == "skill" and String(grant.get("key", "")) == "perception":
			chosen_index = i
			break
	assert(chosen_index >= 0 and Proficiencies.has_proficiency(tab._effective_record(), "skill", "perception"),
		"Confirming the warning dialog persists the selected skill")
	tab._delete_manual_group([chosen_index])
	assert(not Proficiencies.has_proficiency(tab._effective_record(), "skill", "perception"),
		"Selected source choices can be permanently removed, not just disabled")
	var orphan_index: int = tab._rows.size()
	tab._rows.append({"kind": "language", "key": "draconic", "origin_id": "", "disabled": false})
	tab._selected_id = "~none~"
	tab._delete_manual_group([orphan_index])
	assert(not Proficiencies.has_choice(tab._rows, "language", "draconic"),
		"Unassigned manual proficiency can be permanently removed")
	var fixed_index := -1
	for i: int in range(tab._rows.size()):
		if String(tab._rows[i].get("kind", "")) == "weapon" and String(tab._rows[i].get("key", "")) == "martial":
			fixed_index = i
			break
	assert(fixed_index >= 0 and bool(tab._rows[fixed_index].get("automatic", false)))
	tab._delete_manual_group([fixed_index])
	assert(Proficiencies.has_choice(tab._rows, "weapon", "martial"),
		"Fixed class proficiencies cannot be deleted from the manual-choice editor")
	# Interleave types to ensure headings are rendered only once.
	tab._rows.append({"kind": "weapon", "key": "rapier", "origin_id": "", "disabled": false})
	tab._rows.append({"kind": "skill", "key": "arcana", "origin_id": "", "disabled": false})
	tab._rows.append({"kind": "weapon", "key": "dagger", "origin_id": "", "disabled": false})
	tab._refresh_competences()
	var heading_names: Array[String] = []
	var has_link_button := false
	var has_mastery_word := false
	for card: Node in tab._proficiency_cards.get_children():
		if card is Label:
			heading_names.append((card as Label).text)
		for child: Node in card.get_children():
			if child is HBoxContainer:
				for control: Node in child.get_children():
					if control is Button and (control as Button).text == "↳":
						has_link_button = true
					if control is CheckButton and (control as CheckButton).text == "Mestria":
						has_mastery_word = true
	assert(heading_names.count("Abilità") == 1
		and heading_names.count("Categorie di armi") == 1
		and heading_names.count("Singole armi") == 1,
		"Skill and weapon headings must never repeat with interleaved grants")
	assert(not has_link_button and has_mastery_word,
		"Manual linking action is removed and stars are replaced by Mestria")
	# Deleting a shared skill requires the source (or all sources).
	tab.load_record(_record())
	tab._rows.append({"kind": "skill", "key": "insight", "origin_id": "custom|first", "disabled": false})
	tab._rows.append({"kind": "skill", "key": "insight", "origin_id": "custom|second", "disabled": false})
	tab._refresh_competences()
	tab._request_delete_competence("skill", "insight")
	assert(tab._delete_dialog.visible and tab._delete_picker.item_count == 3,
		"Shared proficiency deletion must ask for a specific origin or all origins")
	tab._delete_picker.select(1)
	tab._confirm_delete_competence()
	tab._delete_dialog.hide()
	assert(tab._deletable_sources("skill", "insight").size() == 1,
		"Deleting from one source must preserve other sources")
	tab._request_delete_competence("skill", "insight")
	assert(tab._deletable_sources("skill", "insight").size() == 0,
		"Deleting the last remaining source removes the skill")
	var required: Array[Dictionary] = Proficiencies.choices(_record())
	var fighter_index := -1
	for i: int in range(required.size()):
		if String(required[i].get("origin_id", "")) == "class|phb|fighter" and String(required[i].get("kind", "")) == "weapon" and String(required[i].get("key", "")) == "martial":
			fighter_index = i
			break
	assert(fighter_index >= 0, "Fighter's martial training is a required grant")
	tab.load_record(_record())
	var fixed_before := Proficiencies.has_choice(tab._rows, "weapon", "martial")
	tab._delete_competence_from_source("weapon", "martial", "~all~")
	assert(fixed_before and Proficiencies.has_choice(tab._rows, "weapon", "martial"),
		"Required grants cannot be deleted even by choosing all origins")
	tab._select_origin("class|phb|fighter")
	var unrelated := tab._rows.size()
	tab._rows.append({"kind": "skill", "key": "nature", "origin_id": "custom|separate", "disabled": false})
	assert(tab._group_enabled([unrelated]), "Selecting a different origin must not show active proficiencies as off")
	tab.queue_free()
	await process_frame
	print("PASS: automatically granted structured proficiencies, choose warnings, toggles, source highlights and migration")
	quit()
