extends SceneTree

const PDFStatblockImporter = preload("res://vtt/pdf_statblock_importer.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var sample := """
Adult Black Dragon
Huge dragon, chaotic evil
Armor Class 19 (natural armor)
Hit Points 195 (17d12 + 85)
Speed 40 ft., fly 80 ft., swim 40 ft.
STR DEX CON INT WIS CHA
23 (+6) 14 (+2) 21 (+5) 14 (+2) 13 (+1) 19 (+4)
Saving Throws Dex +7, Con +10, Wis +6, Cha +9
Skills Perception +11, Stealth +7
Damage Immunities acid
Senses blindsight 60 ft., darkvision 120 ft., passive Perception 21
Languages Common, Draconic
Challenge 14 (11,500 XP)
Proficiency Bonus +5
Traits
Amphibious. The dragon can breathe air and water.
Actions
Multiattack. The dragon makes three Rend attacks.
Rend. Melee Weapon Attack: +11 to hit, reach 10 ft. Hit: 13 slashing damage.
Acid Breath (Recharge 5-6). Each creature in a 60-foot line makes a Dexterity save.
Legendary Actions
Cloud of Insects. One creature within 120 feet takes poison damage.
"""

	var stat := PDFStatblockImporter.parse_stat_block_text(
		sample,
		"adult-black-dragon"
	)
	assert(String(stat.get("name", "")) == "Adult Black Dragon")
	assert(String(stat.get("source", "")) == "PDF")
	assert(bool(stat.get("_imported_pdf", false)))
	assert(String(stat.get("size", "")) == "H")
	assert(String(stat.get("type", "")) == "dragon")
	assert(String(stat.get("alignment", "")) == "chaotic evil")
	assert(int(stat.get("str", 0)) == 23)
	assert(int(stat.get("dex", 0)) == 14)
	assert(int(stat.get("cha", 0)) == 19)

	var hp: Dictionary = stat.get("hp", {})
	assert(int(hp.get("average", 0)) == 195)
	assert(String(hp.get("formula", "")) == "17d12 + 85")
	assert("40 ft." in String(stat.get("speed", "")))
	assert("Perception +11" in String(stat.get("skill", "")))
	assert("acid" in String(stat.get("immune", "")))
	assert(int(stat.get("passive", 0)) == 21)
	assert("Common" in String(stat.get("languages", "")))
	assert(String(stat.get("cr", "")).begins_with("14"))

	var traits: Array = stat.get("trait", [])
	var actions: Array = stat.get("action", [])
	var legendary: Array = stat.get("legendary", [])
	assert(traits.size() == 1)
	assert(actions.size() == 3)
	assert(legendary.size() == 1)
	assert(String((actions[1] as Dictionary).get("name", "")) == "Rend")
	assert(
		"slashing damage"
		in String(
			((actions[1] as Dictionary).get("entries", []) as Array)[0]
		)
	)

	print("PASS: PDF stat blocks parse into editable master creature data")
	quit()
