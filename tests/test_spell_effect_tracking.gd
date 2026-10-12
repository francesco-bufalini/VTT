extends SceneTree

const ActiveSpells = preload("res://vtt/creature_active_spells.gd")
const SpellcastingTab = preload("res://vtt/creature_spellcasting_tab.gd")


class Sink extends Node:
	func changed(_values: Dictionary) -> void:
		pass
	func status(_message: String) -> void:
		pass


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	assert(not ActiveSpells.has_duration({"duration": "Instantaneous"}))
	assert(not ActiveSpells.has_duration({"duration": [{"type": "instant"}]}))
	assert(ActiveSpells.has_duration({"duration": "1 hour"}))
	assert(ActiveSpells.has_duration({"duration": "Concentration, up to 1 minute"}))
	assert(ActiveSpells.requires_concentration({"duration": "Concentration, up to 1 minute"}))
	assert(ActiveSpells.requires_concentration({"duration": [{"type": "timed", "concentration": true}]}))
	assert(not ActiveSpells.requires_concentration({"duration": "10 minutes"}))

	var sink := Sink.new()
	root.add_child(sink)
	var tab := SpellcastingTab.new()
	root.add_child(tab)
	tab.setup(Callable(sink, "changed"), Callable(sink, "status"))
	var record := {
		"kind": "character", "rules_version": "2014",
		"class": "wizard", "level": 5,
		"abilities": {"int": 16},
		"conditions": [],
		"spell_slots_total": [0, 4, 3, 2, 0, 0, 0, 0, 0, 0]
	}
	tab.load_record(record)
	var summary: Label = tab.get("_spell_summary")
	assert(summary != null)
	assert("INT" in summary.text and "+6" in summary.text and "CD: 14" in summary.text,
		"The spellcasting stats must always be visible and use the caster's ability.")
	assert("nessuna" in summary.text)

	record["concentrating_spell_id"] = "test_spell"
	record["conditions"] = ["concentrating"]
	tab.refresh_spell_state(record)
	assert("test_spell" in summary.text and "Concentrazione:" in summary.text)
	record["concentrating_spell_id"] = ""
	record["conditions"] = []
	tab.refresh_spell_state(record)
	assert("nessuna" in summary.text)
	tab.queue_free()
	sink.queue_free()
	print("PASS: spell duration filtering, concentration detection and casting header")
	quit()
