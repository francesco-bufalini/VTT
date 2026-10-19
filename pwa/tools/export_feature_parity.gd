extends SceneTree
const Runtime = preload("res://vtt/class_feature_activation.gd")
const Meta = preload("res://vtt/spell_metamagic.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2: quit(2); return
	var cases: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not cases is Array: quit(2); return
	var output: Array = []
	for test: Dictionary in cases:
		var result: Dictionary
		match String(test.get("operation", "activate")):
			"convert": result = Runtime.convert_slots(test.record, int(test.options.level), bool(test.options.create_slot))
			"recover": result = Runtime.recover_slots(test.record, test.options.levels)
			"metamagic": result = Meta.plan(test.record, test.spell, int(test.level), test.selection)
			_: result = Runtime.activate(test.record, test.id, test.get("options", {}))
		output.append(result)
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	if file == null: quit(2); return
	file.store_string(JSON.stringify(output));file.close()
	print("PASS: exported native privilege effect fixtures")
	quit()
