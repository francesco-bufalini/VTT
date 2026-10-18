extends SceneTree
const Tab = preload("res://vtt/creature_spellcasting_tab.gd")
var captured: Dictionary = {}
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(1000, 900)
	root.title = "VTT - Metamagia (dati di prova)"
	var tab := Tab.new()
	tab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(tab)
	tab.setup(func(_values: Dictionary) -> void: pass, func(_message: String) -> void: pass,
		func(spell: Dictionary, _level: int, _grant: Dictionary = {}) -> bool:
			captured = spell.duplicate(true)
			return false)
	var record := {"kind": "character", "rules_version": "2014", "classes": [{"name": "Sorcerer", "source": "PHB", "level": 6}], "abilities": {"cha": 18}, "optional_features_catalog": [{"name": "Distant Spell", "source": "PHB"}, {"name": "Subtle Spell", "source": "PHB"}], "spell_slots_total": [0, 4, 3, 3, 0, 0, 0, 0, 0, 0], "resource_tracker_spent": {}}
	tab.load_record(record)
	var spell := {"id": "fixture_spell", "name": "Incantesimo di prova", "level": 1, "casting_time": "1 action", "range_feet": 60, "range": "60 feet", "duration": "Instantaneous", "description": "Scegli le opzioni di Metamagia per questo lancio."}
	tab._view_cast_class(spell, {"id": "class|phb|sorcerer", "name": "Sorcerer"})
	assert(tab._metamagic_checks.size() == 2)
	assert(tab._cast_dialog.visible)
	tab._metamagic_checks[0].button_pressed = true
	if "--visual" in OS.get_cmdline_user_args(): return
	tab._confirm_cast_spell()
	assert(captured.metamagic.names == ["Distant Spell"])
	assert(int(tab._spent[1]) == 0 and tab._record.resource_tracker_spent.is_empty(), "A rejected dispatch must not charge points or slots")
	tab.queue_free()
	await process_frame
	print("PASS: metamagic dialog exposes selected options and rejected dispatch leaves resources unchanged")
	quit()
