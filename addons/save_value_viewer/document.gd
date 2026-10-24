@tool
extends RefCounted
## Read-only view of a save or settings file. Nothing in this class writes to disk:
## the file is read once per open/reload and only the resolved text span is exposed.

const Parser = preload("parser.gd")
const MAX_BYTES := 8 * 1024 * 1024

var path: String = ""
var last_error: String = ""
var file_size: int = 0
var rows: Array[Dictionary] = []

var _index: Dictionary = {}
var _json: bool = false


func open_file(file_path: String) -> bool:
	last_error = ""
	if file_path.strip_edges().is_empty():
		return _fail("Choose a file first.")
	var absolute := ProjectSettings.globalize_path(file_path).simplify_path()
	if not absolute.is_absolute_path():
		return _fail("Choose an absolute path, or a res:// or user:// path.")
	var read := _read(absolute)
	if read.is_empty():
		return false
	var parser := Parser.new()
	if not parser.parse(read["text"], _is_json(absolute)):
		return _fail("Cannot read this file: " + parser.error)
	path = absolute
	file_size = read["size"]
	_json = _is_json(absolute)
	rows = parser.rows
	_index.clear()
	for i in rows.size():
		_index[rows[i]["id"]] = i
	return true


func reload() -> bool:
	return open_file(path) if not path.is_empty() else _fail("No file is open.")


func count() -> int:
	return rows.size()


func is_json() -> bool:
	return _json


func entry(id: String) -> Dictionary:
	if not _index.has(id):
		return {}
	var row: Dictionary = rows[_index[id]]
	return {
		"id": row["id"],
		"section": row["section"],
		"key": row["key"],
		"kind": row["kind"],
		"value": row["original"],
		"editable_in_editor_addon": row["editable"],
	}


func _is_json(file_path: String) -> bool:
	return file_path.get_extension().to_lower() == "json"


func _read(absolute: String) -> Dictionary:
	var file := FileAccess.open(absolute, FileAccess.READ)
	if file == null:
		_fail("Cannot open %s: %s." % [absolute, error_string(FileAccess.get_open_error())])
		return {}
	var length := file.get_length()
	if length > MAX_BYTES:
		file.close()
		_fail("This file is larger than the 8 MiB limit: " + absolute)
		return {}
	var bytes := file.get_buffer(length)
	var read_error := file.get_error()
	var end_length := file.get_length()
	file.close()
	if bytes.size() != length or end_length != length or read_error != OK:
		_fail("The file could not be read completely: " + absolute)
		return {}
	if bytes.has(0):
		_fail("Binary, UTF-16 and compressed save files are not supported: " + absolute)
		return {}
	var bom := bytes.size() >= 3 and bytes[0] == 0xef and bytes[1] == 0xbb and bytes[2] == 0xbf
	var payload := bytes.slice(3) if bom else bytes
	var text := ("\ufeff" if bom else "") + payload.get_string_from_utf8()
	if text.to_utf8_buffer() != bytes:
		_fail("This file is not valid UTF-8 text: " + absolute)
		return {}
	return {"text": text, "size": bytes.size()}


func _fail(message: String) -> bool:
	last_error = message
	return false
