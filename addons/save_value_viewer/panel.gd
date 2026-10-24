@tool
extends MarginContainer
## Read-only panel: open, search, inspect and copy values. No write path exists.

const Document = preload("res://addons/save_value_viewer/document.gd")
const NO_SELECTION := ""
const EDITOR_URL := "https://onpont.itch.io/save-value-editor"
const USER_EXTENSIONS := ["cfg", "ini", "json"]
const LAST_PATH_SECTION := "save_value_viewer"
const LAST_PATH_KEY := "last_file"

var document = Document.new()
var selected_id := NO_SELECTION
var filling := false

var path_label: Label
var status: Label
var status_box: Control
var summary: Label
var body: VBoxContainer
var purpose_label: Label
var footer: HFlowContainer
var list_box: VBoxContainer
var detail: VBoxContainer
var split: SplitContainer
var split_vertical := false
var filter: LineEdit
var filter_timer: Timer
var tree: Tree
var selection_label: Label
var value_text: TextEdit
var value_hint: Label
var copy_value_button: Button
var copy_key_button: Button
var show_button: Button
var reload_button: Button
var picker: FileDialog


func _ready() -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for edge in ["left", "top", "right", "bottom"]:
		add_theme_constant_override("margin_" + edge, 16)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	add_child(body)
	var title := Label.new()
	title.text = "Save Value Viewer"
	title.add_theme_font_size_override("font_size", 22)
	body.add_child(title)
	purpose_label = Label.new()
	purpose_label.text = "Read any value in a Godot ConfigFile or JSON save file. This panel never writes to the file."
	purpose_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(purpose_label)
	# A flow container so the six buttons wrap instead of forcing the dock to ~690 px.
	var toolbar := HFlowContainer.new()
	toolbar.add_theme_constant_override("h_separation", 6)
	toolbar.add_theme_constant_override("v_separation", 6)
	body.add_child(toolbar)
	_button(toolbar, "Open file…", _choose_file)
	_button(toolbar, "Project user://…", _choose_user_folder)
	reload_button = _button(toolbar, "Reload", _reload)
	show_button = _button(toolbar, "Show in folder", _show_in_folder)
	copy_key_button = _button(toolbar, "Copy key", _copy_key)
	copy_value_button = _button(toolbar, "Copy value", _copy_value)
	path_label = Label.new()
	path_label.text = "No file open — choose a UTF-8 .cfg, .ini or .json file."
	path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	path_label.custom_minimum_size.y = 26
	body.add_child(path_label)
	filter = LineEdit.new()
	filter.placeholder_text = "Filter by section, key, type or value…"
	filter.clear_button_enabled = true
	filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter.text_changed.connect(_on_filter_text_changed)
	filter.text_submitted.connect(func(_text: String): _flush_filter())
	body.add_child(filter)
	# One rebuilt list after a pause, not one per keystroke.
	filter_timer = Timer.new()
	filter_timer.one_shot = true
	filter_timer.wait_time = 0.15
	filter_timer.timeout.connect(_populate_tree)
	add_child(filter_timer)
	split = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 0
	body.add_child(split)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(list_box)
	tree = Tree.new()
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size = Vector2(200, 180)
	tree.columns = 3
	tree.hide_root = true
	tree.column_titles_visible = true
	tree.select_mode = Tree.SELECT_ROW
	var titles := ["Section / key", "Type", "Value"]
	var widths := [110, 58, 110]
	for i in 3:
		tree.set_column_title(i, titles[i])
		tree.set_column_expand(i, true)
		tree.set_column_expand_ratio(i, [3, 1, 3][i])
		tree.set_column_custom_minimum_width(i, widths[i])
	tree.item_selected.connect(_on_tree_selection)
	list_box.add_child(tree)
	summary = Label.new()
	summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	list_box.add_child(summary)
	detail = VBoxContainer.new()
	detail.custom_minimum_size.x = 300
	split.add_child(detail)
	selection_label = Label.new()
	selection_label.text = "Select a value"
	selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(selection_label)
	value_text = TextEdit.new()
	value_text.editable = false
	value_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	value_text.custom_minimum_size.y = 150
	value_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	value_text.add_theme_color_override("font_readonly_color", Color(0.88, 0.88, 0.88))
	detail.add_child(value_text)
	value_hint = Label.new()
	value_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value_hint.text = "The value is shown exactly as it appears in the file."
	detail.add_child(value_hint)
	# The status line carries messages whose length depends on the file path. Left as a plain
	# child it makes the whole panel taller when it wraps, which pushed the bottom of the
	# panel outside a short area. A fixed-height clipped box keeps the message inside the
	# layout; the full text stays available as a tooltip.
	status_box = Control.new()
	status_box.clip_contents = true
	status_box.custom_minimum_size.y = 52
	body.add_child(status_box)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Ready. Open a save file to list its values."
	status_box.add_child(status)
	status.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# One line, always visible: this add-on never writes, so say where writing lives.
	# A flow container so the note and the link wrap in a narrow dock.
	footer = HFlowContainer.new()
	footer.add_theme_constant_override("h_separation", 6)
	body.add_child(footer)
	var read_only_note := Label.new()
	read_only_note.text = "Read-only by design."
	read_only_note.modulate = Color(1, 1, 1, 0.65)
	footer.add_child(read_only_note)
	var editor_link := LinkButton.new()
	editor_link.text = "Need to change a value? Save Value Editor"
	editor_link.tooltip_text = EDITOR_URL
	editor_link.pressed.connect(func() -> void: OS.shell_open(EDITOR_URL))
	footer.add_child(editor_link)
	picker = FileDialog.new()
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.title = "Open settings or save file"
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.filters = PackedStringArray([
		"*.cfg, *.ini, *.json ; Supported save files",
		"*.cfg, *.ini ; Godot ConfigFile",
		"*.json ; JSON",
	])
	picker.file_selected.connect(func(path: String): open_path(path))
	add_child(picker)
	_clear_selection()
	_refresh()
	_reopen_last.call_deferred()


# The editor's main-screen area is usually narrower than 620 px. Side-by-side leaves the
# value pane off-screen there, so the list and the value pane stack vertically in a narrow
# area. The panel keeps its own minimum when the area around it shrinks, so its own size
# can stay unchanged while the visible area gets shorter: react to the parent as well.
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_instance_valid(split):
		_evaluate_area()
	elif what == NOTIFICATION_PARENTED and get_parent() is Control:
		if not get_parent().resized.is_connected(_evaluate_area):
			get_parent().resized.connect(_evaluate_area)


func _evaluate_area() -> void:
	if not is_instance_valid(split):
		return
	var area := _available_size()
	var want_vertical := area.x < 620
	if want_vertical != split_vertical:
		_rebuild_split.call_deferred(want_vertical)
	else:
		_apply_height.call_deferred(area.y)


# The panel is a child of a container; when its own minimum is larger than that area the
# panel is laid out bigger than the space it has, so the space must be read from the parent.
func _available_size() -> Vector2:
	var area := get_parent_area_size()
	return area if area.y > 0.0 else size


# A 1280x720 editor window leaves about 590 px of height for the main screen, which is less
# than the normal minimum. Short areas drop the one-line purpose and the value hint and
# shrink the list and the value box so Copy value and the footer stay on screen. A stacked
# layout (narrow area) needs the same treatment from a much taller area: the list and the
# value pane share one column there.
#
# The stage used to be picked by a height threshold (700/860, then 760/905). A constant is
# wrong in a band, because the uncompacted minimum depends on the width (wrapped labels)
# and on the engine's theme metrics (4.5's editor measures about 1.3x taller than 4.7's).
# Measure instead: try the normal layout and compact only as far as needed.
func _apply_height(available: float) -> void:
	if not is_instance_valid(split):
		return
	var factor := editor_ui_scale()
	for level in 3:
		_apply_stage(level, factor)
		if get_combined_minimum_size().y <= available:
			return
	# Even the tightest stage is taller than this area. Nothing is left to remove without
	# hiding the value pane.


func _apply_stage(level: int, factor: float) -> void:
	var tight := level >= 1
	var tighter := level >= 2
	# Margins stay fixed: changing this container's own theme constants from inside
	# NOTIFICATION_RESIZED feeds the layout back into itself and crashed 4.6.3.
	body.add_theme_constant_override("separation", 4 if tighter else (6 if tight else 10))
	purpose_label.visible = not split_vertical and not tight
	value_hint.visible = not tight
	summary.visible = not tighter
	status_box.custom_minimum_size.y = (26 if tighter else (40 if tight else 52)) * factor
	tree.custom_minimum_size.y = ((70 if tighter else 90) if tight else (150 if split_vertical else 180)) * factor
	value_text.custom_minimum_size.y = ((38 if tighter else 44) if tight else (56 if split_vertical else 150)) * factor


# The editor interface scale ("Interface > Editor > Display Scale"). A SceneTree probe or
# a running game has no editor singleton, where 1.0 is the honest value.
func editor_ui_scale() -> float:
	# A running game registers a stub EditorInterface too, so has_singleton() alone is
	# not enough: calling get_editor_scale() on the stub raises "Nonexistent function".
	# Go through the same editor-only gate as the rest of the panel.
	var editor = _editor_interface_instance()
	if editor == null or not editor.has_method("get_editor_scale"):
		return 1.0
	var scaled: float = editor.get_editor_scale()
	if scaled <= 0.0:
		return 1.0
	return clampf(scaled, 0.75, 3.0)


func _rebuild_split(vertical: bool) -> void:
	if not is_instance_valid(split) or vertical == split_vertical:
		return
	var index := split.get_index()
	split.remove_child(list_box)
	split.remove_child(detail)
	body.remove_child(split)
	split.queue_free()
	var next: SplitContainer = VSplitContainer.new() if vertical else HSplitContainer.new()
	next.size_flags_vertical = Control.SIZE_EXPAND_FILL
	next.split_offset = 0
	body.add_child(next)
	body.move_child(next, index)
	next.add_child(list_box)
	next.add_child(detail)
	split = next
	split_vertical = vertical
	# Both panes claim the height so the stacked split shares it, instead of giving the
	# list only its 3-row minimum and handing every spare pixel to the value pane.
	list_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Stacked, the value pane sits under the list, so the list, the purpose line and the
	# value box give up height to keep Copy value in an ordinary dock.
	purpose_label.visible = not vertical
	value_hint.visible = not vertical
	detail.custom_minimum_size.x = 195 if vertical else 300
	tree.custom_minimum_size.y = 130 if vertical else 180
	value_text.custom_minimum_size.y = 48 if vertical else 150
	_apply_height(_available_size().y)
	_refresh()


func _button(parent: Node, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _choose_file() -> void:
	if not document.path.is_empty():
		picker.current_dir = document.path.get_base_dir()
	picker.popup_centered(Vector2i(960, 640))


func _choose_user_folder() -> void:
	var dir_abs := ProjectSettings.globalize_path("user://").simplify_path()
	if not DirAccess.dir_exists_absolute(dir_abs):
		# Opening a file dialog on a folder that does not exist shows an empty window
		# and explains nothing, so say where the game would write instead.
		_message("This project has no user:// folder yet. Run the game once so it writes a save, or use Open file… for a file elsewhere. Expected: " + dir_abs, true)
		return
	var candidates := _user_candidates()
	if candidates.is_empty():
		_message("No .cfg, .ini or .json file under user:// yet: " + dir_abs + " — run the game once, or use Open file… for a file elsewhere.", true)
		return
	picker.current_dir = dir_abs
	_message("%d supported file(s) under user://: %s" % [candidates.size(), dir_abs])
	picker.popup_centered(Vector2i(960, 640))


# Count what this tool can open under user:// before offering the picker. Bounded so a
# project with an unusual amount of user data cannot stall the editor.
func _user_candidates(limit: int = 2000) -> Array[String]:
	var found: Array[String] = []
	var pending: Array[String] = ["user://"]
	while not pending.is_empty() and found.size() < limit:
		var current: String = pending.pop_back()
		var directory := DirAccess.open(current)
		if directory == null:
			continue
		for file_name in directory.get_files():
			if found.size() >= limit:
				break
			if String(file_name).get_extension().to_lower() in USER_EXTENSIONS:
				found.append(current.path_join(file_name))
		for child in directory.get_directories():
			pending.append(current.path_join(child))
	return found


func _editor_interface_instance():
	if not Engine.is_editor_hint():
		return null
	return Engine.get_singleton("EditorInterface")


# The editor's per-project settings are the right place for "the file I was looking at
# last time": they live outside the project folder and never touch the game's own data.
func _remember_path(file_path: String) -> void:
	var editor = _editor_interface_instance()
	if editor == null:
		return
	var settings = editor.get_editor_settings()
	if settings != null:
		settings.set_project_metadata(LAST_PATH_SECTION, LAST_PATH_KEY, file_path)


func _remembered_path() -> String:
	var editor = _editor_interface_instance()
	if editor == null:
		return ""
	var settings = editor.get_editor_settings()
	if settings == null:
		return ""
	return str(settings.get_project_metadata(LAST_PATH_SECTION, LAST_PATH_KEY, ""))


# Looking at a value is a repeat visit: change something, run the game, look again.
# Reopening the last file on editor start keeps that loop to one click, and only reads.
func _reopen_last() -> void:
	if not is_instance_valid(tree):
		return
	var last := _remembered_path()
	if last.is_empty():
		return
	if not FileAccess.file_exists(last):
		_message("Last file is no longer there: " + last + " — open a file to continue.")
		return
	open_path(last)
	if document.path == last:
		_message("Reopened the last file: " + last)


func open_path(path: String) -> void:
	if not document.open_file(path):
		_message(document.last_error, true)
		return
	selected_id = NO_SELECTION
	_clear_selection()
	_remember_path(document.path)
	filter.set_block_signals(true)
	filter.text = ""
	filter.set_block_signals(false)
	filter_timer.stop()
	_refresh()
	# Show the first value straight away: an open file with an empty detail pane
	# reads as if nothing was loaded.
	if document.count() > 0:
		selected_id = document.rows[0]["id"]
		_show_entry(selected_id)
		var first := tree.get_root().get_first_child()
		if first != null:
			first.select(0)
	_message("Opened %s (%s)." % [document.path.get_file(), _human_size(document.file_size)])


func has_open_file() -> bool:
	return not document.path.is_empty()


func _reload() -> void:
	if not document.reload():
		_message(document.last_error, true)
		return
	_populate_tree()
	_show_entry(selected_id)
	_message("Reloaded from disk (%s)." % _human_size(document.file_size))


func _on_filter_text_changed(_text: String) -> void:
	filter_timer.start()


func _flush_filter() -> void:
	filter_timer.stop()
	_populate_tree()


func _display_path(entry: Dictionary) -> String:
	# Show a readable path: "section/key", where a ConfigFile key that sits above
	# the first section (project.godot's config_version) reads "(top level)".
	# JSON pointers escape "/" and "~" as "~1"/"~0"; those are undone for display
	# only, so the stored id stays the exact pointer used for lookups.
	if String(entry.get("id", "")).is_empty():
		return "(root)"
	var section := String(entry.get("section", ""))
	var head := "(top level)"
	if not section.is_empty():
		head = section.replace("~1", "/").replace("~0", "~")
	return head + "/" + String(entry.get("key", ""))


func _populate_tree() -> void:
	if not is_instance_valid(tree):
		return
	filling = true
	tree.clear()
	var root := tree.create_item()
	var needle := filter.text.to_lower()
	var visible_count := 0
	for row in document.rows:
		var searchable := "%s %s %s %s" % [row["id"], row["kind"], row["original"], row["section"]]
		if not needle.is_empty() and not needle in searchable.to_lower():
			continue
		var item := tree.create_item(root)
		item.set_metadata(0, row["id"])
		item.set_text(0, _display_path(row))
		item.set_text(1, row["kind"])
		item.set_text(2, _one_line(row["original"]))
		for col in 3:
			item.set_tooltip_text(col, "%s\n%s\n%s" % [row["id"], row["kind"], _one_line(row["original"])])
		if row["id"] == selected_id:
			item.select(0)
		visible_count += 1
	if document.path.is_empty():
		summary.text = ""
	elif document.count() == 0:
		summary.text = "This file contains no values."
	else:
		summary.text = "%d shown / %d values   ·   %s" % [visible_count, document.count(), _human_size(document.file_size)]
	filling = false


func _on_tree_selection() -> void:
	if filling:
		return
	var item := tree.get_selected()
	if item == null:
		return
	_show_entry(item.get_metadata(0))


func _show_entry(id: String) -> void:
	var entry := document.entry(id)
	if entry.is_empty():
		_clear_selection()
		return
	selected_id = id
	selection_label.text = "%s\n%s" % [_display_path(entry), entry["kind"]]
	value_text.text = entry["value"]
	copy_value_button.disabled = false
	copy_key_button.disabled = false


func _clear_selection() -> void:
	selected_id = NO_SELECTION
	selection_label.text = "Select a value"
	value_text.text = ""
	copy_value_button.disabled = true
	copy_key_button.disabled = true


func _copy_value() -> void:
	var entry := document.entry(selected_id)
	if entry.is_empty():
		return
	DisplayServer.clipboard_set(entry["value"])
	_message("Copied the value of %s." % entry["id"])


func _copy_key() -> void:
	var entry := document.entry(selected_id)
	if entry.is_empty():
		return
	var shown := _display_path(entry)
	DisplayServer.clipboard_set(shown)
	_message("Copied the key %s." % shown)


func _show_in_folder() -> void:
	if document.path.is_empty():
		return
	OS.shell_show_in_file_manager(document.path)


func _refresh() -> void:
	_populate_tree()
	if document.path.is_empty():
		path_label.text = "No file open — choose a UTF-8 .cfg, .ini or .json file."
		path_label.tooltip_text = ""
	else:
		path_label.text = document.path
		path_label.tooltip_text = document.path
	reload_button.disabled = document.path.is_empty()
	show_button.disabled = document.path.is_empty()
	_clear_selection()


func _one_line(text: String) -> String:
	return text.replace("\n", " ↵ ").replace("\r", "")


func _human_size(size: int) -> String:
	if size < 1024:
		return "%d B" % size
	if size < 1024 * 1024:
		return "%.1f KiB" % (size / 1024.0)
	return "%.1f MiB" % (size / (1024.0 * 1024.0))


func _message(text: String, is_error: bool = false) -> void:
	status.text = text
	# The box clips a long path on a short area, so keep the whole sentence reachable.
	status.tooltip_text = text
	status.modulate = Color(1.0, 0.58, 0.48) if is_error else Color.WHITE
