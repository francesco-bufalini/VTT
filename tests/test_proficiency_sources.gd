extends SceneTree

const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")
const ProficiencyTab = preload("res://vtt/creature_proficiencies_tab.gd")
const Attacks = preload("res://vtt/creature_attack_data.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
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
	_check_index_parity()
	_check_feat_origin_chains()
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
	var additive_attack: Dictionary = weapon.duplicate(true)
	additive_attack["damage"] = "1d8+2"
	assert(Attacks.damage_expression(record, additive_attack).ends_with("+2+4"),
		"Rolling damage must retain base and ability bonuses when both appear in the displayed formula")
	record["proficiency_origins"] = [{"id": "class|phb|fighter", "name": "Starting Fighter", "automatic": true, "disabled": true}]
	assert(Attacks.attack_bonus(record, weapon, 2) == 4,
		"Muting a mandatory class origin temporarily removes its attack proficiency bonus")
	var normalized_sources: Array[Dictionary] = Proficiencies.origins(record)
	for normalized: Dictionary in normalized_sources:
		if String(normalized.get("id", "")) == "class|phb|fighter":
			assert(bool(normalized.get("disabled", false)), "Mandatory sources retain their disabled state on load")
	record["proficiency_origins"][0]["disabled"] = false
	assert(Attacks.attack_bonus(record, weapon, 2) == 6,
		"Reactivating a mandatory origin restores its unmodified grants")
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
	monster_base["class"] = "Barbarian"
	monster_base["class_source"] = "PHB"
	monster_base["classes"] = [
		{"name": "Barbarian", "source": "PHB", "level": 1}
	]
	var monster_starting_found := false
	for source: Dictionary in Proficiencies.candidate_sources(monster_base):
		if String(source.get("id", "")) == "class|phb|barbarian":
			monster_starting_found = String(source.get("mode", "")) == "starting"
	assert(monster_starting_found,
		"Each playable class added to a monster uses Starting grants")
	assert(Proficiencies.has_proficiency(monster_base, "weapon", "martial"),
		"Starting monster-added Barbarian receives martial weapon training")
	monster_base["classes"].append({"name": "Fighter", "source": "PHB", "level": 1})
	var fighter_starting := false
	for source: Dictionary in Proficiencies.candidate_sources(monster_base):
		if String(source.get("id", "")) == "class|phb|fighter":
			fighter_starting = String(source.get("mode", "")) == "starting"
	assert(fighter_starting, "Multiple added monster classes each receive Starting privileges")
	# Flattened 5etools subrace entries include all parent racial features.
	# Origin-grant bookkeeping still needs two distinct source identities.
	var high_elf := _record()
	high_elf["species"] = "Elf"
	high_elf["species_source"] = "PHB"
	high_elf["subrace"] = "High"
	high_elf["subrace_source"] = "PHB"
	assert(Proficiencies.has_proficiency(high_elf, "skill", "perception"),
		"High Elf inherits the parent Elf's Perception proficiency")
	assert(Proficiencies.has_proficiency(high_elf, "weapon", "longsword"),
		"High Elf receives structured subrace weapon proficiency")
	var race_found := false
	var subrace_found := false
	for origin: Dictionary in Proficiencies.candidate_sources(high_elf):
		if String(origin.get("id", "")) == "race|phb|elf":
			race_found = true
		if String(origin.get("id", "")) == "subrace|phb|high":
			subrace_found = true
	assert(race_found and subrace_found, "Base and subrace grants have distinct origins")
	var wood_elf := high_elf.duplicate(true)
	wood_elf["subrace"] = "Wood"
	var stale_high_origin := false
	for origin: Dictionary in Proficiencies.candidate_sources(wood_elf):
		if String(origin.get("id", "")) == "subrace|phb|high":
			stale_high_origin = true
	assert(not stale_high_origin, "Changing subrace removes the old source")
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
		"Fixed class proficiencies can be muted by switching their origin off")
	var muted_index := -1
	for row_index: int in range(tab._rows.size()):
		var muted_row: Dictionary = tab._rows[row_index]
		if (String(muted_row.get("origin_id", "")) == "class|phb|fighter"
			and String(muted_row.get("kind", "")) == "weapon"
			and String(muted_row.get("key", "")) == "martial"):
			muted_index = row_index
			break
	assert(muted_index >= 0 and not tab._group_enabled([muted_index]),
		"Muted source must show its proficiencies as inactive")
	tab._toggle_origin(true, "class|phb|fighter")
	assert(Proficiencies.has_proficiency(tab._effective_record(), "weapon", "martial"),
		"Reactivating an origin restores fixed grants without rewriting rows")
	# A 5etools background can require a language and an artisan tool.
	# Both must be reachable in the same dialog, and opening again should
	# focus the first incomplete category rather than always the language.
	var dual_choice_record: Dictionary = _record()
	dual_choice_record["background"] = "Guild Artisan"
	dual_choice_record["background_source"] = "PHB"
	tab.load_record(dual_choice_record)
	tab._open_missing_choices("background|phb|guild artisan")
	var tool_choice: Dictionary = {}
	var language_choice: Dictionary = {}
	for choice: Dictionary in tab._choice_groups:
		if String(choice.get("kind", "")) == "tool":
			tool_choice = choice
		if String(choice.get("kind", "")) == "language":
			language_choice = choice
	assert(not tool_choice.is_empty() and not language_choice.is_empty(),
		"Guild Artisan must expose tool and language as separate selectable groups")
	assert(not (tool_choice.get("boxes") as Array).is_empty(),
		"Artisan tool choice must work even without a complete player tool catalog")
	var tool_group_index: int = int(tool_choice.get("index", -1))
	var language_group_index: int = int(language_choice.get("index", -1))
	tab._show_choice_group(tool_group_index)
	assert((tool_choice.get("panel") as VBoxContainer).visible
		and not (language_choice.get("panel") as VBoxContainer).visible,
		"Tool group must become visible when chosen in the popup")
	tab._show_choice_group(language_group_index)
	assert((language_choice.get("panel") as VBoxContainer).visible,
		"Language choices must still be reachable afterwards")
	var tool_option: Dictionary = (tool_choice.get("boxes") as Array)[0]
	(tool_option.get("check") as CheckBox).set_pressed_no_signal(true)
	tab._refresh_choice_limit(tool_choice)
	tab._apply_choice_dialog()
	tab._choice_dialog.hide()
	assert(Proficiencies.has_proficiency(tab._effective_record(), "tool", String(tool_option.get("key", ""))),
		"Confirming the dialog must persist the selected artisan tool")
	var guild_origin: Dictionary = {}
	for source: Dictionary in Proficiencies.origins(tab._effective_record()):
		if String(source.get("id", "")) == "background|phb|guild artisan":
			guild_origin = source
	assert(not guild_origin.is_empty(), "The selected background is a proficiency origin")
	var still_missing: Array[String] = Proficiencies.requirement_missing(
		guild_origin, tab._rows, tab._enabled_map())
	var tool_missing := false
	var language_missing := false
	for missing_entry: String in still_missing:
		tool_missing = tool_missing or missing_entry.begins_with("tool ")
		language_missing = language_missing or missing_entry.begins_with("language ")
	assert(not tool_missing and language_missing,
		"Artisan tool choice must count toward its quota while language remains missing")
	tab._open_missing_choices("background|phb|guild artisan")
	assert(tab._choice_selector.selected == language_group_index,
		"After choosing an artisan tool, the popup must focus the still-missing language")
	var remaining_language_group: Dictionary = tab._choice_groups[language_group_index]
	assert(not (remaining_language_group.get("boxes") as Array).is_empty(),
		"A language selection must still be available after completing the tool group")
	var language_option: Dictionary = (remaining_language_group.get("boxes") as Array)[0]
	(language_option.get("check") as CheckBox).set_pressed_no_signal(true)
	tab._refresh_choice_limit(remaining_language_group)
	tab._apply_choice_dialog()
	tab._choice_dialog.hide()
	assert(Proficiencies.has_proficiency(tab._effective_record(), "tool", String(tool_option.get("key", "")))
		and Proficiencies.has_proficiency(tab._effective_record(), "language", String(language_option.get("key", ""))),
		"The confirmed language and artisan tool must coexist on the same background")
	tab.load_record(record)
	var illuminated_record: Dictionary = record.duplicate(true)
	illuminated_record["proficiency_origins"] = [
		{"id": "custom|light", "name": "Luce", "group": "custom", "disabled": false}
	]
	illuminated_record["proficiency_choices"] = [
		{"kind": "skill", "key": "nature", "origin_id": "custom|light", "disabled": false}
	]
	tab.load_record(illuminated_record)
	tab._select_origin("class|phb|fighter")
	var light_card: PanelContainer = null
	for node: Node in tab._proficiency_cards.get_children():
		if not node is PanelContainer:
			continue
		for row_node: Node in node.get_children():
			if row_node is HBoxContainer:
				for entry_node: Node in row_node.get_children():
					if entry_node is Label and String((entry_node as Label).text).contains("nature"):
						light_card = node as PanelContainer
	assert(light_card != null and light_card.has_theme_stylebox_override("panel"),
		"Other-source active skills must remain illuminated while a different origin is selected")
	tab._select_origin("class|phb|fighter")
	assert(light_card != null, "Previously selected source can be deselected")
	var nature_outline := false
	for node: Node in tab._proficiency_cards.get_children():
		if not node is PanelContainer or not (node as PanelContainer).has_theme_stylebox_override("panel"):
			continue
		for row_node: Node in node.get_children():
			if row_node is HBoxContainer:
				for entry_node: Node in row_node.get_children():
					if entry_node is Label and String((entry_node as Label).text).contains("nature"):
						nature_outline = true
	assert(nature_outline, "Skills must remain lit after deselecting the focused origin")
	tab.load_record(record)
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
	assert(not skill_group.is_empty() and (skill_group.get("boxes") as Array).size() == 8,
		"Fighter's warning opens the eight structured skill options")
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
	# Fixed and manually removable rows must have the same layout, even
	# while another origin is highlighted (the reported armor/tool mismatch).
	tab._selected_id = "class|phb|fighter"
	tab._rows.append({"kind": "tool", "key": "dice set", "origin_id": "", "disabled": false})
	tab._refresh_competences()
	var armor_card: PanelContainer = null
	var tool_card: PanelContainer = null
	var manual_switch: CheckButton = null
	for node: Node in tab._proficiency_cards.get_children():
		if not node is PanelContainer:
			continue
		var content: HBoxContainer = node.get_child(0) as HBoxContainer
		if content == null:
			continue
		for control: Node in content.get_children():
			if not control is Label:
				continue
			var title_text: String = String((control as Label).text)
			if title_text.ends_with("light"):
				armor_card = node as PanelContainer
			if title_text.ends_with("dice set"):
				tool_card = node as PanelContainer
				for sibling: Node in content.get_children():
					if sibling is CheckButton and (sibling as CheckButton).text == "⏻":
						manual_switch = sibling as CheckButton
	assert(armor_card != null and tool_card != null and manual_switch != null,
		"Mandatory armor and separately sourced tool must render with activation switches")
	var armor_style: StyleBox = armor_card.get_theme_stylebox("panel")
	var tool_style: StyleBox = tool_card.get_theme_stylebox("panel")
	assert(armor_card.custom_minimum_size.y == tool_card.custom_minimum_size.y
		and is_equal_approx(armor_style.get_content_margin(SIDE_LEFT), tool_style.get_content_margin(SIDE_LEFT))
		and is_equal_approx(armor_style.get_content_margin(SIDE_TOP), tool_style.get_content_margin(SIDE_TOP)),
		"Armor and tool rows must use exactly the same padding and height")
	assert(not manual_switch.disabled, "An unrelated selected origin must not block the tool switch")
	var tool_index: int = -1
	for i: int in range(tab._rows.size()):
		if String(tab._rows[i].get("kind", "")) == "tool" and String(tab._rows[i].get("key", "")) == "dice set":
			tool_index = i
			break
	assert(tool_index >= 0, "The manual tool must be present in its origin")
	tab._toggle_group(false, [tool_index])
	assert(not tab._group_enabled([tool_index]) and bool(tab._rows[tool_index].get("disabled", false)),
		"Competences from other origins remain individually deactivatable")
	tab._toggle_group(true, [tool_index])
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
	assert(Proficiencies.is_mandatory_grant(_record(), "class|phb|fighter", "weapon", "martial"),
		"Martial weapon category must be recognized as a fixed class grant")
	assert(not Proficiencies.is_mandatory_grant(_record(), "", "weapon", "martial"),
		"Unknown origin may always be explicitly removed")
	assert(tab._deletable_sources("weapon", "martial").is_empty(),
		"The UI must not offer a delete button when all sources are mandatory")
	var mandatory_index: int = -1
	for i: int in range(tab._rows.size()):
		if String(tab._rows[i].get("origin_id", "")) == "class|phb|fighter" and String(tab._rows[i].get("kind", "")) == "weapon" and String(tab._rows[i].get("key", "")) == "martial":
			mandatory_index = i
			break
	assert(mandatory_index >= 0 and tab._is_mandatory_choice(tab._rows[mandatory_index]))
	tab._toggle_competence(false, mandatory_index)
	assert(bool(tab._rows[mandatory_index].get("disabled", false)),
		"Mandatory proficiency can be deactivated individually without deleting it")
	assert(not Proficiencies.has_proficiency(tab._effective_record(), "weapon", "martial"),
		"A muted fixed grant must stop contributing to the effective proficiency")
	tab._refresh_competences()
	var fixed_control: CheckButton = null
	var fixed_card: PanelContainer = null
	for card_node: Node in tab._proficiency_cards.get_children():
		if not card_node is PanelContainer:
			continue
		for container_node: Node in card_node.get_children():
			if container_node is HBoxContainer:
				var has_martial := false
				for child_node: Node in container_node.get_children():
					if child_node is Label and String((child_node as Label).text).contains("martial"):
						has_martial = true
				if has_martial:
					fixed_card = card_node as PanelContainer
					for child_node: Node in container_node.get_children():
						if child_node is CheckButton and (child_node as CheckButton).text == "⏻":
							fixed_control = child_node as CheckButton
	assert(fixed_control != null and not fixed_control.disabled
		and fixed_card != null, "Fixed grants must have a usable on/off switch")
	tab._toggle_group(true, [mandatory_index])
	assert(not bool(tab._rows[mandatory_index].get("disabled", true)),
		"Fixed grant can be reactivated without adding a new source grant")
	tab._toggle_group(false, [mandatory_index])
	var saved_fixed: Dictionary = tab._effective_record()
	var reloaded_fixed: Dictionary = {}
	for stored_row: Dictionary in Proficiencies.choices(saved_fixed):
		if (String(stored_row.get("origin_id", "")) == "class|phb|fighter"
			and String(stored_row.get("kind", "")) == "weapon"
			and String(stored_row.get("key", "")) == "martial"):
			reloaded_fixed = stored_row
			break
	assert(not Proficiencies.has_proficiency(saved_fixed, "weapon", "martial")
		and not reloaded_fixed.is_empty()
		and bool(reloaded_fixed.get("disabled", false))
		and bool(reloaded_fixed.get("automatic", false)),
		"Disabled mandatory grant survives serialization without becoming removable")
	tab._toggle_group(true, [mandatory_index])
	tab._select_origin("class|phb|fighter")
	var unrelated := tab._rows.size()
	tab._rows.append({"kind": "skill", "key": "nature", "origin_id": "custom|separate", "disabled": false})
	assert(tab._group_enabled([unrelated]), "Selecting a different origin must not show active proficiencies as off")
	# Both hidden catalog languages must appear in the 2014 picker.
	tab.load_record(_record())
	for expected: String in ["deep speech", "druidic"]:
		var found := false
		for entry: Dictionary in tab._catalog_entries_for_kind("language"):
			if String(entry.get("key", "")) == expected:
				found = true
				break
		assert(found, "Missing core/secret 5etools language: " + expected)
	assert(Proficiencies.grant_matches([{"anyExotic": 1}], "language", "deep speech") == 1,
		"Deep Speech is a selectable exotic language")
	assert(Proficiencies.grant_matches([{"anyExotic": 1}], "language", "druidic") == 0,
		"Secret Druidic must not be offered as an arbitrary exotic language")
	tab.load_record(_record())
	var owned_feat: Dictionary = {"id": "feat:test-source", "name": "Feat Source", "source": "HB"}
	tab._attach_feat(owned_feat, "class|phb|fighter")
	tab._refresh_from_current_state()
	assert(not tab._feats.is_empty() and String(tab._feats[0].get("origin_id", "")) == "class|phb|fighter",
		"Adding a feat to a chosen origin stores the granting source")
	var feat_source_sid: String = Proficiencies.feat_source_id(owned_feat)
	assert(tab._origin_exists(feat_source_sid),
		"Even homebrew feats without a structured proficiency grant are usable origins")
	tab._toggle_feat_grants(false, [0])
	assert(not bool(Proficiencies.origin_enabled_map(tab._effective_record()).get(feat_source_sid, true)),
		"Feat switch disables the source without deleting the feat")
	tab._toggle_feat_grants(true, [0])
	assert(bool(Proficiencies.origin_enabled_map(tab._effective_record()).get(feat_source_sid, false)),
		"Feat switch restores the origin")
	tab.queue_free()
	await process_frame
	print("PASS: automatically granted structured proficiencies, choose warnings, toggles, source highlights and migration")
	quit()


func _check_feat_origin_chains() -> void:
	var record: Dictionary = _record()
	var feat_a: Dictionary = {"id": "feat:a", "name": "A", "source": "HB",
		"origin_id": "class|phb|fighter", "disabled": false}
	var feat_b: Dictionary = {"id": "feat:b", "name": "B", "source": "HB",
		"origin_id": "feat|hb|a", "disabled": false}
	var feat_independent: Dictionary = {"id": "feat:c", "name": "Independent", "source": "HB",
		"origin_id": "", "disabled": false}
	record["feats_catalog"] = [feat_a, feat_b, feat_independent]
	record["proficiency_choices"] = [
		{"kind": "skill", "key": "arcana", "origin_id": "feat|hb|b", "disabled": false},
		{"kind": "skill", "key": "arcana", "origin_id": "", "disabled": false},
		{"kind": "tool", "key": "disguise kit", "origin_id": "feat|hb|a", "disabled": false}
	]
	record["formula_bonuses"] = [{"id": "feat:bonus", "target": "initiative",
		"expression": "3", "origin_id": "feat|hb|b", "disabled": false}]
	var initial: Dictionary = Proficiencies.origin_enabled_map(record)
	assert(bool(initial.get("feat|hb|a", false)) and bool(initial.get("feat|hb|b", false))
		and bool(initial.get("feat|hb|independent", false)),
		"Origin-linked feat chains are active when their ancestors are active")
	assert(Bonuses.bonus(record, "initiative") == 3,
		"Active grandchild feat contributes a linked formula bonus")
	record["proficiency_origins"] = [
		{"id": "class|phb|fighter", "disabled": true, "automatic": true}]
	var muted: Dictionary = Proficiencies.origin_enabled_map(record)
	assert(not bool(muted.get("feat|hb|a", true)) and not bool(muted.get("feat|hb|b", true))
		and bool(muted.get("feat|hb|independent", false)),
		"Muting an ancestor recursively mutes feat descendants but not unrelated feats")
	assert(not Proficiencies.has_proficiency(record, "tool", "disguise kit")
		and Proficiencies.has_proficiency(record, "skill", "arcana"),
		"Independent skill grants survive while the feat-derived grant is inactive")
	assert(Bonuses.bonus(record, "initiative") == 0,
		"Grandchild feat bonuses must not survive a muted ancestor")
	record["proficiency_origins"] = []
	assert(Bonuses.bonus(record, "initiative") == 3,
		"Re-enabling the ancestor restores the full chain automatically")
	(record["feats_catalog"] as Array)[0]["disabled"] = true
	assert(not bool(Proficiencies.origin_enabled_map(record).get("feat|hb|b", true)),
		"Muting a feat also mutes a feat granted by that feat")
	assert(Bonuses.bonus(record, "initiative") == 0,
		"Individual feat disabling also cascades into bonuses")
	(record["feats_catalog"] as Array)[0]["disabled"] = false
	# Duplicate feat grants obey OR semantics: muting one source must not
	# suppress the feat while another independent origin still grants it.
	(record["feats_catalog"] as Array).append({
		"id": "feat:a", "name": "A", "source": "HB", "origin_id": "", "disabled": false})
	(record["feats_catalog"] as Array)[0]["disabled"] = true
	assert(bool(Proficiencies.origin_enabled_map(record).get("feat|hb|a", false)),
		"A second independent feat grant keeps the shared feat origin active")
	(record["feats_catalog"] as Array).pop_back()
	(record["feats_catalog"] as Array)[0]["disabled"] = false
	assert(Bonuses.bonus(record, "initiative") == 3,
		"Unmuting the feat restores dependent bonuses without rewriting them")
	(record["feats_catalog"] as Array).remove_at(0)
	var removed: Dictionary = Proficiencies.origin_enabled_map(record)
	assert(not bool(removed.get("feat|hb|b", true))
		and not Proficiencies.has_proficiency(record, "tool", "disguise kit"),
		"Deleting a granting feat invalidates its dependent origins and grants")


func _check_index_parity() -> void:
	Proficiencies._load_sources()
	# Check every catalog identity, duplicate class names and ambiguous legacy
	# backgrounds against the original full scan and source/parent predicate.
	for group: String in ["class", "race", "subrace", "background", "feat"]:
		var rows: Array = Proficiencies._sources.get(group, [])
		for raw: Variant in rows:
			if not raw is Dictionary:
				continue
			var record: Dictionary = {}
			var name: String = String(raw.get("name", "")).to_upper()
			var source: String = String(raw.get("source", ""))
			match group:
				"class":
					record = {"class": name, "class_source": source, "classes": [{"name": name, "source": source}]}
				"feat":
					record = {"feats_catalog": [{"name": name, "source": source}]}
				"race":
					record = {"species": name, "species_source": source}
				"subrace":
					record = {"subrace": name, "subrace_source": source,
						"species": raw.get("raceName", ""), "species_source": raw.get("raceSource", "")}
				"background":
					record = {"background": name} # Older saves have no source book.
			var expected: Array[int] = []
			for index: int in range(rows.size()):
				var row: Dictionary = rows[index]
				if Proficiencies._selected_source(record, group, String(row.get("name", "")), String(row.get("source", "")), row):
					expected.append(index)
			var actual: Array[int] = []
			for index: int in Proficiencies._candidate_indices(record, group):
				var row: Dictionary = rows[index]
				if Proficiencies._selected_source(record, group, String(row.get("name", "")), String(row.get("source", "")), row):
					actual.append(index)
			assert(actual == expected, "Indexed candidates must preserve full-scan matching and order")