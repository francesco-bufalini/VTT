extends RefCounted

# Shared data normalization and local content overlays, never private sheets.
const HOME_DIR := "user://homebrew"
const CATEGORIES := ["monsters", "races", "classes", "spells", "conditions", "diseases", "effects", "class_features", "species_traits", "feats", "backgrounds", "optional_features"]
const EFFECT_CATEGORIES := ["conditions", "diseases", "effects"]
const MAX_FILE_BYTES := 2 * 1024 * 1024
const LEGACY_CONDITIONS := [
	# Le 15 condizioni ufficiali D&D 5e / SRD.
	{"id": "blinded", "name": "Accecato", "icon": "🙈", "official": true},
	{"id": "charmed", "name": "Affascinato", "icon": "💘", "official": true},
	{"id": "deafened", "name": "Assordato", "icon": "🔇", "official": true},
	{"id": "exhaustion", "name": "Sfinimento", "icon": "🥱", "official": true},
	{"id": "frightened", "name": "Spaventato", "icon": "😨", "official": true},
	{"id": "grappled", "name": "Afferrato", "icon": "🪢", "official": true},
	{"id": "incapacitated", "name": "Incapacitato", "icon": "⛔", "official": true},
	{"id": "invisible", "name": "Invisibile", "icon": "👻", "official": true},
	{"id": "paralyzed", "name": "Paralizzato", "icon": "🧊", "official": true},
	{"id": "petrified", "name": "Pietrificato", "icon": "🗿", "official": true},
	{"id": "poisoned", "name": "Avvelenato", "icon": "☠️", "official": true},
	{"id": "prone", "name": "Prono", "icon": "⬇️", "official": true},
	{"id": "restrained", "name": "Trattenuto", "icon": "⛓️", "official": true},
	{"id": "stunned", "name": "Stordito", "icon": "💫", "official": true},
	{"id": "unconscious", "name": "Privo di sensi", "icon": "😴", "official": true},

	# Marker tattici utili nel VTT. Non sono condizioni ufficiali SRD.
	{"id": "concentrating", "name": "Concentrazione", "icon": "🧠", "official": false},
	{"id": "surprised", "name": "Sorpreso", "icon": "❗", "official": false},
	{"id": "hidden", "name": "Nascosto", "icon": "🥷", "official": false},
	{"id": "dead", "name": "Morto", "icon": "💀", "official": false},

]

static var _home: Dictionary = {}
static var _loaded := false
static var diagnostics: Array[String] = []
static var _effects: Array[Dictionary] = []

static func reload_homebrew(paths: Array[String] = ["res://homebrew", HOME_DIR]) -> void:
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
		data["default_miniature_id"] = String(entry.get("default_miniature_id", data.get("default_miniature_id", "")))
		data["overrides"] = String(entry.get("overrides", ""))
		if category in EFFECT_CATEGORIES:
			data["icon_id"] = String(entry.get("icon_id", ""))
			data["icon"] = String(entry.get("icon", ""))
			if data.icon.length() > 16:
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
		result.append(row)
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
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for legacy: Dictionary in LEGACY_CONDITIONS:
		var row := legacy.duplicate(true)
		var versions: Array[Dictionary] = []
		for effect: Dictionary in _effects:
			if String(effect.get("legacy_id", "")) == String(row.id):
				versions.append(effect)
		row["versions"] = versions
		for version: Dictionary in versions:
			if String(version.get("edition", "")) == edition:
				row["entries"] = version.get("entries", [])
				row["source"] = version.get("source", "")
		row["category"] = "conditions" if bool(row.get("official", false)) else "effects"
		result.append(row)
		seen[String(row.id)] = true
	for effect: Dictionary in _effects:
		if String(effect.get("legacy_id", "")).is_empty():
			var row := effect.duplicate(true)
			row["icon"] = "🦠" if row.get("category") == "diseases" else "•"
			row["official"] = true
			result.append(row)
	for category: String in EFFECT_CATEGORIES:
		result = merge(category, result) if category == "conditions" else _append_home_effects(result, category)
	for row: Dictionary in result:
		if String(row.get("icon", "")).is_empty():
			row["icon"] = icon_for(String(row.get("icon_id", "")))
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
