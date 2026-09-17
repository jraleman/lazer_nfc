@tool
extends EditorPlugin

## Register once in the host; only the tagged Android preset receives the native library.

var _export_plugin: AndroidReaderExport


func _enter_tree() -> void:
	_export_plugin = AndroidReaderExport.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class AndroidReaderExport extends EditorExportPlugin:
	const FEATURE := "lazer_nfc"
	const AAR_PATH := "res://games/lazer_nfc/android/bin/lazer-nfc-release.aar"
	const BUILD_MESSAGE := (
		"LaZer NFC requires games/lazer_nfc/android/bin/lazer-nfc-release.aar. "
		+ "Run android\\gradlew.bat --no-daemon clean stageRelease from its directory; "
		+ "see games/lazer_nfc/android/README.md for the SDK/JDK prerequisites."
	)

	var _features := PackedStringArray()

	func _get_name() -> String:
		return "LazerNfc"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _export_begin(
		features: PackedStringArray, _debug: bool, _path: String, _flags: int
	) -> void:
		_features = features
		var platform := get_export_platform()
		if _is_nfc_export(platform) and not FileAccess.file_exists(AAR_PATH):
			platform.add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR,
				"LaZer NFC reader", BUILD_MESSAGE)
			push_error(BUILD_MESSAGE)

	func _export_end() -> void:
		_features = PackedStringArray()

	func _get_export_options_overrides(platform: EditorExportPlatform) -> Dictionary:
		if _is_nfc_export(platform):
			return {"gradle_build/use_gradle_build": true}
		return {}

	func _get_android_libraries(
		platform: EditorExportPlatform, _debug: bool
	) -> PackedStringArray:
		if not _is_nfc_export(platform):
			return PackedStringArray()
		# Keep the required dependency even when absent. Filtering it out would
		# let Gradle produce an apparently NFC-capable APK without the reader.
		if not FileAccess.file_exists(AAR_PATH):
			platform.add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR,
				"LaZer NFC reader", BUILD_MESSAGE)
		return PackedStringArray([AAR_PATH])

	func _is_nfc_export(platform: EditorExportPlatform) -> bool:
		if not platform is EditorExportPlatformAndroid:
			return false
		var preset := get_export_preset()
		if preset != null:
			for feature: String in preset.get_custom_features().split(",", false):
				if feature.strip_edges() == FEATURE:
					return true
			return false
		return _features.has(FEATURE)
