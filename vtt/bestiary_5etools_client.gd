extends Node

signal catalog_ready(entries: Array[Dictionary])
signal catalog_failed(message: String)
signal creature_ready(request_key: String, creature: Dictionary)
signal creature_failed(request_key: String, message: String)

const ContentCatalog = preload("res://vtt/content_catalog.gd")
const CACHE_DIR := "user://vtt_5etools_bestiary"
const SEARCH_CACHE := CACHE_DIR + "/search_index.json"
const SOURCE_CACHE := CACHE_DIR + "/source_index.json"

const OFFICIAL_BASE := "https://5e.tools/"
const MIRROR_BASE := (
	"https://raw.githubusercontent.com/5etools-mirror-3/"
	+ "5etools-src/main/"
)

var _http: HTTPRequest
var _queue: Array[Dictionary] = []
var _active: Dictionary = {}
var _source_files: Dictionary = {}
var _catalog: Array[Dictionary] = []
var _catalog_requested: bool = false
static var _detail_cache: Dictionary = {}


func setup() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(CACHE_DIR)
	)
	_http = HTTPRequest.new()
	_http.name = "BestiaryHttp"
	_http.timeout = 12.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func load_catalog(force_refresh: bool = false) -> void:
	if _http == null:
		setup()
	if not force_refresh and _load_catalog_from_cache():
		catalog_ready.emit(ContentCatalog.merge("monsters", _catalog))
		return

	_catalog_requested = true
	_queue.clear()
	_enqueue_json(
		"source_index",
		OFFICIAL_BASE + "data/bestiary/index.json",
		MIRROR_BASE + "data/bestiary/index.json",
		SOURCE_CACHE
	)
	_enqueue_json(
		"search_index",
		OFFICIAL_BASE + "search/index.json",
		MIRROR_BASE + "search/index.json",
		SEARCH_CACHE
	)
	_pump_queue()


func catalog() -> Array[Dictionary]:
	return ContentCatalog.merge("monsters", _catalog)


func request_creature(
	creature_name: String,
	source: String,
	request_key: String
) -> void:
	for row: Dictionary in ContentCatalog.merge("monsters", _catalog):
		if row.get("origin") == "homebrew" and String(row.get("name", "")).nocasecmp_to(creature_name) == 0 and String(row.get("source", "")).nocasecmp_to(source) == 0:
			creature_ready.emit(request_key, row.duplicate(true))
			return
	if _http == null:
		setup()

	if _source_files.is_empty():
		_load_source_index_cache()
	if _source_files.is_empty():
		_queue.push_back({
			"kind": "deferred_creature",
			"name": creature_name,
			"source": source,
			"request_key": request_key
		})
		_enqueue_json_front(
			"source_index",
			OFFICIAL_BASE + "data/bestiary/index.json",
			MIRROR_BASE + "data/bestiary/index.json",
			SOURCE_CACHE
		)
		_pump_queue()
		return

	_request_creature_now(creature_name, source, request_key)


func _request_creature_now(
	creature_name: String,
	source: String,
	request_key: String
) -> void:
	var filename: String = String(_source_files.get(source, "")).strip_edges()
	if filename.is_empty():
		creature_failed.emit(
			request_key,
			"Nessun file del bestiario trovato per la fonte %s." % source
		)
		return

	var cache_path := CACHE_DIR.path_join(filename)
	if FileAccess.file_exists(cache_path):
		var parsed: Variant = _read_json(cache_path)
		if parsed is Dictionary:
			var creature := _find_creature(
				parsed as Dictionary,
				creature_name,
				source
			)
			if not creature.is_empty():
				_deliver_or_resolve_copy(
					request_key,
					creature,
					parsed as Dictionary
				)
				return

	_queue.push_back({
		"kind": "creature_file",
		"url": OFFICIAL_BASE + "data/bestiary/" + filename,
		"fallback_url": MIRROR_BASE + "data/bestiary/" + filename,
		"cache_path": cache_path,
		"fallback_used": false,
		"name": creature_name,
		"source": source,
		"request_key": request_key
	})
	_pump_queue()


func _enqueue_json(
	kind: String,
	url: String,
	fallback_url: String,
	cache_path: String
) -> void:
	_queue.push_back({
		"kind": kind,
		"url": url,
		"fallback_url": fallback_url,
		"cache_path": cache_path,
		"fallback_used": false
	})


func _enqueue_json_front(
	kind: String,
	url: String,
	fallback_url: String,
	cache_path: String
) -> void:
	for queued: Dictionary in _queue:
		if String(queued.get("kind", "")) == kind:
			return
	_queue.push_front({
		"kind": kind,
		"url": url,
		"fallback_url": fallback_url,
		"cache_path": cache_path,
		"fallback_used": false
	})


func _pump_queue() -> void:
	if _http == null or not _active.is_empty():
		return

	while not _queue.is_empty():
		var next: Dictionary = _queue.pop_front()
		if String(next.get("kind", "")) == "deferred_creature":
			if _source_files.is_empty():
				_queue.push_front(next)
				return
			_request_creature_now(
				String(next.get("name", "")),
				String(next.get("source", "")),
				String(next.get("request_key", ""))
			)
			continue

		_active = next
		var error: Error = _http.request(String(_active.get("url", "")))
		if error == OK:
			return
		_retry_or_fail("Errore HTTP locale: %s" % error)
		if not _active.is_empty():
			return


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if _active.is_empty():
		return

	var success := (
		result == HTTPRequest.RESULT_SUCCESS
		and response_code >= 200
		and response_code < 300
	)
	if not success:
		_retry_or_fail(
			"HTTP %d (risultato %d)" % [response_code, result]
		)
		_pump_queue()
		return

	var text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		_retry_or_fail("Risposta JSON non valida.")
		_pump_queue()
		return

	var cache_path: String = String(_active.get("cache_path", ""))
	if not cache_path.is_empty():
		_write_text(cache_path, text)

	var task: Dictionary = _active
	_active = {}
	var kind: String = String(task.get("kind", ""))
	match kind:
		"source_index":
			_parse_source_index(parsed)
		"search_index":
			_parse_search_index(parsed)
		"creature_file":
			if parsed is Dictionary:
				var creature := _find_creature(
					parsed as Dictionary,
					String(task.get("name", "")),
					String(task.get("source", ""))
				)
				var request_key: String = String(
					task.get("request_key", "")
				)
				if creature.is_empty():
					creature_failed.emit(
						request_key,
						"Creatura non trovata nel bestiario."
					)
				else:
					_deliver_or_resolve_copy(
						request_key,
						creature,
						parsed as Dictionary
					)
		"copy_base_file":
			var copy_request_key := String(task.get("request_key", ""))
			var child_value: Variant = task.get("child", {})
			if parsed is Dictionary and child_value is Dictionary:
				var base := _find_creature(
					parsed as Dictionary,
					String(task.get("base_name", "")),
					String(task.get("base_source", ""))
				)
				if not base.is_empty():
					_deliver_enriched(
						copy_request_key,
						_merge_copy_creature(
							base,
							child_value as Dictionary
						)
					)
				else:
					_deliver_enriched(
						copy_request_key,
						(child_value as Dictionary).duplicate(true)
					)
		"creature_detail":
			var detailed: Dictionary = task.get("creature", {})
			if parsed is Dictionary:
				_apply_details(detailed, parsed, String(task.get("detail_kind", "")))
			_deliver_enriched(String(task.get("request_key", "")), detailed, int(task.get("stage", 0)) + 1)

	_finish_catalog_if_ready()
	_pump_queue()


func _retry_or_fail(message: String) -> void:
	var task: Dictionary = _active
	if task.is_empty():
		return

	if (
		not bool(task.get("fallback_used", false))
		and not String(task.get("fallback_url", "")).is_empty()
	):
		task["fallback_used"] = true
		task["url"] = String(task.get("fallback_url", ""))
		_active = {}
		_queue.push_front(task)
		return

	var kind: String = String(task.get("kind", ""))
	var request_key: String = String(task.get("request_key", ""))
	_active = {}

	if kind == "creature_detail":
		# Lore is optional offline; never discard the usable stat block.
		_deliver_enriched(request_key, task.get("creature", {}), int(task.get("stage", 0)) + 1)
	elif kind in ["creature_file", "copy_base_file"]:
		creature_failed.emit(request_key, message)
	elif kind in ["source_index", "search_index"]:
		if _load_catalog_from_cache():
			_catalog_requested = false
			catalog_ready.emit(ContentCatalog.merge("monsters", _catalog))
			_queue.clear()
		else:
			_catalog_requested = false
			catalog_failed.emit(
				"Impossibile caricare il bestiario: " + message
			)
			_queue.clear()


func _deliver_or_resolve_copy(
	request_key: String,
	creature: Dictionary,
	source_root: Dictionary
) -> void:
	var copy_value: Variant = creature.get("_copy", {})
	if not copy_value is Dictionary:
		_deliver_enriched(request_key, creature)
		return

	var copy_data: Dictionary = copy_value as Dictionary
	var base_name := String(copy_data.get("name", "")).strip_edges()
	var base_source := String(copy_data.get("source", "")).strip_edges()
	if base_name.is_empty() or base_source.is_empty():
		_deliver_enriched(request_key, creature)
		return

	var base := _find_creature(source_root, base_name, base_source)
	if base.is_empty():
		var filename := String(_source_files.get(base_source, "")).strip_edges()
		if not filename.is_empty():
			var cache_path := CACHE_DIR.path_join(filename)
			if FileAccess.file_exists(cache_path):
				var cached_value: Variant = _read_json(cache_path)
				if cached_value is Dictionary:
					base = _find_creature(
						cached_value as Dictionary,
						base_name,
						base_source
					)
			if base.is_empty():
				_queue.push_front({
					"kind": "copy_base_file",
					"url": OFFICIAL_BASE + "data/bestiary/" + filename,
					"fallback_url": (
						MIRROR_BASE + "data/bestiary/" + filename
					),
					"cache_path": cache_path,
					"fallback_used": false,
					"request_key": request_key,
					"base_name": base_name,
					"base_source": base_source,
					"child": creature.duplicate(true)
				})
				_pump_queue()
				return

	if base.is_empty():
		_deliver_enriched(request_key, creature)
		return

	_deliver_enriched(
		request_key,
		_merge_copy_creature(base, creature)
	)


func _deliver_enriched(request_key: String, creature: Dictionary, stage: int = 0) -> void:
	var filename: String = ""
	var detail_kind: String = ""
	if stage == 0:
		var source_file: String = String(_source_files.get(creature.get("source", ""), ""))
		if not creature.has("fluff") and not source_file.is_empty():
			filename = "fluff-" + source_file
			detail_kind = "fluff"
	elif stage == 1 and creature.has("legendaryGroup"):
		filename = "legendarygroups.json"
		detail_kind = "legendary"
	else:
		creature_ready.emit(request_key, creature)
		return
	if filename.is_empty():
		_deliver_enriched(request_key, creature, stage + 1)
		return
	var cache_path: String = CACHE_DIR.path_join(filename)
	if FileAccess.file_exists(cache_path):
		var cached: Variant = _read_json(cache_path)
		if cached is Dictionary:
			_apply_details(creature, cached, detail_kind)
			_deliver_enriched(request_key, creature, stage + 1)
			return
	_queue.push_front({"kind": "creature_detail", "detail_kind": detail_kind,
		"url": OFFICIAL_BASE + "data/bestiary/" + filename,
		"fallback_url": MIRROR_BASE + "data/bestiary/" + filename,
		"cache_path": cache_path, "fallback_used": false, "request_key": request_key,
		"creature": creature, "stage": stage})
	_pump_queue()


static func _resolve_fluff(root: Dictionary, name: String, source: String, seen: Array[String] = []) -> Array:
	var key: String = source.to_lower() + "|" + name.to_lower()
	if key in seen:
		return []
	var visited: Array[String] = seen.duplicate()
	visited.append(key)
	for row: Variant in root.get("monsterFluff", []):
		if not row is Dictionary or String(row.get("name", "")).nocasecmp_to(name) != 0 or String(row.get("source", "")).nocasecmp_to(source) != 0:
			continue
		var result: Array = row.get("entries", []).duplicate(true)
		var copy: Dictionary = row.get("_copy", {})
		if not copy.is_empty():
			result = _resolve_fluff(root, String(copy.get("name", "")), String(copy.get("source", source)), visited) + result
		return result
	return []


static func _apply_details(creature: Dictionary, root: Dictionary, kind: String) -> void:
	if kind == "fluff" and not creature.has("fluff"):
		var entries: Array = _resolve_fluff(root, String(creature.get("name", "")), String(creature.get("source", "")))
		if not entries.is_empty():
			creature["fluff"] = {"entries": entries}
	elif kind == "legendary":
		var reference: Dictionary = creature.get("legendaryGroup", {})
		for row: Variant in root.get("legendaryGroup", []):
			if row is Dictionary and row.get("name", "") == reference.get("name", "") and row.get("source", "") == reference.get("source", ""):
				var resolved: Dictionary = row.duplicate(true)
				var copy: Dictionary = row.get("_copy", {})
				for base: Variant in root.get("legendaryGroup", []):
					if base is Dictionary and base.get("name", "") == copy.get("name", "") and base.get("source", "") == copy.get("source", ""):
						for field: String in ["lairActions", "regionalEffects"]:
							if not resolved.has(field) and base.has(field):
								resolved[field] = base[field]
				for field: String in ["lairActions", "regionalEffects"]:
					if not creature.has(field) and resolved.has(field):
						creature[field] = resolved[field].duplicate(true)
				return


static func enrich_cached(creature: Dictionary) -> Dictionary:
	var enriched: Dictionary = creature.duplicate(true)
	var index: Dictionary = _cached_detail_json(SOURCE_CACHE)
	if index is Dictionary:
		var filename: String = String(index.get(enriched.get("source", ""), ""))
		for detail: Dictionary in [{"file": "fluff-" + filename, "kind": "fluff"}, {"file": "legendarygroups.json", "kind": "legendary"}]:
			var path: String = CACHE_DIR.path_join(String(detail.file))
			if FileAccess.file_exists(path):
				var root: Dictionary = _cached_detail_json(path)
				if not root.is_empty():
					_apply_details(enriched, root, String(detail.kind))
	return enriched


static func _cached_detail_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var modified: int = FileAccess.get_modified_time(path)
	if _detail_cache.has(path) and int(_detail_cache[path].modified) == modified:
		return _detail_cache[path].root
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	if _detail_cache.size() >= 8:
		_detail_cache.clear()
	_detail_cache[path] = {"modified": modified, "root": parsed}
	return parsed


func _merge_copy_creature(
	base: Dictionary,
	child: Dictionary
) -> Dictionary:
	var merged := base.duplicate(true)
	for key: Variant in child.keys():
		if String(key) == "_copy":
			continue
		merged[key] = child[key]
	# Manteniamo il blocco _copy: le eventuali _mod avanzate di 5eTools
	# restano visibili nella scheda anche quando non sono trasformate qui.
	merged["_copy"] = child.get("_copy", {}).duplicate(true)
	return merged


func _load_catalog_from_cache() -> bool:
	_load_source_index_cache()
	if _source_files.is_empty() or not FileAccess.file_exists(SEARCH_CACHE):
		return false
	var search_value: Variant = _read_json(SEARCH_CACHE)
	if search_value == null:
		return false
	_parse_search_index(search_value)
	return not _catalog.is_empty()


func _load_source_index_cache() -> void:
	if not FileAccess.file_exists(SOURCE_CACHE):
		return
	var source_value: Variant = _read_json(SOURCE_CACHE)
	if source_value != null:
		_parse_source_index(source_value)


func _parse_source_index(value: Variant) -> void:
	if not value is Dictionary:
		return
	_source_files.clear()
	for source_value: Variant in (value as Dictionary).keys():
		var source := String(source_value)
		var filename := String((value as Dictionary).get(source_value, ""))
		if not source.is_empty() and not filename.is_empty():
			_source_files[source] = filename


func _parse_search_index(value: Variant) -> void:
	if not value is Dictionary:
		return
	var root: Dictionary = value as Dictionary
	var rows_value: Variant = root.get("x", [])
	if not rows_value is Array:
		return

	var source_by_id: Dictionary = {}
	var meta_value: Variant = root.get("m", {})
	if meta_value is Dictionary:
		var source_meta_value: Variant = (
			(meta_value as Dictionary).get("s", {})
		)
		if source_meta_value is Dictionary:
			for source_value: Variant in (
				source_meta_value as Dictionary
			).keys():
				var meta_id: Variant = (
					(source_meta_value as Dictionary).get(source_value)
				)
				source_by_id[int(meta_id)] = String(source_value)

	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for row_value: Variant in (rows_value as Array):
		if not row_value is Dictionary:
			continue
		var row: Dictionary = row_value as Dictionary
		if int(row.get("c", -1)) != 1:
			continue
		var entry_name: String = String(row.get("n", "")).strip_edges()
		if entry_name.is_empty():
			continue

		var source_variant: Variant = row.get("s", "")
		var source := ""
		if source_variant is String:
			source = String(source_variant)
		else:
			source = String(source_by_id.get(int(source_variant), ""))
		if source.is_empty():
			continue

		var key := entry_name.to_lower() + "|" + source.to_lower()
		if seen.has(key):
			continue
		seen[key] = true
		result.append({
			"name": entry_name,
			"source": source,
			"page": int(row.get("p", 0)),
			"hash": String(row.get("u", ""))
		})

	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var name_cmp := String(a.get("name", "")).naturalnocasecmp_to(
				String(b.get("name", ""))
			)
			if name_cmp == 0:
				return String(a.get("source", "")) < String(
					b.get("source", "")
				)
			return name_cmp < 0
	)
	_catalog = result


func _finish_catalog_if_ready() -> void:
	if not _catalog_requested:
		return
	if _source_files.is_empty() or _catalog.is_empty():
		return
	_catalog_requested = false
	catalog_ready.emit(ContentCatalog.merge("monsters", _catalog))


func _find_creature(
	root: Dictionary,
	creature_name: String,
	source: String
) -> Dictionary:
	var monsters_value: Variant = root.get("monster", [])
	if not monsters_value is Array:
		return {}
	for monster_value: Variant in (monsters_value as Array):
		if not monster_value is Dictionary:
			continue
		var monster: Dictionary = monster_value as Dictionary
		if (
			String(monster.get("name", "")).nocasecmp_to(creature_name) == 0
			and String(monster.get("source", "")).nocasecmp_to(source) == 0
		):
			return monster.duplicate(true)
	return {}


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	return JSON.parse_string(text)


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()
