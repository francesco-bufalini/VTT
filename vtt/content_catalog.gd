extends RefCounted

# Shared data normalization and local content overlays, never private sheets.
const HOME_DIR := "user://homebrew"
const ENRICHMENT_USER_DIR := "user://vtt_enrichment"
const ENRICHMENT_SCRIPT_PATH := "res://vtt/content_enrichment.gd"
const NATIVE_ADAPTER_PATH := "res://vtt/native_5etools_adapter.gd"
const CATEGORIES := ["items", "documents", "subclasses", "subclass_features", "monsters", "races", "classes", "spells", "conditions", "diseases", "effects", "class_features", "species_traits", "feats", "backgrounds", "optional_features"]
const EFFECT_CATEGORIES := ["conditions", "diseases", "effects"]
const MAX_FILE_BYTES := 2 * 1024 * 1024
const LEGACY_CONDITIONS := [
	# Le 15 condizioni ufficiali D&D 5e / SRD.
	{"id": "blinded", "name": "Blinded", "icon": "🙈", "official": true},
	{"id": "charmed", "name": "Charmed", "icon": "💘", "official": true},
	{"id": "deafened", "name": "Deafened", "icon": "🔇", "official": true},
	{"id": "exhaustion", "name": "Exhaustion", "icon": "🥱", "official": true},
	{"id": "frightened", "name": "Frightened", "icon": "😨", "official": true},
	{"id": "grappled", "name": "Grappled", "icon": "🪢", "official": true},
	{"id": "incapacitated", "name": "Incapacitated", "icon": "⛔", "official": true},
	{"id": "invisible", "name": "Invisible", "icon": "👻", "official": true},
	{"id": "paralyzed", "name": "Paralyzed", "icon": "🧊", "official": true},
	{"id": "petrified", "name": "Petrified", "icon": "🗿", "official": true},
	{"id": "poisoned", "name": "Poisoned", "icon": "☠️", "official": true},
	{"id": "prone", "name": "Prone", "icon": "⬇️", "official": true},
	{"id": "restrained", "name": "Restrained", "icon": "⛓️", "official": true},
	{"id": "stunned", "name": "Stunned", "icon": "💫", "official": true},
	{"id": "unconscious", "name": "Unconscious", "icon": "😴", "official": true},

	# Marker tattici utili nel VTT. Non sono condizioni ufficiali SRD.
	{"id": "concentrating", "name": "Concentration", "icon": "🧠", "official": false},
	{"id": "surprised", "name": "Surprised", "icon": "❗", "official": false},
	{"id": "hidden", "name": "Hidden", "icon": "🥷", "official": false},
	{"id": "helped", "name": "Aiutato", "icon": "🤝", "official": false, "description": "Solo marcatore tattico: nessun effetto automatico."},
	{"id": "dead", "name": "Dead", "icon": "💀", "official": false},

]

static var _home: Dictionary = {}
static var _loaded := false
static var _revision := 0
static var _revision_extension: Script
static var diagnostics: Array[String] = []
static var _effects: Array[Dictionary] = []
# Expanded definitions are immutable between enrichment/homebrew reloads.
# Tactical token badges used to rebuild this whole table multiple times a frame.
static var _condition_definition_cache: Dictionary = {}

# The stable core catalog is deliberately independent from the two
# optional adapters. Their scripts are loaded only when invoked; a problem
# in the runtime extension cannot invalidate this script's preloads.
static func _optional_script(path: String) -> Script:
	var resource: Resource = load(path)
	if resource is Script:
		return resource as Script
	return null


static func reload_enrichment() -> void:
	_revision += 1
	_condition_definition_cache.clear()
	var extension := _optional_script(ENRICHMENT_SCRIPT_PATH)
	if extension != null:
		extension.call("reload_overlays")


static func enrichment_diagnostics() -> Array[String]:
	var output: Array[String] = []
	var extension := _optional_script(ENRICHMENT_SCRIPT_PATH)
	if extension == null:
		return output
	var messages: Variant = extension.get("diagnostics")
	if messages is Array:
		for raw: Variant in messages:
			output.append(String(raw))
	return output


static func enrich(category: String, definition: Dictionary) -> Dictionary:
	var extension := _optional_script(ENRICHMENT_SCRIPT_PATH)
	if extension == null:
		return definition.duplicate(true)
	var result: Variant = extension.call("apply_to", category, definition)
	if result is Dictionary:
		return result as Dictionary
	return definition.duplicate(true)


static func _load_native_package(package: Dictionary, path: String) -> void:
	var adapter := _optional_script(NATIVE_ADAPTER_PATH)
	if adapter == null:
		_diagnose("Homebrew 5etools: adattatore non disponibile: " + path)
		return
	var parsed: Variant = adapter.call("normalize", package, path)
	if not parsed is Dictionary:
		_diagnose("Homebrew 5etools: adattatore non valido: " + path)
		return
	var result: Dictionary = parsed
	for issue: Variant in result.get("diagnostics", []):
		_diagnose(String(issue))
	for value: Variant in result.get("entries", []):
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		var id: String = String(entry.get("id", ""))
		if id.is_empty():
			continue
		if _home.has(id):
			_diagnose("Homebrew: ID duplicato ignorato (vince il primo): " + id)
			continue
		_home[id] = entry


static func reload_homebrew(paths: Array[String] = ["res://homebrew", HOME_DIR]) -> void:
	_condition_definition_cache.clear()
	reload_enrichment()
	_home.clear()
	diagnostics.clear()
	_loaded = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(HOME_DIR))
	for path: String in paths:
		_load_directory(path, 0)

static func _load_directory(path: String, depth: int) -> void:
	if depth > 4:
		_diagnose("Homebrew: profondità massima superata: " + path)
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	var files := dir.get_files()
	files.sort()
	for filename: String in files:
		if filename.ends_with(".json") and not filename.ends_with(".schema.json"):
			_load_package(path.path_join(filename))
	var folders := dir.get_directories()
	folders.sort()
	for folder: String in folders:
		if folder not in ["examples", "templates"] and not folder.begins_with("."):
			_load_directory(path.path_join(folder), depth + 1)

static func _load_package(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		_diagnose("Homebrew: file illeggibile o troppo grande: " + path)
		return
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary:
		_diagnose("Homebrew: JSON non valido: " + path)
		return
	var package: Dictionary = parser.data
	if package.has("_meta") and not package.has("schema_version"):
		_load_native_package(package, path)
		return
	if package.get("schema_version") != 1 or not package.get("entries") is Array:
		_diagnose("Homebrew: schema non valido: " + path)
		return
	var package_namespace := String(package.get("namespace", ""))
	var namespace_regex := RegEx.new()
	namespace_regex.compile("^[a-z0-9][a-z0-9_-]{0,47}$")
	if namespace_regex.search(package_namespace) == null:
		_diagnose("Homebrew: package_namespace non valido: " + path)
		return
	for raw: Variant in package.entries:
		if not raw is Dictionary:
			_diagnose("Homebrew: voce non valida: " + path)
			continue
		var entry: Dictionary = (raw as Dictionary).duplicate(true)
		var category := String(entry.get("category", ""))
		var local_id := String(entry.get("id", ""))
		var id_regex := RegEx.new()
		id_regex.compile("^[a-z0-9][a-z0-9_-]{0,63}$")
		if category not in CATEGORIES or id_regex.search(local_id) == null or not entry.get("name") is String or String(entry.name).strip_edges().is_empty() or not entry.get("data") is Dictionary:
			_diagnose("Homebrew: voce incompleta: " + path + " / " + local_id)
			continue
		var id := "homebrew:%s:%s:%s" % [package_namespace, category, local_id]
		if _home.has(id):
			_diagnose("Homebrew: ID duplicato ignorato (vince il primo): " + id)
			continue
		var data: Dictionary = entry.data.duplicate(true)
		data["id"] = id
		data["name"] = entry.name
		data["category"] = category
		data["source"] = String(entry.get("source", package_namespace))
		data["origin"] = "homebrew"
		# Keep the asset folder so a custom item's image can be
		# stored beside the JSON file that defines it.
		data["asset_dir"] = path.get_base_dir()
		data["default_miniature_id"] = String(entry.get("default_miniature_id", data.get("default_miniature_id", "")))
		data["overrides"] = String(entry.get("overrides", ""))
		if category in EFFECT_CATEGORIES:
			data["icon_id"] = String(entry.get("icon_id", ""))
			data["icon"] = String(entry.get("icon", ""))
			if data.icon.length() > 16:
				data["icon"] = ""
		_home[id] = data

# Consumers may reuse merged catalogs until either content layer is reloaded.
static func revision() -> int:
	if not _loaded:
		reload_homebrew()
	if _revision_extension == null:
		_revision_extension = _optional_script(ENRICHMENT_SCRIPT_PATH)
	return _revision + (int(_revision_extension.call("revision")) if _revision_extension != null else 0)


static func home_entries(category: String) -> Array[Dictionary]:
	if not _loaded:
		reload_homebrew()
	var result: Array[Dictionary] = []
	for raw: Dictionary in _home.values():
		if String(raw.get("category", "")) == category:
			result.append(raw.duplicate(true))
	return result

static func stable_id(category: String, entry: Dictionary) -> String:
	return "5etools:%s:%s:%s" % [category, String(entry.get("source", "")).to_lower(), String(entry.get("name", "")).to_lower().uri_encode()]

static func merge(category: String, base: Array[Dictionary]) -> Array[Dictionary]:
	var indexed: Dictionary = {}
	for row: Dictionary in base:
		var entry := row.duplicate(true)
		if String(entry.get("id", "")).is_empty():
			entry["id"] = stable_id(category, entry)
		entry["origin"] = String(entry.get("origin", "5etools"))
		indexed[String(entry.id)] = entry
	# Base definitions must be indexed before local document overrides,
	# regardless of filesystem traversal order.
	var home_rows: Array[Dictionary] = home_entries(category)
	if category == "documents":
		home_rows.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return String(a.get("overrides", "")).is_empty() and not String(b.get("overrides", "")).is_empty()
		)
	for row: Dictionary in home_rows:
		var target := String(row.get("overrides", ""))
		if not target.is_empty():
			if not indexed.has(target):
				_diagnose("Homebrew: sostituzione non trovata: " + target)
				continue
			if String(indexed[target].get("category", category)) != category:
				_diagnose("Homebrew: categoria diversa per sostituzione: " + target)
				continue
			var replacement: Dictionary = indexed[target].duplicate(true)
			for key: Variant in row.keys():
				if key not in ["id", "icon", "icon_id"]:
					replacement[key] = row[key]
			# Existing IDs and icon associations are immutable for overrides.
			indexed[target] = replacement
		else:
			indexed[String(row.id)] = row
	var result: Array[Dictionary] = []
	for row: Dictionary in indexed.values():
		result.append(enrich(category, row))
	return result

static func _load_effects() -> void:
	if not _effects.is_empty():
		return
	var file := FileAccess.open("res://vtt/data/effects_5etools.json", FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary and parsed.get("entries") is Array:
		for row: Variant in parsed.entries:
			if row is Dictionary:
				_effects.append(row)

static func condition_definitions(edition: String = "2014") -> Array[Dictionary]:
	var rules_edition := "2024" if edition == "2024" else "2014"
	if _condition_definition_cache.has(rules_edition):
		# Never expose the cached dictionaries to UI consumers that may edit
		# an entry while selecting condition metadata.
		return (_condition_definition_cache[rules_edition] as Array).duplicate(true)
	_load_effects()
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for legacy: Dictionary in LEGACY_CONDITIONS:
		var row := legacy.duplicate(true)
		var versions: Array[Dictionary] = []
		for effect: Dictionary in _effects:
			var effect_id := String(effect.get("legacy_id", ""))
			# Historic tactical IDs are retained for existing saved tokens, but
			# only selections actually documented by 5etools appear in the UI.
			if (
				effect_id == String(row.id)
				or (String(row.id) == "concentrating"
					and String(effect.get("name", "")) == "Concentration")
				or (String(row.id) == "surprised"
					and String(effect.get("name", "")) == "Surprised")
			):
				versions.append(effect)
		if versions.is_empty():
			# Local VTT tactical markers must appear even without a 5etools rule.
			if String(row.id) == "helped":
				row["category"] = "conditions"
				row["edition"] = rules_edition
				row["entries"] = ["Marcatore tattico senza effetti automatici."]
				result.append(row)
				seen[String(row.id)] = true
			continue
		var matched := false
		for version: Dictionary in versions:
			if String(version.get("edition", "")) == rules_edition:
				row["entries"] = version.get("entries", [])
				row["source"] = version.get("source", "")
				row["edition"] = rules_edition
				row["category"] = String(version.get("category", "conditions"))
				matched = true
				break
		if not matched:
			continue
		row["versions"] = versions
		result.append(row)
		seen[String(row.id)] = true
	for effect: Dictionary in _effects:
		if (
			String(effect.get("edition", "")) != rules_edition
			or not String(effect.get("legacy_id", "")).is_empty()
			or String(effect.get("name", "")) in ["Concentration", "Surprised"]
		):
			continue
		var row := effect.duplicate(true)
		row["icon"] = "🦠" if row.get("category") == "diseases" else "•"
		row["official"] = true
		result.append(row)
	# Explicit homebrew additions remain selectable in their own categories.
	for category: String in EFFECT_CATEGORIES:
		result = merge(category, result) if category == "conditions" else _append_home_effects(result, category)
	for row: Dictionary in result:
		if String(row.get("icon", "")).is_empty():
			row["icon"] = icon_for(String(row.get("icon_id", "")))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")).nocasecmp_to(String(b.get("name", ""))) < 0
	)
	_condition_definition_cache[rules_edition] = result.duplicate(true)
	return result

static func _append_home_effects(base: Array[Dictionary], category: String) -> Array[Dictionary]:
	# Merge only this category so conditions retain their canonical IDs.
	var subset: Array[Dictionary] = []
	var others: Array[Dictionary] = []
	for row: Dictionary in base:
		if row.get("category") == category:
			subset.append(row)
		else:
			others.append(row)
	others.append_array(merge(category, subset))
	return others

static func icon_for(id: String) -> String:
	for row: Dictionary in LEGACY_CONDITIONS:
		if row.id == id:
			return String(row.icon)
	return "•"

static func valid_effect_id(id: String) -> bool:
	for row: Dictionary in LEGACY_CONDITIONS:
		if row.id == id:
			return true
	if id.length() > 220:
		return false
	var regex := RegEx.new()
	regex.compile("^(homebrew:[a-z0-9_-]+:(conditions|diseases|effects):[a-z0-9_-]+|5etools:(conditions|diseases|effects):[a-z0-9_-]+:[a-z0-9%_.~-]+)$")
	return regex.search(id) != null

static func description(entry: Dictionary) -> String:
	var lines: Array[String] = [String(entry.get("name", "")), "Fonte: " + String(entry.get("source", entry.get("origin", "VTT")))]
	_flatten(entry.get("entries", entry.get("description", [])), lines)
	if entry.get("versions") is Array:
		for version: Dictionary in entry.versions:
			lines.append("\n" + String(version.get("edition", "")) + " · " + String(version.get("source", "")))
			_flatten(version.get("entries", []), lines)
	var text := "\n".join(lines)
	var regex := RegEx.new()
	regex.compile("\\{@([A-Za-z0-9]+) ([^{}]+)\\}")
	for found: RegExMatch in regex.search_all(text):
		var parts := found.get_string(2).split("|")
		var visible: String = parts[2] if parts.size() > 2 and not parts[2].is_empty() else parts[0]
		text = text.replace(found.get_string(), visible)
	return text

static func _flatten(value: Variant, lines: Array[String]) -> void:
	if value is String:
		lines.append(value)
	elif value is Array:
		for item: Variant in value:
			_flatten(item, lines)
	elif value is Dictionary:
		if value.has("name"):
			lines.append(String(value.name))
		for key: String in ["entry", "entries", "items", "colLabels", "rows"]:
			if value.has(key):
				_flatten(value[key], lines)


static func _diagnose(message: String) -> void:
	if message not in diagnostics and diagnostics.size() < 200:
		diagnostics.append(message)
