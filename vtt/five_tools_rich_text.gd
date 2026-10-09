extends RefCounted

# Present the nested 5etools "entries" format with Godot's own RichTextLabel.
# Keep the sheet's normal font, scrollbars and parchment/burgundy palette;
# no embedded browser or separate HTML style is needed.
const GOLD := "#dfb67d"
const MUTED := "#bbac99"
const GRID := "#69503b"
const ROW_A := "#292322"
const ROW_B := "#302827"
const ROW_HEAD := "#46352f"
const MAX_DEPTH := 16


static func style(label: RichTextLabel) -> void:
	label.bbcode_enabled = true
	label.selection_enabled = true
	label.scroll_active = true
	label.add_theme_color_override("default_color", Color(0.94, 0.89, 0.80))
	label.add_theme_constant_override("line_separation", 3)


static func title(value: String) -> String:
	return "[font_size=18][b]%s[/b][/font_size]" % _escape(value)


static func meta(value: String) -> String:
	return "[color=%s]%s[/color]" % [MUTED, _escape(value)]


static func section(value: String) -> String:
	return "[font_size=15][b][color=%s]%s[/color][/b][/font_size]" % [
		GOLD, _escape(value)
	]


static func subtitle(value: String) -> String:
	return "[b][color=%s]%s[/color][/b]" % [GOLD, _escape(value)]


static func blocks(value: Variant) -> String:
	return _block(value, 0)


static func _block(value: Variant, depth: int) -> String:
	if depth >= MAX_DEPTH or value == null:
		return ""
	if value is String:
		return _inline(String(value))
	if value is Array:
		var parts: PackedStringArray = []
		for item: Variant in value:
			var part: String = _block(item, depth + 1).strip_edges()
			if not part.is_empty():
				parts.append(part)
		return "\n\n".join(parts)
	if not value is Dictionary:
		return _escape(str(value))

	var data: Dictionary = value as Dictionary
	var kind: String = String(data.get("type", "")).to_lower()
	if kind == "table" or (data.has("rows") and data.has("colLabels")):
		return _table(data, depth + 1)
	if kind == "tablegroup" or data.has("tables"):
		var tables: String = _block(data.get("tables", []), depth + 1)
		var table_name: String = String(data.get("name", "")).strip_edges()
		return (subtitle(table_name) + "\n" if not table_name.is_empty() else "") + tables
	if kind == "spellcasting":
		return _spellcasting(data, depth + 1)
	if kind == "list" or data.has("items"):
		return _list(data, depth + 1)

	var name: String = String(data.get("name", "")).strip_edges()
	var body: String = ""
	if data.has("entries"):
		body = _block(data["entries"], depth + 1)
	elif data.has("entry"):
		body = _block(data["entry"], depth + 1)
	elif data.has("description"):
		body = _block(data["description"], depth + 1)
	elif data.has("text"):
		body = _block(data["text"], depth + 1)
	elif data.has("roll"):
		return _roll(data["roll"])
	if name.is_empty():
		return body
	if body.is_empty():
		return subtitle(name)
	if kind == "item":
		return subtitle(name) + " " + body
	return subtitle(name) + "\n" + body


static func _list(data: Dictionary, depth: int) -> String:
	var lines: PackedStringArray = []
	var items: Variant = data.get("items", [])
	if items is Array:
		for item: Variant in items:
			var value: String = _block(item, depth + 1).strip_edges()
			if not value.is_empty():
				lines.append("•  " + value)
	var list_body: String = "\n".join(lines)
	var name: String = String(data.get("name", "")).strip_edges()
	if name.is_empty():
		return list_body
	return subtitle(name) + "\n" + list_body


static func _table(data: Dictionary, depth: int) -> String:
	var labels: Array = data.get("colLabels", []) if data.get("colLabels", []) is Array else []
	var rows: Array = data.get("rows", []) if data.get("rows", []) is Array else []
	var columns: int = labels.size()
	for original: Variant in rows:
		var row: Variant = original
		if row is Dictionary:
			row = (row as Dictionary).get("row", [])
		if row is Array:
			columns = maxi(columns, (row as Array).size())
	if columns <= 0:
		return ""
	columns = mini(columns, 16)
	var cells: PackedStringArray = []
	for col: int in range(columns):
		var heading: String = _cell_value(labels[col], depth + 1) if col < labels.size() else ""
		if not labels.is_empty():
			cells.append(_cell(heading, ROW_HEAD, true))
	for row_index: int in range(rows.size()):
		var raw_row: Variant = rows[row_index]
		var row: Array = []
		if raw_row is Array:
			row = raw_row
		elif raw_row is Dictionary and (raw_row as Dictionary).get("row") is Array:
			row = (raw_row as Dictionary)["row"]
		var background: String = ROW_A if row_index % 2 == 0 else ROW_B
		for col: int in range(columns):
			var value: String = _cell_value(row[col], depth + 1) if col < row.size() else ""
			cells.append(_cell(value, background, false))
	var table_text: String = "[table=%d]%s[/table]" % [columns, "".join(cells)]
	var caption: String = String(data.get("caption", "")).strip_edges()
	if not caption.is_empty():
		table_text = subtitle(caption) + "\n" + table_text
	var footnotes: Variant = data.get("footnotes", [])
	if footnotes is Array and not (footnotes as Array).is_empty():
		table_text += "\n" + meta("Note:") + "\n" + _block(footnotes, depth + 1)
	return table_text


static func _cell(value: String, background: String, is_heading: bool) -> String:
	var text_value: String = "[b]%s[/b]" % value if is_heading else value
	return "[cell bg=%s border=%s padding=7,5,7,5]%s[/cell]" % [
		background, GRID, text_value
	]


static func _cell_value(value: Variant, depth: int) -> String:
	if value is Dictionary:
		var data: Dictionary = value as Dictionary
		if data.has("roll"):
			var roll_text: String = _roll(data["roll"])
			var extra: String = _block(data.get("entry", ""), depth + 1)
			return roll_text if extra.is_empty() else roll_text + " " + extra
	return _block(value, depth + 1).replace("\n\n", "\n")


static func _roll(value: Variant) -> String:
	if not value is Dictionary:
		return _inline(str(value))
	var roll: Dictionary = value as Dictionary
	if roll.has("exact"):
		return _escape(str(roll["exact"]))
	if roll.has("min") and roll.has("max"):
		return _escape("%s–%s" % [str(roll["min"]), str(roll["max"])])
	return _escape(str(roll.get("min", roll.get("max", ""))))


static func _spellcasting(data: Dictionary, depth: int) -> String:
	var parts: PackedStringArray = []
	var name: String = String(data.get("name", "")).strip_edges()
	if not name.is_empty():
		parts.append(subtitle(name))
	var opening: String = _block(data.get("headerEntries", data.get("entries", [])), depth + 1)
	if not opening.is_empty():
		parts.append(opening)
	var levels: Variant = data.get("spells", {})
	if levels is Dictionary:
		var keys: Array = (levels as Dictionary).keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool:
			return int(str(a)) < int(str(b))
		)
		for raw_key: Variant in keys:
			var key: String = String(raw_key)
			var line: Variant = (levels as Dictionary)[raw_key]
			if not line is Dictionary:
				continue
			var spell_names: Variant = (line as Dictionary).get("spells", [])
			var summary: String = _block(spell_names, depth + 1).replace("\n\n", ", ")
			if not summary.is_empty():
				parts.append(subtitle("Trucchetti" if key == "0" else "Livello " + key) + ": " + summary)
	for frequency: String in ["will", "daily", "rest", "weekly", "yearly", "constant"]:
		var collection: Variant = data.get(frequency, {})
		if collection is Dictionary:
			for key: Variant in (collection as Dictionary).keys():
				parts.append(subtitle(String(key) + " " + frequency) + ": "
					+ _block((collection as Dictionary)[key], depth + 1).replace("\n\n", ", "))
	parts.append(_block(data.get("footerEntries", []), depth + 1))
	var output: PackedStringArray = []
	for part: String in parts:
		if not part.is_empty():
			output.append(part)
	return "\n\n".join(output)


static func _inline(value: String) -> String:
	# 5etools inline tags are data, not BBCode. Convert only supported tags;
	# always escape literal brackets to prevent homebrew markup injection.
	var tag_regex := RegEx.new()
	tag_regex.compile("\\{@([A-Za-z][A-Za-z0-9]*)\\s*([^{}]*)\\}")
	var parts: PackedStringArray = []
	var position: int = 0
	for match_value: RegExMatch in tag_regex.search_all(value):
		parts.append(_escape(value.substr(position, match_value.get_start() - position)))
		var tag_name: String = match_value.get_string(1).to_lower()
		var args: PackedStringArray = match_value.get_string(2).split("|")
		var display: String = args[0].strip_edges()
		if args.size() > 2 and not args[2].strip_edges().is_empty():
			display = args[2].strip_edges()
		var visible: String = _escape(display)
		match tag_name:
			"b", "bold", "strong":
				parts.append("[b]%s[/b]" % visible)
			"i", "italic", "note":
				parts.append("[i]%s[/i]" % visible)
			"u":
				parts.append("[u]%s[/u]" % visible)
			"s", "strike":
				parts.append("[s]%s[/s]" % visible)
			"hit":
				parts.append("+" + visible if not visible.begins_with("-") and not visible.begins_with("+") else visible)
			"dc":
				parts.append("CD " + visible)
			"h":
				parts.append("[i]Colpito:[/i] ")
			"recharge":
				parts.append("(Ricarica %s–6)" % visible if not visible.is_empty() else "(Ricarica 6)")
			"dice", "damage", "d20":
				parts.append("[b][color=%s]%s[/color][/b]" % [GOLD, visible])
			"spell", "condition", "skill", "sense", "item":
				parts.append("[color=%s]%s[/color]" % [GOLD, visible])
			"atk":
				parts.append("[i]%s[/i]" % _escape(_attack_name(display)))
			"chance":
				parts.append(visible + "%")
			_:
				parts.append(visible)
		position = match_value.get_end()
	parts.append(_escape(value.substr(position)))
	return "".join(parts)


static func _attack_name(value: String) -> String:
	match value:
		"mw":
			return "Melee Weapon Attack:"
		"rw":
			return "Ranged Weapon Attack:"
		"ms":
			return "Melee Spell Attack:"
		"rs":
			return "Ranged Spell Attack:"
		"mw,rw":
			return "Melee or Ranged Weapon Attack:"
		"ms,rs":
			return "Melee or Ranged Spell Attack:"
		_:
			return value


static func _escape(value: String) -> String:
	var result: String = ""
	for i: int in range(value.length()):
		var ch: String = value.substr(i, 1)
		if ch == "[":
			result += "[lb]"
		elif ch == "]":
			result += "[rb]"
		else:
			result += ch
	return result
