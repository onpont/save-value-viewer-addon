@tool
extends EditorPlugin

const ViewerPanel = preload("res://addons/save_value_viewer/panel.gd")

var panel: Control


func _enter_tree() -> void:
	panel = ViewerPanel.new()
	# The editor's main screen area is a VBoxContainer: without the expand flags the panel
	# keeps only its minimum height and leaves the rest of the tab empty.
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.hide()


func _exit_tree() -> void:
	if is_instance_valid(panel):
		panel.queue_free()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if is_instance_valid(panel):
		panel.visible = visible


func _get_plugin_name() -> String:
	return "Value Viewer"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("File", "EditorIcons")
