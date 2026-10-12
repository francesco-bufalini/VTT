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
	var master: MenuButton
	for child: Node in row.get_children():
		if child is MenuButton:
			assert(child.text != "Item", "Item actions must live under Master")
			if child.text == "Master":
				master = child
	assert(master != null)
	assert(master.get_popup().get_item_index(board.CONTEXT_ITEM_MANAGE) >= 0)
	board._show_context_menu(Vector2(100, 100))
	var master_context: PopupMenu = board.context_menu.get_node("ContextMasterMenu")
	assert(master_context.get_item_index(board.CONTEXT_ITEM_CREATE) >= 0)
	assert(board.context_game_menu.get_item_index(101) == -1, "Retired Add Creature action must be absent")
	board._on_context_menu_id_pressed(board.CONTEXT_ITEM_MANAGE)
	await process_frame
	await process_frame
	assert(board.item_controller.panel.visible and board._ui_owns_mouse)
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	board.item_controller.panel.hide()
	board._on_context_menu_id_pressed(board.CONTEXT_ITEM_CREATE)
	await process_frame
	assert(board.item_controller.placing and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	assert(board.item_controller.handle_event(cancel))
	assert(not board.item_controller.placing)
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
	board.queue_free()
	await process_frame
	print("PASS: real toolbar, group token nudge and item undo/redo")
	quit()
