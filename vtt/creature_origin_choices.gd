extends RefCounted

# Candidate origins belong to benefits, never to a stand-alone "add origin"
# action. The selector can reference a real feature/item/identity even if that
# source has no other benefit in the sheet.
const Rules = preload("res://vtt/creature_proficiency_rules.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Traits = preload("res://vtt/creature_traits_tab.gd")
const Items = preload("res://vtt/creature_item_rules.gd")


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
	return result


static func populate(picker: OptionButton, record: Dictionary, preferred: String = "") -> void:
	var previous: String = preferred
	if picker.selected >= 0:
		previous = String((picker.get_item_metadata(picker.selected) as Dictionary).get("id", preferred))
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


static func selected(picker: OptionButton) -> Dictionary:
	if picker == null or picker.selected < 0:
		return {}
	var value: Variant = picker.get_item_metadata(picker.selected)
	return value as Dictionary if value is Dictionary else {}


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
