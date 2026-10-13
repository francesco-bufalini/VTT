extends CanvasLayer
# Viewport-local hover captions. They stay open while the pointer enters the
# caption, allowing native RichTextLabel scrolling and text selection.
var _panel: PanelContainer
var _body: RichTextLabel
var _target: Control
var _item_index := -1
var _item_label := ""
var _text := ""
var _elapsed := 0.0
var _leave := 0.0

static func install(owner: Node) -> void:
	var viewport: Viewport = owner.get_viewport()
	if viewport.has_node("ScrollableCaptions"):
		return
	var caption := new()
	caption.name = "ScrollableCaptions"
	viewport.add_child(caption)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_viewport() == get_tree().root:
		get_tree().node_added.connect(func(node: Node) -> void:
			if node is Window:
				_install_later.call_deferred(node)
		)
	layer = 120
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.hide()
	add_child(_panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.13, 0.98)
	style.border_color = Color(0.60, 0.52, 0.38)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = false
	_body.scroll_active = true
	_body.mouse_force_pass_scroll_events = false
	_body.selection_enabled = true
	_body.fit_content = false
	_body.mouse_filter = Control.MOUSE_FILTER_STOP
	_body.add_theme_font_size_override("normal_font_size", 15)
	_panel.add_child(_body)

func _process(delta: float) -> void:
	if get_viewport() is Window and not (get_viewport() as Window).visible:
		_restore_target()
		_panel.hide()
		return
	if _panel.visible and _panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
		_leave = 0.0
		return
	var hovered: Control = get_viewport().gui_get_hovered_control()
	var candidate: Control = hovered
	var item_index := -1
	var item_caption := false
	if hovered is ItemList:
		item_index = hovered.get_item_at_position(hovered.get_local_mouse_position(), true)
		if item_index >= 0:
			item_caption = not hovered.get_item_tooltip(item_index).is_empty() or (hovered == _target and item_index == _item_index and hovered.get_item_text(item_index) == _item_label)
	if not item_caption:
		item_index = -1
	while candidate != null and not item_caption:
		if candidate == _target or not candidate.tooltip_text.is_empty():
			break
		candidate = candidate.get_parent() as Control
	if candidate == _target and item_index == _item_index and is_instance_valid(_target) and _target.is_visible_in_tree():
		_leave = 0.0
		if _item_index < 0 and not _target.tooltip_text.is_empty():
			_text = _target.tooltip_text
			_target.tooltip_text = ""
			if _panel.visible:
				_body.text = _text
		_elapsed += delta
		if _elapsed >= 0.45 and not _panel.visible:
			_show_caption()
		return
	_leave += delta
	if _panel.visible and _leave < 0.25:
		return
	_restore_target()
	_panel.hide()
	_target = candidate
	_elapsed = 0.0
	_leave = 0.0
	if is_instance_valid(_target):
		if _target is ItemList and item_index >= 0:
			_item_index = item_index
			_item_label = _target.get_item_text(item_index)
			_text = _target.get_item_tooltip(item_index)
			_target.set_item_tooltip(item_index, "")
		else:
			_text = _target.tooltip_text
			_target.tooltip_text = ""

func _restore_target() -> void:
	if is_instance_valid(_target):
		if _target is ItemList and _item_index >= 0:
			if _item_index < _target.item_count and _target.get_item_text(_item_index) == _item_label and _target.get_item_tooltip(_item_index).is_empty():
				_target.set_item_tooltip(_item_index, _text)
		elif _target.tooltip_text.is_empty():
			_target.tooltip_text = _text
	_target = null
	_item_index = -1
	_item_label = ""

func _show_caption() -> void:
	if not is_instance_valid(_target) or _text.is_empty():
		return
	var available: Vector2 = get_viewport().get_visible_rect().size
	var width: float = minf(clampf(float(_text.length()) * 8.0 + 24.0, 180.0, 480.0), available.x - 24.0)
	var estimated: float = 36.0 + 20.0 * (ceili(float(_text.length()) / maxf(1.0, width / 8.0)) + _text.count("\n"))
	var height: float = minf(clampf(estimated, 80.0, 320.0), available.y - 24.0)
	_panel.custom_minimum_size = Vector2(width, height)
	_panel.size = Vector2(width, height)
	_body.text = _text
	_body.scroll_to_line(0)
	var point: Vector2 = get_viewport().get_mouse_position() + Vector2(16, 20)
	point.x = clampf(point.x, 12.0, available.x - width - 12.0)
	point.y = clampf(point.y, 12.0, available.y - height - 12.0)
	_panel.position = point
	_panel.show()

func _exit_tree() -> void:
	_restore_target()


func _install_later(window: Node) -> void:
	if is_instance_valid(window) and window.is_inside_tree() and window.get_viewport() != null:
		install(window)
