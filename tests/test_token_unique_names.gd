extends SceneTree

const DnDBase = preload("res://dnd_base.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var none: Array[String] = []
	assert(DnDBase.unique_token_display_name("Ape", none) == "Ape")

	var base_taken: Array[String] = ["Ape"]
	assert(
		DnDBase.unique_token_display_name("Ape", base_taken)
		== "Ape 1"
	)

	var numbered: Array[String] = ["Ape", "Ape 1", "Ape 3"]
	assert(
		DnDBase.unique_token_display_name("Ape", numbered)
		== "Ape 2"
	)

	# Changing miniature must recompute from the new creature base name,
	# rather than carrying the previous automatic suffix across.
	var mixed: Array[String] = ["Ape", "Ape 1", "Goblin"]
	assert(
		DnDBase.unique_token_display_name("Goblin", mixed)
		== "Goblin 1"
	)
	assert(
		DnDBase.unique_token_display_name("Giant Goat", mixed)
		== "Giant Goat"
	)

	# Display-name uniqueness is case-insensitive and ignores edge spaces.
	var case_variant: Array[String] = ["  APE  ", "ape 1"]
	assert(
		DnDBase.unique_token_display_name("Ape", case_variant)
		== "Ape 2"
	)

	print("PASS: token display names are unique and suffixes follow live names")
	quit()
