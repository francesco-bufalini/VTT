extends Node

signal catalog_updated(entries: Array[Dictionary])
signal catalog_refresh_failed(message: String)
signal token_downloaded(token_id: String, cache_path: String)
signal token_download_failed(token_id: String, message: String)
signal token_mounted(token_id: String, scene_path: String)
signal token_mount_failed(token_id: String, message: String)

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

var catalog_url: String = DEFAULT_CATALOG_URL
var _catalog: Dictionary = {}
var _entries_by_id: Dictionary = {}
var _request: HTTPRequest
var _download_request: HTTPRequest
var _download_token_id: String = ""
var _download_target_path: String = ""
var _mounted_token_ids: Dictionary = {}
var _validated_cache_sha: Dictionary = {}


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
	# Headless validation/builds use local data and must not invoke HTTP or gh.
	if DisplayServer.get_name() == "headless":
		return
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


func mount_token(token_id: String) -> Error:
	var id := token_id.strip_edges()
	if id.is_empty():
		return ERR_INVALID_PARAMETER
	if not _entries_by_id.has(id):
		return ERR_DOES_NOT_EXIST
	# is_downloaded() also validates the current catalog SHA and removes stale
	# cache files. This prevents an outdated PCK from reaching mount logic.
	if not is_downloaded(id):
		return ERR_FILE_NOT_FOUND
	var entry := get_entry(id)
	return _mount_token_pack(
		id,
		entry,
		cache_path_for(id),
		true
	)


func mount_local_token(
	token_id: String,
	entry: Dictionary,
	pck_path: String
) -> Error:
	var id := token_id.strip_edges()
	if id.is_empty() or pck_path.strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	return _mount_token_pack(id, entry, pck_path, true)


func _mount_token_pack(
	token_id: String,
	entry: Dictionary,
	pck_path: String,
	verify_sha: bool
) -> Error:
	if bool(_mounted_token_ids.get(token_id, false)):
		return OK

	if not FileAccess.file_exists(pck_path):
		return ERR_FILE_NOT_FOUND

	var expected_sha := String(entry.get("sha256", "")).strip_edges().to_lower()
	if verify_sha and not expected_sha.is_empty():
		var actual_sha := FileAccess.get_sha256(pck_path).to_lower()
		if actual_sha != expected_sha:
			push_warning(
				"TokenPackManager: SHA-256 mismatch for %s (expected %s, got %s)"
				% [pck_path, expected_sha, actual_sha]
			)
			return ERR_FILE_CORRUPT

	var absolute_pck := ProjectSettings.globalize_path(pck_path)
	if not ProjectSettings.load_resource_pack(absolute_pck, false):
		return ERR_CANT_OPEN

	var scene_path := String(entry.get("scene", "")).strip_edges()
	if scene_path.is_empty():
		scene_path = (
			"res://remote_tokens/%s/%s_token.tscn"
			% [token_id, token_id]
		)

	var packed := ResourceLoader.load(
		scene_path,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	if packed == null:
		var message := "PCK mounted but scene is not loadable: %s" % scene_path
		push_warning("TokenPackManager: %s" % message)
		token_mount_failed.emit(token_id, message)
		return ERR_CANT_OPEN

	var instance := packed.instantiate()
	if not instance is Node3D:
		if instance != null:
			instance.free()
		var message := "Remote scene did not instantiate a Node3D: %s" % scene_path
		push_warning("TokenPackManager: %s" % message)
		token_mount_failed.emit(token_id, message)
		return ERR_INVALID_DATA

	var token := instance as Node3D
	var behaves_as_token := (
		token.has_method("configure")
		and token.has_method("set_visual_asset")
		and token.has_method("get_visual_asset_path")
	)
	token.free()
	if not behaves_as_token:
		var message := (
			"Remote scene does not inherit expected token behavior: %s"
			% scene_path
		)
		push_warning("TokenPackManager: %s" % message)
		token_mount_failed.emit(token_id, message)
		return ERR_INVALID_DATA

	_mounted_token_ids[token_id] = true
	print(
		"TokenPackManager: %s mounted; scene load/instantiate OK: %s"
		% [pck_path, scene_path]
	)
	token_mounted.emit(token_id, scene_path)
	return OK


func is_mounted(token_id: String) -> bool:
	return bool(_mounted_token_ids.get(token_id, false))


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
		_validated_cache_sha[token_id] = expected_sha.to_lower()
		return true
	_validated_cache_sha.erase(token_id)
	print(
		"TokenPackManager: cached %s.pck is stale (expected %s, got %s)."
		% [token_id, expected_sha, actual_sha]
	)
	return false


func _remove_cached_file(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	_validated_cache_sha.erase(path.get_file().get_basename())
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
		(
			"TokenPackManager: HTTP download for %s.pck unavailable "
			+ "(result=%d code=%d), trying gh fallback..."
		) % [id, result, response_code]
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
	var id := token_id.strip_edges()
	if id.is_empty() or not _entries_by_id.has(id):
		return false

	var path := cache_path_for(id)
	if not FileAccess.file_exists(path):
		_validated_cache_sha.erase(id)
		return false

	var entry := get_entry(id)
	var expected_sha := String(entry.get("sha256", "")).strip_edges().to_lower()
	if expected_sha.is_empty():
		_validated_cache_sha.erase(id)
		return false

	if String(_validated_cache_sha.get(id, "")) == expected_sha:
		return true

	var actual_sha := FileAccess.get_sha256(path).to_lower()
	if actual_sha != expected_sha:
		print(
			(
				"TokenPackManager: removing stale cached %s.pck "
				+ "(catalog SHA changed)."
			) % id
		)
		_remove_cached_file(path)
		_validated_cache_sha.erase(id)
		return false

	_validated_cache_sha[id] = expected_sha
	return true


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
	_validated_cache_sha.clear()

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
			return
		push_warning("TokenPackManager: HTTP catalog JSON is invalid.")

	print(
		(
			"TokenPackManager: HTTP catalog unavailable (result=%d code=%d), "
			+ "trying gh fallback..."
		) % [result, response_code]
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

	# While the repository is private, discover every release that publishes a
	# token_catalog.json and merge them into one runtime catalog. This mirrors
	# the future public setup where a single global catalog can point at PCKs
	# spread across multiple releases.
	var release_output: Array = []
	var release_exit := OS.execute(
		gh_path,
		PackedStringArray([
			"release",
			"list",
			"--repo",
			GITHUB_REPOSITORY,
			"--limit",
			"100",
			"--json",
			"tagName,isDraft",
		]),
		release_output,
		true,
		false
	)
	if release_exit != 0 or release_output.is_empty():
		push_warning(
			"TokenPackManager: gh release discovery failed (exit %d): %s"
			% [release_exit, "\n".join(release_output)]
		)
		return false

	var releases_value: Variant = JSON.parse_string(String(release_output[0]))
	if not releases_value is Array:
		push_warning("TokenPackManager: gh release list returned invalid JSON.")
		return false

	var sources_root := CACHE_DIR.path_join(".catalog_sources")
	var sources_absolute := ProjectSettings.globalize_path(sources_root)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(sources_absolute)
	if mkdir_error != OK and not DirAccess.dir_exists_absolute(sources_absolute):
		push_warning(
			"TokenPackManager: cannot create catalog source cache: %s"
			% error_string(mkdir_error)
		)
		return false

	var merged_entries: Dictionary = {}
	var catalogs_loaded := 0
	var releases_checked := 0

	for release_value: Variant in releases_value as Array:
		if not release_value is Dictionary:
			continue
		var release := release_value as Dictionary
		if bool(release.get("isDraft", false)):
			continue
		var tag := String(release.get("tagName", "")).strip_edges()
		if tag.is_empty():
			continue
		releases_checked += 1

		var safe_tag := tag.replace("/", "_").replace("\\", "_")
		safe_tag = safe_tag.replace(":", "_")
		var source_dir := sources_root.path_join(safe_tag)
		var source_absolute := ProjectSettings.globalize_path(source_dir)
		DirAccess.make_dir_recursive_absolute(source_absolute)

		var download_output: Array = []
		var download_exit := OS.execute(
			gh_path,
			PackedStringArray([
				"release",
				"download",
				tag,
				"--repo",
				GITHUB_REPOSITORY,
				"--pattern",
				CATALOG_FILENAME,
				"--dir",
				source_absolute,
				"--clobber",
			]),
			download_output,
			true,
			false
		)
		if download_exit != 0:
			# A release is allowed to contain only PCK assets. It simply does
			# not contribute metadata until a catalog is published there.
			continue

		var source_path := source_dir.path_join(CATALOG_FILENAME)
		if not FileAccess.file_exists(source_path):
			continue
		var source_file := FileAccess.open(source_path, FileAccess.READ)
		if source_file == null:
			continue
		var source_raw := source_file.get_as_text()
		source_file.close()
		var source_parsed: Variant = JSON.parse_string(source_raw)
		if not source_parsed is Dictionary:
			continue
		var source_tokens: Variant = (source_parsed as Dictionary).get(
			"tokens",
			[]
		)
		if not source_tokens is Array:
			continue

		catalogs_loaded += 1
		for token_value: Variant in source_tokens as Array:
			if not token_value is Dictionary:
				continue
			var entry := (token_value as Dictionary).duplicate(true)
			var token_id := String(entry.get("id", "")).strip_edges()
			if token_id.is_empty():
				continue

			# Prefer the first occurrence from gh's newest-first release list.
			# A catalog entry that already names its actual release keeps that
			# tag; otherwise the catalog's own release is the source.
			if merged_entries.has(token_id):
				continue
			if String(entry.get("release_tag", "")).strip_edges().is_empty():
				entry["release_tag"] = tag
			merged_entries[token_id] = entry

	if catalogs_loaded == 0 or merged_entries.is_empty():
		push_warning(
			"TokenPackManager: no token catalogs found across %d releases."
			% releases_checked
		)
		return false

	var merged_tokens: Array = []
	for entry_value: Variant in merged_entries.values():
		if entry_value is Dictionary:
			merged_tokens.append(entry_value)
	merged_tokens.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("id", "")).nocasecmp_to(
				String(b.get("id", ""))
			) < 0
	)

	var merged_catalog := {
		"version": 1,
		"tokens": merged_tokens,
	}
	var merged_raw := JSON.stringify(merged_catalog, "\t")
	if not _accept_catalog_text(merged_raw, true):
		push_warning("TokenPackManager: merged gh catalog is invalid.")
		return false

	print(
		(
			"TokenPackManager: catalog loaded via gh fallback "
			+ "(%d catalogs, %d tokens)"
		) % [catalogs_loaded, _entries_by_id.size()]
	)
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
