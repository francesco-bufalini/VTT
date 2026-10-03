extends Node

signal catalog_ready(entries: Array[Dictionary])
signal catalog_failed(message: String)
signal creature_ready(request_key: String, creature: Dictionary)
signal creature_failed(request_key: String, message: String)

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


func setup() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(CACHE_DIR)
	)
	_http = HTTPRequest.new()
	_http.name = "BestiaryHttp"
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func load_catalog(force_refresh: bool = false) -> void:
	if _http == null:
		setup()
	if not force_refresh and _load_catalog_from_cache():
		catalog_ready.emit(_catalog.duplicate(true))
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
	return _catalog.duplicate(true)


func request_creature(
	creature_name: String,
	source: String,
	request_key: String
) -> void:
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
			"Nessun file 5eTools trovato per la fonte %s." % source
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
				creature_ready.emit(request_key, creature)
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
						"Creatura non trovata nel file 5eTools."
					)
				else:
					creature_ready.emit(request_key, creature)

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

	if kind == "creature_file":
		creature_failed.emit(request_key, message)
	elif kind in ["source_index", "search_index"]:
		if _load_catalog_from_cache():
			_catalog_requested = false
			catalog_ready.emit(_catalog.duplicate(true))
			_queue.clear()
		else:
			_catalog_requested = false
			catalog_failed.emit(
				"Impossibile caricare il bestiario 5eTools: " + message
			)
			_queue.clear()


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
	for row_value: Variant in rows_value as Array:
		if not row_value is Dictionary:
			continue
		var row: Dictionary = row_value as Dictionary
		if int(row.get("c", -1)) != 1:
			continue
		var name: String = String(row.get("n", "")).strip_edges()
		if name.is_empty():
			continue

		var source_variant: Variant = row.get("s", "")
		var source := ""
		if source_variant is String:
			source = String(source_variant)
		else:
			source = String(source_by_id.get(int(source_variant), ""))
		if source.is_empty():
			continue

		var key := name.to_lower() + "|" + source.to_lower()
		if seen.has(key):
			continue
		seen[key] = true
		result.append({
			"name": name,
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
	catalog_ready.emit(_catalog.duplicate(true))


func _find_creature(
	root: Dictionary,
	creature_name: String,
	source: String
) -> Dictionary:
	var monsters_value: Variant = root.get("monster", [])
	if not monsters_value is Array:
		return {}
	for monster_value: Variant in monsters_value as Array:
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
