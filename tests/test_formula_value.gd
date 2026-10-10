extends SceneTree

const FormulaValue = preload("res://vtt/formula_value.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var parent := HBoxContainer.new()
	root.add_child(parent)
	var label := Label.new()
	parent.add_child(label)
	var base := SpinBox.new()
	var bonus := SpinBox.new()
	parent.add_child(base)
	parent.add_child(bonus)
	base.value = 12
	bonus.value = 2
	var old_position := label.get_index()
	parent.remove_child(label)
	var formula := FormulaValue.new()
	parent.add_child(formula)
	parent.move_child(formula, old_position)
	formula.setup(label, [base, bonus], ["Base", "Bonus"])
	formula.set_formula("14", "12 + 2 = 14")
	assert(formula.value_label.text == "14"
		and "12 + 2 = 14" in formula._readout.tooltip_text,
		"Formula should appear only on hover, not as permanent input boxes")
	assert(formula._readout.visible and not formula._editor.visible)
	assert(formula._fields.size() == 2
		and base.get_parent().get_parent() == formula._editor
		and bonus.get_parent().get_parent() == formula._editor,
		"Existing edit controls must be retained with their connections")
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.double_click = true
	formula._readout.gui_input.emit(event)
	assert(formula._editor.visible and not formula._readout.visible,
		"Double-clicking the number must open only the existing editable fields")
	formula.close_editor()
	assert(formula._readout.visible and not formula._editor.visible)
	parent.queue_free()
	await process_frame
	print("PASS: compact formula, tooltip, double-click and preserved editor fields")
	quit()
