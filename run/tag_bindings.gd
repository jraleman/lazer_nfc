extends RefCounted

## Physical tag identities stay separate from settings and never truncate a richer save.

const Palette = preload("res://games/lazer_nfc/run/palette.gd")
const DEFAULT_PATH := "user://lazer_nfc_tags.cfg"
const SECTION := "tags"
const MAX_BINDINGS := 21
const MAX_UID_CHARACTERS := 64

var uid_to_color: Dictionary = {}
var _failed_reads: Dictionary[String, Error] = {}
# An empty owner authorizes a prompted relabel; otherwise retire only the known owner.
var _retired_uids: Dictionary[String, StringName] = {}


## Android supplies complete hexadecimal bytes, without separators or whitespace.
static func canonical_uid(uid: String) -> String:
	if uid.is_empty() or uid.length() % 2 != 0 or uid.length() > MAX_UID_CHARACTERS:
		return ""
	for index in uid.length():
		var character := uid.unicode_at(index)
		if not (
			(character >= 48 and character <= 57)
			or (character >= 65 and character <= 70)
			or (character >= 97 and character <= 102)
		):
			return ""
	return uid.to_lower()


## A failed read keeps the last good map and locks that path against later saves.
func load_file(path: String = DEFAULT_PATH) -> Error:
	if path.is_empty():
		return _failure("read an empty save path", path, ERR_FILE_BAD_PATH)
	var config := ConfigFile.new()
	var error := config.load(path)
	if error == ERR_FILE_NOT_FOUND:
		return error
	var bindings: Dictionary = {}
	if error == OK:
		error = _read_config(config, bindings)
	if error != OK:
		_failed_reads[_path_key(path)] = error
		return _failure("read", path, error)
	uid_to_color = bindings
	_retired_uids.clear()
	_failed_reads.erase(_path_key(path))
	return OK


## Only an explicit roll-call prompt may relabel a UID already owned by another colour.
func bind_tag(
	uid: String, color_id: StringName, allow_reassignment: bool = false
) -> Error:
	var canonical := canonical_uid(uid)
	if canonical.is_empty() or not Palette.is_valid(color_id):
		return _failure("bind tag", "", ERR_INVALID_PARAMETER)
	var bindings: Dictionary = {}
	var error := _validate_map(uid_to_color, bindings)
	if error != OK:
		return _failure("bind tag", "", error)
	if (
		bindings.has(canonical) and bindings[canonical] != color_id
		and not allow_reassignment
	):
		return _failure("bind tag already assigned to another colour", "", ERR_ALREADY_EXISTS)
	for previous_uid: String in bindings.keys():
		if previous_uid != canonical and bindings[previous_uid] == color_id:
			if not _retired_uids.has(previous_uid):
				_retired_uids[previous_uid] = color_id
			bindings.erase(previous_uid)
	if allow_reassignment:
		_retired_uids[canonical] = &""
	bindings[canonical] = color_id
	uid_to_color = bindings
	return OK


## Unknown or malformed scans are not answers and cannot create bindings.
func color_for(uid: String) -> StringName:
	var canonical := canonical_uid(uid)
	if canonical.is_empty():
		return &""
	var color_id: Variant = uid_to_color.get(canonical, &"")
	if not (color_id is String or color_id is StringName):
		return &""
	return StringName(color_id) if Palette.is_valid(StringName(color_id)) else &""


## The roll call first establishes distinct hues, then dark and light tag groups.
static func binding_order(shades: bool = false) -> Array[StringName]:
	var result: Array[StringName] = []
	for hue: StringName in Palette.GROWTH_ORDER:
		result.append(hue)
	if shades:
		for shade in [0, 2]:
			for hue: StringName in Palette.GROWTH_ORDER:
				result.append(Palette.id_for(hue, shade))
	return result


## Return actual bound IDs, not a count that could accidentally unlock an absent hue.
func bound_colors(shades: bool = false) -> Array[StringName]:
	var result: Array[StringName] = []
	var colors := uid_to_color.values()
	for color_id: StringName in binding_order(shades):
		if colors.has(color_id):
			result.append(color_id)
	return result


## Merge against disk again, preserving skipped hues, shade tags and unrelated sections.
func save_file(path: String = DEFAULT_PATH) -> Error:
	if path.is_empty():
		return _failure("write an empty save path", path, ERR_FILE_BAD_PATH)
	var path_key := _path_key(path)
	if _failed_reads.has(path_key):
		return _failure("save after failed read; load a repaired file first",
			path, _failed_reads[path_key])
	var incoming: Dictionary = {}
	var error := _validate_map(uid_to_color, incoming)
	if error != OK:
		return _failure("save invalid in-memory bindings", path, error)
	var config := ConfigFile.new()
	error = config.load(path)
	var merged: Dictionary = {}
	if error == OK:
		error = _read_config(config, merged)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		_failed_reads[path_key] = error
		return _failure("read before merge", path, error)

	for uid: String in _retired_uids:
		var previous_owner := _retired_uids[uid]
		if previous_owner.is_empty() or merged.get(uid, &"") == previous_owner:
			merged.erase(uid)
	var incoming_colors := incoming.values()
	for previous_uid: String in merged.keys():
		if incoming_colors.has(merged[previous_uid]):
			merged.erase(previous_uid)
	for uid: String in incoming:
		if merged.has(uid) and merged[uid] != incoming[uid]:
			return _failure("merge a UID already assigned to an unbound colour",
				path, ERR_ALREADY_EXISTS)
		merged[uid] = incoming[uid]
	if merged.size() > MAX_BINDINGS:
		return _failure("save too many bindings", path, ERR_INVALID_DATA)

	if config.has_section(SECTION):
		config.erase_section(SECTION)
	for uid: String in merged:
		config.set_value(SECTION, uid, String(merged[uid]))
	error = _save_atomically(config, path)
	if error == OK:
		uid_to_color = merged
		_retired_uids.clear()
	return error


func _read_config(config: ConfigFile, bindings: Dictionary) -> Error:
	var raw: Dictionary = {}
	if config.has_section(SECTION):
		for uid: String in config.get_section_keys(SECTION):
			raw[uid] = config.get_value(SECTION, uid)
	return _validate_map(raw, bindings)


func _validate_map(raw: Dictionary, bindings: Dictionary) -> Error:
	var color_to_uid: Dictionary = {}
	for raw_uid: Variant in raw:
		if not (raw_uid is String or raw_uid is StringName):
			return ERR_INVALID_DATA
		var uid := canonical_uid(String(raw_uid))
		var raw_color: Variant = raw[raw_uid]
		if uid.is_empty() or not (raw_color is String or raw_color is StringName):
			return ERR_INVALID_DATA
		var color_id := StringName(raw_color)
		if not Palette.is_valid(color_id):
			return ERR_INVALID_DATA
		if bindings.has(uid) and bindings[uid] != color_id:
			return ERR_INVALID_DATA
		if color_to_uid.has(color_id) and color_to_uid[color_id] != uid:
			return ERR_INVALID_DATA
		bindings[uid] = color_id
		color_to_uid[color_id] = uid
	return OK if bindings.size() <= MAX_BINDINGS else ERR_INVALID_DATA


func _save_atomically(config: ConfigFile, path: String) -> Error:
	var temporary := "%s.%d.%d.tmp" % [path, OS.get_process_id(), get_instance_id()]
	if FileAccess.file_exists(temporary):
		return _failure("save over an existing temporary file", path, ERR_ALREADY_EXISTS)
	var error := config.save(temporary)
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		if FileAccess.file_exists(temporary):
			var cleanup_error := DirAccess.remove_absolute(temporary)
			if cleanup_error != OK:
				_failure("remove temporary save", temporary, cleanup_error)
		return _failure("save", path, error)
	return OK


func _path_key(path: String) -> String:
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	return absolute.to_lower() if OS.get_name() == "Windows" else absolute


func _failure(operation: String, path: String, error: Error) -> Error:
	push_warning("LaZer NFC could not %s%s: %s. Existing tags unchanged." % [
		operation, " at " + path if not path.is_empty() else "", error_string(error),
	])
	return error
