extends Node
## Tactical map boundary shared with the authenticated PWA HTTP host.
## The old Android/iOS UDP polling and raw TCP action listener are retired.
## No local TCP/UDP socket is opened here.
signal data_changed(data: Dictionary)
signal status_changed(message: String)

const ACTIONS := ["place_token", "claim_free_token", "snapshot", "move_token", "set_condition", "battle_action", "hit_attack", "begin_spell", "target_spell", "cancel_spell", "finish_spell", "target_attack", "preview_spell", "spell_status", "set_appearance", "set_token_spell", "chat_send", "chat_poll"]

var _provider: Callable
var _action_provider: Callable

func source_name() -> String:
	return "board" if _provider.is_valid() else "offline"

func use_board(provider: Callable) -> void:
	_provider = provider
	data_changed.emit(get_map_data())

func serve(enabled: bool, session: String) -> Error:
	# Compatibility for BoardSync.listen(): the PWA host owns the HTTP listener.
	# No native client-facing UDP/TCP service is started.
	if enabled and (not _provider.is_valid() or session.strip_edges().is_empty()):
		return ERR_INVALID_PARAMETER
	return OK

func get_map_data() -> Dictionary:
	if not _provider.is_valid():
		return {}
	var value: Variant = _provider.call()
	return value.duplicate(true) if value is Dictionary else {}

func set_action_provider(provider: Callable) -> void:
	_action_provider = provider

func execute_web_action(action: String, payload: Dictionary) -> Dictionary:
	# Authentication and origin checks are enforced upstream in PwaHost.
	if not _provider.is_valid() or not _action_provider.is_valid() or action not in ACTIONS:
		return {"ok": false, "error": "Comando PWA non disponibile."}
	var value: Variant = await _action_provider.call(action, payload)
	return value if value is Dictionary else {"ok": false, "error": "Risposta non valida."}

static func valid_data(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1:
		return false
	if not value.get("tokens") is Array or not value.get("combat") is Dictionary:
		return false
	if value.tokens.size() > 512:
		return false
	if value.has("revision"):
		# Revision numbers must survive transport as integer-valued JSON numbers.
		var revision: Variant = value.revision
		if not (revision is int or revision is float) or not is_finite(float(revision)) or float(revision) < 0 or float(revision) != floorf(float(revision)):
			return false
	var ids: Dictionary = {}
	for row: Variant in value.tokens:
		if not row is Dictionary or not row.get("id") is String or not row.get("name") is String or not row.get("conditions") is Array:
			return false
		if row.id.is_empty() or row.id.length() > 120 or ids.has(row.id) or row.name.length() > 256 or row.conditions.size() > 64:
			return false
		if row.has("free") and not row.free is bool:
			return false
		if row.has("active_spell_ids"):
			if not row.active_spell_ids is Array or row.active_spell_ids.size() > 128:
				return false
			for spell_id: Variant in row.active_spell_ids:
				if not spell_id is String or spell_id.length() > 256:
					return false
		for field: String in ["current_miniature_id", "default_miniature_id"]:
			if row.has(field) and (not row[field] is String or row[field].length() > 256):
				return false
		ids[row.id] = true
		for condition: Variant in row.conditions:
			if not condition is String or condition.length() > 256:
				return false
	var combat: Dictionary = value.combat
	if not combat.get("active") is bool or not combat.get("entries") is Array:
		return false
	for key: String in ["round", "active_index"]:
		var number: Variant = combat.get(key)
		if not (number is int or number is float) or not is_finite(float(number)) or float(number) != floorf(float(number)):
			return false
	if combat.entries.size() > 512 or combat.round < 1 or combat.active_index < -1 or combat.active_index >= combat.entries.size():
		return false
	for row: Variant in combat.entries:
		if not row is Dictionary or not row.get("name") is String or not row.get("token_id") is String:
			return false
		if row.name.length() > 256 or row.token_id.length() > 120:
			return false
		var initiative: Variant = row.get("initiative")
		if not (initiative is int or initiative is float) or not is_finite(float(initiative)):
			return false
	return true

