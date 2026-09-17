extends SceneTree

## Binding regressions touch only explicitly named disposable files, never the player's map.

const TagBindings = preload("res://games/lazer_nfc/run/tag_bindings.gd")
const Palette = preload("res://games/lazer_nfc/run/palette.gd")

var _failures: Array[String] = []
var _checks := 0
var _paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_uid_validation()
	_test_order_and_palette()
	_test_merge_and_rebind()
	_test_explicit_reassignment()
	_test_reassignment_chains()
	_test_reassignment_read_guard()
	_test_failed_reads()
	_test_invalid_maps()
	for path: String in _paths:
		if FileAccess.file_exists(path):
			_expect(DirAccess.remove_absolute(path) == OK,
				"The explicitly named tag fixture must be removed.")
	if _failures.is_empty():
		print("lazer_nfc_bindings_test: %d checks passed." % _checks)
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_uid_validation() -> void:
	var tags := TagBindings.new()
	_expect(tags.bind_tag("04AABBCC", &"red") == OK, "A real hex UID can be bound.")
	_expect(tags.color_for("04aAbBcC") == &"red", "UID lookup is case-independent.")
	_expect(tags.uid_to_color.has("04aabbcc"), "In-memory UIDs are lowercase.")
	var before := tags.uid_to_color.duplicate()
	var invalid := [
		"", "a", "abc", "0x04aabbcc", "04:AA:BB:CC", " aa ", "aa\n",
		"gg", "keyboard:red", "touch_red", "a".repeat(66), "aa" + String.chr(1),
	]
	for uid: String in invalid:
		_expect(tags.bind_tag(uid, &"blue") == ERR_INVALID_PARAMETER,
			"Malformed or fallback UID must be rejected: %s." % uid.c_escape())
		_expect(tags.color_for(uid) == &"", "Malformed UID lookup remains unknown.")
	_expect(tags.uid_to_color == before, "Rejected scans cannot mutate good bindings.")
	_expect(tags.bind_tag("04aabbcc", &"blue") == ERR_ALREADY_EXISTS,
		"One UID cannot belong to two colours.")
	_expect(tags.bind_tag("04aabbdd", &"blue_mid") == ERR_INVALID_PARAMETER,
		"Only the declared 21 colour IDs can be persisted.")
	_expect(tags.color_for("04000000") == &"", "An unbound real UID is not an answer.")


func _test_order_and_palette() -> void:
	var expected: Array[StringName] = [
		&"red", &"yellow", &"green", &"blue", &"orange", &"indigo", &"violet",
	]
	_expect(TagBindings.binding_order() == expected, "Roll call uses growth, not key order.")
	var order := TagBindings.binding_order(true)
	_expect(order.size() == 21, "Shade roll call contains precisely 21 colours.")
	_expect(order[7] == &"red_dark" and order[13] == &"violet_dark",
		"Dark tags follow the complete base group.")
	_expect(order[14] == &"red_light" and order[20] == &"violet_light",
		"Light tags follow the complete dark group.")
	var tags := TagBindings.new()
	for index in order.size():
		_expect(tags.bind_tag("%08X" % (index + 1), order[index]) == OK,
			"Each of the 21 declared colours accepts one tag.")
	_expect(tags.bound_colors() == expected, "Base mode does not expose stored shade tags.")
	_expect(tags.bound_colors(true) == order, "Shade mode exposes the real bound palette.")
	_expect(tags.uid_to_color.size() == 21, "There are never more than 21 bindings.")
	_expect(tags.bind_tag("04abcdef", &"red") == OK, "A colour can get a replacement sticker.")
	_expect(tags.color_for("00000001") == &"", "A replaced sticker is no longer an answer.")
	_expect(tags.uid_to_color.size() == 21, "Rebinding does not grow the map.")


func _test_merge_and_rebind() -> void:
	var path := _fixture_path("merge")
	var config := ConfigFile.new()
	config.set_value(TagBindings.SECTION, "04AA0001", "red")
	config.set_value(TagBindings.SECTION, "04bb0002", "blue")
	config.set_value(TagBindings.SECTION, "04cc0003", "violet_light")
	config.set_value("unrelated", "keep_me", {"number": 7, "text": "retained"})
	_expect(config.save(path) == OK, "The merge fixture saves.")

	var partial := TagBindings.new()
	_expect(partial.bind_tag("04DD0004", &"red") == OK, "A partial roll call can rebind red.")
	_expect(partial.save_file(path) == OK, "Saving merges a partial map into the stored map.")
	config = ConfigFile.new()
	_expect(config.load(path) == OK, "The merged file remains readable.")
	_expect(not config.has_section_key(TagBindings.SECTION, "04AA0001"),
		"The obsolete uppercase UID is intentionally removed.")
	_expect(config.get_value(TagBindings.SECTION, "04dd0004", "") == "red",
		"A saved UID is canonical.")
	_expect(config.get_value(TagBindings.SECTION, "04bb0002", "") == "blue",
		"A skipped hue survives a partial roll call.")
	_expect(config.get_value(TagBindings.SECTION, "04cc0003", "") == "violet_light",
		"A base-only save cannot remove an unbound shade.")
	_expect(config.get_value("unrelated", "keep_me", {}) == {"number": 7, "text": "retained"},
		"The merge preserves unrelated ConfigFile sections and values.")
	var base: Array[StringName] = [&"red", &"blue"]
	_expect(partial.bound_colors() == base, "Bound colours describe the actual sparse palette.")

	var conflict := TagBindings.new()
	_expect(conflict.bind_tag("04bb0002", &"green") == OK,
		"A partial in-memory map does not know the disk's other colours.")
	var before := FileAccess.get_file_as_string(path)
	_expect(conflict.save_file(path) == ERR_ALREADY_EXISTS,
		"Merge detects a UID owned by an unseen stored colour.")
	_expect(FileAccess.get_file_as_string(path) == before, "A conflicting merge writes nothing.")

	var loaded := TagBindings.new()
	_expect(loaded.load_file(path) == OK, "The persisted partial palette loads.")
	_expect(loaded.bind_tag("040000aa", &"blue") == OK, "Blue can move to a new free UID.")
	_expect(loaded.bind_tag("04bb0002", &"red") == OK, "An explicitly freed UID can be reused.")
	_expect(loaded.save_file(path) == OK, "Merge understands both intentional replacements.")
	_expect(loaded.color_for("04dd0004") == &"", "The second red replacement removes its old UID.")
	_expect(loaded.color_for("04bb0002") == &"red", "The freed UID has exactly its new colour.")
	_expect(loaded.color_for("040000aa") == &"blue", "Blue retains its replacement.")
	_expect(loaded.color_for("04cc0003") == &"violet_light", "Untouched shades still survive.")


func _test_explicit_reassignment() -> void:
	var path := _fixture_path("reassignment")
	_seed_reassignment_file(path)
	var tags := TagBindings.new()
	_expect(tags.load_file(path) == OK, "The original physical tag labels load.")
	var before := tags.uid_to_color.duplicate()
	_expect(tags.bind_tag("04aa0001", &"red") == ERR_ALREADY_EXISTS,
		"Reassignment remains opt-in outside a prompted roll call.")
	_expect(tags.uid_to_color == before, "A denied reassignment changes no owner.")
	_expect(tags.bind_tag("04AA0001", &"red", true) == OK,
		"A prompted roll call can relabel the orange sticker as red.")
	_expect(tags.color_for("04aa0001") == &"red", "The scanned UID has exactly its new owner.")
	_expect(tags.color_for("04bb0002") == &"", "The old red sticker is intentionally retired.")
	_expect(not tags.bound_colors().has(&"orange"), "The old owner is no longer a bound colour.")
	_expect(tags.save_file(path) == OK, "Explicit reassignment merges successfully into the old file.")

	var saved := TagBindings.new()
	_expect(saved.load_file(path) == OK, "Reassigned labels survive a fresh load.")
	_expect(saved.color_for("04aa0001") == &"red" and saved.color_for("04bb0002") == &"",
		"Merge does not resurrect either obsolete assignment.")
	_expect(saved.color_for("04cc0003") == &"blue", "Skipping a different hue preserves its tag.")
	_expect(saved.color_for("04dd0004") == &"violet_light",
		"Skipping shade prompts preserves their existing tags.")
	_expect(saved.uid_to_color.size() == 3, "Reassignment cannot leave duplicate colour owners.")
	var config := ConfigFile.new()
	_expect(config.load(path) == OK, "The reassignment file is a normal ConfigFile.")
	_expect(config.get_value("unrelated", "keep_me", "") == "retained",
		"Explicit relabeling still preserves unrelated settings.")

	var partial := TagBindings.new()
	_expect(partial.bind_tag("04cc0003", &"yellow", true) == OK,
		"An explicit prompt also authorizes a UID outside a partial in-memory palette.")
	_expect(partial.save_file(path) == OK, "Only that explicitly selected stored owner is replaced.")
	_expect(partial.color_for("04cc0003") == &"yellow"
		and partial.color_for("04aa0001") == &"red",
		"Partial reassignment preserves other stored hues.")


func _test_reassignment_chains() -> void:
	var path := _fixture_path("reassignment_chain")
	_seed_reassignment_file(path)
	var tags := TagBindings.new()
	_expect(tags.load_file(path) == OK, "The chain fixture loads.")
	_expect(tags.bind_tag("04aa0001", &"red", true) == OK, "The first prompt relabels orange.")
	_expect(tags.bind_tag("04ee0005", &"red") == OK, "Red can subsequently move to another sticker.")
	_expect(tags.save_file(path) == OK, "Multiple unsaved replacements merge in order.")
	_expect(tags.color_for("04aa0001") == &"" and tags.color_for("04bb0002") == &"",
		"Neither the old orange nor the old red assignment can reappear after red moves again.")
	_expect(tags.color_for("04ee0005") == &"red", "Only the final red sticker remains.")

	var config := ConfigFile.new()
	_expect(config.load(path) == OK, "The saved chain can receive an independent new binding.")
	config.set_value(TagBindings.SECTION, "04aa0001", "yellow")
	_expect(config.save(path) == OK, "An independently relabeled retired UID is stored.")
	_expect(tags.bind_tag("04aa0001", &"green") == OK,
		"The session has not yet observed that independent disk binding.")
	var before := FileAccess.get_file_as_string(path)
	_expect(tags.save_file(path) == ERR_ALREADY_EXISTS,
		"A successful save consumes reassignment permission rather than granting it forever.")
	_expect(FileAccess.get_file_as_string(path) == before, "The new disk owner remains protected.")

	_seed_reassignment_file(path)
	_expect(tags.load_file(path) == OK, "A successful load replaces pending changes on the same object.")
	_expect(tags.bind_tag("04ee0005", &"red") == OK, "An ordinary replacement retires the old red UID.")
	_expect(tags.bind_tag("04ee0005", &"orange", true) == OK,
		"A later explicit prompt may relabel the newly bound sticker.")
	_expect(tags.save_file(path) == OK, "A colour that disappears during roll call stays unbound.")
	_expect(tags.color_for("04aa0001") == &"" and tags.color_for("04bb0002") == &"",
		"Merge cannot resurrect a retired colour just because it has no replacement now.")
	_expect(tags.color_for("04ee0005") == &"orange" and not tags.bound_colors().has(&"red"),
		"The final palette contains actual final assignments, not historical owners.")

	_seed_reassignment_file(path)
	_expect(tags.load_file(path) == OK, "The ordinary-replacement fixture loads.")
	_expect(tags.bind_tag("04ee0005", &"red") == OK, "Red moves without blanket UID reassignment.")
	config = ConfigFile.new()
	_expect(config.load(path) == OK, "The old UID can be independently relabeled on disk.")
	config.set_value(TagBindings.SECTION, "04bb0002", "yellow")
	_expect(config.save(path) == OK, "The unrelated new owner saves.")
	_expect(tags.save_file(path) == OK, "A normal replacement preserves a different unseen owner.")
	_expect(tags.color_for("04bb0002") == &"yellow" and tags.color_for("04ee0005") == &"red",
		"Ordinary retirement removes only the known former owner, not an unrelated new binding.")


func _test_reassignment_read_guard() -> void:
	var path := _fixture_path("reassignment_guard")
	_seed_reassignment_file(path)
	var tags := TagBindings.new()
	_expect(tags.load_file(path) == OK, "The guarded object starts with a good physical palette.")
	_write_text(path, "[tags]\n\"keyboard:red\"=\"red\"\n")
	var before := FileAccess.get_file_as_string(path)
	_expect(tags.load_file(path) == ERR_INVALID_DATA, "A failed read locks that same object.")
	_expect(tags.bind_tag("04aa0001", &"red", true) == OK,
		"Prompted tags may still work in memory while a save path is protected.")
	_expect(tags.color_for("04aa0001") == &"red" and tags.color_for("04bb0002") == &"",
		"The valid in-memory reassignment remains usable.")
	_expect(tags.save_file(path) == ERR_INVALID_DATA, "Reassignment never bypasses the failed-read guard.")
	_expect(FileAccess.get_file_as_string(path) == before, "The failed-read file remains untouched.")


func _seed_reassignment_file(path: String) -> void:
	var config := ConfigFile.new()
	var bindings := {
		"04aa0001": "orange", "04bb0002": "red",
		"04cc0003": "blue", "04dd0004": "violet_light",
	}
	for uid: String in bindings:
		config.set_value(TagBindings.SECTION, uid, bindings[uid])
	config.set_value("unrelated", "keep_me", "retained")
	_expect(config.save(path) == OK, "The explicitly named reassignment fixture saves.")


func _test_failed_reads() -> void:
	var path := _fixture_path("corrupt")
	var missing_path := _fixture_path("missing")
	var tags := TagBindings.new()
	tags.bind_tag("04000001", &"red")
	_expect(tags.load_file(missing_path) == ERR_FILE_NOT_FOUND,
		"A first-run missing save is distinguishable from corruption.")
	_expect(tags.color_for("04000001") == &"red", "A missing file retains the good memory map.")
	_expect(tags.save_file(missing_path) == OK, "An absent first-run file can be created.")
	_write_text(path, "[tags\nbroken")
	var before := FileAccess.get_file_as_string(path)
	_expect(tags.load_file(path) == ERR_PARSE_ERROR, "Malformed ConfigFile syntax is reported.")
	_expect(tags.color_for("04000001") == &"red", "A malformed read retains the prior good map.")
	_expect(tags.save_file(path) != OK, "A failed-read path is locked against a later save.")
	_expect(tags.save_file(ProjectSettings.globalize_path(path)) != OK,
		"A path alias cannot bypass the failed-read lock.")
	_expect(FileAccess.get_file_as_string(path) == before, "Corrupt input is not overwritten.")
	var repaired := ConfigFile.new()
	repaired.set_value(TagBindings.SECTION, "04000002", "blue")
	_expect(repaired.save(path) == OK, "The fixture can be explicitly repaired.")
	_expect(tags.save_file(path) != OK, "An external repair still requires an explicit good load.")
	_expect(tags.load_file(path) == OK, "Loading the repaired map clears the failed-read lock.")
	_expect(tags.color_for("04000002") == &"blue", "The repaired map replaces the memory map.")
	_expect(tags.save_file(path) == OK, "Saving is allowed after a successful repair load.")

	_write_text(path, "[tags]\n\"key:red\"=\"red\"\n")
	var unread := TagBindings.new()
	unread.bind_tag("04000003", &"green")
	before = FileAccess.get_file_as_string(path)
	_expect(unread.save_file(path) == ERR_INVALID_DATA,
		"Save itself validates the old file rather than replacing unread bad data.")
	_expect(FileAccess.get_file_as_string(path) == before, "Read-before-merge failure is non-destructive.")


func _test_invalid_maps() -> void:
	var path := _fixture_path("invalid")
	var cases: Array[Dictionary] = [
		{"04000001": "cyan"},
		{"04000001": 7},
		{"0400000A": "red", "0400000a": "blue"},
		{"04000001": "red", "04000002": "red"},
		{"04000001\n": "red"},
	]
	for raw: Dictionary in cases:
		var config := ConfigFile.new()
		for uid: String in raw:
			config.set_value(TagBindings.SECTION, uid, raw[uid])
		_expect(config.save(path) == OK, "A malformed-map fixture saves syntactically.")
		var tags := TagBindings.new()
		tags.bind_tag("04000003", &"yellow")
		var before := tags.uid_to_color.duplicate()
		_expect(tags.load_file(path) == ERR_INVALID_DATA,
			"Unknown, mistyped, malformed and non-unique bindings must fail the entire read.")
		_expect(tags.uid_to_color == before, "No valid prefix of a malformed map leaks into memory.")
		_expect(tags.save_file(path) == ERR_INVALID_DATA, "The malformed-map path remains protected.")

	var injected := TagBindings.new()
	injected.uid_to_color = {"04000001": &"red", "04000002": &"red"}
	_expect(injected.save_file(_fixture_path("invalid_memory")) == ERR_INVALID_DATA,
		"Direct public dictionary mutation cannot persist duplicate colours.")


func _fixture_path(label: String) -> String:
	var path := "user://lazer_nfc_bindings_test_%d_%s.tmp.cfg" % [OS.get_process_id(), label]
	if FileAccess.file_exists(path):
		_expect(false, "A regression must not overwrite an existing fixture.")
		return ""
	_paths.append(path)
	return path


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "The named malformed fixture can be opened.")
	if file == null:
		return
	file.store_string(text)
	file.close()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
