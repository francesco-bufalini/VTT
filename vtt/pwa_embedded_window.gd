extends Window
## Movable Godot frame for the actual PWA. No desktop archive or IPC adapter.

const MARGIN := Vector2i(32, 40)
const MINIMUM := Vector2i(720, 480)

var browser: Control
var _view_url := ""
var _placed := false
var _available := Vector2i.ZERO


func _ready() -> void:
	title = "Creature"
	force_native = false
	wrap_controls = false
	transient = true
	close_requested.connect(dismiss)
	get_tree().root.size_changed.connect(_fit)
	visibility_changed.connect(_sync_browser)
	size_changed.connect(_sync_browser)
	set_process(false)


static func view_url(origin: String, section: String) -> String:
	if origin.is_empty() or section not in ["creatures", "compendium"]:
		return ""
	return origin.trim_suffix("/") + "/?native_view=" + section


func show_pwa(origin: String, section: String = "creatures") -> bool:
	var url := view_url(origin, section)
	if url.is_empty() or not ClassDB.class_exists("WebView"):
		return false
	title = "Compendio" if section == "compendium" else "Creature"
	if not is_instance_valid(browser):
		browser = ClassDB.instantiate("WebView") as Control
		if browser == null:
			return false
		# WRY attaches a native child to Godot's main window, not to this frame.
		browser.mouse_filter = Control.MOUSE_FILTER_IGNORE
		browser.set("full_window_size", false)
		browser.set("forward_input_events", false)
		# The PWA now owns its IndexedDB. Incognito would erase the archive.
		browser.set("incognito", false)
		browser.set("devtools", OS.is_debug_build())
		browser.set("url", url)
		_view_url = url
		add_child(browser)
	elif _view_url != url:
		browser.set("url", url)
		_view_url = url
	_fit()
	show()
	set_process(true)
	browser.show()
	_sync_browser()
	browser.call_deferred("focus")
	return true


func dismiss() -> void:
	if is_instance_valid(browser):
		# Return keyboard focus to the 3D board (especially on Windows).
		browser.call("focus_parent")
		browser.hide()
	set_process(false)
	hide()
	if is_instance_valid(browser):
		browser.call_deferred("focus_parent")


func _fit() -> void:
	if not is_inside_tree():
		return
	var available := Vector2i(get_tree().root.get_visible_rect().size)
	_available = available
	var allowed := (available - MARGIN * 2).max(Vector2i.ONE)
	min_size = MINIMUM.min(allowed)
	max_size = allowed
	if not _placed:
		size = Vector2i(Vector2(available) * 0.84).min(Vector2i(1360, 900)).max(min_size).min(allowed)
		position = (available - size) / 2
		_placed = true
	else:
		size = size.clamp(min_size, allowed)
		position = position.clamp(MARGIN, (available - size - MARGIN).max(MARGIN))
	_sync_browser()


func _process(_delta: float) -> void:
	# Moving the OS window or changing DPI does not fire Control.resized.
	position = position.clamp(MARGIN, (_available - size - MARGIN).max(MARGIN))
	_sync_browser()


func _sync_browser() -> void:
	if not is_inside_tree() or not is_instance_valid(browser) or not browser.is_inside_tree() or not visible:
		return
	var native_rect := native_bounds(get_screen_transform(), Vector2(size))
	# WRY 1.0.2 expects unscaled browser pixels rather than Godot logical units.
	var desired_position := browser.position + browser.get_screen_transform().basis_xform_inv(native_rect.position - browser.get_screen_position())
	if not browser.position.is_equal_approx(desired_position) or not browser.size.is_equal_approx(native_rect.size):
		browser.position = desired_position
		browser.size = native_rect.size
		browser.call("resize")


static func native_bounds(screen_transform: Transform2D, logical_size: Vector2) -> Rect2:
	var screen_rect := screen_transform * Rect2(Vector2.ZERO, logical_size)
	return Rect2(screen_rect.position.round(), screen_rect.size.round().max(Vector2.ONE))
