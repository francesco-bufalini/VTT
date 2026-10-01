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
	_apply_post_kaos_terrain_rules()
	_position_starting_group_near_sphere()


func _apply_post_kaos_terrain_rules() -> void:
	# Port the useful terrain behavior from Campaign Editor Post-Kaos onto
	# Scontro contro Kaos without changing its phase-2 combat controller.
	# Kaos keeps the one-hand pose, but the head and upper neck are removed;
	# the shoulders and neck stump are opaque, real walkable geometry.
	PostKaosHelpers.prepare_scontro_kaos_terrain(self)
	PostKaosHelpers.disable_scontro_legacy_platforms(self)
	PostKaosHelpers.ensure_solid_surfaces(self)

	# As in Post-Kaos, only the dedicated right-arm proxy drives the blue 3D
	# grid. Physical support still comes from the exact body/sphere colliders.
	volumetric_grid.collision_mask = PostKaosHelpers.RIGHT_ARM_GRID_LAYER
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
