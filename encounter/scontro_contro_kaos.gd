extends "res://encounter/final_encounter.gd"

const PostKaosHelpers = preload("res://encounter/post_kaos_helpers.gd")
const CosmicBackdrop = preload("res://encounter/cosmic_backdrop.gd")

const ImportedPrison = preload("res://encounter/klotis_prison.gd")
const CONTEXT_BREAK_LEFT_SEAL := 120
const CONTEXT_BREAK_RIGHT_SEAL := 121
const CONTEXT_BREAK_FOREHEAD_SEAL := 122
const CONTEXT_RESET_SEALS := 123
var klotis_prison: Node3D

const CHARIOT_OFFSETS_METERS := [
	Vector3(-27.0, 24.0, 70.0),
	Vector3(-9.0, 30.0, 74.0),
	Vector3(9.0, 30.0, 74.0),
	Vector3(27.0, 24.0, 70.0),
]

const HAND_TELEGRAPH_MIN_RADIUS_METERS := 3.0
const HAND_TELEGRAPH_MAX_RADIUS_METERS := 10.0
const HAND_TELEGRAPH_VERTICAL_TOLERANCE_METERS := 8.0
const FOREHEAD_CONE_LENGTH_METERS := 18.0
const FOREHEAD_CONE_RADIUS_FACTOR := 0.5
const TELEGRAPH_SURFACE_OFFSET_METERS := 0.08

var _klothys_attack_visual: MeshInstance3D
var _active_klothys_attack_side: String = ""
var _active_hand_center: Vector3 = Vector3.ZERO
var _active_hand_radius: float = 0.0
var _active_cone_origin: Vector3 = Vector3.ZERO
var _active_cone_direction: Vector3 = Vector3.FORWARD


func _ready() -> void:
	super._ready()
	# The WorldEnvironment sky is sufficient; do not add the local
	# cylindrical starfield that would duplicate the background around the arena.
	CosmicBackdrop.install(self, false)
	_clean_scontro_board()
	_apply_post_kaos_terrain_rules()
	_install_imported_prison()
	_position_starting_group_near_sphere()


func _clean_scontro_board() -> void:
	# Scontro Contro Kaos now starts as a clean tactical board: no spell
	# areas and no creature tokens. Keep exactly one Pegasus/chariot token.
	if measurement_tool != null and is_instance_valid(measurement_tool):
		for method_name: String in [
			"clear_persistent_aoes",
			"clear_post_cast_spell_visuals",
			"clear_spell_fixed_previews",
			"hide_spell_preview",
			"hide_spell_range_preview"
		]:
			if measurement_tool.has_method(method_name):
				measurement_tool.call(method_name)

	_clear_selection()

	var retained_chariot: CharacterBody3D = null
	for child: Node in tokens_root.get_children():
		if (
			retained_chariot == null
			and child is CharacterBody3D
			and bool(child.get_meta("compound_chariot", false))
		):
			retained_chariot = child as CharacterBody3D

	for child: Node in tokens_root.get_children():
		if child == retained_chariot:
			continue
		child.free()

	if retained_chariot == null:
		push_warning(
			"Scontro Contro Kaos: nessun carro alato generato da conservare."
		)
		return

	retained_chariot.name = "PegasusChariot"
	retained_chariot.set_meta("post_kaos_roster", true)
	if retained_chariot.has_method("set_display_name"):
		retained_chariot.call("set_display_name", "Carro alato")


func _apply_post_kaos_terrain_rules() -> void:
	# Port the useful terrain behavior from Campaign Editor Post-Kaos onto
	# Scontro contro Kaos without changing its phase-2 combat controller.
	# Kaos keeps the one-hand pose, but the head and upper neck are removed;
	# the shoulders and neck stump are opaque, real walkable geometry.
	PostKaosHelpers.prepare_scontro_kaos_terrain(self)
	PostKaosHelpers.disable_scontro_legacy_platforms(self)
	PostKaosHelpers.ensure_solid_surfaces(self, true)

	# Scan ordinary solid map layers as well as the dedicated surface shells
	# for Kaos, Klothys and the prison sphere.
	volumetric_grid.collision_mask = (
		PostKaosHelpers.WALKABLE_LAYER
		| 4
		| PostKaosHelpers.RIGHT_ARM_GRID_LAYER
	)
	# The tactical voxel itself is now the authoritative floor for tokens.
	# Keep cells at their natural position: their upper face is guaranteed to
	# sit above the solid geometry that caused the cell to be occupied.
	volumetric_grid.display_offset_cells = Vector3.ZERO
	measurement_tool.collision_mask = 1 | 4
	if volumetric_grid.has_method("refresh"):
		volumetric_grid.call_deferred("refresh")


func _position_starting_group_near_sphere() -> void:
	var units: float = measurement_tool.meters_to_world(1.0)
	var staging_origin: Vector3 = $KaosRoot.global_position
	var chariots: Array[CharacterBody3D] = []

	for node: Node in tokens_root.get_children():
		if (
			node is CharacterBody3D
			and bool(node.get_meta("compound_chariot", false))
		):
			chariots.append(node as CharacterBody3D)

	chariots.sort_custom(
		func(a: CharacterBody3D, b: CharacterBody3D) -> bool:
			return a.global_position.x < b.global_position.x
	)

	for index: int in range(mini(chariots.size(), CHARIOT_OFFSETS_METERS.size())):
		var chariot: CharacterBody3D = chariots[index]
		var deck_value: Variant = chariot.get("deck")
		var deck: Node3D = deck_value as Node3D if deck_value is Node3D else null
		var passengers: Array[Dictionary] = []

		if deck != null:
			for candidate: Node in tokens_root.get_children():
				if not candidate is CharacterBody3D or candidate == chariot:
					continue
				var passenger := candidate as CharacterBody3D
				if passenger.get("grid_support") != deck:
					continue
				passengers.append({
					"token": passenger,
					"local_transform": (
						deck.global_transform.affine_inverse()
						* passenger.global_transform
					)
				})

		chariot.global_position = (
			staging_origin
			+ CHARIOT_OFFSETS_METERS[index] * units
		)

		if deck != null:
			for passenger_data: Dictionary in passengers:
				var passenger := passenger_data.get("token") as CharacterBody3D
				if passenger == null or not is_instance_valid(passenger):
					continue
				var local_transform: Transform3D = passenger_data.get(
					"local_transform",
					Transform3D.IDENTITY
				)
				passenger.global_transform = deck.global_transform * local_transform
				passenger.set("grid_support", deck)
				passenger.set("_support_transform", deck.global_transform)
				passenger.set("velocity", Vector3.ZERO)


func _install_imported_prison() -> void:
	klotis_prison = ImportedPrison.new()
	klotis_prison.name = "KlotisPrison"
	klotis_prison.scene = self
	var visual: Node3D = preload("res://encounter/assets/klotis_prison/klotis_prison.glb").instantiate()
	visual.name = "Visual"
	klotis_prison.add_child(visual)
	add_child(klotis_prison)
	klotis_prison.seal_broken.connect(_on_klothys_seal_broken)
	klotis_prison.arm_walkable.connect(_on_klothys_arm_walkable)
	klotis_prison.head_bowed.connect(_on_klothys_head_bowed)
	volumetric_grid.collision_probe_scale = 0.99
	volumetric_grid.call("_configure_grid")
	volumetric_grid.call_deferred("refresh")


func _process(delta: float) -> void:
	super._process(delta)
	if _active_klothys_attack_side.is_empty():
		return
	if (
		klotis_prison == null
		or not is_instance_valid(klotis_prison)
		or not bool(
			klotis_prison.broken.get(
				_active_klothys_attack_side,
				false
			)
		)
	):
		_clear_klothys_attack_telegraph()
		return
	_refresh_klothys_attack_highlight()


func _on_klothys_seal_broken(side: String) -> void:
	if side == "forehead":
		_show_forehead_cone_telegraph()
	elif side in ["left", "right"]:
		_show_hand_telegraph(side)


func _on_klothys_arm_walkable(side: String) -> void:
	if _active_klothys_attack_side == side:
		_clear_klothys_attack_telegraph()


func _on_klothys_head_bowed() -> void:
	if _active_klothys_attack_side == "forehead":
		_clear_klothys_attack_telegraph()


func _show_hand_telegraph(side: String) -> void:
	_clear_klothys_attack_telegraph()
	var units: float = measurement_tool.meters_to_world(1.0)
	var target: Vector3 = klotis_prison.get_hand_target_position(side)
	if target == Vector3.ZERO:
		return
	_active_klothys_attack_side = side
	_active_hand_center = _project_telegraph_to_surface(target)
	_active_hand_radius = clampf(
		klotis_prison.get_hand_target_radius(side) + cell_size * 0.5,
		HAND_TELEGRAPH_MIN_RADIUS_METERS * units,
		HAND_TELEGRAPH_MAX_RADIUS_METERS * units
	)
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = _active_hand_radius
	cylinder.bottom_radius = _active_hand_radius
	cylinder.height = maxf(0.04 * units, cell_size * 0.04)
	cylinder.radial_segments = 64
	cylinder.material = _klothys_telegraph_material(0.34)
	_replace_klothys_attack_visual(cylinder, _active_hand_center)
	_refresh_klothys_attack_highlight()


func _show_forehead_cone_telegraph() -> void:
	_clear_klothys_attack_telegraph()
	var units: float = measurement_tool.meters_to_world(1.0)
	# Use the forehead location from the END of Klothys' head animation.
	# seal_broken is emitted near the beginning, when her head is still close
	# to the sealed pose, so using the live position would start the cone from
	# the wrong place.
	var origin: Vector3 = klotis_prison.get_forehead_final_world_position()
	var neck_target: Vector3 = (
		klotis_prison.get_petrified_neck_world_position()
	)
	var toward_neck: Vector3 = neck_target - origin
	if toward_neck.length_squared() <= 0.000001:
		return
	_active_klothys_attack_side = "forehead"
	_active_cone_origin = origin
	_active_cone_direction = toward_neck.normalized()
	var length: float = FOREHEAD_CONE_LENGTH_METERS * units
	var radius: float = length * FOREHEAD_CONE_RADIUS_FACTOR
	var cone_mesh := _build_klothys_cone_mesh(
		_active_cone_direction,
		length,
		radius
	)
	_replace_klothys_attack_visual(cone_mesh, _active_cone_origin)
	_refresh_klothys_attack_highlight()


func _replace_klothys_attack_visual(mesh: Mesh, position: Vector3) -> void:
	if _klothys_attack_visual != null and is_instance_valid(_klothys_attack_visual):
		_klothys_attack_visual.free()
	_klothys_attack_visual = MeshInstance3D.new()
	_klothys_attack_visual.name = "KlothysAttackTelegraph"
	_klothys_attack_visual.mesh = mesh
	_klothys_attack_visual.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	add_child(_klothys_attack_visual)
	_klothys_attack_visual.global_position = position


func _klothys_telegraph_material(alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.03, 0.02, alpha)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.015, 0.005, 1.0)
	material.emission_energy_multiplier = 1.4
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	return material


func _build_klothys_cone_mesh(
	direction: Vector3,
	length: float,
	radius: float
) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var material := _klothys_telegraph_material(0.24)
	var right: Vector3 = direction.cross(Vector3.UP)
	if right.length_squared() <= 0.000001:
		right = direction.cross(Vector3.RIGHT)
	right = right.normalized()
	var radial_up: Vector3 = right.cross(direction).normalized()
	var end_center: Vector3 = direction * length
	var segments := 40
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for index in range(segments):
		var angle_a := TAU * float(index) / float(segments)
		var angle_b := TAU * float(index + 1) / float(segments)
		var edge_a := (
			end_center
			+ right * cos(angle_a) * radius
			+ radial_up * sin(angle_a) * radius
		)
		var edge_b := (
			end_center
			+ right * cos(angle_b) * radius
			+ radial_up * sin(angle_b) * radius
		)
		mesh.surface_add_vertex(Vector3.ZERO)
		mesh.surface_add_vertex(edge_a)
		mesh.surface_add_vertex(edge_b)
		mesh.surface_add_vertex(end_center)
		mesh.surface_add_vertex(edge_b)
		mesh.surface_add_vertex(edge_a)
	mesh.surface_end()
	return mesh


func _project_telegraph_to_surface(point: Vector3) -> Vector3:
	var units: float = measurement_tool.meters_to_world(1.0)
	var from := point + Vector3.UP * 20.0 * units
	var to := point - Vector3.UP * 30.0 * units
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = (
		PostKaosHelpers.WALKABLE_LAYER
		| PostKaosHelpers.RIGHT_ARM_GRID_LAYER
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var surface: Vector3 = hit["position"]
		return (
			surface
			+ Vector3.UP * TELEGRAPH_SURFACE_OFFSET_METERS * units
		)
	return point


func _refresh_klothys_attack_highlight() -> void:
	var affected: Array = []
	for node: Node in tokens_root.get_children():
		if not node is CharacterBody3D:
			continue
		var token := node as CharacterBody3D
		if _token_inside_klothys_telegraph(token):
			affected.append(token)
	set_affected_token_highlight(affected)


func _token_inside_klothys_telegraph(token: CharacterBody3D) -> bool:
	var token_radius: float = _token_effect_radius(token)
	if _active_klothys_attack_side in ["left", "right"]:
		var delta: Vector3 = token.global_position - _active_hand_center
		var horizontal: float = Vector2(delta.x, delta.z).length()
		var units: float = measurement_tool.meters_to_world(1.0)
		return (
			horizontal <= _active_hand_radius + token_radius
			and absf(delta.y)
				<= (
					HAND_TELEGRAPH_VERTICAL_TOLERANCE_METERS
					* units
					+ token_radius
				)
		)
	if _active_klothys_attack_side == "forehead":
		var length: float = (
			FOREHEAD_CONE_LENGTH_METERS
			* float(measurement_tool.meters_to_world(1.0))
		)
		var relative: Vector3 = token.global_position - _active_cone_origin
		var along: float = relative.dot(_active_cone_direction)
		if along < -token_radius or along > length + token_radius:
			return false
		var radial: float = (
			relative - _active_cone_direction * along
		).length()
		var effective_along: float = clampf(along, 0.0, length)
		return radial <= (
			effective_along * FOREHEAD_CONE_RADIUS_FACTOR
			+ token_radius
		)
	return false


func _token_effect_radius(token: CharacterBody3D) -> float:
	if token.has_method("get_footprint_extent"):
		var extent: Variant = token.call("get_footprint_extent")
		if extent is Vector2:
			var footprint: Vector2 = extent
			return maxf(
				cell_size * 0.5,
				footprint.length() * 0.5
			)
	return cell_size * 0.5


func _clear_klothys_attack_telegraph() -> void:
	_active_klothys_attack_side = ""
	_active_hand_center = Vector3.ZERO
	_active_hand_radius = 0.0
	_active_cone_origin = Vector3.ZERO
	_active_cone_direction = Vector3.FORWARD
	if (
		_klothys_attack_visual != null
		and is_instance_valid(_klothys_attack_visual)
	):
		_klothys_attack_visual.free()
	_klothys_attack_visual = null
	set_affected_token_highlight([])


func avvia_animazione_sigillo(lato: String) -> bool:
	var aliases := {"sinistro":1,"left":1,"destro":2,"right":2,"fronte":0,"forehead":0}
	if not aliases.has(lato.to_lower()) or encounter.encounter_finished:
		return false
	var index: int = aliases[lato.to_lower()]
	if encounter.seals.damage[index] >= encounter.seals.break_damage:
		return false
	encounter.register_seal_damage(index, encounter.seals.break_damage)
	return true


func resetta_tutti_i_sigilli() -> void:
	_clear_klothys_attack_telegraph()
	if encounter == null or not is_instance_valid(encounter):
		return
	if encounter.seals == null or not is_instance_valid(encounter.seals):
		return

	# Also recover an already-running session created before this fix, where
	# breaking all seals could mark the encounter as finished.
	encounter.encounter_finished = false
	encounter.end_reason = ""
	encounter.seals.restore([0.0, 0.0, 0.0])
	if klotis_prison != null and is_instance_valid(klotis_prison):
		klotis_prison.reset_seals()
	encounter.state_changed.emit()


func _show_context_menu(screen_position: Vector2) -> void:
	super._show_context_menu(screen_position)
	context_menu.add_separator("Sigilli di Klotis")
	var seal_ids := [
		CONTEXT_BREAK_LEFT_SEAL,
		CONTEXT_BREAK_RIGHT_SEAL,
		CONTEXT_BREAK_FOREHEAD_SEAL,
	]
	var seal_labels := [
		"Spezza sigillo sinistro",
		"Spezza sigillo destro",
		"Spezza sigillo sulla fronte",
	]
	var seal_sides := ["left", "right", "forehead"]
	var any_broken := false
	for index in range(3):
		context_menu.add_item(seal_labels[index], seal_ids[index])
		var side: String = seal_sides[index]
		var is_broken: bool = bool(klotis_prison.broken.get(side, false))
		any_broken = any_broken or is_broken
		context_menu.set_item_disabled(
			context_menu.get_item_index(seal_ids[index]),
			is_broken
		)
	context_menu.add_separator()
	context_menu.add_item("Resetta tutti i sigilli", CONTEXT_RESET_SEALS)
	context_menu.set_item_disabled(
		context_menu.get_item_index(CONTEXT_RESET_SEALS),
		not any_broken
	)


func _on_context_menu_id_pressed(id: int) -> void:
	if id in [
		CONTEXT_BREAK_LEFT_SEAL,
		CONTEXT_BREAK_RIGHT_SEAL,
		CONTEXT_BREAK_FOREHEAD_SEAL,
	]:
		_close_context_menu_to_game()
		avvia_animazione_sigillo(
			["sinistro", "destro", "fronte"][id - CONTEXT_BREAK_LEFT_SEAL]
		)
	elif id == CONTEXT_RESET_SEALS:
		resetta_tutti_i_sigilli()
		_close_context_menu_to_game()
	elif id == CONTEXT_SHOULDERS and is_instance_valid(klotis_prison):
		camera.exit_first_person()
		var target: Vector3 = klotis_prison.statue_top
		camera.global_position = target + Vector3(-18,25,24)
		camera.look_at(target)
		_close_context_menu_to_game()
	else:
		super._on_context_menu_id_pressed(id)
