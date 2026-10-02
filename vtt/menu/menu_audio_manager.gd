extends Node

const SOUNDTRACK_PATH := "res://assets/menu/audio/menu_theme.mp3"
const SETTINGS_PATH := "user://vtt_menu_settings.cfg"
const SETTINGS_SECTION := "soundtrack"
const DEFAULT_ENABLED := true
const DEFAULT_VOLUME := 0.55
const FADE_DURATION := 0.6

const MENU_SCENE_PATH := "res://vtt/menu/main_menu.tscn"
const ACTIVE_CAMPAIGNS_SCENE_PATH := "res://vtt/menu/active_campaigns.tscn"
const CAMPAIGN_SCENARIOS_SCENE_PATH := "res://vtt/menu/campaign_scenarios.tscn"

var soundtrack_enabled: bool = DEFAULT_ENABLED
var soundtrack_volume: float = DEFAULT_VOLUME

var _player: AudioStreamPlayer
var _fade_tween: Tween
var _audio_available: bool = false


func _ready() -> void:
	_load_settings()

	_player = AudioStreamPlayer.new()
	_player.name = "MenuSoundtrackPlayer"
	_player.bus = &"Master"
	add_child(_player)

	if not ResourceLoader.exists(SOUNDTRACK_PATH):
		push_warning(
			"MenuAudioManager: soundtrack non trovata: " + SOUNDTRACK_PATH
		)
		return

	var stream: AudioStream = ResourceLoader.load(
		SOUNDTRACK_PATH,
		"AudioStreamMP3"
	)
	if stream == null:
		push_warning(
			"MenuAudioManager: impossibile caricare la soundtrack: "
			+ SOUNDTRACK_PATH
		)
		return

	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_player.stream = stream
	_audio_available = true
	_player.finished.connect(_on_player_finished)

	get_tree().scene_changed.connect(_sync_with_scene)
	call_deferred("_sync_with_scene")


func _sync_with_scene() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	var scene_path := scene.scene_file_path
	var should_play := (
		scene_path == MENU_SCENE_PATH
		or scene_path == ACTIVE_CAMPAIGNS_SCENE_PATH
		or scene_path == CAMPAIGN_SCENARIOS_SCENE_PATH
	)

	if should_play:
		_start_if_allowed()
	else:
		_stop_soundtrack()


func _start_if_allowed() -> void:
	if not _audio_available or not soundtrack_enabled:
		_stop_soundtrack()
		return

	if _player.playing:
		if _fade_tween != null and _fade_tween.is_valid():
			_fade_tween.kill()
		_set_volume_immediately(_volume_db())
		return

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

	_player.volume_db = -80.0
	_player.play()
	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_SINE)
	_fade_tween.set_ease(Tween.EASE_IN_OUT)
	_fade_tween.tween_property(
		_player,
		"volume_db",
		_volume_db(),
		FADE_DURATION
	)


func _on_player_finished() -> void:
	# loop=true normally handles MP3 looping. This is a defensive fallback
	# for imported streams/platforms where the loop flag is not honored.
	if _is_menu_scene() and soundtrack_enabled and _audio_available:
		_player.play()


func _is_menu_scene() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var scene_path := scene.scene_file_path
	return (
		scene_path == MENU_SCENE_PATH
		or scene_path == ACTIVE_CAMPAIGNS_SCENE_PATH
		or scene_path == CAMPAIGN_SCENARIOS_SCENE_PATH
	)


func _stop_soundtrack() -> void:
	if _player == null or not _player.playing:
		return

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_SINE)
	_fade_tween.set_ease(Tween.EASE_IN_OUT)
	_fade_tween.tween_property(
		_player,
		"volume_db",
		-80.0,
		FADE_DURATION
	)
	_fade_tween.tween_callback(_player.stop)


func set_soundtrack_enabled(enabled: bool) -> void:
	soundtrack_enabled = enabled
	_save_settings()

	if enabled:
		_sync_with_scene()
	else:
		_stop_soundtrack()


func set_soundtrack_volume(linear_volume: float) -> void:
	soundtrack_volume = clampf(linear_volume, 0.0, 1.0)
	_save_settings()

	if _player != null and _player.playing:
		_set_volume_immediately(_volume_db())


func is_soundtrack_available() -> bool:
	return _audio_available


func get_soundtrack_volume() -> float:
	return soundtrack_volume


func _volume_db() -> float:
	if soundtrack_volume <= 0.001:
		return -80.0
	return linear_to_db(soundtrack_volume)


func _set_volume_immediately(value_db: float) -> void:
	if _player != null:
		_player.volume_db = value_db


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return

	soundtrack_enabled = bool(
		config.get_value(
			SETTINGS_SECTION,
			"enabled",
			DEFAULT_ENABLED
		)
	)
	soundtrack_volume = clampf(
		float(
			config.get_value(
				SETTINGS_SECTION,
				"volume",
				DEFAULT_VOLUME
			)
		),
		0.0,
		1.0
	)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(
		SETTINGS_SECTION,
		"enabled",
		soundtrack_enabled
	)
	config.set_value(
		SETTINGS_SECTION,
		"volume",
		soundtrack_volume
	)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning(
			"MenuAudioManager: impossibile salvare le impostazioni: "
			+ error_string(error)
		)
