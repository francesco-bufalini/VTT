extends SceneTree

const MountController = preload("res://vtt/mount_controller.gd")
const ItemController = preload("res://items/item_controller.gd")
const TokenScene = preload("res://token.tscn")


class TestBoard extends Node3D:
	var cell_size: float = 1.0
	var board_sync: Node
	var item_controller: Node
	var mount_controller: Node

	func push_undo_state() -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func _token(board: Node3D, position: Vector3) -> CharacterBody3D:
	var token: CharacterBody3D = TokenScene.instantiate()
	board.get_node("Tokens").add_child(token)
	token.global_position = position
	token.set_physics_process(false)
	return token


func _run() -> void:
	# Compile shared scene and scripts without requiring a running multiplayer server.
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
	board.item_controller = ItemController.new()
	board.add_child(board.item_controller)
	board.item_controller.setup(board)
	board.item_controller.set_physics_process(false)
	board.mount_controller = MountController.new()
	board.add_child(board.mount_controller)
	board.mount_controller.setup(board)
	board.mount_controller.set_physics_process(false)
	board.board_sync = load("res://network/board_sync.gd").new()
	board.add_child(board.board_sync)
	board.board_sync.setup(board, TokenScene, tokens, measure)

	var rider := _token(board, Vector3(0, 1, 0))
	var horse := _token(board, Vector3(4, 1, 0))
	var friend := _token(board, Vector3(-2, 1, 0))
	assert(board.mount_controller.can_mount(rider, horse))
	assert(not board.mount_controller.can_mount(rider, rider))
	assert(board.mount_controller.mount(rider, horse))
	var relative := horse.to_local(rider.global_position)
	horse.global_position += Vector3(2, 0, -3)
	horse.rotate_y(PI / 2.0)
	board.mount_controller.refresh_all()
	assert(rider.global_position.is_equal_approx(horse.to_global(relative)))
	# Nesting cannot create a circular mount relationship.
	assert(not board.mount_controller.can_mount(horse, rider))
	assert(board.mount_controller.mount(friend, rider))
	assert(not board.mount_controller.can_mount(horse, friend))

	var cart: StaticBody3D = board.item_controller.create_item(Vector3(0, 0, 0))
	assert(board.mount_controller.mount(rider, cart))
	var cart_local := cart.to_local(rider.global_position)
	board.item_controller.move_item(cart, Vector3(8, 0, 2))
	board.mount_controller.refresh_all()
	assert(rider.global_position.is_equal_approx(cart.to_global(cart_local)))
	assert(rider.grid_support == null)

	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(
		board.board_sync.create_snapshot()
	))
	assert(board.board_sync.valid_snapshot(snapshot))
	var mounted_data: Dictionary = {}
	for value: Dictionary in snapshot.objects:
		if String(value.get("id", "")) == String(rider.call("get_token_id")):
			mounted_data = value
	assert(mounted_data.mount_target_kind == "item")
	assert(mounted_data.mount_target_id == cart.item_id)

	board.mount_controller.dismount(rider)
	assert(not board.mount_controller.is_mounted(rider))
	assert(board.board_sync.apply_snapshot(snapshot))
	assert(board.mount_controller.is_mounted(rider))
	assert(board.mount_controller.get_target(rider) == board.item_controller.items[0])
	assert(rider.global_position.is_equal_approx(
		board.item_controller.items[0].to_global(cart_local)
	))
	var invalid: Dictionary = snapshot.duplicate(true)
	for value: Dictionary in invalid.objects:
		if String(value.get("id", "")) == String(rider.call("get_token_id")):
			value.mount_target_kind = "token"
			value.mount_target_id = String(rider.call("get_token_id"))
	assert(not board.board_sync.valid_snapshot(invalid))

	board.item_controller.remove_item(board.item_controller.items[0])
	board.mount_controller.refresh_all()
	assert(not board.mount_controller.is_mounted(rider))
	board.free()
	print("PASS: mount creature/item, follow, cycle checks, snapshot and dismount")
	quit()
