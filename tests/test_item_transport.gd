extends SceneTree

const Controller = preload("res://items/item_controller.gd")
const TokenScene = preload("res://token.tscn")
class TestBoard extends Node3D:
	var cell_size: float = 1.0
	var board_sync: Node
	var item_controller: Node
	var token_list: Node
	var _ui_owns_mouse: bool = false

func _initialize() -> void:
	call_deferred("run")

func make_token(board: Node3D, point: Vector3) -> CharacterBody3D:
	var token: CharacterBody3D = TokenScene.instantiate()
	board.get_node("Tokens").add_child(token)
	token.global_position = point
	token.set_physics_process(false)
	return token

func run() -> void:
	# Loading the real board here also compiles all integrations with autoloads.
	assert(load("res://dnd_base.gd") != null)
	var board := TestBoard.new()
	board.scene_file_path = "res://tests/scenes/agent_test_arena.tscn"
	root.add_child(board)
	var ui := CanvasLayer.new()
	ui.name = "UI"
	board.add_child(ui)
	var tokens := Node3D.new()
	tokens.name = "Tokens"
	board.add_child(tokens)
	var measure: Node = load("res://measurement_tool.gd").new()
	board.add_child(measure)
	var initiative: Node = load("res://vtt/initiative_tracker.gd").new()
	initiative.name = "InitiativeTracker"
	board.add_child(initiative)
	board.board_sync = load("res://network/board_sync.gd").new()
	board.add_child(board.board_sync)
	board.board_sync.setup(board, TokenScene, tokens, measure)
	board.item_controller = Controller.new()
	board.add_child(board.item_controller)
	board.item_controller.setup(board)
	board.item_controller.set_physics_process(false)
	var controller: Node = board.item_controller
	var driver := make_token(board, Vector3(3.5, 1, 0.5))
	var rider := make_token(board, Vector3(0.5, 1, 0.5))
	var outside := make_token(board, Vector3(-1.5, 1, 0.5))
	var above := make_token(board, Vector3(0.5, 5, 0.5))
	var ground_rider := make_token(board, Vector3(0.5, 0.3, -0.5))
	var cart: StaticBody3D = controller.create_item(Vector3.ZERO)
	assert(not cart.is_in_group("dnd_token"))
	assert(cart.get_child_count() >= 2, "GLB must import and load")
	assert(cart.get_meta("passenger_deck_extent") == Vector2(2, 2))
	controller.link_item(cart, driver)
	var original_offset: Vector3 = cart.link_offset
	driver.position += Vector3(2, 0, 3)
	controller.flush_motion()
	assert(cart.position.is_equal_approx(Vector3(2, 0, 3)))
	assert(rider.position.is_equal_approx(Vector3(2.5, 1, 3.5)))
	assert((cart.position - driver.position).is_equal_approx(original_offset))
	assert(outside.position.is_equal_approx(Vector3(-1.5, 1, 0.5)))
	assert(above.position.is_equal_approx(Vector3(0.5, 5, 0.5)))
	assert(ground_rider.position.is_equal_approx(Vector3(2.5, 0.3, 2.5)))
	controller.flush_motion()
	assert(rider.position.is_equal_approx(Vector3(2.5, 1, 3.5)))
	# Selected passengers moved by token dragging must never be moved twice.
	driver.position += Vector3.RIGHT
	rider.position += Vector3.RIGHT
	controller.flush_motion([driver, rider])
	assert(rider.position.is_equal_approx(Vector3(3.5, 1, 3.5)))
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(board.board_sync.create_snapshot()))
	assert(board.board_sync.valid_snapshot(snapshot))
	assert(snapshot.objects.size() == 5 and snapshot.items.size() == 1)
	var saved_position: Vector3 = cart.position
	var saved_rider: Vector3 = rider.position
	controller.move_item(cart, cart.position + Vector3(4, 0, 0))
	assert(rider.position.is_equal_approx(saved_rider + Vector3(4, 0, 0)))
	controller.select_item(cart)
	controller.rotate_selected_yaw(1)
	assert(is_equal_approx(rad_to_deg(cart.rotation.y), 45.0))
	controller.rotate_selected_vertical(1)
	assert(is_equal_approx(rad_to_deg(cart.rotation.x), 30.0))
	var rotated_snapshot: Dictionary = board.board_sync.create_snapshot()
	assert(board.board_sync.valid_snapshot(rotated_snapshot))
	assert(board.board_sync.apply_snapshot(snapshot))
	cart = controller.items[0]
	assert(cart.position.is_equal_approx(saved_position))
	assert(rider.position.is_equal_approx(saved_rider))
	assert(rider.grid_support == cart)
	# Loading must rebase movement caches, preserving the saved offset.
	driver.position += Vector3(0, 1, 0)
	controller.flush_motion()
	assert(cart.position.is_equal_approx(saved_position + Vector3.UP))
	assert(rider.position.is_equal_approx(saved_rider + Vector3.UP))
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid.items.append(invalid.items[0].duplicate(true))
	assert(not board.board_sync.valid_snapshot(invalid))
	invalid = snapshot.duplicate(true)
	invalid.items[0].linked_token_id = "missing"
	assert(not board.board_sync.valid_snapshot(invalid))
	# Old V5 saves contain no items and remain loadable.
	var legacy: Dictionary = snapshot.duplicate(true)
	legacy.version = 5
	legacy.erase("items")
	assert(board.board_sync.apply_snapshot(legacy))
	assert(controller.items.is_empty())
	assert(rider.grid_support == null)
	board.free()
	print("PASS: item transport, offset, passengers, snapshot round trip and legacy saves")
	quit()
