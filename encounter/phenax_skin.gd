extends RefCounted

func apply(token: Node3D) -> void:
	for child in token.visuals.get_children():
		child.hide()
	token.visuals.scale = Vector3.ONE*token.cell_size
	var model: Node3D = preload("res://encounter/assets/characters/phenax.glb").instantiate()
	model.position.y = -token.token_height_cells*.5
	token.visuals.add_child(model)
	var cosmic := ShaderMaterial.new()
	cosmic.shader = preload("res://encounter/phenax_cosmic.gdshader")
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		if String(mesh.name).begins_with("Anatomy"):
			mesh.material_override = cosmic
	token.set_meta("party_skin","phenax")
	token.set_meta("display_name","Phenax")
