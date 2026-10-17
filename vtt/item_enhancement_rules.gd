extends RefCounted

# Shared selector and numeric-effect interpreter for any feature that
# enchants an inventory item (infusions today, other item benefits later).
# Item requirements are explicit data, never parsed from display prose.
const ItemRules = preload("res://vtt/creature_item_rules.gd")


static func item_matches(selector: Dictionary, owned: Dictionary) -> bool:
	if selector.is_empty():
		return false
	var entry: Dictionary = ItemRules.entry_for(owned)
	var item_id: String = String(owned.get("id", ""))
	var planned_id: String = String(selector.get("planned_item_id", ""))
	if not planned_id.is_empty() and planned_id != item_id:
		return false
	var prefix: String = String(selector.get("id_prefix", ""))
	if not prefix.is_empty() and not item_id.begins_with(prefix):
		return false
	if bool(selector.get("nonmagical", false)):
		if item_id.begins_with("magic_item:") or bool(entry.get("magic", false)):
			return false
		if String(entry.get("rarity", "")).to_lower() not in ["", "none", "unknown", "—"]:
			return false
	var kinds: Variant = selector.get("kinds", [])
	if kinds is Array and not (kinds as Array).is_empty() and ItemRules.kind(entry) not in kinds:
		var fallback: String = String(entry.get("name", owned.get("name", ""))).to_lower()
		var alternatives: Variant = selector.get("name_contains_any", [])
		if not alternatives is Array or not _name_matches(fallback, alternatives):
			return false
	else:
		var names: Variant = selector.get("name_contains_any", [])
		if kinds is Array and (kinds as Array).is_empty() and names is Array and not (names as Array).is_empty():
			if not _name_matches(String(entry.get("name", owned.get("name", ""))).to_lower(), names):
				return false
	for property_code: Variant in selector.get("properties_all", []):
		if not ItemRules.has_property(entry, String(property_code)):
			return false
	var types: Variant = selector.get("item_types", [])
	if types is Array and not (types as Array).is_empty():
		if String(entry.get("type", "")).split("|")[0].to_upper() not in types:
			return false
	return true


static func _name_matches(name: String, fragments: Array) -> bool:
	for fragment: Variant in fragments:
		if String(fragment).to_lower() in name:
			return true
	return false


static func numeric_effects(definition: Dictionary, owned: Dictionary, upgraded: bool) -> Dictionary:
	var raw: Variant = definition.get("numeric_item_bonuses", {})
	if not raw is Dictionary:
		return {}
	var effect: Dictionary = raw
	var selector: Variant = effect.get("item_selector", {})
	if selector is Dictionary and not (selector as Dictionary).is_empty():
		if not item_matches(selector, owned):
			return {}
	var multiplier: int = 2 if upgraded else 1
	var result: Dictionary = {}
	# These are the existing item-bonus targets consumed by the sheet.
	for key: String in ["bonus_ac", "bonus_weapon", "bonus_spell_attack"]:
		if effect.has(key):
			result[key] = int(effect[key]) * multiplier
	return result
