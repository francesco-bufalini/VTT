extends SceneTree
const TokenScene = preload("res://token.tscn")
const AreaCatalog = preload("res://vtt/spells/spell_area_catalog.gd")
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false
func run() -> void:
	var token: CharacterBody3D = TokenScene.instantiate()
	root.add_child(token)
	if not check(not token.set_visual_asset("res://assets/tokens/__absent__.obj"), "Absent asset must return false"):
		return
	if not check(token.set_visual_asset("res://assets/tokens/test/test_token_visual.tscn"), "Available model must load"):
		return
	var imported: String = token.get_visual_asset_path()
	if not check(not token.set_visual_asset("res://assets/tokens/__absent__.obj") and token.get_visual_asset_path() == imported, "Failed load must preserve existing model"):
		return
	var spec: Dictionary = AreaCatalog.spec_for_spell({"name":"Lightning Bolt", "source":"__unknown_source__"})
	if not check(not spec.is_empty() and spec.effect.geometry.width_feet == 5.0, "Missing source must fall back to the preferred spell geometry"):
		return
	token.queue_free()
	await process_frame
	print("PASS: missing assets preserve visuals and missing spell sources use preferred geometry")
	quit()

