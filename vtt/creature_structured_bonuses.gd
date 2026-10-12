extends RefCounted

# Numeric 5etools mechanics only. Never interpret descriptive prose as a grant.
# Stable IDs let the sheet disable a specific automatic grant without freezing
# the value in the save file. Source removal automatically withdraws the grant.
const ABILITY_GRANTS_PATH := "res://vtt/data/structured_ability_grants_5etools.json"
const Items = preload("res://vtt/creature_item_rules.gd")
const Traits = preload("res://vtt/creature_traits_tab.gd")
const Skills = preload("res://vtt/creature_skills_5etools.gd")
const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]
static var _cached_signature := ""
static var _cached_results: Array[Dictionary] = []
static var _ability_index: Dictionary = {}


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
	var fixed: Dictionary = {}
	var first := true
	for item: Variant in options:
		if not item is Dictionary:
			return
		var option: Dictionary = item
		var current: Dictionary = {}
		for stat: String in ABILITIES:
			if option.has(stat) and (option[stat] is int or option[stat] is float):
				current[stat] = option[stat]
		if first:
			fixed = current
			first = false
		else:
			for stat: String in fixed.keys():
				if not current.has(stat) or current[stat] != fixed[stat]:
					fixed.erase(stat)
	for stat: String in fixed.keys():
		_add(result, sid, label, "ability", "ability:" + stat, fixed[stat])


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
		if Items.requires_attunement(entry) and not bool(owned.get("attuned", false)):
			active = false
		if not active:
			continue
		if kind not in ["armor", "shield", "weapon"] and not bool(owned.get("equipped", false)):
			continue
		var equipped: bool = (
			(kind == "armor" and "body" in slots)
			or (kind == "shield" and ("main" in slots or "off" in slots))
			or (kind == "weapon" and ("main" in slots or "off" in slots))
		)
		# A spare copy must not consume the equipped copy's source ID.
		if kind in ["armor", "shield", "weapon"] and not equipped:
			continue
		var label: String = "Oggetto · " + String(owned.get("name", entry.get("name", item_id)))
		if kind in ["armor", "shield"] and equipped and not seen.has(sid):
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
				if not valid or seen.has(sid + "|" + attack_id):
					continue
				seen[sid + "|" + attack_id] = true
				if not weapon.is_empty():
					_add(result, sid, label, "bonus_weapon", "attack_hit:" + attack_id, weapon)
					_add(result, sid, label, "bonus_weapon", "attack_damage:" + attack_id, weapon)
				_add(result, sid, label, "bonus_weapon_attack", "attack_hit:" + attack_id, attack_only)
				_add(result, sid, label, "bonus_weapon_damage", "attack_damage:" + attack_id, damage_only)
		# Passive grants remain unique per source, while each equipped hand
		# retains its own attack grants across separate rows of the same item.
		if seen.has(sid):
			continue
		seen[sid] = true
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
		# Item ability fields may SET a score (giant-strength belts), not add.
		# Only explicitly additive item metadata can produce formula bonuses.
		var additive_ability: Variant = _field(entry, "bonus_ability", "bonusAbility")
		if additive_ability is Dictionary:
			_ability_grants(result, sid, label, {"ability": additive_ability})


static func _load_ability_index() -> void:
	if not _ability_index.is_empty():
		return
	var file: FileAccess = FileAccess.open(ABILITY_GRANTS_PATH, FileAccess.READ)
	if file == null:
		return
	var raw: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if raw is Dictionary:
		_ability_index = raw


# The catalog retains 5etools' structured options (not prose).
# Only unambiguous one-score, one-pick choices are modeled here; for
# example Telepathic allows INT, WIS or CHA +1. Multi-score ASI remains
# deliberately excluded until its multiple picks can be represented.
static func feat_ability_choice(feat: Dictionary) -> Dictionary:
	_load_ability_index()
	var name: String = String(feat.get("name", "")).strip_edges()
	var source: String = String(feat.get("source", "")).strip_edges()
	for row: Dictionary in _ability_index.get("feat", []):
		if (
			String(row.get("name", "")).nocasecmp_to(name) != 0
			or String(row.get("source", "")) != source
		):
			continue
		var raw: Variant = row.get("ability_choices", [])
		var variants: Array = raw if raw is Array else [raw]
		if variants.size() != 1 or not variants[0] is Dictionary:
			return {}
		var chosen: Variant = (variants[0] as Dictionary).get("choose", {})
		if not chosen is Dictionary:
			return {}
		var pick: Dictionary = chosen as Dictionary
		if int(pick.get("count", 1)) != 1:
			return {}
		var options_raw: Variant = pick.get("from", [])
		if not options_raw is Array or (options_raw as Array).is_empty():
			return {}
		var offered: Array[String] = []
		for value: Variant in options_raw:
			var stat: String = String(value).strip_edges().to_lower()
			if stat in ABILITIES and stat not in offered:
				offered.append(stat)
		if offered.is_empty():
			return {}
		var amount: int = int(pick.get("amount", 1))
		if amount <= 0:
			return {}
		return {"from": offered, "amount": amount}
	return {}


static func _catalog_origins(result: Array[Dictionary], record: Dictionary) -> void:
	_load_ability_index()
	var species: String = String(record.get("species", ""))
	var species_book: String = String(record.get("species_source", ""))
	var parent_name := ""
	var parent_book := ""
	if not species.is_empty():
		for row: Dictionary in _ability_index.get("subrace", []):
			var label: String = String(row.get("raceName", "")) + " (" + String(row.get("name", "")) + ")"
			var flattened_match := species.nocasecmp_to(label) == 0 and String(row.get("source", "")) == species_book
			var selected_match := (
				String(row.get("raceName", "")).nocasecmp_to(species) == 0
				and String(row.get("raceSource", "")) == species_book
				and String(row.get("name", "")).nocasecmp_to(String(record.get("subrace", ""))) == 0
				and String(row.get("source", "")) == String(record.get("subrace_source", ""))
			)
			if not flattened_match and not selected_match:
				continue
			parent_name = String(row.get("raceName", ""))
			parent_book = String(row.get("raceSource", ""))
			var sid: String = "subrace|" + String(row.get("source", "")).to_lower() + "|" + String(row.get("name", "")).to_lower()
			_ability_grants(result, sid, "Sottorazza · " + String(row.get("name", "")), row)
			break
		for row: Dictionary in _ability_index.get("race", []):
			var is_base: bool = String(row.get("name", "")).nocasecmp_to(species) == 0 and String(row.get("source", "")) == species_book
			var is_parent: bool = not parent_name.is_empty() and String(row.get("name", "")).nocasecmp_to(parent_name) == 0 and String(row.get("source", "")) == parent_book
			if is_base or is_parent:
				var sid: String = "race|" + String(row.get("source", "")).to_lower() + "|" + String(row.get("name", "")).to_lower()
				_ability_grants(result, sid, "Specie · " + String(row.get("name", "")), row)
	var background: String = String(record.get("background", ""))
	var background_book: String = String(record.get("background_source", ""))
	if not background.is_empty():
		for row: Dictionary in _ability_index.get("background", []):
			if String(row.get("name", "")).nocasecmp_to(background) != 0 or (not background_book.is_empty() and String(row.get("source", "")) != background_book):
				continue
			var sid: String = "background|" + String(row.get("source", "")).to_lower() + "|" + String(row.get("name", "")).to_lower()
			_ability_grants(result, sid, "Background · " + String(row.get("name", "")), row)
	var selected: Variant = record.get("feats_catalog", [])
	if selected is Array and not (selected as Array).is_empty():
		for row: Dictionary in _ability_index.get("feat", []):
			var representative: Dictionary = {}
			var options: Dictionary = {}
			var picked: String = ""
			for value: Variant in selected:
				if not value is Dictionary:
					continue
				var feat: Dictionary = value
				if String(row.get("name", "")).nocasecmp_to(String(feat.get("name", ""))) != 0 or String(row.get("source", "")) != String(feat.get("source", "")):
					continue
				if representative.is_empty():
					representative = feat
					options = feat_ability_choice(feat)
				var candidate: String = String(feat.get("ability_choice", "")).to_lower()
				if picked.is_empty() and not options.is_empty() and candidate in options.get("from", []):
					picked = candidate
			if representative.is_empty():
				continue
			var sid: String = "feat|" + String(row.get("source", "")).to_lower() + "|" + String(row.get("name", "")).to_lower()
			var feat_label: String = "Talento · " + String(row.get("name", ""))
			# Multiple granting origins do not stack one feat with itself.
			_ability_grants(result, sid, feat_label, row)
			if not picked.is_empty():
				_add(result, sid, feat_label, "ability_choice",
					"ability:" + picked, int(options.get("amount", 1)))


static func derive(record: Dictionary) -> Array[Dictionary]:
	# Avoid repeating catalog scans for every formula, saving throw or attack.
	var signature: String = JSON.stringify({
		"species": record.get("species", ""), "species_source": record.get("species_source", ""),
		"species_id": record.get("species_id", ""), "subrace": record.get("subrace", ""),
		"subrace_source": record.get("subrace_source", ""), "subrace_id": record.get("subrace_id", ""),
		"class": record.get("class", ""), "class_source": record.get("class_source", ""),
		"subclass": record.get("subclass", ""), "subclass_source": record.get("subclass_source", ""),
		"background": record.get("background", ""), "background_source": record.get("background_source", ""),
		"feats_catalog": record.get("feats_catalog", []), "classes": record.get("classes", []),
		"level": record.get("level", 1), "kind": record.get("kind", ""),
		"inventory": record.get("inventory", []), "stat_block": record.get("stat_block", {})
	})
	if signature == _cached_signature:
		return _cached_results.duplicate(true)
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
	_cached_signature = signature
	_cached_results = result.duplicate(true)
	return result
