@tool
extends EditorPlugin

## Register once in the host; only the tagged iOS preset receives the Core NFC plugin.

var _export_plugin: IosReaderExport


func _enter_tree() -> void:
	_export_plugin = IosReaderExport.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class IosReaderExport extends EditorExportPlugin:
	const FEATURE := "lazer_nfc"
	## Godot only scans the host project's own ios/plugins folder, one level deep,
	## so build_plugin.sh stages the game-owned artefacts here.
	const PLUGIN_DIR := "res://ios/plugins/lazer_nfc"
	const GDIP_PATH := PLUGIN_DIR + "/lazer_nfc.gdip"
	const FRAMEWORKS := ["lazer_nfc.release.xcframework", "lazer_nfc.debug.xcframework"]
	const ENTITLEMENT_KEY := "com.apple.developer.nfc.readersession.formats"
	const ENTITLEMENT_XML := (
		"\t<key>" + ENTITLEMENT_KEY + "</key>\n"
		+ "\t<array>\n\t\t<string>TAG</string>\n\t</array>"
	)
	const BUILD_MESSAGE := (
		"LaZer NFC requires the Core NFC plugin staged in ios/plugins/lazer_nfc. "
		+ "On macOS run games/lazer_nfc/ios/build_plugin.sh; "
		+ "see games/lazer_nfc/ios/README.md for the Xcode/Godot source prerequisites."
	)
	const PROFILE_MESSAGE := (
		"Enable the \"Near Field Communication Tag Reading\" capability on App ID "
		+ "com.deskcansaw.lazernfc and re-download the provisioning profile, "
		+ "otherwise the signed build is rejected at install time."
	)

	var _features := PackedStringArray()

	func _get_name() -> String:
		return "LazerNfcIos"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformIOS

	func _export_begin(
		features: PackedStringArray, _debug: bool, _path: String, _flags: int
	) -> void:
		_features = features
		var platform := get_export_platform()
		if not _is_nfc_export(platform):
			return
		var missing := _missing_artifacts()
		if not missing.is_empty():
			var message := BUILD_MESSAGE + " Missing: " + ", ".join(missing) + "."
			platform.add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR,
				"LaZer NFC reader", message)
			push_error(message)
		platform.add_message(EditorExportPlatform.EXPORT_MESSAGE_INFO,
			"LaZer NFC reader", PROFILE_MESSAGE)

	func _export_end() -> void:
		_features = PackedStringArray()

	func _get_export_options_overrides(platform: EditorExportPlatform) -> Dictionary:
		# Only the plugin toggle is forced. entitlements/additional is left alone
		# because reading it here to append would recurse through this override.
		if _is_nfc_export(platform):
			return {"plugins/LazerNfc": true}
		return {}

	## Godot offers no API to contribute entitlements, and a build whose
	## entitlement is missing crashes the moment a scan starts. Repair the
	## generated file instead of trusting every preset to carry the XML.
	func _end_generate_apple_embedded_project(
		path: String, _will_build_archive: bool
	) -> void:
		var platform := get_export_platform()
		if not _is_nfc_export(platform):
			return
		var entitlements := _find_entitlements(path)
		if entitlements.is_empty():
			platform.add_message(EditorExportPlatform.EXPORT_MESSAGE_WARNING,
				"LaZer NFC reader",
				"No .entitlements file was generated, so the NFC reader entitlement "
				+ "could not be verified. Add it in Xcode before signing.")
			return
		var text := FileAccess.get_file_as_string(entitlements)
		if text.contains(ENTITLEMENT_KEY):
			return
		var patched := _patch_entitlements(text)
		if patched.is_empty():
			platform.add_message(EditorExportPlatform.EXPORT_MESSAGE_WARNING,
				"LaZer NFC reader",
				"Could not parse " + entitlements + "; add " + ENTITLEMENT_KEY
				+ " manually before signing.")
			return
		var file := FileAccess.open(entitlements, FileAccess.WRITE)
		if file == null:
			platform.add_message(EditorExportPlatform.EXPORT_MESSAGE_WARNING,
				"LaZer NFC reader",
				"Could not write " + entitlements + "; add " + ENTITLEMENT_KEY
				+ " manually before signing.")
			return
		file.store_string(patched)
		file.close()
		platform.add_message(EditorExportPlatform.EXPORT_MESSAGE_INFO,
			"LaZer NFC reader",
			"Added the NFC reader entitlement to " + entitlements.get_file() + ".")

	func _missing_artifacts() -> PackedStringArray:
		var missing := PackedStringArray()
		if not FileAccess.file_exists(GDIP_PATH):
			missing.append(GDIP_PATH.trim_prefix("res://"))
		for name: String in FRAMEWORKS:
			if not DirAccess.dir_exists_absolute(PLUGIN_DIR + "/" + name):
				missing.append(name)
		return missing

	static func _find_entitlements(path: String) -> String:
		if path.is_empty():
			return ""
		# The export path may name the .ipa or the directory that receives the
		# Xcode project, so start from whichever of the two actually exists.
		var root := path if DirAccess.dir_exists_absolute(path) else path.get_base_dir()
		return _scan_entitlements(root, 2)

	static func _scan_entitlements(dir_path: String, depth: int) -> String:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			return ""
		for file: String in dir.get_files():
			if file.get_extension() == "entitlements":
				return dir_path.path_join(file)
		if depth <= 0:
			return ""
		for sub: String in dir.get_directories():
			var found := _scan_entitlements(dir_path.path_join(sub), depth - 1)
			if not found.is_empty():
				return found
		return ""

	static func _patch_entitlements(text: String) -> String:
		if text.contains(ENTITLEMENT_KEY):
			return text
		var close := text.rfind("</dict>")
		if close < 0:
			return ""
		return text.substr(0, close) + ENTITLEMENT_XML + "\n" + text.substr(close)

	func _is_nfc_export(platform: EditorExportPlatform) -> bool:
		if not platform is EditorExportPlatformIOS:
			return false
		var preset := get_export_preset()
		if preset != null:
			for feature: String in preset.get_custom_features().split(",", false):
				if feature.strip_edges() == FEATURE:
					return true
			return false
		return _features.has(FEATURE)
