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

# Eight sheet-navigation artworks generated specifically for VTT.
# An 8-frame transparent atlas keeps the same artwork on desktop, Android and web.
const CHARACTER_TAB_ART: Texture2D = preload("res://pwa/icons/character_tabs.png")
const CHARACTER_TAB_TITLES := ["Info", "Statistiche", "Cosa posso fare?", "Poteri",
	"Inventario", "Tratti", "Condizioni", "Modifica personaggio"]

static func character_tab_icon(title: String) -> Texture2D:
	var label := "Statistiche" if title == "Caratteristiche e abilità" else title
	var index := CHARACTER_TAB_TITLES.find(label)
	if index < 0:
		return icon("weapon") if label == "Battaglia" else icon("information")
	var frame := AtlasTexture.new()
	frame.atlas = CHARACTER_TAB_ART
	frame.region = Rect2(index * 32, 0, 32, 32)
	return frame

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

static func icon(key: String) -> AtlasTexture:
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
			box.shadow_size = 2
			control.add_theme_stylebox_override(slot, box)
	if control is Label and control.has_theme_color_override("font_color"):
		var color := control.get_theme_color("font_color")
		if color.b > color.r:
			control.add_theme_color_override("font_color", GOLD if control.get_theme_font_size("font_size") >= 17 else MUTED)
