extends SceneTree

const ActiveSpells = preload("res://vtt/creature_active_spells.gd")
const SpellcastingTab = preload("res://vtt/creature_spellcasting_tab.gd")
const PlayerStore = preload("res://vtt/player_character_store.gd")
const MonsterStore = preload("res://vtt/master_creature_store.gd")


class Sink extends Node:
	var last_change: Dictionary = {}
	func changed(values: Dictionary) -> void:
		last_change = values.duplicate(true)
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
	var picker: OptionButton = tab.get("_spell_ability_choice")
	assert(picker != null and picker.item_count == 7)
	tab.call("_on_spellcasting_ability_selected", 5)
	assert(sink.last_change.get("spellcasting_ability", "") == "wis")
	assert("SAG" in picker.get_item_text(5))
	tab.call("_on_spellcasting_ability_selected", 0)
	assert(sink.last_change.get("spellcasting_ability", "missing") == "")
	var player: Dictionary = PlayerStore.new().normalize_character({
		"spellcasting_ability": "wis", "concentrating_spell_id": "bless",
		"conditions": ["concentrating"]
	})
	assert(player.get("spellcasting_ability") == "wis")
	assert(player.get("concentrating_spell_id") == "bless")
	var monster: Dictionary = MonsterStore.new().normalize_creature({
		"stat_block": {"name": "Goblin"}, "spellcasting_ability": "cha",
		"concentrating_spell_id": "bless", "conditions": ["concentrating"]
	})
	assert(monster.get("spellcasting_ability") == "cha")
	assert(monster.get("concentrating_spell_id") == "bless")
	var summary: Label = tab.get("_spell_summary")
	assert(summary != null and "nessuna" in summary.text)
	var stats: Array[Node] = tab._view.find_children("CastingStatistics", "Label", true, false)
	assert(not stats.is_empty(), "Each spellcasting class has a visible casting statistics label")
	assert(stats.any(func(node: Node) -> bool:
		return "Modificatore: +6" in (node as Label).text and "CD: 14" in (node as Label).text),
		"Class-specific Modifier and DC use the caster's own ability.")
	var abilities: Array[Node] = tab._view.find_children("CastingAbility", "OptionButton", true, false)
	assert(abilities.any(func(node: Node) -> bool:
		return String((node as OptionButton).get_selected_metadata()) == "int"),
		"Ability is represented once, in the section selector")
	assert(summary.get_parent() == tab._drop_concentration_button.get_parent(),
		"End concentration belongs beside the active spell name")

	record["concentrating_spell_id"] = "test_spell"
	record["conditions"] = ["concentrating"]
	tab.refresh_spell_state(record)
	assert("test_spell" in summary.text and "Concentrazione:" in summary.text)
	tab.call("_drop_concentration")
	assert(sink.last_change.get("concentrating_spell_id", "missing") == "")
	assert(not ("concentrating" in sink.last_change.get("conditions", [])))
	record["concentrating_spell_id"] = ""
	record["conditions"] = []
	tab.refresh_spell_state(record)
	assert("nessuna" in summary.text)
	tab.queue_free()
	sink.queue_free()
	print("PASS: spell duration filtering, concentration detection and casting header")
	quit()
