extends SceneTree

const PwaEmbeddedWindow = preload("res://vtt/pwa_embedded_window.gd")
const HostScript = preload("res://network/pwa_host.gd")
const ToolbarScript = preload("res://vtt/runtime_toolbar.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	await process_frame
	var empty_host: Node = HostScript.new()
	assert(empty_host.has_method("local_origin"))
	assert(String(empty_host.call("local_origin")).is_empty(),
		"Native PWA URL must not be offered when the listener is stopped")
	empty_host.free()

	assert(PwaEmbeddedWindow.view_url("http://127.0.0.1:8765", "creatures") ==
		"http://127.0.0.1:8765/?native_view=creatures",
		"Native Creature entry must open the archive-only PWA route")
	assert(PwaEmbeddedWindow.view_url("http://127.0.0.1:8765/", "compendium") ==
		"http://127.0.0.1:8765/?native_view=compendium",
		"Native Compendium entry must open the catalog-only PWA route")
	assert(PwaEmbeddedWindow.view_url("http://127.0.0.1:8765", "session").is_empty(),
		"The native toolbar must not expose the PWA Partita tab")

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
	var compendium_button: Button = row.get_node_or_null("OpenCompendiumPwa") as Button
	assert(compendium_button != null and compendium_button.text == "Compendio",
		"The native Compendium must be a direct PWA button, not a separate native panel")
	assert(toolbar.has_method("_open_compendium"))
	assert(toolbar.has_method("_open_pwa_view"))
	board.queue_free()
	print("PASS: native PWA Creature and Compendium routes, toolbar and WebView bounds")
	quit()
