extends SceneTree

const SpellCatalog = preload("res://vtt/spells/spell_catalog.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var fireball: Dictionary = SpellCatalog.spell("fireball")
	assert(not fireball.is_empty())
	assert(String(fireball.get("target_mode", "")) == "token_then_point")
	assert(is_equal_approx(float(fireball.get("range_feet", 0.0)), 150.0))
	assert(String(fireball.get("aoe_shape", "")) == "sphere")
	assert(is_equal_approx(float(fireball.get("aoe_radius_feet", 0.0)), 20.0))
	assert(String(fireball.get("visual_style", "")) == "fire")
	assert(fireball.has("map_effect_spec"))
	var fireball_spec: Dictionary = fireball.get("map_effect_spec", {})
	assert(fireball_spec.has("range"))
	assert(fireball_spec.has("targeting"))
	assert(fireball_spec.has("effect"))
	assert(not fireball_spec.has("effects"))
	var fireball_effect: Dictionary = fireball_spec.get("effect", {})
	var fireball_geometry: Dictionary = fireball_effect.get("geometry", {})
	assert(String(fireball_geometry.get("shape", "")) == "sphere")
	assert(is_equal_approx(
		float(fireball_geometry.get("radius_feet", 0.0)),
		20.0
	))

	var lightning: Dictionary = SpellCatalog.spell("lightning_bolt")
	assert(not lightning.is_empty())
	assert(String(lightning.get("aoe_shape", "")) == "line")
	assert(int(lightning.get("aoe_length_cells", 0)) == 20)
	assert(is_equal_approx(float(lightning.get("line_width_feet", 0.0)), 5.0))
	assert(String(lightning.get("visual_style", "")) == "lightning")

	var call_lightning: Dictionary = SpellCatalog.spell("call_lightning")
	assert(not call_lightning.is_empty())
	assert(String(call_lightning.get("target_mode", "")) == "token_then_point")
	assert(String(call_lightning.get("aoe_shape", "")) == "cylinder")
	assert(is_equal_approx(
		float(call_lightning.get("aoe_radius_feet", 0.0)),
		60.0
	))
	assert(is_equal_approx(
		float(call_lightning.get("aoe_height_feet", 0.0)),
		10.0
	))

	var detonate: Dictionary = SpellCatalog.spell("detonate")
	assert(not detonate.is_empty())
	assert(String(detonate.get("target_mode", "")) == "token_then_token")
	assert(String(detonate.get("aoe_shape", "")) == "sphere")
	assert(is_equal_approx(
		float(detonate.get("aoe_radius_feet", 0.0)),
		60.0
	))
	assert(String(detonate.get("visual_style", "")) == "fire")

	var wall_fire: Dictionary = SpellCatalog.spell("wall_of_fire")
	assert(not wall_fire.is_empty())
	assert(String(wall_fire.get("target_mode", "")) == "wall_design")
	var fire_modes: Array = wall_fire.get("wall_modes", [])
	assert("polyline" in fire_modes)
	assert("circle" in fire_modes)
	assert(is_equal_approx(float(wall_fire.get("wall_max_length_feet", 0.0)), 60.0))
	assert(is_equal_approx(float(wall_fire.get("wall_circle_max_radius_feet", 0.0)), 10.0))
	assert(bool(wall_fire.get("wall_choose_damage_side", false)))
	assert(String(wall_fire.get("visual_style", "")) == "fire")

	var wall_force: Dictionary = SpellCatalog.spell("wall_of_force")
	assert(not wall_force.is_empty())
	var force_modes: Array = wall_force.get("wall_modes", [])
	assert("polyline" in force_modes)
	assert("globe" in force_modes)
	assert("dome" in force_modes)
	assert(is_equal_approx(float(wall_force.get("wall_max_length_feet", 0.0)), 100.0))
	assert(is_equal_approx(float(wall_force.get("wall_globe_max_radius_feet", 0.0)), 10.0))
	assert(not bool(wall_force.get("wall_requires_ground", false)))
	# No single damage family exists, so the bespoke barrier style remains.
	assert(String(wall_force.get("visual_style", "")) == "wall_of_force")

	var wind_wall: Dictionary = SpellCatalog.spell("wind_wall")
	assert(not wind_wall.is_empty())
	assert(String(wind_wall.get("visual_style", "")) == "bludgeoning")

	print(
		"PASS: compact 5eTools map spec drives range, AoE, walls and damage VFX"
	)
	quit()
