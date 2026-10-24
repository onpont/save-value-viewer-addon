@tool
extends RefCounted
## Non-executing, bounded lexical parser. Offsets are String character offsets;
## encoding the unchanged source back to UTF-8 reproduces the original bytes.

const MAX_DEPTH := 64
const MAX_ENTRIES := 20000
const MAX_NODES := 100000
const MAX_ID_LENGTH := 4096
const CONSTRUCTORS := {
	"Vector2": 2, "Vector2i": 2, "Vector3": 3, "Vector3i": 3,
	"Vector4": 4, "Vector4i": 4, "Rect2": 4, "Rect2i": 4,
	"Transform2D": 6, "Plane": 4, "Quaternion": 4, "AABB": 6,
	"Basis": 9, "Transform3D": 12, "Projection": 16, "Color": 4,
	"PackedByteArray": -1, "PackedInt32Array": -1, "PackedInt64Array": -1,
	"PackedFloat32Array": -1, "PackedFloat64Array": -1,
	"PackedStringArray": -1, "PackedVector2Array": -2,
	"PackedVector3Array": -3, "PackedVector4Array": -4, "PackedColorArray": -4,
}

var error: String = ""
var rows: Array[Dictionary] = []
var _text: String = ""
var _pos: int = 0
var _json: bool = true
var _nodes: int = 0
var _string_has_nul: bool = false
var _number := RegEx.new()
var _integer := RegEx.new()
var _config_number := RegEx.new()


func parse(source: String, json_mode: bool) -> bool:
	_text = source
	_pos = 0
	_json = json_mode
	_nodes = 0
	error = ""
	rows.clear()
	_number.compile("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$")
	_integer.compile("^-?[0-9]+$")
	_config_number.compile("^-?[0-9]+(\\.[0-9]*)?([eE][+-]?[0-9]+)?$")
	# Keep a UTF-8 BOM in the source, but do not treat it as a token.
	if _peek() == "\ufeff":
		_pos += 1
	if _json:
		_space()
		if not _json_value("", "", "(root)", 0):
			return false
		_space()
		if _pos != _text.length():
			return _fail("Unexpected text after JSON value")
		return true
	return _config()


func validate_literal(literal: String, json_mode: bool, expected_kind: String) -> bool:
	# Parse the entire literal, without accepting surrounding whitespace/comments.
	if literal.is_empty() or literal != literal.strip_edges() or literal.contains("\n") or literal.contains("\r"):
		error = "Enter one literal without surrounding whitespace or a line break."
		return false
	if not parse(literal if json_mode else "value=" + literal, json_mode):
		return false
	if rows.size() != 1 or rows[0]["original"] != literal or rows[0]["kind"] != expected_kind:
		error = "The replacement must keep the original scalar type (%s)." % expected_kind
		return false
	return bool(rows[0]["editable"])


func _peek() -> String:
	return _text.substr(_pos, 1)


func _fail(message: String) -> bool:
	if error.is_empty():
		error = "%s (character %d)." % [message, _pos + 1]
	return false


func _tick(depth: int) -> bool:
	_nodes += 1
	if depth > MAX_DEPTH:
		return _fail("Nesting exceeds %d levels" % MAX_DEPTH)
	if _nodes > MAX_NODES:
		return _fail("Document exceeds %d values" % MAX_NODES)
	return true


func _space() -> void:
	while _pos < _text.length():
		if _peek() in [" ", "\t", "\r", "\n"]:
			_pos += 1
		elif not _json and _peek() == ";":
			_comment()
		else:
			break


func _comment() -> void:
	while _pos < _text.length() and _peek() != "\n":
		_pos += 1


func _pointer(part: String) -> String:
	return part.replace("~", "~0").replace("/", "~1")


func _add(id: String, section: String, key: String, kind: String, start: int, finish: int, editable: bool) -> bool:
	if id.length() > MAX_ID_LENGTH:
		return _fail("Entry identifier exceeds %d characters" % MAX_ID_LENGTH)
	if rows.size() >= MAX_ENTRIES:
		return _fail("Document exceeds %d entries" % MAX_ENTRIES)
	var literal := _text.substr(start, finish - start)
	rows.append({"id": id, "section": section, "key": key, "kind": kind,
		"original": literal, "draft": literal, "editable": editable,
		"start": start, "finish": finish})
	return true


func _json_value(id: String, section: String, key: String, depth: int) -> bool:
	if not _tick(depth):
		return false
	if id.length() > MAX_ID_LENGTH:
		return _fail("JSON pointer exceeds %d characters" % MAX_ID_LENGTH)
	_space()
	var start := _pos
	var ch := _peek()
	if ch == "{":
		_pos += 1
		_space()
		var seen: Dictionary = {}
		if _peek() == "}":
			_pos += 1
			return true
		while true:
			if _peek() != "\"":
				return _fail("Expected a quoted JSON object key")
			var object_key := _string()
			if not error.is_empty():
				return false
			if _string_has_nul:
				return _fail("NUL in object keys cannot be represented by Godot String/JSON pointers")
			if seen.has(object_key):
				return _fail("Duplicate JSON object key: %s" % object_key)
			seen[object_key] = true
			_space()
			if _peek() != ":":
				return _fail("Expected ':' after object key")
			_pos += 1
			if not _json_value(id + "/" + _pointer(object_key), id, object_key, depth + 1):
				return false
			_space()
			if _peek() == "}":
				_pos += 1
				return true
			if _peek() != ",":
				return _fail("Expected ',' or '}'")
			_pos += 1
			_space()
	elif ch == "[":
		_pos += 1
		_space()
		var index := 0
		if _peek() == "]":
			_pos += 1
			return true
		while true:
			if not _json_value(id + "/" + str(index), id, str(index), depth + 1):
				return false
			index += 1
			_space()
			if _peek() == "]":
				_pos += 1
				return true
			if _peek() != ",":
				return _fail("Expected ',' or ']'")
			_pos += 1
			_space()
	elif ch == "\"":
		_string()
		if not error.is_empty():
			return false
		return _add(id, section, key, "string", start, _pos, true)
	else:
		var token := _token()
		var kind := ""
		if token in ["true", "false"]:
			kind = "bool"
		elif token == "null":
			kind = "null"
		elif not token.is_empty() and _number.search(token) != null:
			kind = "number"
		else:
			return _fail("Invalid JSON scalar")
		return _add(id, section, key, kind, start, _pos, kind != "null")
	return false


func _token() -> String:
	var start := _pos
	while _pos < _text.length() and not (_peek() in [" ", "\t", "\r", "\n", ",", "]", "}", ")", ":", ";"]):
		_pos += 1
	return _text.substr(start, _pos - start)


func _hex(count: int) -> int:
	if _pos + count > _text.length():
		_fail("Incomplete Unicode escape")
		return -1
	var value := 0
	for index in range(count):
		var digit := "0123456789abcdef".find(_peek().to_lower())
		if digit < 0:
			_fail("Invalid Unicode escape")
			return -1
		value = value * 16 + digit
		_pos += 1
	return value


func _string() -> String:
	# Decode only strings (for duplicate detection/labels), never numeric values.
	_string_has_nul = false
	_pos += 1
	var parts := PackedStringArray()
	var start := _pos
	while _pos < _text.length():
		var ch := _peek()
		if ch == "\"":
			parts.append(_text.substr(start, _pos - start))
			_pos += 1
			return "".join(parts)
		if ch == "\\":
			parts.append(_text.substr(start, _pos - start))
			_pos += 1
			var escape := _peek()
			_pos += 1
			var decoded := ""
			if escape in ["\"", "\\", "/"]:
				decoded = escape
			elif escape == "b":
				decoded = String.chr(8)
			elif escape == "f":
				decoded = String.chr(12)
			elif escape == "n":
				decoded = "\n"
			elif escape == "r":
				decoded = "\r"
			elif escape == "t":
				decoded = "\t"
			elif escape == "u" or (not _json and escape == "U"):
				var code := _hex(6 if escape == "U" else 4)
				if code < 0:
					return ""
				if code >= 0xd800 and code <= 0xdbff:
					if _text.substr(_pos, 2) != "\\u":
						_fail("Unpaired Unicode high surrogate")
						return ""
					_pos += 2
					var low := _hex(4)
					if low < 0xdc00 or low > 0xdfff:
						_fail("Invalid Unicode surrogate pair")
						return ""
					code = 0x10000 + (code - 0xd800) * 1024 + low - 0xdc00
				elif code >= 0xdc00 and code <= 0xdfff:
					_fail("Unpaired Unicode low surrogate")
					return ""
				if code > 0x10ffff:
					_fail("Unicode escape outside scalar range")
					return ""
				if code == 0:
					# Godot String.chr(0) produces U+FFFD and logs an error.
					# Scalar values remain raw; keys are explicitly rejected.
					_string_has_nul = true
					decoded = "\\u0000"
				else:
					decoded = String.chr(code)
			elif not _json and not escape.is_empty():
				# Godot's VariantParser treats unknown escapes as the escaped char.
				decoded = escape
			else:
				_fail("Invalid string escape")
				return ""
			parts.append(decoded)
			start = _pos
		else:
			if _json and ch.unicode_at(0) < 32:
				_fail("Unescaped control character in JSON string")
				return ""
			_pos += 1
	_fail("Unterminated string")
	return ""


func _config() -> bool:
	var section := ""
	var seen: Dictionary = {}
	while true:
		_space()
		if _pos >= _text.length():
			return true
		if _peek() == "[":
			_pos += 1
			var section_start := _pos
			while _pos < _text.length() and _peek() != "]":
				if _peek() in ["\n", "\r", "\\", "["]:
					return _fail("Unsupported ConfigFile section syntax")
				_pos += 1
			if _peek() != "]":
				return _fail("Unterminated section")
			section = _text.substr(section_start, _pos - section_start).strip_edges()
			if section.is_empty():
				return _fail("Empty ConfigFile sections are ambiguous and are not supported")
			_pos += 1
			if not _line_end():
				return false
			continue
		var key := ""
		if _peek() == "\"":
			key = _string()
			if not error.is_empty() or key.contains("\n") or key.contains("\r") or _string_has_nul:
				return _fail("Unsupported multiline key")
			while _peek() in [" ", "\t"]:
				_pos += 1
		else:
			var key_start := _pos
			while _pos < _text.length() and not (_peek() in ["=", "\n", "\r", ";"]):
				if _peek() in ["\"", "[", "]", "\\"]:
					return _fail("Use a quoted ConfigFile key")
				_pos += 1
			key = _text.substr(key_start, _pos - key_start).strip_edges()
			# Godot ignores whitespace in unquoted keys. Refuse that ambiguity.
			if key.contains(" ") or key.contains("\t"):
				return _fail("Keys containing whitespace must be quoted")
		if key.is_empty() or _peek() != "=":
			return _fail("Expected a ConfigFile key followed by '='")
		_pos += 1
		var before_value := _pos
		_space()
		var start := _pos
		var kind := _config_value(0)
		if kind.is_empty():
			return false
		var finish := _pos
		var id := "/" + _pointer(section) + "/" + _pointer(key)
		if seen.has(id):
			return _fail("Duplicate ConfigFile section/key: %s" % id)
		seen[id] = true
		var multiline := _text.substr(before_value, finish - before_value).contains("\n") or _text.substr(before_value, finish - before_value).contains("\r")
		var editable := kind in ["string", "bool", "int", "float"] and not multiline
		if not _add(id, section, key, kind, start, finish, editable):
			return false
		if not _line_end():
			return false
	return true


func _line_end() -> bool:
	while _peek() in [" ", "\t", "\r"]:
		_pos += 1
	if _peek() == ";":
		_comment()
	if _pos == _text.length():
		return true
	if _peek() != "\n":
		return _fail("Unsupported text after ConfigFile value/section")
	_pos += 1
	return true


func _config_value(depth: int) -> String:
	if not _tick(depth):
		return ""
	_space()
	if _peek() == "\"":
		_string()
		return "string" if error.is_empty() else ""
	if _peek() == "[":
		return "array" if _config_container(depth, false) else ""
	if _peek() == "{":
		return "dictionary" if _config_container(depth, true) else ""
	# StringName is safe, but intentionally not scalar-editable.
	if _peek() == "&" and _text.substr(_pos + 1, 1) == "\"":
		_pos += 1
		_string()
		return "StringName" if error.is_empty() else ""
	var start := _pos
	while _pos < _text.length() and not (_peek() in [" ", "\t", "\r", "\n", ",", "]", "}", ")", "(", ":", ";"]):
		_pos += 1
	var token := _text.substr(start, _pos - start)
	if token in ["true", "false"]:
		return "bool"
	if token == "null":
		return "null"
	if token in ["inf", "-inf", "inf_neg", "nan"]:
		return "float"
	if _integer.search(token) != null:
		if not _int64_fits(token):
			_fail("ConfigFile integer is outside signed 64-bit range")
			return ""
		return "int"
	# Godot allows a trailing decimal point; require exponent digits.
	if _config_number.search(token) != null:
		return "float"
	if CONSTRUCTORS.has(token):
		return token if _config_constructor(token, depth) else ""
	_fail("Unsupported ConfigFile value/type: %s (objects/resources/typed containers are not loaded)" % token)
	return ""


func _int64_fits(token: String) -> bool:
	var negative := token.begins_with("-")
	var digits := token.substr(1) if negative else token
	var first := 0
	while first < digits.length() - 1 and digits.substr(first, 1) == "0":
		first += 1
	digits = digits.substr(first)
	var limit := "9223372036854775808" if negative else "9223372036854775807"
	return digits.length() < limit.length() or (digits.length() == limit.length() and digits <= limit)


func _config_container(depth: int, dictionary: bool) -> bool:
	var close := "}" if dictionary else "]"
	_pos += 1
	_space()
	if _peek() == close:
		_pos += 1
		return true
	while true:
		if _config_value(depth + 1).is_empty():
			return false
		_space()
		if dictionary:
			if _peek() != ":":
				return _fail("Expected ':' in dictionary")
			_pos += 1
			if _config_value(depth + 1).is_empty():
				return false
			_space()
		if _peek() == close:
			_pos += 1
			return true
		if _peek() != ",":
			return _fail("Expected ',' or '%s'" % close)
		_pos += 1
		_space()
		# Godot permits trailing commas in arrays/dictionaries.
		if _peek() == close:
			_pos += 1
			return true
	return false


func _config_constructor(name: String, depth: int) -> bool:
	_space()
	if _peek() != "(":
		return _fail("Expected '(' after %s" % name)
	_pos += 1
	_space()
	var count := 0
	if _peek() != ")":
		while true:
			var kind := _config_value(depth + 1)
			if kind.is_empty():
				return false
			if name == "PackedStringArray":
				if kind != "string":
					return _fail("PackedStringArray requires strings")
			elif not (kind in ["int", "float"]):
				return _fail("%s requires numeric arguments" % name)
			count += 1
			_space()
			if _peek() == ")":
				break
			if _peek() != ",":
				return _fail("Expected ',' or ')' in constructor")
			_pos += 1
			_space()
	_pos += 1
	var required: int = CONSTRUCTORS[name]
	if required >= 0 and count != required:
		return _fail("%s requires %d arguments" % [name, required])
	if required < -1 and count % (-required) != 0:
		return _fail("Invalid packed vector/color argument count")
	return true
