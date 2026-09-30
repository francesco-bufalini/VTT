extends RefCounted

const CATALOG_PATH := "res://assets/spell_area_geometry.json"

static var _loaded: bool = false
static var _catalog: Dictionary = {}
static var _name_index: Dictionary = {}


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_catalog = {}
	_name_index = {}

	if not FileAccess.file_exists(CATALOG_PATH):
		push_warning(
			"SpellAreaCatalog: file non trovato: %s" % CATALOG_PATH
		)
		return

	var text_value: String = FileAccess.get_file_as_string(CATALOG_PATH)
	var parsed: Variant = JSON.parse_string(text_value)
	if not parsed is Dictionary:
		push_warning(
			"SpellAreaCatalog: JSON non valido in %s" % CATALOG_PATH
		)
		return

	_catalog = (parsed as Dictionary).duplicate(true)
	for key_value: Variant in _catalog.keys():
		var key: String = String(key_value)
		var separator: int = key.find("::")
		if separator < 0:
			continue
		var name: String = key.substr(separator + 2)
		if not _name_index.has(name):
			_name_index[name] = []
		var keys_value: Variant = _name_index.get(name, [])
		if keys_value is Array:
			(keys_value as Array).append(key)


static func _preferred_key_for_name(name: String) -> String:
	_ensure_loaded()
	var value: Variant = _name_index.get(name, [])
	if not value is Array:
		return ""

	var keys: Array = value as Array
	for preferred_source: String in ["XPHB", "PHB"]:
		var preferred_key: String = "%s::%s" % [
			preferred_source,
			name
		]
		if preferred_key in keys:
			return preferred_key

	if not keys.is_empty():
		return String(keys[0])
	return ""


static func spec_for_spell(spell_data: Dictionary) -> Dictionary:
	_ensure_loaded()
	if spell_data.is_empty():
		return {}

	var name: String = String(spell_data.get("name", ""))
	var source: String = String(spell_data.get("source", ""))
	if not name.is_empty() and not source.is_empty():
		var exact_key: String = "%s::%s" % [source, name]
		var exact_value: Variant = _catalog.get(exact_key, {})
		if exact_value is Dictionary:
			return (exact_value as Dictionary).duplicate(true)

	if name.is_empty():
		return {}

	var fallback_key: String = _preferred_key_for_name(name)
	if fallback_key.is_empty():
		return {}

	var fallback_value: Variant = _catalog.get(fallback_key, {})
	if fallback_value is Dictionary:
		return (fallback_value as Dictionary).duplicate(true)
	return {}


static func _primary_effect(spec: Dictionary) -> Dictionary:
	var effect_value: Variant = spec.get("effect", {})
	if effect_value is Dictionary and not (effect_value as Dictionary).is_empty():
		return (effect_value as Dictionary).duplicate(true)

	# Backward compatibility for a stale generated asset during development.
	var effects_value: Variant = spec.get("effects", [])
	if effects_value is Array:
		var effects: Array = effects_value as Array
		for item: Variant in effects:
			if item is Dictionary:
				return (item as Dictionary).duplicate(true)
	return {}


static func _primary_damage_style(effect: Dictionary) -> String:
	var damage_value: Variant = effect.get("damage_types", [])
	if damage_value is Array:
		var damage_types: Array = damage_value as Array
		# One damage family maps cleanly to one static material family.
		# Multi-type effects keep their existing style instead of arbitrarily
		# choosing one damage type.
		if damage_types.size() == 1:
			return String(damage_types[0]).to_lower()
	return ""


static func _apply_range(
	result: Dictionary,
	spec: Dictionary
) -> void:
	var range_value: Variant = spec.get("range", {})
	if not range_value is Dictionary:
		return
	var range_data: Dictionary = range_value as Dictionary
	if range_data.has("feet"):
		result["range_feet"] = float(range_data.get("feet", 0.0))


static func _apply_targeting(
	result: Dictionary,
	spec: Dictionary
) -> void:
	var targeting_value: Variant = spec.get("targeting", {})
	if not targeting_value is Dictionary:
		return

	var targeting: Dictionary = targeting_value as Dictionary
	var targeting_type: String = String(
		targeting.get("type", "")
	)

	# The generated targeting is authoritative for ordinary area spells.
	# Keep dedicated state machines only for mechanics the geometry catalogue
	# does not describe (teleport, chain/multi-target selection, persistent
	# links, and legacy token-impact sequences).
	var existing_mode: String = String(
		result.get("target_mode", "")
	)
	var preserve_token_target: bool = (
		existing_mode == "token_then_token"
		and (
			bool(result.get("persistent_link", false))
			or float(result.get("impact_aoe_radius_feet", 0.0)) > 0.0
		)
	)
	if (
		existing_mode not in [
			"teleport_self",
			"token_then_chain",
			"token_then_multi_token"
		]
		and not preserve_token_target
	):
		match targeting_type:
			"point":
				result["target_mode"] = "token_then_point"
			"token":
				result["target_mode"] = "token_then_token"
			"multi_token":
				result["target_mode"] = "token_then_multi_token"
			"caster":
				result["target_mode"] = "self_emanation"
			"caster_direction":
				result["target_mode"] = "self_token"
			"wall":
				result["target_mode"] = "wall_design"

	if targeting.has("base_target_clicks"):
		result["base_target_clicks"] = int(targeting.get("base_target_clicks", 1))
	if targeting.has("target_clicks_per_slot_above_base"):
		result["target_clicks_per_slot_above_base"] = int(
			targeting.get("target_clicks_per_slot_above_base", 0)
		)
	if targeting.has("allow_repeat_targets"):
		result["allow_repeat_targets"] = bool(
			targeting.get("allow_repeat_targets", false)
		)
	if bool(targeting.get("projectile", false)):
		if String(result.get("projectile_style", "")).is_empty():
			result["projectile_style"] = String(result.get("id", "arcane"))
		if not result.has("projectile_travel_seconds"):
			result["projectile_travel_seconds"] = 0.65

	if bool(targeting.get("requires_ground", false)):
		result["requires_ground"] = true
		result["wall_requires_ground"] = true
	if bool(targeting.get("allow_pitch", false)):
		result["allow_pitch"] = true
	if bool(targeting.get("choose_damage_side", false)):
		result["wall_choose_damage_side"] = true


static func _apply_geometry(
	result: Dictionary,
	effect: Dictionary
) -> void:
	var geometry_value: Variant = effect.get("geometry", {})
	if not geometry_value is Dictionary:
		return
	var geometry: Dictionary = geometry_value as Dictionary
	var shape: String = String(geometry.get("shape", ""))

	match shape:
		"sphere", "emanation", "hemisphere":
			result["aoe_shape"] = "sphere"
			if geometry.has("radius_feet"):
				result["aoe_radius_feet"] = float(
					geometry.get("radius_feet", 5.0)
				)
		"cone":
			result["aoe_shape"] = "cone"
			if geometry.has("length_feet"):
				result["aoe_length_cells"] = maxi(
					1,
					int(round(
						float(geometry.get("length_feet", 5.0))
						/ 5.0
					))
				)
		"line":
			result["aoe_shape"] = "line"
			if geometry.has("length_feet"):
				result["aoe_length_cells"] = maxi(
					1,
					int(round(
						float(geometry.get("length_feet", 5.0))
						/ 5.0
					))
				)
			if geometry.has("width_feet"):
				result["line_width_feet"] = float(
					geometry.get("width_feet", 5.0)
				)
		"cube":
			result["aoe_shape"] = "cube"
			if geometry.has("side_feet"):
				result["aoe_side_feet"] = float(
					geometry.get("side_feet", 5.0)
				)
		"square":
			result["aoe_shape"] = "flat_square"
			if geometry.has("side_feet"):
				result["aoe_side_feet"] = float(
					geometry.get("side_feet", 5.0)
				)
		"circle":
			# The current renderer has no dedicated flat disk. A shallow
			# cylinder preserves the radius and is still fully data-driven.
			result["aoe_shape"] = "cylinder"
			if geometry.has("radius_feet"):
				result["aoe_radius_feet"] = float(
					geometry.get("radius_feet", 5.0)
				)
			result["aoe_height_feet"] = 0.5
		"cylinder":
			result["aoe_shape"] = "cylinder"
			if geometry.has("radius_feet"):
				result["aoe_radius_feet"] = float(
					geometry.get("radius_feet", 5.0)
				)
			if geometry.has("height_feet"):
				result["aoe_height_feet"] = float(
					geometry.get("height_feet", 5.0)
				)
		"wall":
			_apply_wall_geometry(result, geometry)


static func _apply_wall_geometry(
	result: Dictionary,
	geometry: Dictionary
) -> void:
	var variants_value: Variant = geometry.get("variants", [])
	if not variants_value is Array:
		return

	var modes: Array[String] = []
	var variants: Array = variants_value as Array
	for item: Variant in variants:
		if not item is Dictionary:
			continue
		var variant: Dictionary = item as Dictionary
		var variant_type: String = String(
			variant.get("type", "")
		)

		match variant_type:
			"path":
				if "polyline" not in modes:
					modes.append("polyline")
				result["wall_max_length_feet"] = float(
					variant.get("max_length_feet", 10.0)
				)
				result["wall_height_feet"] = float(
					variant.get("height_feet", 10.0)
				)
				result["wall_thickness_feet"] = float(
					variant.get("thickness_feet", 1.0)
				)
			"circle":
				if "circle" not in modes:
					modes.append("circle")
				result["wall_circle_max_radius_feet"] = float(
					variant.get("radius_feet", 10.0)
				)
				result["wall_circle_height_feet"] = float(
					variant.get(
						"height_feet",
						result.get("wall_height_feet", 10.0)
					)
				)
				if not result.has("wall_thickness_feet"):
					result["wall_thickness_feet"] = float(
						variant.get("thickness_feet", 1.0)
					)
			"globe":
				if "globe" not in modes:
					modes.append("globe")
				result["wall_globe_max_radius_feet"] = float(
					variant.get("radius_feet", 10.0)
				)
			"dome":
				if "dome" not in modes:
					modes.append("dome")
				result["wall_globe_max_radius_feet"] = float(
					variant.get("radius_feet", 10.0)
				)
			"panels":
				if "polyline" not in modes:
					modes.append("polyline")
				var panel_count: int = int(
					variant.get("max_panels", 1)
				)
				var panel_width: float = float(
					variant.get("panel_width_feet", 10.0)
				)
				result["wall_max_length_feet"] = (
					float(maxi(panel_count, 1)) * panel_width
				)
				result["wall_height_feet"] = float(
					variant.get("panel_height_feet", 10.0)
				)
				result["wall_thickness_feet"] = float(
					variant.get("thickness_feet", 0.5)
				)

	if not modes.is_empty():
		var ordered_modes: Array[String] = []
		for canonical_mode: String in [
			"polyline", "circle", "globe", "dome"
		]:
			if canonical_mode in modes:
				ordered_modes.append(canonical_mode)
		result["wall_modes"] = ordered_modes


static func apply_to_spell(spell_data: Dictionary) -> Dictionary:
	var result: Dictionary = spell_data.duplicate(true)
	var spec: Dictionary = spec_for_spell(result)
	if spec.is_empty():
		return result

	# Keep the normalized runtime description available to newer systems while
	# also translating it to the legacy fields consumed by SpellSystem today.
	result["map_effect_spec"] = spec
	_apply_range(result, spec)
	_apply_targeting(result, spec)

	var effect: Dictionary = _primary_effect(spec)
	if effect.is_empty():
		return result

	_apply_geometry(result, effect)

	var persistence: String = String(
		effect.get("persistence", "instant")
	)
	result["persistent"] = persistence == "persistent"

	# A single damage family drives the generic material and particle
	# animation. Non-damaging and multi-damage effects keep bespoke styles.
	var generic_style: String = _primary_damage_style(effect)
	if not generic_style.is_empty():
		result["visual_style"] = generic_style

	return result
