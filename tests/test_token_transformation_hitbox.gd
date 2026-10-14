extends SceneTree

const TokenScene = preload("res://token.tscn")
const BoardScript = preload("res://dnd_base.gd")
const SHORT_VISUAL := "res://assets/tokens/test/short_hitbox_visual.tscn"
const TALL_VISUAL := "res://assets/tokens/test/tall_hitbox_visual.tscn"


func _initialize() -> void:
	call_deferred("run")


func _size(token: CharacterBody3D) -> Vector3:
	var collider := token.get_node("CollisionShape3D") as CollisionShape3D
	return (collider.shape as BoxShape3D).size


func _assert_base_at(token: CharacterBody3D, base_y: float) -> void:
	assert(is_equal_approx(
		token.global_position.y - _size(token).y * 0.5, base_y
	))


func run() -> void:
	var token := TokenScene.instantiate() as CharacterBody3D
	root.add_child(token)
	assert(token.set_visual_asset(SHORT_VISUAL, 1.0))
	token.set_size_category("Medium", 1.0)
	token.global_position = Vector3(0.0, 0.5, 0.0)
	assert(_size(token).is_equal_approx(Vector3(1.0, 1.0, 1.0)))

	# Same tactical footprint, different mesh height: the collider must change.
	token.push_transformation_state()
	assert(token.set_visual_asset(TALL_VISUAL, 1.0))
	assert(_size(token).is_equal_approx(Vector3(1.0, 3.0, 1.0)))
	_assert_base_at(token, 0.0)

	# A new native footprint on the SAME mesh must also refresh the hitbox.
	assert(token.set_visual_asset(TALL_VISUAL, 2.0))
	assert(_size(token).is_equal_approx(Vector3(1.0, 1.5, 1.0)))
	_assert_base_at(token, 0.0)

	token.set_size_category("Large", 2.0)
	assert(_size(token).is_equal_approx(Vector3(2.0, 3.0, 2.0)))
	_assert_base_at(token, 0.0)

	# Restoring the original miniature must restore width, height and base.
	assert(token.restore_previous_transformation())
	assert(token.get_visual_asset_path() == SHORT_VISUAL)
	assert(_size(token).is_equal_approx(Vector3(1.0, 1.0, 1.0)))
	assert(token.get_size_name() == "Medium")
	_assert_base_at(token, 0.0)

	# The creature sheet keeps its base size. A polymorphed miniature adopts
	# its own profile footprint, and the base form returns to the sheet size.
	var board := BoardScript.new()
	var profiles: Array[Dictionary] = [{
		"id": "tall-form",
		"visual_asset": TALL_VISUAL,
		"size_name": "Large",
		"footprint": 2.0
	}]
	board.set("_token_profiles", profiles)
	var record := {
		"default_miniature_id": "short-form",
		"current_miniature_id": "tall-form",
		"size_name": "Medium",
		"footprint": 1.0
	}
	assert(token.set_visual_asset(TALL_VISUAL, 2.0))
	board.apply_creature_sheet_properties(token, record)
	assert(token.get_size_name() == "Large")
	assert(_size(token).is_equal_approx(Vector3(2.0, 3.0, 2.0)))
	_assert_base_at(token, 0.0)

	record["current_miniature_id"] = "short-form"
	assert(token.set_visual_asset(SHORT_VISUAL, 1.0))
	board.apply_creature_sheet_properties(token, record)
	assert(token.get_size_name() == "Medium")
	assert(_size(token).is_equal_approx(Vector3(1.0, 1.0, 1.0)))
	_assert_base_at(token, 0.0)

	board.free()
	token.queue_free()
	print("PASS: transformed and restored miniature collider follows visual bounds and sheet footprint")
	quit()
