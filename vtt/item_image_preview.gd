extends AcceptDialog

# Item images are rendered from explicit 5etools hrefs or relative homebrew
# assets. Missing images do not add broken buttons to catalog rows.
const DialogLayout = preload("res://vtt/dialog_layout.gd")
var _request: HTTPRequest
var _picture: TextureRect
var _status: Label
static var _official_images: Dictionary = {}
static var _images_loaded := false
var _expected_url := ""


static func _image_href(value: Variant) -> String:
	if value is String:
		return String(value).strip_edges()
	if value is Dictionary:
		var info: Dictionary = value as Dictionary
		if info.has("href"):
			return _image_href(info["href"])
		if String(info.get("type", "")) == "external":
			return String(info.get("url", ""))
		return String(info.get("path", info.get("url", ""))).strip_edges()
	if value is Array:
		for entry: Variant in value:
			var path: String = _image_href(entry)
			if not path.is_empty():
				return path
	return ""


static func _load_official_images() -> void:
	if _images_loaded:
		return
	_images_loaded = true
	for index: int in range(5):
		var file: FileAccess = FileAccess.open("res://vtt/data/item_images_%d.json" % index, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			_official_images.merge(parsed as Dictionary, true)


static func image_source(item: Dictionary) -> String:
	var source := ""
	for key: String in ["image", "images", "imageUrl", "img", "fluffImages", "fluff_images", "fluff"]:
		if not item.has(key):
			continue
		source = _image_href(item[key])
		if not source.is_empty():
			break
	if source.is_empty():
		return ""
	if source.begins_with("https://"):
		return source
	if source.begins_with("http://"):
		return ""
	if source.begins_with("res://") or source.begins_with("user://"):
		return source if FileAccess.file_exists(source) or ResourceLoader.exists(source) else ""
	if source.begins_with("img/"):
		return "https://5e.tools/" + source.uri_encode().replace("%2F", "/")
	if source.begins_with("/img/"):
		return "https://5e.tools" + source.uri_encode().replace("%2F", "/")
	if String(item.get("origin", "")) == "homebrew":
		if ".." in source:
			return ""
		for folder: String in ["user://homebrew", "res://homebrew"]:
			var candidate: String = folder.path_join(source)
			if FileAccess.file_exists(candidate) or ResourceLoader.exists(candidate):
				return candidate
	return ""


func setup() -> void:
	title = "Immagine dell'oggetto"
	min_size = Vector2i(520, 400)
	get_ok_button().text = "Chiudi"
	var body := VBoxContainer.new()
	add_child(body)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_status)
	_picture = TextureRect.new()
	_picture.custom_minimum_size = Vector2(480, 320)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	body.add_child(_picture)
	_request = HTTPRequest.new()
	_request.body_size_limit = 4 * 1024 * 1024
	_request.timeout = 12
	add_child(_request)
	_request.request_completed.connect(_on_loaded)


func preview(item: Dictionary) -> void:
	var source: String = image_source(item)
	if source.is_empty():
		return
	_expected_url = source
	title = "Immagine · " + String(item.get("name", "Oggetto"))
	_picture.texture = null
	_status.text = "Caricamento immagine…"
	DialogLayout.popup(self, Vector2i(650, 530), 0.9)
	if source.begins_with("res://") or source.begins_with("user://"):
		_show_file(source)
	else:
		_request.cancel_request()
		if _request.request(source) != OK:
			_status.text = "Impossibile avviare il caricamento."


func _show_file(path: String) -> void:
	var img: Image = Image.load_from_file(path)
	if img == null or img.is_empty():
		_status.text = "File immagine non leggibile."
		return
	_picture.texture = ImageTexture.create_from_image(img)
	_status.text = ""


func _on_loaded(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_status.text = "Immagine non disponibile."
		return
	var img := Image.new()
	var decoded: Error = img.load_webp_from_buffer(body)
	if decoded != OK:
		decoded = img.load_png_from_buffer(body)
	if decoded != OK:
		decoded = img.load_jpg_from_buffer(body)
	if decoded != OK:
		_status.text = "Formato immagine non supportato."
		return
	_picture.texture = ImageTexture.create_from_image(img)
	_status.text = ""
