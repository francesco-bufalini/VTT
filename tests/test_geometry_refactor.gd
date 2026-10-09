extends SceneTree

const AoeSnapshotValidator = preload("res://vtt/aoe_snapshot_validator.gd")
const SpellTargetGeometry = preload("res://vtt/spells/spell_target_geometry.gd")


func _initialize() -> void:
	# AoE data is accepted/rejected exactly as before its extraction from
	# MeasurementTool; no scene or network service is required.
	assert(AoeSnapshotValidator.valid_aoes([]))
	assert(not AoeSnapshotValidator.valid_aoes({}))
	assert(not AoeSnapshotValidator.valid_aoes(Array(range(257))))

	var sphere := {
		"shape": "sphere",
		"start": [0.0, 0.0, 0.0],
		"end": [1.0, 0.0, 0.0],
		"style": "fire",
		"color": {"r": 1.0, "g": 0.2, "b": 0.1, "a": 1.0}
	}
	assert(AoeSnapshotValidator.valid_aoes([sphere]))
	var invalid_color: Dictionary = sphere.duplicate(true)
	invalid_color["color"]["r"] = 1.1
	assert(not AoeSnapshotValidator.valid_aoes([invalid_color]))
	var invalid_point: Dictionary = sphere.duplicate(true)
	invalid_point["start"] = [100001.0, 0.0, 0.0]
	assert(not AoeSnapshotValidator.valid_aoes([invalid_point]))

	var wall := {
		"shape": "wall_path",
		"points": [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0]],
		"wall_height": 2.0,
		"wall_thickness": 0.25,
		"damage_side": -1
	}
	assert(AoeSnapshotValidator.valid_aoes([wall]))
	var invalid_wall: Dictionary = wall.duplicate(true)
	invalid_wall["damage_side"] = 2
	assert(not AoeSnapshotValidator.valid_aoes([invalid_wall]))
	assert(AoeSnapshotValidator.valid_aoes([{
		"shape": "wall_globe",
		"center": [0, 0, 0],
		"radius": 1.0,
		"hemisphere": true
	}]))
	assert(not AoeSnapshotValidator.valid_aoes([{"shape": "unknown"}]))

	# All six fallback spell geometries and degenerate directions remain
	# independently testable without an active board or rendering context.
	assert(_inside(Vector3(4.4, 0, 0), "sphere", {"aoe_radius_feet": 20.0}))
	assert(not _inside(Vector3(5, 0, 0), "sphere", {"aoe_radius_feet": 20.0}))
	assert(SpellTargetGeometry.contains_point(
		Vector3(5.8, 0, 0), Vector3.ZERO, Vector3.RIGHT * 4.0,
		"sphere", {"aoe_radius_feet": 20.0}, 1.0, 30.0
	))
	assert(_inside(Vector3(1.3, 0, 0), "cube", {"aoe_side_feet": 10.0}))
	assert(not _inside(Vector3(2, 0, 0), "cube", {"aoe_side_feet": 10.0}))
	assert(_inside(Vector3(0, 1.4, 0), "flat_square", {"aoe_side_feet": 10.0}))
	assert(not _inside(Vector3(0, 2, 0), "flat_square", {"aoe_side_feet": 10.0}))
	assert(_inside(Vector3(0.5, 1.2, 0), "cylinder", {
		"aoe_radius_feet": 5.0, "aoe_height_feet": 5.0
	}))
	assert(not _inside(Vector3(0.5, 2.0, 0), "cylinder", {}))
	assert(_inside(Vector3(2, 0.8, 0), "line", {"line_width_feet": 5.0}))
	assert(not _inside(Vector3(2, 1.2, 0), "line", {}))
	assert(_inside(Vector3(2, 1, 0), "cone", {}))
	assert(not _inside(Vector3(2, 4, 0), "cone", {}))
	assert(not _inside(Vector3.ZERO, "unknown", {}))
	assert(not SpellTargetGeometry.contains_point(
		Vector3.ZERO, Vector3.ZERO, Vector3.ZERO,
		"line", {}, 1.0, 5.0
	))
	assert(not SpellTargetGeometry.contains_point(
		Vector3.ZERO, Vector3.ZERO, Vector3.ZERO,
		"cone", {}, 1.0, 5.0
	))
	print("Geometry extraction regression checks passed.")
	quit(0)


func _inside(point: Vector3, shape: String, spell_data: Dictionary) -> bool:
	return SpellTargetGeometry.contains_point(
		point,
		Vector3.ZERO,
		Vector3.RIGHT * 4.0,
		shape,
		spell_data,
		1.0,
		float(spell_data.get("aoe_radius_feet", 5.0))
	)
