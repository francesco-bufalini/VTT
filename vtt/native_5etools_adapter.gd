extends RefCounted

# Converts an upstream 5etools homebrew document to normalized catalog
# entries without modifying the document on disk. No creature state lives here.
const CATEGORIES := {
	"monster": "monsters",
	"spell": "spells",
	"item": "items",
	"document": "documents",
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


static func _slug(input: String, max_length: int) -> String:
	var regex := RegEx.new()
	regex.compile("[^a-z0-9_-]+")
	var value: String = regex.sub(input.strip_edges().to_lower(), "_", true)
	return value.trim_prefix("_").trim_suffix("_").substr(0, max_length)


static func normalize(document: Dictionary, path: String) -> Dictionary:
	var entries: Array[Dictionary] = []
	var diagnostics: Array[String] = []
	var metadata: Variant = document.get("_meta", {})
	if not metadata is Dictionary:
		diagnostics.append("Homebrew 5etools: _meta non valido: " + path)
		return {"entries": entries, "diagnostics": diagnostics}

	var defined_sources: Dictionary = {}
	var sources: Variant = metadata.get("sources", [])
	if sources is Array:
		for raw: Variant in sources:
			if raw is Dictionary:
				var source_id: String = String(raw.get("json", "")).strip_edges()
				if not source_id.is_empty():
					defined_sources[source_id] = true
	if defined_sources.is_empty():
		diagnostics.append("Homebrew 5etools: _meta.sources mancante: " + path)
		return {"entries": entries, "diagnostics": diagnostics}

	var fallback_source := ""
	if defined_sources.size() == 1:
		fallback_source = String(defined_sources.keys()[0])
	for native_category: String in CATEGORIES.keys():
		var raw_entries: Variant = document.get(native_category, [])
		if not raw_entries is Array:
			continue
		var category: String = String(CATEGORIES[native_category])
		for raw: Variant in raw_entries:
			if not raw is Dictionary:
				diagnostics.append("Homebrew 5etools: voce non valida: " + path)
				continue
			var data: Dictionary = raw.duplicate(true)
			var name: String = String(data.get("name", "")).strip_edges()
			var source: String = String(data.get("source", fallback_source)).strip_edges()
			if name.is_empty() or not defined_sources.has(source):
				diagnostics.append("Homebrew 5etools: nome/fonte non validi: " + path)
				continue
			var source_namespace: String = _slug(source, 48)
			var identifier := String(data.get("id", name)) if category == "documents" else name
			var local_id: String = _slug(identifier, 64)
			if source_namespace.is_empty() or local_id.is_empty():
				diagnostics.append("Homebrew 5etools: ID non valido: " + name)
				continue
			data["id"] = "homebrew:%s:%s:%s" % [source_namespace, category, local_id]
			data["source"] = source
			data["category"] = category
			data["origin"] = "homebrew"
			data["asset_dir"] = path.get_base_dir()
			if category in ["conditions", "diseases", "effects"]:
				if String(data.get("icon", "")).length() > 16:
					data["icon"] = ""
			entries.append(data)
	return {"entries": entries, "diagnostics": diagnostics}
