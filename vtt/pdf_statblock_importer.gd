extends RefCounted

const PDF_HELPER := "res://tools/pdf_statblock_extract.py"

const SECTION_KEYS := {
	"traits": "trait",
	"trait": "trait",
	"tratti": "trait",
	"actions": "action",
	"action": "action",
	"azioni": "action",
	"bonus actions": "bonus",
	"bonus action": "bonus",
	"azioni bonus": "bonus",
	"reactions": "reaction",
	"reaction": "reaction",
	"reazioni": "reaction",
	"legendary actions": "legendary",
	"azioni leggendarie": "legendary",
	"mythic actions": "mythic",
	"azioni mitiche": "mythic",
	"lair actions": "lairActions",
	"azioni di tana": "lairActions",
	"regional effects": "regionalEffects",
	"effetti regionali": "regionalEffects",
}

const SIZE_CODES := {
	"tiny": "T",
	"small": "S",
	"medium": "M",
	"large": "L",
	"huge": "H",
	"gargantuan": "G",
	"minuscola": "T",
	"piccola": "S",
	"media": "M",
	"grande": "L",
	"enorme": "H",
	"mastodontica": "G",
}


func import_pdf(path: String) -> Dictionary:
	var extraction := extract_pdf_text(path)
	if not bool(extraction.get("ok", false)):
		return extraction

	var text := String(extraction.get("text", "")).strip_edges()
	if text.is_empty():
		return {
			"ok": false,
			"message": (
				"Il PDF non contiene testo leggibile. "
				+ "Se è una scansione serve OCR (Tesseract/Poppler)."
			)
		}

	var stat := parse_stat_block_text(
		text,
		path.get_file().get_basename()
	)
	if stat.is_empty():
		return {
			"ok": false,
			"message": "Non riesco a riconoscere uno stat block nel PDF."
		}

	return {
		"ok": true,
		"stat_block": stat,
		"text": text,
		"method": String(extraction.get("method", "")),
		"warning": String(extraction.get("warning", "")),
	}


func extract_pdf_text(path: String) -> Dictionary:
	if path.get_extension().to_lower() != "pdf":
		return {"ok": false, "message": "Seleziona un file PDF."}
	if not FileAccess.file_exists(path):
		return {"ok": false, "message": "Il PDF selezionato non esiste più."}

	var helper_path := ProjectSettings.globalize_path(PDF_HELPER)
	if not FileAccess.file_exists(helper_path):
		# In an exported project res:// may live inside the PCK. Materialize
		# the helper under user:// so Python can execute a real filesystem file.
		if not FileAccess.file_exists(PDF_HELPER):
			return {
				"ok": false,
				"message": "Helper PDF non trovato nel progetto."
			}
		var helper_text := FileAccess.get_file_as_string(PDF_HELPER)
		var user_helper := "user://pdf_statblock_extract.py"
		var helper_file := FileAccess.open(user_helper, FileAccess.WRITE)
		if helper_file == null:
			return {
				"ok": false,
				"message": "Impossibile preparare l'estrattore PDF."
			}
		helper_file.store_string(helper_text)
		helper_file.close()
		helper_path = ProjectSettings.globalize_path(user_helper)

	var candidates: Array[Dictionary] = []
	if OS.get_name() == "Windows":
		candidates.append({
			"exe": "py",
			"args": PackedStringArray(["-3", helper_path, path])
		})
	candidates.append({
		"exe": "python",
		"args": PackedStringArray([helper_path, path])
	})
	candidates.append({
		"exe": "python3",
		"args": PackedStringArray([helper_path, path])
	})

	var last_message := ""
	for candidate: Dictionary in candidates:
		var output: Array = []
		var args: PackedStringArray = candidate.get(
			"args",
			PackedStringArray()
		)
		var exit_code := OS.execute(
			String(candidate.get("exe", "")),
			args,
			output,
			false,
			false
		)
		if exit_code == -1:
			continue

		var output_lines := PackedStringArray()
		for output_value: Variant in output:
			output_lines.append(String(output_value))
		var raw := "\n".join(output_lines).strip_edges()
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			var result := (parsed as Dictionary).duplicate(true)
			if bool(result.get("ok", false)):
				return result
			last_message = String(result.get("message", ""))
		else:
			last_message = (
				raw if not raw.is_empty()
				else "L'estrattore PDF non ha restituito dati."
			)

	if last_message.is_empty():
		last_message = (
			"Python non è disponibile. Installa Python 3 oppure aggiungilo al PATH."
		)
	return {"ok": false, "message": last_message}


static func parse_stat_block_text(
	raw_text: String,
	fallback_name: String = "Creatura PDF"
) -> Dictionary:
	var text := _normalize_text(raw_text)
	var lines := _clean_lines(text)
	if lines.is_empty():
		return {}

	var stat: Dictionary = {
		"name": _guess_name(lines, fallback_name),
		"source": "PDF",
		"page": 0,
		"_imported_pdf": true,
		"_pdf_name": fallback_name,
		"raw_text": "\n".join(lines),
	}

	_parse_size_type_alignment(lines, stat)
	_parse_core_fields(lines, stat)
	_parse_abilities(text, stat)
	_parse_sections(lines, stat)

	# A usable imported creature must always have an HP pool. If HP was not
	# recognized, keep it explicit so the user can immediately edit it.
	if not stat.has("hp"):
		stat["hp"] = {"average": 1}

	return stat


static func _normalize_text(value: String) -> String:
	var text := value.replace("\r\n", "\n").replace("\r", "\n")
	text = text.replace("\u00a0", " ")
	text = text.replace("–", "-").replace("—", "-")
	var whitespace := RegEx.new()
	if whitespace.compile("[ \\t]+") == OK:
		text = whitespace.sub(text, " ", true)
	return text.strip_edges()


static func _clean_lines(text: String) -> Array[String]:
	var result: Array[String] = []
	var footer_date := RegEx.new()
	footer_date.compile(
		"^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4},\\s*[0-9]{1,2}:[0-9]{2}\\b"
	)
	var page_fraction := RegEx.new()
	page_fraction.compile("^[0-9]+\\s*/\\s*[0-9]+$")

	for raw_line: String in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty():
			continue
		var lower := line.to_lower()
		if lower.begins_with("about:blank"):
			continue
		if footer_date.search(line) != null:
			continue
		if page_fraction.search(line) != null:
			continue
		result.append(line)
	return result


static func _guess_name(
	lines: Array[String],
	fallback_name: String
) -> String:
	# Prefer a heading immediately followed by the size/type line or by the
	# Armor Class block. This skips page headers and PDF document titles.
	for index: int in range(lines.size()):
		var line := lines[index]
		if not _valid_name_candidate(line):
			continue
		for lookahead: int in range(
			index + 1,
			mini(lines.size(), index + 5)
		):
			var next_lower := lines[lookahead].to_lower()
			if (
				_looks_like_size_type_line(next_lower)
				or next_lower.begins_with("armor class")
				or next_lower.begins_with("classe armatura")
				or next_lower.begins_with("ac ")
				or next_lower.begins_with("ca ")
			):
				return line

	for line: String in lines:
		if _valid_name_candidate(line):
			return line
	var fallback := fallback_name.strip_edges()
	return fallback if not fallback.is_empty() else "Creatura PDF"


static func _valid_name_candidate(line: String) -> bool:
	var lower := line.to_lower()
	if _is_field_line(lower) or _section_key(lower) != "":
		return false
	if (
		lower.begins_with("dungeons & dragons")
		or lower.begins_with("challenge rating")
		or lower.begins_with("stat block")
		or lower.begins_with("monster manual")
	):
		return false
	return line.length() <= 100


static func _looks_like_size_type_line(lower: String) -> bool:
	for size_word: Variant in SIZE_CODES.keys():
		if lower.begins_with(String(size_word) + " "):
			return true
	return false


static func _parse_size_type_alignment(
	lines: Array[String],
	stat: Dictionary
) -> void:
	var name := String(stat.get("name", ""))
	var name_index := lines.find(name)
	if name_index < 0:
		return

	for index: int in range(
		name_index + 1,
		mini(lines.size(), name_index + 5)
	):
		var line := lines[index]
		var lower := line.to_lower()
		for size_word: Variant in SIZE_CODES.keys():
			var key := String(size_word)
			if not lower.begins_with(key + " "):
				continue
			stat["size"] = String(SIZE_CODES[key])
			var rest := line.substr(key.length()).strip_edges()
			var comma := rest.find(",")
			if comma >= 0:
				stat["type"] = rest.substr(0, comma).strip_edges()
				stat["alignment"] = rest.substr(comma + 1).strip_edges()
			else:
				stat["type"] = rest
			return


static func _parse_core_fields(
	lines: Array[String],
	stat: Dictionary
) -> void:
	var field_definitions: Array[Dictionary] = [
		{
			"key": "ac",
			"labels": ["armor class", "ac", "classe armatura", "ca"]
		},
		{
			"key": "hp",
			"labels": ["hit points", "hp", "punti ferita", "pf"]
		},
		{
			"key": "speed",
			"labels": ["speed", "velocità", "velocita"]
		},
		{
			"key": "save",
			"labels": ["saving throws", "tiri salvezza", "salvezza"]
		},
		{
			"key": "skill",
			"labels": ["skills", "abilità", "abilita"]
		},
		{
			"key": "vulnerable",
			"labels": [
				"damage vulnerabilities",
				"vulnerabilità ai danni",
				"vulnerabilita ai danni"
			]
		},
		{
			"key": "resist",
			"labels": ["damage resistances", "resistenze ai danni"]
		},
		{
			"key": "immune",
			"labels": [
				"damage immunities",
				"immunità ai danni",
				"immunita ai danni"
			]
		},
		{
			"key": "conditionImmune",
			"labels": [
				"condition immunities",
				"immunità alle condizioni",
				"immunita alle condizioni"
			]
		},
		{
			"key": "senses",
			"labels": ["senses", "sensi"]
		},
		{
			"key": "languages",
			"labels": ["languages", "linguaggi"]
		},
		{
			"key": "cr",
			"labels": [
				"challenge rating",
				"challenge",
				"cr",
				"grado sfida",
				"gs"
			]
		},
		{
			"key": "pbNote",
			"labels": ["proficiency bonus", "bonus di competenza"]
		},
	]

	var seen_fields: Dictionary = {}
	for index: int in range(lines.size()):
		for definition: Dictionary in field_definitions:
			var labels: Array[String] = []
			for label_value: Variant in definition.get("labels", []):
				labels.append(String(label_value))

			var collected := _collect_labeled_value(
				lines,
				index,
				labels
			)
			if not bool(collected.get("matched", false)):
				continue

			var key := String(definition.get("key", ""))
			if seen_fields.has(key):
				break
			var value := String(
				collected.get("value", "")
			).strip_edges()
			if value.is_empty():
				break

			seen_fields[key] = true
			if key == "hp":
				stat[key] = _parse_hp(value)
			else:
				stat[key] = value

			if key == "senses":
				var passive := _extract_first_int_after(
					value.to_lower(),
					[
						"passive perception",
						"percezione passiva"
					]
				)
				if passive >= 0:
					stat["passive"] = passive
			break


static func _collect_labeled_value(
	lines: Array[String],
	index: int,
	labels: Array[String]
) -> Dictionary:
	if index < 0 or index >= lines.size():
		return {"matched": false, "value": ""}

	var line := lines[index].strip_edges()
	var matched_label := _matched_label(line, labels)
	if matched_label.is_empty():
		return {"matched": false, "value": ""}

	var value := line.substr(matched_label.length()).strip_edges()
	while (
		value.begins_with(":")
		or value.begins_with(".")
		or value.begins_with("-")
	):
		value = value.substr(1).strip_edges()

	var parts := PackedStringArray()
	if not value.is_empty():
		parts.append(value)

	var compact_label := matched_label.to_lower()
	var one_line_value := compact_label in [
		"challenge",
		"challenge rating",
		"cr",
		"grado sfida",
		"gs",
		"proficiency bonus",
		"bonus di competenza"
	]

	for next_index: int in range(index + 1, lines.size()):
		var next_line := lines[next_index].strip_edges()
		if next_line.is_empty():
			continue
		if _is_core_value_boundary(next_line):
			break
		if one_line_value and not parts.is_empty():
			break
		parts.append(next_line)
		if one_line_value:
			break

	return {
		"matched": true,
		"value": " ".join(parts).strip_edges()
	}


static func _matched_label(
	line: String,
	labels: Array[String]
) -> String:
	var normalized := line.strip_edges()
	var lower := normalized.to_lower()
	for label: String in labels:
		var candidate := label.to_lower()
		if not lower.begins_with(candidate):
			continue
		var boundary := candidate.length()
		if lower.length() > boundary:
			var next := lower.substr(boundary, 1)
			if next not in [" ", ":", ".", "-"]:
				continue
		return normalized.substr(0, boundary)
	return ""


static func _is_core_value_boundary(line: String) -> bool:
	var lower := line.to_lower().strip_edges()
	if _is_field_line(lower):
		return true
	if _is_ability_label(line):
		return true
	if not _section_key(lower).is_empty():
		return true
	if not _split_entry_line(line).is_empty():
		return true
	return false

static func _parse_hp(value: String) -> Dictionary:
	var hp := {"average": 1}
	var regex := RegEx.new()
	if regex.compile("([0-9]+)(?:\\s*\\(([^)]+)\\))?") != OK:
		return hp
	var hit := regex.search(value)
	if hit == null:
		return hp
	hp["average"] = int(hit.get_string(1))
	var formula := hit.get_string(2).strip_edges()
	if not formula.is_empty():
		hp["formula"] = formula
	return hp


static func _parse_abilities(text: String, stat: Dictionary) -> void:
	var patterns := [
		{
			"labels": ["str", "dex", "con", "int", "wis", "cha"],
			"pattern": (
				"(?is)\\bSTR\\b\\s+\\bDEX\\b\\s+\\bCON\\b\\s+"
				+ "\\bINT\\b\\s+\\bWIS\\b\\s+\\bCHA\\b"
				+ "\\s+([0-9]{1,2})\\s*\\([^)]*\\)"
				+ "\\s+([0-9]{1,2})\\s*\\([^)]*\\)"
				+ "\\s+([0-9]{1,2})\\s*\\([^)]*\\)"
				+ "\\s+([0-9]{1,2})\\s*\\([^)]*\\)"
				+ "\\s+([0-9]{1,2})\\s*\\([^)]*\\)"
				+ "\\s+([0-9]{1,2})"
			)
		},
		{
			"labels": ["str", "dex", "con", "int", "wis", "cha"],
			"pattern": (
				"(?is)\\bFOR\\b\\s+\\bDES\\b\\s+\\bCOS\\b\\s+"
				+ "\\bINT\\b\\s+\\bSAG\\b\\s+\\bCAR\\b"
				+ "\\s+([0-9]{1,2})\\s*\\([^)]*\\)"
				+ "\\s+([0-9]{1,2})\\s*\\([^)]*\\)"
				+ "\\s+([0-9]{1,2})\\s*\\([^)]*\\)"
				+ "\\s+([0-9]{1,2})\\s*\\([^)]*\\)"
				+ "\\s+([0-9]{1,2})\\s*\\([^)]*\\)"
				+ "\\s+([0-9]{1,2})"
			)
		},
	]

	for definition: Dictionary in patterns:
		var regex := RegEx.new()
		if regex.compile(String(definition.get("pattern", ""))) != OK:
			continue
		var hit := regex.search(text)
		if hit == null:
			continue
		var labels: Array = definition.get("labels", [])
		for index: int in range(6):
			stat[String(labels[index])] = int(hit.get_string(index + 1))
		return

	var aliases := {
		"str": "str", "for": "str",
		"dex": "dex", "des": "dex",
		"con": "con", "cos": "con",
		"int": "int",
		"wis": "wis", "sag": "wis",
		"cha": "cha", "car": "cha",
	}

	# Inline layout: "STR 18 (+4) DEX 14 (+2) ..."
	var inline := RegEx.new()
	if inline.compile(
		"(?i)\\b(STR|DEX|CON|INT|WIS|CHA|FOR|DES|COS|SAG|CAR)"
		+ "\\s*([0-9]{1,2})\\s*\\("
	) == OK:
		for hit: RegExMatch in inline.search_all(text):
			var label := hit.get_string(1).to_lower()
			var key := String(aliases.get(label, ""))
			if not key.is_empty():
				stat[key] = int(hit.get_string(2))

	if (
		stat.has("str")
		and stat.has("dex")
		and stat.has("con")
		and stat.has("int")
		and stat.has("wis")
		and stat.has("cha")
	):
		return

	# Tetra-Cube/Chromium extraction often yields:
	# STR
	# 22 (+6)
	# DEX
	# 26 (+8)
	# ...
	var lines := _clean_lines(text)
	var score_regex := RegEx.new()
	if score_regex.compile("^([0-9]{1,2})\\s*(?:\\([^)]*\\))?") != OK:
		return

	for index: int in range(lines.size() - 1):
		var label := lines[index].strip_edges().to_lower()
		if not aliases.has(label):
			continue
		var score_hit := score_regex.search(lines[index + 1])
		if score_hit == null:
			continue
		stat[String(aliases[label])] = int(score_hit.get_string(1))


static func _is_ability_label(line: String) -> bool:
	var normalized := line.strip_edges().to_lower()
	return normalized in [
		"str", "dex", "con", "int", "wis", "cha",
		"for", "des", "cos", "sag", "car"
	]

static func _parse_sections(
	lines: Array[String],
	stat: Dictionary
) -> void:
	var current_key := ""
	var current_entries: Array = []
	var current_entry: Dictionary = {}
	var implicit_traits_ready := false

	for line: String in lines:
		var lower := line.to_lower()
		var section := _section_key(lower)
		if not section.is_empty():
			_flush_entry(current_entries, current_entry)
			if not current_key.is_empty() and not current_entries.is_empty():
				stat[current_key] = current_entries.duplicate(true)
			current_key = section
			current_entries.clear()
			current_entry = {}
			implicit_traits_ready = false
			continue

		if _is_field_line(lower):
			if (
				lower.begins_with("challenge")
				or lower.begins_with("cr ")
				or lower.begins_with("grado sfida")
				or lower.begins_with("gs ")
				or lower.begins_with("proficiency bonus")
				or lower.begins_with("bonus di competenza")
			):
				implicit_traits_ready = true
			continue

		# Official/third-party PDFs often omit a literal "Traits" heading.
		# After Challenge/Proficiency Bonus, treat named entries before
		# "Actions" as traits.
		if current_key.is_empty():
			if not implicit_traits_ready:
				continue
			current_key = "trait"

		var parsed_entry := _split_entry_line(line)
		if not parsed_entry.is_empty():
			_flush_entry(current_entries, current_entry)
			current_entry = parsed_entry
		elif (
			current_entry.is_empty()
			and line.ends_with(".")
			and line.length() <= 100
			and line.substr(0, 1) == line.substr(0, 1).to_upper()
		):
			# Tetra-Cube can place the first trait name on its own line,
			# followed by the description on the next visual line.
			current_entry = {
				"name": line.trim_suffix(".").strip_edges(),
				"entries": []
			}
		elif current_entry.is_empty():
			current_entry = {"name": "", "entries": [line]}
		else:
			var entry_lines: Array = current_entry.get("entries", [])
			if entry_lines.is_empty():
				entry_lines.append(line)
			else:
				entry_lines[entry_lines.size() - 1] = (
					String(entry_lines.back()) + " " + line
				)
			current_entry["entries"] = entry_lines

	_flush_entry(current_entries, current_entry)
	if not current_key.is_empty() and not current_entries.is_empty():
		stat[current_key] = current_entries


static func _split_entry_line(line: String) -> Dictionary:
	var regex := RegEx.new()
	if regex.compile(
		"^([A-ZÀ-ÖØ-Þ][A-Za-zÀ-ÿ0-9 '’+\\-/(),]{1,70})"
		+ "[.:]\\s+(.+)$"
	) != OK:
		return {}
	var hit := regex.search(line)
	if hit == null:
		return {}
	var title := hit.get_string(1).strip_edges()
	var body := hit.get_string(2).strip_edges()
	if title.count(" ") > 9:
		return {}
	return {"name": title, "entries": [body]}


static func _flush_entry(entries: Array, entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var copy := entry.duplicate(true)
	var entry_lines: Array = copy.get("entries", [])
	var body_parts := PackedStringArray()
	for item: Variant in entry_lines:
		var part := String(item).strip_edges()
		if not part.is_empty():
			body_parts.append(part)
	copy["entries"] = [" ".join(body_parts)]
	entries.append(copy)
	entry.clear()


static func _value_after_label(
	line: String,
	labels: Array[String]
) -> String:
	var matched := _matched_label(line, labels)
	if matched.is_empty():
		return ""
	var value := line.substr(matched.length()).strip_edges()
	while (
		value.begins_with(":")
		or value.begins_with(".")
		or value.begins_with("-")
	):
		value = value.substr(1).strip_edges()
	return value

static func _extract_first_int_after(
	text: String,
	labels: Array[String]
) -> int:
	for label: String in labels:
		var index := text.find(label)
		if index < 0:
			continue
		var tail := text.substr(index + label.length())
		var regex := RegEx.new()
		if regex.compile("[0-9]+") != OK:
			continue
		var hit := regex.search(tail)
		if hit != null:
			return int(hit.get_string())
	return -1


static func _section_key(lower_line: String) -> String:
	var normalized := lower_line.strip_edges().trim_suffix(":")
	return String(SECTION_KEYS.get(normalized, ""))


static func _is_field_line(lower_line: String) -> bool:
	var prefixes := [
		"armor class", "ac ", "classe armatura", "ca ",
		"hit points", "hp ", "punti ferita", "pf ",
		"speed", "velocità", "velocita",
		"saving throws", "tiri salvezza",
		"skills", "abilità", "abilita",
		"damage vulnerabilities", "damage resistances",
		"damage immunities", "condition immunities",
		"vulnerabilità", "vulnerabilita", "resistenze", "immunità", "immunita",
		"senses", "sensi", "languages", "linguaggi",
		"challenge", "cr ", "grado sfida", "gs ",
		"proficiency bonus", "bonus di competenza",
	]
	for prefix: String in prefixes:
		if lower_line.begins_with(prefix):
			if prefix in ["speed", "velocità", "velocita"]:
				var remainder := lower_line.substr(prefix.length()).strip_edges().trim_prefix(":").strip_edges()
				# Named actions such as Speed Clone are entries, not speed fields.
				if not remainder.is_empty() and not remainder.substr(0, 1).is_valid_int():
					continue
			return true
	return false
