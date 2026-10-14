extends CanvasLayer
# One hover presenter for the entire VTT (including detached Window viewports).
# Native Control, ItemList, Tree and tab hints share a bounded, selectable,
# scrollable RichTextLabel. Suppress native duplicates only during hover.
const APPEAR_DELAY := 0.45
const LEAVE_GRACE := 0.22

var _panel: PanelContainer
var _body: RichTextLabel
var _target: Control
var _kind := ""
var _item_index := -1
var _item_label := ""
var _tree_item: TreeItem
var _tree_column := -1
var _text := ""
var _elapsed := 0.0
var _leave := 0.0

static func install(owner: Node) -> void:
	if owner == null or not owner.is_inside_tree():
		return
	var viewport: Viewport = owner as Viewport if owner is Viewport else owner.get_viewport()
	if viewport == null or viewport.has_node("ScrollableCaptions"):
		return
	var caption := new()
	caption.name = "ScrollableCaptions"
	viewport.add_child(caption)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The autoload is created before the menu and the board. Cover popup menus,
	# dialogs and other Window viewports even when created much later.
	if get_viewport() == get_tree().root:
		get_tree().node_added.connect(_on_node_added)
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

func _on_node_added(node: Node) -> void:
	if node is Window and node != get_tree().root:
		_install_later.call_deferred(weakref(node))

func _install_later(reference: WeakRef) -> void:
	var window: Node = reference.get_ref()
	if is_instance_valid(window) and not window.is_queued_for_deletion() and window.is_inside_tree():
		install(window)

func _process(delta: float) -> void:
	if OS.has_feature("mobile") or get_tree().root.has_meta("vtt_touch_layout"):
		return
	var viewport: Viewport = get_viewport()
	if viewport is Window and not (viewport as Window).visible:
		_reset()
		return
	# The pointer must be able to enter, select and wheel-scroll the hint.
	if _panel.visible and _panel.get_global_rect().has_point(viewport.get_mouse_position()):
		_leave = 0.0
		return
	var hint: Dictionary = _hint_under_pointer()
	var candidate: Control = hint.get("target") as Control
	if candidate == _target and _same_item(hint) and is_instance_valid(_target) and _target.is_visible_in_tree():
		_leave = 0.0
		var updated: String = String(hint.get("text", ""))
		if not updated.is_empty() and updated != _text:
			_text = updated
			_suppress()
			if _panel.visible:
				_body.text = _text
		_elapsed += delta
		if _elapsed >= APPEAR_DELAY and not _panel.visible:
			_show_caption()
		return
	_leave += delta
	if _panel.visible and _leave < LEAVE_GRACE:
		return
	_reset()
	if candidate == null or String(hint.get("text", "")).is_empty():
		return
	_target = candidate
	_kind = String(hint.get("kind", "control"))
	_item_index = int(hint.get("index", -1))
	_item_label = String(hint.get("label", ""))
	_tree_item = hint.get("tree_item") as TreeItem
	_tree_column = int(hint.get("column", -1))
	_text = String(hint.get("text", ""))
	_elapsed = 0.0
	_leave = 0.0
	_suppress()

func _hint_under_pointer() -> Dictionary:
	var hovered: Control = get_viewport().gui_get_hovered_control()
	var candidate: Control = hovered
	while candidate != null:
		if candidate is ItemList:
			var list: ItemList = candidate as ItemList
			var index: int = list.get_item_at_position(list.get_local_mouse_position(), true)
			if index >= 0:
				var label: String = list.get_item_text(index)
				var value: String = list.get_item_tooltip(index)
				if candidate == _target and _kind == "item" and index == _item_index and label == _item_label and value.is_empty():
					value = _text
				if not value.is_empty():
					return {"target": candidate, "kind": "item", "index": index, "label": label, "text": value}
		elif candidate is Tree:
			var tree: Tree = candidate as Tree
			var point: Vector2 = tree.get_local_mouse_position()
			var item: TreeItem = tree.get_item_at_position(point)
			var column: int = tree.get_column_at_position(point)
			if is_instance_valid(item) and column >= 0:
				var value: String = item.get_tooltip_text(column)
				if candidate == _target and _kind == "tree" and item == _tree_item and column == _tree_column and value.is_empty():
					value = _text
				if not value.is_empty():
					return {"target": candidate, "kind": "tree", "tree_item": item, "column": column, "text": value}
		elif candidate is TabBar:
			var tabs: TabBar = candidate as TabBar
			var index: int = tabs.get_tab_idx_at_point(tabs.get_local_mouse_position())
			if index >= 0:
				var value: String = tabs.get_tab_tooltip(index)
				if candidate == _target and _kind == "tab" and index == _item_index and value.is_empty():
					value = _text
				if not value.is_empty():
					return {"target": candidate, "kind": "tab", "index": index, "text": value}
		elif candidate is TabContainer:
			var tabs: TabContainer = candidate as TabContainer
			var index: int = tabs.get_tab_idx_at_point(tabs.get_local_mouse_position())
			if index >= 0:
				var value: String = tabs.get_tab_tooltip(index)
				if candidate == _target and _kind == "tabs" and index == _item_index and value.is_empty():
					value = _text
				if not value.is_empty():
					return {"target": candidate, "kind": "tabs", "index": index, "text": value}
		var message: String = candidate.tooltip_text
		if candidate == _target and _kind == "control" and message.is_empty():
			message = _text
		if not message.is_empty():
			return {"target": candidate, "kind": "control", "text": message}
		candidate = candidate.get_parent() as Control
	return {}

func _same_item(hint: Dictionary) -> bool:
	if String(hint.get("kind", "")) != _kind:
		return false
	match _kind:
		"item":
			return int(hint.get("index", -1)) == _item_index and String(hint.get("label", "")) == _item_label
		"tree":
			return hint.get("tree_item") == _tree_item and int(hint.get("column", -1)) == _tree_column
		"tab", "tabs":
			return int(hint.get("index", -1)) == _item_index
	return true

func _suppress() -> void:
	if not is_instance_valid(_target):
		return
	match _kind:
		"item":
			var list: ItemList = _target as ItemList
			if list != null and _item_index >= 0 and _item_index < list.item_count:
				list.set_item_tooltip(_item_index, "")
		"tree":
			if is_instance_valid(_tree_item):
				_tree_item.set_tooltip_text(_tree_column, "")
		"tab":
			var bar: TabBar = _target as TabBar
			if bar != null and _item_index >= 0 and _item_index < bar.tab_count:
				bar.set_tab_tooltip(_item_index, " ")
		"tabs":
			var container: TabContainer = _target as TabContainer
			if container != null and _item_index >= 0 and _item_index < container.get_tab_count():
				container.set_tab_tooltip(_item_index, " ")
		_:
			_target.tooltip_text = ""

func _restore_target() -> void:
	if is_instance_valid(_target):
		match _kind:
			"item":
				var list: ItemList = _target as ItemList
				if list != null and _item_index >= 0 and _item_index < list.item_count and list.get_item_text(_item_index) == _item_label and list.get_item_tooltip(_item_index).is_empty():
					list.set_item_tooltip(_item_index, _text)
			"tree":
				if is_instance_valid(_tree_item) and _tree_column >= 0 and _tree_item.get_tooltip_text(_tree_column).is_empty():
					_tree_item.set_tooltip_text(_tree_column, _text)
			"tab":
				var bar: TabBar = _target as TabBar
				if bar != null and _item_index >= 0 and _item_index < bar.tab_count and bar.get_tab_tooltip(_item_index) == " ":
					bar.set_tab_tooltip(_item_index, _text)
			"tabs":
				var container: TabContainer = _target as TabContainer
				if container != null and _item_index >= 0 and _item_index < container.get_tab_count() and container.get_tab_tooltip(_item_index) == " ":
					container.set_tab_tooltip(_item_index, _text)
			_:
				if _target.tooltip_text.is_empty():
					_target.tooltip_text = _text
	_target = null
	_kind = ""
	_item_index = -1
	_item_label = ""
	_tree_item = null
	_tree_column = -1
	_text = ""

func _reset() -> void:
	_restore_target()
	_panel.hide()
	_elapsed = 0.0
	_leave = 0.0

func _show_caption() -> void:
	if not is_instance_valid(_target) or _text.is_empty():
		return
	var available: Vector2 = get_viewport().get_visible_rect().size
	if available.x < 80 or available.y < 80:
		return
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

# Touch help reads the same explanations as desktop hover without firing a click.
func touch_hint_at(point: Vector2) -> String:
	_reset()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	var hint := _hint_under_pointer()
	motion = InputEventMouseMotion.new()
	motion.position = Vector2(-100, -100)
	get_viewport().push_input(motion, true)
	return String(hint.get("text", ""))
