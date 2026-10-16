extends SceneTree

const DialogLayout = preload("res://vtt/dialog_layout.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	# The shipped desktop app must use viewport coordinates for ALL popups,
	# not native screen coordinates. Earlier tests forced embedding only here.
	assert(bool(ProjectSettings.get_setting(
		"display/window/subwindows/embed_subwindows", false
	)), "Project must embed desktop subwindows globally, not only in tests")
	var main_position := Vector2i(460, 260)
	var main_size := Vector2i(800, 600)
	var popup_size := Vector2i(620, 430)
	assert(DialogLayout._centered_popup_position(
		main_position, main_size, popup_size, true
	) == Vector2i(90, 85), "Embedded popup must use viewport-local coordinates")
	assert(DialogLayout._centered_popup_position(
		main_position, main_size, popup_size, false
	) == Vector2i(550, 345), "Native popup must include the desktop window's screen offset")
	# Unlike the host window's physical pixels, embedded popup coordinates
	# always belong to the logical viewport (which may be much smaller).
	assert(DialogLayout._bounds_for_coordinate_space(
		Vector2i(1696, 948), Vector2i(1152, 648), true
	) == Vector2i(1152, 648), "Embedded popup bounds must use logical pixels")
	assert(DialogLayout._bounds_for_coordinate_space(
		Vector2i(1696, 948), Vector2i(1152, 648), false
	) == Vector2i(1696, 948), "Native popup bounds must use physical pixels")
	root.size = main_size
	assert(root.gui_embed_subwindows,
		"The real project configuration should embed popups before any test overrides")
	await process_frame
	var dialog := ConfirmationDialog.new()
	dialog.title = "Test primo avvio"
	dialog.min_size = Vector2i(320, 160)
	root.add_child(dialog)
	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(400, 220)
	dialog.add_child(body)
	var caption := Label.new()
	caption.text = "Dati da confermare"
	body.add_child(caption)
	var field := LineEdit.new()
	field.placeholder_text = "Campo"
	body.add_child(field)

	DialogLayout.popup(dialog, Vector2i(430, 310), 0.92)
	assert(dialog.visible and dialog.is_embedded(),
		"The first opening must display a popup embedded in the game window")
	assert(not dialog.wrap_controls, "Desktop dialog must not resize itself beyond window bounds")
	assert(dialog.get_ok_button().visible, "Confirm must be visible on first open")
	assert(dialog.get_cancel_button().visible, "Cancel must be visible on first open")
	await process_frame
	assert(dialog.size.y >= ceili(dialog.get_contents_minimum_size().y),
		"The native footer must fit after first-frame layout")
	# Content can finish measuring or receive data after the first popup.
	body.set_deferred("custom_minimum_size", Vector2(400, 1100))
	await process_frame
	await process_frame
	assert(body.get_parent() is ScrollContainer, "Late first-open content must scroll instead of hiding Confirm")
	assert(dialog.position.y + dialog.get_ok_button().get_global_rect().end.y <= root.get_visible_rect().size.y,
		"Late content must keep Confirm reachable on screen")
	dialog.hide()

	# Custom-button dialogs (the initiative picker) hide the native footer.
	dialog.get_ok_button().hide()
	dialog.get_cancel_button().hide()
	DialogLayout.popup(dialog, Vector2i(430, 310))
	assert(not dialog.get_ok_button().visible and not dialog.get_cancel_button().visible,
		"The shared popup must preserve deliberately hidden native buttons")
	dialog.hide()
	# An oversized sheet must scroll without moving its native footer off-screen.
	dialog.get_ok_button().show()
	dialog.get_cancel_button().show()
	body.custom_minimum_size.y = 1100
	DialogLayout.popup(dialog, Vector2i(600, 500))
	await process_frame
	await process_frame
	assert(body.get_parent() is ScrollContainer, "Tall sheet content must scroll")
	assert(dialog.size.y <= root.get_visible_rect().size.y * 0.92,
		"The entire dialog must fit within the game viewport")
	var confirm_rect: Rect2 = dialog.get_ok_button().get_global_rect()
	assert(confirm_rect.position.y >= 0 and confirm_rect.end.y <= dialog.size.y,
		"Confirm must be inside the window, not merely marked visible")
	assert(dialog.position.y + confirm_rect.end.y <= root.get_visible_rect().size.y,
		"Confirm must be reachable on screen")
	dialog.hide()
	dialog.queue_free()
	await process_frame

	# Reproduce the long Tailscale/share dialog layout, including wrapped text.
	var share := AcceptDialog.new()
	share.title = "Mappa · rete locale e Tailscale"
	root.add_child(share)
	var share_body := VBoxContainer.new()
	share.add_child(share_body)
	var share_info := Label.new()
	share_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	share_info.text = "Puoi salvare o caricare una copia locale della mappa, oppure " + (
		"sincronizzarla con gli altri VTT sulla stessa rete locale o via Tailscale. "
	).repeat(3)
	share_body.add_child(share_info)
	DialogLayout.popup(share, Vector2i(620, 430))
	assert(share.is_embedded() and share.visible)
	assert(share.position.x >= 0 and share.position.y >= 0
		and share.position.x + share.size.x <= root.size.x
		and share.position.y + share.size.y <= root.size.y,
		"Tailscale/share popup must open fully within the desktop window")
	await process_frame
	assert(share.position.x >= 0 and share.position.y >= 0
		and share.position.x + share.size.x <= root.size.x
		and share.position.y + share.size.y <= root.size.y,
		"Tailscale/share popup must stay inside after its content is measured")
	DialogLayout.resize_visible(share, Vector2i(950, 660), 0.90)
	assert(share.position.x >= 0 and share.position.y >= 0
		and share.position.x + share.size.x <= root.size.x
		and share.position.y + share.size.y <= root.size.y,
		"Resizing an open document-style popup must not leave the window")
	share.hide()
	share.queue_free()
	await process_frame

	var menu := PopupMenu.new()
	root.add_child(menu)
	menu.add_item("Azione token")
	menu.add_item("Elimina")
	DialogLayout.popup_menu(menu, Vector2i(790, 595))
	assert(menu.visible and menu.is_embedded())
	assert(menu.position.x >= 0 and menu.position.y >= 0
		and menu.position.x + menu.size.x <= root.size.x
		and menu.position.y + menu.size.y <= root.size.y,
		"Context menu near the screen edge must fit immediately")
	await process_frame
	assert(menu.position.x >= 0 and menu.position.y >= 0
		and menu.position.x + menu.size.x <= root.size.x
		and menu.position.y + menu.size.y <= root.size.y,
		"Context menu must remain inside after contents are measured")
	menu.hide()
	menu.queue_free()
	await process_frame

	# Regression: a dynamically measured wide HBox/Label must not force
	# an embedded desktop window beyond the viewport after being opened.
	# This reproduces the Tailscale panel cut off at the right/bottom edge.
	root.size = Vector2i(850, 560)
	root.content_scale_factor = 1.5
	await process_frame
	var oversized := AcceptDialog.new()
	oversized.title = "Condividi con Tailscale"
	root.add_child(oversized)
	var huge_content := VBoxContainer.new()
	oversized.add_child(huge_content)
	var very_wide := Label.new()
	very_wide.text = "Testo che forza la larghezza minima del contenuto"
	very_wide.custom_minimum_size = Vector2(1700, 850)
	huge_content.add_child(very_wide)
	DialogLayout.popup(oversized, Vector2i(680, 520), 0.90)
	for frame in range(3):
		await process_frame
		assert(oversized.size.x <= root.size.x * 0.90
			and oversized.size.y <= root.size.y * 0.90,
			"A child minimum size must never expand a modal beyond viewport limits")
		assert(oversized.position.x >= 0 and oversized.position.y >= 0
			and oversized.position.x + oversized.size.x <= root.size.x
			and oversized.position.y + oversized.size.y <= root.size.y,
			"Scaled, oversized Tailscale-style modal must remain completely visible")
	assert(huge_content.get_parent() is ScrollContainer,
		"Too-large modal content must scroll rather than resize its window")
	oversized.hide()
	oversized.queue_free()
	root.content_scale_factor = 1.0
	await process_frame

	# The user maximizes Godot's floating Game Workspace with Stretch to Fit.
	# Emulate a physical 1696x948 host displaying a smaller logical canvas.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_size = Vector2i(1152, 648)
	root.size = Vector2i(1696, 948)
	await process_frame
	await process_frame
	var logical: Vector2i = Vector2i(root.get_visible_rect().size)
	print("Stretch-to-fit diagnostic: physical=%s logical=%s factor=%.2f" % [
		root.size, logical, root.content_scale_factor
	])
	var maximized := AcceptDialog.new()
	maximized.title = "Mappa · rete locale e Tailscale"
	root.add_child(maximized)
	var large_body := VBoxContainer.new()
	maximized.add_child(large_body)
	var large_row := HBoxContainer.new()
	large_body.add_child(large_row)
	for title in ["Attiva accesso telefono", "Disattiva", "Aggiorna", "Copia link telefono"]:
		var button := Button.new()
		button.text = title
		large_row.add_child(button)
	DialogLayout.popup(maximized, Vector2i(680, 565), 0.92)
	for step in range(3):
		await process_frame
		var rect := Rect2(Vector2(maximized.position), Vector2(maximized.size))
		assert(Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size)).encloses(rect),
			"Maximized/stretch-to-fit modal must fit inside LOGICAL viewport")
	maximized.hide()
	maximized.queue_free()
	root.content_scale_size = Vector2i.ZERO
	await process_frame
	print("PASS: native/embedded positions, modal max-size, stretch-to-fit, Tailscale and context menus")
	quit()
