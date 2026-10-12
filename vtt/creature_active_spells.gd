extends RefCounted

# A spell applied from the Conditions page is a real origin/trait. A separate
# "applied" flag preserves it when no benefit has been added yet. Spells
# assigned via benefit editors keep their existing grant-driven lifecycle.
const SpellCatalog = preload("res://vtt/spells/spell_catalog.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")


static func active_origins(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var enabled: Dictionary = Proficiencies.origin_enabled_map(record)
	var seen: Dictionary = {}
	for raw: Variant in record.get("proficiency_origins", []):
		if not raw is Dictionary:
			continue
		var origin: Dictionary = raw
		var sid: String = String(origin.get("id", ""))
		if not sid.begins_with("spell:") or String(origin.get("group", "")) != "spell":
			continue
		if seen.has(sid) or not bool(enabled.get(sid, false)):
			continue
		var spell: Dictionary = SpellCatalog.catalog_spell(sid.substr(6))
		if spell.is_empty():
			continue
		seen[sid] = true
		result.append({"id": sid, "definition": spell})
	return result


static func apply(record: Dictionary, spell_id: String) -> bool:
	var definition: Dictionary = SpellCatalog.catalog_spell(spell_id)
	if definition.is_empty():
		return false
	var sid: String = "spell:" + spell_id
	var origins: Array = record.get("proficiency_origins", []).duplicate(true)
	for raw: Variant in origins:
		if raw is Dictionary and String(raw.get("id", "")) == sid:
			var existing: Dictionary = raw
			existing["group"] = "spell"
			existing["name"] = "Incantesimo · " + String(definition.get("name", spell_id))
			existing["applied"] = true
			existing["disabled"] = false
			record["proficiency_origins"] = origins
			return true
	origins.append({
		"id": sid, "group": "spell",
		"name": "Incantesimo · " + String(definition.get("name", spell_id)),
		"disabled": false, "automatic": false, "applied": true
	})
	record["proficiency_origins"] = origins
	return true


static func remove(record: Dictionary, origin_id: String) -> bool:
	if not origin_id.begins_with("spell:"):
		return false
	var origins: Array = record.get("proficiency_origins", []).duplicate(true)
	var found := false
	for i: int in range(origins.size() - 1, -1, -1):
		var raw: Variant = origins[i]
		if raw is Dictionary and String(raw.get("group", "")) == "spell" and String(raw.get("id", "")) == origin_id:
			origins.remove_at(i)
			found = true
	if not found:
		return false
	record["proficiency_origins"] = origins
	# Removing the applied spell also withdraws bonuses, proficiencies,
	# trackers, defenses and granted feats tied to it or its nested traits.
	Proficiencies.reconcile_origin_dependents(record)
	Proficiencies.sync_legacy_fields(record, Proficiencies.choices(record))
	return true
