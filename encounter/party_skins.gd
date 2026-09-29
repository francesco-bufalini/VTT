extends RefCounted

const SKINS := ["horned","ranger","sun_elf","hoplite","night_elf","feathered"]

func apply(token: Node3D,index: int) -> void:
	var visuals: Node3D = token.get_node("Visuals")
	for child in visuals.get_children():
		child.hide()
	var model: Node3D = load("res://encounter/assets/characters/party_"+SKINS[index%SKINS.size()]+".glb").instantiate()
	model.name = "PartySkin"
	model.position.y = -1.0
	visuals.add_child(model)
	token.set_meta("party_skin",SKINS[index%SKINS.size()])
