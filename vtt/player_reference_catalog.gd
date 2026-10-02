extends RefCounted

# Compact player-facing reference catalog normalized from the categories used
# by 5e.tools. Full spell data stays in SpellCatalog, which is already
# generated from 5e.tools in this project.

const ABILITIES: Array[Dictionary] = [
	{"id": "str", "name": "Forza", "short": "FOR"},
	{"id": "dex", "name": "Destrezza", "short": "DES"},
	{"id": "con", "name": "Costituzione", "short": "COS"},
	{"id": "int", "name": "Intelligenza", "short": "INT"},
	{"id": "wis", "name": "Saggezza", "short": "SAG"},
	{"id": "cha", "name": "Carisma", "short": "CAR"}
]

const SKILLS: Array[Dictionary] = [
	{"id": "acrobatics", "name": "Acrobazia", "ability": "dex"},
	{"id": "animal_handling", "name": "Addestrare Animali", "ability": "wis"},
	{"id": "arcana", "name": "Arcano", "ability": "int"},
	{"id": "athletics", "name": "Atletica", "ability": "str"},
	{"id": "stealth", "name": "Furtività", "ability": "dex"},
	{"id": "investigation", "name": "Indagare", "ability": "int"},
	{"id": "deception", "name": "Inganno", "ability": "cha"},
	{"id": "intimidation", "name": "Intimidire", "ability": "cha"},
	{"id": "performance", "name": "Intrattenere", "ability": "cha"},
	{"id": "insight", "name": "Intuizione", "ability": "wis"},
	{"id": "medicine", "name": "Medicina", "ability": "wis"},
	{"id": "nature", "name": "Natura", "ability": "int"},
	{"id": "perception", "name": "Percezione", "ability": "wis"},
	{"id": "persuasion", "name": "Persuasione", "ability": "cha"},
	{"id": "sleight_of_hand", "name": "Rapidità di Mano", "ability": "dex"},
	{"id": "religion", "name": "Religione", "ability": "int"},
	{"id": "survival", "name": "Sopravvivenza", "ability": "wis"},
	{"id": "history", "name": "Storia", "ability": "int"}
]

# The union keeps the sheet usable with both the 2014 and 2024 rules families.
# Source labels are retained so future rule automation can distinguish them.
const CLASSES: Array[Dictionary] = [
	{"name": "Artificer", "display": "Artefice", "source": "TCE"},
	{"name": "Barbarian", "display": "Barbaro", "source": "XPHB"},
	{"name": "Bard", "display": "Bardo", "source": "XPHB"},
	{"name": "Cleric", "display": "Chierico", "source": "XPHB"},
	{"name": "Druid", "display": "Druido", "source": "XPHB"},
	{"name": "Fighter", "display": "Guerriero", "source": "XPHB"},
	{"name": "Monk", "display": "Monaco", "source": "XPHB"},
	{"name": "Paladin", "display": "Paladino", "source": "XPHB"},
	{"name": "Ranger", "display": "Ranger", "source": "XPHB"},
	{"name": "Rogue", "display": "Ladro", "source": "XPHB"},
	{"name": "Sorcerer", "display": "Stregone", "source": "XPHB"},
	{"name": "Warlock", "display": "Warlock", "source": "XPHB"},
	{"name": "Wizard", "display": "Mago", "source": "XPHB"}
]

const SPECIES: Array[Dictionary] = [
	{"name": "Aasimar", "source": "XPHB"},
	{"name": "Dragonborn", "display": "Dragonide", "source": "XPHB"},
	{"name": "Dwarf", "display": "Nano", "source": "XPHB"},
	{"name": "Elf", "display": "Elfo", "source": "XPHB"},
	{"name": "Gnome", "source": "XPHB"},
	{"name": "Goliath", "source": "XPHB"},
	{"name": "Halfling", "source": "XPHB"},
	{"name": "Human", "display": "Umano", "source": "XPHB"},
	{"name": "Orc", "display": "Orco", "source": "XPHB"},
	{"name": "Tiefling", "source": "XPHB"},
	{"name": "Half-Elf", "display": "Mezzelfo", "source": "PHB"},
	{"name": "Half-Orc", "display": "Mezzorco", "source": "PHB"}
]

const BACKGROUNDS: Array[Dictionary] = [
	{"name": "Acolyte", "display": "Accolito", "source": "XPHB"},
	{"name": "Artisan", "display": "Artigiano", "source": "XPHB"},
	{"name": "Charlatan", "display": "Ciarlatano", "source": "XPHB"},
	{"name": "Criminal", "display": "Criminale", "source": "XPHB"},
	{"name": "Entertainer", "display": "Intrattenitore", "source": "XPHB"},
	{"name": "Farmer", "display": "Contadino", "source": "XPHB"},
	{"name": "Guard", "display": "Guardia", "source": "XPHB"},
	{"name": "Guide", "display": "Guida", "source": "XPHB"},
	{"name": "Hermit", "display": "Eremita", "source": "XPHB"},
	{"name": "Merchant", "display": "Mercante", "source": "XPHB"},
	{"name": "Noble", "display": "Nobile", "source": "XPHB"},
	{"name": "Sage", "display": "Sapiente", "source": "XPHB"},
	{"name": "Sailor", "display": "Marinaio", "source": "XPHB"},
	{"name": "Scribe", "display": "Scriba", "source": "XPHB"},
	{"name": "Soldier", "display": "Soldato", "source": "XPHB"},
	{"name": "Wayfarer", "display": "Viandante", "source": "XPHB"},
	{"name": "Folk Hero", "display": "Eroe Popolare", "source": "PHB"},
	{"name": "Guild Artisan", "display": "Artigiano di Gilda", "source": "PHB"},
	{"name": "Outlander", "display": "Forestiero", "source": "PHB"},
	{"name": "Urchin", "display": "Monello", "source": "PHB"}
]


static func display_name(entry: Dictionary) -> String:
	return String(entry.get("display", entry.get("name", "")))


static func proficiency_bonus(level: int) -> int:
	return 2 + maxi(0, level - 1) / 4


static func ability_modifier(score: int) -> int:
	return floori((score - 10) / 2.0)


static func skill_ability(skill_id: String) -> String:
	for skill: Dictionary in SKILLS:
		if String(skill.get("id", "")) == skill_id:
			return String(skill.get("ability", ""))
	return ""
