extends RefCounted
## Class-feature state and payments. No board, UI or private remote-sheet access.
const PlayerCatalog = preload("res://vtt/player_5etools_catalog.gd")
const Features = preload("res://vtt/creature_features.gd")
const Profs = preload("res://vtt/creature_proficiency_rules.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Items = preload("res://vtt/creature_item_rules.gd")
const Skills = preload("res://vtt/creature_skills_5etools.gd")
const RULES := [
	["rage", "Barbarian", "Rage", "Ira", "Rages", "toggle", "bonus"],
	["reckless_attack", "Barbarian", "Reckless Attack", "Attacco irruento", "", "toggle", "free"],
	["second_wind", "Fighter", "Second Wind", "Recuperare energie", "Second Wind", "heal_roll", "bonus"],
	["action_surge", "Fighter", "Action Surge", "Impeto d'azione", "Action Surge", "context", "free"],
	["lay_on_hands", "Paladin", "Lay on Hands", "Imposizione delle mani", "Lay on Hands", "heal_pool", "action"],
	["divine_sense", "Paladin", "Divine Sense", "Percezione del divino", "Divine Sense", "context", "action"],
	["turn_undead", "Cleric", "Turn Undead", "Scacciare non morti", "Channel Divinity", "context", "action"],
	["channel_divinity", "Paladin", "Channel Divinity", "Incanalare divinità", "Channel Divinity", "context", "action"],
	["font_of_magic", "Sorcerer", "Font of Magic", "Fonte di magia", "Sorcery Points", "conversion", "bonus"],
	["innate_sorcery", "Sorcerer", "Innate Sorcery", "Stregoneria innata", "Innate Sorcery", "toggle", "bonus"],
	["arcane_recovery", "Wizard", "Arcane Recovery", "Recupero arcano", "Arcane Recovery", "recovery", "free"],
	["flurry_of_blows", "Monk", "Ki", "Raffica di colpi", "Ki Points", "context", "bonus"],
	["patient_defense", "Monk", "Ki", "Difesa paziente", "Ki Points", "toggle", "bonus"],
	["step_of_the_wind", "Monk", "Ki", "Passo del vento", "Ki Points", "toggle", "bonus"],
	["stunning_strike", "Monk", "Stunning Strike", "Colpo stordente", "Ki Points", "context", "free"],
	["uncanny_dodge", "Rogue", "Uncanny Dodge", "Schivata prodigiosa", "", "context", "reaction"],
	["deflect_missiles", "Monk", "Deflect Missiles", "Deviare proiettili", "", "context", "reaction"],
	["deflect_attacks", "Monk", "Deflect Attacks", "Deviare attacchi", "", "context", "reaction"]
]

static func class_level(record: Dictionary, name: String) -> int:
	for raw: Variant in record.get("classes", []):
		if raw is Dictionary and String(raw.get("name", "")).nocasecmp_to(name) == 0:
			return int(raw.get("level", 0))
	return int(record.get("level", 0)) if String(record.get("class", "")).nocasecmp_to(name) == 0 else 0

static func entries(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var collected := Features.collect_features(record)
	var enabled := Profs.origin_enabled_map(record)
	var revised := String(record.get("rules_version", "2014")) == "2024"
	for rule: Array in RULES:
		for feature: Dictionary in collected:
			var parent: String = String(rule[2])
			if revised and parent == "Ki": parent = "Monk’s Focus"
			var feature_name := String(feature.get("name", "")).replace("'", "’")
			if feature_name.nocasecmp_to(parent) != 0 or String(feature.get("class_name", "")).nocasecmp_to(String(rule[1])) != 0:
				continue
			var origin := "feature:" + String(feature.get("key", ""))
			if bool(feature.get("inactive", false)) or not bool(enabled.get(origin, true)):
				continue
			var resource: String = String(rule[4])
			if revised and resource == "Ki Points": resource = "Focus Points"
			if revised and rule[0] == "divine_sense": resource = "Channel Divinity"
			var tracker := tracker_named(record, resource, String(rule[1]))
			var row := {"id": "class_feature:" + String(rule[0]), "key": rule[0], "name": rule[3],
				"class_name": rule[1], "origin_id": origin, "feature_name": feature.name,
				"detail": _text(feature.get("entries", "")), "mode": rule[5], "activation": rule[6],
				"tracker_id": tracker.get("id", ""), "resource_name": resource, "cost": 1}
			if revised and rule[0] == "lay_on_hands": row.activation = "bonus"
			if revised and rule[0] in ["patient_defense", "step_of_the_wind"]:
				row.cost = 0 # Base Disengage/Dash is free; enhanced mode spends 1.
			row["active"] = row.mode == "toggle" and is_active(record, String(rule[0]), false)
			result.append(row)
			break
	# The selected metamagic options retain their own source identities.
	for option: Dictionary in metamagic_options(record):
		result.append({"id": "metamagic:" + String(option.name), "key": "metamagic", "name": option.name,
			"class_name": "Sorcerer", "feature_name": "Metamagic", "detail": "Scegli questa opzione durante il lancio di un incantesimo. " + String(option.get("description", "")),
			"mode": "metamagic_roll" if String(option.name) in ["Empowered Spell", "Seeking Spell"] else "metamagic", "activation": "free", "resource_name": "Sorcery Points", "cost": option.cost})
	return result

static func _text(raw: Variant) -> String:
	if raw is String: return raw
	if raw is Array:
		var parts: PackedStringArray = []
		for child: Variant in raw: parts.append(_text(child))
		return "\n".join(parts)
	if raw is Dictionary:
		return String(raw.get("name", "")) + " " + _text(raw.get("entries", raw.get("items", "")))
	return ""

static func tracker_named(record: Dictionary, name: String, owner_class: String = "") -> Dictionary:
	if name.is_empty(): return {}
	for tracker: Dictionary in Trackers.for_creature(record):
		if String(tracker.get("name", "")).nocasecmp_to(name) != 0: continue
		if not owner_class.is_empty() and String(tracker.get("origin_class", "")).nocasecmp_to(owner_class) != 0: continue
		return tracker
	return {}

static func remaining(record: Dictionary, tracker: Dictionary) -> int:
	if tracker.is_empty() or bool(tracker.get("disabled", false)): return 0
	var id := String(tracker.get("id", ""))
	return maxi(0, Bonuses.add(record, "tracker:" + id, int(tracker.get("max", 0))) - int(record.get("resource_tracker_spent", {}).get(id, 0)))

static func spend(record: Dictionary, tracker: Dictionary, cost: int) -> bool:
	if cost < 0 or remaining(record, tracker) < cost: return false
	if cost == 0: return true
	var spent: Dictionary = record.get("resource_tracker_spent", {}).duplicate(true)
	var id := String(tracker.get("id", ""))
	spent[id] = int(spent.get(id, 0)) + cost
	record["resource_tracker_spent"] = spent
	return true

static func heavy_armor(record: Dictionary) -> bool:
	var armor := Items.equipped_armor(record.get("inventory", []))
	return not armor.is_empty() and String(Items.entry_for(armor).get("type", "")).split("|")[0] == "HA"

static func is_active(record: Dictionary, key: String, validate: bool = true) -> bool:
	if not record.get("active_class_features", {}).has(key): return false
	if key == "rage" and (heavy_armor(record) or "unconscious" in record.get("conditions", [])
		or (String(record.get("rules_version", "2014")) == "2024" and "incapacitated" in record.get("conditions", []))): return false
	if validate:
		for row: Dictionary in entries(record):
			if row.get("key", "") == key: return true
		return false
	return true

static func activate(record: Dictionary, id: String, options: Dictionary = {}) -> Dictionary:
	var action: Dictionary = {}
	for row: Dictionary in entries(record):
		if row.id == id: action = row; break
	if action.is_empty(): return {"ok": false, "message": "Privilegio non disponibile."}
	var next := record.duplicate(true)
	var active: Dictionary = next.get("active_class_features", {}).duplicate(true)
	var key := String(action.key)
	if String(action.mode) == "toggle" and active.has(key):
		active.erase(key)
		next["active_class_features"] = active
		return {"ok": true, "record": next, "message": String(action.name) + " terminato."}
	if action.mode in ["metamagic", "conversion", "recovery"]:
		return {"ok": false, "message": "Completa le scelte del privilegio."}
	if key == "rage" and (heavy_armor(next) or "unconscious" in next.get("conditions", []) or (String(next.get("rules_version", "2014")) == "2024" and "incapacitated" in next.get("conditions", []))):
		return {"ok": false, "message": "Ira non disponibile con armatura pesante o privo di sensi."}
	var cost := int(options.get("cost", action.cost))
	if action.mode == "heal_pool": cost = int(options.get("amount", 1))
	if key in ["patient_defense", "step_of_the_wind"] and String(next.get("rules_version", "2014")) == "2024":
		cost = 1 if bool(options.get("enhanced", false)) else 0
	elif action.mode != "heal_pool": cost = int(action.cost)
	if cost < 0 or (action.mode == "heal_pool" and cost < 1): return {"ok": false, "message": "Quantità non valida."}
	var resource := tracker_named(next, String(action.resource_name), String(action.class_name))
	if not String(action.resource_name).is_empty() and cost > 0:
		if not spend(next, resource, cost): return {"ok": false, "message": "Risorsa insufficiente."}
	if action.mode == "heal_roll":
		var die := clampi(int(options.get("roll", randi_range(1, 10))), 1, 10)
		var amount := die + class_level(next, "Fighter")
		next["current_hp"] = mini(Bonuses.value(next, "hp"), int(next.get("current_hp", 0)) + amount)
	elif action.mode == "heal_pool":
		if bool(options.get("apply_to_self", true)):
			next["current_hp"] = mini(Bonuses.value(next, "hp"), int(next.get("current_hp", 0)) + cost)
	else:
		active[key] = {"name": action.name, "origin_id": action.origin_id,
			"rules_version": next.get("rules_version", "2014"), "enhanced": bool(options.get("enhanced", false))}
		next["active_class_features"] = active
	if key == "rage":
		next["concentrating_spell_id"] = ""
		var conditions: Array = next.get("conditions", []).duplicate()
		conditions.erase("concentrating")
		next["conditions"] = conditions
	return {"ok": true, "record": next, "message": String(action.name) + " attivato."}

static func rage_damage(record: Dictionary, attack: Dictionary, ability: String) -> int:
	if ability != "str" or not is_active(record, "rage"): return 0
	var ranged := bool(attack.get("thrown", false)) or String(attack.get("weapon_kind", "")) == "R"
	if String(record.get("rules_version", "2014")) != "2024" and ranged: return 0
	var level := class_level(record, "Barbarian")
	return 4 if level >= 16 else 3 if level >= 9 else 2

static func roll_advantage(record: Dictionary, key: String) -> bool:
	if key == "save:dex" and is_active(record, "patient_defense") and "incapacitated" not in record.get("conditions", []):
		if String(record.get("rules_version", "2014")) != "2024" or bool(record.get("active_class_features", {}).get("patient_defense", {}).get("enhanced", false)): return true
	if is_active(record, "rage"):
		if key in ["ability_mod:str", "save:str"]: return true
		if key.begins_with("skill:"):
			for skill: Dictionary in Skills.SKILLS:
				if skill.id == key.trim_prefix("skill:") and skill.ability == "str": return true
	return false

const METAMAGIC_COSTS := {"Careful Spell": 1, "Distant Spell": 1, "Empowered Spell": 1,
	"Extended Spell": 1, "Heightened Spell": 3, "Quickened Spell": 2, "Subtle Spell": 1,
	"Twinned Spell": 1, "Seeking Spell": 2, "Transmuted Spell": 1}
static func metamagic_options(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var revised := String(record.get("rules_version", "2014")) == "2024"
	for raw: Variant in record.get("optional_features_catalog", []):
		if not raw is Dictionary or bool(raw.get("disabled", false)): continue
		var name := String(raw.get("name", ""))
		if not METAMAGIC_COSTS.has(name): continue
		var description := _text(raw.get("entries", ""))
		if description.is_empty():
			description = PlayerCatalog.description_text("optional_features", PlayerCatalog.detailed_entry("optional_features", raw))
		result.append({"name": name, "cost": 2 if revised and name == "Heightened Spell" else 1 if revised and name == "Seeking Spell" else int(METAMAGIC_COSTS[name]), "description": description})
	return result

static func convert_slots(record: Dictionary, level: int, create_slot: bool) -> Dictionary:
	if level < 1 or level > 5: return {"ok": false, "message": "Livello slot non valido."}
	var allowed := false
	for row: Dictionary in entries(record):
		if row.key == "font_of_magic": allowed = true
	if not allowed: return {"ok": false, "message": "Fonte di magia non disponibile."}
	var next := record.duplicate(true)
	var tracker := tracker_named(next, "Sorcery Points", "Sorcerer")
	var slots: Array = next.get("spell_slots_spent", []).duplicate()
	while slots.size() < 10: slots.append(0)
	if create_slot:
		var costs := [0, 2, 3, 5, 6, 7]
		if class_level(next, "Sorcerer") < level * 2 - 1 and String(next.get("rules_version", "2014")) == "2024":
			return {"ok": false, "message": "Livello da Stregone insufficiente."}
		if not spend(next, tracker, int(costs[level])): return {"ok": false, "message": "Punti stregoneria insufficienti."}
		var created: Array = next.get("created_spell_slots", []).duplicate()
		while created.size() < 10: created.append(0)
		created[level] = int(created[level]) + 1
		next["created_spell_slots"] = created
	else:
		var totals: Array = next.get("spell_slots_total", [])
		var available := int(totals[level]) if totals.size() > level else 0
		var created: Array = next.get("created_spell_slots", [])
		if created.size() > level: available += int(created[level])
		if int(slots[level]) >= available: return {"ok": false, "message": "Slot non disponibile."}
		var spent: Dictionary = next.get("resource_tracker_spent", {}).duplicate(true)
		var id := String(tracker.get("id", ""))
		if tracker.is_empty(): return {"ok": false, "message": "Risorsa non disponibile."}
		if int(spent.get(id, 0)) < level: return {"ok": false, "message": "I punti recuperati supererebbero il massimo."}
		spent[id] = int(spent.get(id, 0)) - level
		next["resource_tracker_spent"] = spent
		slots[level] = int(slots[level]) + 1
		next["spell_slots_spent"] = slots
	return {"ok": true, "record": next, "message": "Conversione completata."}


static func recover_slots(record: Dictionary, levels: Array) -> Dictionary:
	var available := false
	for row: Dictionary in entries(record):
		if row.key == "arcane_recovery": available = true
	if not available: return {"ok": false, "message": "Recupero arcano non disponibile."}
	var budget := ceili(float(class_level(record, "Wizard")) / 2.0)
	var total := 0
	var next := record.duplicate(true)
	var spent: Array = next.get("spell_slots_spent", []).duplicate()
	while spent.size() < 10: spent.append(0)
	for raw: Variant in levels:
		var level := int(raw)
		if level < 1 or level > 5 or int(spent[level]) < 1: return {"ok": false, "message": "Seleziona slot consumati di livello da 1 a 5."}
		total += level
		spent[level] = int(spent[level]) - 1
	if total < 1 or total > budget: return {"ok": false, "message": "I livelli degli slot superano il budget di Recupero arcano."}
	if not spend(next, tracker_named(next, "Arcane Recovery", "Wizard"), 1): return {"ok": false, "message": "Recupero arcano già utilizzato."}
	next["spell_slots_spent"] = spent
	return {"ok": true, "record": next, "message": "Slot recuperati."}

static func attack_advantage(record: Dictionary, attack: Dictionary, ability: String) -> bool:
	if ability != "str" or not is_active(record, "reckless_attack"): return false
	return String(record.get("rules_version", "2014")) == "2024" or not (bool(attack.get("thrown", false)) or String(attack.get("weapon_kind", "")) == "R")
