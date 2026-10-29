extends SceneTree


func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var TokenScene = load("res://token.tscn")
	var manager := root.get_node("TokenPackManager")
	assert(manager.miniature_identity("ape", "res://remote_tokens/wolf/wolf_visual.res") == "wolf")
	assert(manager.get_bestiary_reference("ape", "2014").source == "MM")
	assert(manager.get_bestiary_reference("ape", "2024").source == "XMM")
	assert(manager.get_bestiary_reference("valandir", "2024").is_empty())
	assert(manager.get_bestiary_reference("lioness", "2024").name == "Lion")
	assert(manager.get_bestiary_reference("swarm_of_beetles", "2024").name == "Swarm of Insects")
	# New GitHub Release PCKs share the correct 5etools portraits by monster
	# identity, regardless of pose, update suffix, or 2024 renaming.
	assert(manager.get_bestiary_reference("adult_brass_dragon_flying_updated", "2024").name == "Adult Brass Dragon")
	assert(manager.get_bestiary_reference("adult_brass_dragon_updated", "2014").name == "Adult Brass Dragon")
	assert(manager.get_bestiary_token_url("adult_brass_dragon_flying_updated").contains("Adult%20Brass%20Dragon.webp"))
	assert(manager.get_bestiary_reference("duodrone_updated", "2024").name == "Modron Duodrone")
	assert(manager.get_bestiary_reference("hobgoblin_updated", "2024").name == "Hobgoblin Warrior")
	assert(manager.get_bestiary_reference("red_half_dragon", "2024").name == "Half-Dragon")
	assert(manager.get_bestiary_reference("red_half_dragon", "2014").is_empty())
	assert(manager.get_bestiary_reference("mindflayer_infiltrator_2", "2024").name == "Mind Flayer")
	assert(manager.get_bestiary_reference("hell_hound_puppy", "2014").name == "Hell Hound")
	assert(manager.get_bestiary_reference("tiamat_updated", "2014").source == "RoT")
	assert(manager.get_bestiary_reference("bahamut_updated", "2014").source == "FTD")
	assert(manager.get_bestiary_reference("old_black_dragon", "2024").is_empty())
	assert(manager.get_bestiary_reference("tiamat_necklace", "2024").is_empty())
	assert(manager.get_bestiary_token_url("tiamat_necklace").is_empty())

	# The miniature's exact 5etools association determines its tactical size,
	# even if a stale PCK catalog reports a different size.
	assert(manager.get_bestiary_reference("awakened_tree", "2014").size_name == "Huge")
	assert(manager.get_bestiary_reference("awakened_tree", "2014").footprint == 3)
	assert(manager.get_bestiary_reference("giant_goat", "2014").size_name == "Large")
	assert(manager.get_bestiary_reference("giant_goat", "2014").footprint == 2)
	assert(manager.get_bestiary_reference("red_half_dragon", "2024").size_name == "Medium")
	var board = load("res://dnd_base.gd").new()
	var resolved: Dictionary = board._profile_with_bestiary_size({
		"id": "awakened_tree", "size_name": "Small", "footprint": 1.0
	})
	assert(resolved.size_name == "Huge" and resolved.footprint == 3.0)
	resolved = board._profile_with_bestiary_size({
		"id": "adult_brass_dragon_flying_updated",
		"size_name": "Medium", "footprint": 1.0
	})
	assert(resolved.size_name == "Huge" and resolved.footprint == 3.0)
	resolved = board._profile_with_bestiary_size({
		"id": "red_half_dragon", "size_name": "Large", "footprint": 2.0
	})
	assert(resolved.size_name == "Medium" and resolved.footprint == 1.0)
	resolved = board._profile_with_bestiary_size({
		"id": "old_black_dragon", "size_name": "Large", "footprint": 2.0
	})
	assert(resolved.size_name == "Large" and resolved.footprint == 2.0)
	board.free()

	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var ape_url: String = manager.get_bestiary_token_url("ape")
	var wolf_url: String = manager.get_bestiary_token_url("wolf")
	manager._bestiary_textures[ape_url] = texture
	manager._bestiary_textures[wolf_url] = texture

	var a = TokenScene.instantiate()
	var b = TokenScene.instantiate()
	a.visual_asset_path = "res://absent/ape.res"
	b.visual_asset_path = "res://absent/ape.res"
	root.add_child(a)
	root.add_child(b)
	await process_frame
	# Missing PCK visuals still preserve configured identity via pack metadata.
	a.set_token_pack_id("ape")
	b.set_token_pack_id("ape")
	assert(a.get_miniature_identity() == "ape")
	assert(b.get_miniature_identity() == "ape")
	b.set_token_pack_id("wolf")
	assert(b.get_miniature_identity() == "wolf")

	var shape_before: Shape3D = a.collision_shape.shape
	var id_before: String = a.get_token_id()
	a.set_top_down_token_enabled(true)
	assert(a.visuals.visible)
	assert(a._top_down_token_sprite.visible)
	a.set_2d_elevation_overlay_enabled(true)
	assert(not a._top_down_token_sprite.visible)
	assert(a.get_top_down_icon_texture() == texture)
	a.set_2d_elevation_overlay_enabled(false)
	assert(a._top_down_token_sprite.visible)
	assert(a._top_down_token_sprite.position.y > a.token_height_cells * a.cell_size * 0.5)
	assert(a.collision_shape.shape == shape_before)
	assert(a.get_token_id() == id_before)
	a.set_token_size(2.0)
	assert(is_equal_approx(a._top_down_token_sprite.pixel_size * 64, 2.0 * a.cell_size))
	a.set_top_down_token_enabled(false)
	assert(not a._top_down_token_sprite.visible)
	assert(a.visuals.visible)
	var character_shape: Shape3D = a.collision_shape.shape
	a.set_token_pack_id("valandir")
	a.set_top_down_token_enabled(true)
	assert(a._top_down_token_sprite.visible)
	assert(a._top_down_token_sprite.texture == manager.get_bestiary_texture(manager.get_bestiary_token_url("valandir")))
	assert(a.visuals.visible and a.collision_shape.shape == character_shape)
	a.set_token_pack_id("missing_character_artwork")
	a.set_top_down_token_enabled(true)
	assert(not a._top_down_token_sprite.visible)
	a._on_bestiary_texture_ready(ape_url, texture)
	assert(not a._top_down_token_sprite.visible)

	# The 2D overlay must not cover the map with a filled blue tile or
	# fall back to two initials. Token names and selection remain legible.
	var scene_camera: Camera3D = Camera3D.new()
	scene_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	scene_camera.size = 20.0
	root.add_child(scene_camera)
	scene_camera.position = Vector3(0.0, 25.0, 0.0)
	scene_camera.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	scene_camera.current = true

	var elevation_ui: Control = (
		preload("res://vtt/top_down_elevation_overlay.gd").new()
	)
	root.add_child(elevation_ui)
	elevation_ui.set("camera", scene_camera)
	elevation_ui.set("cell_size", 1.0)

	a.set_token_pack_id("ape")
	a.set_top_down_token_enabled(true)
	a.set_2d_elevation_overlay_enabled(true)
	a.set_display_name("Gilliam")
	a.set_selected(true)
	assert(not a._name_label.visible)
	assert(not a.selection_marker.visible)
	elevation_ui.call("_render_token_badge", a, 0.0)
	var badges: Dictionary = elevation_ui.get("_badges")
	var a_badge: Control = badges[a.get_instance_id()] as Control
	assert(a_badge.get_node_or_null("Background") == null)
	assert(a_badge.get_node_or_null("Fallback") == null)
	var a_portrait: TextureRect = a_badge.get_node("Portrait") as TextureRect
	assert(a_portrait.texture == texture)
	var a_name: Label = a_badge.get_node("Name") as Label
	assert(a_name.text == "Gilliam")
	assert(a_name.position.y < a_portrait.position.y)
	var a_ring: Panel = a_badge.get_node("SelectionRing") as Panel
	assert(a_ring.visible)
	a.set_selected(false)
	elevation_ui.call("_render_token_badge", a, 0.0)
	assert(not a_ring.visible)
	a.set_selected(true)
	a.set_2d_elevation_overlay_enabled(false)
	assert(a.selection_marker.visible)
	assert(a._name_label.visible)

	# A token that previously had a portrait must not retain it when its
	# new identity lacks 2D art.
	b.set_token_pack_id("wolf")
	b.set_top_down_token_enabled(true)
	assert(b.get_top_down_icon_texture() == texture)
	b.set_token_pack_id("missing_character_artwork")
	b.set_top_down_token_enabled(true)
	assert(b.get_top_down_icon_texture() == null)
	b.set_2d_elevation_overlay_enabled(true)
	b.set_display_name("Kryss")
	elevation_ui.call("_render_token_badge", b, 0.0)
	badges = elevation_ui.get("_badges")
	var b_badge: Control = badges[b.get_instance_id()] as Control
	assert(b_badge.get_node_or_null("Background") == null)
	assert(b_badge.get_node_or_null("Fallback") == null)
	assert((b_badge.get_node("Name") as Label).text == "Kryss")
	# Transparent miniatures are rendered from the existing 3D visuals,
	# rather than showing a colored rectangle and a monogram.
	assert(b_badge.get_node_or_null("MiniaturePreview") is SubViewport)
	assert((b_badge.get_node("Portrait") as TextureRect).texture != null)

	elevation_ui.free()
	scene_camera.free()

	# A late-created token follows an ancestor already in 2D.
	var arena := Node3D.new()
	arena.set_script(load("res://tests/fixtures/bestiary_2d_board.gd"))
	root.add_child(arena)
	var late = TokenScene.instantiate()
	late.visual_asset_path = "res://absent/ape.res"
	late.token_pack_id = "ape"
	arena.add_child(late)
	await process_frame
	assert(late._top_down_token_sprite.visible)
	a.free()
	b.free()
	arena.free()
	print("PASS: 2D token portraits and 3D miniature previews have no tiles or initials, with names and selection")
	quit()
