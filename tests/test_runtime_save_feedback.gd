extends SceneTree

# UI confirmation must correspond to a completed local save or a confirmed
# network sync, never to a pending send or a rejected peer.
class TestBoard extends Node3D:
	var board_sync: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var board := TestBoard.new()
	root.add_child(board)
	var ui := CanvasLayer.new()
	ui.name = "UI"
	board.add_child(ui)
	# Load after autoload globals are registered in the running SceneTree.
	var sync: Node = load("res://network/board_sync.gd").new()
	sync.set_process(false)
	board.add_child(sync)
	board.board_sync = sync

	var toolbar: Node = preload("res://vtt/runtime_toolbar.gd").new()
	board.add_child(toolbar)
	toolbar.board_root = board
	toolbar.ui_root = ui
	toolbar._build_toolbar()
	toolbar._connect_feedback_signals()
	assert(toolbar.status_label.text.is_empty())

	var game_menu: PopupMenu
	for node: Node in ui.find_children("*", "MenuButton", true, false):
		var menu := node as MenuButton
		if menu.text == "Gioco":
			game_menu = menu.get_popup()
			break
	assert(game_menu != null, "Desktop toolbar must expose the Game menu")
	for index in range(game_menu.item_count):
		assert(game_menu.get_item_text(index) != "Salva",
			"The obsolete manual Save command must not appear")

	# The autosave event is emitted only after the file rename succeeded.
	sync.map_autosave_committed.emit({"test": 1}, {}, true)
	assert(toolbar.status_label.text == "Salvato")
	var first_deadline: int = toolbar._feedback_hide_at_msec
	sync.map_autosave_committed.emit({"test": 2}, {"test": 1}, true)
	assert(toolbar._feedback_hide_at_msec >= first_deadline,
		"Successive autosaves must refresh the indicator duration")
	toolbar._feedback_hide_at_msec = Time.get_ticks_msec() - 1
	toolbar._process(0.0)
	assert(toolbar.status_label.text.is_empty(),
		"Saved confirmation must disappear automatically")
	sync.map_autosave_committed.emit({"test": 3}, {}, true)
	assert(toolbar.status_label.text == "Salvato",
		"Another save must bring the saved message back")

	# Received snapshot updates must not masquerade as local writes.
	toolbar._feedback_hide_at_msec = Time.get_ticks_msec() - 1
	toolbar._process(0.0)
	sync.map_autosave_committed.emit({"remote": 1}, {}, false)
	assert(toolbar.status_label.text.is_empty())

	# The sending API returns OK when a transfer STARTS. Only ACKs count.
	sync.set("_bulk_generation", 1)
	sync.set("_bulk_total", 2)
	sync.set("_bulk_pending", 2)
	sync.set("_bulk_accepted", 0)
	sync.set("_bulk_failed", 0)
	sync.set("_bulk_rejected", 0)
	sync._finish_bulk_attempt({"bulk_id": 1}, true, false)
	assert(toolbar.status_label.text.is_empty(),
		"A single ACK is not enough while another peer is pending")
	sync._finish_bulk_attempt({"bulk_id": 1}, false, true)
	assert(toolbar.status_label.text.is_empty(),
		"A partially rejected sync must not say synchronized")

	sync.set("_bulk_generation", 2)
	sync.set("_bulk_total", 1)
	sync.set("_bulk_pending", 1)
	sync.set("_bulk_accepted", 0)
	sync.set("_bulk_failed", 0)
	sync.set("_bulk_rejected", 0)
	sync._finish_bulk_attempt({"bulk_id": 2}, true, false)
	assert(toolbar.status_label.text == "Sincronizzato",
		"Complete remote ACKs must display synchronized confirmation")

	toolbar._feedback_hide_at_msec = Time.get_ticks_msec() - 1
	toolbar._process(0.0)
	assert(toolbar.status_label.text.is_empty())
	sync.map_synchronized.emit()
	assert(toolbar.status_label.text == "Sincronizzato",
		"An accepted incoming map must reuse the synchronization indicator")

	toolbar._set_status("Errore di salvataggio")
	toolbar._process(0.0)
	assert(toolbar.status_label.text == "Errore di salvataggio"
		and toolbar._feedback_hide_at_msec == 0,
		"An error must remain readable and never be confused with success")

	board.queue_free()
	await process_frame
	print("PASS: desktop Save removal and transient autosave/network acknowledgements")
	quit()
