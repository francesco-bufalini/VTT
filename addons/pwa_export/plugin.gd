@tool
extends EditorPlugin
const WebAssets = preload("res://addons/pwa_export/web_assets.gd")
var _exporter: EditorExportPlugin

func _enter_tree() -> void:
	_exporter = WebAssets.new()
	add_export_plugin(_exporter)

func _exit_tree() -> void:
	remove_export_plugin(_exporter)
	_exporter = null
