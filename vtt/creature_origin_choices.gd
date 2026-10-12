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
	# Saved origins and bonus sources are ordered before live traits. Preserve
	# their state, but hydrate their presentation data from the actual feature:
	# otherwise several ASI levels all appear as "Tratto · Ability Score Improvement".
	var trait_sources: Array[Dictionary] = Rules.trait_origins(record)
	var trait_by_id: Dictionary = {}
	for trait_source: Dictionary in trait_sources:
		trait_by_id[String(trait_source.get("id", ""))] = trait_source
	var candidates: Array[Dictionary] = []
	candidates.append_array(Rules.origins(record))
	candidates.append_array(Rules.candidate_sources(record))
	candidates.append_array(Bonuses.available_origins(record))
	candidates.append_array(trait_sources)
	for source: Dictionary in candidates:
		var sid: String = String(source.get("id", ""))
		if sid.is_empty() or seen.has(sid):
			continue
		seen[sid] = true
		var option: Dictionary = source.duplicate(true)
		if trait_by_id.has(sid):
			var real_feature: Dictionary = trait_by_id[sid]
			for field: String in [
				"origin", "origin_key", "class_name", "class_source",
				"level", "book", "category"
			]:
				option[field] = real_feature.get(field)
		result.append(option)
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


# Display-only identifiers: preserve the original origin IDs and grant state.
# Real feature context must take priority over saved labels, which often contain
# nothing beyond the repeated trait name.
static func display_labels(sources: Array[Dictionary], record: Dictionary = {}) -> Dictionary:
	var labels: Dictionary = {}
	var by_name: Dictionary = {}
	for source: Dictionary in sources:
		var sid: String = String(source.get("id", ""))
		var name: String = String(source.get("name", sid))
		labels[sid] = name
		var normalized: String = name.strip_edges().to_lower()
		if not by_name.has(normalized):
			by_name[normalized] = []
		var ids: Array = by_name[normalized]
		if sid not in ids:
			ids.append(sid)
	var duplicates: Dictionary = {}
	var need_feature_fallback: bool = false
	for normalized: String in by_name.keys():
		var ids: Array = by_name[normalized]
		if ids.size() <= 1:
			continue
		for raw_id: Variant in ids:
			var sid: String = String(raw_id)
			duplicates[sid] = true
	# Repeated ASI features should *always* show the class and acquisition
	# level, even if just one of their occurrences was loaded by this picker.
	for source: Dictionary in sources:
		var sid: String = String(source.get("id", ""))
		if sid.begins_with("feature:") and "ability score improvement" in String(source.get("name", "")).to_lower():
			duplicates[sid] = true
	for source: Dictionary in sources:
		var sid: String = String(source.get("id", ""))
		if not duplicates.has(sid) or not sid.begins_with("feature:"):
			continue
		if String(source.get("class_name", "")).is_empty() and String(source.get("origin", "")).is_empty():
			need_feature_fallback = true
			break
	var feature_details: Dictionary = {}
	if need_feature_fallback and not record.is_empty():
		for feature: Dictionary in Traits.collect_features(record):
			feature_details["feature:" + String(feature.get("key", ""))] = feature
	for source: Dictionary in sources:
		var sid: String = String(source.get("id", ""))
		if not duplicates.has(sid):
			continue
		var detail: Dictionary = feature_details.get(sid, source)
		var class_name: String = String(detail.get("class_name", "")).strip_edges()
		var level: int = int(detail.get("level", 0))
		var context: String = class_name
		if context.is_empty():
			context = String(detail.get("origin", "")).strip_edges()
		if level > 0 and (not class_name.is_empty() or String(detail.get("category", "")) == "classi"):
			context += (" · " if not context.is_empty() else "") + "livello %d" % level
		var book: String = String(detail.get("class_source", "")).strip_edges()
		if book.is_empty():
			book = String(detail.get("book", "")).strip_edges()
		if book.is_empty():
			book = String(detail.get("source", "")).strip_edges()
		if not book.is_empty() and (not context.is_empty() or sid.begins_with("feature:")):
			context += (" · " if not context.is_empty() else "") + book
		if not context.is_empty():
			labels[sid] = String(labels[sid]) + " · " + context
	# Some homebrew/legacy features have neither structured class nor level.
	# Give those stable sequence numbers, never an exposed internal node ID.
	var collisions: Dictionary = {}
	for sid: String in duplicates.keys():
		var key: String = String(labels[sid]).to_lower()
		if not collisions.has(key):
			collisions[key] = []
		(collisions[key] as Array).append(sid)
	for group: Array in collisions.values():
		if group.size() <= 1:
			continue
		group.sort()
		for index: int in range(group.size()):
			var sid: String = String(group[index])
			labels[sid] = String(labels[sid]) + " · #%d" % (index + 1)
	return labels


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
	var temporary: Dictionary = {}
	if picker.selected >= 0:
		var current: Dictionary = selected(picker)
		if String(current.get("id", "")).begins_with("spell:"):
			temporary = current
	picker.clear()
	var available_sources: Array[Dictionary] = available(record)
	if not temporary.is_empty():
		var present := false
		for existing: Dictionary in available_sources:
			if existing.get("id", "") == temporary.get("id", ""):
				present = true
				break
		if not present:
			available_sources.append(temporary)
	var labels: Dictionary = display_labels(available_sources, record)
	for source: Dictionary in available_sources:
		var sid: String = String(source.get("id", ""))
		var label: String = String(labels.get(sid, source.get("name", "")))
		picker.add_item(label)
		picker.set_item_metadata(picker.item_count - 1, source)
		picker.set_item_tooltip(picker.item_count - 1, label)
	# Incantesimo is the first action, not the default assigned origin.
	var select_index := 1 if picker.item_count > 1 else 0
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
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void:
		_restore_selection(picker)
		dialog.queue_free()
	)
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
