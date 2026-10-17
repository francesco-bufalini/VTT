extends SceneTree
const Actions = preload("res://vtt/creature_action_economy_tab.gd")
const Area = preload("res://vtt/creature_area.gd")
const Catalog = preload("res://vtt/spells/spell_catalog.gd")
func _initialize() -> void: call_deferred("run")
func spell(id: String, unit: String) -> Dictionary:
	return {"id": id, "name": id, "level": 1, "time": [{"unit": unit, "number": 1}], "entries": ["Descrizione di prova"]}
func groups(tab: Control) -> Array:
	var found: Array = []
	for section: VBoxContainer in tab._sections:
		for node: Node in section.get_children():
			if node.has_meta("action_entry"):
				var entry: Dictionary = node.get_meta("action_entry")
				if String(entry.get("id", "")).begins_with("spells_"): found.append(entry)
	return found
func run() -> void:
	root.gui_embed_subwindows = true
	var tab := Actions.new()
	tab._options_path = "user://spell_group_test_%d.cfg" % Time.get_ticks_usec()
	root.add_child(tab)
	tab.size = Vector2(846, 700)
	tab.load_record({})
	assert(groups(tab).is_empty(), "No empty spell group may appear")
	var action := spell("spell_fixture_action", "action")
	var bonus := spell("spell_fixture_bonus", "bonus")
	var reaction := spell("spell_fixture_reaction", "reaction")
	var slow := spell("spell_fixture_slow", "minute")
	var book := spell("spell_fixture_book", "action")
	var record := {"prepared_spells": [action, bonus, reaction, slow], "spells": [action], "spellbook_spells": [book]}
	tab.load_record(record)
	var found := groups(tab)
	assert(found.size() == 3)
	for entry: Dictionary in found:
		assert(int(entry["time"]) in [0, 1, 4])
		assert(entry["children"].size() == 1, "Legacy duplicate selections are not duplicated; spellbook-only spells stay out")
		var child: Dictionary = entry["children"][0]
		assert(child["time"] == entry["time"])
		assert(String(child["tracker"]).contains("Slot"))
	tab.load_record({"prepared_spells": [bonus]})
	assert(groups(tab).size() == 1 and groups(tab)[0]["time"] == 1, "Groups disappear independently when their last spell is removed")
	# Actual catalogue IDs and origin trackers must survive projection.
	var shield: Dictionary = {}
	for candidate: Dictionary in Catalog.all_spells_for_rules("2014"):
		if String(candidate.get("name", "")).to_lower() == "shield" and candidate.get("source", "") == "PHB":
			shield = candidate; break
	assert(not shield.is_empty())
	var grant_record := {"proficiency_origins": [{"id": "custom:test", "name": "Dono", "group": "custom"}],
		"resource_trackers": [{"id": "charges", "name": "Cariche bacchetta", "max": 3}],
		"origin_spell_grants": [{"id": "wand_shield", "origin_id": "custom:test", "spell_id": shield["id"], "tracker_id": "charges", "payment_mode": "tracker"}]}
	var granted := Actions.spell_entries(grant_record)
	assert(granted.size() == 1 and granted[0]["time"] == 4, JSON.stringify({"granted": granted, "time": shield.get("time"), "casting_time": shield.get("casting_time"), "grants": Actions.OriginSpells.all_grants(grant_record), "id": shield.get("id"), "catalogue": Catalog.catalog_spell(shield.get("id", ""))}))
	assert(granted[0]["tracker_id"] == "charges" and granted[0]["grant_id"] == "wand_shield")
	assert(granted[0]["tracker"] == "Cariche bacchetta")
	var multiclass := {"classes": [{"name": "Wizard", "source": "PHB", "level": 3}, {"name": "Sorcerer", "source": "PHB", "level": 3}], "prepared_spells": [{"id": shield["id"], "casting_classes": ["class|phb|wizard", "class|phb|sorcerer"]}]}
	var rows := Actions.spell_entries(multiclass)
	assert(rows.size() == 2 and rows[0]["class_id"] != rows[1]["class_id"])
	# The real eight-tab strip must fit its normal archive width with full titles.
	var area := Area.new()
	root.add_child(area)
	area._tabs = TabContainer.new()
	root.add_child(area._tabs)
	area._tabs.theme = preload("res://vtt/creature_sheet_style.gd").sheet_theme()
	area._tabs.size = Vector2(846, 600)
	for title: String in ["Info", "Statistiche", "Cosa posso fare?", "Poteri", "Inventario", "Tratti", "Condizioni", "Modifica personaggio"]:
		area._add_sheet_tab(area._tabs, title)
	for i: int in range(4): await process_frame
	area._fit_sheet_tabs()
	await process_frame
	var bar := area._tabs.get_tab_bar()
	assert(bar.get_tab_rect(7).end.x <= bar.size.x, "Every desktop tab must fit without horizontal scrolling")
	assert(area._tabs.get_tab_title(7) == "Modifica personaggio")
	area._tabs.queue_free()
	area.queue_free()
	tab.queue_free()
	print("PASS: conditional action/bonus/reaction spell groups, source resources, class identities and all desktop tabs visible")
	quit(0)
