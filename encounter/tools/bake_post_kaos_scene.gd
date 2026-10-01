extends SceneTree

const SOURCE_SCENE := "res://encounter/kaos_klothis.tscn"
const OUTPUT_SCENE := "res://encounter/post_kaos_editable.scn"
const PostKaosHelpers = preload("res://encounter/post_kaos_helpers.gd")

const RUNTIME_ONLY_PATHS: Array[String] = [
	"EncounterProgressController",
	"HazardController",
	"HazardAllowedArea",
	"EnvironmentCollapseController",
	"Scenery",
	"KaosPositions",
	"UI/EncounterUI",
	"SealController",
]

const KAOS_HELPER_SCRIPTS: Array[String] = [
	"res://encounter/kaos_climb.gd",
	"res://encounter/kaos_motion.gd",
]

func _initialize() -> void:
	call_deferred("_bake")


func _bake() -> void:
	var source: PackedScene = load(SOURCE_SCENE)
	if source == null:
		_fail("Cannot load %s" % SOURCE_SCENE)
		return

	var scene := source.instantiate()
	root.add_child(scene)

	# Let the normal encounter build all procedural geometry once.
	await process_frame
	await physics_frame
	await process_frame

	var progress := scene.get_node_or_null("EncounterProgressController")
	var kaos := scene.get_node_or_null("KaosRoot")
	if progress == null or kaos == null:
		_fail("Encounter did not initialize the expected controller nodes.")
		return

	var climb: Node = kaos.get("climb")
	var petrification: Node = progress.get("petrification")
	if not is_instance_valid(climb) or not is_instance_valid(petrification):
		_fail("Encounter did not prepare Kaos climb/petrification state.")
		return

	# Freeze exactly the state used by the live encounter after Kaos reaches
	# Klothis, finishes the jump/climb, and the giant body is petrified.
	climb.call("restore_phase_two")
	progress.set("kaos_step", 0)
	progress.set("encounter_phase", 2)
	progress.set("giant_hp", 0.0)
	progress.set("giant_petrified", true)
	progress.set("damage_since_last_advance", 0.0)
	progress.set("kaos_slowed", false)
	progress.set("obstacle_slowed", false)
	var hazards: Node = progress.get("hazards")
	if is_instance_valid(hazards):
		var threatened: Array = hazards.get("threatened_cells")
		threatened.clear()
	petrification.call("apply", false)
	PostKaosHelpers.remove_kaos_phase_two_token(scene)
	PostKaosHelpers.close_kaos_petrification_hole(scene)

	# open_head_space() uses a deferred collision update.
	await physics_frame
	await process_frame

	# Keep the normal VTT base controls, but remove the phase-one encounter
	# state machine. All scenery/characters that were generated at startup
	# remain as real nodes and resources in the baked scene.
	for path in RUNTIME_ONLY_PATHS:
		_free_path(scene, path)

	_strip_kaos_runtime(kaos)
	PostKaosHelpers.clear_baked_tokens(scene)
	PostKaosHelpers.remove_legacy_platforms(scene)
	PostKaosHelpers.ensure_body_collisions(scene)
	_strip_dnd_runtime(scene)
	_restore_base_ui(scene)

	# The volumetric grid is runtime visualization. Keep its controller node,
	# but do not bake a stale frame of generated grid geometry.
	var grid := scene.get_node_or_null("VolumetricGrid")
	if grid != null:
		for child in grid.get_children():
			child.free()

	scene.name = "PostKaosEncounter"
	scene.set_meta("baked_from", SOURCE_SCENE)
	scene.set_meta("baked_state", "post_jump_petrified")
	scene.set_meta("editor_editable_environment", true)
	scene.set_script(load("res://encounter/post_kaos_scene.gd"))

	# Runtime-created children have no owner. Assigning the scene root makes
	# them persistent and directly editable in the Godot 3D editor.
	_make_owned(scene, scene)

	var packed := PackedScene.new()
	var pack_error := packed.pack(scene)
	if pack_error != OK:
		_fail("PackedScene.pack failed with error %s" % pack_error)
		return

	var save_error := ResourceSaver.save(packed, OUTPUT_SCENE, ResourceSaver.FLAG_COMPRESS)
	if save_error != OK:
		_fail("ResourceSaver.save failed with error %s" % save_error)
		return

	print("Baked editable post-Kaos scene: %s" % OUTPUT_SCENE)
	quit(0)


func _strip_kaos_runtime(kaos: Node) -> void:
	for child in kaos.get_children().duplicate():
		var script: Script = child.get_script()
		if script != null and script.resource_path in KAOS_HELPER_SCRIPTS:
			child.free()
	kaos.set_script(null)


func _strip_dnd_runtime(scene: Node) -> void:
	var runtime_scripts: Array[String] = [
		"res://interaction/token_drag.gd",
		"res://network/board_sync.gd",
		"res://vtt/spells/spell_system.gd",
		"res://vtt/initiative_tracker.gd",
		"res://vtt/token_list.gd",
		"res://vtt/runtime_toolbar.gd",
	]
	for child in scene.get_children().duplicate():
		if child.name in [
			"SelectedTokenGridHighlight",
			"AffectedTokenGridHighlight",
		]:
			child.free()
			continue
		var script: Script = child.get_script()
		if script != null and script.resource_path in runtime_scripts:
			child.free()

func _restore_base_ui(scene: Node) -> void:
	var ui := scene.get_node_or_null("UI")
	if ui == null:
		return
	var keep_ui := [
		"Crosshair",
		"MeasurementModeLabel",
		"ContextMenu",
		"TokenColorDialog",
	]
	for child in ui.get_children().duplicate():
		if String(child.name) not in keep_ui:
			child.free()

	var context_menu := ui.get_node_or_null("ContextMenu")
	if context_menu != null:
		for child in context_menu.get_children().duplicate():
			child.free()

	var content := ui.get_node_or_null("TokenColorDialog/Content/VBox")
	if content != null:
		for child in content.get_children().duplicate():
			if String(child.name) not in ["SizeLabel", "SizeSelector"]:
				child.free()

func _free_path(scene: Node, path: String) -> void:
	var node := scene.get_node_or_null(path)
	if node != null:
		node.free()


func _make_owned(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		_make_owned(child, scene_root)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
