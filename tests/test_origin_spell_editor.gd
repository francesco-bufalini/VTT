extends SceneTree

const Editor = preload("res://vtt/creature_origin_spells_tab.gd")
const Structured = preload("res://vtt/structured_origin_spells_5etools.gd")
const Grants = preload("res://vtt/origin_spell_grants.gd")
const PlayerStore = preload("res://vtt/player_character_store.gd")
const MasterStore = preload("res://vtt/master_creature_store.gd")

class Listener extends Node:
	var updates: Array = []
	func changed(grants: Array, configs: Dictionary) -> void:
		updates.append({"grants": grants.duplicate(true), "configs": configs.duplicate(true)})

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var initiate: Dictionary = {
		"kind": "character", "level": 1, "rules_version": "2014",
		"feats_catalog": [{"name": "Magic Initiate", "source": "PHB"}]
	}
	var structured: Dictionary = Structured.for_creature(initiate)
	var choices: Array = structured.get("choices", [])
	assert(choices.size() == 2,
		"Magic Initiate must produce exactly TWO choice groups, not 6x their count")
	var totals: Array[int] = [0, 0]
	for raw: Variant in choices:
		if raw is Dictionary:
			var group: Dictionary = raw
			if "level=0" in String(group.get("filter", "")):
				totals[0] = int(group.get("count", 0))
			elif "level=1" in String(group.get("filter", "")):
				totals[1] = int(group.get("count", 0))
	assert(totals == [2, 1], "Magic Initiate grants only two cantrips and one 1st-level spell")
	var scion: Dictionary = {"kind": "character", "level": 1,
		"feats_catalog": [{"name": "Scion of the Outer Planes", "source": "SatO"}]}
	var scion_data: Dictionary = Structured.for_creature(scion)
	assert((scion_data.get("grants", []) as Array).is_empty(),
		"Alternative fixed cantrips cannot all be granted at once")
	var scion_choices: Array = scion_data.get("choices", [])
	assert(scion_choices.size() == 1
		and int((scion_choices[0] as Dictionary).get("count", 0)) == 1
		and (scion_choices[0] as Dictionary).get("spell_options", []).size() == 5,
		"Scion must select ONE cantrip from five fixed alternatives")
	var source: Dictionary = {
		"kind": "character", "class": "Wizard", "level": 2,
		"origin_spell_configs": {"origin:spell": {
			"payment_mode": "slot", "spellcasting_ability": "wis"}},
		"spell_slots_manual": true,
		"spell_slots_automatic": false
	}
	var normalized: Dictionary = PlayerStore.new().normalize_character(source)
	assert(normalized.get("origin_spell_configs", {}).has("origin:spell")
		and bool(normalized.get("spell_slots_manual", false)),
		"Character reload must preserve per-origin casting ability and slot policy")
	var master: Dictionary = MasterStore.new().normalize_creature(source)
	assert(master.get("origin_spell_configs", {}).has("origin:spell")
		and bool(master.get("spell_slots_manual", false)),
		"Monster reload must preserve per-origin casting config too")
	var listener := Listener.new()
	root.add_child(listener)
	var tab := Editor.new()
	root.add_child(tab)
	tab.setup(Callable(listener, "changed"))
	tab.load_record(initiate)
	assert(tab.get("_spells") != null, "Origin spell editor must appear independently of class spellbook")
	assert(tab.get("_origin_picker").item_count > 0)
	tab.queue_free()
	listener.queue_free()
	print("PASS origin spells editor and unified Magic Initiate choice capacity")
	quit()
