extends SceneTree

const SCENE_PATH := "res://encounter/post_kaos_editable.scn"
const PostKaosHelpers = preload("res://encounter/post_kaos_helpers.gd")


func _initialize() -> void:
	call_deferred("_upgrade")


func _upgrade() -> void:
	var source: PackedScene = load(SCENE_PATH)
	if source == null:
		_fail("Cannot load existing %s" % SCENE_PATH)
		return

	var scene := source.instantiate()
	if scene == null:
		_fail("Cannot instantiate existing post-Kaos scene.")
		return

	PostKaosHelpers.remove_kaos_phase_two_token(scene)
	PostKaosHelpers.remove_legacy_platforms(scene)
	PostKaosHelpers.prepare_kaos_petrified_geometry(scene)
	PostKaosHelpers.restore_encounter_decor(scene)
	PostKaosHelpers.ensure_solid_surfaces(scene)

	var grid := scene.get_node_or_null("VolumetricGrid")
	if grid != null:
		grid.set(
			"collision_mask",
			PostKaosHelpers.RIGHT_ARM_GRID_LAYER
		)
		# The rendered MultiMesh is runtime-only and must be rebuilt from the
		# dedicated right-arm proxy when the scene starts.
		for child in grid.get_children().duplicate():
			child.free()

	var measurement := scene.get_node_or_null("MeasurementTool")
	if measurement != null:
		measurement.set("collision_mask", 1 | 4)

	scene.set("grid_visible_on_start", true)
	scene.set_meta("baked_state", "post_jump_petrified")
	scene.set_meta("editor_editable_environment", true)
	scene.set_meta("post_kaos_incremental_upgrade", true)

	_make_owned(scene, scene)

	var packed := PackedScene.new()
	var pack_error := packed.pack(scene)
	if pack_error != OK:
		_fail("PackedScene.pack failed with error %s" % pack_error)
		return

	var save_error := ResourceSaver.save(
		packed,
		SCENE_PATH,
		ResourceSaver.FLAG_COMPRESS
	)
	if save_error != OK:
		_fail("ResourceSaver.save failed with error %s" % save_error)
		return

	print("Upgraded editable post-Kaos scene: %s" % SCENE_PATH)
	quit(0)


func _make_owned(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		_make_owned(child, scene_root)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
