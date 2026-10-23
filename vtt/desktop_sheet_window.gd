extends Window
## Embedded Godot frame. WRY still attaches its native child to the main window.
const MARGIN := Vector2i(32, 40)
const MINIMUM := Vector2i(720, 480)
var browser: Control
var _placed := false
var _available := Vector2i.ZERO

func _ready() -> void:
	title = "Creature"
	force_native = false
	wrap_controls = false
	transient = true
	get_tree().root.size_changed.connect(_fit)
	visibility_changed.connect(_sync_browser)
	size_changed.connect(_sync_browser)
	set_process(false)

func present() -> void:
	_fit()
	show()
	set_process(true)
	_sync_browser()

func dismiss() -> void:
	set_process(false)
	hide()

func _fit() -> void:
	if not is_inside_tree(): return
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
	# Moving the main window or changing DPI does not emit Control.resized.
	position = position.clamp(MARGIN, (_available - size - MARGIN).max(MARGIN))
	_sync_browser()

func _sync_browser() -> void:
	if not is_inside_tree() or not is_instance_valid(browser) or not browser.is_inside_tree() or not visible: return
	var native_rect := native_bounds(get_screen_transform(), Vector2(size))
	# WRY 1.0.2 passes get_screen_position() and the *unscaled* Control.size
	# directly to its child-window API. An embedded Window's screen transform
	# gives parent-client pixels, including Godot's canvas/editor stretch.
	# The browser is a native surface, so its own Control needs that pixel size.
	var desired_position := browser.position + browser.get_screen_transform().basis_xform_inv(native_rect.position - browser.get_screen_position())
	if not browser.position.is_equal_approx(desired_position) or not browser.size.is_equal_approx(native_rect.size):
		browser.position = desired_position
		browser.size = native_rect.size
		browser.call("resize")

static func native_bounds(screen_transform: Transform2D, logical_size: Vector2) -> Rect2:
	var screen_rect := screen_transform * Rect2(Vector2.ZERO, logical_size)
	return Rect2(screen_rect.position.round(), screen_rect.size.round().max(Vector2.ONE))
