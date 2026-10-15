extends RefCounted

# Artificer infusions use the existing optional_features_catalog, owned item
# instances, attunement and structured item-bonus pipeline.
# Eligibility comes from 5etools' typed optional-feature prerequisites.
const ClassMechanics = preload("res://vtt/class_mechanics_5etools.gd")
const ItemRules = preload("res://vtt/creature_item_rules.gd")
const INDEX_PATH := "res://vtt/data/artificer_infusions_5etools.json"

static var _rows: Array[Dictionary] = []
static var _by_id: Dictionary = {}
static var _loaded := false


static func catalog() -> Array[Dictionary]:
	if not _loaded:
		_loaded = true
		var file := FileAccess.open(INDEX_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				for raw: Variant in (parsed as Dictionary).get("infusions", []):
					if raw is Dictionary:
						var entry: Dictionary = (raw as Dictionary).duplicate(true)
						_rows.append(entry)
						_by_id[String(entry.get("id", ""))] = entry
	return _rows.duplicate(true)


static func definition(value: Dictionary) -> Dictionary:
	catalog()
	return (_by_id.get(String(value.get("id", "")), {}) as Dictionary).duplicate(true)


static func artificer_level(record: Dictionary) -> int:
	var raw: Variant = record.get("classes", [])
	if raw is Array and not (raw as Array).is_empty():
		for member: Variant in raw:
			if member is Dictionary and String(member.get("name", "")).nocasecmp_to("Artificer") == 0 and String(member.get("source", "")) == "TCE":
				return clampi(int(member.get("level", 0)), 0, 20)
		return 0
	if String(record.get("class", "")).nocasecmp_to("Artificer") == 0 and String(record.get("class_source", "")) == "TCE":
		return clampi(int(record.get("level", 0)), 0, 20)
	return 0


static func active_limit(record: Dictionary) -> int:
	var level: int = artificer_level(record)
	if level < 2:
		return 0
	return maxi(0, int(ClassMechanics.column_value("Artificer", "TCE", "Infused Items", level)))


static func known_limit(record: Dictionary) -> int:
	# TCE's Infusions Known progression is twice the Infused Items table column.
	return 2 * active_limit(record)


static func known(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	catalog()
	for raw: Variant in record.get("optional_features_catalog", []):
		if not raw is Dictionary:
			continue
		var saved: Dictionary = raw
		if not _by_id.has(String(saved.get("id", ""))):
			continue
		var row: Dictionary = (_by_id[String(saved.get("id", ""))] as Dictionary).duplicate(true)
		row["plan_item_id"] = String(saved.get("plan_item_id", ""))
		row["plan_item_name"] = String(saved.get("plan_item_name", ""))
		result.append(row)
	return result


static func is_learned(record: Dictionary, option: Dictionary) -> bool:
	for row: Dictionary in known(record):
		if String(row.get("id", "")) == String(option.get("id", "")) and String(row.get("plan_item_id", "")) == String(option.get("plan_item_id", "")):
			return true
	return false


static func active_count(inventory: Array) -> int:
	var count := 0
	for raw: Variant in inventory:
		if raw is Dictionary and int(raw.get("quantity", 0)) > 0 and raw.get("infusion", {}) is Dictionary and not (raw.get("infusion", {}) as Dictionary).is_empty():
			count += 1
	return count


static func item_eligible(option: Dictionary, owned: Dictionary) -> bool:
	var entry: Dictionary = ItemRules.entry_for(owned)
	var kind: String = ItemRules.kind(entry)
	var item_id: String = String(owned.get("id", ""))
	var replicate: bool = String(option.get("name", "")) == "Replicate Magic Item"
	if replicate:
		if String(option.get("plan_item_id", "")).is_empty() or String(option.get("plan_item_id", "")) != item_id:
			return false
		return item_id.begins_with("magic_item:")
	if item_id.begins_with("magic_item:") or bool(entry.get("magic", false)):
		return false
	var rarity: String = String(entry.get("rarity", "")).to_lower()
	if rarity not in ["", "none", "unknown", "—"]:
		return false
	var item: String = String(option.get("item_prerequisite", "")).to_lower()
	var name: String = String(entry.get("name", owned.get("name", ""))).to_lower()
	if "armor or a shield" in item:
		return kind in ["armor", "shield"]
	if "armor or robes" in item:
		return kind == "armor" or "robe" in name
	if "suit of armor" in item:
		return kind == "armor"
	if "shield" in item:
		return kind == "shield"
	if "weapon" in item:
		if kind != "weapon":
			return false
		var properties: String = str(entry.get("properties", [])).to_upper()
		if "ammunition" in item and not ("A" in properties or "AMMUNITION" in properties):
			return false
		if "thrown" in item and not ("T" in properties or "THROWN" in properties):
			return false
		return true
	if "rod, staff, or wand" in item:
		return "rod" in name or "staff" in name or "wand" in name
	if "boots" in item:
		return "boot" in name
	if "helmet" in item:
		return "helm" in name
	if "ring" in item:
		return "ring" in name
	# The structured prerequisite specifies a gem/crystal (or a generic
	# object). Do not infer additional mechanics from narrative text.
	return kind in ["other", "tool"]


static func replicable(option: Dictionary, item: Dictionary, level: int) -> bool:
	if String(option.get("name", "")) != "Replicate Magic Item":
		return false
	if not String(item.get("id", "")).begins_with("magic_item:"):
		return false
	var name: String = String(item.get("name", "")).strip_edges()
	for raw: Variant in option.get("replicable_items", []):
		if raw is Dictionary and String(raw.get("name", "")).nocasecmp_to(name) == 0 and level >= int(raw.get("level", 99)):
			return true
	return String(item.get("rarity", "")).to_lower() == "common" and String(item.get("type", "")).to_upper() not in ["P", "SC"]


static func numeric_bonuses(record: Dictionary, owned: Dictionary) -> Dictionary:
	var raw: Variant = owned.get("infusion", {})
	if not raw is Dictionary:
		return {}
	var infusion: Dictionary = raw
	var option: Dictionary = definition(infusion)
	if option.is_empty() or String(option.get("name", "")) == "Replicate Magic Item":
		return {}
	var bonus: Variant = option.get("numeric_item_bonuses", {})
	if not bonus is Dictionary:
		return {}
	var level: int = int(infusion.get("level", 2))
	if String(infusion.get("creator_id", "")) == String(record.get("id", "")) and artificer_level(record) >= 2:
		level = artificer_level(record)
	if level < int(option.get("min_level", 2)):
		return {}
	var upgrade: int = int((bonus as Dictionary).get("upgrade_level", 99))
	var multiplier := 2 if level >= upgrade else 1
	var result: Dictionary = {}
	for key: String in ["bonus_ac", "bonus_weapon", "bonus_spell_attack"]:
		if (bonus as Dictionary).has(key):
			if String(option.get("name", "")) == "Repeating Shot":
				var entry: Dictionary = ItemRules.entry_for(owned)
				if String(entry.get("type", "")).to_upper() != "R":
					continue
			result[key] = int((bonus as Dictionary)[key]) * multiplier
	return result
