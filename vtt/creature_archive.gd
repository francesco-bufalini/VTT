extends RefCounted

# One creature-facing API for all locally stored characters and monsters.
# Embedded scene definitions use a separate read-only hook.
const CharacterStore = preload("res://vtt/player_character_store.gd")
const MonsterStore = preload("res://vtt/master_creature_store.gd")
const Storage = preload("res://vtt/creature_local_storage.gd")
const CreatureOwner = preload("res://vtt/creature_owner.gd")
const PortableContent = preload("res://vtt/portable_creature_content.gd")

var _characters
var _monsters
var _storage


func setup(_campaign_manager: Node = null) -> void:
	# Campaign selection never changes the creature collection.
	_characters = CharacterStore.new()
	_monsters = MonsterStore.new()
	_storage = Storage.new()


func list_owned() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw: Dictionary in _storage.list_records():
		if not CreatureOwner.is_owner(raw):
			continue
		result.append(_normalize(raw))
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("name", "")).naturalnocasecmp_to(
				String(b.get("name", ""))
			) < 0
	)
	return result


# Scene authors may expose get_embedded_creature_records() on their scene root.
# This never persists to user://, joins the private player archive or
# automatically displays anything to connected players. It is opt-in.
func scene_records_from(scene_root: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if scene_root == null or not is_instance_valid(scene_root):
		return result
	if not scene_root.has_method("get_embedded_creature_records"):
		return result
	var raw_records: Variant = scene_root.call("get_embedded_creature_records")
	if not raw_records is Array:
		return result
	for raw: Variant in raw_records:
		if not raw is Dictionary:
			continue
		var kind := String((raw as Dictionary).get("kind", ""))
		if kind not in ["character", "monster"]:
			continue
		var record: Dictionary = _normalize(raw as Dictionary)
		record["_storage_origin"] = "scene"
		result.append(record)
	return result


func _normalize(record: Dictionary) -> Dictionary:
	var result: Dictionary = (
		_monsters.normalize_creature(record)
		if String(record.get("kind", "")) == "monster"
		else _characters.normalize_character(record)
	)
	result["kind"] = String(record.get("kind", ""))
	for key: String in ["variants", "current_form_id", "variant_schema_version"]:
		if record.has(key):
			result[key] = record[key].duplicate(true) if record[key] is Array or record[key] is Dictionary else record[key]
	return result


func create_character() -> Dictionary:
	var record: Dictionary = _characters.create_character()
	record["kind"] = "character"
	return record


func create_monster(stat: Dictionary, side: String = "ally") -> Dictionary:
	var record: Dictionary = _monsters.create_creature(stat, side)
	record["kind"] = "monster"
	return record


func save(record: Dictionary) -> Error:
	if String(record.get("_storage_origin", "")) == "scene":
		# Embedded sheets belong to the scene author, not the device archive.
		return ERR_UNAUTHORIZED
	if not CreatureOwner.is_owner(record):
		return ERR_UNAUTHORIZED
	if String(record.get("kind", "")) not in ["character", "monster"]:
		return ERR_INVALID_PARAMETER
	if String(record.get("id", "")).strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	return _storage.upsert(_normalize(record))


func update_owned_many(records: Array[Dictionary]) -> Error:
	var normalized: Array[Dictionary] = []
	for record: Dictionary in records:
		if String(record.get("_storage_origin", "")) == "scene" or not CreatureOwner.is_owner(record): return ERR_UNAUTHORIZED
		if String(record.get("kind", "")) not in ["character", "monster"]: return ERR_INVALID_PARAMETER
		normalized.append(_normalize(record))
	return _storage.update_owned_many(normalized)


# Undo/redo only edit existing locally owned sheets; never transfer ownership.
func undo_owned(record: Dictionary) -> Error:
	if String(record.get("_storage_origin", "")) == "scene":
		return ERR_UNAUTHORIZED
	return _storage.undo_owned(record)


func redo_owned(record: Dictionary) -> Error:
	if String(record.get("_storage_origin", "")) == "scene":
		return ERR_UNAUTHORIZED
	return _storage.undo_owned(record, true)


func delete(record: Dictionary) -> Error:
	if String(record.get("_storage_origin", "")) == "scene":
		return ERR_UNAUTHORIZED
	return _storage.delete_record(record)


func relinquish(record: Dictionary, new_owner: String) -> Dictionary:
	if not CreatureOwner.is_owner(record) or String(record.get("_storage_origin", "")) == "scene":
		return {}
	var target := new_owner.strip_edges()
	if target.length() < 16 or target == CreatureOwner.local_id():
		return {}
	var persisted := _stored(String(record.get("kind", "")), String(record.get("id", "")))
	if persisted.is_empty() or not CreatureOwner.can_edit(record, persisted):
		return {}
	var transferred := record.duplicate(true)
	transferred["owner_id"] = target
	transferred["transfer_revision"] = int(persisted.get("transfer_revision", 0)) + 1
	# This intentional ownership transfer bypasses normal local-owner checks.
	if _storage.upsert(_normalize(transferred), true) != OK:
		return {}
	return {
		"format": "vtt_creature_transfer_v1",
		"recipient": target,
		"creature": transferred
	}


func import_transfer(payload: Dictionary) -> Error:
	if String(payload.get("format", "")) != "vtt_creature_transfer_v1":
		return ERR_INVALID_DATA
	if String(payload.get("recipient", "")) != CreatureOwner.local_id():
		return ERR_UNAUTHORIZED
	var raw: Variant = payload.get("creature", {})
	if not raw is Dictionary:
		return ERR_INVALID_DATA
	var record: Dictionary = raw
	if String(record.get("owner_id", "")) != CreatureOwner.local_id():
		return ERR_UNAUTHORIZED
	var kind := String(record.get("kind", ""))
	var id := String(record.get("id", ""))
	if id.is_empty() or kind not in ["monster", "character"]:
		return ERR_INVALID_DATA
	var persisted := _stored(kind, id)
	if not persisted.is_empty() and int(record.get("transfer_revision", 0)) <= int(persisted.get("transfer_revision", 0)):
		return ERR_ALREADY_EXISTS
	return _storage.upsert(_normalize(record), true)


func _stored(kind: String, id: String) -> Dictionary:
	for row: Dictionary in _storage.list_records(kind):
		if String(row.get("id", "")) == id:
			return _normalize(row)
	return {}


# A batch is a collection of the existing portable single-creature envelopes.
# Validate every member before mutating the local archive, then import each
# as an independently owned copy (matching desktop single-sheet semantics).
func import_export_batch(payload: Dictionary) -> Error:
	if payload.get("format") != "vtt_creature_batch_export_v1" or payload.get("version") != 1:
		return ERR_INVALID_DATA
	var entries: Variant = payload.get("entries", [])
	if not entries is Array or entries.is_empty() or entries.size() > 200:
		return ERR_INVALID_DATA
	for item: Variant in entries:
		if not item is Dictionary:
			return ERR_INVALID_DATA
		var value: Dictionary = item as Dictionary
		if value.get("format") != "vtt_creature_export_v1" or value.get("version") != 1:
			return ERR_INVALID_DATA
		if not value.get("creature") is Dictionary:
			return ERR_INVALID_DATA
		var creature: Dictionary = value.creature
		if String(creature.get("name", "")).is_empty() or creature.get("kind") not in ["character", "monster"]:
			return ERR_INVALID_DATA
	for item: Variant in entries:
		var result := import_export_copy(item as Dictionary)
		if result != OK:
			return result
	return OK


# Portable exports create an independent local copy, never an ownership transfer.
func import_export_copy(payload: Dictionary) -> Error:
	if payload.get("format") != "vtt_creature_export_v1" or payload.get("version") != 1 or not payload.get("creature") is Dictionary:
		return ERR_INVALID_DATA
	var record: Dictionary = payload.creature.duplicate(true)
	if record.get("kind") not in ["character", "monster"] or String(record.get("name", "")).strip_edges().is_empty():
		return ERR_INVALID_DATA
	var content_error: Error = PortableContent.install(payload.get("homebrew_content", null))
	if content_error != OK:
		return content_error
	record["id"] = "import_" + Crypto.new().generate_random_bytes(16).hex_encode()
	record["owner_id"] = CreatureOwner.local_id()
	record["transfer_revision"] = 0
	record["linked_token_sync_id"] = ""
	return save(record)


# The base stays canonical on disk. Only presentation/game consumers resolve the
# current form; public token polling writes back to the section's actual owner.
static func resolve_form(record: Dictionary) -> Dictionary:
	var result := record.duplicate(true)
	for form: Dictionary in record.get("variants", []):
		if String(form.get("id", "")) != String(record.get("current_form_id", "")):
			continue
		_merge_form_values(result, form.get("values", {}), "*" in form.get("sections", []))
		break
	return result

static func _merge_form_values(target: Dictionary, values: Dictionary, replace_objects: bool = false, protect_identity: bool = true) -> void:
	for key: String in values:
		if protect_identity and key in ["id", "owner_id", "kind", "transfer_revision", "linked_token_sync_id", "linked_token_name", "variants", "current_form_id", "variant_schema_version"]:
			continue
		if not replace_objects and values[key] is Dictionary and target.get(key) is Dictionary:
			_merge_form_values(target[key], values[key], false, false)
		else:
			target[key] = values[key].duplicate(true) if values[key] is Dictionary or values[key] is Array else values[key]

static func apply_public_form_patch(record: Dictionary, patch: Dictionary) -> Dictionary:
	var result := record.duplicate(true)
	var active: Dictionary = {}
	for form: Dictionary in result.get("variants", []):
		if String(form.get("id", "")) == String(result.get("current_form_id", "")):
			active = form
			break
	for key: String in patch:
		var section := "conditions" if key in ["conditions", "concentrating_spell_id"] else "name" if key == "name" else "appearance" if key in ["current_miniature_id", "default_miniature_id", "size_name", "footprint", "visual_front_quarter_turns"] else ""
		var sections: Array = active.get("sections", [])
		var destination: Dictionary = active.get("values", {}) if "*" in sections or section in sections else result
		destination[key] = patch[key].duplicate(true) if patch[key] is Array or patch[key] is Dictionary else patch[key]
	return result
