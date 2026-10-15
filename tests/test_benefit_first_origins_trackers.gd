extends SceneTree

const OriginChoices = preload("res://vtt/creature_origin_choices.gd")
const BonusTab = preload("res://vtt/creature_bonus_tab.gd")
const ProficiencyTab = preload("res://vtt/creature_proficiencies_tab.gd")
const FeatsTab = preload("res://vtt/creature_feats_tab.gd")
const TrackerTab = preload("res://vtt/creature_trackers_tab.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")
const BonusRules = preload("res://vtt/creature_bonus_rules.gd")
const Characters = preload("res://vtt/player_character_store.gd")
const Monsters = preload("res://vtt/master_creature_store.gd")


func _initialize() -> void:
	call_deferred("run")


func _select_source(picker: OptionButton, id: String) -> void:
	for i: int in range(picker.item_count):
		var source: Dictionary = picker.get_item_metadata(i)
		if String(source.get("id", "")) == id:
			picker.select(i)
			return
	assert(false, "Expected existing source in benefit editor: " + id)


func run() -> void:
	var record: Dictionary = {
		"kind": "character", "classes": [],
		"abilities": {"str": 10, "dex": 16, "con": 10, "int": 10, "wis": 10, "cha": 10},
		"proficiency_choices": [], "formula_bonuses": [], "feats_catalog": [],
		"resource_trackers": [],
		"proficiency_origins": [
			{"id": "custom|used", "name": "Used", "group": "custom", "disabled": false},
			{"id": "custom|unused", "name": "Unused", "group": "custom", "disabled": false}
		]
	}
	assert(BonusRules.value(record, "initiative") == 3,
		"Initiative should always start from the effective DEX modifier.")

	var bonus_record: Dictionary = record.duplicate(true)
	bonus_record["formula_bonuses"] = [
		{"id": "used_bonus", "target": "ac", "expression": "2", "origin_id": "custom|used"}
	]
	var bonuses := BonusTab.new()
	root.add_child(bonuses)
	bonuses.setup(Callable())
	bonuses.load_record(bonus_record)
	assert(bonuses._origin_cards.get_child_count() == 1,
		"Empty source must never appear in the bonus origin list.")
	_select_source(bonuses._origin_picker, "custom|unused")
	bonuses._add_bonus()
	assert(bonuses._origin_cards.get_child_count() == 2,
		"An origin appears only after a bonus is granted.")
	assert(String(bonuses._rows.back().get("origin_id", "")) == "custom|unused")
	# An owned item is a valid origin without a pre-existing saved source.
	var item_record: Dictionary = bonus_record.duplicate(true)
	item_record["inventory"] = [{"id": "test_potion", "name": "Test potion", "quantity": 1}]
	bonuses.load_record(item_record)
	var was_saved := false
	for source: Dictionary in bonuses._origins:
		if String(source.get("id", "")) == "item:test_potion":
			was_saved = true
	assert(was_saved, "Live inventory items may be listed as selectable origins without a saved grant.")
	var item_stored := false
	for saved_origin: Dictionary in item_record["proficiency_origins"]:
		if String(saved_origin.get("id", "")) == "item:test_potion":
			item_stored = true
	assert(not item_stored, "Discovering an inventory source must not silently persist an origin.")
	_select_source(bonuses._origin_picker, "item:test_potion")
	bonuses._add_bonus()
	assert(String(bonuses._rows.back().get("origin_id", "")) == "item:test_potion")
	var was_created := false
	for source: Dictionary in bonuses._origins:
		if String(source.get("id", "")) == "item:test_potion":
			was_created = true
	assert(was_created, "The benefit action must auto-register a newly referenced origin.")

	var prof_record: Dictionary = record.duplicate(true)
	prof_record["proficiency_choices"] = [
		{"kind": "skill", "key": "insight", "origin_id": "custom|used"}
	]
	var prof := ProficiencyTab.new()
	root.add_child(prof)
	prof.setup(Callable())
	prof.load_record(prof_record)
	assert(prof._origin_cards.get_child_count() == 1,
		"Proficiency origins must exclude identities without a proficiency.")
	_select_source(prof._origin_picker, "custom|unused")
	prof._kind_picker.select(2)
	prof._proficiency_name.text = "acrobatics"
	prof._add_competence()
	assert(prof._origin_cards.get_child_count() == 2)
	assert(String(prof._rows.back().get("origin_id", "")) == "custom|unused")

	var feat_record: Dictionary = record.duplicate(true)
	feat_record["inventory"] = [{"id": "test_potion", "name": "Test potion", "quantity": 1}]
	feat_record["feats_catalog"] = [
		{"id": "alert|phb", "name": "Alert", "source": "PHB", "origin_id": "custom|used"}
	]
	var feats := FeatsTab.new()
	root.add_child(feats)
	feats.setup(Callable())
	feats.load_record(feat_record)
	assert(feats._origin_cards.get_child_count() == 1,
		"Only feat-granting origins should be listed.")
	_select_source(feats._origin_picker, "item:test_potion")
	assert(not feats._catalog_matches.is_empty())
	# The first catalog row now creates a custom feat; choose a real entry.
	var actual_feat := -1
	for index: int in range(feats._catalog_matches.size()):
		if String(feats._catalog_matches[index].get("id", "")) != "__create_custom_feat__":
			actual_feat = index
			break
	assert(actual_feat >= 0)
	feats._feat_picker.select(actual_feat)
	feats._add_feat()
	assert(feats._origin_cards.get_child_count() == 2,
		"The origin of a new feat should appear after assignment.")
	assert(String(feats._feats.back().get("origin_id", "")) == "item:test_potion")

	var tracker_record: Dictionary = record.duplicate(true)
	tracker_record["resource_trackers"] = [
		{"id": "manual_1", "name": "Focus", "max": 3, "origin_id": "custom|used",
			"origin_name": "Used", "recharge": "manual"}
	]
	var trackers := TrackerTab.new()
	root.add_child(trackers)
	trackers.setup(Callable())
	trackers.load_record(tracker_record)
	assert(trackers._origin_cards.get_child_count() == 1,
		"Only tracker-granting origins should appear in this editor.")
	_select_source(trackers._origin_picker, "custom|unused")
	trackers._name_input.text = "Special dice"
	trackers._maximum_input.value = 4
	trackers._add_tracker()
	assert(trackers._origin_cards.get_child_count() == 2)
	var granted: Dictionary = trackers._manual.back()
	assert(String(granted.get("origin_id", "")) == "custom|unused")
	assert(int(granted.get("max", 0)) == 4)
	var saved: Dictionary = trackers._effective_record()
	assert(Trackers.for_creature(saved).size() == 2,
		"Manual trackers must survive save/load and coexist with automatic ones.")
	var stored_character: Dictionary = Characters.new().normalize_character(saved)
	assert(Trackers.for_creature(stored_character).size() == 2,
		"Character archive normalization must retain manual trackers.")
	var stored_monster: Dictionary = Monsters.new().normalize_creature({
		"kind": "monster", "stat_block": {}, "resource_trackers": trackers._manual.duplicate(true)
	})
	assert(stored_monster.get("resource_trackers", []).size() == 2,
		"Monster archive normalization must retain manual trackers.")
	trackers._set_enabled(false, String(granted.get("id", "")))
	assert(bool(trackers._manual.back().get("disabled", false)),
		"Individual manual tracker switches must be retained.")

	for tab: Node in [bonuses, prof, feats, trackers]:
		tab.queue_free()
	await process_frame
	print("PASS: grant-first origin lists, origin assignment and manual trackers")
	quit()
