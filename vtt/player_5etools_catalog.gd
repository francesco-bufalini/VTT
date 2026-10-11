extends RefCounted

const ContentCatalog = preload("res://vtt/content_catalog.gd")
const CATALOG_PATH := "res://vtt/data/player_5etools_catalog.json"
# Keep the searchable/structured catalog compact. Load detailed 5etools prose
# only for the selected entry, never for every item in an OptionButton.
const DESCRIPTION_PATHS := {
	"classes": "res://vtt/data/compendium_class_fluff_5etools.json",
	"subclasses": "res://vtt/data/compendium_subclass_features_5etools.json",
	"backgrounds": "res://vtt/data/compendium_backgrounds_5etools.json",
	"feats": "res://vtt/data/compendium_features_5etools.json",
	"optional_features": "res://vtt/data/compendium_features_5etools.json",
	"races": "res://vtt/data/compendium_features_5etools.json",
	"languages": "res://vtt/data/compendium_features_5etools.json",
	"species_traits": "res://vtt/data/compendium_features_5etools.json",
	"weapons": "res://vtt/data/compendium_items_5etools.json",
	"armor": "res://vtt/data/compendium_items_5etools.json",
	"tools": "res://vtt/data/compendium_items_5etools.json",
	"mundane_items": "res://vtt/data/compendium_items_5etools.json",
	"magic_items": "res://vtt/data/compendium_items_5etools.json"
}
static var _description_files: Dictionary = {}


static func _description_index(category: String) -> Dictionary:
	var path: String = String(DESCRIPTION_PATHS.get(category, ""))
	if path.is_empty():
		return {}
	if not _description_files.has(path):
		var parsed: Dictionary = {}
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file != null:
			var content: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if content is Dictionary:
				parsed = content
		_description_files[path] = parsed
	return (_description_files[path] as Dictionary).get(category, {})


static func _description_key(category: String, entry: Dictionary) -> String:
	var key: String = String(entry.get("name", "")).strip_edges().to_lower() + "|" + String(entry.get("source", "")).strip_edges().to_lower()
	if category == "species_traits":
		key += "|" + String(entry.get("species", "")).strip_edges().to_lower()
	return key


static func detailed_entry(category: String, entry: Dictionary) -> Dictionary:
	var output: Dictionary = entry.duplicate(true)
	# Homebrew overrides have priority over imported 5etools descriptions.
	if String(entry.get("origin", "")) == "homebrew":
		return output
	var lookup_category: String = category
	if category == "items":
		# Inventory origins reference the unified item list, while the offline
		# prose indexes retain their original equipment categories.
		var item_id: String = String(entry.get("id", "")).to_lower()
		for candidate: String in ["magic_items", "mundane_items", "weapons", "armor", "tools"]:
			var prefix: String = {
				"magic_items": "magic_item:", "mundane_items": "mundane_item:",
				"weapons": "weapon:", "armor": "armor:", "tools": "tool:"
			}[candidate]
			if item_id.begins_with(prefix):
				lookup_category = candidate
				break
	var indexed: Dictionary = _description_index(lookup_category)
	var raw: Variant = indexed.get(_description_key(lookup_category, entry), {})
	if raw is Dictionary:
		var detail: Dictionary = raw
		for field: String in ["entries", "fluff"]:
			if (not output.has(field) or output.get(field) in [null, "", []]) and detail.has(field):
				output[field] = detail[field]
	return output


static func description_text(category: String, entry: Dictionary) -> String:
	var detail: Dictionary = detailed_entry(category, entry)
	var sections: PackedStringArray = []
	for field: String in ["entries", "description", "text", "additionalEntries", "fluff"]:
		if not detail.has(field):
			continue
		var parts: PackedStringArray = []
		_flatten_description_value(detail[field], parts, 0)
		var content: String = "\n\n".join(parts).strip_edges()
		if not content.is_empty() and content not in sections:
			sections.append(("Approfondimento:\n" if field == "fluff" else "") + content)
	return "\n\n".join(sections)


static var _catalog: Dictionary = {}
static var _references: Dictionary = {}
static var _subclass_catalogs: Dictionary = {}
static var _merged_catalogs: Dictionary = {}
static var _merged_revision := -1


static func _ensure_loaded() -> void:
	if not _catalog.is_empty():
		return
	if not FileAccess.file_exists(CATALOG_PATH):
		push_error("Player5eToolsCatalog: catalogo non trovato.")
		return
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("Player5eToolsCatalog: impossibile aprire il catalogo.")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_catalog = parsed as Dictionary
	else:
		push_error("Player5eToolsCatalog: JSON non valido.")


static func entries(category: String) -> Array[Dictionary]:
	_ensure_loaded()
	var revision: int = ContentCatalog.revision()
	if revision != _merged_revision:
		_merged_catalogs.clear()
		_merged_revision = revision
	if _merged_catalogs.has(category):
		return (_merged_catalogs[category] as Array[Dictionary]).duplicate(true)
	var result: Array[Dictionary] = []
	var categories: Array[String] = [category]
	if category == "items":
		categories = ["weapons", "armor", "tools", "mundane_items", "magic_items"]
	for source_category: String in categories:
		var value: Variant = _catalog.get(source_category, [])
		if value is Array:
			for item: Variant in value:
				if item is Dictionary:
					result.append((item as Dictionary).duplicate(true))
	if category in ["subclasses", "subclass_features"]:
		if not _subclass_catalogs.has(category):
			var path: String = (
				"res://vtt/data/subclasses_5etools.json" if category == "subclasses"
				else "res://vtt/data/subclass_features_5etools.json"
			)
			var data: Dictionary = {}
			var extra_file: FileAccess = FileAccess.open(path, FileAccess.READ)
			if extra_file != null:
				var parsed: Variant = JSON.parse_string(extra_file.get_as_text())
				extra_file.close()
				if parsed is Dictionary:
					data = parsed as Dictionary
			_subclass_catalogs[category] = data.get(category, [])
		var extra_rows: Variant = _subclass_catalogs.get(category, [])
		if extra_rows is Array:
			for item: Variant in extra_rows:
				if item is Dictionary:
					result.append((item as Dictionary).duplicate(true))
	if category in ["classes", "races", "class_features"]:
		if _references.is_empty():
			var reference_file := FileAccess.open("res://vtt/data/creature_references_5etools.json", FileAccess.READ)
			if reference_file != null:
				var reference_value: Variant = JSON.parse_string(reference_file.get_as_text())
				reference_file.close()
				if reference_value is Dictionary:
					_references = reference_value
		var reference_value: Variant = _references
		if reference_value is Dictionary and reference_value.get(category) is Array:
			if category == "class_features":
				# Detailed core entries replace matching metadata IDs only.
				var keys: Dictionary = {}
				for row: Dictionary in reference_value[category]:
					keys[String(row.name) + "|" + String(row.class_name) + "|" + String(row.class_source) + "|" + str(row.level)] = true
				var retained: Array[Dictionary] = []
				for row: Dictionary in result:
					if not keys.has(String(row.name) + "|" + String(row.class_name) + "|" + String(row.class_source) + "|" + str(row.level)):
						retained.append(row)
				result = retained
			for raw: Variant in reference_value[category]:
				if raw is Dictionary:
					result.append(raw.duplicate(true))
	# The compact player catalog can omit backgrounds even though the
	# bundled structured proficiency index contains their full identifiers.
	# Include those options while keeping catalog/homebrew entries authoritative.
	if category == "backgrounds":
		# 2024 backgrounds and older supplements can lack proficiency grants,
		# but they still belong in the compendium and identity selector.
		var complete: Dictionary = _description_index("backgrounds")
		var known: Dictionary = {}
		for row: Dictionary in result:
			known[_description_key("backgrounds", row)] = true
		for raw_key: Variant in complete.keys():
			var detail: Dictionary = complete[raw_key]
			if not known.has(String(raw_key)):
				known[String(raw_key)] = true
				result.append({"id": "background:" + String(raw_key), "name": String(detail.get("name", "")), "source": String(detail.get("source", ""))})
		var existing: Dictionary = {}
		for entry: Dictionary in result:
			existing[String(entry.get("name", "")).to_lower() + "|" + String(entry.get("source", "")).to_lower()] = true
		var index_file := FileAccess.open("res://vtt/data/proficiency_grants_5etools.json", FileAccess.READ)
		if index_file != null:
			var indexed: Variant = JSON.parse_string(index_file.get_as_text())
			index_file.close()
			if indexed is Dictionary:
				var background_rows: Variant = (indexed as Dictionary).get("background", [])
				if background_rows is Array:
					for row: Variant in background_rows:
						if not row is Dictionary:
							continue
						var name: String = String(row.get("name", "")).strip_edges()
						var source: String = String(row.get("source", "")).strip_edges()
						var key: String = name.to_lower() + "|" + source.to_lower()
						if name.is_empty() or existing.has(key):
							continue
						existing[key] = true
						result.append({"id": "background:" + key, "name": name, "source": source})
	var merged: Array[Dictionary] = ContentCatalog.merge(category, result)
	if category == "items":
		merged.append_array(ContentCatalog.merge("documents", []))
	if category in ["races", "feats", "items", "subclasses", "backgrounds"]:
		# Merge first, then sort once. Core, supplements and homebrew must
		# participate in a single alphabetical ordering.
		merged.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				var first := String(a.get("name", ""))
				var second := String(b.get("name", ""))
				if first.naturalnocasecmp_to(second) == 0:
					return String(a.get("source", "")).naturalnocasecmp_to(
						String(b.get("source", ""))
					) < 0
				return first.naturalnocasecmp_to(second) < 0
		)
	# Preserve the public editable-copy contract; callers must never mutate
	# the shared catalog used by other sheets.
	_merged_catalogs[category] = merged.duplicate(true)
	return merged


# One selectable class per name and rules edition. Supplements contribute
# features to a class; they do not create new character classes.
# Homebrew classes retain their own IDs and are not merged by display name.
static func class_choices(rules_version: String = "2014") -> Array[Dictionary]:
	var chosen: Dictionary = {}
	var priorities: Dictionary = {}
	for entry: Dictionary in entries("classes"):
		var name := String(entry.get("name", "")).strip_edges()
		if name.is_empty():
			continue
		var key := name.to_lower()
		if String(entry.get("origin", "")) == "homebrew":
			key = "homebrew:" + String(entry.get("id", ""))
		var priority := _class_source_priority(String(entry.get("source", "")), rules_version)
		if not chosen.has(key) or priority > int(priorities[key]):
			chosen[key] = entry
			priorities[key] = priority
	var result: Array[Dictionary] = []
	for selected: Variant in chosen.values():
		result.append((selected as Dictionary).duplicate(true))
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("name", "")).naturalnocasecmp_to(
				String(b.get("name", ""))
			) < 0
	)
	return result


static func _class_source_priority(source: String, rules_version: String) -> int:
	if rules_version == "2024":
		match source:
			"XPHB": return 100
			"EFA": return 95
			"PHB": return 40
			"TCE": return 35
	else:
		match source:
			"PHB": return 100
			"TCE": return 95
			"XPHB": return 40
			"EFA": return 35
	return 10


static func search(
	category: String,
	query: String = "",
	filters: Dictionary = {},
	limit: int = 120
) -> Array[Dictionary]:
	var normalized_query := query.strip_edges().to_lower()
	var result: Array[Dictionary] = []
	for entry: Dictionary in entries(category):
		if not _matches_filters(entry, filters):
			continue
		if (
			not normalized_query.is_empty()
			and normalized_query not in _search_text(entry)
		):
			continue
		result.append(entry)
		if result.size() >= maxi(1, limit):
			break
	return result


static func _matches_filters(
	entry: Dictionary,
	filters: Dictionary
) -> bool:
	for raw_key: Variant in filters.keys():
		var key := String(raw_key)
		var expected: String = String(filters[raw_key]).strip_edges()
		if expected.is_empty():
			continue

		var actual_value: Variant = entry.get(key)
		if actual_value is Array:
			var found := false
			for array_value: Variant in actual_value:
				if (
					String(array_value).strip_edges().to_lower()
					== expected.to_lower()
				):
					found = true
					break
			if not found:
				return false
		elif (
			String(actual_value).strip_edges().to_lower()
			!= expected.to_lower()
		):
			return false
	return true


static func _search_text(entry: Dictionary) -> String:
	var values: PackedStringArray = []
	for key: String in [
		"name",
		"source",
		"type",
		"rarity",
		"weapon_category",
		"class_name",
		"class_source",
		"species",
		"base_species",
		"category",
		"script",
	]:
		if entry.has(key):
			values.append(String(entry.get(key, "")))
	return " ".join(values).to_lower()


static func display_label(entry: Dictionary) -> String:
	var name := String(entry.get("name", ""))
	var source := String(entry.get("source", ""))
	var details: PackedStringArray = []

	if entry.has("level") and int(entry.get("level", 0)) > 0:
		details.append("Lv %d" % int(entry.get("level", 0)))
	if not String(entry.get("rarity", "")).is_empty():
		var rarity := String(entry.get("rarity", ""))
		if rarity != "none":
			details.append(rarity)
	if not String(entry.get("weapon_category", "")).is_empty():
		details.append(String(entry.get("weapon_category", "")))

	var suffix := ""
	if not details.is_empty():
		suffix = " · " + " · ".join(details)
	if not source.is_empty():
		suffix += " · " + source
	return name + suffix


static func has_property(entry: Dictionary, property_code: String) -> bool:
	var wanted := property_code.strip_edges().to_upper()
	var value: Variant = entry.get("properties", [])
	if not value is Array:
		return false
	for raw_property: Variant in value:
		var property_text := String(raw_property)
		var code := property_text.split("|")[0].strip_edges().to_upper()
		if code == wanted:
			return true
	return false


static func info_text(
	entry: Dictionary,
	description: String = ""
) -> String:
	if entry.is_empty():
		return "Nessuna informazione disponibile."

	var lines: PackedStringArray = []
	lines.append(String(entry.get("name", "Voce catalogo")))
	var source := String(entry.get("source", "")).strip_edges()
	if not source.is_empty():
		lines.append("Fonte: %s" % source)

	var class_name_value := String(
		entry.get("class_name", "")
	).strip_edges()
	if not class_name_value.is_empty():
		var class_line := "Classe: %s" % class_name_value
		var level := int(entry.get("level", 0))
		if level > 0:
			class_line += " · Livello %d" % level
		lines.append(class_line)

	var species := String(entry.get("species", "")).strip_edges()
	if not species.is_empty():
		lines.append("Specie/Razza: %s" % species)

	var category := String(entry.get("category", "")).strip_edges()
	if not category.is_empty():
		lines.append("Categoria: %s" % category)

	var type_code := String(entry.get("type", "")).split("|")[0]
	if not type_code.is_empty():
		lines.append("Tipo: %s" % _item_type_name(type_code))

	var rarity := String(entry.get("rarity", "")).strip_edges()
	if not rarity.is_empty() and rarity.to_lower() != "none":
		lines.append("Rarità: %s" % rarity)

	var damage := String(entry.get("damage", "")).strip_edges()
	if not damage.is_empty():
		var damage_line := "Danno: %s" % damage
		var damage_type := String(
			entry.get("damage_type", "")
		).strip_edges()
		if not damage_type.is_empty():
			damage_line += " %s" % _damage_type_name(damage_type)
		lines.append(damage_line)

	var versatile := String(
		entry.get("versatile_damage", "")
	).strip_edges()
	if not versatile.is_empty():
		lines.append("Danno versatile: %s" % versatile)

	var range_text := String(entry.get("range", "")).strip_edges()
	if not range_text.is_empty():
		lines.append("Gittata: %s ft" % range_text)

	var properties_text := _properties_text(entry)
	if not properties_text.is_empty():
		lines.append("Proprietà: %s" % properties_text)

	var mastery_value: Variant = entry.get("mastery", [])
	if mastery_value is Array and not (mastery_value as Array).is_empty():
		var mastery_names: PackedStringArray = []
		for raw_mastery: Variant in mastery_value:
			mastery_names.append(
				String(raw_mastery).split("|")[0]
			)
		lines.append("Maestria: %s" % ", ".join(mastery_names))

	if entry.has("ac") and entry.get("ac") != null:
		var ac_value: Variant = entry.get("ac")
		if ac_value is Dictionary:
			var ac_data: Dictionary = ac_value as Dictionary
			var base_ac := int(ac_data.get("base", 0))
			if base_ac > 0:
				lines.append("CA base: %d" % base_ac)
			else:
				lines.append("CA: %s" % JSON.stringify(ac_data))
		elif (
			typeof(ac_value) == TYPE_INT
			or typeof(ac_value) == TYPE_FLOAT
		):
			if int(ac_value) > 0:
				lines.append("CA: %d" % int(ac_value))

	if entry.has("weight") and entry.get("weight") != null:
		var weight := float(entry.get("weight", 0.0))
		if weight > 0.0:
			lines.append("Peso: %s lb" % _trim_number(weight))

	if entry.has("value") and entry.get("value") != null:
		var copper := float(entry.get("value", 0.0))
		if copper > 0.0:
			lines.append(
				"Costo: %s gp" % _trim_number(copper / 100.0)
			)

	var mechanic := _known_mechanic_summary(entry)
	if not mechanic.is_empty():
		lines.append("")
		lines.append(mechanic)

	var clean_description := description.strip_edges()
	if not clean_description.is_empty():
		lines.append("")
		lines.append("Descrizione:")
		lines.append(clean_description)

	lines.append("")
	lines.append(
		"Dati strutturati: catalogo locale derivato da 5e.tools."
	)
	return "\n".join(lines)


static func description_text_from_raw_item(entry: Dictionary) -> String:
	if entry.has("entries") or entry.has("description"):
		return ContentCatalog.description(entry)
	var parts: PackedStringArray = []
	for field_name: String in ["entries", "additionalEntries"]:
		if entry.has(field_name):
			_flatten_description_value(entry.get(field_name), parts, 0)
	return "\n\n".join(parts).strip_edges()


static func _flatten_description_value(
	value: Variant,
	parts: PackedStringArray,
	depth: int
) -> void:
	if depth > 12 or value == null:
		return
	if value is String:
		var clean := _clean_5etools_markup(String(value)).strip_edges()
		if not clean.is_empty():
			parts.append(clean)
		return
	if value is Array:
		for child: Variant in value:
			_flatten_description_value(child, parts, depth + 1)
		return
	if not value is Dictionary:
		return

	var data := value as Dictionary
	var entry_type := String(data.get("type", ""))
	var heading := String(data.get("name", "")).strip_edges()
	if not heading.is_empty() and entry_type in ["entries", "item"]:
		parts.append(heading + ":")

	if entry_type == "table":
		var caption := String(data.get("caption", "")).strip_edges()
		if not caption.is_empty():
			parts.append(caption)
		var labels: Variant = data.get("colLabels", [])
		if labels is Array and not (labels as Array).is_empty():
			var label_parts: PackedStringArray = []
			for label_value: Variant in labels:
				label_parts.append(_clean_5etools_markup(String(label_value)))
			parts.append(" | ".join(label_parts))
		var rows: Variant = data.get("rows", [])
		if rows is Array:
			for row_value: Variant in rows:
				if not row_value is Array:
					continue
				var row_parts: PackedStringArray = []
				for cell_value: Variant in row_value:
					if cell_value is String:
						row_parts.append(
							_clean_5etools_markup(String(cell_value))
						)
					else:
						row_parts.append(str(cell_value))
				parts.append(" | ".join(row_parts))
		return

	for child_key: String in ["entry", "entries", "additionalEntries", "items"]:
		if data.has(child_key):
			_flatten_description_value(
				data.get(child_key),
				parts,
				depth + 1
			)


static func _clean_5etools_markup(value: String) -> String:
	var result := value
	var regex := RegEx.new()
	if regex.compile("\\{@([^ ]+) ([^}]+)\\}") != OK:
		return result
	var matches := regex.search_all(result)
	for match_index: int in range(matches.size() - 1, -1, -1):
		var match: RegExMatch = matches[match_index]
		var tag := match.get_string(1).to_lower()
		var payload := match.get_string(2)
		var visible := payload.split("|")[0]
		if tag == "dc":
			visible = "DC " + visible
		elif tag == "hit":
			visible = visible + " al tiro per colpire"
		result = (
			result.substr(0, match.get_start())
			+ visible
			+ result.substr(match.get_end())
		)
	result = result.replace("\u00a0", " ")
	return result


static func _known_mechanic_summary(entry: Dictionary) -> String:
	var name := String(entry.get("name", "")).strip_edges().to_lower()
	match name:
		"sneak attack":
			return (
				"Attacco Furtivo: aggiunge dadi d6 una volta per turno "
				+ "a un attacco idoneo; i dadi aumentano con il livello da Ladro."
			)
		"martial arts":
			return (
				"Arti Marziali: abilita il dado marziale e l'uso della "
				+ "caratteristica marziale per colpi senz'armi/armi idonee."
			)
		"flurry of blows":
			return (
				"Raffica di Colpi: permette più colpi senz'armi come parte "
				+ "della risorsa/azione bonus del Monaco."
			)
		"ki-fueled attack":
			return (
				"Ki-Fueled Attack: dopo aver speso Ki durante l'azione, "
				+ "consente un ulteriore attacco idoneo come azione bonus."
			)
		"bonus unarmed strike":
			return (
				"Bonus Unarmed Strike: concede un colpo senz'armi aggiuntivo "
				+ "tramite l'azione bonus prevista dal privilegio."
			)
		"cunning strike":
			return (
				"Cunning Strike: permette di scambiare parte dei dadi "
				+ "dell'Attacco Furtivo con effetti aggiuntivi."
			)
		"heightened focus":
			return (
				"Heightened Focus: potenzia le opzioni di Focus del Monaco, "
				+ "inclusa Raffica di Colpi."
			)
	return ""


static func _properties_text(entry: Dictionary) -> String:
	var value: Variant = entry.get("properties", [])
	if not value is Array:
		return ""
	var names: PackedStringArray = []
	for raw_property: Variant in value:
		var code := String(raw_property).split("|")[0].to_upper()
		names.append(_property_name(code))
	return ", ".join(names)


static func _property_name(code: String) -> String:
	match code:
		"F":
			return "Finesse"
		"L":
			return "Leggera"
		"T":
			return "Lancio"
		"V":
			return "Versatile"
		"H":
			return "Pesante"
		"2H":
			return "A due mani"
		"A":
			return "Munizioni"
		"R":
			return "Portata"
		"LD":
			return "Caricamento"
		"RLD":
			return "Ricarica"
	return code


static func _item_type_name(code: String) -> String:
	match code:
		"M":
			return "Arma da mischia"
		"R":
			return "Arma a distanza"
		"LA":
			return "Armatura leggera"
		"MA":
			return "Armatura media"
		"HA":
			return "Armatura pesante"
		"S":
			return "Scudo"
		"AT":
			return "Strumento da artigiano"
		"INS":
			return "Strumento musicale"
		"SCF":
			return "Focus da incantatore"
	return code


static func _damage_type_name(code: String) -> String:
	match code.to_upper():
		"B":
			return "contundente"
		"P":
			return "perforante"
		"S":
			return "tagliente"
	return code


static func _trim_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value
