extends Node

const CAMPAIGNS_DIR := "user://campaigns"
const CAMPAIGN_METADATA_FILE := "campaign.json"
const CAMPAIGN_STATE_FILE := "state.json"
const BUILTIN_STATES_DIR := "user://campaigns/_builtin_states"

const MAIN_MENU_SCENE := "res://vtt/menu/main_menu.tscn"
const ACTIVE_CAMPAIGNS_SCENE := "res://vtt/menu/active_campaigns.tscn"
const CAMPAIGN_SCENARIOS_SCENE := "res://vtt/menu/campaign_scenarios.tscn"
const CAMPAIGN_EDITOR_SCENE := "res://vtt/editor/campaign_editor.tscn"

const BUILTIN_CAMPAIGN_GROUPS := [
	{
		"id": "i_figli_dell_apocalisse",
		"name": "I Figli dell'Apocalisse",
		"description": "La campagna che raccoglie gli scenari attualmente disponibili.",
		"builtin": true
	}
]

const BUILTIN_CAMPAIGNS := [
	{
		"id": "encounter",
		"name": "Encounter",
		"description": "Scenario encounter esistente",
		"scene": "res://encounter/kaos_klothis.tscn",
		"preview": "",
		"builtin": true
	},
	{
		"id": "scontro_contro_kaos",
		"name": "Scontro Contro Kaos",
		"description": "Encounter dalla fase 2, con Kaos gia' sulla sfera",
		"scene": "res://encounter/scontro_contro_kaos.tscn",
		"preview": "",
		"builtin": true
	},
	{
		"id": "dnd_base",
		"name": "D&D Base",
		"description": "Scena VTT di base",
		"scene": "res://dnd_base.tscn",
		"preview": "",
		"builtin": true
	}
]

# Astrolabe non e' presente come scena dedicata nel branch corrente. Questi
# percorsi vengono registrati automaticamente se una futura versione la aggiunge.
const OPTIONAL_BUILTIN_CAMPAIGNS := [
	{
		"id": "astrolabe_puzzle",
		"name": "Astrolabe Puzzle",
		"description": "Puzzle dell'astrolabio",
		"scene": "res://astrolabe_puzzle.tscn",
		"preview": "",
		"builtin": true
	},
	{
		"id": "astrolabe_puzzle",
		"name": "Astrolabe Puzzle",
		"description": "Puzzle dell'astrolabio",
		"scene": "res://astrolabe/astrolabe_puzzle.tscn",
		"preview": "",
		"builtin": true
	},
	{
		"id": "astrolabe_puzzle",
		"name": "Astrolabe Puzzle",
		"description": "Puzzle dell'astrolabio",
		"scene": "res://puzzle/astrolabe_puzzle.tscn",
		"preview": "",
		"builtin": true
	}
]

var selected_campaign_group_id: String = ""
var selected_campaign_group: Dictionary = {}
var active_campaign_id: String = ""
var active_campaign: Dictionary = {}


func _ready() -> void:
	_ensure_campaigns_directory()


func list_campaign_groups() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in BUILTIN_CAMPAIGN_GROUPS:
		var item: Dictionary = entry.duplicate(true)
		item["scenario_count"] = list_campaign_scenarios(
			String(item.get("id", ""))
		).size()
		result.append(item)
	return result


func get_campaign_group(campaign_group_id: String) -> Dictionary:
	for campaign_group: Dictionary in list_campaign_groups():
		if String(campaign_group.get("id", "")) == campaign_group_id:
			return campaign_group
	return {}


func select_campaign_group(campaign_group_id: String) -> Error:
	var data: Dictionary = get_campaign_group(campaign_group_id)
	if data.is_empty():
		return ERR_DOES_NOT_EXIST
	selected_campaign_group_id = campaign_group_id
	selected_campaign_group = data.duplicate(true)
	return OK


func open_campaign_group(campaign_group_id: String) -> Error:
	var error: Error = select_campaign_group(campaign_group_id)
	if error != OK:
		return error
	return get_tree().change_scene_to_file(CAMPAIGN_SCENARIOS_SCENE)


func get_selected_campaign_group() -> Dictionary:
	return selected_campaign_group.duplicate(true)


func get_selected_campaign_group_name() -> String:
	return String(
		selected_campaign_group.get("name", "Campagna")
	)


func list_campaign_scenarios(
	campaign_group_id: String
) -> Array[Dictionary]:
	# The first campaign groups the entries that the previous UI exposed
	# directly as "campagne attive". This intentionally includes user-created
	# entries such as "Test incantesimi", preserving their existing state.
	if campaign_group_id == "i_figli_dell_apocalisse":
		return list_campaigns()
	return []


func open_scenario(
	campaign_group_id: String,
	scenario_id: String
) -> Error:
	var campaign_group: Dictionary = get_campaign_group(campaign_group_id)
	if campaign_group.is_empty():
		return ERR_DOES_NOT_EXIST

	var scenario_exists := false
	for scenario: Dictionary in list_campaign_scenarios(campaign_group_id):
		if String(scenario.get("id", "")) == scenario_id:
			scenario_exists = true
			break
	if not scenario_exists:
		return ERR_DOES_NOT_EXIST

	var select_error: Error = select_campaign_group(campaign_group_id)
	if select_error != OK:
		return select_error
	return open_campaign(scenario_id)


func list_campaigns() -> Array[Dictionary]:
	var campaigns: Array[Dictionary] = []

	for entry: Dictionary in BUILTIN_CAMPAIGNS:
		if ResourceLoader.exists(String(entry.get("scene", ""))):
			campaigns.append(entry.duplicate(true))

	var optional_ids := {}
	for entry: Dictionary in OPTIONAL_BUILTIN_CAMPAIGNS:
		var scene_path: String = String(entry.get("scene", ""))
		var campaign_id: String = String(entry.get("id", ""))
		if not optional_ids.has(campaign_id) and ResourceLoader.exists(scene_path):
			campaigns.append(entry.duplicate(true))
			optional_ids[campaign_id] = true

	var user_campaigns := _list_user_campaigns()
	user_campaigns.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("name", "")).naturalnocasecmp_to(
				String(b.get("name", ""))
			) < 0
	)
	campaigns.append_array(user_campaigns)
	return campaigns


func create_campaign(display_name: String = "") -> String:
	_ensure_campaigns_directory()

	var campaign_id := "campaign_%s_%s" % [
		str(int(Time.get_unix_time_from_system())),
		str(Time.get_ticks_usec())
	]
	var name := display_name.strip_edges()
	if name.is_empty():
		name = "Nuova campagna %d" % (_list_user_campaigns().size() + 1)

	var metadata := {
		"id": campaign_id,
		"name": name,
		"description": "Campagna personalizzata",
		"scene": CAMPAIGN_EDITOR_SCENE,
		"preview": "",
		"builtin": false,
		"created_at": Time.get_datetime_string_from_system(),
		"last_saved": ""
	}

	var directory := _campaign_directory(campaign_id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if _write_json(directory.path_join(CAMPAIGN_METADATA_FILE), metadata) != OK:
		return ""

	return campaign_id


func rename_campaign(campaign_id: String, new_name: String) -> Error:
	var cleaned_name: String = new_name.strip_edges()
	if cleaned_name.is_empty():
		return ERR_INVALID_PARAMETER

	var campaign: Dictionary = get_campaign(campaign_id)
	if campaign.is_empty():
		return ERR_DOES_NOT_EXIST
	if bool(campaign.get("builtin", false)):
		return ERR_UNAVAILABLE

	campaign["name"] = cleaned_name
	var metadata_path: String = (
		_campaign_directory(campaign_id)
		.path_join(CAMPAIGN_METADATA_FILE)
	)
	var error: Error = _write_json(metadata_path, campaign)
	if error == OK and active_campaign_id == campaign_id:
		active_campaign = campaign.duplicate(true)
	return error


func delete_campaign(campaign_id: String) -> Error:
	var campaign: Dictionary = get_campaign(campaign_id)
	if campaign.is_empty():
		return ERR_DOES_NOT_EXIST
	if bool(campaign.get("builtin", false)):
		return ERR_UNAVAILABLE

	var directory_path: String = _campaign_directory(campaign_id)
	var absolute_path: String = ProjectSettings.globalize_path(directory_path)
	var error: Error = _remove_directory_recursive(absolute_path)
	if error == OK and active_campaign_id == campaign_id:
		active_campaign_id = ""
		active_campaign = {}
	return error


func _remove_directory_recursive(absolute_path: String) -> Error:
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return ERR_DOES_NOT_EXIST

	directory.list_dir_begin()
	var entry_name: String = directory.get_next()
	while not entry_name.is_empty():
		if entry_name != "." and entry_name != "..":
			var child_path: String = absolute_path.path_join(entry_name)
			var child_error: Error = OK
			if directory.current_is_dir():
				child_error = _remove_directory_recursive(child_path)
			else:
				child_error = DirAccess.remove_absolute(child_path)
			if child_error != OK:
				directory.list_dir_end()
				return child_error
		entry_name = directory.get_next()
	directory.list_dir_end()
	return DirAccess.remove_absolute(absolute_path)


func open_campaign(campaign_id: String) -> Error:
	var data := get_campaign(campaign_id)
	if data.is_empty():
		return ERR_DOES_NOT_EXIST

	var scene_path: String = String(data.get("scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return ERR_FILE_NOT_FOUND

	active_campaign_id = campaign_id
	active_campaign = data.duplicate(true)
	return get_tree().change_scene_to_file(scene_path)


func get_campaign(campaign_id: String) -> Dictionary:
	for campaign: Dictionary in list_campaigns():
		if String(campaign.get("id", "")) == campaign_id:
			return campaign
	return {}


func activate_campaign_for_scene(scene_path: String) -> void:
	if (
		not active_campaign.is_empty()
		and String(active_campaign.get("scene", "")) == scene_path
	):
		return

	for campaign: Dictionary in list_campaigns():
		if String(campaign.get("scene", "")) == scene_path:
			active_campaign_id = String(campaign.get("id", ""))
			active_campaign = campaign.duplicate(true)
			return


func save_active_runtime_state(state: Dictionary) -> Error:
	if active_campaign_id.is_empty() or active_campaign.is_empty():
		return ERR_UNAVAILABLE

	if not bool(active_campaign.get("builtin", false)):
		return save_active_state(state)

	var directory: String = BUILTIN_STATES_DIR.path_join(active_campaign_id)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(directory)
	)
	return _write_json(directory.path_join(CAMPAIGN_STATE_FILE), state)


func load_active_runtime_state() -> Dictionary:
	if active_campaign_id.is_empty() or active_campaign.is_empty():
		return {}

	if not bool(active_campaign.get("builtin", false)):
		return load_active_state()

	var state_path: String = (
		BUILTIN_STATES_DIR
		.path_join(active_campaign_id)
		.path_join(CAMPAIGN_STATE_FILE)
	)
	var value: Variant = _read_json(state_path)
	if value is Dictionary:
		return value as Dictionary
	return {}


func get_active_campaign_name() -> String:
	return String(active_campaign.get("name", "Campagna"))


func is_active_user_campaign() -> bool:
	return (
		not active_campaign_id.is_empty()
		and not active_campaign.is_empty()
		and not bool(active_campaign.get("builtin", false))
	)


func save_active_state(state: Dictionary) -> Error:
	if not is_active_user_campaign():
		return ERR_UNAVAILABLE

	var directory := _campaign_directory(active_campaign_id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))

	var save_error := _write_json(
		directory.path_join(CAMPAIGN_STATE_FILE),
		state
	)
	if save_error != OK:
		return save_error

	active_campaign["last_saved"] = Time.get_datetime_string_from_system()
	var metadata_error := _write_json(
		directory.path_join(CAMPAIGN_METADATA_FILE),
		active_campaign
	)
	return metadata_error


func load_active_state() -> Dictionary:
	if not is_active_user_campaign():
		return {}

	var data: Variant = _read_json(
		_campaign_directory(active_campaign_id).path_join(CAMPAIGN_STATE_FILE)
	)
	if data is Dictionary:
		return data as Dictionary
	return {}


func return_to_main_menu() -> Error:
	selected_campaign_group_id = ""
	selected_campaign_group = {}
	active_campaign_id = ""
	active_campaign = {}
	return get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _list_user_campaigns() -> Array[Dictionary]:
	_ensure_campaigns_directory()
	var result: Array[Dictionary] = []
	var directory := DirAccess.open(CAMPAIGNS_DIR)
	if directory == null:
		return result

	directory.list_dir_begin()
	var entry_name := directory.get_next()
	while not entry_name.is_empty():
		if directory.current_is_dir():
			var metadata_path := (
				CAMPAIGNS_DIR
				.path_join(entry_name)
				.path_join(CAMPAIGN_METADATA_FILE)
			)
			var data: Variant = _read_json(metadata_path)
			if data is Dictionary:
				var metadata := data as Dictionary
				if (
					not String(metadata.get("id", "")).is_empty()
					and ResourceLoader.exists(
						String(metadata.get("scene", CAMPAIGN_EDITOR_SCENE))
					)
				):
					result.append(metadata)
		entry_name = directory.get_next()
	directory.list_dir_end()
	return result


func _campaign_directory(campaign_id: String) -> String:
	return CAMPAIGNS_DIR.path_join(campaign_id)


func _ensure_campaigns_directory() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(CAMPAIGNS_DIR)
	)


func _write_json(path: String, data: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_string(JSON.stringify(data, "  "))
	var error := file.get_error()
	file.close()
	return error


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null

	var text := file.get_as_text()
	file.close()
	return JSON.parse_string(text)
