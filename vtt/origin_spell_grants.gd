extends RefCounted

# Spell entitlements belong to actual feature/item origins. Manual entries
# may point at a tracker owned by a *different* origin.
const Catalog = preload("res://vtt/spells/spell_catalog.gd")
const Traits = preload("res://vtt/creature_traits_tab.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")
const Profs = preload("res://vtt/creature_proficiency_rules.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Structured5e = preload("res://vtt/structured_origin_spells_5etools.gd")

const BARDIC := "vtt_bardic_inspiration"
const WILD_SHAPE := "vtt_wild_shape"


static func _class_level(record: Dictionary, klass: String) -> int:
	for raw: Variant in record.get("classes", []):
		if raw is Dictionary and String(raw.get("name", "")).nocasecmp_to(klass) == 0:
			return int(raw.get("level", 0))
	if String(record.get("class", "")).nocasecmp_to(klass) == 0:
		return int(record.get("level", 0))
	return 0


static func _builtins(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if String(record.get("kind", "")) == "monster":
		return result
	var bard_level: int = _class_level(record, "Bard")
	var druid_level: int = _class_level(record, "Druid")
	if bard_level < 1 and druid_level < 2:
		return result
	var trackers: Array[Dictionary] = Trackers.for_creature(record)
	for feature: Dictionary in Traits.collect_features(record):
		var name: String = String(feature.get("name", ""))
		var spell_id := ""
		var class_label := ""
		var resource_name := ""
		if name == "Bardic Inspiration" and bard_level >= 1:
			spell_id = BARDIC
			class_label = "Bard"
			resource_name = "Bardic Inspiration"
		elif name == "Wild Shape" and druid_level >= 2:
			spell_id = WILD_SHAPE
			class_label = "Druid"
			resource_name = "Wild Shape"
		if spell_id.is_empty():
			continue
		var tracker_id := ""
		for tracker: Dictionary in trackers:
			if String(tracker.get("name", "")).nocasecmp_to(resource_name) == 0 and (
				class_label.to_lower() in String(tracker.get("id", "")).to_lower()
			):
				tracker_id = String(tracker.get("id", ""))
				break
		if tracker_id.is_empty():
			continue
		result.append({
			"id": "auto:" + String(feature.get("key", "")) + ":" + spell_id,
			"origin_id": "feature:" + String(feature.get("key", "")),
			"origin_name": String(feature.get("name", name)),
			"spell_id": spell_id,
			"tracker_id": tracker_id,
			"automatic": true
		})
	return result


static func all_grants(record: Dictionary) -> Array[Dictionary]:
	var grants: Array[Dictionary] = _builtins(record)
	var additional: Dictionary = Structured5e.for_creature(record)
	var dedupe: Dictionary = {}
	for grant: Dictionary in grants:
		dedupe[String(grant.get("origin_id", "")) + "|" + String(grant.get("spell_id", ""))] = true
	for raw: Variant in record.get("origin_spell_grants", []):
		if not raw is Dictionary:
			continue
		var item: Dictionary = raw
		var sid: String = String(item.get("origin_id", ""))
		var spell_id: String = String(item.get("spell_id", ""))
		if sid.is_empty() or spell_id.is_empty() or Catalog.catalog_spell(spell_id).is_empty():
			continue
		var key: String = sid + "|" + spell_id
		if dedupe.has(key):
			continue
		dedupe[key] = true
		grants.append({
			"id": String(item.get("id", key)),
			"origin_id": sid,
			"origin_name": String(item.get("origin_name", sid)),
			"spell_id": spell_id,
			"tracker_id": String(item.get("tracker_id", "")),
			"automatic": false
		})
	for value: Variant in additional.get("grants", []):
		if not value is Dictionary:
			continue
		var grant: Dictionary = value
		var key: String = String(grant.get("origin_id", "")) + "|" + String(grant.get("spell_id", ""))
		if dedupe.has(key):
			continue
		dedupe[key] = true
		grants.append(grant)
	var enabled: Dictionary = Profs.origin_enabled_map(record)
	var output: Array[Dictionary] = []
	var active_origins: Dictionary = {}
	for source: Dictionary in Profs.origins(record):
		active_origins[String(source.get("id", ""))] = true
	for feature: Dictionary in Traits.collect_features(record):
		active_origins["feature:" + String(feature.get("key", ""))] = true
	for raw: Variant in record.get("inventory", []):
		if raw is Dictionary and int(raw.get("quantity", 1)) > 0:
			active_origins["item:" + String(raw.get("id", ""))] = true
	for key: String in ["grants", "choices"]:
		for value: Variant in additional.get(key, []):
			if value is Dictionary:
				active_origins[String((value as Dictionary).get("origin_id", ""))] = true
	for grant: Dictionary in grants:
		var origin_id: String = String(grant.get("origin_id", ""))
		if not active_origins.has(origin_id) or not bool(enabled.get(origin_id, true)):
			continue
		output.append(grant)
	return output


static func tracker_for(record: Dictionary, grant: Dictionary) -> Dictionary:
	var id: String = String(grant.get("tracker_id", ""))
	if id.is_empty():
		return {}
	for entry: Dictionary in Trackers.for_creature(record):
		if String(entry.get("id", "")) == id:
			return entry
	return {}


static func remaining(record: Dictionary, grant: Dictionary) -> int:
	var id: String = String(grant.get("tracker_id", ""))
	if id.is_empty():
		return -1  # Explicit unlimited casting, no slot.
	var tracker: Dictionary = tracker_for(record, grant)
	if tracker.is_empty() or bool(tracker.get("disabled", false)):
		return 0
	var enabled: Dictionary = Profs.origin_enabled_map(record)
	if not bool(enabled.get(String(tracker.get("origin_id", "")), true)):
		return 0
	var cap: int = maxi(0, Bonuses.add(record, "tracker:" + id, int(tracker.get("max", 0))))
	var used: int = int(record.get("resource_tracker_spent", {}).get(id, 0))
	return maxi(0, cap - used)


static func spend(record: Dictionary, grant: Dictionary) -> bool:
	if remaining(record, grant) == 0:
		return false
	var id: String = String(grant.get("tracker_id", ""))
	if id.is_empty():
		return true
	var spent: Dictionary = record.get("resource_tracker_spent", {}).duplicate(true)
	spent[id] = int(spent.get(id, 0)) + 1
	record["resource_tracker_spent"] = spent
	return true


static func cast_context(record: Dictionary, spell_id: String) -> Dictionary:
	# Snapshot the granting caster's level at cast time. The recipient's
	# statistics must never influence the size of a granted spell's die.
	var definition: Dictionary = Catalog.catalog_spell(spell_id)
	var source_class: String = String(definition.get("source_class", ""))
	var source_level: int = _class_level(record, source_class) if not source_class.is_empty() else int(record.get("level", 0))
	var dice := ""
	var progression: Variant = definition.get("dice_progression", [])
	if progression is Array:
		for value: Variant in progression:
			if value is Dictionary and int(value.get("level", 0)) <= source_level:
				dice = String(value.get("dice", ""))
	return {
		"source_level": source_level, "bonus_dice": dice,
		"caster_name": String(record.get("name", ""))
	}
