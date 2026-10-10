extends RefCounted

# Stable combat attack definitions. The remaining creature reach_feet field
# is only a derived compatibility value for token opportunity/reach overlays.
const Rules = preload("res://vtt/creature_rules.gd")
const Catalog = preload("res://vtt/player_5etools_catalog.gd")


static func definitions(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var kind: String = String(record.get("kind", "character"))
	if kind != "monster":
		result.append({
			"id": "unarmed", "name": "Colpo senz'armi",
			"source": "unarmed", "melee": true, "range_feet": 5,
			"proficient": true, "damage": "", "base_hit": 0
		})
	var stat: Dictionary = record.get("stat_block", {})
	for section: String in ["action", "bonus", "reaction", "legendary", "mythic"]:
		var raw_section: Variant = stat.get(section, [])
		if not raw_section is Array:
			continue
		for index: int in range((raw_section as Array).size()):
			var raw: Variant = (raw_section as Array)[index]
			if not raw is Dictionary:
				continue
			var action: Dictionary = raw as Dictionary
			var title: String = String(action.get("name", "")).strip_edges()
			if title.is_empty():
				continue
			var text_value: String = JSON.stringify(action.get("entries", []))
			var hit_tag: String = _capture(text_value, "\\{@hit\\s*([+-]?\\d+)\\}")
			if hit_tag.is_empty():
				hit_tag = _capture(text_value, "([+-]\\d+)\\s+to\\s+hit")
			var has_attack: bool = (
				not hit_tag.is_empty()
				or "{@atk " in text_value
				or "weapon attack:" in text_value.to_lower()
				or "spell attack:" in text_value.to_lower()
			)
			if not has_attack:
				continue
			var reach: String = _capture(text_value.to_lower(), "reach\\s*(\\d+)\\s*(?:ft|feet)")
			var ranged_distance_text: String = _capture(text_value.to_lower(), "range\\s*(\\d+)\\s*(?:/|ft|feet)")
			var ranged: bool = (
				"ranged" in text_value.to_lower()
				or "{@atk rw}" in text_value
				or "{@atk rs}" in text_value
			)
			var dice: String = _capture(text_value, "\\{@damage\\s*([^}]+)\\}")
			if dice.is_empty():
				dice = _capture(text_value, "(\\d+d\\d+(?:\\s*[+-]\\s*\\d+)?)")
			var distance_feet: int = 5
			if ranged and not ranged_distance_text.is_empty():
				distance_feet = int(ranged_distance_text)
			elif not reach.is_empty():
				distance_feet = int(reach)
			var melee: bool = not ranged or "melee or ranged" in text_value.to_lower()
			result.append({
				"id": "monster:%s:%d" % [section, index],
				"name": title, "source": section, "melee": melee,
				"range_feet": maxi(5, distance_feet),
				"melee_reach_feet": maxi(5, int(reach)) if not reach.is_empty() else 5,
				"proficient": true, "damage": dice,
				"base_hit": int(hit_tag) if not hit_tag.is_empty() else 0,
				"hit_known": not hit_tag.is_empty(),
				"source_ability": "dex" if ranged else "str",
				"raw": action.duplicate(true)
			})
	var inventory: Variant = record.get("inventory", [])
	if inventory is Array:
		var owned: Dictionary = {}
		for raw_item: Variant in inventory:
			if raw_item is Dictionary:
				owned[String((raw_item as Dictionary).get("id", ""))] = true
		var catalog_items: Array[Dictionary] = []
		if not owned.is_empty():
			catalog_items = Catalog.entries("items")
		for item: Dictionary in catalog_items:
			if not owned.has(String(item.get("id", ""))):
				continue
			if String(item.get("weapon_category", "")).is_empty():
				continue
			var weapon_id: String = String(item.get("id", ""))
			var range_text: String = String(item.get("range", ""))
			var ranged: bool = "ranged" in String(item.get("weapon_category", "")).to_lower()
			var distance: String = _capture(range_text, "(\\d+)")
			result.append({
				"id": "item:" + weapon_id,
				"name": String(item.get("name", "")),
				"source": "item", "melee": not ranged,
				"range_feet": maxi(5, int(distance) if not distance.is_empty() else 5),
				"proficient": false, "damage": String(item.get("dmg1", "1d4")),
				"base_hit": 0
			})
	return result


static func _capture(text_value: String, expression: String) -> String:
	var pattern: RegEx = RegEx.create_from_string(expression)
	if pattern == null:
		return ""
	var match_value: RegExMatch = pattern.search(text_value)
	return match_value.get_string(1) if match_value != null else ""


static func override_for(record: Dictionary, attack_id: String) -> Dictionary:
	var source: Variant = record.get("attack_overrides", {})
	if source is Dictionary:
		var entry: Variant = (source as Dictionary).get(attack_id, {})
		if entry is Dictionary:
			return entry as Dictionary
	return {}


static func range_for(record: Dictionary, attack: Dictionary) -> int:
	var settings: Dictionary = override_for(record, String(attack.get("id", "")))
	return clampi(int(settings.get("range_feet", attack.get("range_feet", 5))), 5, 1000)


static func ability_modifier(record: Dictionary) -> int:
	var ability: String = "dex" if String(record.get("attack_ability", "str")) == "dex" else "str"
	var scores: Dictionary = record.get("abilities", {})
	var bonuses: Dictionary = record.get("ability_bonuses", {})
	return Rules.ability_modifier(int(scores.get(ability, 10)) + int(bonuses.get(ability, 0)))


static func _ability_delta_for_monster(record: Dictionary, attack: Dictionary) -> int:
	var desired: String = "dex" if String(record.get("attack_ability", "str")) == "dex" else "str"
	var original: String = String(attack.get("source_ability", "str"))
	if desired == original:
		return 0
	var scores: Dictionary = record.get("abilities", {})
	var bonuses: Dictionary = record.get("ability_bonuses", {})
	return (
		Rules.ability_modifier(int(scores.get(desired, 10)) + int(bonuses.get(desired, 0)))
		- Rules.ability_modifier(int(scores.get(original, 10)) + int(bonuses.get(original, 0)))
	)


static func attack_bonus(record: Dictionary, attack: Dictionary, proficiency: int) -> int:
	var settings: Dictionary = override_for(record, String(attack.get("id", "")))
	var manual: int = int(settings.get("bonus", 0))
	if String(record.get("kind", "")) == "monster" and String(attack.get("source", "")) != "item":
		# The bestiary hit value already includes its proficiency. Changing the
		# preferred ability adjusts the ability component only.
		return int(attack.get("base_hit", 0)) + _ability_delta_for_monster(record, attack) + manual
	var trained: bool = bool(settings.get("proficient", attack.get("proficient", false)))
	if String(attack.get("id", "")) == "unarmed":
		trained = true
	return ability_modifier(record) + (proficiency if trained else 0) + manual


static func damage_label(record: Dictionary, attack: Dictionary) -> String:
	var source: String = String(attack.get("source", ""))
	var base: String = String(attack.get("damage", "")).strip_edges()
	var modifier: int = (
		_ability_delta_for_monster(record, attack)
		if String(record.get("kind", "")) == "monster" and source != "item"
		else ability_modifier(record)
	)
	# A weapon's manually entered enhancement applies both to hit and damage,
	# but proficiency continues to affect only the attack roll.
	var settings: Dictionary = override_for(record, String(attack.get("id", "")))
	modifier += int(settings.get("bonus", 0))
	if String(attack.get("id", "")) == "unarmed":
		return str(maxi(1, 1 + modifier)) + " contundenti"
	if base.is_empty():
		return "Come da bestiario"
	if String(record.get("kind", "")) == "monster" and source != "item" and modifier == 0:
		return base
	return base + (" %+d" % modifier if modifier != 0 else "")


static func max_melee_range(record: Dictionary) -> float:
	var maximum: float = 5.0
	for attack: Dictionary in definitions(record):
		if bool(attack.get("melee", false)):
			var value: float = float(range_for(record, attack))
			if attack.has("melee_reach_feet") and "ranged" in JSON.stringify(attack.get("raw", {})).to_lower():
				value = float(attack.get("melee_reach_feet", 5))
			maximum = maxf(maximum, value)
	return maximum


# Tactical reach is determined by the first available melee attack in the
# sheet's order; a later long-reach attack must not silently enlarge it.
static func first_melee_range(record: Dictionary) -> float:
	for attack: Dictionary in definitions(record):
		if not bool(attack.get("melee", false)):
			continue
		var settings := override_for(record, String(attack.get("id", "")))
		if settings.has("range_feet"):
			return float(range_for(record, attack))
		# A bestiary attack that supports both melee and ranged modes must
		# use its melee reach, never the projectile range.
		if attack.has("melee_reach_feet") and "ranged" in JSON.stringify(
			attack.get("raw", {})
		).to_lower():
			return float(attack.get("melee_reach_feet", 5))
		return float(range_for(record, attack))
	return 5.0
