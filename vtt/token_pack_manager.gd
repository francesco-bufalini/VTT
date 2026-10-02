extends Node

signal catalog_updated(entries: Array[Dictionary])
signal catalog_refresh_failed(message: String)
signal token_downloaded(token_id: String, cache_path: String)
signal token_download_failed(token_id: String, message: String)

const CACHE_DIR := "user://token_cache"
const CATALOG_CACHE_PATH := CACHE_DIR + "/token_catalog.json"

# Public HTTP is always attempted first. This URL can later be replaced with
# R2/B2/a public GitHub Release without changing the manager API.
const DEFAULT_CATALOG_URL := (
	"https://github.com/francesco-bufalini/VTT/releases/download/"
	+ "token-packs-test-001/token_catalog.json"
)

# Development-only fallback while the GitHub repository is private.
const GITHUB_REPOSITORY := "francesco-bufalini/VTT"
const GITHUB_RELEASE_TAG := "token-packs-test-001"
const CATALOG_FILENAME := "token_catalog.json"
const STARTUP_DOWNLOAD_TEST_ID := "ape"

var catalog_url: String = DEFAULT_CATALOG_URL
var _catalog: Dictionary = {}
var _entries_by_id: Dictionary = {}
var _request: HTTPRequest
var _download_request: HTTPRequest
var _download_token_id: String = ""
var _download_target_path: String = ""


func _ready() -> void:
	_ensure_cache_dir()
	var had_cached_catalog := _load_cached_catalog()
	if had_cached_catalog:
		print(
			"TokenPackManager: cached catalog loaded (%d tokens)"
			% _entries_by_id.size()
		)

	_request = HTTPRequest.new()
	_request.name = "CatalogRequest"
	add_child(_request)
	_request.request_completed.connect(_on_catalog_request_completed)

	_download_request = HTTPRequest.new()
	_download_request.name = "TokenDownloadRequest"
	add_child(_download_request)
	_download_request.request_completed.connect(_on_token_download_completed)

	call_deferred("_refresh_catalog_on_start")


func _refresh_catalog_on_start() -> void:
	print("TokenPackManager: refreshing remote catalog...")
	var error := refresh_catalog()
	if error != OK:
		var message := "Could not start catalog refresh: %s" % error_string(error)
		push_warning("TokenPackManager: %s" % message)
		catalog_refresh_failed.emit(message)


func configure_catalog_url(url: String) -> void:
	var cleaned := url.strip_edges()
	if not cleaned.is_empty():
		catalog_url = cleaned


func refresh_catalog() -> Error:
	if _request == null:
		return ERR_UNCONFIGURED
	if _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return ERR_BUSY
	if catalog_url.is_empty():
		return ERR_INVALID_PARAMETER

	# Deliberately unauthenticated: the final distribution is expected to be
	# public. A private-repository gh fallback is attempted only on failure.
	var headers := PackedStringArray([
		"Accept: application/json",
		"User-Agent: VTT-token-pack-manager",
	])
	return _request.request(
		catalog_url,
		headers,
		HTTPClient.METHOD_GET
	)


func download_token(token_id: String) -> Error:
	var id := token_id.strip_edges()
	if id.is_empty():
		return ERR_INVALID_PARAMETER
	if not _entries_by_id.has(id):
		return ERR_DOES_NOT_EXIST
	if _download_request == null:
		return ERR_UNCONFIGURED
	if not _download_token_id.is_empty():
		return ERR_BUSY

	var entry := get_entry(id)
	var expected_sha := String(entry.get("sha256", "")).strip_edges().to_lower()
	if expected_sha.is_empty():
		return ERR_INVALID_DATA

	var target_path := cache_path_for(id)
	if FileAccess.file_exists(target_path):
		if _verify_cached_pck(id, expected_sha):
			print("TokenPackManager: %s.pck already cached and SHA-256 valid." % id)
			token_downloaded.emit(id, target_path)
			return OK
		_remove_cached_file(target_path)

	var url := _download_url_for(entry)
	if url.is_empty():
		# With a private GitHub repository the HTTP URL may be absent from older
		# catalogs. Go directly to the authenticated development fallback.
		if _download_token_via_gh(id, entry):
			return OK
		return ERR_CANT_RESOLVE

	_download_token_id = id
	_download_target_path = target_path
	_download_request.download_file = target_path
	print("TokenPackManager: downloading %s.pck via HTTP..." % id)
	var headers := PackedStringArray([
		"Accept: application/octet-stream",
		"User-Agent: VTT-token-pack-manager",
	])
	var error := _download_request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		_download_request.download_file = ""
		_download_token_id = ""
		_download_target_path = ""
	return error


func _download_url_for(entry: Dictionary) -> String:
	var explicit := String(entry.get("release_download_url", "")).strip_edges()
	if not explicit.is_empty():
		return explicit

	var pck := String(entry.get("pck", "")).strip_edges()
	var release_tag := String(entry.get("release_tag", "")).strip_edges()
	if pck.is_empty():
		return ""
	if release_tag.is_empty():
		release_tag = GITHUB_RELEASE_TAG
	return (
		"https://github.com/%s/releases/download/%s/%s"
		% [GITHUB_REPOSITORY, release_tag, pck]
	)


func _verify_cached_pck(token_id: String, expected_sha: String) -> bool:
	var path := cache_path_for(token_id)
	if not FileAccess.file_exists(path):
		return false
	var actual_sha := FileAccess.get_sha256(path).to_lower()
	if actual_sha == expected_sha.to_lower():
		return true
	push_warning(
		"TokenPackManager: SHA-256 mismatch for %s.pck (expected %s, got %s)"
		% [token_id, expected_sha, actual_sha]
	)
	return false


func _remove_cached_file(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute)


func _on_token_download_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	_body: PackedByteArray
) -> void:
	var id := _download_token_id
	var target_path := _download_target_path
	_download_request.download_file = ""
	_download_token_id = ""
	_download_target_path = ""

	if id.is_empty():
		return

	var entry := get_entry(id)
	var expected_sha := String(entry.get("sha256", "")).strip_edges().to_lower()
	if (
		result == HTTPRequest.RESULT_SUCCESS
		and response_code >= 200
		and response_code < 300
		and FileAccess.file_exists(target_path)
		and _verify_cached_pck(id, expected_sha)
	):
		print("TokenPackManager: %s.pck downloaded via HTTP and SHA-256 verified." % id)
		token_downloaded.emit(id, target_path)
		return

	_remove_cached_file(target_path)
	print(
		"TokenPackManager: HTTP download for %s.pck unavailable "
		+ "(result=%d code=%d), trying gh fallback..."
		% [id, result, response_code]
	)
	if _download_token_via_gh(id, entry):
		return

	var message := (
		"Download failed for %s.pck (HTTP result=%d code=%d) and gh fallback failed."
		% [id, result, response_code]
	)
	push_warning("TokenPackManager: %s" % message)
	token_download_failed.emit(id, message)


func _download_token_via_gh(token_id: String, entry: Dictionary) -> bool:
	var gh_path := _find_gh()
	if gh_path.is_empty():
		return false

	var pck_name := String(entry.get("pck", "%s.pck" % token_id)).strip_edges()
	if pck_name.is_empty():
		pck_name = "%s.pck" % token_id
	var release_tag := String(entry.get("release_tag", "")).strip_edges()
	if release_tag.is_empty():
		release_tag = GITHUB_RELEASE_TAG

	var cache_absolute := ProjectSettings.globalize_path(CACHE_DIR)
	var output: Array = []
	var exit_code := OS.execute(
		gh_path,
		PackedStringArray([
			"release",
			"download",
			release_tag,
			"--repo",
			GITHUB_REPOSITORY,
			"--pattern",
			pck_name,
			"--dir",
			cache_absolute,
			"--clobber",
		]),
		output,
		true,
		false
	)
	if exit_code != 0:
		push_warning(
			"TokenPackManager: gh download failed for %s (exit %d): %s"
			% [token_id, exit_code, "\n".join(output)]
		)
		return false

	var expected_sha := String(entry.get("sha256", "")).strip_edges().to_lower()
	if expected_sha.is_empty() or not _verify_cached_pck(token_id, expected_sha):
		_remove_cached_file(cache_path_for(token_id))
		return false

	print(
		"TokenPackManager: %s.pck downloaded via gh fallback and SHA-256 verified."
		% token_id
	)
	token_downloaded.emit(token_id, cache_path_for(token_id))
	return true


func _run_startup_download_test() -> void:
	if not has_token(STARTUP_DOWNLOAD_TEST_ID):
		push_warning(
			"TokenPackManager: startup test token '%s' is absent from catalog."
			% STARTUP_DOWNLOAD_TEST_ID
		)
		return
	var error := download_token(STARTUP_DOWNLOAD_TEST_ID)
	if error != OK:
		push_warning(
			"TokenPackManager: could not start %s.pck test download: %s"
			% [STARTUP_DOWNLOAD_TEST_ID, error_string(error)]
		)


func get_catalog() -> Dictionary:
	return _catalog.duplicate(true)


func get_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for value: Variant in _entries_by_id.values():
		if value is Dictionary:
			out.append((value as Dictionary).duplicate(true))
	out.sort_custom(_sort_entries)
	return out


func get_entry(token_id: String) -> Dictionary:
	var value: Variant = _entries_by_id.get(token_id, {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func has_token(token_id: String) -> bool:
	return _entries_by_id.has(token_id)


func cache_path_for(token_id: String) -> String:
	return CACHE_DIR.path_join("%s.pck" % token_id)


func is_downloaded(token_id: String) -> bool:
	if token_id.is_empty():
		return false
	return FileAccess.file_exists(cache_path_for(token_id))


func downloaded_token_ids() -> Array[String]:
	var result: Array[String] = []
	for token_id: Variant in _entries_by_id.keys():
		var id := String(token_id)
		if is_downloaded(id):
			result.append(id)
	result.sort()
	return result


func _ensure_cache_dir() -> Error:
	var absolute := ProjectSettings.globalize_path(CACHE_DIR)
	if DirAccess.dir_exists_absolute(absolute):
		return OK
	return DirAccess.make_dir_recursive_absolute(absolute)


func _load_cached_catalog() -> bool:
	if not FileAccess.file_exists(CATALOG_CACHE_PATH):
		return false
	var file := FileAccess.open(CATALOG_CACHE_PATH, FileAccess.READ)
	if file == null:
		return false
	var raw := file.get_as_text()
	file.close()
	return _accept_catalog_text(raw, false)


func _save_catalog_cache(raw: String) -> Error:
	var directory_error := _ensure_cache_dir()
	if directory_error != OK:
		return directory_error
	var file := FileAccess.open(CATALOG_CACHE_PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(raw)
	var error := file.get_error()
	file.close()
	return error


func _accept_catalog_text(raw: String, persist: bool) -> bool:
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		return false

	var catalog := parsed as Dictionary
	var tokens_value: Variant = catalog.get("tokens", [])
	if not tokens_value is Array:
		return false

	var entries: Dictionary = {}
	for value: Variant in tokens_value:
		if not value is Dictionary:
			continue
		var entry := value as Dictionary
		var token_id := String(entry.get("id", "")).strip_edges()
		if token_id.is_empty():
			continue
		entries[token_id] = entry.duplicate(true)

	_catalog = catalog.duplicate(true)
	_entries_by_id = entries

	if persist:
		var cache_error := _save_catalog_cache(raw)
		if cache_error != OK:
			push_warning(
				"TokenPackManager: catalog loaded but cache write failed: %s"
				% error_string(cache_error)
			)

	catalog_updated.emit(get_entries())
	return true


func _on_catalog_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if (
		result == HTTPRequest.RESULT_SUCCESS
		and response_code >= 200
		and response_code < 300
	):
		var raw := body.get_string_from_utf8()
		if _accept_catalog_text(raw, true):
			print(
				"TokenPackManager: catalog loaded via HTTP (%d tokens)"
				% _entries_by_id.size()
			)
			call_deferred("_run_startup_download_test")
			return
		push_warning("TokenPackManager: HTTP catalog JSON is invalid.")

	print(
		"TokenPackManager: HTTP catalog unavailable (result=%d code=%d), "
		+ "trying gh fallback..."
		% [result, response_code]
	)

	# Current private-repository development fallback. This path is not required
	# once the catalog URL is publicly downloadable.
	if _refresh_catalog_via_gh():
		return

	var message := (
		"Catalog refresh failed (HTTP result=%d code=%d) and gh fallback "
		+ "was unavailable or failed."
	) % [result, response_code]
	push_warning("TokenPackManager: %s" % message)
	catalog_refresh_failed.emit(message)


func _refresh_catalog_via_gh() -> bool:
	var gh_path := _find_gh()
	if gh_path.is_empty():
		return false

	var cache_absolute := ProjectSettings.globalize_path(CACHE_DIR)
	var output: Array = []
	var exit_code := OS.execute(
		gh_path,
		PackedStringArray([
			"release",
			"download",
			GITHUB_RELEASE_TAG,
			"--repo",
			GITHUB_REPOSITORY,
			"--pattern",
			CATALOG_FILENAME,
			"--dir",
			cache_absolute,
			"--clobber",
		]),
		output,
		true,
		false
	)
	if exit_code != 0:
		push_warning(
			"TokenPackManager: gh fallback failed (exit %d): %s"
			% [exit_code, "\n".join(output)]
		)
		return false

	if not _load_cached_catalog():
		push_warning(
			"TokenPackManager: gh downloaded the catalog but it is invalid."
		)
		return false

	print(
		"TokenPackManager: catalog loaded via gh fallback (%d tokens)"
		% _entries_by_id.size()
	)
	call_deferred("_run_startup_download_test")
	return true


func _find_gh() -> String:
	# Windows commonly resolves gh.exe through PATH. OS.execute can use the
	# command name directly; where.exe is used only to avoid spawning an
	# obviously missing command and to support installations outside defaults.
	if OS.get_name() == "Windows":
		var output: Array = []
		var code := OS.execute(
			"where",
			PackedStringArray(["gh"]),
			output,
			true,
			false
		)
		if code == 0 and not output.is_empty():
			var lines := String(output[0]).split("\n", false)
			if not lines.is_empty():
				return String(lines[0]).strip_edges()
	else:
		var output: Array = []
		var code := OS.execute(
			"which",
			PackedStringArray(["gh"]),
			output,
			true,
			false
		)
		if code == 0 and not output.is_empty():
			return String(output[0]).strip_edges()
	return ""


func _sort_entries(a: Dictionary, b: Dictionary) -> bool:
	return (
		String(a.get("name", a.get("id", ""))).nocasecmp_to(
			String(b.get("name", b.get("id", "")))
		) < 0
	)
