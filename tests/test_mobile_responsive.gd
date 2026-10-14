extends SceneTree
const Mobile = preload("res://vtt/mobile/creatures_mobile.tscn")

func _initialize() -> void:
 call_deferred("run")

func settle() -> void:
 for i: int in range(15):
  await process_frame

func run() -> void:
 root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
 root.size = Vector2i(390, 844)
 var manager := root.get_node("CampaignManager")
 manager.selected_campaign_group_id = "mobile_responsive_%d" % Time.get_ticks_usec()
 manager.active_campaign_id = ""
 var mobile := Mobile.instantiate()
 root.add_child(mobile)
 await settle()
 var sheet: Node = mobile.creature_area
 var record: Dictionary = load("res://vtt/player_character_store.gd").new().create_character()
 record.kind = "character"
 record.name = "Mobile responsive wizard"
 record.classes = [{"name":"Wizard", "level":5, "source":"PHB"}]
 sheet._records.assign([record])
 sheet._selected_id = record.id
 sheet._selected_kind = "character"
 sheet._load_form(record)
 sheet.show_touch_library(false)
 for width: int in [360, 390, 480]:
  root.size = Vector2i(width, 844)
  await settle()
  for index: int in range(sheet._tabs.get_tab_count()):
   sheet._tabs.current_tab = index
   await settle()
   var scroll := sheet._tabs.get_tab_control(index) as ScrollContainer
   assert(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED)
   print("WIDTH ",width," TAB ",index," panel ",sheet._panel.size.x," scroll ",scroll.size.x," content_min ",scroll.get_child(0).get_combined_minimum_size().x)
   assert(sheet._panel.size.x <= width + 1, "Mobile sheet must stay within viewport")
   assert(scroll.get_child(0).get_combined_minimum_size().x <= scroll.size.x + 1, "Tab contents must fit without horizontal scrolling")
 var button := Button.new()
 button.text = "Test help"
 button.tooltip_text = "Explanation for touch"
 button.position = Vector2(10, 120)
 button.size = Vector2(130, 48)
 button.z_index = 240
 mobile.ui_root.add_child(button)
 var clicked := [0]
 button.pressed.connect(func() -> void: clicked[0] += 1)
 await settle()
 var down := InputEventScreenTouch.new()
 down.pressed = true
 down.position = button.get_global_rect().get_center()
 root.push_input(down, true)
 mobile._finger_started_msec -= 600
 var up := InputEventScreenTouch.new()
 up.position = down.position
 root.push_input(up, true)
 await settle()
 assert(mobile._help_panel.visible and mobile._help_text.text == button.tooltip_text)
 assert(clicked[0] == 0, "Long press help must not activate the button")
 mobile._help_panel.hide()
 button.queue_free()
 var packs := root.get_node("TokenPackManager")
 assert(packs._accept_catalog_text(FileAccess.get_file_as_string(packs.OFFLINE_CATALOG_PATH), false))
 assert(not mobile.list_available_miniatures().is_empty())
 sheet._choose_miniature(record, false, true)
 await settle()
 assert(sheet._miniature_dialog.visible and not sheet._miniature_choices.is_empty())
 assert(sheet._miniature_dialog.size.x <= root.size.x)
 sheet._miniature_dialog.hide()
 var dialog := ConfirmationDialog.new()
 dialog.dialog_text = "A long explanation that must wrap on mobile. ".repeat(12)
 mobile.ui_root.add_child(dialog)
 load("res://vtt/dialog_layout.gd").popup(dialog, Vector2i(800, 600))
 await settle()
 assert(dialog.size.x <= root.size.x and dialog.size.y <= root.size.y)
 dialog.hide()
 dialog.queue_free()
 mobile.queue_free()
 await settle()
 print("PASS: responsive mobile tabs, bounded dialogs, non-activating long press and offline miniature selection")
 quit()