extends SceneTree

const PublicStatus = preload("res://vtt/creature_public_status.gd")
const StandaloneScene = preload("res://vtt/standalone/creatures_standalone.tscn")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var private_record := {
		"linked_token_sync_id": "token_for_test",
		"conditions": ["poisoned"],
		"current_hp": 35,
		"max_hp": 70,
		"temporary_hp": 5,
		"concentrating_spell_id": "",
		"stat_block": {"secret": "DO_NOT_SHARE"}
	}
	var status: Dictionary = PublicStatus.from_record(private_record)
	assert(status.get("token_id") == "token_for_test")
	assert(is_equal_approx(float(status.get("hp_percent")), 50.0))
	assert(status.get("conditions") == ["poisoned"])
	assert(not JSON.stringify(status).contains("DO_NOT_SHARE"))
	assert(not status.has("current_hp") and not status.has("max_hp"))
	assert(PublicStatus.from_record({}).is_empty())
	private_record["second_form_hp"] = 8
	private_record["second_form_max_hp"] = 20
	assert(is_equal_approx(float(PublicStatus.from_record(private_record)["hp_percent"]), 40.0))

	var standalone: Control = StandaloneScene.instantiate() as Control
	assert(standalone != null)
	root.add_child(standalone)
	await process_frame
	assert(standalone.get_node_or_null("DiceRollerChat") != null)
	assert(standalone.get_node_or_null("Compendio") != null)
	assert(standalone.get_node_or_null("CreatureArea") != null)
	assert(standalone.dice_roller.sync == null, "Offline dice roller must not open a network listener")
	assert(standalone.get_node("CreatureArea").get_public_status_entries() is Array)
	var scene_nodes: Array = root.find_children("*", "Node3D", true, false)
	assert(scene_nodes.is_empty(), "Standalone creature scene instantiated a 3D world")
	standalone.queue_free()
	await process_frame
	print("PASS: standalone creature systems, offline dice and public status")
	quit()
