extends RefCounted

# Validation only. Rendering, undo, and persistence stay in MeasurementTool.
# Keep legacy snapshot rules stable: board_sync relies on this contract.

static func _valid_serialized_point(value: Variant) -> bool:
	if not value is Array:
		return false
	var point: Array = value
	if point.size() != 3:
		return false
	for coordinate: Variant in point:
		if (
			not (coordinate is float or coordinate is int)
			or not is_finite(float(coordinate))
			or absf(float(coordinate)) > 100000.0
		):
			return false
	return true


static func valid_aoes(data: Variant) -> bool:
	if not data is Array or data.size() > 256:
		return false

	for item_value: Variant in data:
		if not item_value is Dictionary:
			return false
		var item: Dictionary = item_value
		var shape: String = String(item.get("shape", ""))

		if shape == "wall_path":
			var points_value: Variant = item.get("points", [])
			if not points_value is Array:
				return false
			var points: Array = points_value
			if points.size() < 2 or points.size() > 128:
				return false
			for point_value: Variant in points:
				if not _valid_serialized_point(point_value):
					return false

			for numeric_key: String in ["wall_height", "wall_thickness"]:
				var number_value: Variant = item.get(numeric_key)
				if not (number_value is float or number_value is int):
					return false
				var number: float = float(number_value)
				if not is_finite(number) or number <= 0.0 or number > 10000.0:
					return false

			if item.has("damage_side"):
				var side_value: Variant = item.get("damage_side")
				if not (side_value is int or side_value is float):
					return false
				if absi(int(side_value)) > 1:
					return false

		elif shape == "wall_globe":
			if not _valid_serialized_point(item.get("center", [])):
				return false
			var radius_value: Variant = item.get("radius")
			if not (radius_value is float or radius_value is int):
				return false
			var radius: float = float(radius_value)
			if not is_finite(radius) or radius <= 0.0 or radius > 10000.0:
				return false
			if item.has("hemisphere") and not item.get("hemisphere") is bool:
				return false

		elif shape in [
			"sphere",
			"cube",
			"cone",
			"line",
			"flat_square",
			"cylinder"
		]:
			for key: String in ["start", "end"]:
				if not _valid_serialized_point(item.get(key, [])):
					return false
		else:
			return false

		if item.has("style") and not item.get("style") is String:
			return false

		if item.has("line_width_world"):
			var width_value: Variant = item.get("line_width_world")
			if not (width_value is float or width_value is int):
				return false
			var line_width: float = float(width_value)
			if not is_finite(line_width) or line_width <= 0.0 or line_width > 10000.0:
				return false

		if item.has("movable_aoe_feet"):
			var movement_value: Variant = item.get("movable_aoe_feet")
			if not (movement_value is float or movement_value is int):
				return false
			var movement_feet: float = float(movement_value)
			if (
				not is_finite(movement_feet)
				or movement_feet <= 0.0
				or movement_feet > 10000.0
			):
				return false
			var movement_mode: String = String(
				item.get("movable_aoe_mode", "free")
			)
			if movement_mode not in [
				"free",
				"free_exact",
				"away_from_caster"
			]:
				return false
			if (
				movement_mode == "away_from_caster"
				and not _valid_serialized_point(
					item.get("caster_origin", [])
				)
			):
				return false

		if item.has("wall_meta") and not item.get("wall_meta") is Dictionary:
			return false

		if (
			item.has("spell_click_to_remove")
			and not item.get("spell_click_to_remove") is bool
		):
			return false

		if item.has("color"):
			var color_value: Variant = item.get("color")
			if not color_value is Dictionary:
				return false
			var color_data: Dictionary = color_value
			for channel: String in ["r", "g", "b", "a"]:
				var channel_value: Variant = color_data.get(channel)
				if (
					not (channel_value is float or channel_value is int)
					or not is_finite(float(channel_value))
					or float(channel_value) < 0.0
					or float(channel_value) > 1.0
				):
					return false

	return true


