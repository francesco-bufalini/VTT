extends Control

const MENU_BACKGROUND_DIRECTORY := "res://assets/menu/background/slideshow"
const MENU_BACKGROUND_FALLBACK := "res://assets/menu/background/menu_background.webp"
const SLIDE_DURATION_SECONDS := 60.0
const FADE_DURATION_SECONDS := 2.5

var _background_layers: Array[TextureRect] = []
var _background_paths: Array[String] = []
var _background_index: int = 0
var _active_layer: int = 0
var _slide_elapsed: float = 0.0
var _slide_tween: Tween
var _background_root: Control
var _background_rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_image_background()
	_build_vignette()


func _process(delta: float) -> void:
	if _background_paths.size() <= 1:
		return
	_slide_elapsed += delta
	if _slide_elapsed >= SLIDE_DURATION_SECONDS:
		_slide_elapsed = 0.0
		_show_next_background()


func _build_image_background() -> void:
	_background_root = Control.new()
	_background_root.name = "FantasyBackground"
	_background_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background_root.clip_contents = true
	add_child(_background_root)

	_background_paths = _discover_backgrounds()
	if (
		_background_paths.is_empty()
		and ResourceLoader.exists(MENU_BACKGROUND_FALLBACK)
	):
		_background_paths.append(MENU_BACKGROUND_FALLBACK)

	if _background_paths.is_empty():
		push_error("MenuBackdrop: nessuna texture di sfondo disponibile.")
		return

	for layer_index: int in range(2):
		var layer := TextureRect.new()
		layer.name = "BackgroundLayer%d" % layer_index
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		layer.modulate = Color(1.0, 1.0, 1.0, 0.0)
		_background_root.add_child(layer)
		_background_layers.append(layer)

	_background_rng.randomize()
	_background_index = _background_rng.randi_range(
		0,
		_background_paths.size() - 1
	)
	_background_layers[0].texture = load(
		_background_paths[_background_index]
	)
	_background_layers[0].modulate.a = 1.0


func _discover_backgrounds() -> Array[String]:
	var paths: Array[String] = []
	var directory := DirAccess.open(MENU_BACKGROUND_DIRECTORY)
	if directory == null:
		return paths

	for file_name: String in directory.get_files():
		var extension: String = file_name.get_extension().to_lower()
		if extension not in ["jpg", "jpeg", "png", "webp"]:
			continue
		paths.append(MENU_BACKGROUND_DIRECTORY + "/" + file_name)

	paths.sort()
	return paths


func _pick_random_background_index() -> int:
	if _background_paths.size() <= 1:
		return 0
	var next_index := _background_index
	while next_index == _background_index:
		next_index = _background_rng.randi_range(
			0,
			_background_paths.size() - 1
		)
	return next_index


func _show_next_background() -> void:
	if _background_paths.size() <= 1 or _background_layers.size() < 2:
		return

	var incoming_layer_index: int = 1 - _active_layer
	var outgoing: TextureRect = _background_layers[_active_layer]
	var incoming: TextureRect = _background_layers[incoming_layer_index]

	_background_index = _pick_random_background_index()
	incoming.texture = load(_background_paths[_background_index])
	incoming.modulate.a = 0.0
	incoming.position = Vector2.ZERO
	incoming.scale = Vector2.ONE
	outgoing.position = Vector2.ZERO
	outgoing.scale = Vector2.ONE

	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()

	_slide_tween = create_tween()
	_slide_tween.set_parallel(true)
	_slide_tween.set_trans(Tween.TRANS_SINE)
	_slide_tween.set_ease(Tween.EASE_IN_OUT)
	_slide_tween.tween_property(
		incoming,
		"modulate:a",
		1.0,
		FADE_DURATION_SECONDS
	)
	_slide_tween.tween_property(
		outgoing,
		"modulate:a",
		0.0,
		FADE_DURATION_SECONDS
	)
	_active_layer = incoming_layer_index


func _build_vignette() -> void:
	var overlay := ColorRect.new()
	overlay.name = "CinematicVignette"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

void fragment() {
	vec2 p = UV - vec2(0.5);
	p.x *= 0.78;
	float edge = smoothstep(0.22, 0.67, length(p));
	float bottom = smoothstep(0.48, 0.95, UV.y);
	float top = 1.0 - smoothstep(0.0, 0.23, UV.y);
	float alpha = clamp(edge * 0.62 + bottom * 0.24 + top * 0.10, 0.0, 0.72);
	COLOR = vec4(0.005, 0.006, 0.010, alpha);
}
"""
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	overlay.material = shader_material
	add_child(overlay)
