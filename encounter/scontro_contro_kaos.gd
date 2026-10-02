extends "res://encounter/final_encounter.gd"

const PostKaosHelpers = preload("res://encounter/post_kaos_helpers.gd")

const CHARIOT_OFFSETS_METERS := [
	Vector3(-27.0, 24.0, 70.0),
	Vector3(-9.0, 30.0, 74.0),
	Vector3(9.0, 30.0, 74.0),
	Vector3(27.0, 24.0, 70.0),
]


func _ready() -> void:
	super._ready()
	_clean_scontro_board()
	_apply_post_kaos_terrain_rules()
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
	# Surface collision cells straddle the mesh by construction. Rendering
	# them half a cell downward makes their top plane coincide with the
	# walkable surface, so tokens stand on the grid instead of inside it.
	volumetric_grid.display_offset_cells = Vector3(0.0, -0.5, 0.0)
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
