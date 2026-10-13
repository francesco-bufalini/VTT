extends SceneTree

const BonusTab = preload("res://vtt/creature_bonus_tab.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var tab := BonusTab.new()
	root.add_child(tab)
	tab.setup(Callable())
	tab._record = {"kind": "character", "abilities": {},
		"classes": [], "formula_bonuses": [], "proficiency_origins": []}
	tab._origins = [
		{"id": "custom|alpha", "name": "Origine alfa", "disabled": false},
		{"id": "custom|beta", "name": "Origine beta", "disabled": false}
	]
	tab._rows = [
		{"id": "bonus-alpha", "target": "ac", "expression": "2",
			"origin_id": "custom|alpha", "origin_name": "Origine alfa",
			"disabled": true, "automatic": false},
		{"id": "bonus-beta", "target": "ac", "expression": "2",
			"origin_id": "custom|beta", "origin_name": "Origine beta",
			"disabled": false, "automatic": false}
	]
	tab._selected_origin = "custom|alpha"
	tab._refresh_options()
	tab._refresh()
	for i: int in range(tab._origin_picker.item_count):
		assert("Personalizzata" not in tab._origin_picker.get_item_text(i),
			"Bonus origins cannot be created through a free-form option")
	var cards: Array[PanelContainer] = []
	for node: Node in tab._bonus_cards.get_children():
		if node is PanelContainer:
			cards.append(node)
	assert(cards.size() == 2, "Two additive +2 AC sources must remain separate")
	for card: PanelContainer in cards:
		var row: HBoxContainer = card.get_child(0) as HBoxContainer
		assert(row != null and row.get_child(0) is Label,
			"Bonus rows must start with their read-only formula before the explicit edit button")
	var selected_style: StyleBoxFlat = cards[0].get_theme_stylebox("panel") as StyleBoxFlat
	var other_style: StyleBoxFlat = cards[1].get_theme_stylebox("panel") as StyleBoxFlat
	assert(selected_style != null and other_style != null)
	assert(selected_style.border_width_left == 2 and other_style.border_width_left == 1,
		"Selecting an origin must outline only its own bonus, including a disabled one")
	tab._selected_origin = "custom|beta"
	tab._refresh()
	cards.clear()
	for node: Node in tab._bonus_cards.get_children():
		if node is PanelContainer:
			cards.append(node)
	selected_style = cards[0].get_theme_stylebox("panel") as StyleBoxFlat
	other_style = cards[1].get_theme_stylebox("panel") as StyleBoxFlat
	assert(selected_style.border_width_left == 1 and other_style.border_width_left == 2,
		"Changing the selected origin must move the highlight without merging bonuses")
	tab.queue_free()
	await process_frame
	print("PASS: bonus origin highlighted without repeating its label beside expressions")
	quit()
