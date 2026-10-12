extends RefCounted

# Candidate origins belong to benefits, never to a stand-alone "add origin"
# action. The selector can reference a real feature/item/identity even if that
# source has no other benefit in the sheet.
const Rules = preload("res://vtt/creature_proficiency_rules.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Traits = preload("res://vtt/creature_traits_tab.gd")
const Items = preload("res://vtt/creature_item_rules.gd")
const SpellCatalog = preload("res://vtt/spells/spell_catalog.gd")

const SPELL_PICKER_ID := "__choose_spell__"


static func available(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = [{"id": "", "name": "Senza origine", "group": ""}]
	var seen: Dictionary = {"": true}
	var candidates: Array[Dictionary] = []
	candidates.append_array(Rules.origins(record))
	candidates.append_array(Rules.candidate_sources(record))
	candidates.append_array(Bonuses.available_origins(record))
	candidates.append_array(Rules.trait_origins(record))
	for source: Dictionary in candidates:
		var sid: String = String(source.get("id", ""))
		if sid.is_empty() or seen.has(sid):
			continue
		seen[sid] = true
		result.append(source.duplicate(true))
	for owned: Variant in record.get("inventory", []):
		if not owned is Dictionary:
			continue
		var item: Dictionary = owned
		if int(item.get("quantity", 1)) <= 0 or Items.kind(Items.entry_for(item)) == "document":
			continue
		var sid: String = "item:" + String(item.get("id", ""))
		if sid == "item:" or seen.has(sid):
			continue
		seen[sid] = true
		result.append({"id": sid, "name": "Oggetto · " + String(item.get("name", "")), "group": "item"})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if String(a.get("id", "")).is_empty():
			return true
		if String(b.get("id", "")).is_empty():
			return false
		return String(a.get("name", "")).naturalnocasecmp_to(String(b.get("name", ""))) < 0
	)
	result.insert(0, {"id": SPELL_PICKER_ID, "name": "Incantesimo…", "group": "spell_picker"})
	return result


static func populate(picker: OptionButton, record: Dictionary, preferred: String = "") -> void:
	var previous: String = preferred
	if picker.selected >= 0:
		var current: Dictionary = selected(picker)
		previous = String(current.get("id", preferred))
	if previous == SPELL_PICKER_ID:
		previous = String(picker.get_meta("_origin_last_id", ""))
	picker.set_meta("_origin_last_id", previous)
	picker.set_meta("_origin_rules_version", String(record.get("rules_version", "2014")))
	if not bool(picker.get_meta("_origin_spell_wired", false)):
		picker.item_selected.connect(_on_origin_selected.bind(picker))
		picker.set_meta("_origin_spell_wired", true)
	picker.clear()
	for source: Dictionary in available(record):
		picker.add_item(String(source.get("name", source.get("id", ""))))
		picker.set_item_metadata(picker.item_count - 1, source)
	var select_index := 0
	for i: int in range(picker.item_count):
		if String((picker.get_item_metadata(i) as Dictionary).get("id", "")) == previous:
			select_index = i
			break
	if picker.item_count > 0:
		picker.select(select_index)
		picker.set_meta("_origin_last_id", String((picker.get_item_metadata(select_index) as Dictionary).get("id", "")))



static func _restore_selection(picker: OptionButton) -> void:
	if not is_instance_valid(picker):
		return
	var preferred: String = String(picker.get_meta("_origin_last_id", ""))
	for i: int in range(picker.item_count):
		var data: Dictionary = picker.get_item_metadata(i) as Dictionary
		if String(data.get("id", "")) == preferred:
			picker.select(i)
			return
	if picker.item_count > 1:
		picker.select(1)


static func _on_origin_selected(index: int, picker: OptionButton) -> void:
	var source: Dictionary = picker.get_item_metadata(index) as Dictionary
	var sid: String = String(source.get("id", ""))
	if sid != SPELL_PICKER_ID:
		picker.set_meta("_origin_last_id", sid)
		return
	_open_spell_picker(picker)


static func _open_spell_picker(picker: OptionButton) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Scegli l'incantesimo che concede il beneficio"
	dialog.ok_button_text = "Seleziona"
	picker.add_child(dialog)
	var layout := VBoxContainer.new()
	dialog.add_child(layout)
	var search := LineEdit.new()
	search.placeholder_text = "Cerca un incantesimo…"
	layout.add_child(search)
	var spells := OptionButton.new()
	spells.custom_minimum_size.x = 410
	spells.fit_to_longest_item = false
	layout.add_child(spells)
	var edition: String = String(picker.get_meta("_origin_rules_version", "2014"))
	var definitions: Array[Dictionary] = SpellCatalog.all_spells_for_rules(edition)
	var fill := func(query: String) -> void:
		spells.clear()
		var needle: String = query.strip_edges().to_lower()
		for definition: Dictionary in definitions:
			var name: String = String(definition.get("name", ""))
			if name.is_empty() or (not needle.is_empty() and needle not in name.to_lower()):
				continue
			var spell_id: String = String(definition.get("id", ""))
			if spell_id.is_empty():
				continue
			spells.add_item("%s · %s" % [name, String(definition.get("source", ""))])
			spells.set_item_metadata(spells.item_count - 1, {
				"id": "spell:" + spell_id, "name": "Incantesimo · " + name,
				"group": "spell", "spell_id": spell_id
			})
		if spells.item_count > 0:
			spells.select(0)
	fill.call("")
	search.text_changed.connect(func(query: String) -> void: fill.call(query))
	dialog.confirmed.connect(func() -> void:
		if not is_instance_valid(picker):
			return
		if spells.selected >= 0:
			var source: Dictionary = spells.get_selected_metadata() as Dictionary
			var sid: String = String(source.get("id", ""))
			var found := -1
			for i: int in range(picker.item_count):
				if String((picker.get_item_metadata(i) as Dictionary).get("id", "")) == sid:
					found = i
					break
			if found < 0:
				picker.add_item(String(source.get("name", "")))
				found = picker.item_count - 1
				picker.set_item_metadata(found, source)
			picker.select(found)
			picker.set_meta("_origin_last_id", sid)
		else:
			_restore_selection(picker)
	)
	dialog.canceled.connect(func() -> void: _restore_selection(picker))
	dialog.popup_centered(Vector2i(530, 180))


static func selected(picker: OptionButton) -> Dictionary:
	if picker == null or picker.selected < 0:
		return {}
	var value: Variant = picker.get_item_metadata(picker.selected)
	var source: Dictionary = value as Dictionary if value is Dictionary else {}
	return {} if String(source.get("id", "")) == SPELL_PICKER_ID else source


static func ensure(origins: Array[Dictionary], source: Dictionary) -> void:
	var sid: String = String(source.get("id", ""))
	if sid.is_empty():
		return
	for existing: Dictionary in origins:
		if String(existing.get("id", "")) == sid:
			return
	origins.append({
		"id": sid, "name": String(source.get("name", sid)),
		"group": String(source.get("group", "custom")),
		"disabled": false, "automatic": bool(source.get("automatic", false)),
		"requirements": source.get("requirements", []).duplicate(true)
	})
