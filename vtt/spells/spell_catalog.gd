extends RefCounted

const CLASS_NAMES: Array[String] = [
	"Barbaro",
	"Bardo",
	"Chierico",
	"Druido",
	"Guerriero",
	"Monaco",
	"Paladino",
	"Ranger",
	"Ladro",
	"Stregone",
	"Warlock",
	"Mago",
	"Spellblade"
]

const LEVEL_NAMES: Array[String] = [
	"Trucchetti",
	"1° livello",
	"2° livello",
	"3° livello",
	"4° livello",
	"5° livello",
	"6° livello",
	"7° livello",
	"8° livello",
	"9° livello"
]

const SPELLS: Dictionary = {
	"burning_hands": {
		"id": "burning_hands",
		"name": "Burning Hands",
		"level": 1,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "Self",
		"target": "Self",
		"area": "15-foot cone",
		"components": "V, S",
		"duration": "Instantaneous",
		"classes": ["Stregone", "Mago"],
		"description": (
			"As you hold your hands with thumbs touching and fingers spread, "
			+ "a thin sheet of flames shoots forth from your outstretched fingertips. "
			+ "Each creature in a 15-foot cone must make a Dexterity saving throw. "
			+ "A creature takes 3d6 fire damage on a failed save, or half as much "
			+ "damage on a successful one.\n\n"
			+ "The fire ignites any flammable objects in the area that aren't "
			+ "being worn or carried."
		),
		"higher_levels": (
			"When cast using a spell slot of 2nd level or higher, the damage "
			+ "increases by 1d6 for each slot level above 1st."
		),
		"target_mode": "self_token",
		"aoe_shape": "cone",
		"aoe_length_cells": 3,
		"transient_seconds": 5.0
	},
	"fireball": {
		"id": "fireball",
		"name": "Fireball",
		"level": 3,
		"school": "Evocation",
		"casting_time": "1 action",
		"range": "150 feet",
		"target": "A point you choose within range",
		"area": "20-foot-radius sphere",
		"components": "V, S, M (A tiny ball of bat guano and sulfur)",
		"duration": "Instantaneous",
		"classes": ["Stregone", "Mago", "Spellblade"],
		"description": (
			"A bright streak flashes from your pointing finger to a point you "
			+ "choose within range and then blossoms with a low roar into an "
			+ "explosion of flame. Each creature in a 20-foot-radius sphere "
			+ "centered on that point must make a Dexterity saving throw. "
			+ "A target takes 8d6 fire damage on a failed save, or half as much "
			+ "damage on a successful one. The fire spreads around corners. "
			+ "It ignites flammable objects in the area that aren't being worn "
			+ "or carried."
		),
		"higher_levels": (
			"When cast using a spell slot of 4th level or higher, the damage "
			+ "increases by 1d6 for each slot level above 3rd."
		),
		"target_mode": "token_then_point",
		"range_feet": 150,
		"aoe_shape": "sphere",
		"aoe_radius_feet": 20,
		"transient_seconds": 5.0
	}
}


static func spell(spell_id: String) -> Dictionary:
	var value: Variant = SPELLS.get(spell_id, {})
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


static func all_spells() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for spell_id: Variant in SPELLS.keys():
		var value: Variant = SPELLS.get(spell_id, {})
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("name", "")).naturalnocasecmp_to(
				String(b.get("name", ""))
			) < 0
	)
	return result


static func spells_for_class_and_level(
	class_label: String,
	level: int
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in all_spells():
		var classes_value: Variant = entry.get("classes", [])
		if not classes_value is Array:
			continue
		if (
			class_label in (classes_value as Array)
			and int(entry.get("level", -1)) == level
		):
			result.append(entry)
	return result
