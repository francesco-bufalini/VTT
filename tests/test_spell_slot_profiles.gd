extends SceneTree
# Regression tests for data-driven slot profiles (not spell selection limits).
const Rules = preload("res://vtt/creature_rules.gd")
const Mechanics = preload("res://vtt/class_mechanics_5etools.gd")


func _initialize() -> void:
	call_deferred("run")


func _cast(classes: Array, edition: String = "2014") -> Dictionary:
	return Rules.spell_slot_progression({"rules_version": edition, "classes": classes})


func _one(name: String, level: int, edition: String = "2014", source: String = "") -> Dictionary:
	return _cast([{"name": name, "level": level, "source": source}], edition)


func run() -> void:
	var artificer: Dictionary = Mechanics.slot_profile("Artificer")
	assert(artificer.get("slot_kind", "") == "fractional")
	assert(Mechanics.slot_profile("homebrew").is_empty())

	# Singles: preserve the full, half and artificer contributions at every level.
	for level: int in range(1, 21):
		assert(_one("Wizard", level).caster_level == level)
		assert(_one("Bard", level).caster_level == level)
		assert(_one("Artificer", level, "2014", "TCE").caster_level == ceili(float(level) / 2.0))
		assert(_one("Artificer", level, "2024", "TCE").caster_level == ceili(float(level) / 2.0))
		var legacy_half: int = 0 if level < 2 else ceili(float(level) / 2.0)
		assert(_one("Paladin", level, "2014").caster_level == legacy_half)
		assert(_one("Ranger", level, "2014").caster_level == legacy_half)
		assert(_one("Paladin", level, "2024").caster_level == ceili(float(level) / 2.0))
		assert(_one("Ranger", level, "2024").caster_level == ceili(float(level) / 2.0))
		var warlock: Dictionary = _one("Warlock", level)
		var pact_total: int = 1 if level == 1 else 2 if level < 11 else 3 if level < 17 else 4
		assert(warlock.caster_level == 0)
		assert(warlock.pact_total == pact_total)
		assert(warlock.pact_level == mini(5, ceili(float(level) / 2.0)))

	# Multiclass rounding is based on Spellcasting contributors, not the
	# number of listed classes. Pact Magic is always counted separately.
	for half_level: int in range(1, 21):
		for wizard_level: int in [1, 3, 9, 20]:
			var expected_artificer: int = mini(20, ceili(float(half_level) / 2.0) + wizard_level)
			var expected_legacy_half: int = mini(20, (0 if half_level < 2 else floori(float(half_level) / 2.0)) + wizard_level)
			var expected_modern_half: int = mini(20, ceili(float(half_level) / 2.0) + wizard_level)
			var art: Dictionary = _cast([{"name": "Artificer", "source": "TCE", "level": half_level}, {"name": "Wizard", "level": wizard_level}])
			var pal: Dictionary = _cast([{"name": "Paladin", "level": half_level}, {"name": "Wizard", "level": wizard_level}])
			var ranger: Dictionary = _cast([{"name": "Ranger", "level": half_level}, {"name": "Wizard", "level": wizard_level}], "2024")
			assert(art.caster_level == expected_artificer)
			assert(pal.caster_level == expected_legacy_half)
			assert(ranger.caster_level == expected_modern_half)

	assert(_cast([{"name": "Paladin", "level": 3}, {"name": "Ranger", "level": 3}]).caster_level == 2)
	assert(_cast([{"name": "Paladin", "level": 3}, {"name": "Fighter", "level": 2}]).caster_level == 2)
	var mixed_pact: Dictionary = _cast([{"name": "Wizard", "level": 3}, {"name": "Warlock", "level": 5}])
	assert(mixed_pact.caster_level == 3 and mixed_pact.pact_total == 2 and mixed_pact.pact_level == 3)
	assert(_cast([{"name": "Paladin", "level": 3}, {"name": "Warlock", "level": 2}]).caster_level == 2)
	assert(_one("Fighter", 6).warnings.contains("sottoclassi magiche"))
	assert(_one("Rogue", 6).warnings.contains("sottoclassi magiche"))
	assert(_one("Monk", 6).warnings.is_empty())
	assert(_one("Unknown Custom Class", 5).warnings.contains("homebrew"))
	assert(_one("Mostro", 4).warnings.is_empty())
	assert(_one("Wizard", 3).slots == [0, 4, 2, 0, 0, 0, 0, 0, 0, 0])
	print("PASS: data-driven 2014/2024 slot profiles, multiclass rounding, pact pool and warnings")
	quit()
