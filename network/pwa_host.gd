extends Node
## Loopback-only HTTP bridge. HTTPS termination is provided by Tailscale Serve
## or another trusted reverse proxy. No second application/server is required.
## An explicit random pairing secret protects the session-scoped game endpoints.

const MapDataController = preload("res://vtt/map_data_controller.gd")
const SpellCatalog = preload("res://vtt/spells/spell_catalog.gd")
const ActiveSpells = preload("res://vtt/creature_active_spells.gd")
const BestiaryClient = preload("res://vtt/bestiary_5etools_client.gd")
const ContentCatalog = preload("res://vtt/content_catalog.gd")
const BackupStore = preload("res://network/pwa_backup_store.gd")
const PORT := 8765
const HEADER_LIMIT := 16384
const BODY_LIMIT := 2 * 1024 * 1024
# Peer-to-peer deliveries stay in memory. Durable recovery copies are kept
# separately by BackupStore; neither is exposed through unauthenticated URLs.
const SHARE_CHUNK_BYTES := 128 * 1024
const SHARE_MAX_BYTES := 16 * 1024 * 1024
const SHARE_MAX_QUEUED_BYTES := 32 * 1024 * 1024
const SHARE_PEER_TTL_MS := 25000
const SHARE_TRANSFER_TTL_MS := 15 * 60 * 1000
# A single ES module graph can request over 35 files in parallel; two tabs,
# HTTPS reverse-proxy requests and a Service Worker can overlap. The former
# 32-connection cap exhausted the accept queue and Tailscale Serve returned
# HTTP 502 for module dependencies even though the assets were valid.
# The cap remains finite to bound per-frame work and outgoing buffers.
const MAX_CLIENTS := 96
const TIMEOUT_MS := 15000
const MODULE_DIAG_PATH := "/__vtt_module_diagnostics"
const VERSION_PATH := "/__vtt_version"
const MODULE_DIAG_LIMIT := 160
const TOKEN_PATH := "user://pwa_pairing_token.txt"
const SHORT_CODE_LIFETIME_MS := 300000
const MAX_PAIRING_ATTEMPTS := 8
const QrEncoder = preload("res://vtt/qr/qr_code.gd")
const FILES := {
	"/companion_rules.js": ["res://pwa/companion_rules.js", "text/javascript; charset=utf-8"],
	"/companion_owner_stats.js": ["res://pwa/companion_owner_stats.js", "text/javascript; charset=utf-8"],
	"/creature_variants.js": ["res://pwa/creature_variants.js", "text/javascript; charset=utf-8"],
	"/creature_variants_view.js": ["res://pwa/creature_variants_view.js", "text/javascript; charset=utf-8"],
	"/catalog/companion_spells.json": ["res://pwa/catalog/companion_spells.json", "application/json; charset=utf-8"],
  "/catalog/generic_item_variants.json": ["res://pwa/catalog/generic_item_variants.json", "application/json; charset=utf-8"],
	"/": ["res://pwa/index.html", "text/html; charset=utf-8"],
	"/index.html": ["res://pwa/index.html", "text/html; charset=utf-8"],
	"/client.js": ["res://pwa/client.js", "text/javascript; charset=utf-8"],
	"/share_transfer.js": ["res://pwa/share_transfer.js", "text/javascript; charset=utf-8"],
	"/inventory_transfer.js": ["res://pwa/inventory_transfer.js", "text/javascript; charset=utf-8"],
	"/main.js": ["res://pwa/main.js", "text/javascript; charset=utf-8"],
	"/native_sheet.js": ["res://pwa/native_sheet.js", "text/javascript; charset=utf-8"],
	"/defense_summary.js": ["res://pwa/defense_summary.js", "text/javascript; charset=utf-8"],
	"/identity_aliases.js": ["res://pwa/identity_aliases.js", "text/javascript; charset=utf-8"],
	"/d20_rerolls.js": ["res://pwa/d20_rerolls.js", "text/javascript; charset=utf-8"],
	"/source_edition.js": ["res://pwa/source_edition.js", "text/javascript; charset=utf-8"],
  "/item_controls.js": ["res://pwa/item_controls.js", "text/javascript; charset=utf-8"],
  "/item_applied_options.js": ["res://pwa/item_applied_options.js", "text/javascript; charset=utf-8"],
  "/inventory_search.js": ["res://pwa/inventory_search.js", "text/javascript; charset=utf-8"],
  "/item_detail_facts.js": ["res://pwa/item_detail_facts.js", "text/javascript; charset=utf-8"],
  "/documents.js": ["res://pwa/documents.js", "text/javascript; charset=utf-8"],
  "/spell_selection.js": ["res://pwa/spell_selection.js", "text/javascript; charset=utf-8"],
  "/activated_abilities.js": ["res://pwa/activated_abilities.js", "text/javascript; charset=utf-8"],
	"/sheet_rules.js": ["res://pwa/sheet_rules.js", "text/javascript; charset=utf-8"],
	"/scaling_dice.js": ["res://pwa/scaling_dice.js", "text/javascript; charset=utf-8"],
	"/skill_definitions.js": ["res://pwa/skill_definitions.js", "text/javascript; charset=utf-8"],
	"/offhand_rules.js": ["res://pwa/offhand_rules.js", "text/javascript; charset=utf-8"],
	"/species_defenses.js": ["res://pwa/species_defenses.js", "text/javascript; charset=utf-8"],
	"/class_defenses.js": ["res://pwa/class_defenses.js", "text/javascript; charset=utf-8"],
"/catalog/class_defense_rules.js": ["res://pwa/catalog/class_defense_rules.js", "text/javascript; charset=utf-8"],
"/catalog/class_numeric_feature_grants.js": ["res://pwa/catalog/class_numeric_feature_grants.js", "text/javascript; charset=utf-8"],
"/catalog/feature_feat_grants.js": ["res://pwa/catalog/feature_feat_grants.js", "text/javascript; charset=utf-8"],
"/species_variant_families.js": ["res://pwa/species_variant_families.js", "text/javascript; charset=utf-8"],
"/catalog/barbarian_2014_rules.js": ["res://pwa/catalog/barbarian_2014_rules.js", "text/javascript; charset=utf-8"],
"/catalog/supplemental_rules.js": ["res://pwa/catalog/supplemental_rules.js", "text/javascript; charset=utf-8"],
	"/armor_rules.js": ["res://pwa/armor_rules.js", "text/javascript; charset=utf-8"],
	"/armor_class_formula.js": ["res://pwa/armor_class_formula.js", "text/javascript; charset=utf-8"],
	"/feature_item_grants.js": ["res://pwa/feature_item_grants.js", "text/javascript; charset=utf-8"],
	"/spell_storing_item.js": ["res://pwa/spell_storing_item.js", "text/javascript; charset=utf-8"],
	"/spell_imprints.js": ["res://pwa/spell_imprints.js", "text/javascript; charset=utf-8"],
	"/spell_item_effects.js": ["res://pwa/spell_item_effects.js", "text/javascript; charset=utf-8"],
	"/attack_hit_effects.js": ["res://pwa/attack_hit_effects.js", "text/javascript; charset=utf-8"],
	"/catalog/feature_item_grants.json": ["res://pwa/catalog/feature_item_grants.json", "application/json; charset=utf-8"],
	"/sense_rules.js": ["res://pwa/sense_rules.js", "text/javascript; charset=utf-8"],
	"/species_trait_text.js": ["res://pwa/species_trait_text.js", "text/javascript; charset=utf-8"],
	"/species_powers.js": ["res://pwa/species_powers.js", "text/javascript; charset=utf-8"],
	"/feature_rolls.js": ["res://pwa/feature_rolls.js", "text/javascript; charset=utf-8"],
	"/zero_hp_responses.js": ["res://pwa/zero_hp_responses.js", "text/javascript; charset=utf-8"],
	"/barbarian_2014.js": ["res://pwa/barbarian_2014.js", "text/javascript; charset=utf-8"],
	"/dragonborn_ftd.js": ["res://pwa/dragonborn_ftd.js", "text/javascript; charset=utf-8"],
	"/ability_areas.js": ["res://pwa/ability_areas.js", "text/javascript; charset=utf-8"],
	"/species_benefit_catalogs.js": ["res://pwa/species_benefit_catalogs.js", "text/javascript; charset=utf-8"],
	"/species_roll_modes.js": ["res://pwa/species_roll_modes.js", "text/javascript; charset=utf-8"],
	"/species_origin_rules.js": ["res://pwa/species_origin_rules.js", "text/javascript; charset=utf-8"],
	"/species_conditional_bonuses.js": ["res://pwa/species_conditional_bonuses.js", "text/javascript; charset=utf-8"],
	"/ability_choice_rules.js": ["res://pwa/ability_choice_rules.js", "text/javascript; charset=utf-8"],
	"/feat_picker.js": ["res://pwa/feat_picker.js", "text/javascript; charset=utf-8"],
	"/concentration_rules.js": ["res://pwa/concentration_rules.js", "text/javascript; charset=utf-8"],
	"/rule_supplements.js": ["res://pwa/rule_supplements.js", "text/javascript; charset=utf-8"],
	"/character_core.js": ["res://pwa/character_core.js", "text/javascript; charset=utf-8"],
	"/level_up.js": ["res://pwa/level_up.js", "text/javascript; charset=utf-8"],
	"/character_portrait.js": ["res://pwa/character_portrait.js", "text/javascript; charset=utf-8"],
	"/quick_homebrew.js": ["res://pwa/quick_homebrew.js", "text/javascript; charset=utf-8"],
	"/character_homebrew.js": ["res://pwa/character_homebrew.js", "text/javascript; charset=utf-8"],
	"/catalog/class_resource_overrides.json": ["res://vtt/data/class_resource_overrides.json", "application/json; charset=utf-8"],
	"/structured_effects.js": ["res://pwa/structured_effects.js", "text/javascript; charset=utf-8"],
	"/attack_count_benefits.js": ["res://pwa/attack_count_benefits.js", "text/javascript; charset=utf-8"],
	"/pending_choices.js": ["res://pwa/pending_choices.js", "text/javascript; charset=utf-8"],
	"/sheet_rules_view.js": ["res://pwa/sheet_rules_view.js", "text/javascript; charset=utf-8"],
	"/sheet_roll_origin.js": ["res://pwa/sheet_roll_origin.js", "text/javascript; charset=utf-8"],
	"/ui.js": ["res://pwa/ui.js", "text/javascript; charset=utf-8"],
	"/5etools_inline.js": ["res://pwa/5etools_inline.js", "text/javascript; charset=utf-8"],
	"/ui_primitives.js": ["res://pwa/ui_primitives.js", "text/javascript; charset=utf-8"],
	"/distance_units.js": ["res://pwa/distance_units.js", "text/javascript; charset=utf-8"],
	"/attack_range.js": ["res://pwa/attack_range.js", "text/javascript; charset=utf-8"],
	"/trait_benefits.js": ["res://pwa/trait_benefits.js", "text/javascript; charset=utf-8"],
	"/trait_benefit_distribution.js": ["res://pwa/trait_benefit_distribution.js", "text/javascript; charset=utf-8"],
	"/trait_benefit_editor.js": ["res://pwa/trait_benefit_editor.js", "text/javascript; charset=utf-8"],
	"/effect_extensions.js": ["res://pwa/effect_extensions.js", "text/javascript; charset=utf-8"],
	"/monster_traits.js": ["res://pwa/monster_traits.js", "text/javascript; charset=utf-8"],
	"/trait_projection.js": ["res://pwa/trait_projection.js", "text/javascript; charset=utf-8"],
	"/spell_metadata.js": ["res://pwa/spell_metadata.js", "text/javascript; charset=utf-8"],
	"/condition_catalog.js": ["res://pwa/condition_catalog.js", "text/javascript; charset=utf-8"],
	"/exhaustion_rules.js": ["res://pwa/exhaustion_rules.js", "text/javascript; charset=utf-8"],
	"/catalog/effects_5etools.json": ["res://vtt/data/effects_5etools.json", "application/json; charset=utf-8"],
	"/chat_notifications.js": ["res://pwa/chat_notifications.js", "text/javascript; charset=utf-8"],
	"/feature_mechanics.js": ["res://pwa/feature_mechanics.js", "text/javascript; charset=utf-8"],
	"/trait_state_rules.js": ["res://pwa/trait_state_rules.js", "text/javascript; charset=utf-8"],
	"/power_selection.js": ["res://pwa/power_selection.js", "text/javascript; charset=utf-8"],
	"/optional_feature_progression.js": ["res://pwa/optional_feature_progression.js", "text/javascript; charset=utf-8"],
	"/action_economy.js": ["res://pwa/action_economy.js", "text/javascript; charset=utf-8"],
	"/demo.js": ["res://pwa/demo.js", "text/javascript; charset=utf-8"],
	"/tactical_view.js": ["res://pwa/tactical_view.js", "text/javascript; charset=utf-8"],
	"/session_map.js": ["res://pwa/session_map.js", "text/javascript; charset=utf-8"],
	"/catalog_data.js": ["res://pwa/catalog_data.js", "text/javascript; charset=utf-8"],
	"/catalog/action_feature_overrides.json": ["res://vtt/data/action_feature_overrides.json", "application/json; charset=utf-8"],
	"/catalog/benefits/action.json": ["res://vtt/enrichment/benefits/action.json", "application/json; charset=utf-8"],
	"/catalog/benefits/activation.json": ["res://vtt/enrichment/benefits/activation.json", "application/json; charset=utf-8"],
	"/catalog/benefits/resource_recovery.json": ["res://vtt/enrichment/benefits/resource_recovery.json", "application/json; charset=utf-8"],
	"/catalog/benefits/attack_count.json": ["res://vtt/enrichment/benefits/attack_count.json", "application/json; charset=utf-8"],
	"/catalog/benefits/action_sequence.json": ["res://vtt/enrichment/benefits/action_sequence.json", "application/json; charset=utf-8"],
	"/catalog/benefits/resource.json": ["res://vtt/enrichment/benefits/resource.json", "application/json; charset=utf-8"],
	"/class_benefit_progression.js": ["res://pwa/class_benefit_progression.js", "text/javascript; charset=utf-8"],
	"/catalog/benefits/roll_bonus.json": ["res://vtt/enrichment/benefits/roll_bonus.json", "application/json; charset=utf-8"],
	"/class_benefit_catalogs.js": ["res://pwa/class_benefit_catalogs.js", "text/javascript; charset=utf-8"],
	"/catalog/combat_actions_5etools.json": ["res://vtt/data/combat_actions_5etools.json", "application/json; charset=utf-8"],
	"/icons/action_controls.svg": ["res://vtt/icons/action_controls.svg", "image/svg+xml"],
	"/catalog/combat_action_supplements_5etools.json": ["res://vtt/data/combat_action_supplements_5etools.json", "application/json; charset=utf-8"],
	"/catalog/feature_timing_recovery_rules.json": ["res://vtt/data/feature_timing_recovery_rules.json", "application/json; charset=utf-8"],
	"/catalog/classes.json": ["res://pwa/catalog/classes.json", "application/json; charset=utf-8"],
	"/catalog/ability_grants.json": ["res://pwa/catalog/ability_grants.json", "application/json; charset=utf-8"],
	"/catalog/activated_abilities.json": ["res://vtt/data/activated_abilities_5etools.json", "application/json; charset=utf-8"],
	"/catalog/class_mechanics.json": ["res://pwa/catalog/class_mechanics.json", "application/json; charset=utf-8"],
	"/catalog/trait_states.json": ["res://pwa/catalog/trait_states.json", "application/json; charset=utf-8"],
	"/catalog/power_selections.json": ["res://pwa/catalog/power_selections.json", "application/json; charset=utf-8"],
	"/catalog/spellcasting_benefits.json": ["res://pwa/catalog/spellcasting_benefits.json", "application/json; charset=utf-8"],
	"/catalog/optional_feature_progressions.json": ["res://pwa/catalog/optional_feature_progressions.json", "application/json; charset=utf-8"],
	"/catalog/feature_slot_spells.json": ["res://pwa/catalog/feature_slot_spells.json", "application/json; charset=utf-8"],
	"/catalog/roll_bonus_rules.json": ["res://pwa/catalog/roll_bonus_rules.json", "application/json; charset=utf-8"],
	"/catalog/scaling_dice.json": ["res://pwa/catalog/scaling_dice.json", "application/json; charset=utf-8"],
	"/catalog/effect_extensions.json": ["res://pwa/catalog/effect_extensions.json", "application/json; charset=utf-8"],
	"/catalog/species_types.json": ["res://pwa/catalog/species_types.json", "application/json; charset=utf-8"],
	"/benefits/attack.json": ["res://vtt/enrichment/benefits/attack.json", "application/json; charset=utf-8"],
	"/benefits/movement.json": ["res://vtt/enrichment/benefits/movement.json", "application/json; charset=utf-8"],
	"/catalog/species_defenses.json": ["res://pwa/catalog/species_defenses.json", "application/json; charset=utf-8"],
	"/catalog/species_powers.json": ["res://pwa/catalog/species_powers.json", "application/json; charset=utf-8"],
	"/catalog/spell_grant_rules.json": ["res://pwa/catalog/spell_grant_rules.json", "application/json; charset=utf-8"],
	"/catalog/sense_grants.json": ["res://pwa/catalog/sense_grants.json", "application/json; charset=utf-8"],
	"/benefits/roll_mode.json": ["res://vtt/enrichment/benefits/roll_mode.json", "application/json; charset=utf-8"],
	"/benefits/roll_bonus.json": ["res://vtt/enrichment/benefits/roll_bonus.json", "application/json; charset=utf-8"],
	"/benefits/resource.json": ["res://vtt/enrichment/benefits/resource.json", "application/json; charset=utf-8"],
	"/catalog/proficiency_grants.json": ["res://pwa/catalog/proficiency_grants.json", "application/json; charset=utf-8"],
	"/catalog/player.json": ["res://vtt/data/player_5etools_catalog.json", "application/json; charset=utf-8"],
	"/catalog/backgrounds.json": ["res://vtt/data/compendium_backgrounds_5etools.json", "application/json; charset=utf-8"],
	"/catalog/features.json": ["res://vtt/data/compendium_features_5etools.json", "application/json; charset=utf-8"],
	"/catalog/items.json": ["res://vtt/data/compendium_items_5etools.json", "application/json; charset=utf-8"],
	"/miniature-images/ore.webp": ["res://pwa/miniature-images/ore.webp", "image/webp"],
	"/miniature-images/gilliam.webp": ["res://pwa/miniature-images/gilliam.webp", "image/webp"],
	"/miniature-images/kaos.webp": ["res://pwa/miniature-images/kaos.webp", "image/webp"],
	"/miniature-images/kryss.webp": ["res://pwa/miniature-images/kryss.webp", "image/webp"],
	"/miniature-images/phenax.webp": ["res://pwa/miniature-images/phenax.webp", "image/webp"],
	"/miniature-images/sariel.webp": ["res://pwa/miniature-images/sariel.webp", "image/webp"],
	"/miniature-images/valandir.webp": ["res://pwa/miniature-images/valandir.webp", "image/webp"],
	"/miniature-images/wilfred.webp": ["res://pwa/miniature-images/wilfred.webp", "image/webp"],
	"/miniature-images/wyrda.webp": ["res://pwa/miniature-images/wyrda.webp", "image/webp"],
	"/miniature-images/nazaryl.webp": ["res://pwa/miniature-images/nazaryl.webp", "image/webp"],
	"/miniature-images/tiabald.webp": ["res://pwa/miniature-images/tiabald.webp", "image/webp"],
	"/miniature-images/harmakis.webp": ["res://pwa/miniature-images/harmakis.webp", "image/webp"],
	"/catalog/miniatures.json": ["res://vtt/data/token_catalog_offline.json", "application/json; charset=utf-8"],
	"/mobile_metal_theme.css": ["res://pwa/mobile_metal_theme.css", "text/css; charset=utf-8"],
	"/styles.css": ["res://pwa/styles.css", "text/css; charset=utf-8"],
	"/server_backup_core.js": ["res://pwa/server_backup_core.js", "text/javascript; charset=utf-8"],
	"/server_backup_worker.js": ["res://pwa/server_backup_worker.js", "text/javascript; charset=utf-8"],
	"/server_backups.js": ["res://pwa/server_backups.js", "text/javascript; charset=utf-8"],
	"/storage.js": ["res://pwa/storage.js", "text/javascript; charset=utf-8"],
	"/creatures.js": ["res://pwa/creatures.js", "text/javascript; charset=utf-8"],
	"/creature_format.js": ["res://pwa/creature_format.js", "text/javascript; charset=utf-8"],
	"/sw.js": ["res://pwa/sw.js", "text/javascript; charset=utf-8"],
	"/version_gate.js": ["res://pwa/version_gate.js", "text/javascript; charset=utf-8"],
	"/manifest.webmanifest": ["res://pwa/manifest.webmanifest", "application/manifest+json"],
	"/icon.svg": ["res://pwa/icon.svg", "image/svg+xml"],
	"/icons/action_dashboard_gloss.svg": ["res://pwa/icons/action_dashboard_gloss.svg", "image/svg+xml"],
	"/icons/action_extras.svg": ["res://pwa/icons/action_extras.svg", "image/svg+xml"],
	"/icons/gold_generated/gold_0.svg": ["res://pwa/icons/gold_generated/gold_0.svg", "image/svg+xml"],
	"/icons/gold_generated/gold_1.svg": ["res://pwa/icons/gold_generated/gold_1.svg", "image/svg+xml"],
	"/icons/gold_generated/gold_2.svg": ["res://pwa/icons/gold_generated/gold_2.svg", "image/svg+xml"],
	"/icons/gold_generated/gold_3.svg": ["res://pwa/icons/gold_generated/gold_3.svg", "image/svg+xml"],
	"/icons/info/identity.svg": ["res://assets/creature_info/identity.svg", "image/svg+xml"],
	"/icons/info/physique.svg": ["res://assets/creature_info/physique.svg", "image/svg+xml"],
	"/icons/info/progression.svg": ["res://assets/creature_info/progression.svg", "image/svg+xml"],
	"/icons/info/talents.svg": ["res://assets/creature_info/talents.svg", "image/svg+xml"],
	"/icons/info/biography.svg": ["res://assets/creature_info/biography.svg", "image/svg+xml"],
	"/icon-192.png": ["res://pwa/icon-192.png", "image/png"],
	"/icon-512.png": ["res://pwa/icon-512.png", "image/png"],
	"/icon-1024.png": ["res://pwa/icon-1024.png", "image/png"]
}

# Keep fixtures independent from a running desktop session.
var _listen_port: int = PORT
var _server := TCPServer.new()
var _clients: Array[Dictionary] = []
# Bounded, session-only HTTP telemetry. No IPs, pairing tokens, API contents,
# player data, query strings or request headers are retained.
var _module_diag_events: Array[Dictionary] = []
var _module_diag_total := 0
var _pwa_revision: String = ""
var _module_diag_peak := 0
var _module_diag_next_id := 0
var _token := ""
var _short_code := ""
var _short_code_expiry := 0
var _short_code_attempts := 0
var _public_spells_payload := PackedByteArray()
var _public_spell_entries: Array[Dictionary] = []
var _share_session_key := ""
var _share_peers: Dictionary = {}
var _share_deliveries: Dictionary = {}
var _share_queued_bytes := 0
var _backup_store = BackupStore.new()
var _backup_jobs := 0

# PWA HTTP runs only while the native 3D board is open. A permanently
# installed autoload tracks the scene, but does not keep a listening socket
# outside the board. Godot F5/F6 launches include autoloads too.
func _ready() -> void:
	set_process(false)
	if OS.has_feature("web"):
		return
	_token = _pairing_token()
	if _token.is_empty():
		push_error("PWA: impossibile creare la credenziale di associazione")
		return
	get_tree().scene_changed.connect(_on_scene_changed)
	call_deferred("_refresh_scene_server")


func _is_board_scene(scene: Node) -> bool:
	if scene == null or not is_instance_valid(scene):
		return false
	if scene.scene_file_path == "res://dnd_base.tscn":
		return true
	# Campaigns such as Scontro contro Kaos inherit from the tactical
	# board script but have their own .tscn path. Accept all legitimate
	# board-script descendants, not just the original scene filename.
	var board_script: Script = scene.get_script() as Script
	while board_script != null:
		if board_script.resource_path == "res://dnd_base.gd":
			return true
		board_script = board_script.get_base_script()
	return false


func _on_scene_changed(_scene: Node) -> void:
	_refresh_scene_server()


func _refresh_scene_server() -> void:
	if _is_board_scene(get_tree().current_scene):
		_start_listener()
	else:
		_stop_listener()


func _on_board_exiting() -> void:
	# Called on tree_exiting even if the board is freed without a scene change.
	_stop_listener()


func _start_listener() -> Error:
	if _server.is_listening():
		return OK
	if _token.is_empty():
		return ERR_UNAUTHORIZED
	var err := _server.listen(_listen_port, "127.0.0.1")
	if err != OK:
		push_warning("PWA: localhost:%d non disponibile: %s" % [_listen_port, error_string(err)])
		return err
	_pwa_revision = _read_pwa_revision()
	set_process(true)
	var board := get_tree().current_scene
	if _is_board_scene(board) and not board.tree_exiting.is_connected(_on_board_exiting):
		board.tree_exiting.connect(_on_board_exiting)
	return OK


func _stop_listener() -> void:
	_short_code = ""
	_short_code_expiry = 0
	_short_code_attempts = 0
	set_process(false)
	_server.stop()
	for item: Dictionary in _clients:
		var peer: StreamPeerTCP = item.get("peer") as StreamPeerTCP
		if peer != null:
			peer.disconnect_from_host()
	_clients.clear()
	_share_peers.clear()
	_share_deliveries.clear()
	_share_queued_bytes = 0
	_share_session_key = ""


# Fingerprint what this server actually serves, including uncommitted changes,
# rather than git HEAD (which can stay unchanged across local PWA edits).
# Hash in small chunks to avoid loading large catalogs into memory at startup.
func _read_pwa_revision() -> String:
	var digest := HashingContext.new()
	if digest.start(HashingContext.HASH_SHA256) != OK:
		return ""
	var paths: Array = FILES.keys()
	paths.sort()
	for path in paths:
		var route := String(path)
		digest.update(route.to_utf8_buffer())
		digest.update(PackedByteArray([0]))
		var asset: Array = FILES[route]
		var file := FileAccess.open(String(asset[0]), FileAccess.READ)
		if file == null:
			digest.update(PackedByteArray([0]))
			continue
		while not file.eof_reached():
			var chunk := file.get_buffer(65536)
			if chunk.is_empty():
				break
			digest.update(chunk)
	return digest.finish().hex_encode()


func _pairing_token() -> String:
	if FileAccess.file_exists(TOKEN_PATH):
		var existing := FileAccess.get_file_as_string(TOKEN_PATH).strip_edges()
		if existing.length() == 64 and existing.is_valid_hex_number():
			return existing
		return ""
	var secret := Crypto.new().generate_random_bytes(32).hex_encode()
	var file := FileAccess.open(TOKEN_PATH, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(secret + "\n")
	file.close()
	return secret



# New phones exchange a short-lived 16-character desktop code for the
# existing strong 256-bit bearer. The old bearer stays compatible with
# previously installed clients. Never transmit it in a QR or URL.
func _new_short_code() -> String:
	_short_code = Crypto.new().generate_random_bytes(8).hex_encode().to_upper()
	_short_code_expiry = Time.get_ticks_msec() + SHORT_CODE_LIFETIME_MS
	_short_code_attempts = 0
	return _short_code


func _consume_short_code(value: String) -> bool:
	if _short_code.is_empty() or Time.get_ticks_msec() > _short_code_expiry:
		_short_code = ""
		return false
	_short_code_attempts += 1
	if _short_code_attempts > MAX_PAIRING_ATTEMPTS:
		_short_code = ""
		return false
	if value == _short_code:
		_short_code = ""
		_short_code_expiry = 0
		return true
	return false


func _tailscale_url() -> String:
	var result: Dictionary = await preload("res://network/tailscale_serve.gd")._command(PackedStringArray(["status", "--json"]))
	if result.ok:
		var data: Variant = JSON.parse_string(String(result.message))
		if not data is Dictionary:
			return ""
		var me: Variant = (data as Dictionary).get("Self", {})
		if not me is Dictionary:
			return ""
		var domain := String((me as Dictionary).get("DNSName", "")).trim_suffix(".")
		if domain.ends_with(".ts.net") and not domain.contains("/") and not domain.contains(":"):
			return "https://" + domain
	return ""


func _pair_url(origin: String, code: String) -> String:
	var normalized := origin.strip_edges().trim_suffix("/")
	if normalized.begins_with("https://") and not normalized.contains("#") and not normalized.contains("?"):
		return normalized + "/#pair=" + code
	if normalized.begins_with("http://127.0.0.1:") and not normalized.contains("#") and not normalized.contains("?"):
		return normalized + "/#pair=" + code
	return ""


# Ctrl+Shift+P is intentionally handled only on the desktop game viewport.
func _input(event: InputEvent) -> void:
	if not _server.is_listening() or _token.is_empty() or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or not key.ctrl_pressed or not key.shift_pressed or key.keycode != KEY_P:
		return
	get_viewport().set_input_as_handled()
	_show_pairing_dialog()


func _show_pairing_dialog() -> void:
	for node: Node in get_tree().root.get_children():
		if node.name == "VttPwaPairing" and node is AcceptDialog:
			node.queue_free()
	var code := _new_short_code()
	var dialog := AcceptDialog.new()
	dialog.name = "VttPwaPairing"
	dialog.title = "Collega VTT Mobile"
	dialog.min_size = Vector2i(480, 560)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	dialog.add_child(layout)
	var intro := Label.new()
	intro.text = "Inquadra il QR con la fotocamera oppure inserisci il codice in Partita.\nValido 5 minuti, per un solo dispositivo."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(intro)
	var code_label := Label.new()
	code_label.text = "Codice: %s-%s-%s-%s" % [code.substr(0, 4), code.substr(4, 4), code.substr(8, 4), code.substr(12, 4)]
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_label.add_theme_font_size_override("font_size", 24)
	layout.add_child(code_label)
	var address_label := Label.new()
	address_label.text = "Indirizzo HTTPS Tailscale (modificabile):"
	layout.add_child(address_label)
	var url_edit := LineEdit.new()
	url_edit.placeholder_text = "https://nome-pc.nome-tailnet.ts.net"
	layout.add_child(url_edit)
	var qr := TextureRect.new()
	qr.custom_minimum_size = Vector2(240, 240)
	qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layout.add_child(qr)
	var feedback := Label.new()
	feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(feedback)
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_child(controls)
	var copy_code := Button.new()
	copy_code.text = "Copia codice"
	controls.add_child(copy_code)
	copy_code.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(code)
	)
	var copy_url := Button.new()
	copy_url.text = "Copia link"
	var backup_folder := Button.new()
	backup_folder.text = "Apri copie PWA"
	controls.add_child(backup_folder)
	backup_folder.pressed.connect(func() -> void:
		var folder := ProjectSettings.globalize_path(BackupStore.ROOT)
		DirAccess.make_dir_recursive_absolute(folder)
		OS.shell_open(folder)
	)
	controls.add_child(copy_url)
	var update_qr := func() -> void:
		var link := _pair_url(url_edit.text, code)
		if link.is_empty():
			qr.texture = null
			copy_url.disabled = true
			feedback.text = "Inserisci l'URL HTTPS di Tailscale Serve per generare il QR.\nIl codice manuale funziona comunque."
			return
		var generator: Node = QrEncoder.new()
		generator.set("error_correct_level", 1)
		qr.texture = generator.call("get_texture", link)
		generator.free()
		feedback.text = "Scansiona per aprire VTT e associare il telefono."
		copy_url.disabled = false

	copy_url.pressed.connect(func() -> void:
		var link := _pair_url(url_edit.text, code)
		if not link.is_empty():
			DisplayServer.clipboard_set(link)
	)
	url_edit.text_submitted.connect(func(_value: String) -> void: update_qr.call())
	url_edit.focus_exited.connect(func() -> void: update_qr.call())
	update_qr.call()
	get_tree().root.add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	dialog.popup_centered()
	var detected_url := await _tailscale_url()
	if is_instance_valid(url_edit) and url_edit.text.is_empty():
		url_edit.text = detected_url
		update_qr.call()


func public_spells_json() -> PackedByteArray:
	# Public built-in references only; private desktop homebrew stays local.
	if _public_spells_payload.is_empty():
		var spells: Array[Dictionary] = []
		for entry: Dictionary in SpellCatalog.all_spells():
			var spell_id: String = String(entry.get("id", ""))
			if spell_id.is_empty() or spell_id.begins_with("homebrew:") or String(entry.get("origin", "")) == "homebrew":
				continue
			spells.append({
				"id": spell_id, "name": String(entry.get("name", "")),
				"source": String(entry.get("source", "")),
				"level": int(entry.get("level", 0)),
				"school": String(entry.get("school", "")),
				"classes": entry.get("classes", []),
				"range": String(entry.get("range", "")),
				"casting_time": String(entry.get("casting_time", "")),
				"components": entry.get("components", ""),
				"target": entry.get("target", ""),
				"ritual": bool(entry.get("ritual", false)),
				"duration": entry.get("duration", ""),
				"has_duration": ActiveSpells.has_duration(entry),
				"requires_concentration": ActiveSpells.requires_concentration(entry),
				"description": String(entry.get("description", ""))
			})
		_public_spell_entries = spells
		_public_spells_payload = JSON.stringify({"version": 1, "spells": spells}).to_utf8_buffer()
	return _public_spells_payload


func _board_sync() -> Node:
	var scene := get_tree().current_scene
	if not _is_board_scene(scene):
		return null
	var value: Variant = scene.get("board_sync")
	if value is Node and is_instance_valid(value):
		return value as Node
	return null


func _web_board_controller(board: Node) -> MapDataController:
	# This HTTPS bridge is independent of the legacy LAN/Tailscale TCP/UDP
	# receivers. Their ports may fail to bind even while the actual Godot board
	# and its local tactical action provider are fully available.
	if board == null or not is_instance_valid(board):
		return null
	var value: Variant = board.get("map_data_controller")
	if value is MapDataController and is_instance_valid(value):
		var controller := value as MapDataController
		if controller.source_name() == "board":
			return controller
	return null


func _process(_delta: float) -> void:
	# Stop accepting at capacity, letting TCP queue new requests. Previously
	# requests above the cap were accepted and disconnected immediately, which
	# surfaced in Chromium as "Failed to fetch dynamically imported module".
	while _server.is_connection_available() and _clients.size() < MAX_CLIENTS:
		var peer := _server.take_connection()
		_module_diag_next_id += 1
		_clients.append({"peer": peer, "buffer": PackedByteArray(),
			"out": PackedByteArray(), "sent": 0, "processing": false,
			"connection_id": _module_diag_next_id,
			"deadline": Time.get_ticks_msec() + TIMEOUT_MS})
		_module_diag_peak = maxi(_module_diag_peak, _clients.size())
	for i in range(_clients.size() - 1, -1, -1):
		var client: Dictionary = _clients[i]
		var peer: StreamPeerTCP = client.peer
		peer.poll()
		if Time.get_ticks_msec() > int(client.deadline):
			_drop(i, "timeout")
			continue
		if peer.get_status() in [StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE]:
			_drop(i, "peer_disconnected")
			continue
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		if not client.out.is_empty():
			var sent := int(client.sent)
			if sent >= (client.out as PackedByteArray).size():
				_drop(i, "bytes_sent")
				continue
			var partial := peer.put_partial_data(client.out.slice(sent, mini(sent + 65536, client.out.size())))
			if partial[0] != OK:
				_drop(i, "send_error")
			else:
				client.sent = sent + int(partial[1])
			continue
		if bool(client.processing):
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var received := peer.get_data(mini(available, 65536))
			if received[0] != OK:
				_drop(i, "receive_error")
				continue
			var incoming: PackedByteArray = client.buffer
			incoming.append_array(received[1])
			client.buffer = incoming
		if (client.buffer as PackedByteArray).size() > BODY_LIMIT + HEADER_LIMIT:
			_answer(client, 413, {"error": "request_too_large"})
			continue
		_inspect_request(client)


func _inspect_request(client: Dictionary) -> void:
	var bytes: PackedByteArray = client.buffer
	var header_end := bytes.get_string_from_utf8().find("\r\n\r\n")
	if header_end < 0:
		if bytes.size() >= HEADER_LIMIT:
			_answer(client, 431, {"error": "headers_too_large"})
		return
	if header_end > HEADER_LIMIT:
		_answer(client, 431, {"error": "headers_too_large"})
		return
	var lines := bytes.slice(0, header_end).get_string_from_utf8().split("\r\n")
	var request := lines[0].split(" ")
	if request.size() != 3 or request[2] != "HTTP/1.1":
		_answer(client, 400, {"error": "bad_request"})
		return
	var headers := {}
	for i in range(1, lines.size()):
		var row: String = lines[i]
		var pos := row.find(":")
		if pos <= 0:
			_answer(client, 400, {"error": "bad_headers"})
			return
		var key := row.substr(0, pos).to_lower()
		if headers.has(key):
			_answer(client, 400, {"error": "duplicate_header"})
			return
		headers[key] = row.substr(pos + 1).strip_edges()
	if headers.has("transfer-encoding"):
		_answer(client, 400, {"error": "unsupported_transfer_encoding"})
		return
	var raw_length := String(headers.get("content-length", "0"))
	if not raw_length.is_valid_int():
		_answer(client, 400, {"error": "bad_content_length"})
		return
	var content_length := int(raw_length)
	if content_length < 0 or content_length > BODY_LIMIT:
		_answer(client, 413, {"error": "request_too_large"})
		return
	if bytes.size() < header_end + 4 + content_length:
		return
	client.processing = true
	_handle_http.call_deferred(client, request[0], request[1].get_slice("?", 0), headers,
		bytes.slice(header_end + 4, header_end + 4 + content_length))


# Expose the server computer's human-readable device name, never its machine ID.
# Windows supplies COMPUTERNAME; Unix often supplies HOSTNAME. If the game was
# launched without that environment (common on macOS), resolve it once via
# the system hostname utility instead of spawning a process on every poll.
var _pwa_device_name: String = ""

func _server_device_name() -> String:
	if _pwa_device_name != "":
		return _pwa_device_name
	var name: String = OS.get_environment("COMPUTERNAME").strip_edges()
	if name == "":
		name = OS.get_environment("HOSTNAME").strip_edges()
	if name == "":
		var hostname_output: Array = []
		if OS.execute("hostname", PackedStringArray(), hostname_output) == 0 and not hostname_output.is_empty():
			name = String(hostname_output[0]).strip_edges()
	_pwa_device_name = name.replace("\n", " ").replace("\r", " ").substr(0, 80)
	if _pwa_device_name == "":
		_pwa_device_name = "Server"
	return _pwa_device_name

func _handle_http(client: Dictionary, method: String, path: String,
		headers: Dictionary, body: PackedByteArray) -> void:
	if method == "GET" and path == VERSION_PATH:
		_answer(client, 200, {"revision": _pwa_revision, "commit": _pwa_revision})
		return
	if method == "GET" and path == MODULE_DIAG_PATH:
		# Anonymous read-only snapshot of JS transfer health, not session data.
		_answer(client, 200, {
			"version": 1, "connections_active": _clients.size(),
			"connections_peak": _module_diag_peak,
			"connections_limit": MAX_CLIENTS,
			"module_requests_recorded": _module_diag_total,
			"module_events": _module_diag_events.duplicate(true)
		})
		return
	if method == "GET" and (path == "/catalog/bestiary.json" or path.begins_with("/catalog/bestiary/")):
		_serve_bestiary(client, path)
		return
	if method == "GET" and FILES.has(path):
		if path.ends_with(".js"):
			client["module_path"] = path
			client["module_started_ms"] = Time.get_ticks_msec()
		var asset: Array = FILES[path]
		if not FileAccess.file_exists(asset[0]):
			_answer(client, 500, {"error": "missing_pwa_asset"})
			return
		var payload := FileAccess.get_file_as_bytes(asset[0])
		if path == "/sw.js":
			# Make the worker bytes (and its atomic offline cache) change
			# whenever the actual files served by this host change.
			var revision := _pwa_revision if not _pwa_revision.is_empty() else "unversioned"
			payload = payload.get_string_from_utf8().replace(
				"__VTT_COMMIT_SHA__", revision).to_utf8_buffer()
		_respond(client, 200, String(asset[1]), payload)
		return
	# This payload is also used to package the standalone offline prototype.
	if path == "/catalog/spells.json" and method == "GET":
		_respond(client, 200, "application/json; charset=utf-8", public_spells_json())
		return
	# Serve only the spell definitions a character actually needs. The full
	# compendium is still exposed separately for discovery and offline prefetch.
	if path == "/catalog/spells/selected" and method == "POST":
		if body.size() > 32768:
			_answer(client, 413, {"error": "too_many_spell_references"})
			return
		var selection: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not selection is Dictionary:
			_answer(client, 400, {"error": "invalid_spell_selection"})
			return
		var requested: Variant = selection.get("ids", [])
		var classes: Variant = selection.get("classes", [])
		if not requested is Array or not classes is Array or requested.size() > 250 or classes.size() > 16:
			_answer(client, 400, {"error": "invalid_spell_selection"})
			return
		var requested_ids: Dictionary = {}
		for spell_id: Variant in requested:
			if not spell_id is String or (spell_id as String).length() > 180:
				_answer(client, 400, {"error": "invalid_spell_id"})
				return
			requested_ids[spell_id] = true
		var filters: Array[Dictionary] = []
		for candidate: Variant in classes:
			if not candidate is Dictionary:
				_answer(client, 400, {"error": "invalid_class_selection"})
				return
			var target_class_name: String = String(candidate.get("name", "")).strip_edges().to_lower()
			var max_level: int = int(candidate.get("max_level", -1))
			if target_class_name.is_empty() or target_class_name.length() > 100 or max_level < 0 or max_level > 9:
				_answer(client, 400, {"error": "invalid_class_selection"})
				return
			filters.append({"name": target_class_name, "max_level": max_level})
		# Initialization and serialization are cached on the desktop, not the phone.
		public_spells_json()
		var selected: Array[Dictionary] = []
		for spell: Dictionary in _public_spell_entries:
			var include_spell: bool = requested_ids.has(spell.get("id", ""))
			if not include_spell:
				for filter: Dictionary in filters:
					if int(spell.get("level", 0)) > int(filter["max_level"]):
						continue
					for spell_class_name: Variant in spell.get("classes", []):
						if String(spell_class_name).to_lower() == String(filter["name"]):
							include_spell = true
							break
					if include_spell:
						break
			if include_spell:
				selected.append(spell)
		_answer(client, 200, {"version": 1, "spells": selected})
		return
	# One-time pairing endpoint. No authentication is needed for this narrow
	# exchange; wrong guesses are limited globally per displayed code.
	if path == "/api/pair":
		if method != "POST":
			_answer(client, 405, {"error": "method_not_allowed"})
			return
		if body.size() > 128 or String(headers.get("content-type", "")).split(";")[0].strip_edges() != "application/json":
			_answer(client, 415, {"error": "expected_small_json"})
			return
		var envelope: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not envelope is Dictionary:
			_answer(client, 400, {"error": "invalid_pair_code"})
			return
		var code: String = String((envelope as Dictionary).get("code", "")).replace("-", "").replace(" ", "").to_upper()
		if code.length() != 16 or not code.is_valid_hex_number() or not _consume_short_code(code):
			_answer(client, 401, {"error": "invalid_or_expired_pair_code"})
			return
		_answer(client, 200, {"token": _token})
		return
	if path == "/api/status" and method == "GET":
		var board := _board_sync()
		_answer(client, 200, {"protocol": 1,
			"desktop_online": _web_board_controller(board) != null,
			"device_name": _server_device_name(),
			"pairing_required": true})
		return
	if path.begins_with("/api/backup/"):
		if method != "POST":
			_answer(client, 405, {"error": "method_not_allowed"})
		elif String(headers.get("authorization", "")) != "Bearer " + _token:
			_answer(client, 401, {"error": "pairing_required"})
		elif String(headers.get("content-type", "")).split(";")[0].strip_edges() != "application/json":
			_answer(client, 415, {"error": "expected_json"})
		elif _backup_jobs >= 4 or body.size() > 100000:
			_answer(client, 429, {"error": "backup_busy_or_chunk_too_large"})
		else:
			# Disk I/O, hashing and archive serialization never run on the game thread.
			_backup_jobs += 1
			var store: RefCounted = _backup_store
			WorkerThreadPool.add_task(func() -> void:
				var result: Dictionary = store.handle(path.trim_prefix("/api/backup/"), body)
				_finish_backup.call_deferred(client, result)
			)
		return
	if path not in ["/api/session", "/api/map", "/api/action", "/api/conditions"] and not path.begins_with("/api/share/"):
		_answer(client, 404, {"error": "not_found"})
		return
	if ((path == "/api/action" or path.begins_with("/api/share/")) and method != "POST") or (
		path != "/api/action" and not path.begins_with("/api/share/") and method != "GET"
	):
		_answer(client, 405, {"error": "method_not_allowed"})
		return
	if String(headers.get("authorization", "")) != "Bearer " + _token:
		_answer(client, 401, {"error": "pairing_required"})
		return
	var board := _board_sync()
	var controller := _web_board_controller(board)
	if controller == null:
		_answer(client, 503, {"error": "no_active_desktop_session"})
		return
	if path.begins_with("/api/share/"):
		var game_key := String(board.get("session_key"))
		if _share_session_key != game_key:
			_share_session_key = game_key
			_share_peers.clear()
			_share_deliveries.clear()
			_share_queued_bytes = 0
		_handle_share(client, path, body)
		return
	if path == "/api/session":
		_answer(client, 200, {"protocol": 1, "session": board.get("session_key"),
			"mobile_protocol": 3, "device_name": _server_device_name()})
	elif path == "/api/conditions":
		_answer(client, 200, _condition_public_catalog())
	elif path == "/api/map":
		_answer(client, 200, controller.get_map_data())
	else:
		if String(headers.get("content-type", "")).split(";")[0].strip_edges() != "application/json":
			_answer(client, 415, {"error": "expected_json"})
			return
		var request: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not request is Dictionary or not request.get("action") is String or not request.get("payload") is Dictionary:
			_answer(client, 400, {"error": "invalid_action_envelope"})
			return
		var result: Dictionary = await controller.execute_web_action(
			String(request.action), request.payload)
		_answer(client, 200, result)


func _finish_backup(client: Dictionary, result: Dictionary) -> void:
	_backup_jobs = maxi(0, _backup_jobs - 1)
	if _clients.has(client):
		_answer(client, int(result.get("status", 500)), result.get("data", {"error": "backup_failed"}))


# Paired devices share through the existing session HTTP bridge. The
# sender uploads bounded chunks and the recipient explicitly imports or
# rejects a complete delivery. Only the intended device can pull its chunks.
func _share_valid_id(value: Variant) -> bool:
	return value is String and (value as String).length() == 32 and (value as String).is_valid_hex_number()


func _share_forget(transfer_id: String) -> void:
	if not _share_deliveries.has(transfer_id):
		return
	_share_queued_bytes = maxi(0, _share_queued_bytes - int(_share_deliveries[transfer_id].get("received_bytes", 0)))
	_share_deliveries.erase(transfer_id)


func _share_expire() -> void:
	var now := Time.get_ticks_msec()
	for peer_id: Variant in _share_peers.keys():
		if now - int(_share_peers[peer_id].get("seen", 0)) > SHARE_PEER_TTL_MS:
			_share_peers.erase(peer_id)
	for delivery_id: Variant in _share_deliveries.keys():
		if now - int(_share_deliveries[delivery_id].get("created", 0)) > SHARE_TRANSFER_TTL_MS:
			_share_forget(String(delivery_id))


func _handle_share(client: Dictionary, path: String, body: PackedByteArray) -> void:
	if body.is_empty() or String(body.get_string_from_utf8()).length() > BODY_LIMIT:
		_answer(client, 413, {"error": "invalid_share_body"})
		return
	var value: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not value is Dictionary:
		_answer(client, 400, {"error": "invalid_share_json"})
		return
	var request: Dictionary = value
	var device_id: Variant = request.get("device_id", null)
	if not _share_valid_id(device_id) :
		_answer(client, 400, {"error": "invalid_device_id"})
		return
	var device_token: Variant = request.get("device_token", null)
	if not device_token is String or (device_token as String).length() != 64 or not (device_token as String).is_valid_hex_number():
		_answer(client, 400, {"error": "invalid_device_credential"})
		return
	_share_expire()
	var now := Time.get_ticks_msec()
	if path == "/api/share/peers":
		var nickname: String = String(request.get("device_name", "")).strip_edges()
		if nickname.is_empty() or nickname.length() > 60:
			_answer(client, 400, {"error": "invalid_device_name"})
			return
		if _share_peers.has(device_id) and _share_peers[device_id].token != device_token:
			_answer(client, 401, {"error": "device_credential_mismatch"})
			return
		_share_peers[device_id] = {"name": nickname, "token": device_token, "seen": now}
		var others: Array[Dictionary] = []
		for peer_id: Variant in _share_peers.keys():
			if peer_id != device_id:
				others.append({"id": peer_id, "name": _share_peers[peer_id].name})
		var inbox: Array[Dictionary] = []
		for transfer_id: Variant in _share_deliveries.keys():
			var entry: Dictionary = _share_deliveries[transfer_id]
			if entry.recipient == device_id and entry.received_parts == entry.parts:
				inbox.append({"id": transfer_id, "kind": entry.kind, "title": entry.title,
					"size": entry.size, "parts": entry.parts, "sender_name": entry.sender_name})
		_answer(client, 200, {"devices": others, "inbox": inbox})
		return
	if not _share_peers.has(device_id) or _share_peers[device_id].token != device_token:
		_answer(client, 401, {"error": "device_not_registered_or_unauthorized"})
		return
	if path == "/api/share/chunk":
		var recipient: Variant = request.get("recipient_id", null)
		var transfer_id: Variant = request.get("transfer_id", null)
		var kind: Variant = request.get("kind", null)
		var title: Variant = request.get("title", null)
		var index := int(request.get("index", -1))
		var count := int(request.get("parts", 0))
		var byte_size := int(request.get("size", 0))
		var encoded: Variant = request.get("data", null)
		if not _share_valid_id(recipient) or recipient == device_id or not _share_valid_id(transfer_id) or \
			kind not in ["creature", "homebrew", "inventory"] or not title is String or (title as String).length() > 160 or \
			count < 1 or count > 128 or byte_size < 1 or byte_size > SHARE_MAX_BYTES or \
			count != int(ceil(float(byte_size) / SHARE_CHUNK_BYTES)) or index < 0 or index >= count or \
			not encoded is String or (encoded as String).length() > 180000:
			_answer(client, 400, {"error": "invalid_transfer_chunk"})
			return
		var decoded: PackedByteArray = Marshalls.base64_to_raw(encoded)
		var expected := mini(SHARE_CHUNK_BYTES, byte_size - index * SHARE_CHUNK_BYTES)
		if decoded.size() != expected or Marshalls.raw_to_base64(decoded) != encoded:
			_answer(client, 400, {"error": "invalid_chunk_encoding"})
			return
		if not _share_deliveries.has(transfer_id):
			if index != 0 or (not _share_peers.has(recipient)) or _share_deliveries.size() >= 24:
				_answer(client, 400, {"error": "recipient_offline_or_queue_full"})
				return
			var chunks: Array = []
			chunks.resize(count)
			_share_deliveries[transfer_id] = {
				"sender": device_id, "sender_name": _share_peers[device_id].name,
				"recipient": recipient, "kind": kind, "title": title,
				"size": byte_size, "parts": count, "received_parts": 0,
				"received_bytes": 0, "created": now, "chunks": chunks
			}
		var entry: Dictionary = _share_deliveries[transfer_id]
		if entry.sender != device_id or entry.recipient != recipient or entry.kind != kind or \
			entry.title != title or entry.parts != count or entry.size != byte_size:
			_answer(client, 400, {"error": "transfer_id_collision"})
			return
		var chunks: Array = entry.chunks
		if chunks[index] != null:
			if chunks[index] != encoded:
				_answer(client, 400, {"error": "chunk_conflict"})
				return
		else:
			if _share_queued_bytes + decoded.size() > SHARE_MAX_QUEUED_BYTES:
				_answer(client, 413, {"error": "share_queue_full"})
				return
			chunks[index] = encoded
			entry.chunks = chunks
			entry.received_parts = int(entry.received_parts) + 1
			entry.received_bytes = int(entry.received_bytes) + decoded.size()
			_share_queued_bytes += decoded.size()
			_share_deliveries[transfer_id] = entry
		_answer(client, 200, {"ok": true, "uploaded": entry.received_parts, "parts": count})
		return
	if path == "/api/share/pull":
		var transfer_id: Variant = request.get("transfer_id", null)
		var index := int(request.get("index", -1))
		if not _share_valid_id(transfer_id) or not _share_deliveries.has(transfer_id):
			_answer(client, 404, {"error": "transfer_not_found"})
			return
		var entry: Dictionary = _share_deliveries[transfer_id]
		if entry.recipient != device_id or entry.received_parts != entry.parts or index < 0 or index >= int(entry.parts):
			_answer(client, 400, {"error": "transfer_not_available"})
			return
		_answer(client, 200, {"data": entry.chunks[index], "index": index})
		return
	if path == "/api/share/ack":
		var transfer_id: Variant = request.get("transfer_id", null)
		if not _share_valid_id(transfer_id) or not _share_deliveries.has(transfer_id):
			_answer(client, 404, {"error": "transfer_not_found"})
			return
		if _share_deliveries[transfer_id].recipient != device_id:
			_answer(client, 400, {"error": "not_recipient"})
			return
		_share_forget(transfer_id)
		_answer(client, 200, {"ok": true})
		return
	_answer(client, 404, {"error": "unknown_share_route"})


# This HTTP endpoint relays offers between PWA browsers only.
# The Godot board has no creature/inventory library of its own.
func _condition_public_catalog() -> Dictionary:
	var editions: Dictionary = {}
	for edition: String in ["2014", "2024"]:
		var rows: Array[Dictionary] = []
		for definition: Dictionary in ContentCatalog.condition_definitions(edition):
			rows.append({
				"id": String(definition.get("id", "")),
				"name": String(definition.get("name", "")),
				"category": String(definition.get("category", "conditions")),
				"source": String(definition.get("source", definition.get("origin", "VTT"))),
				"page": definition.get("page", null),
				"entries": definition.get("entries", definition.get("description", []))
			})
		editions[edition] = rows
	return {"editions": editions}

func _answer(client: Dictionary, status: int, value: Dictionary) -> void:
	_respond(client, status, "application/json; charset=utf-8",
		JSON.stringify(value).to_utf8_buffer())


func _respond(client: Dictionary, status: int, mime: String,
		payload: PackedByteArray) -> void:
	if not _clients.has(client):
		return
	var reasons := {200: "OK", 400: "Bad Request", 401: "Unauthorized",
		404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large",
		415: "Unsupported Media Type", 431: "Request Header Fields Too Large",
		500: "Internal Server Error", 503: "Service Unavailable"}
	var head := "HTTP/1.1 %d %s\r\n" % [status, reasons.get(status, "Error")]
	head += "Content-Type: %s\r\nContent-Length: %d\r\n" % [mime, payload.size()]
	head += "Connection: close\r\nCache-Control: no-store\r\n"
	head += "X-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\n"
	head += "Content-Security-Policy: default-src 'self'; script-src 'self'; connect-src 'self'; img-src 'self' blob: data:; frame-src https://2014.5e.tools; object-src 'none'; base-uri 'none'; frame-ancestors 'none'\r\n\r\n"
	var response := head.to_utf8_buffer()
	response.append_array(payload)
	client.out = response
	client.sent = 0
	if client.has("module_path"):
		client["module_header_bytes"] = head.to_utf8_buffer().size()
		client["module_payload_bytes"] = payload.size()
		client["module_http_status"] = status


func _drop(index: int, reason: String = "closed") -> void:
	var client: Dictionary = _clients[index]
	if client.has("module_path"):
		var body_expected := int(client.get("module_payload_bytes", 0))
		var head_bytes := int(client.get("module_header_bytes", 0))
		var body_queued := maxi(0, int(client.get("sent", 0)) - head_bytes)
		var body_sent := mini(body_expected, body_queued)
		# A peer may close immediately after the whole response was queued.
		# The TCP status can switch to NONE before the following _process tick:
		# that is not proof of a truncated JavaScript response. Conversely a
		# partial write must always remain visible as an incomplete transfer.
		var complete := body_sent == body_expected and reason in ["bytes_sent", "peer_disconnected"]
		var outcome := "socket_written" if reason == "bytes_sent" else (
			"socket_written_peer_closed" if complete else reason)
		var record: Dictionary = {
			"id": int(client.get("connection_id", 0)),
			"path": String(client.module_path),
			"status": int(client.get("module_http_status", 0)),
			"bytes_written": body_sent,
			"bytes_expected": body_expected,
			"duration_ms": Time.get_ticks_msec() - int(client.module_started_ms),
			"outcome": outcome
		}
		_module_diag_total += 1
		_module_diag_events.append(record)
		if _module_diag_events.size() > MODULE_DIAG_LIMIT:
			_module_diag_events.pop_front()
		if not complete:
			push_warning("PWA JS transfer incomplete: %s %d/%d bytes (%s)" % [
				String(client.module_path), body_sent, body_expected, reason])
	(client.peer as StreamPeerTCP).disconnect_from_host()
	_clients.remove_at(index)


func _exit_tree() -> void:
	_stop_listener()


# Public catalog only: the existing bestiary client owns fetching, cache, homebrew
# and _copy resolution. No local creature archive is exposed over HTTP.
func _serve_bestiary(client: Dictionary, path: String) -> void:
	client["deadline"] = Time.get_ticks_msec() + 90000
	var bestiary := BestiaryClient.new()
	add_child(bestiary)
	var fail := func(_key: String, message: String) -> void:
		_answer(client, 503, {"error": message})
		bestiary.queue_free()
	bestiary.creature_failed.connect(fail, CONNECT_ONE_SHOT)
	if path == "/catalog/bestiary.json":
		bestiary.catalog_ready.connect(func(entries: Array[Dictionary]) -> void:
			_answer(client, 200, {"version": 1, "monsters": entries})
			bestiary.queue_free()
		, CONNECT_ONE_SHOT)
		bestiary.catalog_failed.connect(func(message: String) -> void: fail.call("", message), CONNECT_ONE_SHOT)
		bestiary.load_catalog()
		return
	var parts := path.trim_prefix("/catalog/bestiary/").trim_suffix(".json").split("/")
	if parts.size() != 2 or parts[0].length() > 512 or parts[1].length() > 128:
		_answer(client, 400, {"error": "invalid_bestiary_reference"})
		bestiary.queue_free()
		return
	bestiary.creature_ready.connect(func(_key: String, stat: Dictionary) -> void:
		_answer(client, 200, stat)
		bestiary.queue_free()
	, CONNECT_ONE_SHOT)
	bestiary.request_creature(parts[0].uri_decode(), parts[1].uri_decode(), "pwa-variant")
