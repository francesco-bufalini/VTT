extends SceneTree
var failures: int = 0
var checked: int = 0

func _initialize() -> void:
	_scan("res://")
	print("Script compilation: %d scripts, %d failure(s)" % [checked,failures])
	quit(0 if failures == 0 else 1)

func _scan(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file in directory.get_files():
		if file.ends_with(".gd"):
			var script: Script = load(path.path_join(file))
			checked += 1
			if script == null or not script.can_instantiate():
				failures += 1
	for child in directory.get_directories():
		if not child.begins_with("."):
			_scan(path.path_join(child))
