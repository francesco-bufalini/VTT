extends RefCounted

# Source-bound presentation. Combat and resource IDs remain unchanged.
const Metadata = preload("res://vtt/monster_action_metadata.gd")

static func origin(record: Dictionary) -> String:
	var stat: Dictionary = record.get("stat_block", {})
	return "monster|" + String(stat.get("source", record.get("source", ""))).to_lower() + "|" + String(stat.get("name", record.get("base_name", record.get("species", "")))).to_lower()

static func legacy_key(section: String, row: Dictionary) -> String:
	var base: String = "monster|" + section
	return base + "|" + String(row.get("id", base + "|0|" + String(row.get("name", "")).to_lower()))

static func is_multiattack(row: Dictionary) -> bool:
	return String(row.get("name", "")).strip_edges().to_lower() in ["multiattack", "multiattacco"]

static func is_resistance(row: Dictionary) -> bool:
	var name: String = String(row.get("name", "")).to_lower()
	return name.begins_with("legendary resistance") or name.begins_with("resistenza leggendaria") or name.begins_with("resistenze leggendarie")

static func action_cost(row: Dictionary) -> int:
	for field: String in ["legendaryActionCost", "actionCost", "cost"]:
		if row.has(field) and int(row[field]) > 0:
			return int(row[field])
	var found: RegExMatch = RegEx.create_from_string("(?i)\\(Costs? (\\d+) Actions?\\)").search(String(row.get("name", "")))
	return int(found.get_string(1)) if found != null else 1

static func lair_options(entries: Array) -> Array:
	var options: Array = []
	for row: Variant in entries:
		if row is Dictionary and row.get("type", "") == "list":
			options.append_array(row.get("items", []))
	return options if not options.is_empty() else entries


static func action_options(action: Dictionary) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	_collect_action_options(action.get("entries", []), options)
	return options


static func _collect_action_options(nodes: Variant, options: Array[Dictionary]) -> void:
	if not nodes is Array:
		return
	for node: Variant in nodes:
		if not node is Dictionary:
			continue
		var items: Array = node.get("items", [])
		if node.get("type", "") == "list" and items.size() >= 2 and items.all(func(item: Variant) -> bool: return item is Dictionary and item.get("type", "") == "item" and not String(item.get("name", "")).strip_edges().is_empty() and (item.has("entry") or item.has("entries"))):
			for item: Dictionary in items:
				options.append({"id": str(options.size()), "name": item.name, "entries": item.get("entry", item.get("entries", []))})
		elif node.has("entries"):
			_collect_action_options(node.entries, options)

static func _make(record: Dictionary, id: String, name: String, entries: Variant = "") -> Dictionary:
	var stat: Dictionary = record.get("stat_block", {})
	return {"id": id, "name": name, "entries": entries, "source": stat.get("source", ""),
		"origin_key": origin(record), "origin": "Mostro · " + String(stat.get("name", record.get("base_name", "Creatura"))),
		"feature_key": origin(record) + "|" + id, "monster_role": id, "rank": 0,
		"monster_actions": [], "monster_attack_ids": [], "monster_tracker_ids": [], "monster_legacy_keys": []}

static func traits(record: Dictionary) -> Array[Dictionary]:
	var stat: Dictionary = record.get("stat_block", {})
	var fluff: Variant = stat.get("fluff", record.get("fluff", stat.get("description", "")))
	if fluff is Dictionary:
		fluff = fluff.get("entries", [])
	var overview: Dictionary = _make(record, "overview", "Panoramica", fluff)
	overview["rank"] = -1
	var output: Array[Dictionary] = [overview]
	var special: Dictionary = {}
	if not stat.get("legendary", []).is_empty():
		var row: Dictionary = _make(record, "legendary", "Azioni leggendarie", stat.get("legendaryHeader", "Concede le azioni leggendarie elencate, ciascuna con il proprio costo."))
		row["monster_pool"] = {"id": "legendary_actions", "name": "Azioni leggendarie", "max": int(stat.get("legendaryActions", stat.get("vtt_legendary_actions", 3))), "recharge": "turn"}
		row.monster_tracker_ids.append("legendary_actions")
		special["legendary"] = row
		output.append(row)
	if not stat.get("lairActions", []).is_empty():
		var row: Dictionary = _make(record, "lair", "Azioni di tana", stat.get("lairHeader", stat.get("lairActions", [])))
		row["monster_pool"] = {"id": "lair_actions", "name": "Azioni di tana", "max": 1, "recharge": "turn"}
		row.monster_tracker_ids.append("lair_actions")
		special["lairActions"] = row
		output.append(row)
	for section: String in ["trait", "action", "bonus", "reaction", "legendary", "mythic", "lairActions"]:
		var entries: Variant = stat.get(section, [])
		if not entries is Array:
			continue
		if section == "lairActions":
			entries = lair_options(entries)
		for index: int in range(entries.size()):
			var raw: Variant = entries[index]
			var row: Dictionary = raw.duplicate(true) if raw is Dictionary else {"name": "Azione di tana · %d" % (index + 1), "entries": [raw]}
			if is_multiattack(row) or section == "trait":
				var projected_trait: Dictionary = _make(record, "trait:%s:%d" % [section, index], String(row.get("name", "")), row.get("entries", row.get("description", "")))
				projected_trait.merge(row, true)
				projected_trait["feature_key"] = legacy_key(section, row)
				projected_trait["monster_role"] = "resistance" if is_resistance(row) else "multiattack" if is_multiattack(row) else "passive"
				if row.get("vtt_resource", {}).has("id"):
					projected_trait.monster_tracker_ids.append(row.vtt_resource.id)
				if is_resistance(row):
					var found: RegExMatch = RegEx.create_from_string("(?i)\\((\\d+)\\s*/\\s*(?:day|giorno)(?:\\)|,)").search(String(row.get("name", "")))
					var resource: Dictionary = row.get("vtt_resource", {})
					var maximum: int = int(resource.get("max", int(found.get_string(1)) if found != null else 0))
					if maximum > 0:
						var id: String = String(resource.get("id", "legendary_resistance"))
						projected_trait["monster_pool"] = {"id": id, "name": row.name, "max": maximum, "recharge": resource.get("recharge", "long_rest")}
						projected_trait["monster_tracker_ids"] = [id]
				output.append(projected_trait)
				continue
			var owner: Dictionary = special.get(section, overview)
			owner.monster_legacy_keys.append(legacy_key(section, row))
			var id: String = "monster:%s:%d" % [section, index]
			var resource_id: String = String(row.get("vtt_resource", {}).get("id", ""))
			if not resource_id.is_empty():
				owner.monster_tracker_ids.append(resource_id)
			var spec: Dictionary = row.get("vtt_attack", {})
			if spec.is_empty() and not stat.has("vtt_action_metadata_version"):
				spec = Metadata.parse_attack(row)
			var attack: bool = String(spec.get("attack_kind", "")) == "attack"
			var rechargeable: bool = "{@recharge" in String(row.get("name", "")) or String(row.get("vtt_resource", {}).get("recharge", "")) in ["d6", "short_rest", "long_rest"]
			var options: Array[Dictionary] = []
			if rechargeable:
				options = action_options(row)
			if attack:
				overview.monster_attack_ids.append(id)
			if not attack or special.has(section) or not options.is_empty():
				var timing: String = {"bonus": "bonus", "reaction": "reaction", "legendary": "legendary", "lairActions": "lair"}.get(section, "action")
				owner.monster_actions.append({"id": id, "name": row.get("name", "Capacità"), "entries": row.get("entries", ""),
					"action_type": timing, "origin_id": "feature:" + String(owner.feature_key),
					"tracker_id": owner.monster_pool.id if special.has(section) else resource_id,
					"cost": action_cost(row) if special.has(section) else 1 if not resource_id.is_empty() else 0,
					"options": options,
					"attack_id": id if attack else ""})
	for caster: Variant in stat.get("spellcasting", []):
		if not caster is Dictionary:
			continue
		var lines: Array = caster.get("headerEntries", []).duplicate(true)
		for level: Variant in caster.get("spells", {}):
			lines.append("Livello " + String(level) + ": " + ", ".join(caster.spells[level].get("spells", [])))
		for mode: String in ["daily", "rest", "weekly", "will", "constant"]:
			var groups: Variant = caster.get(mode, {})
			if groups is Array:
				lines.append(mode + ": " + ", ".join(groups))
			elif groups is Dictionary:
				for count: Variant in groups:
					lines.append(mode + " " + String(count) + ": " + ", ".join(groups[count]))
		lines.append_array(caster.get("footerEntries", []))
		var story: Array = overview.entries if overview.entries is Array else [overview.entries]
		story.append({"name": caster.get("name", "Incantesimi"), "entries": lines})
		overview["entries"] = story
	return output

static func attack_owner(record: Dictionary, id: String) -> Dictionary:
	for row: Dictionary in traits(record):
		if id in row.monster_attack_ids:
			return row
	return {}

static func legacy_sources(record: Dictionary) -> Dictionary:
	var sources: Dictionary = {}
	if record.get("kind", "") != "monster":
		return sources
	for source: Dictionary in traits(record):
		for key: String in source.monster_legacy_keys:
			for prefix: String in ["feature:", "feature:trait:"]:
				sources[prefix + key] = "feature:" + String(source.feature_key)
	return sources

static func bind_trackers(record: Dictionary, trackers: Array[Dictionary]) -> void:
	if record.get("kind", "") != "monster":
		return
	var projected: Array[Dictionary] = traits(record)
	for tracker: Dictionary in trackers:
		var owner: Dictionary = {}
		for projected_trait: Dictionary in projected:
			if tracker.id in projected_trait.monster_tracker_ids:
				owner = projected_trait
				break
		var parts: PackedStringArray = String(tracker.id).split(":")
		if owner.is_empty() and parts.size() == 3 and parts[0] in ["fightclub", "recharge"]:
			if parts[1] == "trait":
				var entries: Array = record.stat_block.get("trait", [])
				if int(parts[2]) >= entries.size():
					continue
				var raw: Dictionary = entries[int(parts[2])]
				for projected_trait: Dictionary in projected:
					if projected_trait.feature_key == legacy_key("trait", raw):
						owner = projected_trait
			else:
				owner = projected[0]
				if parts[1] == "legendary":
					for projected_trait: Dictionary in projected:
						if projected_trait.monster_role == "legendary":
							owner = projected_trait
		if not owner.is_empty():
			tracker["origin_id"] = "feature:" + String(owner.feature_key)
			tracker["origin_name"] = "Tratto · " + String(owner.name)
			tracker["disabled"] = bool(tracker.get("disabled", false)) or record.get("trait_enabled", {}).get(owner.feature_key, true) == false or record.get("origin_enabled", {}).get(tracker.origin_id, true) == false or record.get("origin_enabled", {}).get(owner.origin_key, true) == false
