extends SceneTree

const Actions = preload("res://vtt/creature_action_economy_tab.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var old: Array[Dictionary] = Actions.entries({"rules_version": "2014"}, ["disarm_dmg", "overrun_dmg", "tumble_dmg", "spellcasting_xge"])
	var modern: Array[Dictionary] = Actions.entries({"rules_version": "2024"})
	assert(_contains(old, "Usare un oggetto", 0))
	assert(not _contains(old, "Studiare", 0))
	assert(_contains(modern, "Studiare", 0))
	assert(_contains(modern, "Influenzare", 0))
	assert(_contains(modern, "Muoversi", 3))
	assert(_contains(modern, "Attacco di opportunità", 4))
	# Every source-supplemented edition shows the right available options.
	assert(_contains(old, "Attivare un oggetto magico", 0))
	assert(not _contains(modern, "Attivare un oggetto magico", 0))
	assert(_contains(old, "Disarmare", 0))
	assert(_contains(old, "Travolgere", 1))
	assert(_contains(old, "Passare con acrobazia", 1))
	assert(_contains(old, "Identificare un incantesimo", 0))
	assert(_contains(old, "Identificare un incantesimo", 4))
	assert(_contains(old, "Interrompere concentrazione", 2))
	assert(_contains(modern, "Interrompere concentrazione", 2))
	assert(_contains(modern, "Afferrare una creatura", 0))
	assert(_contains(modern, "Indossare o rimuovere uno scudo", 0))
	assert(_contains(modern, "Combattere con due armi", 1))
	assert(not _contains(modern, "Impulso curativo", 0))
	for definition: Dictionary in Actions._general_supplements():
		assert(String(definition.get("source", "")) in ["DMG", "PHB", "XGE", "XPHB"])
		assert(int(definition.get("page", 0)) > 0)
		assert(not (definition.get("timings", []) as Array).is_empty())
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
	var shared_action_position := -1
	var personal_action_position := -1
	for index: int in range(typed_actions.size()):
		var entry: Dictionary = typed_actions[index]
		if String(entry.get("name", "")) == "Attaccare":
			shared_action_position = index
			assert(String(entry.get("origin", "")) == "general")
		if String(entry.get("name", "")) == "Scatto speciale":
			personal_action_position = index
			assert(String(entry.get("origin", "")) == "personal")
	assert(shared_action_position >= 0 and personal_action_position > shared_action_position)
	for entry: Dictionary in typed_actions:
		if entry.get("name", "") == "Scatto speciale":
			assert(entry.get("tracker", "") == "Cariche")
			assert(String(entry.get("origin", "")) == "personal")
	var featured: Dictionary = {}
	for entry: Dictionary in old:
		if String(entry.get("name", "")) == "Disarmare":
			featured = entry
			break
	assert(featured.get("optional", false) == true)
	assert(featured.get("origin", "") == "general")
	assert(Actions.GROUPS[0] == "Azione")
	print("PASS: native actions ordered general then personal; tracker labels and skills inside Action")
	quit(0)

func _contains(rows: Array[Dictionary], name: String, timing: int) -> bool:
	for row: Dictionary in rows:
		if String(row.get("name", "")) == name and int(row.get("time", -1)) == timing:
			return true
	return false
