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

	var sorcerer_point_projectiles: Array[String] = [
		"fire_bolt",
		"poison_spray",
		"ray_of_frost",
		"sorcerous_burst",
		"chaos_bolt",
		"chromatic_orb",
		"ice_knife",
		"magic_missile",
		"ray_of_sickness",
		"spellfire_flare",
		"scorching_ray",
		"disintegrate"
	]
	for projectile_id: String in sorcerer_point_projectiles:
		var projectile_spell: Dictionary = SpellCatalog.spell(projectile_id)
		assert(not projectile_spell.is_empty())
		assert(not String(
			projectile_spell.get("projectile_style", "")
		).is_empty())
		assert(bool(projectile_spell.get("allow_point_target", false)))

	# Witch Bolt remains on its hand-authored persistent-link mechanic.
	var witch_bolt: Dictionary = SpellCatalog.spell("witch_bolt")
	assert(not witch_bolt.is_empty())
	assert(bool(witch_bolt.get("persistent_link", false)))
	assert(not bool(witch_bolt.get("allow_point_target", false)))

	var fire_bolt: Dictionary = SpellCatalog.spell("fire_bolt")
	assert(not fire_bolt.is_empty())
	assert(String(fire_bolt.get("target_mode", "")) == "token_then_token")
	assert(is_equal_approx(float(fire_bolt.get("range_feet", 0.0)), 120.0))
	assert(String(fire_bolt.get("visual_style", "")) == "fire")
	assert(String(fire_bolt.get("projectile_style", "")) == "fire")
	assert(bool(fire_bolt.get("allow_point_target", false)))

	var chromatic_orb: Dictionary = SpellCatalog.spell("chromatic_orb")
	assert(not chromatic_orb.is_empty())
	assert(String(chromatic_orb.get("target_mode", "")) == "token_then_token")
	assert(is_equal_approx(float(chromatic_orb.get("range_feet", 0.0)), 90.0))
	assert(String(chromatic_orb.get("visual_style", "")) == "prismatic")
	assert(String(chromatic_orb.get("projectile_style", "")) == "prismatic")
	assert(bool(chromatic_orb.get("allow_point_target", false)))

	var magic_missile: Dictionary = SpellCatalog.spell("magic_missile")
	assert(not magic_missile.is_empty())
	assert(String(magic_missile.get("target_mode", "")) == "token_then_multi_token")
	assert(is_equal_approx(float(magic_missile.get("range_feet", 0.0)), 120.0))
	assert(int(magic_missile.get("base_target_clicks", 0)) == 3)
	assert(int(magic_missile.get("target_clicks_per_slot_above_base", 0)) == 1)
	assert(bool(magic_missile.get("allow_repeat_targets", false)))
	assert(bool(magic_missile.get("allow_point_target", false)))
	assert(String(magic_missile.get("visual_style", "")) == "force")
	assert(String(magic_missile.get("projectile_style", "")) == "force")

	var scorching_catalog: Dictionary = SpellCatalog.catalog_spell(
		"scorching_ray"
	)
	assert(not scorching_catalog.is_empty())
	assert(String(scorching_catalog.get("name", "")) == "Scorching Ray")
	assert(int(scorching_catalog.get("level", -1)) == 2)
	assert(String(scorching_catalog.get("school", "")) == "Evocation")
	assert(not String(scorching_catalog.get("description", "")).is_empty())
	assert("three fiery rays" in String(
		scorching_catalog.get("description", "")
	).to_lower())
	assert(SpellCatalog.is_runtime_usable(scorching_catalog))

	var scorching_ray: Dictionary = SpellCatalog.spell("scorching_ray")
	assert(not scorching_ray.is_empty())
	assert(String(scorching_ray.get("target_mode", "")) == "token_then_multi_token")
	assert(is_equal_approx(float(scorching_ray.get("range_feet", 0.0)), 120.0))
	assert(int(scorching_ray.get("base_target_clicks", 0)) == 3)
	assert(int(scorching_ray.get("target_clicks_per_slot_above_base", 0)) == 1)
	assert(bool(scorching_ray.get("allow_repeat_targets", false)))
	assert(bool(scorching_ray.get("allow_point_target", false)))
	assert(String(scorching_ray.get("visual_style", "")) == "fire")
	assert(String(scorching_ray.get("projectile_style", "")) == "fire")

	# ST/MT alone is not enough to invent a projectile. These spells still
	# appear in the browser, but have no supported map effect yet.
	assert(SpellCatalog.spell("charm_person").is_empty())
	assert(SpellCatalog.spell("feather_fall").is_empty())

	var misty_step: Dictionary = SpellCatalog.spell("misty_step")
	assert(not misty_step.is_empty())
	assert(String(misty_step.get("target_mode", "")) == "teleport_self")
	assert(int(misty_step.get("teleport_distance_feet", 0)) == 30)
	assert(String(misty_step.get("visual_style", "")) == "silver_mist")

	var dimension_door: Dictionary = SpellCatalog.spell("dimension_door")
	assert(not dimension_door.is_empty())
	assert(int(dimension_door.get("teleport_distance_feet", 0)) == 500)
	assert(String(dimension_door.get("visual_style", "")) == "force")

	var thunder_step: Dictionary = SpellCatalog.spell("thunder_step")
	assert(not thunder_step.is_empty())
	assert(int(thunder_step.get("teleport_distance_feet", 0)) == 90)
	assert(String(thunder_step.get("visual_style", "")) == "thunder")

	var meteor_swarm: Dictionary = SpellCatalog.spell("meteor_swarm")
	assert(not meteor_swarm.is_empty())
	assert(String(meteor_swarm.get("target_mode", "")) == "token_then_multi_point")
	assert(int(meteor_swarm.get("base_target_clicks", 0)) == 4)
	assert(is_equal_approx(float(meteor_swarm.get("range_feet", 0.0)), 5280.0))
	assert(String(meteor_swarm.get("aoe_shape", "")) == "sphere")
	assert(is_equal_approx(float(meteor_swarm.get("aoe_radius_feet", 0.0)), 40.0))
	assert(String(meteor_swarm.get("visual_style", "")) == "fire")
	assert(String(meteor_swarm.get("projectile_style", "")) == "fire")

	var hold_person: Dictionary = SpellCatalog.spell("hold_person")
	assert(not hold_person.is_empty())
	assert(String(hold_person.get("target_mode", "")) == "token_then_token")
	var hold_conditions: Array = hold_person.get("condition_inflict", [])
	assert("paralyzed" in hold_conditions)
	var hold_saves: Array = hold_person.get("saving_throw", [])
	assert("wisdom" in hold_saves)
	assert(SpellCatalog.is_runtime_usable(hold_person))

	var thunderwave: Dictionary = SpellCatalog.spell("thunderwave")
	assert(not thunderwave.is_empty())
	assert(String(thunderwave.get("target_mode", "")) == "token_then_direction")
	var thunder_saves: Array = thunderwave.get("saving_throw", [])
	assert("constitution" in thunder_saves)
	var thunder_misc: Array = thunderwave.get("misc_tags", [])
	assert("FMV" in thunder_misc)
	assert(bool(thunderwave.get("forced_movement_on_failed_save", false)))
	assert(is_equal_approx(
		float(thunderwave.get("forced_movement_feet", 0.0)),
		15.0
	))

	var find_familiar: Dictionary = SpellCatalog.spell("find_familiar")
	assert(not find_familiar.is_empty())
	assert(String(find_familiar.get("target_mode", "")) == "summon")
	assert(int(find_familiar.get("summon_count", 0)) == 1)
	assert(is_equal_approx(
		float(find_familiar.get("range_feet", 0.0)),
		10.0
	))

	var flock: Dictionary = SpellCatalog.spell("flock_of_familiars")
	assert(not flock.is_empty())
	assert(String(flock.get("target_mode", "")) == "summon")
	assert(int(flock.get("summon_count", 0)) == 3)

	var create_undead: Dictionary = SpellCatalog.spell("create_undead")
	assert(not create_undead.is_empty())
	assert(String(create_undead.get("target_mode", "")) == "summon")
	assert(int(create_undead.get("summon_count_min", 0)) == 1)
	assert(int(create_undead.get("summon_count_max", 0)) == 3)

	var lesser_demons: Dictionary = SpellCatalog.spell(
		"summon_lesser_demons"
	)
	assert(not lesser_demons.is_empty())
	assert(String(lesser_demons.get("target_mode", "")) == "summon")
	var lesser_options: Array = lesser_demons.get(
		"summon_count_options",
		[]
	)
	assert(2 in lesser_options)
	assert(4 in lesser_options)
	assert(8 in lesser_options)

	# SMN can also tag conditional creation/transformation. Existing explicit
	# targeting must win instead of opening the summon-token workflow.
	var finger_of_death: Dictionary = SpellCatalog.spell("finger_of_death")
	assert(not finger_of_death.is_empty())
	assert(String(finger_of_death.get("target_mode", "")) != "summon")

	var entangle: Dictionary = SpellCatalog.spell("entangle")
	assert(not entangle.is_empty())
	assert(String(entangle.get("target_mode", "")) == "token_then_point")
	assert(is_equal_approx(float(entangle.get("range_feet", 0.0)), 90.0))
	assert(String(entangle.get("aoe_shape", "")) == "flat_square")
	assert(is_equal_approx(float(entangle.get("aoe_side_feet", 0.0)), 20.0))
	assert(bool(entangle.get("persistent", false)))
	assert(not bool(entangle.get("requires_ground", false)))
	var entangle_conditions: Array = entangle.get("condition_inflict", [])
	assert("restrained" in entangle_conditions)
	var entangle_saves: Array = entangle.get("saving_throw", [])
	assert("strength" in entangle_saves)

	print(
		"PASS: 5eTools metadata drives projectiles, summon flows, conditions, areas, walls and VFX"
	)
	quit()
