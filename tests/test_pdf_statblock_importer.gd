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


	var tetra_sample := """
Kaos, God of Speed
Gargantuan celestial (god), Chaotic Good
Armor Class 25 (natural armor)
Hit Points 202 (15d20 + 45)
Speed 100 ft. (It can ignore difficult terrain and run on vertical
surfaces or across water if it moves at least 6 meters in a
turn.)
STR
22 (+6)
DEX
30 (+10)
CON
16 (+3)
INT
30 (+10)
WIS
22 (+6)
CHA
24 (+7)
Saving Throws Dex +18, Int +18, Cha +15
Skills Acrobatics +26, Athletics +14, Perception +14, Persuasion
+15, Sleight of Hand +18, Stealth +18
Damage Immunities lightning, poison, radiant, thunder;
bludgeoning, piercing, and slashing from nonmagical attacks
Condition Immunities charmed, exhaustion, frightened,
poisoned
Senses darkvision 100 ft., truesight 100 ft., passive Perception
24
Languages All, telepathy 100 ft.
Challenge 26 (90,000 XP)
Godspeed (Mythic Trait; Recharges after a Short or Long Rest).
When Kaos drops to 0 hit points, he neither dies nor falls
unconscious. Instead, he regains 200 hit points.
Magic Weapons. Kaos's weapon attacks are magical.
Actions
Multiattack. Kaos makes four Lightning Fists attacks.
Lightning Fists. Melee Weapon Attack: +16 to hit, reach 15 ft.,
one target. Hit: 9 (2d8 + 10) bludgeoning damage.
Reactions
Slow Fall. Kaos can use its reaction when falling to reduce fall
damage by 3d10.
Legendary Actions
Instant Movement. It moves 30 feet without provoking
opportunity attacks.
Mythic Actions
Speed Clone (Costs 2 Actions). Kaos activates a speed clone.
24/09/26, 18:33 Kaos, God of Speed
about:blank
1/1
"""
	var tetra := PDFStatblockImporter.parse_stat_block_text(
		tetra_sample,
		"Kaos, God of Speed"
	)
	assert(String(tetra.get("name", "")) == "Kaos, God of Speed")
	assert(String(tetra.get("size", "")) == "G")
	assert(String(tetra.get("type", "")) == "celestial (god)")
	assert(String(tetra.get("alignment", "")) == "Chaotic Good")
	assert(int(tetra.get("str", 0)) == 22)
	assert(int(tetra.get("dex", 0)) == 30)
	assert(int(tetra.get("con", 0)) == 16)
	assert(int(tetra.get("int", 0)) == 30)
	assert(int(tetra.get("wis", 0)) == 22)
	assert(int(tetra.get("cha", 0)) == 24)

	var tetra_hp: Dictionary = tetra.get("hp", {})
	assert(int(tetra_hp.get("average", 0)) == 202)
	assert(String(tetra_hp.get("formula", "")) == "15d20 + 45")
	assert(
		"vertical surfaces"
		in String(tetra.get("speed", ""))
	)
	assert(
		"Persuasion +15"
		in String(tetra.get("skill", ""))
	)
	assert(
		"bludgeoning, piercing"
		in String(tetra.get("immune", ""))
	)
	assert(int(tetra.get("passive", 0)) == 24)
	assert(String(tetra.get("cr", "")) == "26 (90,000 XP)")

	var tetra_traits: Array = tetra.get("trait", [])
	var tetra_actions: Array = tetra.get("action", [])
	var tetra_reactions: Array = tetra.get("reaction", [])
	var tetra_legendary: Array = tetra.get("legendary", [])
	var tetra_mythic: Array = tetra.get("mythic", [])
	assert(tetra_traits.size() >= 2)
	assert(
		String((tetra_traits[0] as Dictionary).get("name", ""))
		.begins_with("Godspeed")
	)
	assert(tetra_actions.size() == 2)
	assert(tetra_reactions.size() == 1)
	assert(tetra_legendary.size() == 1)
	assert(tetra_mythic.size() == 1)
	assert(
		"about:blank"
		not in String(tetra.get("raw_text", ""))
	)

	print("PASS: PDF stat blocks parse into editable master creature data")
	quit()
