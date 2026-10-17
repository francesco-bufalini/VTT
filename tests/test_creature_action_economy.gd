extends SceneTree

const Actions = preload("res://vtt/creature_action_economy_tab.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var old: Array[Dictionary] = Actions.entries({"rules_version": "2014"})
	var modern: Array[Dictionary] = Actions.entries({"rules_version": "2024"})
	assert(_contains(old, "Usare un oggetto", 0))
	assert(not _contains(old, "Studiare", 0))
	assert(_contains(modern, "Studiare", 0))
	assert(_contains(modern, "Influenzare", 0))
	assert(_contains(modern, "Muoversi", 3))
	assert(_contains(modern, "Attacco di opportunità", 4))
	# Non-attack monster options must not disappear just because they lack a hit roll.
	var monster: Dictionary = {
		"kind": "monster", "rules_version": "2014",
		"stat_block": {
			"action": [{"name": "Soffio", "entries": ["Cono di gelo."]}],
			"bonus": [{"name": "Comando", "entries": ["Ordina a un alleato."]}],
			"reaction": [{"name": "Parata", "entries": ["Riduce i danni."]}]
		}
	}
	var monster_actions: Array[Dictionary] = Actions.entries(monster)
	assert(_contains(monster_actions, "Soffio", 0))
	assert(_contains(monster_actions, "Comando", 1))
	assert(_contains(monster_actions, "Parata", 4))
	var typed: Dictionary = {
		"rules_version": "2014",
		"action_grants": [
			{"name": "Scatto speciale", "action_type": "bonus", "tracker_id": "charge"},
			{"name": "Risposta", "action_type": "reaction"}
		],
		"resource_trackers": [
			{"id": "charge", "name": "Cariche", "max": 3, "recharge": "long_rest"}
		]
	}
	var typed_actions: Array[Dictionary] = Actions.entries(typed)
	assert(_contains(typed_actions, "Scatto speciale", 1))
	assert(_contains(typed_actions, "Risposta", 4))
	for entry: Dictionary in typed_actions:
		if entry.get("name", "") == "Scatto speciale":
			assert(entry.get("tracker", "") == "Cariche")
	print("PASS: native action economy SRD, monsters and structured trackers")
	quit(0)

func _contains(rows: Array[Dictionary], name: String, timing: int) -> bool:
	for row: Dictionary in rows:
		if String(row.get("name", "")) == name and int(row.get("time", -1)) == timing:
			return true
	return false
