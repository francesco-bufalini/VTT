extends RefCounted

# Pure renderer for token grid highlights. Keeping this logic independent from
# dnd_base.gd lets headless tests exercise the actual MultiMesh lifecycle
# without loading the full VTT scene and its UI assets.


static func _token_grid_highlight_centers(
	tokens: Array[CharacterBody3D],
	cell_size: float
) -> Array[Vector3]:
	var centers: Array[Vector3] = []
	for token: CharacterBody3D in tokens:
		if token == null or not is_instance_valid(token):
			continue

		var footprint: float = (
			float(token.call("get_footprint_cells"))
			if token.has_method("get_footprint_cells")
			else 1.0
		)
		var height_cells: float = maxf(
			float(token.get("token_height_cells")),
			0.1
		)
		var horizontal_count: int = maxi(1, int(ceil(footprint)))
		var vertical_count: int = maxi(1, int(ceil(height_cells)))
		var horizontal_start: float = (
			-float(horizontal_count - 1) * cell_size * 0.5
		)
		var bottom_y: float = (
			token.global_position.y
			- height_cells * cell_size * 0.5
		)

		for y_index: int in range(vertical_count):
			var world_y: float = (
				bottom_y + (float(y_index) + 0.5) * cell_size
			)
			for z_index: int in range(horizontal_count):
				for x_index: int in range(horizontal_count):
					centers.append(
						Vector3(
							token.global_position.x
							+ horizontal_start
							+ float(x_index) * cell_size,
							world_y,
							token.global_position.z
							+ horizontal_start
							+ float(z_index) * cell_size
						)
					)
	return centers


static func _signature(tokens: Array[CharacterBody3D]) -> String:
	var signature_parts: PackedStringArray = []
	for token: CharacterBody3D in tokens:
		if token == null or not is_instance_valid(token):
			continue
		var footprint: float = (
			float(token.call("get_footprint_cells"))
			if token.has_method("get_footprint_cells")
			else 1.0
		)
		var height_cells: float = maxf(
			float(token.get("token_height_cells")),
			0.1
		)
		signature_parts.append(
			"%s|%s|%.4f|%.4f" % [
				str(token.get_instance_id()),
				str(token.global_position),
				footprint,
				height_cells
			]
		)

	# The empty state must not use "". dnd_base.gd uses "" specifically to
	# invalidate a cached signature; if both values are empty the refresh is
	# skipped and stale MultiMesh instances remain visible.
	return "%d:%s" % [signature_parts.size(), ";".join(signature_parts)]


static func refresh(
	owner: Node3D,
	tokens: Array[CharacterBody3D],
	multimesh: MultiMesh,
	previous_signature: String,
	cell_size: float
) -> String:
	if multimesh == null:
		return previous_signature

	var next_signature: String = _signature(tokens)
	if next_signature == previous_signature:
		return previous_signature

	var centers: Array[Vector3] = _token_grid_highlight_centers(
		tokens,
		cell_size
	)
	multimesh.instance_count = centers.size()
	multimesh.visible_instance_count = centers.size()
	for index: int in range(centers.size()):
		var local_center: Vector3 = (
			owner.to_local(centers[index])
			if owner != null and is_instance_valid(owner)
			else centers[index]
		)
		multimesh.set_instance_transform(
			index,
			Transform3D(Basis.IDENTITY, local_center)
		)
	return next_signature
