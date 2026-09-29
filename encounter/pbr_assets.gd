extends RefCounted

static func apply(material: ShaderMaterial, asset: String) -> void:
	for map in ["diff", "nor_gl", "rough"]:
		material.set_shader_parameter(map, load("res://encounter/assets/polyhaven/%s_%s.jpg" % [asset,map]))
