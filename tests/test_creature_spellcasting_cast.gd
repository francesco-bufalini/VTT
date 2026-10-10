extends SceneTree

const SpellcastingTab = preload("res://vtt/creature_spellcasting_tab.gd")


class CastSink extends Node:
	var calls: Array[Dictionary] = []
	var updates: Array[Dictionary] = []
	var accept_cast: bool = true

	func cast_requested(spell: Dictionary, slot_level: int) -> bool:
		calls.append({"id": spell.get("id", ""), "slot_level": slot_level})
		return accept_cast

	func changed(values: Dictionary) -> void:
		updates.append(values.duplicate(true))

	func status(_message: String) -> void:
		pass


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var sink := CastSink.new()
	root.add_child(sink)
	var tab: VBoxContainer = SpellcastingTab.new()
	root.add_child(tab)
	tab.call("setup",
		Callable(sink, "changed"),
		Callable(sink, "status"),
		Callable(sink, "cast_requested")
	)
	tab.call("load_record", {
		"rules_version": "2014",
		"spell_slots_total": [0, 0, 2, 0, 0, 0, 0, 0, 0, 0],
		"spell_slots_spent": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
		"pact_slots_total": 1,
		"pact_slot_level": 2
	})
	var spell := {"id": "regression_spell", "name": "Test Spell", "level": 2}
	# A confirmed normal slot is consumed exactly once and is persisted.
	tab.call("_dispatch_cast", spell, 2)
	assert(sink.calls.size() == 1 and sink.calls[0].slot_level == 2)
	assert(int((tab.get("_spent") as Array)[2]) == 1)
	assert(not sink.updates.is_empty())
	assert(int((sink.updates.back().get("spell_slots_spent") as Array)[2]) == 1)
	# No-slot casting still calls the handler at the spell's base level.
	tab.call("_dispatch_cast", spell, 0)
	assert(sink.calls.size() == 2 and sink.calls[1].slot_level == 2)
	assert(int((tab.get("_spent") as Array)[2]) == 1)
	# Pact resources are distinct from ordinary slot resources.
	tab.call("_dispatch_cast", spell, 102)
	assert(sink.calls.size() == 3 and int(tab.get("_pact_spent")) == 1)
	tab.call("_dispatch_cast", spell, 102)
	assert(sink.calls.size() == 3, "An exhausted pact slot must not cast")
	# An invalid level or a declined cast must not spend any resource.
	tab.call("_dispatch_cast", spell, 1)
	assert(sink.calls.size() == 3)
	sink.accept_cast = false
	tab.call("_dispatch_cast", spell, 2)
	assert(int((tab.get("_spent") as Array)[2]) == 1)
	# Cantrips cast immediately with level zero and do not spend slots.
	sink.accept_cast = true
	tab.call("_dispatch_cast", {"id": "test_cantrip", "level": 0}, 0)
	assert(sink.calls.back().slot_level == 0)
	assert(int((tab.get("_spent") as Array)[2]) == 1)
	# Selecting any source enables the same cast button.
	var available: ItemList = tab.get("_available") as ItemList
	available.add_item("Test Cantrip")
	available.select(0)
	tab.set("_visible", [{"id": "test_cantrip", "name": "Test Cantrip", "level": 0}])
	tab.call("_update_spell_controls")
	var cast_button: Button = tab.get("_cast_button") as Button
	assert(not cast_button.disabled)
	var before_available: int = (tab.get("_prepared") as Array).size()
	tab.call("_on_spell_activated", "catalog", 0)
	assert(sink.calls.back().id == "test_cantrip" and sink.calls.back().slot_level == 0)
	assert((tab.get("_prepared") as Array).size() == before_available,
		"Double-clicking a catalog spell must not add/remove it from available spells")
	var known_list: ItemList = tab.get("_known_list") as ItemList
	known_list.add_item("Known Cantrip")
	tab.set("_displayed_known", [{"id": "known_cantrip", "name": "Known Cantrip", "level": 0}])
	tab.call("_on_spell_activated", "known", 0)
	assert(sink.calls.back().id == "known_cantrip",
		"Double-clicking a class spell must cast instead of preparing it")
	var prepared_list: ItemList = tab.get("_prepared_list") as ItemList
	prepared_list.add_item("Prepared Cantrip")
	tab.set("_prepared", [{"id": "prepared_cantrip", "name": "Prepared Cantrip", "level": 0}])
	tab.call("_on_spell_activated", "prepared", 0)
	assert(sink.calls.back().id == "prepared_cantrip",
		"Double-clicking an available spell must cast instead of removing it")
	assert((tab.get("_prepared") as Array).size() == 1,
		"Double-clicking must leave the prepared list unchanged")
	assert(cast_button.get_parent() == tab.get("_search_toggle").get_parent()
		and (tab.get("_prepare") as Button).get_parent() == cast_button.get_parent(),
		"Add/remove and cast buttons must stay in the same row as search")
	tab.queue_free()
	sink.queue_free()
	print("PASS: selected spell casting, ordinary/pact/no-slot use and cantrips")
	quit()
