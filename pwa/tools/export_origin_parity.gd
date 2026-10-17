extends SceneTree

const Structured = preload("res://vtt/structured_origin_spells_5etools.gd")
const Catalog = preload("res://vtt/spells/spell_catalog.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var cases: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://pwa/.test-artifacts/origin-cases.json"))
	if not cases is Array:
		push_error("Missing synthetic PWA parity cases")
		quit(1)
		return
	var results: Array = []
	for record: Dictionary in cases:
		results.append(Structured.for_creature(record))
	var file := FileAccess.open("res://pwa/.test-artifacts/native-origin-parity.json", FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	var spells: Array = Catalog.all_spells()
	spells.append_array(Catalog.all_spells_for_rules("2014"))
	file.store_string(JSON.stringify({"cases": cases, "results": results, "spells": spells}))
	file.close()
	print("PASS: native structured origin fixtures exported without changing user archives")
	quit()
