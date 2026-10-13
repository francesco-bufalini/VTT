extends RefCounted

# Public tactical state derived from private creature records.
# Keep exact hit points and other sheet data out of network-facing payloads.
const ActiveSpells = preload("res://vtt/creature_active_spells.gd")


static func health_bar_entry(record: Dictionary) -> Dictionary:
	var token_id: String = String(record.get("linked_token_sync_id", "")).strip_edges()
	var transformed: bool = int(record.get("second_form_hp", 0)) > 0
	var maximum: int = (
		int(record.get("second_form_max_hp", 0))
		if transformed else int(record.get("max_hp", 0))
	)
	if token_id.is_empty() or maximum <= 0:
		return {}
	var current: int = (
		int(record.get("second_form_hp", 0))
		if transformed else int(record.get("current_hp", 0))
	)
	return {
		"token_id": token_id,
		"percent": clampf(float(current) / float(maximum) * 100.0, 0.0, 100.0)
	}


static func from_record(record: Dictionary) -> Dictionary:
	var hp: Dictionary = health_bar_entry(record)
	if hp.is_empty():
		return {}
	var conditions_value: Variant = record.get("conditions", [])
	var conditions: Array = (
		(conditions_value as Array).duplicate()
		if conditions_value is Array else []
	)
	var active_spell_ids: Array[String] = []
	for source: Dictionary in ActiveSpells.active_origins(record):
		var spell_id: String = String(source.get("id", "")).trim_prefix("spell:")
		if not spell_id.is_empty() and spell_id not in active_spell_ids:
			active_spell_ids.append(spell_id)
	return {
		"token_id": String(hp["token_id"]),
		"conditions": conditions,
		"hp_percent": float(hp["percent"]),
		"active_spell_ids": active_spell_ids,
		"concentrating_spell_id": String(record.get("concentrating_spell_id", ""))
	}
