extends Node

## A scene-owned reader with explicit callback epochs, including deferred resume work.

signal tag_scanned(uid: String, age_ms: int)
signal availability_changed(available: bool, reason: String)
signal reader_error(message: String)

const OPTIONS = preload("res://games/lazer_nfc/lazer_nfc_options.gd")
const TagBindings = preload("res://games/lazer_nfc/run/tag_bindings.gd")
const PLUGIN_NAME := "LazerNfc"

var _plugin: Object
var _clock_msec: Callable
var _available := false
var _reason := "no_plugin"
var _requested := false
var _active := false
var _application_active := true
var _generation := 0
var _start_queued := false
var _seen_ms: Dictionary[String, int] = {}
var _connected := false


func _init(plugin: Object = null, clock_msec: Callable = Callable()) -> void:
	process_mode = PROCESS_MODE_PAUSABLE
	_plugin = plugin
	_clock_msec = clock_msec if clock_msec.is_valid() else Time.get_ticks_msec


func _ready() -> void:
	if _plugin == null and Engine.has_singleton(PLUGIN_NAME):
		_plugin = Engine.get_singleton(PLUGIN_NAME)
	if _plugin != null:
		for method: StringName in [
			&"is_supported", &"is_enabled", &"enable_reader", &"disable_reader",
		]:
			if not _plugin.has_method(method):
				_reject_plugin()
				return
		for signal_name: StringName in [&"tag_discovered", &"adapter_state", &"reader_error"]:
			if not _plugin.has_signal(signal_name):
				_reject_plugin()
				return
		_plugin.connect(&"tag_discovered", _on_tag_discovered)
		_plugin.connect(&"adapter_state", _on_adapter_state)
		_plugin.connect(&"reader_error", _on_reader_error)
		_connected = true
	_refresh_availability(true)
	_queue_start()


## Availability describes the device, not whether the game has requested its reader.
func available() -> bool:
	return _available


## No reader starts in a menu merely because the Android activity resumed.
func start() -> void:
	_requested = true
	if not is_inside_tree():
		return
	_refresh_availability()
	_queue_start()


## Invalidate callbacks synchronously, before the native UI-thread stop is serviced.
func stop() -> void:
	_requested = false
	_suspend_reader()


## Drain both render/JNI and deferred callbacks before accepting an identical resumed tag.
func reset_debounce() -> void:
	_suspend_reader()
	_queue_start()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_suspend_reader()
	elif what == NOTIFICATION_UNPAUSED:
		_queue_start()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		_application_active = false
		_suspend_reader()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_application_active = true
		if is_inside_tree():
			_refresh_availability()
			_queue_start()


func _exit_tree() -> void:
	stop()
	if _connected and is_instance_valid(_plugin):
		_plugin.disconnect(&"tag_discovered", _on_tag_discovered)
		_plugin.disconnect(&"adapter_state", _on_adapter_state)
		_plugin.disconnect(&"reader_error", _on_reader_error)
	_connected = false


func _queue_start() -> void:
	if not _can_start() or _active or _start_queued:
		return
	_generation += 1
	_start_queued = true
	# One frame barrier drains old native events before the deferred activation.
	get_tree().process_frame.connect(_after_frame.bind(_generation), CONNECT_ONE_SHOT)


func _after_frame(generation: int) -> void:
	_activate_reader.call_deferred(generation)


func _activate_reader(generation: int) -> void:
	if generation != _generation:
		return
	_start_queued = false
	if not _can_start():
		return
	_seen_ms.clear()
	_active = true
	_plugin.call(&"enable_reader")


func _can_start() -> bool:
	return (
		_requested and _available and _connected and is_inside_tree()
		and not get_tree().paused and _application_active
	)


func _suspend_reader() -> void:
	_generation += 1
	_active = false
	_start_queued = false
	if _connected and is_instance_valid(_plugin):
		_plugin.call(&"disable_reader")


func _on_tag_discovered(uid: String, age_ms: int) -> void:
	if not _active or not is_inside_tree() or get_tree().paused:
		return
	# The native plugin emits on Godot's render thread; capture the epoch now,
	# not in a CONNECT_DEFERRED handler that could belong to a later window.
	_handle_scan.call_deferred(uid, age_ms, int(_clock_msec.call()), _generation)


func _handle_scan(uid: String, age_ms: int, arrived_ms: int, generation: int) -> void:
	if generation != _generation or not _active or not _can_start():
		return
	var canonical := TagBindings.canonical_uid(uid)
	if canonical.is_empty() or age_ms < 0:
		_handle_error("The NFC reader returned an invalid tag or age.", generation)
		return
	for previous_uid: String in _seen_ms.keys():
		if arrived_ms - _seen_ms[previous_uid] >= OPTIONS.NFC_DEBOUNCE_MS:
			_seen_ms.erase(previous_uid)
	if _seen_ms.has(canonical):
		return
	_seen_ms[canonical] = arrived_ms
	# Native age already includes the 80 ms RF estimate. Only add our own delay;
	# Android elapsedRealtime and Godot ticks are never compared as timestamps.
	var deferred_ms := maxi(0, int(_clock_msec.call()) - arrived_ms)
	tag_scanned.emit(canonical, age_ms + deferred_ms)


func _on_adapter_state(enabled: bool) -> void:
	if not is_inside_tree():
		return
	if not enabled and _connected and bool(_plugin.call(&"is_supported")):
		_set_availability(false, "disabled")
	else:
		_refresh_availability()


func _on_reader_error(message: String) -> void:
	_handle_error.call_deferred(message, _generation)


func _handle_error(message: String, generation: int) -> void:
	if generation != _generation or not is_inside_tree():
		return
	_set_availability(false, "reader_error")
	reader_error.emit(message)


func _refresh_availability(force: bool = false) -> void:
	if not _connected:
		_set_availability(false, "no_plugin", force)
	elif not bool(_plugin.call(&"is_supported")):
		_set_availability(false, "no_hardware", force)
	elif not bool(_plugin.call(&"is_enabled")):
		_set_availability(false, "disabled", force)
	else:
		_set_availability(true, "", force)


func _set_availability(value: bool, reason: String, force: bool = false) -> void:
	if not value:
		stop()
	if not force and _available == value and _reason == reason:
		return
	_available = value
	_reason = reason
	availability_changed.emit(value, reason)


func _reject_plugin() -> void:
	_plugin = null
	_set_availability(false, "invalid_plugin", true)
	reader_error.emit("The LazerNfc plugin does not implement the required reader API.")
