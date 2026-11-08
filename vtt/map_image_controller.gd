extends Node3D
## Imports calibrated 2D maps as one-cell-high solid platforms in the 3D board.
## Images are embedded in snapshots so local saves, undo and peers retain them.

const ImagePreview = preload("res://vtt/map_image_preview.gd")
const MAX_SOURCE_BYTES := 24 * 1024 * 1024
const MAX_IMAGE_BYTES := 1200000
const MAX_ENCODED_TOTAL := 3200000
const MAX_LAYERS := 12
const MAX_CELLS := 200.0

var board_root: Node3D
var _images_root: Node3D
var _records: Array[Dictionary] = []

var _file_dialog: FileDialog
var _settings: ConfirmationDialog
var _error_dialog: AcceptDialog
var _manage_dialog: AcceptDialog
var _manage_list: ItemList
var _preview: Control
var _width: SpinBox
var _height: SpinBox
var _offset_x: SpinBox
var _offset_z: SpinBox
var _lock_aspect: CheckBox
var _hint: Label

var _image_bytes: PackedByteArray
var _image_format := ""
var _image_name := ""
var _source_aspect := 1.0
var _texture: Texture2D
var _placing := false
var _ghost: Node3D
var _anchor := Vector3.ZERO
var _anchor_valid := false


func setup(root: Node3D) -> void:
	board_root = root
	_images_root = Node3D.new()
	_images_root.name = "PlacedMapImages"
	add_child(_images_root)
	_build_dialogs()


func _cell_size() -> float:
	return maxf(float(board_root.get("cell_size")), 0.001)


func open_import_dialog() -> void:
	if _placing:
		_cancel_placement()
	board_root.call("release_camera_control")
	_file_dialog.popup_centered(Vector2i(850, 600))


func open_manage_dialog() -> void:
	_refresh_manage_list()
	board_root.call("release_camera_control")
	_manage_dialog.popup_centered(Vector2i(490, 440))


func _refresh_manage_list() -> void:
	_manage_list.clear()
	for record: Dictionary in _records:
		_manage_list.add_item("%s · %g × %g cubi" % [record.name, float(record.width_cells), float(record.height_cells)])


func _remove_selected_plane() -> void:
	var selected: PackedInt32Array = _manage_list.get_selected_items()
	if selected.is_empty():
		return
	var index: int = selected[0]
	if index < 0 or index >= _records.size():
		return
	remove_map_image(String(_records[index].id))
	_refresh_manage_list()


func is_placing() -> bool:
	return _placing


func _build_dialogs() -> void:
	var ui: CanvasLayer = board_root.get_node("UI") as CanvasLayer
	_file_dialog = FileDialog.new()
	_file_dialog.title = "Importa immagine mappa 2D"
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.add_filter("*.png,*.jpg,*.jpeg,*.webp", "Immagini mappa")
	ui.add_child(_file_dialog)
	_file_dialog.file_selected.connect(_on_image_selected)
	_file_dialog.canceled.connect(_restore_camera)

	_settings = ConfirmationDialog.new()
	_settings.title = "Scala e allineamento alla griglia"
	_settings.ok_button_text = "Posiziona sulla mappa 3D"
	ui.add_child(_settings)
	_settings.confirmed.connect(_start_placement)
	_settings.canceled.connect(_restore_camera)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	_settings.add_child(layout)
	var instructions := Label.new()
	instructions.text = "La griglia resta fissa: ridimensiona e sposta l'immagine per allineare le caselle già disegnate."
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(instructions)

	_preview = ImagePreview.new()
	_preview.custom_minimum_size = Vector2(520, 330)
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(_preview)

	_lock_aspect = CheckBox.new()
	_lock_aspect.text = "Mantieni proporzioni originali"
	_lock_aspect.button_pressed = true
	layout.add_child(_lock_aspect)
	_lock_aspect.toggled.connect(_on_lock_changed)

	var dimensions := HBoxContainer.new()
	layout.add_child(dimensions)
	_width = _add_spinner(dimensions, "Larghezza (cubi)", 0.5, MAX_CELLS, 0.1)
	_height = _add_spinner(dimensions, "Altezza (cubi)", 0.5, MAX_CELLS, 0.1)
	_width.value_changed.connect(_on_width_changed)
	_height.value_changed.connect(_on_height_changed)

	var offsets := HBoxContainer.new()
	layout.add_child(offsets)
	_offset_x = _add_spinner(offsets, "Spostamento X (cubi)", -0.99, 0.99, 0.01)
	_offset_z = _add_spinner(offsets, "Spostamento Z (cubi)", -0.99, 0.99, 0.01)
	_offset_x.value_changed.connect(_refresh_preview.unbind(1))
	_offset_z.value_changed.connect(_refresh_preview.unbind(1))
	var note := Label.new()
	note.text = "Il piano avrà spessore 1 cubo. Dopo la calibrazione, clicca dove collocarlo; destro/Esc annulla."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(note)

	_error_dialog = AcceptDialog.new()
	_error_dialog.title = "Importazione mappa 2D"
	ui.add_child(_error_dialog)
	_error_dialog.confirmed.connect(_restore_camera)

	_manage_dialog = AcceptDialog.new()
	_manage_dialog.title = "Piani immagine 2D"
	_manage_dialog.ok_button_text = "Chiudi"
	ui.add_child(_manage_dialog)
	_manage_dialog.confirmed.connect(_restore_camera)
	_manage_dialog.canceled.connect(_restore_camera)
	var manage_column := VBoxContainer.new()
	_manage_dialog.add_child(manage_column)
	_manage_list = ItemList.new()
	_manage_list.custom_minimum_size = Vector2(440, 300)
	manage_column.add_child(_manage_list)
	var remove_button := Button.new()
	remove_button.text = "Rimuovi piano selezionato (annullabile con Ctrl+Z)"
	remove_button.pressed.connect(_remove_selected_plane)
	manage_column.add_child(remove_button)

	_hint = Label.new()
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.offset_left = -330.0
	_hint.offset_right = 330.0
	_hint.offset_top = 70.0
	_hint.offset_bottom = 125.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", Color(1.0, 0.83, 0.52))
	_hint.text = "Posiziona il piano sulla mappa con un clic sinistro. Destro / Esc: annulla."
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.hide()
	ui.add_child(_hint)


func _add_spinner(parent: HBoxContainer, caption: String, low: float, high: float, step_value: float) -> SpinBox:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var label := Label.new()
	label.text = caption
	column.add_child(label)
	var spinner := SpinBox.new()
	spinner.min_value = low
	spinner.max_value = high
	spinner.step = step_value
	spinner.allow_greater = false
	spinner.allow_lesser = false
	spinner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(spinner)
	return spinner


func _on_image_selected(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_show_error("Impossibile aprire il file selezionato.")
		return
	var file_size: int = file.get_length()
	file.close()
	if file_size <= 0 or file_size > MAX_SOURCE_BYTES:
		_show_error("Il file deve essere un'immagine non vuota di massimo 24 MB.")
		return
	var image := Image.new()
	if image.load(path) != OK or image.is_empty():
		_show_error("Formato immagine non valido (PNG, JPG o WebP).")
		return
	if image.get_width() > 8192 or image.get_height() > 8192:
		_show_error("L'immagine non può superare 8192 pixel per lato.")
		return
	var longest: int = maxi(image.get_width(), image.get_height())
	if longest > 2048:
		var factor := 2048.0 / float(longest)
		image.resize(
			maxi(1, roundi(float(image.get_width()) * factor)),
			maxi(1, roundi(float(image.get_height()) * factor)),
			Image.INTERPOLATE_LANCZOS
		)
	_source_aspect = float(image.get_width()) / float(image.get_height())
	_image_format = "png"
	_image_bytes = image.save_png_to_buffer()
	if _image_bytes.size() > MAX_IMAGE_BYTES:
		_image_format = "webp"
		_image_bytes = image.save_webp_to_buffer(true, 0.88)
	while _image_bytes.size() > MAX_IMAGE_BYTES and maxi(image.get_width(), image.get_height()) > 256:
		image.resize(maxi(1, int(image.get_width() * 0.5)), maxi(1, int(image.get_height() * 0.5)), Image.INTERPOLATE_LANCZOS)
		_image_bytes = image.save_webp_to_buffer(true, 0.82)
	if _image_bytes.is_empty() or _image_bytes.size() > MAX_IMAGE_BYTES:
		_show_error("Immagine troppo grande per il salvataggio e la sincronizzazione.")
		return
	_texture = ImageTexture.create_from_image(image)
	_image_name = path.get_file().substr(0, 100)
	_lock_aspect.button_pressed = true
	_width.set_value_no_signal(12.0)
	_height.set_value_no_signal(clampf(12.0 / _source_aspect, 0.5, MAX_CELLS))
	_offset_x.set_value_no_signal(0.0)
	_offset_z.set_value_no_signal(0.0)
	_refresh_preview()
	board_root.call("release_camera_control")
	_settings.popup_centered(Vector2i(660, 695))


func _show_error(message: String) -> void:
	_error_dialog.dialog_text = message
	board_root.call("release_camera_control")
	_error_dialog.popup_centered()


func _on_width_changed(value: float) -> void:
	if _lock_aspect.button_pressed:
		_height.set_value_no_signal(clampf(value / _source_aspect, 0.5, MAX_CELLS))
	_refresh_preview()


func _on_height_changed(value: float) -> void:
	if _lock_aspect.button_pressed:
		_width.set_value_no_signal(clampf(value * _source_aspect, 0.5, MAX_CELLS))
	_refresh_preview()


func _on_lock_changed(locked: bool) -> void:
	if locked:
		_height.set_value_no_signal(clampf(_width.value / _source_aspect, 0.5, MAX_CELLS))
	_refresh_preview()


func _refresh_preview() -> void:
	_preview.call(
		"set_preview", _texture, _width.value, _height.value,
		_offset_x.value, _offset_z.value
	)


func _make_record(anchor: Vector3) -> Dictionary:
	return {
		"id": str(Time.get_ticks_usec()) + "-" + str(randi()),
		"name": _image_name,
		"format": _image_format,
		"image_data": Marshalls.raw_to_base64(_image_bytes),
		"width_cells": _width.value,
		"height_cells": _height.value,
		"offset_x": _offset_x.value,
		"offset_z": _offset_z.value,
		"position": {"x": anchor.x, "y": anchor.y, "z": anchor.z},
	}


func _start_placement() -> void:
	if _image_bytes.is_empty() or _texture == null:
		_restore_camera()
		return
	var test_records: Array = serialize_map_images()
	test_records.append(_make_record(Vector3.ZERO))
	if not valid_records(test_records):
		_show_error("Limite mappe 2D raggiunto: rimuovi un piano o riduci le immagini (massimo 3,2 MB complessivi).")
		return
	_placing = true
	_anchor_valid = false
	_ghost = _build_plane(_make_record(Vector3.ZERO), _texture, true)
	add_child(_ghost)
	_ghost.hide()
	_hint.show()
	board_root.call("release_camera_control")


func handle_placement_input(event: InputEvent) -> bool:
	if not _placing:
		return false
	if event is InputEventMouseMotion:
		_update_placement(event.position)
		return true
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_placement()
		return true
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_placement()
			return true
		if event.button_index == MOUSE_BUTTON_LEFT:
			_update_placement(event.position)
			if _anchor_valid:
				var record := _make_record(_anchor)
				var before: Dictionary = board_root.call("begin_undo_transaction")
				var next_records: Array = serialize_map_images()
				next_records.append(record)
				if apply_map_images(next_records):
					board_root.call("commit_undo_transaction", before)
					_cancel_placement()
				else:
					_show_error("Non è stato possibile aggiungere il piano.")
			return true
		return true
	return event is InputEventKey


func _update_placement(screen_position: Vector2) -> void:
	var camera: Camera3D = board_root.get_node("Camera3D") as Camera3D
	var origin: Vector3 = camera.project_ray_origin(screen_position)
	var direction: Vector3 = camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * camera.far)
	query.collision_mask = 0xFFFFFFFF & ~(2 | (1 << 20))
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var point: Vector3
	if not hit.is_empty():
		point = hit.position
	else:
		var intersection: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)
		if not intersection is Vector3:
			_anchor_valid = false
			_ghost.hide()
			return
		point = intersection
	var cell: float = _cell_size()
	_anchor = Vector3(roundf(point.x / cell) * cell, point.y, roundf(point.z / cell) * cell)
	_anchor_valid = true
	_ghost.position = _anchor
	_ghost.show()


func _cancel_placement() -> void:
	_placing = false
	_anchor_valid = false
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
		_ghost = null
	if _hint != null:
		_hint.hide()
	_restore_camera()


func _restore_camera() -> void:
	if not _placing and board_root != null and is_instance_valid(board_root):
		board_root.call("capture_camera_control")


func serialize_map_images() -> Array:
	return _records.duplicate(true)


static func valid_records(value: Variant) -> bool:
	if not value is Array or value.size() > MAX_LAYERS:
		return false
	var seen: Dictionary = {}
	var total := 0
	for entry: Variant in value:
		if not entry is Dictionary:
			return false
		var record: Dictionary = entry
		var uid: Variant = record.get("id")
		var data: Variant = record.get("image_data")
		if not uid is String or uid.is_empty() or uid.length() > 120 or seen.has(uid):
			return false
		seen[uid] = true
		if not record.get("name") is String or String(record.name).length() > 100:
			return false
		if String(record.get("format", "")) not in ["png", "webp"]:
			return false
		if not data is String or data.is_empty() or data.length() > 1600000 or data.length() % 4 != 0:
			return false
		total += data.length()
		if total > MAX_ENCODED_TOTAL:
			return false
		for key: String in ["width_cells", "height_cells", "offset_x", "offset_z"]:
			var number: Variant = record.get(key)
			if not (number is float or number is int) or not is_finite(float(number)):
				return false
		if float(record.width_cells) < 0.5 or float(record.width_cells) > MAX_CELLS:
			return false
		if float(record.height_cells) < 0.5 or float(record.height_cells) > MAX_CELLS:
			return false
		if absf(float(record.offset_x)) > 0.99 or absf(float(record.offset_z)) > 0.99:
			return false
		var position: Variant = record.get("position")
		if not position is Dictionary:
			return false
		for axis: String in ["x", "y", "z"]:
			var coordinate: Variant = position.get(axis)
			if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)) or absf(float(coordinate)) > 100000.0:
				return false
	return true


func apply_map_images(value: Variant) -> bool:
	if not valid_records(value):
		return false
	if _records == value:
		return true
	# Decode everything before replacing any existing planes.
	var prepared: Array[Dictionary] = []
	for entry: Variant in value:
		var record: Dictionary = entry
		var image := Image.new()
		var bytes: PackedByteArray = Marshalls.base64_to_raw(String(record.image_data))
		var error: Error = image.load_png_from_buffer(bytes) if record.format == "png" else image.load_webp_from_buffer(bytes)
		if error != OK or image.is_empty() or image.get_width() > 8192 or image.get_height() > 8192:
			return false
		prepared.append({"record": record, "texture": ImageTexture.create_from_image(image)})
	for node: Node in _images_root.get_children():
		_images_root.remove_child(node)
		node.queue_free()
	_records.clear()
	for item: Dictionary in prepared:
		var record: Dictionary = item.record
		var mesh_root: Node3D = _build_plane(record, item.texture, false)
		_images_root.add_child(mesh_root)
		_records.append(record.duplicate(true))
	var grid: Node = board_root.get_node_or_null("VolumetricGrid")
	if grid != null and grid.has_method("mark_map_dirty"):
		grid.call("mark_map_dirty")
	return true


func _build_plane(record: Dictionary, texture: Texture2D, ghost: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "MapImage_" + String(record.id).substr(0, 16)
	root.set_meta("map_image_id", String(record.id))
	var position_data: Dictionary = record.position
	root.position = Vector3(
		float(position_data.x), float(position_data.y), float(position_data.z)
	)
	var cell: float = _cell_size()
	var size_x: float = float(record.width_cells) * cell
	var size_z: float = float(record.height_cells) * cell
	var offset := Vector3(float(record.offset_x) * cell, 0, float(record.offset_z) * cell)
	var image_plane := PlaneMesh.new()
	image_plane.size = Vector2(size_x, size_z)
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.68 if ghost else 1.0)
	image_plane.material = material
	var surface := MeshInstance3D.new()
	surface.name = "ImageSurface"
	surface.mesh = image_plane
	surface.position = offset + Vector3.UP * (cell + 0.002 * cell)
	root.add_child(surface)
	if not ghost:
		var solid := StaticBody3D.new()
		solid.name = "OneCubeSupport"
		solid.collision_layer = 1
		solid.collision_mask = 0
		solid.position = offset + Vector3.UP * (cell * 0.5)
		root.add_child(solid)
		var box := CollisionShape3D.new()
		box.name = "SupportShape"
		var shape := BoxShape3D.new()
		shape.size = Vector3(size_x, cell, size_z)
		box.shape = shape
		solid.add_child(box)
	return root


func remove_map_image(uid: String) -> bool:
	var next_records: Array = serialize_map_images()
	for index: int in range(next_records.size()):
		if String(next_records[index].get("id", "")) != uid:
			continue
		var before: Dictionary = board_root.call("begin_undo_transaction")
		next_records.remove_at(index)
		if not apply_map_images(next_records):
			return false
		board_root.call("commit_undo_transaction", before)
		return true
	return false
