extends VBoxContainer
## Local action economy summary for desktop and Android sheets.
const GROUPS := ["Azione", "Azione bonus", "Azione gratuita", "Movimento", "Reazione"]
const BASIC := [
 ["Attaccare", 0, "Attacco con arma o colpo senz'armi."],
 ["Scattare", 0, "Movimento aggiuntivo pari alla velocità."],
 ["Disimpegnarsi", 0, "Evita attacchi di opportunità dovuti al movimento."],
 ["Schivare", 0, "Concentrati sulla difesa."],
 ["Aiutare", 0, "Aiuta un alleato in una prova o contro un avversario."],
 ["Nascondersi", 0, "Prova di Destrezza (Furtività)."],
 ["Cercare", 0, "Prova di Percezione o Indagare."],
 ["Preparare", 0, "Prepara un'azione da eseguire con la reazione."],
 ["Usare un oggetto", 0, "Utilizza un oggetto che richiede un'azione."],
 ["Interagire con un oggetto", 2, "Interazione semplice durante il turno."],
 ["Muoversi", 3, "Usa il movimento disponibile."],
 ["Attacco di opportunità", 4, "Attacco in mischia come reazione, se applicabile."]
]
var _sections: Array[VBoxContainer] = []

func _ready() -> void:
 for title: String in GROUPS:
  var section := VBoxContainer.new()
  var heading := Label.new()
  heading.text = title
  heading.add_theme_font_size_override("font_size", 19)
  section.add_child(heading)
  add_child(section)
  _sections.append(section)

func _category(value: String) -> int:
 var normalized := value.to_lower()
 if "reaction" in normalized or "reazione" in normalized: return 4
 if "bonus" in normalized: return 1
 if "free" in normalized or "gratuit" in normalized: return 2
 if "move" in normalized or "movimento" in normalized: return 3
 return 0

func _add_entry(title: String, category: int, detail: String, kind: String = "", tracker: String = "") -> void:
 var button := Button.new()
 button.text = title + (" · " + kind if not kind.is_empty() else "") + (" · " + tracker if not tracker.is_empty() else "")
 button.alignment = HORIZONTAL_ALIGNMENT_LEFT
 button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 button.tooltip_text = detail
 button.pressed.connect(func() -> void:
  var dialog := AcceptDialog.new()
  dialog.title = title
  dialog.dialog_text = detail
  add_child(dialog)
  dialog.popup_centered_ratio(0.65)
  dialog.confirmed.connect(dialog.queue_free)
  dialog.close_requested.connect(dialog.queue_free)
 )
 _sections[clampi(category, 0, 4)].add_child(button)

func load_record(record: Dictionary) -> void:
 if _sections.is_empty(): return
 for section: VBoxContainer in _sections:
  for child: Node in section.get_children():
   if child is Button: child.queue_free()
 for basic: Array in BASIC:
  _add_entry(str(basic[0]), int(basic[1]), str(basic[2]), "Generale")
 for attack in record.get("attacks", []):
  if attack is Dictionary:
   _add_entry(str(attack.get("name", "Attacco")), 0, str(attack.get("description", "")), "Attacco", str(attack.get("tracker_id", "")))
 for feature in record.get("action_grants", []):
  if feature is Dictionary and not bool(feature.get("disabled", false)):
   _add_entry(str(feature.get("name", "Capacità")), _category(str(feature.get("action_type", feature.get("activation", "action")))), str(feature.get("description", "")), "Capacità", str(feature.get("tracker_id", "")))
 for spell in record.get("prepared_spells", []):
  if spell is Dictionary:
   _add_entry(str(spell.get("name", spell.get("id", "Incantesimo"))), _category(str(spell.get("casting_time", "action"))), str(spell.get("description", "")), "Incantesimo")
