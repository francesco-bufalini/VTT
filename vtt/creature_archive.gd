extends RefCounted

# One creature-facing API for every user and creature origin. The two legacy
# files remain storage adapters so existing characters/monsters are not lost.
const CharacterStore = preload("res://vtt/player_character_store.gd")
const MonsterStore = preload("res://vtt/master_creature_store.gd")
const CreatureOwner = preload("res://vtt/creature_owner.gd")
const CreatureRules = preload("res://vtt/creature_rules.gd")

var _characters
var _monsters


func setup(campaign_manager: Node) -> void:
	_characters = CharacterStore.new()
	_characters.setup(campaign_manager)
	_monsters = MonsterStore.new()
	_monsters.setup(campaign_manager)


func list_owned() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in _characters.list_characters():
		var row := item.duplicate(true)
		row["kind"] = "character"
		result.append(row)
	for item: Dictionary in _monsters.list_creatures():
		var row := item.duplicate(true)
		row["kind"] = "monster"
		result.append(row)
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("name", "")).naturalnocasecmp_to(
				String(b.get("name", ""))
			) < 0
	)
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
	if not CreatureOwner.is_owner(record):
		return ERR_UNAUTHORIZED
	var kind := String(record.get("kind", ""))
	var id := String(record.get("id", "")).strip_edges()
	if id.is_empty():
		return ERR_INVALID_PARAMETER
	var persisted := _stored(kind, id)
	if not persisted.is_empty() and not CreatureOwner.is_owner(persisted):
		return ERR_UNAUTHORIZED
	if kind == "monster":
		var monsters: Array[Dictionary] = _monsters.list_creatures()
		var normalized: Dictionary = _monsters.normalize_creature(record)
		_upsert(monsters, normalized)
		return _monsters.save_creatures(monsters)
	if kind == "character":
		var characters: Array[Dictionary] = _characters.list_characters()
		var normalized: Dictionary = _characters.normalize_character(record)
		_upsert(characters, normalized)
		return _characters.save_characters(characters)
	return ERR_INVALID_PARAMETER


func delete(record: Dictionary) -> Error:
	# Delete only the locally owned sheet. Source bestiary entries are immutable.
	var kind := String(record.get("kind", ""))
	var id := String(record.get("id", "")).strip_edges()
	if id.is_empty() or kind not in ["character", "monster"]:
		return ERR_INVALID_PARAMETER
	if not CreatureOwner.is_owner(record):
		return ERR_UNAUTHORIZED
	var persisted := _stored(kind, id)
	if persisted.is_empty():
		return ERR_DOES_NOT_EXIST
	if not CreatureOwner.is_owner(persisted):
		return ERR_UNAUTHORIZED
	if kind == "monster":
		var monsters: Array[Dictionary] = _monsters.list_creatures()
		for index: int in range(monsters.size()):
			if String(monsters[index].get("id", "")) == id:
				monsters.remove_at(index)
				return _monsters.save_creatures(monsters)
	else:
		var characters: Array[Dictionary] = _characters.list_characters()
		for index: int in range(characters.size()):
			if String(characters[index].get("id", "")) == id:
				characters.remove_at(index)
				return _characters.save_characters(characters)
	return ERR_DOES_NOT_EXIST


func relinquish(record: Dictionary, new_owner: String) -> Dictionary:
	# The transfer is a code, not a multiplayer board snapshot: other
	# participants never receive the private sheet from automatic map sync.
	if not CreatureOwner.is_owner(record):
		return {}
	var target := new_owner.strip_edges()
	if target.length() < 16 or target == CreatureOwner.local_id():
		return {}
	var transferred := record.duplicate(true)
	var persisted := _stored(String(record.get("kind", "")), String(record.get("id", "")))
	if persisted.is_empty() or not CreatureOwner.is_owner(persisted):
		return {}
	transferred["owner_id"] = target
	transferred["transfer_revision"] = int(persisted.get("transfer_revision", 0)) + 1
	var record_kind := String(transferred.get("kind", ""))
	var error: Error = ERR_INVALID_DATA
	# Save through the originating store: permissions now belong to another
	# user, so save() intentionally refuses this write.
	if record_kind == "monster":
		var monsters: Array[Dictionary] = _monsters.list_creatures()
		_upsert(monsters, _monsters.normalize_creature(transferred))
		error = _monsters.save_creatures(monsters, true)
	elif record_kind == "character":
		var characters: Array[Dictionary] = _characters.list_characters()
		_upsert(characters, _characters.normalize_character(transferred))
		error = _characters.save_characters(characters, true)
	if error != OK:
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
	var record: Dictionary = raw as Dictionary
	if String(record.get("owner_id", "")) != CreatureOwner.local_id():
		return ERR_UNAUTHORIZED
	var kind := String(record.get("kind", ""))
	var id := String(record.get("id", ""))
	if id.is_empty() or kind not in ["monster", "character"]:
		return ERR_INVALID_DATA
	var persisted := _stored(kind, id)
	if not persisted.is_empty() and int(record.get("transfer_revision", 0)) <= int(persisted.get("transfer_revision", 0)):
		return ERR_ALREADY_EXISTS
	if kind == "monster":
		var records: Array[Dictionary] = _monsters.list_creatures()
		_upsert(records, _monsters.normalize_creature(record))
		return _monsters.save_creatures(records, true)
	var records: Array[Dictionary] = _characters.list_characters()
	_upsert(records, _characters.normalize_character(record))
	return _characters.save_characters(records, true)


func _stored(kind: String, id: String) -> Dictionary:
	var rows: Array[Dictionary] = _monsters.list_creatures(true) if kind == "monster" else _characters.list_characters(true)
	for row: Dictionary in rows:
		if String(row.get("id", "")) == id:
			return row
	return {}


func _upsert(collection: Array[Dictionary], entry: Dictionary) -> void:
	var id := String(entry.get("id", ""))
	for index: int in range(collection.size()):
		if String(collection[index].get("id", "")) == id:
			collection[index] = entry.duplicate(true)
			return
	collection.append(entry.duplicate(true))
