extends SceneTree
const Abilities = preload("res://vtt/activated_ability_catalog.gd")
const Catalog = preload("res://vtt/spells/spell_catalog.gd")
const Grants = preload("res://vtt/origin_spell_grants.gd")
const Tab = preload("res://vtt/creature_spellcasting_tab.gd")


func _initialize() -> void:
	call_deferred("run")


func _find_grant(record: Dictionary, id: String) -> Dictionary:
	for grant: Dictionary in Grants.all_grants(record):
		if String(grant.get("spell_id", "")) == id:
			return grant
	return {}


func run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280, 850)
	for id: String in [Grants.BARDIC, Grants.WILD_SHAPE]:
		var ability: Dictionary = Catalog.catalog_spell(id)
		assert(Abilities.is_ability(ability))
		assert(not ability.has("school") and not ability.has("components"))
		assert(not ability.has("level"), "Nonspell abilities must not declare a spell level")
		assert(not String(ability.get("target_mode", "")).is_empty(),
			"Existing map targeting mechanics must remain available for powers")

	var fighter: Dictionary = {
		"kind": "character", "class": "Fighter", "class_source": "PHB",
		"level": 3,
		"classes": [{"name": "Fighter", "source": "PHB", "level": 3, "subclass": "Battle Master"}],
		"abilities": {"str": 16, "dex": 14, "con": 14},
		"optional_features_catalog": [
			{"id": "optionalfeature|tce|ambush", "name": "Ambush", "source": "TCE"}
		]
	}
	var picked: Array[Dictionary] = Abilities.selected_optional_features(fighter)
	assert(picked.size() == 1 and picked[0].get("name", "") == "Ambush")
	var ability_id: String = String(picked[0].get("id", ""))
	assert(Abilities.is_ability(Catalog.catalog_spell(ability_id)))
	assert(not picked[0].has("school") and not picked[0].has("components"))
	assert(String(picked[0].get("activation_mode", "")) == "contextual")
	var grant: Dictionary = _find_grant(fighter, ability_id)
	assert(not grant.is_empty(), "Selected maneuver is projected as a native nonspell ability")
	assert(String(grant.get("payment_mode", "")) == "tracker")
	assert(Grants.tracker_cost(grant) == 1)
	var spent_before: Dictionary = fighter.get("resource_tracker_spent", {}).duplicate(true)

	var tab := Tab.new()
	root.add_child(tab)
	tab.setup(func(_new_record: Dictionary) -> void: pass, Callable(),
		func(_spell: Dictionary, _level: int, _grant: Dictionary = {}) -> bool: return true)
	tab.load_record(fighter)
	var header_found := false
	for label: Node in tab._view.find_children("*", "Label", true, false):
		if label.text == "Capacità":
			header_found = true
	assert(header_found, "Nonspell activations must be grouped under a dedicated heading")
	var maneuver_button: Button = null
	for row: Node in tab._view.find_children("PowerRow", "HBoxContainer", true, false):
		var button: Button = row.get_child(0) as Button
		if button != null and button.text == "Ambush":
			maneuver_button = button
	assert(maneuver_button != null,
		"Maneuvers should appear without spell-level suffixes in the final capabilities section")
	maneuver_button.pressed.emit()
	assert(fighter.get("resource_tracker_spent", {}) == spent_before,
		"Inspecting a contextual maneuver must never expend Superiority Dice")
	tab.queue_free()
	await process_frame
	print("PASS: nonspell abilities, 5etools maneuvers, shared grants and final spellcasting section")
	quit()
