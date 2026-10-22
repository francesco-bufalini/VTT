extends RefCounted

# Artificer infusions use the existing optional_features_catalog, owned item
# instances, attunement and structured item-bonus pipeline.
# Eligibility comes from 5etools' typed optional-feature prerequisites.
const BenefitRequirements = preload("res://vtt/benefit_requirements.gd")
const ClassMechanics = preload("res://vtt/class_mechanics_5etools.gd")
const ItemEnhancements = preload("res://vtt/item_enhancement_rules.gd")
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
		row["source_trait_id"] = String(saved.get("source_trait_id", ""))
		result.append(row)
	return result


# The prepared bank is shared with the PWA. Legacy characters without this
# field keep their previously learned infusions ready instead of losing them.
static func prepared(record: Dictionary) -> Array[Dictionary]:
	var all_known: Array[Dictionary] = known(record)
	if not record.has("prepared_optional_features"):
		return all_known
	var result: Array[Dictionary] = []
	var saved: Variant = record.get("prepared_optional_features", [])
	if not saved is Array:
		return result
	for option: Dictionary in all_known:
		for entry: Variant in saved:
			if entry is Dictionary and String(entry.get("id", "")) == String(option.get("id", "")) and String(entry.get("plan_item_id", "")) == String(option.get("plan_item_id", "")):
				result.append(option)
				break
	return result


static func is_learned(record: Dictionary, option: Dictionary) -> bool:
	for row: Dictionary in known(record):
		if String(row.get("id", "")) == String(option.get("id", "")) and String(row.get("plan_item_id", "")) == String(option.get("plan_item_id", "")):
			return true
	return false


static func active_count(inventory: Array, creator_id: String = "") -> int:
	var count := 0
	for raw: Variant in inventory:
		if not raw is Dictionary or int(raw.get("quantity", 0)) <= 0:
			continue
		var infusion: Variant = raw.get("infusion", {})
		if not infusion is Dictionary or (infusion as Dictionary).is_empty():
			continue
		if not creator_id.is_empty() and String(infusion.get("creator_id", "")) != creator_id:
			continue
		count += 1
	return count


# Infusion-specific learning/plan identity stays here; physical item
# eligibility is shared with other item-enhancing features.
static func item_eligible(option: Dictionary, owned: Dictionary) -> bool:
	var selector: Dictionary = option.get("item_selector", {}).duplicate(true)
	if String(option.get("application_kind", "")) == "replicate":
		var plan_id: String = String(option.get("plan_item_id", ""))
		if plan_id.is_empty():
			return false
		selector["planned_item_id"] = plan_id
	return ItemEnhancements.item_matches(selector, owned)


static func replicable(option: Dictionary, item: Dictionary, level: int) -> bool:
	if String(option.get("application_kind", "")) != "replicate":
		return false
	if not String(item.get("id", "")).begins_with("magic_item:"):
		return false
	var name: String = String(item.get("name", "")).strip_edges()
	for raw: Variant in option.get("replicable_items", []):
		if raw is Dictionary and String(raw.get("name", "")).nocasecmp_to(name) == 0 and BenefitRequirements.allows({},
			BenefitRequirements.level_gate(int(raw.get("level", 99)), "class",
				"Artificer", "TCE"), level):
			return true
	return String(item.get("rarity", "")).to_lower() == "common" and String(item.get("type", "")).to_upper() not in ["P", "SC"]


static func numeric_bonuses(record: Dictionary, owned: Dictionary) -> Dictionary:
	var raw: Variant = owned.get("infusion", {})
	if not raw is Dictionary:
		return {}
	var infusion: Dictionary = raw
	if String(infusion.get("creator_id", "")) == String(record.get("id", "")):
		var grant: String = String(infusion.get("source_trait_id", ""))
		if not grant.is_empty() and record.get("origin_enabled", {}).get(grant, true) == false:
			return {}
	var option: Dictionary = definition(infusion)
	if option.is_empty() or String(option.get("application_kind", "")) == "replicate":
		return {}
	var bonus: Variant = option.get("numeric_item_bonuses", {})
	if not bonus is Dictionary:
		return {}
	var level: int = int(infusion.get("level", 2))
	if String(infusion.get("creator_id", "")) == String(record.get("id", "")) and artificer_level(record) >= 2:
		level = artificer_level(record)
	if not BenefitRequirements.accepts(record, option, "class",
		"Artificer", "TCE", "min_level", 2, level):
		return {}
	var upgraded: bool = BenefitRequirements.accepts(record,
		bonus as Dictionary, "class", "Artificer", "TCE",
		"upgrade_level", 99, level)
	return ItemEnhancements.numeric_effects(option, owned, upgraded)
