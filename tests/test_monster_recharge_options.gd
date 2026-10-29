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
	assert(record.stat_block.action[0].vtt_attacks_per_action == 4)
	assert(Actions.attack_action_summary(record).count == 4)
	var legacy: Dictionary = record.stat_block.action[0].duplicate(true)
	legacy["attacks_per_action"] = 3
	assert(Metadata.multiattack_count(legacy) == 4, "The old generated three-count migrates to the full routine")
	legacy["attacks_per_action"] = 7
	assert(Metadata.multiattack_count(legacy) == 7, "An explicit custom count keeps precedence")
	var edited: Dictionary = record.stat_block.duplicate(true)
	edited.action[0].entries = ["The creature can use its special ability. It then makes two attacks."]
	edited = Metadata.prepare(edited)
	assert(edited.action[0].vtt_attacks_per_action == 3, "Changing the description invalidates the derived count")
	var entries: Array[Dictionary] = Actions.entries(record)
	var trackers: Array[Dictionary] = Trackers.for_creature(record)
	for index: int in [4, 5]:
		var variants: Array[Dictionary] = entries.filter(func(row: Dictionary) -> bool: return row.get("parent_action_id", "") == "monster:action:%d" % index)
		assert(variants.size() == 2)
		assert(not entries.any(func(row: Dictionary) -> bool: return row.get("id", "") == "monster:action:%d" % index))
		for variant: Dictionary in variants:
			assert(variant.get("options", []).is_empty())
			assert(variant.tracker_id == "recharge:action:%d" % index and variant.cost == 1)
			assert(trackers.filter(func(row: Dictionary) -> bool: return row.id == variant.tracker_id).size() == 1)
	var breath: Dictionary = entries.filter(func(row: Dictionary) -> bool: return row.get("name", "") == "Cold Breath")[0]
	var lair: Array[Dictionary] = entries.filter(func(row: Dictionary) -> bool: return row.get("aggregate_lair", false))
	assert(lair.size() == 1)
	for expected: String in ["Lava", "Smoke", "Additional Lair Actions", "Frozen Floor", "Ice covers"]:
		assert(expected in lair[0].detail)
	var ordinary: Dictionary = {"kind": "monster", "stat_block": {"action": [{"name": "Ordinary choices", "entries": record.stat_block.action[4].entries}]}}
	assert(MonsterTraits.traits(ordinary)[0].monster_actions[0].options.is_empty())
	var tab = Actions.new()
	root.add_child(tab)
	await process_frame
	tab.load_record(record)
	tab._show_entry(breath)
	var picker: OptionButton = tab.find_child("MonsterActionOptions", true, false)
	var detail: RichTextLabel = tab.find_child("MonsterActionOptionDescription", true, false)
	assert(picker == null and detail == null)
	assert("icy blast" in breath.detail and "paralyzing gas" not in breath.detail)
	tab.queue_free()
	print("PASS: distinct recharge capabilities, unified complete lair description and full Multiattack routine")
	quit()
