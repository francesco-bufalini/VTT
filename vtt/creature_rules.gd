extends RefCounted

# Static, public creature-rule helpers. Mutable resources/trackers have been
# retired from the creature sheet and are no longer generated here.

static func monster_armor_class(stat: Dictionary) -> int:
	var ac_value: Variant = stat.get("ac", [])
	if ac_value is Array:
		for part: Variant in ac_value as Array:
			if part is int or part is float:
				return maxi(0, int(part))
			if part is Dictionary and (part as Dictionary).has("ac"):
				return maxi(0, int((part as Dictionary).get("ac", 10)))
	if ac_value is int or ac_value is float:
		return maxi(0, int(ac_value))
	return 10


static func monster_abilities(stat: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for ability: String in ["str", "dex", "con", "int", "wis", "cha"]:
		result[ability] = clampi(int(stat.get(ability, 10)), 1, 30)
	return result


static func serialize_public_identity(creature: Dictionary) -> Dictionary:
	# No HP, ability scores, spell slots, secret notes, or full stat block.
	return {
		"creature_id": String(creature.get("id", "")),
		"owner_id": String(creature.get("owner_id", "")),
		"default_miniature_id": String(
			creature.get("default_miniature_id", "")
		)
	}
