extends RefCounted

# An owned object references a catalog definition; mutable data lives in the
# creature save. Legacy saved snapshots remain usable when catalog is absent.
const SNAPSHOT_FIELDS := ["type", "weapon_category", "damage", "versatile_damage", "damage_type", "range", "properties", "ac", "bonus_ac", "bonus_weapon"]
const INSTANCE_FIELD_OVERRIDES := ["damage", "versatile_damage", "damage_type", "range", "properties", "ac", "bonus_ac", "bonus_weapon", "weight", "weapon_size"]


static func from_catalog(definition: Dictionary) -> Dictionary:
	var item: Dictionary = {
		"id": String(definition.get("id", "")),
		"name": String(definition.get("name", "")),
		"source": String(definition.get("source", "")),
		"quantity": 1,
		"equipped_slots": [],
		"attuned": false,
		"active": true,
		"instance_overrides": {}
	}
	if String(definition.get("category", "")) == "documents":
		item["category"] = "documents"
		item["added_at"] = int(Time.get_unix_time_from_system())
		item["display_style"] = "pergamena"
		item["instance_id"] = "owned_doc_%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	for field: String in SNAPSHOT_FIELDS:
		if definition.has(field):
			item[field] = definition[field]
	return item


static func from_saved(saved: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"id": String(saved.get("id", "")).strip_edges(),
		"name": String(saved.get("name", "")).strip_edges(),
		"source": String(saved.get("source", "")),
		"quantity": clampi(int(saved.get("quantity", 1)), 1, 99999),
		"equipped_slots": saved.get("equipped_slots", []).duplicate(true) if saved.get("equipped_slots", []) is Array else [],
		"attuned": bool(saved.get("attuned", false)),
		"active": bool(saved.get("active", true)),
		"instance_overrides": {}
	}
	for field: String in ["category", "added_at", "display_style", "instance_id"]:
		if saved.has(field):
			result[field] = saved[field]
	for field: String in SNAPSHOT_FIELDS:
		if saved.has(field):
			result[field] = saved[field]
	var extra: Variant = saved.get("instance_overrides", {})
	if extra is Dictionary:
		result["instance_overrides"] = (extra as Dictionary).duplicate(true)
		# Old physical measurements are no longer a supported customization.
		result["instance_overrides"].erase("dimensions_m")
	return result


static func has_customizations(saved: Dictionary) -> bool:
	var value: Variant = saved.get("instance_overrides", {})
	return value is Dictionary and not (value as Dictionary).is_empty()


static func resolve(definition: Dictionary, saved: Dictionary) -> Dictionary:
	var effective: Dictionary = definition.duplicate(true)
	var value: Variant = saved.get("instance_overrides", {})
	if value is Dictionary:
		for field: String in INSTANCE_FIELD_OVERRIDES:
			if (value as Dictionary).has(field):
				effective[field] = (value as Dictionary)[field]
	return effective
