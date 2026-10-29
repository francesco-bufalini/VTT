extends RefCounted

# UI- and board-independent trait projection from 5etools/homebrew records.
# Both the desktop traits view and tracker derivation use this one service.
const BenefitRequirements = preload("res://vtt/benefit_requirements.gd")
const PlayerCatalog = preload("res://vtt/player_5etools_catalog.gd")
const ClassMechanics = preload("res://vtt/class_mechanics_5etools.gd")
const RaceRules = preload("res://vtt/creature_race_rules.gd")
const ContentCatalog = preload("res://vtt/content_catalog.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")
const Items = preload("res://vtt/creature_item_rules.gd")
const SpellCatalog = preload("res://vtt/spells/spell_catalog.gd")
const Infusions = preload("res://vtt/creature_infusions.gd")

# Formula/proficiency evaluation requests the same traits many times per edit.
# Compare complete snapshots so every field (including nested homebrew data)
# invalidates safely. Keep a small bound rather than retaining whole archives.
static var _feature_cache: Array[Dictionary] = []
static var _feature_revision := -1


static func collect_features(record: Dictionary) -> Array[Dictionary]:
	var revision: int = ContentCatalog.revision()
	if revision != _feature_revision:
		_feature_cache.clear()
		_feature_revision = revision
	for cached: Dictionary in _feature_cache:
		if cached["record"] == record:
			return (cached["features"] as Array[Dictionary]).duplicate(true)
	var features: Array[Dictionary] = _collect_features(record)
	if _feature_cache.size() >= 8:
		_feature_cache.pop_front()
	_feature_cache.append({"record": record.duplicate(true), "features": features.duplicate(true)})
	return features


static func _collect_features(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if record.is_empty():
		return result
	var kind: String = String(record.get("kind", ""))
	if kind == "monster":
		_collect_monster(record, result)
	else:
		_collect_species(record, result)

	# A selected background contributes readable traits too (not just
	# structured proficiencies). Preserve each named feature as a separate card.
	var background_name: String = String(record.get("background", "")).strip_edges()
	var background_book: String = String(record.get("background_source", ""))
	var background_id: String = String(record.get("background_id", ""))
	if not background_name.is_empty():
		for candidate: Dictionary in PlayerCatalog.entries("backgrounds"):
			if not background_id.is_empty() and String(candidate.get("id", "")) == background_id:
				pass
			elif (String(candidate.get("name", "")).nocasecmp_to(background_name) != 0
				or (not background_book.is_empty() and String(candidate.get("source", "")) != background_book)):
				continue
			var background: Dictionary = PlayerCatalog.detailed_entry("backgrounds", candidate)
			var origin: String = "Background · " + background_name
			var origin_key: String = "background|" + String(background.get("source", "")).to_lower() + "|" + background_name.to_lower()
			var raw_entries: Variant = background.get("entries", background.get("description", []))
			_append(result, {"id": "overview", "name": "Descrizione · " + background_name,
				"source": String(background.get("source", "")),
				"entries": PlayerCatalog.description_text("backgrounds", background),
				"feats": background.get("feats", []),
				"resist": background.get("resist", []), "immune": background.get("immune", []),
				"conditionImmune": background.get("conditionImmune", [])},
				1, origin, origin_key, "", "", 0)
			var found_named := false
			if raw_entries is Array:
				for section: Variant in raw_entries:
					if not section is Dictionary:
						continue
					var section_data: Dictionary = section
					if String(section_data.get("name", "")).strip_edges().is_empty():
						continue
					if not section_data.has("entries") and not section_data.has("entry"):
						continue
					var feature: Dictionary = section_data.duplicate(true)
					feature["entries"] = section_data.get("entries", section_data.get("entry", ""))
					feature["source"] = String(background.get("source", ""))
					_append(result, feature, 1, origin, origin_key, "", "", 2)
					found_named = true
			if not found_named:
				_append(result, {
					"name": "Tratti del background · " + background_name,
					"source": String(background.get("source", "")),
					"entries": raw_entries
				}, 1, origin, origin_key, "", "", 2)
			break

	# A spell chosen as the source of a benefit is a live trait, like a feat
	# or an item. The spell ID is stable across editors and saved records.
	var seen_spells: Dictionary = {}
	for raw_origin: Variant in record.get("proficiency_origins", []):
		if not raw_origin is Dictionary:
			continue
		var source: Dictionary = raw_origin
		var sid: String = String(source.get("id", ""))
		if String(source.get("group", "")) != "spell" or not sid.begins_with("spell:") or seen_spells.has(sid):
			continue
		seen_spells[sid] = true
		var spell_id: String = sid.substr(6)
		var spell_data: Dictionary = SpellCatalog.catalog_spell(spell_id)
		if spell_data.is_empty():
			continue
		var spell_name: String = String(spell_data.get("name", spell_id))
		_append(result, {
			"id": spell_id, "name": spell_name,
			"source": String(spell_data.get("source", "")),
			"inactive": bool(source.get("disabled", false)),
			"entries": spell_data.get("entries", spell_data.get("description", "")),
			"vulnerable": spell_data.get("vulnerable", []),
			"resist": spell_data.get("resist", []),
			"immune": spell_data.get("immune", []),
			"conditionImmune": spell_data.get("conditionImmune", []),
			"bonuses": spell_data.get("bonuses", [])
		}, 1, "Incantesimo · " + spell_name, sid, "", "", 2)

	# Explicitly selected feats are traits in their own right. Their full
	# descriptions are loaded on demand; no mechanics are inferred from prose.
	var raw_feats: Variant = record.get("feats_catalog", [])
	if raw_feats is Array:
		var all_feats: Array[Dictionary] = PlayerCatalog.entries("feats")
		var seen_feats: Dictionary = {}
		for raw_feat: Variant in raw_feats:
			if not raw_feat is Dictionary:
				continue
			var owned: Dictionary = raw_feat
			var source_id: String = Proficiencies.feat_source_id(owned)
			if seen_feats.has(source_id):
				continue
			seen_feats[source_id] = true
			var feat_name: String = String(owned.get("name", ""))
			if feat_name.is_empty():
				continue
			var feat_source: String = String(owned.get("source", ""))
			var feat_entry: Dictionary = PlayerCatalog.detailed_entry("feats", owned)
			for candidate: Dictionary in all_feats:
				if String(candidate.get("name", "")) == feat_name and String(candidate.get("source", "")) == feat_source:
					feat_entry = PlayerCatalog.detailed_entry("feats", candidate)
					break
			var feat_id: String = String(owned.get("id", ""))
			if feat_id.is_empty():
				feat_id = feat_name.to_lower() + "|" + feat_source.to_lower()
			_append(result, {
				"id": feat_id, "name": feat_name, "source": feat_source,
				"inactive": bool(owned.get("disabled", false)),
				"feats": feat_entry.get("feats", []),
				"resist": feat_entry.get("resist", []), "immune": feat_entry.get("immune", []),
				"conditionImmune": feat_entry.get("conditionImmune", []),
				"entries": PlayerCatalog.info_text(feat_entry, PlayerCatalog.description_text("feats", feat_entry))
			}, 1, "Talento · " + feat_name, "feat|" + feat_id, "", "", 3)
			var sections: Variant = feat_entry.get("feature_sections", null)
			if sections is Array:
				# Character creation options supply nested named sections with
				# explicit character-level gates in the offline normalized index.
				for raw_section: Variant in sections:
					if not raw_section is Dictionary:
						continue
					var section: Dictionary = raw_section
					var gate: Dictionary = BenefitRequirements.normalize(section,
						"character", "", "", "min_level", 1)
					if not BenefitRequirements.allows(record, gate):
						continue
					var threshold: int = maxi(1, int(gate.get("min_level", 1)))
					var detail: Dictionary = section.duplicate(true)
					detail["inactive"] = bool(owned.get("disabled", false))
					detail["source"] = feat_source
					_append(result, detail, threshold, "Talento · " + feat_name,
						"feat|" + feat_id, "", "", 3)
			else:
				_append_named_entries(result, feat_entry.get("entries", []),
					"Talento · " + feat_name, "feat|" + feat_id, feat_source, 3,
					bool(owned.get("disabled", false)))

	# Every selected optional ability is a first-class trait with its own
	# stable identity. This includes Metamagic, maneuvers and invocations:
	# activation must not be granted merely by a class-level option list.
	var seen_optional: Dictionary = {}
	for raw_optional: Variant in record.get("optional_features_catalog", []):
		if not raw_optional is Dictionary:
			continue
		var selected: Dictionary = raw_optional
		var option_name: String = String(selected.get("name", "")).strip_edges()
		if option_name.is_empty():
			continue
		var book: String = String(selected.get("source", "")).strip_edges()
		var identity: String = "optional|" + book.to_lower() + "|" + option_name.to_lower()
		if seen_optional.has(identity):
			continue
		seen_optional[identity] = true
		var detail: Dictionary = PlayerCatalog.detailed_entry("optional_features", selected)
		_append(result, {
			"id": String(selected.get("id", option_name.to_lower())),
			"name": option_name, "source": book,
			"inactive": bool(selected.get("disabled", false)),
			"entries": selected.get("entries", PlayerCatalog.description_text("optional_features", detail)),
			"action_type": selected.get("action_type", detail.get("action_type", ""))
		}, 0, "Privilegio opzionale · " + option_name, identity, "", "", 2)

	# Known artificer infusions are already optional class features; display
	# their existing 5etools descriptions among ordinary class traits.
	for known: Dictionary in Infusions.known(record):
		var option: Dictionary = PlayerCatalog.detailed_entry("optional_features", known)
		var display_name: String = String(known.get("name", ""))
		var plan: String = String(known.get("plan_item_name", ""))
		if not plan.is_empty():
			display_name += " · " + plan
		_append(result, {"id": String(known.get("id", "")) + "|" + plan.to_lower(),
			"name": "Infusione · " + display_name,
			"source": "TCE", "entries": PlayerCatalog.description_text("optional_features", option)},
			int(known.get("min_level", 2)), "Classe · Artificer", "class|tce|artificer", "Artificer", "TCE", 3)

	# Inventory entries remain visible as traits while owned. Equipment
	# controls only their effective origins, not whether the item exists.
	var inventory: Variant = record.get("inventory", [])
	if inventory is Array:
		var owned_groups: Dictionary = {}
		for raw_owned: Variant in inventory:
			if not raw_owned is Dictionary:
				continue
			var owned: Dictionary = raw_owned
			if int(owned.get("quantity", 1)) <= 0:
				continue
			var item_id: String = String(owned.get("id", ""))
			if item_id.is_empty():
				continue
			if not owned_groups.has(item_id):
				owned_groups[item_id] = {"owned": owned, "active": false, "quantity": 0}
			var group: Dictionary = owned_groups[item_id]
			group["active"] = bool(group.get("active", false)) or Items.origin_active(owned, record)
			group["quantity"] = int(group.get("quantity", 0)) + int(owned.get("quantity", 1))
		for item_id: String in owned_groups.keys():
			var group: Dictionary = owned_groups[item_id]
			var owned: Dictionary = group["owned"]
			var definition: Dictionary = Items.entry_for(owned)
			# Documents are inventory content, not game-mechanical traits.
			if Items.kind(definition) == "document":
				continue
			var detailed: Dictionary = PlayerCatalog.detailed_entry("items", definition)
			var inactive: bool = not bool(group.get("active", false))
			var description: String = PlayerCatalog.description_text("items", detailed)
			if description.is_empty():
				description = String(owned.get("description", definition.get("description", "")))
			var item_label: String = String(owned.get("name", definition.get("name", item_id)))
			var count: int = int(group.get("quantity", 1))
			_append(result, {"id": "overview", "name": "Descrizione · " + item_label + (" ×%d" % count if count > 1 else ""),
				"source": String(definition.get("source", "")), "entries": description,
				"inactive": inactive, "feats": detailed.get("feats", definition.get("feats", [])),
				"resist": detailed.get("resist", []), "immune": detailed.get("immune", []),
				"conditionImmune": detailed.get("conditionImmune", [])},
				0, "Oggetto · " + item_label, "item:" + item_id, "", "", 4)
			_append_named_entries(result, detailed.get("entries", []),
				"Oggetto · " + item_label, "item:" + item_id,
				String(definition.get("source", "")), 4, inactive, record)

	var raw_classes: Variant = record.get("classes", [])
	var classes: Array = raw_classes as Array if raw_classes is Array else []
	if classes.is_empty() and not String(record.get("class", "")).is_empty():
		classes = [{
			"name": record.get("class", ""),
			"source": record.get("class_source", ""),
			"level": record.get("level", 1),
			"subclass": record.get("subclass", ""),
			"subclass_source": record.get("subclass_source", "")
		}]
	var class_features: Array[Dictionary] = PlayerCatalog.entries("class_features")
	var subclass_features: Array[Dictionary] = PlayerCatalog.entries("subclass_features")
	for raw: Variant in classes:
		if not raw is Dictionary:
			continue
		var definition: Dictionary = raw as Dictionary
		var class_label: String = String(definition.get("name", ""))
		if class_label.is_empty() or class_label.to_lower() == "mostro":
			continue
		var class_book: String = String(definition.get("source", record.get("class_source", "")))
		if class_book.is_empty():
			# Legacy sheets omit the source: resolve the same source-qualified
			# edition used by class trackers, rather than generating features
			# with a class|| identity or accidentally mixing 2014/2024 data.
			var requested := "XPHB" if String(record.get("rules_version", "2014")) == "2024" else "PHB"
			class_book = String(ClassMechanics.class_row(class_label, requested).get("source", requested))
		var class_level: int = clampi(int(definition.get("level", 1)), 1, 20)
		var class_origin: String = "Classe · " + class_label
		var class_key: String = "class|" + class_book.to_lower() + "|" + class_label.to_lower()
		for class_entry: Dictionary in PlayerCatalog.entries("classes"):
			if String(class_entry.get("name", "")).nocasecmp_to(class_label) != 0 or String(class_entry.get("source", "")) != class_book:
				continue
			var overview: Dictionary = PlayerCatalog.detailed_entry("classes", class_entry)
			_append(result, {"id": "overview", "name": "Descrizione · " + class_label,
				"source": class_book, "entries": PlayerCatalog.description_text("classes", overview),
				"feats": overview.get("feats", class_entry.get("feats", [])),
				"resist": overview.get("resist", []), "immune": overview.get("immune", []),
				"conditionImmune": overview.get("conditionImmune", [])},
				1, class_origin, class_key, class_label, class_book, 0)
			_append_named_entries(result, overview.get("entries", []), class_origin, class_key, class_book, 0)
			break
		# Level-one synthetic feature: a structured 5etools class overview.
		# The source ID used by the proficiency editor remains the same.
		for source: Dictionary in Proficiencies.candidate_sources(record):
			if String(source.get("group", "")) != "class":
				continue
			var indexed: Dictionary = source.get("data", {})
			if String(indexed.get("name", "")).nocasecmp_to(class_label) != 0 or String(indexed.get("source", "")) != class_book:
				continue
			_append(result, {
				"name": ("Multiclass " if String(source.get("mode", "starting")) == "multiclass" else "Starting ") + class_label,
				"source": class_book,
				"entries": Proficiencies.starting_description(source)
			}, 1, class_origin, class_key, class_label, class_book, 0)
			break
		for feature: Dictionary in class_features:
			if String(feature.get("class_name", "")).nocasecmp_to(class_label) != 0:
				continue
			if not class_book.is_empty() and String(feature.get("class_source", "")) != class_book:
				continue
			var level: int = int(feature.get("level", 0))
			if level < 1 or not BenefitRequirements.allows(record,
				BenefitRequirements.level_gate(level, "class", class_label, class_book),
				class_level):
				continue
			_append(result, feature, level, class_origin, class_key, class_label, class_book)
		var subclass_name: String = String(definition.get("subclass", ""))
		if subclass_name.is_empty():
			continue
		var subclass_book: String = String(definition.get("subclass_source", ""))
		var subclass_origin: String = "Sottoclasse · %s / %s" % [class_label, subclass_name]
		var subclass_key: String = class_key + "|subclass|" + subclass_name.to_lower() + "|" + subclass_book.to_lower()
		for subclass_entry: Dictionary in PlayerCatalog.entries("subclasses"):
			if String(subclass_entry.get("name", subclass_entry.get("short_name", ""))).nocasecmp_to(subclass_name) != 0:
				continue
			if String(subclass_entry.get("source", "")) != subclass_book:
				continue
			_append(result, {"id": "overview", "name": "Descrizione · " + subclass_name,
				"source": subclass_book, "entries": PlayerCatalog.description_text("subclasses", subclass_entry),
				"feats": subclass_entry.get("feats", []),
				"resist": subclass_entry.get("resist", []), "immune": subclass_entry.get("immune", []),
				"conditionImmune": subclass_entry.get("conditionImmune", [])},
				1, subclass_origin, subclass_key, class_label, class_book, 0)
			break
		for feature: Dictionary in subclass_features:
			if String(feature.get("class_name", feature.get("className", ""))).nocasecmp_to(class_label) != 0:
				continue
			if not class_book.is_empty() and String(feature.get("class_source", "")) != class_book:
				continue
			if (
				String(feature.get("subclass_name", feature.get("subclassName", ""))).nocasecmp_to(subclass_name) != 0
				and String(feature.get("subclass_short_name", "")).nocasecmp_to(subclass_name) != 0
			):
				continue
			if not subclass_book.is_empty() and String(feature.get("subclass_source", "")) != subclass_book:
				continue
			var level: int = int(feature.get("level", 0))
			if level < 1 or not BenefitRequirements.allows(record,
				BenefitRequirements.level_gate(level, "class", class_label, class_book),
				class_level):
				continue
			_append(result, feature, level, subclass_origin, subclass_key, class_label, class_book)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var categories: Array[String] = ["razza", "background", "classi", "talenti", "incantesimi", "oggetti", "mostro", "altro"]
		var group_a: int = categories.find(String(a.get("category", "altro")))
		var group_b: int = categories.find(String(b.get("category", "altro")))
		if group_a != group_b:
			return group_a < group_b
		if int(a["level"]) != int(b["level"]):
			return int(a["level"]) < int(b["level"])
		if int(a["rank"]) != int(b["rank"]):
			return int(a["rank"]) < int(b["rank"])
		var by_origin: int = String(a["origin"]).naturalnocasecmp_to(String(b["origin"]))
		if by_origin != 0:
			return by_origin < 0
		return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0
	)
	return result


# Nested named 5etools entries are also real traits. Preserve their
# structured bonus/feat fields independently from the parent description.
static func _append_named_entries(
	output: Array[Dictionary], value: Variant, origin: String, origin_key: String,
	book: String, rank: int = 2, inactive: bool = false,
	record: Dictionary = {}
) -> void:
	if not value is Array:
		return
	var index := 0
	for raw: Variant in value:
		if not raw is Dictionary:
			index += 1
			continue
		var data: Dictionary = raw
		var name: String = String(data.get("name", "")).strip_edges()
		if name.is_empty() or (not data.has("entries") and not data.has("entry")):
			index += 1
			continue
		var feature_data: Dictionary = data.duplicate(true)
		# Optional typed thresholds let item subtraits become available later,
		# without hiding the parent item or interpreting prose as a mechanic.
		var gate: Dictionary = BenefitRequirements.normalize(data)
		if not record.is_empty() and not BenefitRequirements.allows(record, gate):
			index += 1
			continue
		feature_data["requirements"] = gate
		feature_data["id"] = String(data.get("id", "section-%d" % index))
		feature_data["entries"] = data.get("entries", data.get("entry", ""))
		feature_data["source"] = book
		feature_data["inactive"] = inactive or bool(data.get("inactive", false))
		_append(output, feature_data, maxi(1, int(gate.get("min_level", 0))),
			origin, origin_key, "", "", rank)
		index += 1


static func _append(
	output: Array[Dictionary], feature: Dictionary, level: int, origin: String,
	origin_key: String, class_label: String = "", class_book: String = "",
	rank: int = 2
) -> void:
	var name: String = String(feature.get("name", "")).strip_edges()
	if name.is_empty():
		return
	var key: String = String(feature.get("id", ""))
	if key.is_empty():
		key = "%s|%d|%s" % [origin_key, level, name.to_lower()]
	# Disambiguate a feature appearing in two independently selected sources.
	key = String(feature.get("feature_key", origin_key + "|" + key))
	var description: Variant = feature.get("entries", feature.get("description", ""))
	if description is String and String(description).strip_edges().is_empty():
		description = ContentCatalog.description(feature)
	var category: String = "altro"
	if origin_key.begins_with("species|") or origin_key.begins_with("race|") or origin_key.begins_with("subrace|"):
		category = "razza"
	elif origin_key.begins_with("background|"):
		category = "background"
	elif origin_key.begins_with("class|"):
		category = "classi"
	elif origin_key.begins_with("feat|"):
		category = "talenti"
	elif origin_key.begins_with("item:"):
		category = "oggetti"
	elif origin_key.begins_with("spell:"):
		category = "incantesimi"
	elif origin_key.begins_with("monster|"):
		category = "mostro"
	var gate_scope: String = "class" if origin_key.begins_with("class|") else "character"
	var gate: Dictionary = BenefitRequirements.normalize(
		feature, gate_scope, class_label, class_book, "min_level", level
	)
	output.append({
		"monster_role": feature.get("monster_role", ""),
		"monster_legacy_keys": feature.get("monster_legacy_keys", []),
		"monster_actions": feature.get("monster_actions", []),
		"monster_attack_ids": feature.get("monster_attack_ids", []),
		"monster_tracker_ids": feature.get("monster_tracker_ids", []),
		"monster_pool": feature.get("monster_pool", {}),
		"key": key, "name": name, "level": level, "rank": rank, "category": category,
		"requirements": gate,
		"inactive": bool(feature.get("inactive", false)),
		"feats": feature.get("feats", []),
		"origin": origin, "origin_key": origin_key,
		"book": String(feature.get("source", "")),
		"class_name": class_label, "class_source": class_book,
		"entries": description, "bonuses": feature.get("bonuses", []),
		# Preserve explicit activation/consumption metadata for the action economy.
		# Never infer an action from descriptive feature prose.
		"action_type": feature.get("action_type", feature.get("activation_type", "")),
		"activation": feature.get("activation", null),
		"time": feature.get("time", null),
		"action_kind": feature.get("action_kind", "Capacità"),
		"tracker_id": feature.get("tracker_id", ""),
		# Preserve only explicit structured 5etools defensive grants. Descriptive
		# text and conditional resistances are not interpreted as universal.
		"vulnerable": feature.get("vulnerable", []),
		"resist": feature.get("resist", []),
		"immune": feature.get("immune", []),
		"conditionImmune": feature.get("conditionImmune", [])
	})


static func _collect_species(record: Dictionary, output: Array[Dictionary]) -> void:
	var species: String = String(record.get("species", ""))
	var species_book: String = String(record.get("species_source", ""))
	var species_id: String = String(record.get("species_id", ""))
	var species_origin_id: String = "species|" + (species_id if not species_id.is_empty() else species.to_lower()) + "|" + species_book.to_lower()
	if species.is_empty():
		return
	var subrace_name := String(record.get("subrace", ""))
	var effective := RaceRules.effective_race(
		{"name": species, "source": species_book},
		{"name": subrace_name, "source": record.get("subrace_source", "")}
		if not subrace_name.is_empty() else {})
	var wanted_name: String = String(effective.get("name", species))
	var wanted_source: String = String(effective.get("source", species_book))
	for race: Dictionary in PlayerCatalog.entries("races"):
		if not (
			(subrace_name.is_empty() and not species_id.is_empty() and String(race.get("id", "")) == species_id)
			or (String(race.get("name", "")).nocasecmp_to(wanted_name) == 0
				and String(race.get("source", "")) == wanted_source)
		):
			continue
		_append(output, {"id": "overview", "name": "Descrizione · " + species,
			"source": wanted_source, "entries": PlayerCatalog.description_text("races", race),
			"feats": PlayerCatalog.detailed_entry("races", race).get("feats", race.get("feats", []))},
			# The overview is a readable trait, not a second grant of the
			# race's top-level structured defenses. Those are assigned to
			# the selectable race/subrace origin by the defenses editor.
			1, "Specie · " + species, species_origin_id, "", "", 0)
		var raw: Variant = race.get("entries", race.get("description", []))
		if raw is Array:
			for index: int in range((raw as Array).size()):
				var entry: Variant = (raw as Array)[index]
				if entry is Dictionary:
					var entry_data: Dictionary = (entry as Dictionary).duplicate(true)
					if String(entry_data.get("name", "")).is_empty():
						entry_data["name"] = "Altri tratti · %d" % (index + 1)
					entry_data["entries"] = (entry as Dictionary).get("entries", entry)
					entry_data["source"] = wanted_source
					# Level-gated racial traits must not be collected early merely
					# because their descriptive entry exists in the race catalog.
					if not BenefitRequirements.accepts(record, entry_data, "character", "", "", "level", 1):
						continue
					_append(output, entry_data, maxi(1, int(entry_data.get("level", 1))),
						"Specie · " + species, species_origin_id, "", "", 1)
				elif entry is String and not String(entry).strip_edges().is_empty():
					_append(output, {"name": "Tratto · %d" % (index + 1), "entries": entry, "source": species_book},
						1, "Specie · " + species,
						species_origin_id, "", "", 1)
		else:
			_append(output, {"name": "Tratti della specie", "entries": raw, "source": species_book},
				1, "Specie · " + species, species_origin_id, "", "", 1)
		break


static func _collect_monster(record: Dictionary, output: Array[Dictionary]) -> void:
	for row: Dictionary in preload("res://vtt/monster_trait_projection.gd").traits(record):
		_append(output, row, 0, row.origin, row.origin_key, "", "", int(row.get("rank", 0)))
