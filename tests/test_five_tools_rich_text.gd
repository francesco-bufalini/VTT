extends SceneTree
# Offline regression for nested 5etools entries and a real Godot BBCode label.
const RichEntries = preload("res://vtt/five_tools_rich_text.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var fixture: Array = [
		{
			"type": "entries", "name": "Tratto con tabella",
			"entries": [
				"Il bersaglio subisce {@damage 2d6} danni. {@b Importante}.",
				{
					"type": "table", "caption": "Effetti casuali",
					"colLabels": ["d6", "Effetto"],
					"rows": [
						[{"type": "cell", "roll": {"min": 1, "max": 2}}, "Danno"],
						[{"type": "cell", "roll": {"exact": 3}}, "{@condition stunned}"],
						[4, "Uno [b] non deve formattarsi"]
					],
					"footnotes": ["Tira un {@dice 1d6}."]
				},
				{"type": "list", "items": [
					{"type": "item", "name": "Azione", "entry": "Prima opzione"},
					"Seconda opzione"
				]}
			]
		},
		{
			"type": "spellcasting", "name": "Incantesimi",
			"headerEntries": ["L'incantatore usa {@spell fireball}."],
			"spells": {"0": {"spells": ["{@spell light}"]}}
		}
	]
	var rendered: String = RichEntries.blocks(fixture)
	assert("[table=2]" in rendered, "5etools tables must survive rendering")
	assert(rendered.count("[cell bg=") == 8, "Two headers and six row cells required")
	assert("1–2" in rendered and "Effetti casuali" in rendered)
	assert("[b]Importante[/b]" in rendered, "Inline text formatting must survive")
	assert("•  " in rendered and "Prima opzione" in rendered)
	assert("[lb]b[rb]" in rendered, "Text data must not inject BBCode")
	assert("Trucchetti" in rendered and "light" in rendered)
	var label := RichTextLabel.new()
	root.add_child(label)
	RichEntries.style(label)
	label.text = rendered
	assert(label.bbcode_enabled, "Godot RichTextLabel must parse the table markup")
	assert("Danno" in label.get_parsed_text(), "Cells must render as visible text")
	label.queue_free()
	print("PASS: 5etools rich text renderer")
	quit()
