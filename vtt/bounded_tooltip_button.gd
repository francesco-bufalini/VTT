extends Button

# Native Godot tooltips can span beyond the viewport when an origin has a
# long trait description. Keep them bounded and internally scrollable.
func _make_custom_tooltip(for_text: String) -> Object:
	var panel := PanelContainer.new()
	var viewport_size: Vector2 = get_viewport_rect().size
	var body := RichTextLabel.new()
	body.bbcode_enabled = false
	body.selection_enabled = true
	body.scroll_active = true
	body.fit_content = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = for_text
	body.custom_minimum_size = Vector2(
		maxf(180.0, minf(430.0, viewport_size.x * 0.55)),
		maxf(100.0, minf(260.0, viewport_size.y * 0.42))
	)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_theme_constant_override("margin_right", 8)
	pad.add_theme_constant_override("margin_top", 7)
	pad.add_theme_constant_override("margin_bottom", 7)
	panel.add_child(pad)
	pad.add_child(body)
	return panel
