extends SceneTree

const PwaEmbeddedWindow = preload("res://vtt/pwa_embedded_window.gd")
const HostScript = preload("res://network/pwa_host.gd")
const ToolbarScript = preload("res://vtt/runtime_toolbar.gd")


func _initialize() -> void:
	var empty_host: Node = HostScript.new()
	assert(empty_host.has_method("local_origin"))
	assert(String(empty_host.call("local_origin")).is_empty(),
		"Native PWA URL must not be offered when the listener is stopped")
	empty_host.free()

	var scaled: Rect2 = PwaEmbeddedWindow.native_bounds(
		Transform2D.IDENTITY.scaled(Vector2(1.5, 1.5)), Vector2(800, 600))
	assert(scaled.size == Vector2(1200, 900),
		"Embedded WebView must use physical pixels at high DPI")

	var board := Node3D.new()
	root.add_child(board)
	var ui := CanvasLayer.new()
	ui.name = "UI"
	board.add_child(ui)
	var toolbar: Node = ToolbarScript.new()
	board.add_child(toolbar)
	toolbar.set("board_root", board)
	toolbar.set("ui_root", ui)
	toolbar.call("_build_toolbar")
	var ribbon: PanelContainer = ui.get_node("RuntimeToolbar")
	var row: HFlowContainer = ribbon.get_child(0) as HFlowContainer
	var creature_button: Button = row.get_node_or_null("OpenCreaturePwa") as Button
	assert(creature_button != null and creature_button.text == "Creature",
		"Native runtime toolbar must have a dedicated Creature action")
	assert(toolbar.has_method("_open_creatures"))
	board.queue_free()
	print("Embedded PWA Creature toolbar contract OK")
	quit()
