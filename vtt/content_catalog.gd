extends RefCounted

# Optional VTT extensions are loaded when needed, rather than preloaded into
# every compendium consumer. Source definitions remain usable independently.
const ENRICHMENT_SCRIPT_PATH := "res://vtt/content_enrichment.gd"
const ENRICHMENT_USER_DIR := "user://vtt_enrichment"

static var _enrichment_script: Script


static func _extension() -> Script:
	if _enrichment_script != null:
		return _enrichment_script
	var resource: Resource = load(ENRICHMENT_SCRIPT_PATH)
	if resource is Script:
		_enrichment_script = resource as Script
	return _enrichment_script


static func reload_enrichment() -> void:
	var script: Script = _extension()
	if script != null:
		script.call("reload")


static func enrichment_diagnostics() -> Array[String]:
	var result: Array[String] = []
	var script: Script = _extension()
	if script != null:
		var raw: Variant = script.get("diagnostics")
		if raw is Array:
			for item: Variant in raw:
				result.append(String(item))
	return result


static func enrich(category: String, definition: Dictionary) -> Dictionary:
	var script: Script = _extension()
	if script == null:
		return definition.duplicate(true)
	var value: Variant = script.call("apply_to", category, definition)
	return value as Dictionary if value is Dictionary else definition.duplicate(true)

# Shared data normalization and local content overlays, never private sheets.
const HOME_DIR := "user://homebrew"
const CATEGORIES := ["items", "subclasses", "subclass_features", "monsters", "races", "classes", "spells", "conditions", "diseases", "effects", "class_features", "species_traits", "feats", "backgrounds", "optional_features"]
const EFFECT_CATEGORIES := ["conditions", "diseases", "effects"]
const MAX_FILE_BYTES := 2 * 1024 * 1024
# Native 5etools homebrew packages keep their _meta.sources and category
# arrays intact on disk. Adapt them at the catalog boundary only.
const NATIVE_CATEGORIES = {
	"monster": "monsters",
	"spell": "spells",
	"item": "items",
	"baseitem": "items",
	"magicvariant": "items",
	"class": "classes",
	"subclass": "subclasses",
	"subclassFeature": "subclass_features",
	"classFeature": "class_features",
	"race": "races",
	"raceFeature": "species_traits",
	"feat": "feats",
	"background": "backgrounds",
	"optionalfeature": "optional_features",
	"condition": "conditions",
	"disease": "diseases"
}


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
	{"id": "dead", "name": "Dead", "icon": "💀", "official": false},

]

static var _home: Dictionary = {}
static var _loaded := false
static var diagnostics: Array[String] = []
static var _effects: Array[Dictionary] = []

static func reload_homebrew(paths: Array[String] = ["res://homebrew", HOME_DIR]) -> void:
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

static func _native_slug(value: String, max_length: int) -> String:
	var regex := RegEx.new()
	regex.compile("[^a-z0-9_-]+")
	var slug: String = regex.sub(value.to_lower().strip_edges(), "_", true)
	return slug.trim_prefix("_").trim_suffix("_").substr(0, max_length)


static func _load_native_package(package: Dictionary, path: String) -> void:
	var metadata: Variant = package.get("_meta", {})
	if not metadata is Dictionary:
		_diagnose("Homebrew 5etools: _meta non valido: " + path)
		return
	var defined_sources: Dictionary = {}
	var sources: Variant = (metadata as Dictionary).get("sources", [])
	if sources is Array:
		for value: Variant in sources:
			if value is Dictionary:
				var code: String = String((value as Dictionary).get("json", "")).strip_edges()
				if not code.is_empty():
					defined_sources[code] = true
	if defined_sources.is_empty():
		_diagnose("Homebrew 5etools: _meta.sources mancante: " + path)
		return
	var fallback_source: String = String(defined_sources.keys()[0]) if defined_sources.size() == 1 else ""
	for native_category: String in NATIVE_CATEGORIES.keys():
		var entries: Variant = package.get(native_category, [])
		if not entries is Array:
			continue
		var category: String = NATIVE_CATEGORIES[native_category]
		for value: Variant in entries:
			if not value is Dictionary:
				_diagnose("Homebrew 5etools: voce non valida: " + path)
				continue
			var data: Dictionary = (value as Dictionary).duplicate(true)
			var name: String = String(data.get("name", "")).strip_edges()
			var source: String = String(data.get("source", fallback_source)).strip_edges()
			if name.is_empty() or source.is_empty() or not defined_sources.has(source):
				_diagnose("Homebrew 5etools: nome/fonte non validi: " + path)
				continue
			var namespace: String = _native_slug(source, 48)
			var local_id: String = _native_slug(name, 64)
			if namespace.is_empty() or local_id.is_empty():
				_diagnose("Homebrew 5etools: impossibile creare ID: " + name)
				continue
			var id: String = "homebrew:%s:%s:%s" % [namespace, category, local_id]
			if _home.has(id):
				_diagnose("Homebrew: ID duplicato ignorato (vince il primo): " + id)
				continue
			data["id"] = id
			data["source"] = source
			data["category"] = category
			data["origin"] = "homebrew"
			data["asset_dir"] = path.get_base_dir()
			if category in EFFECT_CATEGORIES and String(data.get("icon", "")).length() > 16:
				data["icon"] = ""
			_home[id] = data


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
	for row: Dictionary in home_entries(category):
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
	_load_effects()
	var rules_edition := "2024" if edition == "2024" else "2014"
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
