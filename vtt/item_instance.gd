extends RefCounted

# An owned object references a catalog definition; mutable data lives in the
# creature save. Legacy saved snapshots remain usable when catalog is absent.
# Keep the structured mechanics required by the offline/homebrew fallback,
# including both generated snake_case and raw 5etools camelCase metadata.
const SNAPSHOT_FIELDS := [
	"type", "weapon_category", "damage", "versatile_damage", "damage_type", "range", "properties", "ac", "dexterity_max",
	"bonus_ac", "bonusAc", "bonus_weapon", "bonusWeapon",
	"bonus_weapon_attack", "bonusWeaponAttack", "bonus_weapon_damage", "bonusWeaponDamage",
	"bonus_saving_throw", "bonusSavingThrow", "bonus_ability_check", "bonusAbilityCheck",
	"bonus_spell_attack", "bonusSpellAttack", "bonus_spell_save_dc", "bonusSpellSaveDc",
	"bonus_spell_damage", "bonusSpellDamage", "bonus_proficiency_bonus", "bonusProficiencyBonus",
	"bonus_saving_throw_concentration", "bonusSavingThrowConcentration",
	"bonus_ability", "bonusAbility", "req_attune", "reqAttune",
	"requirements",
	"feats", "entries", "description", "value", "value_gp", "weight", "rarity", "custom_item_type",
	"spell", "spell_name", "spellName", "spell_level", "spellLevel", "level"
]
const INSTANCE_FIELD_OVERRIDES := ["damage", "versatile_damage", "damage_type", "range", "properties", "ac", "bonus_ac", "bonus_weapon", "weight", "weapon_size"]


static func from_catalog(definition: Dictionary) -> Dictionary:
	var item: Dictionary = {
		"id": String(definition.get("id", "")),
		"name": String(definition.get("name", "")),
		"source": String(definition.get("source", "")),
		"quantity": 1,
		"equipped_slots": [],
		"equipped": false,
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
			item[field] = definition[field].duplicate(true) if definition[field] is Array or definition[field] is Dictionary else definition[field]
	return item


static func from_saved(saved: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"id": String(saved.get("id", "")).strip_edges(),
		"name": String(saved.get("name", "")).strip_edges(),
		"source": String(saved.get("source", "")),
		"quantity": clampi(int(saved.get("quantity", 1)), 1, 99999),
		"equipped_slots": saved.get("equipped_slots", []).duplicate(true) if saved.get("equipped_slots", []) is Array else [],
		"equipped": bool(saved.get("equipped", false)),
		"attuned": bool(saved.get("attuned", false)),
		"active": bool(saved.get("active", true)),
		"instance_overrides": {}
	}
	for field: String in ["category", "added_at", "display_style", "instance_id", "infusion"]:
		if saved.has(field):
			result[field] = saved[field].duplicate(true) if saved[field] is Array or saved[field] is Dictionary else saved[field]
	for field: String in SNAPSHOT_FIELDS:
		if saved.has(field):
			result[field] = saved[field].duplicate(true) if saved[field] is Array or saved[field] is Dictionary else saved[field]
	var extra: Variant = saved.get("instance_overrides", {})
	if extra is Dictionary:
		result["instance_overrides"] = (extra as Dictionary).duplicate(true)
		# Old physical measurements are no longer a supported customization.
		result["instance_overrides"].erase("dimensions_m")
	return result


static func has_customizations(saved: Dictionary) -> bool:
	var value: Variant = saved.get("instance_overrides", {})
	return (value is Dictionary and not (value as Dictionary).is_empty()) or (saved.get("infusion", {}) is Dictionary and not (saved.get("infusion", {}) as Dictionary).is_empty())


static func resolve(definition: Dictionary, saved: Dictionary) -> Dictionary:
	var effective: Dictionary = definition.duplicate(true)
	var value: Variant = saved.get("instance_overrides", {})
	if value is Dictionary:
		for field: String in INSTANCE_FIELD_OVERRIDES:
			if (value as Dictionary).has(field):
				effective[field] = (value as Dictionary)[field]
	var infusion: Variant = saved.get("infusion", {})
	if infusion is Dictionary and not (infusion as Dictionary).is_empty():
		effective["infusion"] = (infusion as Dictionary).duplicate(true)
		if bool((infusion as Dictionary).get("requires_attunement", false)):
			effective["req_attune"] = true
	return effective
