extends Control

# Standalone preview of the shared creature systems. No board scene or token
# nodes are instantiated. A mobile shell can replace this navigation later.
const CreatureSheet = preload("res://vtt/creature_area.gd")
const Compendium = preload("res://vtt/compendium.gd")
const DiceRoller = preload("res://vtt/dice_roller_chat.gd")

@onready var ui_root: CanvasLayer = $UI

var creature_area: Node
var compendium: Node
var dice_roller: Node


func _ready() -> void:
	dice_roller = DiceRoller.new()
	dice_roller.name = "DiceRollerChat"
	add_child(dice_roller)
	dice_roller.setup(self, "standalone", Callable(), ui_root, false)

	compendium = Compendium.new()
	compendium.name = "Compendio"
	add_child(compendium)
	compendium.setup(self, ui_root)

	creature_area = CreatureSheet.new()
	creature_area.name = "CreatureArea"
	add_child(creature_area)
	creature_area.setup(self, ui_root, false)

	_build_navigation()
	creature_area.show_panel()


func _build_navigation() -> void:
	var bar := HBoxContainer.new()
	bar.name = "StandaloneNavigation"
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 46.0
	bar.add_theme_constant_override("separation", 8)
	ui_root.add_child(bar)

	var creatures_button := Button.new()
	creatures_button.text = "Creature"
	creatures_button.pressed.connect(creature_area.show_panel)
	bar.add_child(creatures_button)

	var compendium_button := Button.new()
	compendium_button.text = "Compendio"
	compendium_button.pressed.connect(compendium.show_panel)
	bar.add_child(compendium_button)

	var dice_button := Button.new()
	dice_button.text = "Dadi"
	dice_button.pressed.connect(dice_roller.toggle_panel)
	bar.add_child(dice_button)


func get_public_status_entries() -> Array[Dictionary]:
	if creature_area == null:
		return []
	return creature_area.get_public_status_entries()
