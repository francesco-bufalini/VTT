extends RefCounted

# Numeric 5etools mechanics only. Never interpret descriptive prose as a grant.
# Stable IDs let the sheet disable a specific automatic grant without freezing
# the value in the save file. Source removal automatically withdraws the grant.
const Catalog = preload("res://vtt/player_5etools_catalog.gd")
const Items = preload("res://vtt/creature_item_rules.gd")
const Traits = preload("res://vtt/creature_traits_tab.gd")
const Skills = preload("res://vtt/creature_skills_5etools.gd")
const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]


static func _field(entry: Dictionary, snake: String, camel: String = "") -> Variant:
	if entry.has(snake):
		return entry[snake]
	if not camel.is_empty() and entry.has(camel):
		return entry[camel]
	return null


static func _number(value: Variant) -> String:
	if value is int or value is float:
		return str(value)
	if value is String:
		var literal: String = String(value).strip_edges()
		if literal.is_valid_int() or literal.is_valid_float():
			return literal
	return ""


static func _add(result: Array[Dictionary], sid: String, label: String, field: String, target: String, amount: Variant, suffix: String = "") -> void:
	var expression: String = _number(amount)
	if expression.is_empty() or target.is_empty():
		return
	result.append({
		"id": "auto|" + sid + "|" + field + "|" + target + suffix,
		"origin_id": sid, "origin_name": label, "target": target,
		"expression": expression, "automatic": true, "disabled": false
	})


static func _ability_grants(result: Array[Dictionary], sid: String, label: String, data: Dictionary) -> void:
	var raw: Variant = data.get("ability", [])
	var options: Array = raw if raw is Array else [raw]
	for item: Variant in options:
		if not item is Dictionary:
			continue
		var row: Dictionary = item
		# 5etools 'choose' and weighted choices require a player decision.
		# Do not treat the possible selections as simultaneously granted.
		if row.has("choose"):
			continue
		for stat: String in ABILITIES:
			if row.has(stat):
				_add(result, sid, label, "ability", "ability:" + stat, row[stat])


static func _item_grants(result: Array[Dictionary], record: Dictionary) -> void:
	var inventory: Variant = record.get("inventory", [])
	if not inventory is Array:
		return
	var seen: Dictionary = {}
	for raw: Variant in inventory:
		if not raw is Dictionary:
			continue
		var owned: Dictionary = raw
		if int(owned.get("quantity", 1)) <= 0:
			continue
		var item_id: String = String(owned.get("id", ""))
		if item_id.is_empty():
			continue
		var entry: Dictionary = Items.entry_for(owned)
		var sid: String = "item:" + item_id
		var kind: String = Items.kind(entry)
		var slots: Array = Items.slots(owned)
		var active: bool = bool(owned.get("active", true))
		var attunement: Variant = _field(entry, "req_attune", "reqAttune")
		if attunement != null and attunement != false and not bool(owned.get("attuned", false)):
			active = false
		if not active:
			continue
		var equipped: bool = (
			(kind == "armor" and "body" in slots)
			or (kind == "shield" and "off" in slots)
			or (kind == "weapon" and ("main" in slots or "off" in slots))
		)
		# Each physical source is considered once, even if its stack occupies
		# both hands. Attack IDs identify the individual hand/use.
		if seen.has(sid):
			continue
		seen[sid] = true
		var label: String = "Oggetto · " + String(owned.get("name", entry.get("name", item_id)))
		if kind in ["armor", "shield"] and equipped:
			_add(result, sid, label, "bonus_ac", "ac", _field(entry, "bonus_ac", "bonusAc"))
		if kind == "weapon" and equipped:
			var weapon: String = _number(_field(entry, "bonus_weapon", "bonusWeapon"))
			var attack_only: Variant = _field(entry, "bonus_weapon_attack", "bonusWeaponAttack")
			var damage_only: Variant = _field(entry, "bonus_weapon_damage", "bonusWeaponDamage")
			for attack_id: String in [
				"item:" + item_id, "item:off:" + item_id,
				"item:throw:main:" + item_id, "item:throw:off:" + item_id
			]:
				var valid: bool = ("off:" in attack_id and "off" in slots) or (not "off:" in attack_id and "main" in slots)
				if not valid:
					continue
				if not weapon.is_empty():
					_add(result, sid, label, "bonus_weapon", "attack_hit:" + attack_id, weapon)
					_add(result, sid, label, "bonus_weapon", "attack_damage:" + attack_id, weapon)
				_add(result, sid, label, "bonus_weapon_attack", "attack_hit:" + attack_id, attack_only)
				_add(result, sid, label, "bonus_weapon_damage", "attack_damage:" + attack_id, damage_only)
		# Magic items with passive effects need to be owned (and attuned when
		# required). Armor, shields and weapons additionally need to be worn.
		if kind in ["armor", "shield", "weapon"] and not equipped:
			continue
		for stat: String in ABILITIES:
			_add(result, sid, label, "bonus_saving_throw", "save:" + stat, _field(entry, "bonus_saving_throw", "bonusSavingThrow"))
		for skill: Dictionary in Skills.SKILLS:
			_add(result, sid, label, "bonus_ability_check", "skill:" + String(skill.get("id", "")), _field(entry, "bonus_ability_check", "bonusAbilityCheck"))
		for mapping: Dictionary in [
			{"field": "bonus_spell_attack", "camel": "bonusSpellAttack", "target": "spell_attack"},
			{"field": "bonus_spell_save_dc", "camel": "bonusSpellSaveDc", "target": "spell_dc"},
			{"field": "bonus_spell_damage", "camel": "bonusSpellDamage", "target": "spell_damage"},
			{"field": "bonus_proficiency_bonus", "camel": "bonusProficiencyBonus", "target": "proficiency"},
			{"field": "bonus_saving_throw_concentration", "camel": "bonusSavingThrowConcentration", "target": "save_concentration"}
		]:
			_add(result, sid, label, String(mapping.field), String(mapping.target),
				_field(entry, String(mapping.field), String(mapping.camel)))
		_ability_grants(result, sid, label, entry)


static func _catalog_origins(result: Array[Dictionary], record: Dictionary) -> void:
	var candidates: Array[Dictionary] = []
	var species: String = String(record.get("species", ""))
	var species_book: String = String(record.get("species_source", ""))
	for source: Dictionary in Catalog.entries("races"):
		if String(source.get("name", "")).nocasecmp_to(species) == 0 and String(source.get("source", "")) == species_book:
			candidates.append({"group": "race", "data": source})
	var background: String = String(record.get("background", ""))
	var background_book: String = String(record.get("background_source", ""))
	for source: Dictionary in Catalog.entries("backgrounds"):
		if String(source.get("name", "")).nocasecmp_to(background) == 0 and (background_book.is_empty() or String(source.get("source", "")) == background_book):
			candidates.append({"group": "background", "data": source})
	var selected: Variant = record.get("feats_catalog", [])
	if selected is Array and not (selected as Array).is_empty():
		for source: Dictionary in Catalog.entries("feats"):
			for feat: Variant in selected:
				if feat is Dictionary and String(source.get("name", "")).nocasecmp_to(String(feat.get("name", ""))) == 0 and String(source.get("source", "")) == String(feat.get("source", "")):
					candidates.append({"group": "feat", "data": source})
					break
	for choice: Dictionary in candidates:
		var group: String = String(choice.group)
		var data: Dictionary = choice.data
		var sid: String = group + "|" + String(data.get("source", "")).to_lower() + "|" + String(data.get("name", "")).to_lower()
		var label: String = String(data.get("name", ""))
		_ability_grants(result, sid, label, data)


static func derive(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_item_grants(result, record)
	_catalog_origins(result, record)
	# Custom/homebrew traits can expose the same structured numeric fields;
	# prose-only class features are intentionally not guessed.
	for feature: Dictionary in Traits.collect_features(record):
		var sid: String = "feature:" + String(feature.get("key", ""))
		var label: String = "Tratto · " + String(feature.get("name", ""))
		var structured: Variant = feature.get("bonuses", [])
		if not structured is Array:
			continue
		for grant: Variant in structured:
			if grant is Dictionary:
				_add(result, sid, label, "bonuses", String(grant.get("target", "")),
					grant.get("expression", ""), "|" + String(grant.get("target", "")))
	return result
