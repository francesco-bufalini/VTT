extends Control

const ACTIVE_CAMPAIGNS_SCENE_PATH := "res://vtt/menu/active_campaigns.tscn"
const MENU_BACKGROUND_TEXTURE := (
	"res://assets/menu/background/lithophane_background.webp"
)
# Legacy paths kept because the older helper functions below are retained
# for reference, even though the main menu no longer instantiates them.
const MENU_SKY_HDR := (
	"res://assets/menu/environment/sky/"
	+ "kloppenheim_06_puresky_1k.hdr"
)
const CASTLE_PATHS := [
	"res://assets/menu/castle/Castle.glb",
	"res://SFON VTST/castle/Castle.glb",
	"res://SFON VTST/Castle.glb",
	"res://castle/Castle.glb",
	"res://Castle.glb"
]
const CAMERA_TARGET := Vector3(0.0, 0.0, 0.0)
const CAMERA_BASE_RADIUS := 19.5
const CAMERA_BASE_HEIGHT := 0.12
const MENU_SKY_HDR := (
	"res://assets/menu/environment/sky/"
	+ "kloppenheim_06_puresky_1k.hdr"
)
const MENU_NATURE_DIR := "res://assets/menu/environment/kenney"
const MOUNTAIN_MODEL_PATHS := [
	MENU_NATURE_DIR + "/rock_tallA.glb",
	MENU_NATURE_DIR + "/rock_tallB.glb",
	MENU_NATURE_DIR + "/rock_tallH.glb"
]
const RIVER_ROCK_PATHS := [
	MENU_NATURE_DIR + "/rock_largeA.glb",
	MENU_NATURE_DIR + "/rock_largeB.glb",
	MENU_NATURE_DIR + "/stone_largeA.glb",
	MENU_NATURE_DIR + "/stone_largeB.glb"
]
const RIVER_TREE_PATHS := [
	MENU_NATURE_DIR + "/tree_pineTallA.glb",
	MENU_NATURE_DIR + "/tree_pineTallB.glb"
]

var _options_dialog: AcceptDialog
var _new_campaign_dialog: ConfirmationDialog
var _new_campaign_name: LineEdit

var _background_viewport: SubViewport
var _background_world: Node3D
var _castle_root: Node3D
var _camera: Camera3D
var _torch_left: OmniLight3D
var _torch_right: OmniLight3D
var _elapsed: float = 0.0
var _mouse_parallax_target: Vector2 = Vector2.ZERO
var _mouse_parallax: Vector2 = Vector2.ZERO


func _ready() -> void:
	_build_ui()


func _process(delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return

	_elapsed += delta
	_mouse_parallax = _mouse_parallax.lerp(
		_mouse_parallax_target,
		minf(delta * 3.0, 1.0)
	)

	var pan: float = sin(_elapsed * 0.105) * deg_to_rad(2.6)
	var radius: float = CAMERA_BASE_RADIUS + sin(_elapsed * 0.071) * 0.28
	var height: float = (
		CAMERA_BASE_HEIGHT
		+ sin(_elapsed * 0.089) * 0.10
		- _mouse_parallax.y * 0.26
	)
	var parallax_x: float = _mouse_parallax.x * 0.42

	_camera.position = Vector3(
		sin(pan) * radius + parallax_x,
		height,
		cos(pan) * radius
	)
	_camera.look_at(
		CAMERA_TARGET
		+ Vector3(
			_mouse_parallax.x * 0.20,
			-_mouse_parallax.y * 0.12,
			0.0
		),
		Vector3.UP
	)

	if _torch_left != null and is_instance_valid(_torch_left):
		_torch_left.light_energy = (
			2.45
			+ sin(_elapsed * 7.7) * 0.22
			+ sin(_elapsed * 13.1) * 0.11
		)
	if _torch_right != null and is_instance_valid(_torch_right):
		_torch_right.light_energy = (
			2.20
			+ sin(_elapsed * 8.3 + 1.4) * 0.20
			+ sin(_elapsed * 12.4) * 0.10
		)


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return
	var mouse_event := event as InputEventMouseMotion
	var normalized: Vector2 = Vector2(
		mouse_event.position.x / viewport_size.x,
		mouse_event.position.y / viewport_size.y
	)
	_mouse_parallax_target = (
		normalized - Vector2(0.5, 0.5)
	) * 2.0


func _build_ui() -> void:
	_build_3d_background()
	_build_vignette()
	_build_title()
	_build_bottom_controls()
	_build_new_campaign_dialog()
	_build_options_dialog()


func _build_3d_background() -> void:
	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "FantasyBackground"
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(viewport_container)

	_background_viewport = SubViewport.new()
	_background_viewport.name = "FantasyViewport"
	_background_viewport.size = Vector2i(1280, 720)
	_background_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_background_viewport.transparent_bg = false
	viewport_container.add_child(_background_viewport)

	_background_world = Node3D.new()
	_background_world.name = "MenuWorld"
	_background_viewport.add_child(_background_world)

	_build_lithophane_background()

	_camera = Camera3D.new()
	_camera.name = "MenuCamera"
	_camera.fov = 48.0
	_camera.near = 0.05
	_camera.far = 100.0
	_camera.position = Vector3(0.0, CAMERA_BASE_HEIGHT, CAMERA_BASE_RADIUS)
	_camera.look_at(CAMERA_TARGET, Vector3.UP)
	_camera.current = true
	_background_world.add_child(_camera)


func _build_lithophane_background() -> void:
	var background := MeshInstance3D.new()
	background.name = "LithophaneBackground"

	var plane := PlaneMesh.new()
	plane.size = Vector2(26.0, 17.333333)
	plane.subdivide_width = 160
	plane.subdivide_depth = 106
	background.mesh = plane

	# The supplied OBJ is a very dense lithophane (~1.2M surface vertices).
	# For a menu, keep its characteristic shallow relief but generate it from
	# the same supplied texture at runtime. This avoids a huge import cost.
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D background_texture;
uniform float relief_strength = 0.34;

void vertex() {
	float luminance = dot(
		texture(background_texture, UV).rgb,
		vec3(0.2126, 0.7152, 0.0722)
	);
	VERTEX.y -= luminance * relief_strength;
}

void fragment() {
	ALBEDO = texture(background_texture, UV).rgb;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader

	var background_texture: Texture2D = null
	if ResourceLoader.exists(MENU_BACKGROUND_TEXTURE):
		var loaded: Resource = ResourceLoader.load(MENU_BACKGROUND_TEXTURE)
		if loaded is Texture2D:
			background_texture = loaded as Texture2D

	if background_texture == null:
		push_error(
			"MainMenu: texture di sfondo non trovata: "
			+ MENU_BACKGROUND_TEXTURE
		)
	else:
		material.set_shader_parameter(
			"background_texture",
			background_texture
		)

	background.material_override = material
	background.rotation_degrees.x = -90.0
	background.position = Vector3(0.0, -0.02, 0.0)
	_background_world.add_child(background)


func _build_lighting() -> void:
	var moon := DirectionalLight3D.new()
	moon.name = "MoonLight"
	moon.rotation_degrees = Vector3(-46.0, -28.0, 0.0)
	moon.light_color = Color(0.56, 0.66, 0.91)
	moon.light_energy = 1.45
	moon.shadow_enabled = true
	_background_world.add_child(moon)

	_torch_left = _make_torch(
		"TorchLeft",
		Vector3(-2.65, -0.25, 2.65)
	)
	_torch_right = _make_torch(
		"TorchRight",
		Vector3(2.55, -0.10, 2.30)
	)
	_background_world.add_child(_torch_left)
	_background_world.add_child(_torch_right)


func _make_torch(light_name: String, light_position: Vector3) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = light_name
	light.position = light_position
	light.light_color = Color(1.0, 0.49, 0.17)
	light.light_energy = 2.3
	light.omni_range = 5.8
	light.shadow_enabled = true
	return light


func _build_dust_particles() -> void:
	var particles := GPUParticles3D.new()
	particles.name = "AtmosphericDust"
	particles.amount = 120
	particles.lifetime = 8.0
	particles.randomness = 0.75
	particles.visibility_aabb = AABB(
		Vector3(-9.0, -5.0, -8.0),
		Vector3(18.0, 12.0, 16.0)
	)

	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(7.5, 4.3, 5.0)
	process_material.direction = Vector3(0.15, 0.85, 0.05)
	process_material.spread = 80.0
	process_material.initial_velocity_min = 0.025
	process_material.initial_velocity_max = 0.095
	process_material.gravity = Vector3(0.0, 0.012, 0.0)
	process_material.scale_min = 0.6
	process_material.scale_max = 1.5
	process_material.color = Color(0.78, 0.72, 0.60, 0.24)
	particles.process_material = process_material

	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	var particle_material := StandardMaterial3D.new()
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	particle_material.albedo_color = Color(0.92, 0.84, 0.70, 0.34)
	quad.material = particle_material
	particles.draw_pass_1 = quad
	particles.position = Vector3(0.0, 0.4, 0.0)
	_background_world.add_child(particles)


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


func _build_title() -> void:
	var title_margin := MarginContainer.new()
	title_margin.name = "TitleArea"
	title_margin.anchor_left = 0.0
	title_margin.anchor_top = 0.0
	title_margin.anchor_right = 0.0
	title_margin.anchor_bottom = 0.0
	title_margin.offset_left = 34.0
	title_margin.offset_top = 24.0
	title_margin.offset_right = 930.0
	title_margin.offset_bottom = 160.0
	title_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_margin)

	var title := Label.new()
	title.name = "GameTitle"
	title.text = "Virtual Table Story Teller"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	title.add_theme_font_override("font", _medieval_title_font())
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override(
		"font_color",
		Color(0.94, 0.85, 0.64)
	)
	title.add_theme_color_override(
		"font_outline_color",
		Color(0.055, 0.035, 0.025, 1.0)
	)
	title.add_theme_color_override(
		"font_shadow_color",
		Color(0.0, 0.0, 0.0, 0.88)
	)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title_margin.add_child(title)


func _medieval_title_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Old English Text MT",
		"UnifrakturCook",
		"UnifrakturMaguntia",
		"Luminari",
		"Georgia"
	])
	font.font_weight = 600
	return font


func _menu_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Palatino Linotype",
		"Book Antiqua",
		"Palatino",
		"Georgia"
	])
	return font


func _build_bottom_controls() -> void:
	var controls_anchor := MarginContainer.new()
	controls_anchor.name = "BottomControls"
	controls_anchor.anchor_left = 0.0
	controls_anchor.anchor_top = 1.0
	controls_anchor.anchor_right = 0.0
	controls_anchor.anchor_bottom = 1.0
	controls_anchor.offset_left = 28.0
	controls_anchor.offset_top = -270.0
	controls_anchor.offset_right = 390.0
	controls_anchor.offset_bottom = -28.0
	add_child(controls_anchor)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _menu_panel_style())
	controls_anchor.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)

	var active_button: Button = _menu_button("Campagne attive")
	active_button.pressed.connect(_open_active_campaigns)
	layout.add_child(active_button)

	var new_button: Button = _menu_button("Nuova campagna")
	new_button.pressed.connect(_request_new_campaign)
	layout.add_child(new_button)

	var options_button: Button = _menu_button("Opzioni")
	options_button.pressed.connect(_show_options_placeholder)
	layout.add_child(options_button)

	var exit_button: Button = _menu_button("Esci")
	exit_button.pressed.connect(func() -> void: get_tree().quit())
	layout.add_child(exit_button)


func _menu_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.027, 0.035, 0.72)
	style.border_color = Color(0.56, 0.43, 0.24, 0.62)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.52)
	style.shadow_size = 12
	return style


func _menu_button(label_text: String) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(300, 40)
	button.add_theme_font_override("font", _menu_font())
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override(
		"font_color",
		Color(0.90, 0.84, 0.71)
	)
	button.add_theme_color_override(
		"font_hover_color",
		Color(1.0, 0.92, 0.72)
	)
	button.add_theme_stylebox_override(
		"normal",
		_button_style(
			Color(0.075, 0.072, 0.074, 0.86),
			Color(0.40, 0.31, 0.18, 0.74)
		)
	)
	button.add_theme_stylebox_override(
		"hover",
		_button_style(
			Color(0.15, 0.115, 0.075, 0.94),
			Color(0.78, 0.57, 0.27, 0.92)
		)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_button_style(
			Color(0.20, 0.135, 0.075, 0.98),
			Color(0.93, 0.70, 0.34, 1.0)
		)
	)
	return button


func _button_style(
	background_color: Color,
	border_color: Color
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	return style


func _build_new_campaign_dialog() -> void:
	_new_campaign_dialog = ConfirmationDialog.new()
	_new_campaign_dialog.title = "Nuova campagna"
	_new_campaign_dialog.ok_button_text = "Crea campagna"
	_new_campaign_dialog.cancel_button_text = "Annulla"
	_new_campaign_dialog.min_size = Vector2i(440, 210)
	add_child(_new_campaign_dialog)

	var body := VBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 18
	body.offset_top = 18
	body.offset_right = -18
	body.offset_bottom = -68
	body.add_theme_constant_override("separation", 10)
	_new_campaign_dialog.add_child(body)

	var label := Label.new()
	label.text = "Inserisci il nome della campagna:"
	body.add_child(label)

	_new_campaign_name = LineEdit.new()
	_new_campaign_name.placeholder_text = "Nome campagna"
	_new_campaign_name.max_length = 80
	body.add_child(_new_campaign_name)

	_new_campaign_dialog.confirmed.connect(_confirm_new_campaign)


func _build_options_dialog() -> void:
	_options_dialog = AcceptDialog.new()
	_options_dialog.title = "Opzioni"
	_options_dialog.dialog_text = (
		"Sezione predisposta.\n"
		+ "Audio, grafica e comandi saranno aggiunti successivamente."
	)
	add_child(_options_dialog)


func _open_active_campaigns() -> void:
	get_tree().change_scene_to_file(ACTIVE_CAMPAIGNS_SCENE_PATH)


func _request_new_campaign() -> void:
	_new_campaign_name.clear()
	_new_campaign_dialog.popup_centered(Vector2i(440, 210))
	_new_campaign_name.call_deferred("grab_focus")


func _confirm_new_campaign() -> void:
	var campaign_name: String = _new_campaign_name.text.strip_edges()
	if campaign_name.is_empty():
		_show_error("Inserisci un nome per la campagna.")
		return

	var manager: Node = _campaign_manager()
	if manager == null:
		_show_error("CampaignManager non disponibile.")
		return

	var campaign_id: String = String(
		manager.call("create_campaign", campaign_name)
	)
	if campaign_id.is_empty():
		_show_error("Impossibile creare la campagna.")
		return

	var error: Error = int(manager.call("open_campaign", campaign_id))
	if error != OK:
		_show_error(
			"Impossibile aprire la nuova campagna: %s"
			% error_string(error)
		)


func _campaign_manager() -> Node:
	var manager: Node = get_node_or_null("/root/CampaignManager")
	if manager == null:
		push_error("CampaignManager autoload non disponibile.")
	return manager


func _show_options_placeholder() -> void:
	_options_dialog.popup_centered(Vector2i(460, 190))


func _show_error(message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Errore"
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered(Vector2i(480, 180))
	dialog.close_requested.connect(dialog.queue_free)
