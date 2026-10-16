extends RefCounted
## Read-only projection for the authenticated PWA. Calls the exact same
## calculators used by desktop/Android and never saves the supplied record.
const Rules = preload("res://vtt/creature_rules.gd")
const Bonuses = preload("res://vtt/creature_bonus_rules.gd")
const Controller = preload("res://vtt/creature_sheet_controller.gd")
const Proficiencies = preload("res://vtt/creature_proficiency_rules.gd")
const Skills = preload("res://vtt/creature_skills_5etools.gd")
const AttackData = preload("res://vtt/creature_attack_data.gd")
const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]
const MAX_ATTACKS := 30

static func evaluate(original: Dictionary) -> Dictionary:
	if String(original.get("kind", "")) not in ["character", "monster"]:
		return {"ok": false, "error": "invalid_creature_kind"}
	if not original.get("abilities", {}) is Dictionary:
		return {"ok": false, "error": "invalid_abilities"}
	if original.has("inventory") and not original.inventory is Array:
		return {"ok": false, "error": "invalid_inventory"}
	var record: Dictionary = original.duplicate(true)
	# Use exactly the same automatic progression and mirrors as the native UI,
	# but only on the detached copy. Never change resource expenditure in storage.
	Controller.sync_automatic_progression(record)
	Controller.recalculate_bonus_mirrors(record)
	var ability_values := {}
	var saves := {}
	for key: String in ABILITIES:
		ability_values[key] = {
			"score": Bonuses.value(record, "ability:" + key),
			"modifier": Bonuses.value(record, "ability_mod:" + key)
		}
		saves[key] = Bonuses.value(record, "save:" + key)
	var skills := {}
	for definition: Dictionary in Skills.SKILLS:
		var id: String = String(definition.get("id", ""))
		if not id.is_empty():
			skills[id] = Bonuses.value(record, "skill:" + id)
	var speeds := {"walk": maxi(0, Bonuses.value(record, "speed"))}
	for mode: String in Rules.SPECIAL_SPEEDS:
		speeds[mode] = maxi(0, Bonuses.value(record, "speed:" + mode))
	var proficiency: int = Bonuses.value(record, "proficiency")
	var attacks: Array[Dictionary] = []
	for attack: Dictionary in AttackData.definitions(record):
		if attacks.size() >= MAX_ATTACKS:
			break
		attacks.append({
			"id": String(attack.get("id", "")),
			"name": String(attack.get("name", "")),
			"hit": AttackData.attack_bonus(record, attack, proficiency),
			"damage": AttackData.damage_label(record, attack),
			"range_feet": int(attack.get("range_feet", 0)),
			"long_range_feet": int(attack.get("long_range_feet", 0)),
			"hit_formula": AttackData.attack_bonus_formula(record, attack, proficiency)
		})
	var slots: Array[Dictionary] = []
	var totals: Variant = record.get("spell_slots_total", [])
	var spent: Variant = record.get("spell_slots_spent", [])
	for level: int in range(1, 10):
		var saved_total: int = int(totals[level]) if totals is Array and (totals as Array).size() > level else 0
		var maximum: int = maxi(0, Bonuses.add(record, "slot:" + str(level), saved_total))
		var used: int = int(spent[level]) if spent is Array and (spent as Array).size() > level else 0
		slots.append({"level": level, "total": maximum, "spent": clampi(used, 0, maximum)})
	var pact_total: int = maxi(0, Bonuses.add(record, "pact_slot", int(record.get("pact_slots_total", 0))))
	var pact_spent: int = clampi(int(record.get("pact_slots_spent", 0)), 0, pact_total)
	var automatic_hp: Dictionary = {}
	if String(record.get("kind", "character")) == "character":
		# Native HP progression needs the post-bonus CON modifier, not merely
		# the raw ability score saved on the creature.
		var hp_context: Dictionary = record.duplicate(false)
		hp_context["effective_con_modifier"] = Bonuses.value(record, "ability_mod:con")
		automatic_hp = Rules.automatic_hit_points(hp_context)
	return {
		"ok": true,
		"source": "godot",
		"schema": 1,
		"abilities": ability_values,
		"saves": saves,
		"skills": skills,
		"stats": {
			"proficiency": proficiency,
			"initiative": int(record.get("initiative", 0)),
			"armor_class": int(record.get("armor_class", 10)),
			"max_hp": int(record.get("max_hp", 1)),
			"passive_perception": Bonuses.value(record, "passive_perception"),
			"speeds": speeds,
			"hit_dice": String(record.get("hit_dice", "")),
			"level": int(record.get("level", 0)),
			"automatic_hp": automatic_hp
		},
		"spell_slots": slots,
		"pact_slots": {"total": pact_total, "spent": pact_spent, "level": int(record.get("pact_slot_level", 1))},
		"attacks": attacks,
		"explanations": {
			"armor_class": Bonuses.description(record, "ac"),
			"initiative": Bonuses.description(record, "initiative"),
			"speed": Bonuses.description(record, "speed"),
			"hit_points": Bonuses.description(record, "hp")
		}
	}
