extends RefCounted
## Shared visual primitives for creature sheets, including late-loaded editors.
const GOLD := Color("edbd77")
const INK := Color("f5eee5")
const MUTED := Color("c7bdb1")
const GENERATED_ICON_KEYS := ["action","bonus","free","movement","reaction","sword","help","shove","prone","stealth","eye","object","speech","target","shield","book","spark","flag","skill","hand","acrobatics","animal_handling","arcana","armor","athletics","attack_bonus","bardic_inspiration","break_concentration","buff","check","coins","concentration","condition","cross","dash","debuff","deception","decrease","details","disengage","dodge","filter","fire","flight","grapple","healing","help_alt","hide","history","ice","increase","information","infusion","insight","interact","intimidation","inventory","investigation","invisibility","key","lightning","lock","magic_item","maneuver","map","mark_enemy","medicine","misty_step","nature","necromancy","opportunity_attack","perception","persuasion","poison","potion","proficiency","prone_alt","reaction_trigger","ready","religion","reset","rest_long","rest_short","save_throw","scroll","search","settings","sleight_of_hand","speed","spell_cast","spell_slot","stealth_check","summon","survival","talk","teleport","weapon","wild_shape"]
const GENERATED_ICON_ATLASES := [
	preload("res://pwa/icons/gold_generated/gold_0.svg"),
	preload("res://pwa/icons/gold_generated/gold_1.svg"),
	preload("res://pwa/icons/gold_generated/gold_2.svg"),
	preload("res://pwa/icons/gold_generated/gold_3.svg")
]

static func surface(background: Color, border: Color, radius: int = 7, padding: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(padding)
	# Shared lightweight surface treatment: gold edge, depth and a softer shadow.
	style.shadow_color = Color(0, 0, 0, 0.24)
	style.shadow_size = 2
	style.shadow_offset = Vector2(0, 1)
	style.anti_aliasing = true
	return style

static func icon(key: String) -> Texture2D:
	if key.begins_with("info_"):
		return load("res://assets/creature_info/" + key.trim_prefix("info_") + ".svg") as Texture2D
	var index := GENERATED_ICON_KEYS.find(key)
	if index < 0: index = GENERATED_ICON_KEYS.find("information")
	var texture := AtlasTexture.new()
	texture.atlas = GENERATED_ICON_ATLASES[int(index / 25)]
	texture.region = Rect2((index % 25) * 64, 0, 64, 64)
	return texture

static func sheet_theme() -> Theme:
	var theme := (preload("res://vtt/ui/dnd5e_theme.tres") as Theme).duplicate(true) as Theme
	var panel := surface(Color("221d1cf7"), Color("c99750"), 11, 10)
	panel.border_width_top = 2
	for type: String in ["PanelContainer", "Panel", "AcceptDialog", "PopupPanel"]:
		theme.set_stylebox("panel", type, panel)
	for type: String in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", type, surface(Color("352928"), Color("89643f"), 7, 7))
		theme.set_stylebox("hover", type, surface(Color("49342e"), GOLD, 7, 7))
		theme.set_stylebox("pressed", type, surface(Color("542a33"), GOLD, 7, 7))
		theme.set_color("font_color", type, INK)
		theme.set_color("font_hover_color", type, GOLD)
	for type: String in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", type, surface(Color("211c1c"), Color("785a39"), 7, 7))
		theme.set_color("font_color", type, INK)
		theme.set_color("font_placeholder_color", type, MUTED)
	theme.set_color("font_color", "Label", INK)
	theme.set_color("default_color", "RichTextLabel", INK)
	return theme

static func install(root: Control) -> void:
	root.theme = sheet_theme()
	_watch(root)

static func _watch(node: Node) -> void:
	if node.name == "ScrollableCaptions": return
	# Apply after construction so explicit local styles can keep their geometry.
	_polish.call_deferred(node)
	if not node.child_entered_tree.is_connected(_watch):
		node.child_entered_tree.connect(_watch)
	for child: Node in node.get_children(): _watch(child)

static func _polish(node: Node) -> void:
	if not is_instance_valid(node) or not node is Control: return
	var control := node as Control
	for slot: String in ["panel", "normal", "focus"]:
		if not control.has_theme_stylebox_override(slot): continue
		var old := control.get_theme_stylebox(slot) as StyleBoxFlat
		# Replace legacy blue surfaces while keeping warning/selection colors.
		if old != null and (old.bg_color.b > old.bg_color.r or old.border_color.b > old.border_color.r):
			var box := old.duplicate() as StyleBoxFlat
			box.bg_color = Color("352928f7")
			box.border_color = Color("9c7048")
			box.shadow_color = Color(0, 0, 0, 0.24)
			box.set_corner_radius_all(8)
			box.shadow_size = 3
			box.shadow_offset = Vector2(0, 2)
			control.add_theme_stylebox_override(slot, box)
	if control is Label and control.has_theme_color_override("font_color"):
		var color := control.get_theme_color("font_color")
		if color.b > color.r:
			control.add_theme_color_override("font_color", GOLD if control.get_theme_font_size("font_size") >= 17 else MUTED)

static func section_style() -> StyleBoxFlat:
	var box := surface(Color("221d1cf7"), Color("c99750"), 11, 11)
	box.border_width_top = 2
	box.shadow_size = 6
	return box

static func card_style() -> StyleBoxFlat:
	var box := surface(Color("352928f7"), Color("9c7048"), 8, 8)
	box.shadow_size = 3
	box.shadow_offset = Vector2(0, 2)
	return box

static func heading(label: Label, icon_key: String = "information") -> void:
	_heading_later.call_deferred(label, icon_key)

static func _heading_later(label: Label, icon_key: String) -> void:
	if not is_instance_valid(label) or label.has_meta("sheet_heading"): return
	label.set_meta("sheet_heading", true)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", GOLD)
	if label.text == label.text.to_upper():
		var words := label.text.to_lower().split(" ")
		for i: int in range(words.size()):
			if words[i] in ["ca", "pf", "cd", "ts", "xp"]: words[i] = words[i].to_upper()
		if not words.is_empty() and words[0] not in ["CA", "PF", "CD", "TS", "XP"]: words[0] = words[0].capitalize()
		label.text = " ".join(words)
	var parent := label.get_parent()
	if not (parent is VBoxContainer or parent is HBoxContainer or parent is PanelContainer): return
	var index := label.get_index()
	var row: HBoxContainer
	if parent is VBoxContainer or parent is PanelContainer:
		row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		parent.remove_child(label)
		parent.add_child(row)
		parent.move_child(row, index)
		row.add_child(label)
	else:
		row = parent as HBoxContainer
	var emblem := TextureRect.new()
	var key := icon_key
	if key == "information":
		var caption := label.text.to_lower()
		var icons := {"ferita": "healing", "caratteristiche": "proficiency", "abilità": "skill", "risorse": "reset", "attacchi": "sword", "fisico": "movement", "classi": "book", "talenti": "spark", "storia": "scroll", "condizioni": "condition", "linguaggi": "speech"}
		for word: String in icons:
			if word in caption:
				key = String(icons[word])
				break
	emblem.texture = icon(key)
	emblem.custom_minimum_size = Vector2(28, 28)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(emblem)
	row.move_child(emblem, label.get_index())
