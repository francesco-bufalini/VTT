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
	if kind == "monster":
		var monsters: Array[Dictionary] = _monsters.list_creatures()
		var normalized: Dictionary = _monsters.normalize_creature(record)
		_upsert(monsters, normalized)
		return _monsters.save_creatures(monsters)
	if kind == "character":
		var characters: Array[Dictionary] = _characters.list_characters()
		var normalized: Dictionary = _characters.normalize_character(record)
		_sync_player_slots(normalized)
		_upsert(characters, normalized)
		return _characters.save_characters(characters)
	return ERR_INVALID_PARAMETER


func relinquish(record: Dictionary, new_owner: String) -> Dictionary:
	# The transfer is a code, not a multiplayer board snapshot: other
	# participants never receive the private sheet from automatic map sync.
	if not CreatureOwner.is_owner(record):
		return {}
	var target := new_owner.strip_edges()
	if target.length() < 16 or target == CreatureOwner.local_id():
		return {}
	var transferred := record.duplicate(true)
	transferred["owner_id"] = target
	var record_kind := String(transferred.get("kind", ""))
	var error: Error = ERR_INVALID_DATA
	# Save through the originating store: permissions now belong to another
	# user, so save() intentionally refuses this write.
	if record_kind == "monster":
		var monsters: Array[Dictionary] = _monsters.list_creatures()
		_upsert(monsters, _monsters.normalize_creature(transferred))
		error = _monsters.save_creatures(monsters)
	elif record_kind == "character":
		var characters: Array[Dictionary] = _characters.list_characters()
		_upsert(characters, _characters.normalize_character(transferred))
		error = _characters.save_characters(characters)
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
	return save(record)


func _upsert(collection: Array[Dictionary], entry: Dictionary) -> void:
	var id := String(entry.get("id", ""))
	for index: int in range(collection.size()):
		if String(collection[index].get("id", "")) == id:
			collection[index] = entry.duplicate(true)
			return
	collection.append(entry.duplicate(true))


func _sync_player_slots(record: Dictionary) -> void:
	var totals: Array = record.get("spell_slots_total", []).duplicate(true)
	var spent: Array = record.get("spell_slots_spent", []).duplicate(true)
	while totals.size() < 10:
		totals.append(0)
	while spent.size() < 10:
		spent.append(0)
	for raw: Variant in record.get("trackers", []):
		if not raw is Dictionary:
			continue
		var tracker: Dictionary = raw as Dictionary
		var id := String(tracker.get("id", ""))
		if not id.begins_with("slot_"):
			continue
		var level := int(id.trim_prefix("slot_"))
		if level < 1 or level > 9:
			continue
		var maximum := maxi(0, int(tracker.get("maximum", 0)))
		var current := clampi(int(tracker.get("current", 0)), 0, maximum)
		totals[level] = maximum
		spent[level] = maximum - current
	record["spell_slots_total"] = totals
	record["spell_slots_spent"] = spent
