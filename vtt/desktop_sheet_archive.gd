extends RefCounted
## Private IPC facade over the existing archive. Revision tokens are scoped to
## this editor session and checked against a fresh native read on every write.
const Owner = preload("res://vtt/creature_owner.gd")
const Portable = preload("res://vtt/portable_creature_content.gd")
const Catalog = preload("res://vtt/content_catalog.gd")
const Documents = preload("res://vtt/document_homebrew.gd")
var archive: RefCounted
var changed: Callable
var _versions: Dictionary = {}
var _settings: Dictionary = {}

func _row(scope: String, type: String, data: Dictionary) -> Dictionary:
	var key := type + ":" + String(data.id)
	var version: Dictionary = _versions.get(key, {"data": {}, "revision": 0})
	if version.data != data:
		version = {"data": data.duplicate(true), "revision": int(version.revision) + 1}
		_versions[key] = version
	return {"scope": scope, "type": type, "id": data.id, "data": data, "revision": version.revision}

func _list(scope: String, type: String) -> Array:
	var result: Array = []
	if scope == "default" and type == "creature":
		for record: Dictionary in archive.list_owned():
			result.append(_row(scope, type, record))
	elif scope == "global" and type == "homebrew":
		var ids: Array = []
		for category: String in Portable.CATEGORIES:
			for definition: Dictionary in Catalog.merge(category, []):
				ids.append(String(definition.get("id", "")))
		for definition: Dictionary in Portable.bundle({"references": ids}):
			result.append(_row(scope, type, definition))
	return result

func dispatch(method: String, args: Dictionary) -> Dictionary:
	if method == "owner": return {"value": Owner.local_id()}
	if method == "setting":
		var key := String(args.get("key", ""))
		if key == "local-creature-owner-id": return {"value": Owner.local_id()}
		if args.has("value"): _settings[key] = args.value
		return {"value": _settings.get(key)}
	var scope := String(args.get("scope", ""))
	var type := String(args.get("type", ""))
	if not ((scope == "default" and type == "creature") or (scope == "global" and type == "homebrew")):
		return {"error": "Archivio non disponibile in questa modalità."}
	var rows := _list(scope, type)
	if method == "list": return {"value": rows}
	var id := String(args.get("id", ""))
	var old: Dictionary = {}
	for row: Dictionary in rows:
		if row.id == id:
			old = row
			break
	if method == "get": return {"value": null if old.is_empty() else old}
	if method not in ["put", "delete"]: return {"error": "Operazione non supportata."}
	var expected: Variant = args.get("expectedRevision")
	if expected == null or int(expected) != int(old.get("revision", 0)):
		return {"error": "La scheda è cambiata nel VTT. Riaprila prima di salvare; nessun dato è stato sovrascritto."}
	if method == "delete":
		if type != "creature": return {"error": "Gestisci le definizioni condivise dagli strumenti nativi."}
		if old.is_empty(): return {"value": false}
		if archive.delete(old.data) != OK: return {"error": "Eliminazione non riuscita."}
		return {"value": true}
	if not args.get("data") is Dictionary: return {"error": "Dati non validi."}
	var data: Dictionary = args.data.duplicate(true)
	if id.is_empty() or String(data.get("id", "")) != id: return {"error": "Identità non valida."}
	if type == "homebrew":
		if not Portable._valid_entry(data): return {"error": "Definizione non valida."}
		if old.is_empty():
			if Portable.install([data]) != OK: return {"error": "Creazione homebrew non riuscita."}
		elif Documents.is_document(data):
			if not Documents.update_definition(data, String(data.name), String(data.data.get("description", ""))):
				return {"error": "Salvataggio documento non riuscito."}
		else:
			return {"error": "Modifica questa definizione condivisa dagli strumenti nativi."}
		for row: Dictionary in _list(scope, type):
			if row.id == id: return {"value": row}
		return {"error": "Definizione salvata ma non riletta: riapri la scheda."}
	if not Owner.is_owner(data) or (not old.is_empty() and not Owner.can_edit(data, old.data)):
		return {"error": "Il controllo della creatura è cambiato."}
	if not old.is_empty() and data.get("kind") != old.data.get("kind"):
		return {"error": "Non è possibile cambiare il tipo della scheda."}
	if archive.save(data) != OK: return {"error": "Salvataggio nell'archivio VTT non riuscito."}
	for saved: Dictionary in archive.list_owned():
		if saved.id == id:
			if changed.is_valid(): changed.call(saved)
			return {"value": _row(scope, type, saved)}
	return {"error": "Scheda non disponibile dopo il salvataggio."}
