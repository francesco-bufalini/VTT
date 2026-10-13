extends RefCounted

# Roll bonuses are independent of numeric-stat bonuses: never evaluate a die
# to an average or add it to a permanent character modifier.
const ActiveSpells = preload("res://vtt/creature_active_spells.gd")
const Profs = preload("res://vtt/creature_proficiency_rules.gd")
const OriginSpells = preload("res://vtt/origin_spell_grants.gd")

const TARGETS := [
	{"key": "ability_check", "name": "Tutte le prove di caratteristica"},
	{"key": "saving_throw", "name": "Tutti i tiri salvezza"},
	{"key": "attack_roll", "name": "Tutti i tiri per colpire"},
	{"key": "initiative", "name": "Iniziativa"},
	{"key": "any_d20", "name": "Qualunque tiro d20"}
]


static func valid_dice(value: String) -> bool:
	var check := RegEx.create_from_string("^[1-9][0-9]*d(4|6|8|10|12|20|100)$")
	return check != null and check.search(value.strip_edges().to_lower()) != null


static func _scope_for(key: String) -> String:
	if key == "initiative" or key.begins_with("ability_mod:") or key.begins_with("skill:"):
		return "ability_check"
	if key.begins_with("save:"):
		return "saving_throw"
	if key.begins_with("attack_hit:") or key == "spell_attack":
		return "attack_roll"
	return ""


static func applicable(record: Dictionary, key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var scope: String = _scope_for(key)
	if scope.is_empty():
		return result
	var enabled: Dictionary = Profs.origin_enabled_map(record)
	for raw: Variant in record.get("dice_bonuses", []):
		if not raw is Dictionary:
			continue
		var row: Dictionary = raw
		var target: String = String(row.get("target", ""))
		if target not in [key, scope, "any_d20"]:
			continue
		var dice: String = String(row.get("dice", "")).to_lower()
		if not valid_dice(dice) or bool(row.get("disabled", false)):
			continue
		var origin_id: String = String(row.get("origin_id", ""))
		if not origin_id.is_empty() and not bool(enabled.get(origin_id, false)):
			continue
		var grant: Dictionary = row.duplicate(true)
		grant["dice"] = dice
		result.append(grant)
	for spell: Dictionary in ActiveSpells.active_origins(record):
		var sid: String = String(spell.get("id", ""))
		if sid != "spell:" + OriginSpells.BARDIC:
			continue
		# A die is received from the *caster*, never recomputed from the
		# recipient's own class levels or ability modifiers.
		var context: Dictionary = record.get("active_spell_context", {}).get(OriginSpells.BARDIC, {})
		var dice: String = String(context.get("bonus_dice", ""))
		if not valid_dice(dice):
			continue
		result.append({
			"id": "inspiration:" + sid, "origin_id": sid,
			"origin_name": "Bardic Inspiration · " + String(context.get("caster_name", "")),
			"dice": dice, "target": "any_d20",
			"consumes_spell": OriginSpells.BARDIC, "automatic": true
		})
	return result
