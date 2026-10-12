extends SceneTree

const Defenses = preload("res://vtt/creature_damage_defenses_tab.gd")
const OriginChoices = preload("res://vtt/creature_origin_choices.gd")
const Characters = preload("res://vtt/player_character_store.gd")
const Monsters = preload("res://vtt/master_creature_store.gd")


func _initialize() -> void:
	call_deferred("run")


func _select_source(picker: OptionButton, sid: String) -> void:
	for index: int in range(picker.item_count):
		var data: Dictionary = picker.get_item_metadata(index) as Dictionary
		if String(data.get("id", "")) == sid:
			picker.select(index)
			return
	assert(false, "Defense origin must be selectable: " + sid)


func run() -> void:
	var stat: Dictionary = {
		"name": "Defense Test", "source": "MM", "str": 10, "dex": 10,
		"resist": ["cold", {"resist": ["slashing"], "note": "nonmagical"}],
		"immune": ["poison"], "conditionImmune": ["charmed"],
		"trait": [
			{"name": "Elemental Shell", "entries": ["Elemental protection."],
				"resist": ["fire"], "conditionImmune": ["frightened"]},
			{"name": "Dormant Mantle", "entries": ["A dormant trait without defenses."]}
		]
	}
	var monster: Dictionary = {
		"kind": "monster", "stat_block": stat,
		"proficiency_origins": [], "damage_defense_entries": []
	}
	assert(Defenses.rank(monster, "cold") == 1
		and Defenses.rank(monster, "poison") == 2
		and Defenses.rank(monster, "slashing") == 0,
		"Do not promote conditional damage resistance to unconditional protection")
	assert(Defenses.rank(monster, "fire") == 1
		and Defenses.condition_immune(monster, "frightened")
		and Defenses.condition_immune(monster, "charmed"),
		"Structured defenses on bestiary traits and stat blocks are derived")
	var trait_source := ""
	for source: Dictionary in Defenses._sources(monster):
		if "Elemental Shell" in String(source.get("name", "")):
			trait_source = String(source.get("id", ""))
	assert(trait_source.begins_with("feature:"), "Structured trait must retain an origin identity")
	var suppressed: Dictionary = monster.duplicate(true)
	suppressed["proficiency_origins"] = [{"id": trait_source, "disabled": true}]
	assert(Defenses.rank(suppressed, "fire") == 0
		and not Defenses.condition_immune(suppressed, "frightened"),
		"Disabling a trait must suppress structured defenses")

	var editor := Defenses.new()
	root.add_child(editor)
	var events: Array[Dictionary] = []
	editor.setup(func(damage: Dictionary, conditions: Dictionary, entries: Array, origins: Array) -> void:
		events.append({"damage": damage.duplicate(true), "conditions": conditions.duplicate(true),
			"entries": entries.duplicate(true), "origins": origins.duplicate(true)})
	)
	editor.load_record(monster)
	assert(editor._origin_buttons.has(trait_source), "Structured defense source appears on the left")
	editor._select_origin(trait_source)
	var found_highlight := false
	for index: int in editor._entry_cards:
		var entry: Dictionary = editor._record["damage_defense_entries"][index]
		if String(entry.get("origin_id", "")) == trait_source:
			var style: StyleBoxFlat = editor._entry_cards[index].get_theme_stylebox("panel") as StyleBoxFlat
			found_highlight = found_highlight or (style != null and style.border_width_left == 2)
	assert(found_highlight, "Selected source highlights its individual defenses")

	var origin_list: Array[Dictionary] = OriginChoices.available(monster)
	assert(String(origin_list[0].get("name", "")).begins_with("Incantesimo"),
		"Spell is the first option of benefit-origin selectors")
	var dormant_id := ""
	for source: Dictionary in origin_list:
		if "Dormant Mantle" in String(source.get("name", "")):
			dormant_id = String(source.get("id", ""))
	assert(dormant_id.begins_with("feature:"),
		"Traits with no existing defense must still be offered as origins")
	assert(editor._source_picker.get_item_text(0).begins_with("Incantesimo"))
	_select_source(editor._source_picker, dormant_id)
	editor._type_picker.select(0) # Acid
	editor._rank_picker.select(1) # Resistance
	editor._add_defense()
	assert(events.size() == 1, "Adding a defense publishes the changes")
	var saved: Dictionary = monster.duplicate(true)
	saved["damage_defense_entries"] = events.back()["entries"]
	saved["proficiency_origins"] = events.back()["origins"]
	assert(Defenses.rank(saved, "acid") == 1,
		"Manually granted resistance must work with an origin without innate defenses")
	var has_origin := false
	for origin: Dictionary in saved["proficiency_origins"]:
		if String(origin.get("id", "")) == dormant_id:
			has_origin = true
			origin["disabled"] = true
	assert(has_origin, "Selecting a new defense origin persists the origin")
	assert(Defenses.rank(saved, "acid") == 0,
		"Disabling the assigned origin must suppress its manual defense")
	var normalized: Dictionary = Monsters.new().normalize_creature(saved)
	assert(Defenses.rank(normalized, "acid") == 0,
		"Disabled manual defense origin must survive monster normalization")

	var feat_holder: Dictionary = {
		"kind": "character", "feats_catalog": [
			{"name": "Elemental Gift", "source": "HB", "resist": ["acid"],
				"conditionImmune": ["poisoned"]}]
	}
	assert(Defenses.rank(feat_holder, "acid") == 1
		and Defenses.condition_immune(feat_holder, "poisoned"),
		"Structured feat defenses should work without reading prose")
	feat_holder["feats_catalog"] = []
	assert(Defenses.rank(feat_holder, "acid") == 0,
		"Removing the feat must remove its defense")
	var character: Dictionary = Characters.new().normalize_character({
		"id": "damage:test", "kind": "character", "damage_defense_entries": [
			{"key": "fire", "rank": -1, "origin_id": "", "automatic": false}]
	})
	assert(Defenses.rank(character, "fire") == -1, "Character vulnerabilities persist")
	editor.queue_free()
	await process_frame
	print("PASS: defense sources, structured grants, manual origin persistence and immunity")
	quit()
