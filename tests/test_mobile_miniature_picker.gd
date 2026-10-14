extends SceneTree
const Mobile = preload("res://vtt/mobile/creatures_mobile.tscn")
class CopyArchive extends "res://vtt/creature_archive.gd":
	var captured: Dictionary = {}
	func save(record: Dictionary) -> Error:
		captured = record.duplicate(true)
		return OK
	func list_owned() -> Array[Dictionary]:
		return []
func _initialize() -> void:
	call_deferred("run")
func settle() -> void:
	for i: int in range(8):
		await process_frame
func tap(mobile: Node, window: Window, point: Vector2) -> void:
	var position := point + Vector2(window.position)
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = position
		event.pressed = pressed
		mobile._input(event)
func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(480,960)
	var mobile := Mobile.instantiate()
	root.add_child(mobile)
	await settle()
	var sheet: Node = mobile.creature_area
	var archive := CopyArchive.new()
	sheet._archive = archive
	var store = load("res://vtt/player_character_store.gd").new()
	var record: Dictionary = store.create_character()
	record.kind = "character"
	sheet._choose_miniature(record, true)
	await settle()
	var dialog: Window = sheet._miniature_dialog
	assert(dialog.visible and sheet._pending_new_creature, "New mobile characters must open the base miniature picker")
	assert(archive.captured.is_empty(), "Creation must wait for explicit miniature confirmation")
	assert(sheet._miniature_list.item_count > 0, "Mobile picker must contain catalog entries")
	assert(dialog.get_ok_button().disabled)
	var search: LineEdit = sheet._miniature_filter
	tap(mobile, dialog, search.get_global_rect().get_center())
	await settle()
	assert(search.has_focus(), "Touch must focus the search inside its embedded viewport")
	var first: Dictionary = sheet._miniature_choices[0]
	for character: String in String(first.id):
		var key := InputEventKey.new()
		key.pressed = true
		key.unicode = character.unicode_at(0)
		key.keycode = character.to_upper().unicode_at(0)
		dialog.push_input(key, true)
	await settle()
	assert(sheet._visible_miniatures.size() >= 1 and sheet._visible_miniatures.size() < sheet._miniature_choices.size(), "Typing must filter the miniature list")
	var list: ItemList = sheet._miniature_list
	var row := list.get_item_rect(0)
	tap(mobile, dialog, list.global_position + row.get_center())
	await settle()
	assert(not sheet._chosen_miniature_id.is_empty() and not dialog.get_ok_button().disabled, "A real row tap must select a miniature")
	var chosen: String = sheet._chosen_miniature_id
	tap(mobile, dialog, dialog.get_ok_button().get_global_rect().get_center())
	await settle()
	assert(archive.captured.default_miniature_id == chosen and archive.captured.current_miniature_id == chosen, "Confirmation must save both base and current miniature")
	print("PASS: mobile creation requires miniature; embedded search focus, typed filter, row tap and confirmation")
	mobile.queue_free()
	await settle()
	quit()
