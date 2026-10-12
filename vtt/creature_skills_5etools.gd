extends RefCounted

# The canonical 18 5etools/D&D 5e skills and their default ability mappings.
# Keys match the monster stat block "skill" object and character save arrays.
const SKILLS: Array[Dictionary] = [
	{"id": "acrobatics", "label": "Acrobazia", "ability": "dex"},
	{"id": "animal handling", "label": "Addestrare Animali", "ability": "wis"},
	{"id": "arcana", "label": "Arcano", "ability": "int"},
	{"id": "athletics", "label": "Atletica", "ability": "str"},
	{"id": "deception", "label": "Inganno", "ability": "cha"},
	{"id": "history", "label": "Storia", "ability": "int"},
	{"id": "insight", "label": "Intuizione", "ability": "wis"},
	{"id": "intimidation", "label": "Intimidire", "ability": "cha"},
	{"id": "investigation", "label": "Indagare", "ability": "int"},
	{"id": "medicine", "label": "Medicina", "ability": "wis"},
	{"id": "nature", "label": "Natura", "ability": "int"},
	{"id": "perception", "label": "Percezione", "ability": "wis"},
	{"id": "performance", "label": "Intrattenere", "ability": "cha"},
	{"id": "persuasion", "label": "Persuasione", "ability": "cha"},
	{"id": "religion", "label": "Religione", "ability": "int"},
	{"id": "sleight of hand", "label": "Rapidità di Mano", "ability": "dex"},
	{"id": "stealth", "label": "Furtività", "ability": "dex"},
	{"id": "survival", "label": "Sopravvivenza", "ability": "wis"}
]


# 5etools monsters may specify a complete skill modifier instead of just rank.
# Infer 1x/2x proficiency only when it is an exact match; retain unknown
# specialized modifiers in the stat block for future custom bonuses.
static func ranks_from_bestiary(record: Dictionary, proficiency: int, ability_scores: Dictionary) -> Dictionary:
	var ranks: Dictionary = {}
	var stat: Dictionary = record.get("stat_block", {})
	var raw: Variant = stat.get("skill", {})
	if not raw is Dictionary:
		return ranks
	for definition: Dictionary in SKILLS:
		var key: String = String(definition["id"])
		if not (raw as Dictionary).has(key):
			continue
		var source: String = String((raw as Dictionary)[key]).strip_edges()
		if not source.is_valid_int():
			continue
		var ability: String = String(definition["ability"])
		var modifier: int = floori((int(ability_scores.get(ability, 10)) - 10) / 2.0)
		var difference: int = int(source) - modifier
		if difference == proficiency * 2:
			ranks[key] = 2
		elif difference == proficiency:
			ranks[key] = 1
	return ranks
