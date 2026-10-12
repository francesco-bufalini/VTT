extends RefCounted

# One authoritative definition of unfinished, structured catalog choices.
# Keep warnings independent of whichever sheet editor is currently open.
const Structured = preload("res://vtt/creature_structured_bonuses.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")


static func missing_feat_abilities(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var enabled: Dictionary = Proficiencies.origin_enabled_map(record)
	var seen: Dictionary = {}
	for raw: Variant in record.get("feats_catalog", []):
		if not raw is Dictionary:
			continue
		var feat: Dictionary = raw
		var sid: String = Proficiencies.feat_source_id(feat)
		if sid.is_empty() or seen.has(sid) or not bool(enabled.get(sid, false)):
			continue
		var choice: Dictionary = Structured.feat_ability_choice(feat)
		if choice.is_empty():
			continue
		# The same feat may be granted by multiple origins. It requires one
		# shared choice, not an additional ASI for every source.
		var selected: String = ""
		for other_raw: Variant in record.get("feats_catalog", []):
			if other_raw is Dictionary and Proficiencies.feat_source_id(other_raw) == sid:
				var candidate: String = String(other_raw.get("ability_choice", "")).to_lower()
				if candidate in choice.get("from", []):
					selected = candidate
					break
		seen[sid] = true
		if not selected.is_empty():
			continue
		result.append({
			"origin_id": sid, "name": String(feat.get("name", "")),
			"from": choice.get("from", []).duplicate(), "amount": int(choice.get("amount", 1))
		})
	return result


static func missing_proficiencies(record: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var enabled: Dictionary = Proficiencies.origin_enabled_map(record)
	var rows: Array[Dictionary] = Proficiencies.choices(record)
	for origin: Dictionary in Proficiencies.origins(record):
		var sid: String = String(origin.get("id", ""))
		if sid.is_empty() or not bool(enabled.get(sid, false)):
			continue
		for detail: String in Proficiencies.requirement_missing(origin, rows, enabled):
			result.append(String(origin.get("name", sid)) + ": " + detail)
	return result


static func section_warnings(record: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var missing_profs: Array[String] = missing_proficiencies(record)
	if not missing_profs.is_empty():
		result[1] = missing_profs
	var missing_abilities: Array[Dictionary] = missing_feat_abilities(record)
	if not missing_abilities.is_empty():
		var bonus_messages: Array[String] = []
		for entry: Dictionary in missing_abilities:
			bonus_messages.append("%s: scegli la caratteristica (+%d)" % [
				String(entry.get("name", "")), int(entry.get("amount", 1))
			])
		result[3] = bonus_messages
	return result
