extends SceneTree

const Metadata = preload("res://vtt/monster_action_metadata.gd")
const MonsterTraits = preload("res://vtt/monster_trait_projection.gd")
const Actions = preload("res://vtt/creature_action_economy_tab.gd")
const Trackers = preload("res://vtt/structured_resource_trackers.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/monster_traits.json"))
	record.stat_block = Metadata.prepare(record.stat_block)
	assert(record.stat_block.action[0].vtt_attacks_per_action == 3)
	assert(Actions.attack_action_summary(record).count == 3)
	var edited: Dictionary = record.stat_block.duplicate(true)
	edited.action[0].entries = ["The creature can use its special ability. It then makes two attacks."]
	edited = Metadata.prepare(edited)
	assert(edited.action[0].vtt_attacks_per_action == 2, "Changing the description invalidates the derived count")
	var entries: Array[Dictionary] = Actions.entries(record)
	var trackers: Array[Dictionary] = Trackers.for_creature(record)
	for index: int in [4, 5]:
		var parents: Array[Dictionary] = entries.filter(func(row: Dictionary) -> bool: return row.get("id", "") == "monster:action:%d" % index)
		assert(parents.size() == 1)
		var parent: Dictionary = parents[0]
		assert(parent.options.size() == 2)
		assert(parent.tracker_id == "recharge:action:%d" % index and parent.cost == 1)
		assert(trackers.filter(func(row: Dictionary) -> bool: return row.id == parent.tracker_id).size() == 1)
		for option: Dictionary in parent.options:
			assert(not entries.any(func(row: Dictionary) -> bool: return row.get("name", "") == option.name))
	var breath: Dictionary = entries.filter(func(row: Dictionary) -> bool: return row.get("id", "") == "monster:action:4")[0]
	assert(breath.options[0].name == "Cold Breath" and breath.options[1].name == "Paralyzing Breath")
	var ordinary: Dictionary = {"kind": "monster", "stat_block": {"action": [{"name": "Ordinary choices", "entries": record.stat_block.action[4].entries}]}}
	assert(MonsterTraits.traits(ordinary)[0].monster_actions[0].options.is_empty())
	var tab = Actions.new()
	root.add_child(tab)
	await process_frame
	tab.load_record(record)
	tab._show_entry(breath)
	var picker: OptionButton = tab.find_child("MonsterActionOptions", true, false)
	var detail: RichTextLabel = tab.find_child("MonsterActionOptionDescription", true, false)
	assert(picker != null and picker.item_count == 2 and detail != null)
	picker.select(1)
	picker.item_selected.emit(1)
	assert("paralyzing gas" in detail.text and "icy blast" not in detail.text)
	tab.queue_free()
	print("PASS: generic rechargeable alternatives share one pool; Multiattack excludes optional special actions")
	quit()
