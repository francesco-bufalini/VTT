extends SceneTree

const Tab = preload("res://vtt/creature_proficiencies_tab.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var tab := Tab.new()
	root.add_child(tab)
	tab.setup(func(_a: Variant, _b: Variant, _c: Variant) -> void: pass)
	tab.load_record({"kind": "character", "rules_version": "2014"})
	var open: Button
	for button: Node in tab.find_children("*", "Button", true, false):
		if button is Button and button.text == "+ Competenza" and button.visible:
			open = button
	assert(open != null)
	open.pressed.emit()
	assert(tab._competence_editor.is_visible_in_tree(), "First opening must show the form")
	tab._kind_picker.select(2)
	tab._refresh_proficiency_picker()
	tab._proficiency_name.text = "acrobatics"
	assert(tab._add_competence())
	tab._competence_dialog.hide()
	open.pressed.emit()
	assert(tab._competence_editor.is_visible_in_tree(), "Form must remain usable after adding")
	tab._select_origin("class|phb|monk")
	tab._competence_dialog.hide()
	open.pressed.emit()
	assert(tab._competence_editor.is_visible_in_tree(), "Selecting an origin must not hide the form")
	tab._proficiency_name.text = "stealth"
	assert(tab._add_competence())
	assert(tab._rows.size() == 2, "Repeated additions must persist both choices")
	tab.load_record({"kind": "character", "rules_version": "2014", "class": "Fighter", "class_source": "PHB", "classes": [{"name": "Fighter", "source": "PHB", "level": 1}]})
	tab._select_origin("class|phb|fighter")
	open.pressed.emit()
	tab._kind_picker.select(2)
	tab._refresh_proficiency_picker()
	tab._proficiency_name.text = "arcana"
	assert(not tab._add_competence(), "Invalid source choice must be rejected")
	assert(tab._competence_dialog.visible, "Rejected choice must leave the dialog open")
	assert(not tab._competence_error.text.is_empty(), "Rejection must explain the reason")
	tab.queue_free()
	await process_frame
	print("PASS: proficiency popup reopens and preserves rejected choices")
	quit()
