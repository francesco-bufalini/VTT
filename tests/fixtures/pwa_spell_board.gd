extends "res://dnd_base.gd"
## Synthetic board for real HTTP/WebP/browser tests. No campaign or archive.

class PortraitToken:
	extends "res://token.gd"
	var fixture_portrait: Texture2D
	func get_top_down_icon_texture() -> Texture2D:
		return fixture_portrait

var resolve_at := 0
var save_count := 0

func _ready() -> void:
	set_process_input(false)
	get_node("Board").hide()
	get_node("Board").process_mode = Node.PROCESS_MODE_DISABLED
	camera.position = Vector3(0, 24, 20)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("253246")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	add_child(environment)
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 0.1, 80)
	collision.shape = box
	ground.add_child(collision)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("607266")
	mesh.material_override = material
	ground.add_child(mesh)
	ground.position.y = -0.1
	add_child(ground)
	for spec: Array in [
		["caster", "Maga PWA", Vector3(0.5, 1, 0.5), Color("e8c36a")],
		["victim", "Bersaglio", Vector3(3.5, 1, 0.5), Color("e78376")],
		["high", "In volo", Vector3(4.5, 5, 3.5), Color("8cd6f4")],
		["low", "Piano inferiore", Vector3(-3.5, -3, 2.5), Color("c4a9ef")]]:
		var token: CharacterBody3D = load("res://token.tscn").instantiate()
		token.set_script(PortraitToken)
		var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		for x: int in range(96):
			for y: int in range(96):
				if Vector2(x - 48, y - 48).length() < 44:
					image.set_pixel(x, y, spec[3] if abs(x - 48) > 8 or abs(y - 48) > 24 else Color.WHITE)
		token.fixture_portrait = ImageTexture.create_from_image(image)
		token.set_token_id(spec[0])
		token.set_meta("sync_id", spec[0])
		token.set_meta("creature_owner_id", "pwa-fixture-owner-123456")
		tokens_root.add_child(token)
		token.set_display_name(spec[1])
		token.global_position = spec[2]
		token.set_flying(true)
		token.set_physics_process(false)
	measurement_tool.set_camera(camera)
	spell_system = load("res://vtt/spells/spell_system.gd").new()
	spell_system.name = "SpellSystem"
	add_child(spell_system)
	spell_system.setup(self)
	board_sync = load("res://network/board_sync.gd").new()
	add_child(board_sync)
	board_sync.board_root = self
	board_sync.tokens_root = tokens_root
	board_sync.receiving = true
	board_sync.auto_sync_enabled = false
	board_sync.map_data_controller = load("res://vtt/map_data_controller.gd").new()
	board_sync.add_child(board_sync.map_data_controller)
	board_sync.map_data_controller.use_board(board_sync.get_tactical_map_data)
	board_sync.map_data_controller.set_action_provider(board_sync._handle_mobile_action)
	# HTTP actions use the same serving gate as Android, without opening UDP
	# ports belonging to any live desktop session.
	board_sync.map_data_controller._serving = true
	board_sync.session_key = "pwa-spell-fixture"

func _process(_delta: float) -> void:
	if not is_instance_valid(spell_system):
		return
	# Simulate the GM's actual native dialog choice: first fail, then succeed.
	if spell_system._targeting_phase == "saving_throw":
		if resolve_at == 0:
			resolve_at = Time.get_ticks_msec() + 3500
		elif Time.get_ticks_msec() >= resolve_at:
			spell_system._resolve_current_saving_throw(save_count % 2 == 1)
			save_count += 1
			resolve_at = 0
	else:
		resolve_at = 0

func clear_token_selection() -> void:
	pass

func set_affected_token_highlight(_tokens: Array) -> void:
	pass

func push_undo_state() -> void:
	pass

func _sync_explicit_token_change(_edited_token: Node3D = null) -> void:
	pass

func is_2d_view_enabled() -> bool:
	return false
