extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var board: Node3D = load("res://dnd_base.tscn").instantiate()
	root.add_child(board)
	await process_frame
	await process_frame
	await process_frame
	var row: Node = board.get_node("UI/RuntimeToolbar").get_child(0)
	var item_menu: MenuButton = null
	var has_creatures := false
	for child: Node in row.get_children():
		if child is MenuButton and child.text == "Item":
			item_menu = child
		if child is Button and child.text == "Creature":
			has_creatures = true
	assert(item_menu != null and item_menu.get_popup().item_count == 6,
		"The runtime ribbon must expose all item actions")
	assert(has_creatures, "The current ribbon must expose the creature archive")
	var driver: CharacterBody3D = load("res://token.tscn").instantiate()
	var rider: CharacterBody3D = load("res://token.tscn").instantiate()
	board.tokens_root.add_child(driver)
	board.tokens_root.add_child(rider)
	driver.global_position = Vector3(3.5, 4, 0.5)
	rider.global_position = Vector3(0.5, 4, 0.5)
	var cart: StaticBody3D = board.item_controller.create_item(Vector3(0, 3, 0))
	board.item_controller.link_item(cart, driver)
	var item_id: String = cart.item_id
	board._selected_tokens.append(driver)
	board._selected_tokens.append(rider)
	board._move_selected(Vector2i.RIGHT)
	assert(cart.position.is_equal_approx(Vector3(1, 3, 0)))
	assert(rider.position.is_equal_approx(Vector3(1.5, 4, 0.5)))
	assert(board.undo_last_action())
	cart = board.item_controller.items[0]
	assert(cart.item_id == item_id)
	assert(cart.position.is_equal_approx(Vector3(0, 3, 0)))
	assert(rider.position.is_equal_approx(Vector3(0.5, 4, 0.5)))
	assert(board.redo_last_action())
	cart = board.item_controller.items[0]
	assert(cart.position.is_equal_approx(Vector3(1, 3, 0)))
	assert(rider.position.is_equal_approx(Vector3(1.5, 4, 0.5)))
	board.clear_token_selection()
	board.item_controller.select_item(cart)
	assert(board.item_controller.has_selected_item())
	board._move_selected(Vector2i.RIGHT)
	assert(cart.position.x > 1.0)
	board._rotate_selected(1)
	assert(is_equal_approx(rad_to_deg(cart.rotation.y), 45.0))
	# Item tilt remains supported; only creature-token tilt was removed.
	board.item_controller.rotate_selected_vertical(1)
	assert(is_equal_approx(rad_to_deg(cart.rotation.x), 30.0))
	board.free()
	print("PASS: real toolbar, group token nudge and item undo/redo")
	quit()
