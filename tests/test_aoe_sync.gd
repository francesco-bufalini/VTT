extends SceneTree

const SpellCatalog = preload("res://vtt/spells/spell_catalog.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# 5eTools-backed spell catalogue: only spells with real VTT map effects
	# remain exposed while animations are disabled.
	var flame_strike: Dictionary = SpellCatalog.spell("flame_strike")
	assert(not flame_strike.is_empty())
	assert(String(flame_strike.get("target_mode", "")) == "token_then_point")
	assert(String(flame_strike.get("aoe_shape", "")) == "cylinder")
	assert(float(flame_strike.get("aoe_radius_feet", 0.0)) == 10.0)
	assert(float(flame_strike.get("aoe_height_feet", 0.0)) == 40.0)

	var silence: Dictionary = SpellCatalog.spell("silence")
	assert(not silence.is_empty())
	assert(String(silence.get("aoe_shape", "")) == "sphere")
	assert(float(silence.get("aoe_radius_feet", 0.0)) == 20.0)
	assert(bool(silence.get("persistent", false)))

	var entangle: Dictionary = SpellCatalog.spell("entangle")
	assert(not entangle.is_empty())
	assert(String(entangle.get("aoe_shape", "")) == "flat_square")
	assert(float(entangle.get("aoe_side_feet", 0.0)) == 20.0)
	assert(bool(entangle.get("persistent", false)))

	var call_lightning: Dictionary = SpellCatalog.spell("call_lightning")
	assert(not call_lightning.is_empty())
	assert(String(call_lightning.get("target_mode", "")) == "token_then_point")
	assert(String(call_lightning.get("aoe_shape", "")) == "cylinder")

	# Projectile-only / condition-only spells have no map effect with spell
	# animations disabled and must therefore not survive catalogue pruning.
	assert(SpellCatalog.spell("guiding_bolt").is_empty())
	assert(SpellCatalog.spell("magic_missile").is_empty())

	for spell_data: Dictionary in SpellCatalog.all_spells():
		var mode: String = String(spell_data.get("target_mode", ""))
		var shape: String = String(spell_data.get("aoe_shape", ""))
		var usable: bool = (
			mode == "teleport_self"
			or mode == "wall_design"
			or (
				not shape.is_empty()
				and mode in [
					"self_token",
					"self_emanation",
					"token_then_point",
					"token_then_direction"
				]
			)
			or (
				mode == "token_then_token"
				and (
					bool(spell_data.get("persistent_link", false))
					or float(
						spell_data.get("impact_aoe_radius_feet", 0.0)
					) > 0.0
				)
			)
		)
		assert(usable)

	var scene: Node = load("res://dnd_base.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var measure: Node = scene.measurement_tool
	for shape in ["sphere", "cube", "cone", "line", "cylinder"]:
		measure.add_aoe(Vector3(1,2,3), Vector3(4,2,3), shape)
	measure.add_aoe(
		Vector3(2, 0, 2),
		Vector3(6, 0, 2),
		"sphere",
		"cloudkill",
		Color(0.0, 0.0, 0.0, -1.0),
		-1.0,
		10.0,
		"away_from_caster",
		Vector3.ZERO
	)
	assert(measure.serialize_persistent_aoes().size() == 6)
	var data: Array = JSON.parse_string(JSON.stringify(measure.serialize_persistent_aoes()))
	measure.clear_persistent_aoes()
	measure.apply_persistent_aoes(data)
	assert(measure.serialize_persistent_aoes() == data)
	assert(not measure.valid_aoes([{"shape":"sphere", "start":[], "end":[]}]))
	var sync: Node = scene.board_sync
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sync.create_snapshot()))
	assert(sync.valid_snapshot(snapshot))
	assert(sync.apply_snapshot(snapshot))
	# The transfer must also work above the maximum size of a single UDP packet.
	for i in range(250):
		measure.add_aoe(Vector3(i, 2, 3), Vector3(i + 2, 2, 3), "sphere")
	for i in range(200):
		var token: Node3D = load("res://token.tscn").instantiate()
		scene.tokens_root.add_child(token)
		token.position = Vector3(i + 0.25, 5.0, 0.75)
		token.set_flying(true)
	snapshot = JSON.parse_string(JSON.stringify(sync.create_snapshot()))
	assert(JSON.stringify(snapshot).to_utf8_buffer().size() > 65507)
	assert(not sync.apply_snapshot({"version":3}))
	var duplicate: Dictionary = snapshot.duplicate(true)
	if not duplicate.objects.is_empty():
		duplicate.objects.append(duplicate.objects[0])
		assert(not sync.valid_snapshot(duplicate))
	var other: Node = load("res://dnd_base.tscn").instantiate()
	root.add_child(other)
	await process_frame
	assert(sync.create_snapshot().objects.size() == snapshot.objects.size())
	assert(other.board_sync.listen(true, "test-key") == OK)
	assert(sync.send_snapshot("127.0.0.1", "test-key") == OK)
	for frame in range(300):
		await create_timer(0.01).timeout
		if other.measurement_tool.serialize_persistent_aoes().size() == 256:
			break
	assert(other.measurement_tool.serialize_persistent_aoes().size() == 256)
	assert(other.tokens_root.get_child_count() == scene.tokens_root.get_child_count())
	assert(other.tokens_root.get_child(0).position == scene.tokens_root.get_child(0).position)
	other.measurement_tool.clear_persistent_aoes()
	assert(sync.send_snapshot("127.0.0.1", "wrong-key") == OK)
	await create_timer(0.4).timeout
	assert(other.measurement_tool.serialize_persistent_aoes().is_empty())
	scene.queue_free()
	other.queue_free()
	await process_frame
	print("PASS: AoE cylinder/movable round-trip, validation, scene isolation, TCP transfer, wrong key rejection")
	quit()


