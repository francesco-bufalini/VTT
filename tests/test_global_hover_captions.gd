extends SceneTree

const Captions = preload("res://vtt/scrollable_caption.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(1100, 760)
	Captions.install(root)
	assert(root.has_node("ScrollableCaptions"), "Global hover service installed once in the root viewport")
	Captions.install(root)
	var count := 0
	for child: Node in root.get_children():
		if child.name == "ScrollableCaptions":
			count += 1
	assert(count == 1, "Presenter installation is idempotent")
	var caption = root.get_node("ScrollableCaptions")
	var button := Button.new()
	button.tooltip_text = "Example hint with lots of details.\n".repeat(100)
	root.add_child(button)
	caption._target = button
	caption._kind = "control"
	caption._text = button.tooltip_text
	caption._suppress()
	assert(button.tooltip_text.is_empty(), "Native duplicate control tooltip is temporarily suppressed")
	caption._show_caption()
	await process_frame
	assert(caption._panel.visible and caption._body.text == caption._text)
	assert(caption._body.selection_enabled and caption._body.scroll_active)
	assert(caption._panel.size.y <= 320, "Long descriptions are constrained to the viewport and scrollable")
	assert(caption._body.get_v_scroll_bar().max_value > caption._body.get_v_scroll_bar().page)
	caption._reset()
	assert(button.tooltip_text.begins_with("Example hint"), "Native hint is restored after hover")

	var parent := HBoxContainer.new()
	parent.tooltip_text = "Parent hint"
	root.add_child(parent)
	var leaf := Label.new()
	leaf.tooltip_text = "Value hint"
	parent.add_child(leaf)
	caption._target = leaf
	caption._kind = "control"
	caption._text = leaf.tooltip_text
	caption._suppress()
	assert(leaf.tooltip_text.is_empty() and parent.tooltip_text.is_empty())
	parent.tooltip_text = "Updated parent hint"
	caption._suppress()
	assert(parent.tooltip_text.is_empty())
	caption._reset()
	assert(leaf.tooltip_text == "Value hint" and parent.tooltip_text == "Updated parent hint")

	var entries := ItemList.new()
	entries.add_item("One")
	entries.set_item_tooltip(0, "List item details")
	root.add_child(entries)
	caption._target = entries
	caption._kind = "item"
	caption._item_index = 0
	caption._item_label = entries.get_item_text(0)
	caption._text = entries.get_item_tooltip(0)
	caption._suppress()
	assert(entries.get_item_tooltip(0).is_empty())
	caption._reset()
	assert(entries.get_item_tooltip(0) == "List item details")

	var tree := Tree.new()
	tree.columns = 1
	root.add_child(tree)
	var item: TreeItem = tree.create_item()
	item.set_text(0, "Tree entry")
	item.set_tooltip_text(0, "Tree details")
	caption._target = tree
	caption._kind = "tree"
	caption._tree_item = item
	caption._tree_column = 0
	caption._text = "Tree details"
	caption._suppress()
	assert(item.get_tooltip_text(0).is_empty())
	caption._reset()
	assert(item.get_tooltip_text(0) == "Tree details")

	var tabs := TabBar.new()
	tabs.add_tab("First")
	tabs.set_tab_tooltip(0, "Tab details")
	root.add_child(tabs)
	caption._target = tabs
	caption._kind = "tab"
	caption._item_index = 0
	caption._text = "Tab details"
	caption._suppress()
	assert(tabs.get_tab_tooltip(0) == " ")
	caption._reset()
	assert(tabs.get_tab_tooltip(0) == "Tab details")

	var container := TabContainer.new()
	var page := Control.new()
	page.name = "Page"
	container.add_child(page)
	container.set_tab_tooltip(0, "Page details")
	root.add_child(container)
	caption._target = container
	caption._kind = "tabs"
	caption._item_index = 0
	caption._text = "Page details"
	caption._suppress()
	assert(container.get_tab_tooltip(0) == " ")
	caption._reset()
	assert(container.get_tab_tooltip(0) == "Page details")

	var dialog := AcceptDialog.new()
	root.add_child(dialog)
	await process_frame
	await process_frame
	assert(dialog.has_node("ScrollableCaptions"), "Every separately created Window receives the same presenter")

	dialog.free()
	container.free()
	tabs.free()
	tree.free()
	entries.free()
	button.free()
	print("PASS global scrollable hints, window installation, ItemList, Tree and tabs")
	quit()
