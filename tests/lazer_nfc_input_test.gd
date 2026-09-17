extends SceneTree

## Real input adapters are exercised without an Android singleton, wall clock sleeps or saves.

const NfcSource = preload("res://games/lazer_nfc/input/nfc_source.gd")
const KeySource = preload("res://games/lazer_nfc/input/key_source.gd")
const MotionSource = preload("res://games/lazer_nfc/input/motion_source.gd")
const Palette = preload("res://games/lazer_nfc/run/palette.gd")

var _failures: Array[String] = []
var _checks := 0


class FakeClock extends RefCounted:
	var now := 1000

	func milliseconds() -> int:
		return now


class FakePlugin extends RefCounted:
	signal tag_discovered(uid: String, age_ms: int)
	signal adapter_state(enabled: bool)
	signal reader_error(message: String)

	var supported := true
	var enabled := true
	var reading := false
	var starts := 0
	var stops := 0

	func is_supported() -> bool:
		return supported

	func is_enabled() -> bool:
		return enabled

	func enable_reader() -> void:
		reading = true
		starts += 1

	func disable_reader() -> void:
		reading = false
		stops += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_keys()
	_test_motion()
	await _test_availability()
	await _test_reader_lifecycle()
	if _failures.is_empty():
		print("lazer_nfc_input_test: %d checks passed." % _checks)
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_keys() -> void:
	var keys := KeySource.new()
	var actions: Array[StringName] = []
	for index in 7:
		actions.append(StringName("lz_color_%d" % (index + 1)))
	actions.append_array([&"lz_shade_dark", &"lz_shade_light", &"lz_confirm"])
	var saved: Dictionary = {}
	for index in actions.size():
		var action := actions[index]
		var existed := InputMap.has_action(action)
		saved[action] = {
			"existed": existed,
			"events": InputMap.action_get_events(action) if existed else [],
			"strength": Input.get_action_strength(action) if existed else 0.0,
		}
		if not existed:
			InputMap.add_action(action)
		Input.action_release(action)
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, _key(KEY_F1 + index))

	for index in 7:
		_expect(keys.color_from_event(_key(KEY_F1 + index), false) == Palette.HUES[index],
			"Colour events follow live actions in stable spectrum order.")
	var event := _key(KEY_F1)
	event.echo = true
	_expect(keys.color_from_event(event, true) == &"", "Key repeats never become answers.")
	event.echo = false
	event.pressed = false
	_expect(keys.color_from_event(event, true) == &"", "Key releases never become answers.")
	_expect(keys.color_from_event(_key(KEY_F12), true) == &"", "Unbound keys are ignored.")
	Input.action_press(&"lz_shade_dark")
	_expect(keys.color_from_event(_key(KEY_F1), true) == &"red_dark", "The held dark action is live.")
	_expect(keys.color_from_event(_key(KEY_F1), false) == &"red", "Base mode ignores shade actions.")
	Input.action_press(&"lz_shade_light")
	_expect(keys.color_from_event(_key(KEY_F1), true) == &"red", "Both shades held yield neutral base.")
	Input.action_release(&"lz_shade_dark")
	_expect(keys.color_from_event(_key(KEY_F1), true) == &"red_light", "The held light action is live.")
	Input.action_release(&"lz_shade_light")
	InputMap.action_erase_events(&"lz_color_1")
	InputMap.action_add_event(&"lz_color_1", _key(KEY_A))
	_expect(keys.color_from_event(_key(KEY_A), false) == &"red", "Rebinding takes effect immediately.")
	_expect(keys.color_from_event(_key(KEY_F1), false) == &"", "The previous key stops matching.")
	_expect(keys.confirm_pressed(_key(KEY_F10)), "Confirm uses its declared current action.")
	event = _key(KEY_F10)
	event.echo = true
	_expect(not keys.confirm_pressed(event), "An echo cannot repeatedly confirm.")
	event.echo = false
	event.pressed = false
	_expect(not keys.confirm_pressed(event), "A release cannot confirm.")
	for action: StringName in actions:
		Input.action_release(action)
		InputMap.action_erase_events(action)
		if bool(saved[action]["existed"]):
			for original: InputEvent in saved[action]["events"]:
				InputMap.action_add_event(action, original)
			var strength := float(saved[action]["strength"])
			if strength > 0.0:
				Input.action_press(action, strength)
		else:
			InputMap.erase_action(action)


func _test_motion() -> void:
	var acceleration := Input.get_accelerometer()
	var gravity := Input.get_gravity()
	var motion := MotionSource.new()
	Input.set_accelerometer(Vector3.ZERO)
	Input.set_gravity(Vector3.ZERO)
	motion.sample()
	_expect(is_zero_approx(motion.take_peak()), "Missing sensors contribute zero, never a penalty.")
	Input.set_gravity(Vector3(0.0, 9.8, 0.0))
	Input.set_accelerometer(Vector3(3.0, 9.8, 0.0))
	motion.sample()
	Input.set_accelerometer(Vector3(0.0, 13.8, 0.0))
	motion.sample()
	_expect(is_equal_approx(motion.peek_peak(), 4.0), "Audio can inspect the greatest linear acceleration.")
	_expect(is_equal_approx(motion.take_peak(), 4.0), "An answer consumes the greatest linear acceleration.")
	_expect(is_zero_approx(motion.take_peak()), "Momentum cannot be consumed twice.")
	motion.sample()
	motion.reset()
	_expect(is_zero_approx(motion.peek_peak()), "Reset clears pre-pause momentum.")
	Input.set_accelerometer(acceleration)
	Input.set_gravity(gravity)


func _test_availability() -> void:
	for reason: String in ["no_plugin", "no_hardware", "disabled"]:
		var plugin: FakePlugin
		if reason != "no_plugin":
			plugin = FakePlugin.new()
			plugin.supported = reason != "no_hardware"
			plugin.enabled = reason != "disabled"
		var reader := NfcSource.new(plugin)
		var states: Array[Dictionary] = []
		var errors: Array[String] = []
		reader.availability_changed.connect(func(value: bool, why: String) -> void:
			states.append({"available": value, "reason": why}))
		reader.reader_error.connect(func(message: String) -> void: errors.append(message))
		get_root().add_child(reader)
		_expect(not reader.available(), "Unavailable hardware is not reported as usable.")
		_expect(states == [{"available": false, "reason": reason}],
			"Connecting before add_child receives the exact initial unavailable reason.")
		reader.start()
		await _settle()
		_expect(errors.is_empty(), "An absent plugin, adapter or enabled radio is not a reader error.")
		if plugin != null:
			_expect(not plugin.reading, "An unavailable source cannot start its native reader.")
		reader.free()


func _test_reader_lifecycle() -> void:
	var plugin := FakePlugin.new()
	var clock := FakeClock.new()
	var reader := NfcSource.new(plugin, clock.milliseconds)
	var host := Node.new()
	host.process_mode = Node.PROCESS_MODE_ALWAYS
	get_root().add_child(host)
	var scans: Array[Dictionary] = []
	var errors: Array[String] = []
	var states: Array[Dictionary] = []
	reader.tag_scanned.connect(func(uid: String, age: int) -> void:
		scans.append({"uid": uid, "age": age}))
	reader.availability_changed.connect(func(value: bool, why: String) -> void:
		states.append({"available": value, "reason": why}))
	reader.reader_error.connect(func(message: String) -> void: errors.append(message))
	host.add_child(reader)
	_expect(reader.available(), "A supported enabled adapter is available immediately.")
	_expect(plugin.starts == 0, "Ready and availability alone do not enable NFC in menus.")
	plugin.tag_discovered.emit("04AA0001", 80)
	await _settle()
	_expect(scans.is_empty(), "Unrequested scans are ignored.")
	reader.start()
	_expect(not plugin.reading, "Starting first drains pending callbacks.")
	reader.stop()
	await _settle()
	_expect(plugin.starts == 0, "Stopping during the activation barrier cancels the native start.")
	reader.start()
	await _settle()
	_expect(plugin.reading, "The requested active source enables its native reader.")
	reader.start()
	await _settle()
	_expect(plugin.starts == 1, "Repeated start calls do not reopen an active native reader.")
	plugin.tag_discovered.emit("04AA0001", 93)
	clock.now = 1017
	await _settle()
	_expect(scans == [{"uid": "04aa0001", "age": 110}],
		"Age adds only deferred time to native age, not a second RF compensation or epoch offset.")
	clock.now = 1100
	plugin.tag_discovered.emit("04aa0001", 80)
	await _settle()
	_expect(scans.size() == 1, "The same canonical UID is debounced below 500 ms.")
	clock.now = 1200
	plugin.tag_discovered.emit("04bb0002", 80)
	await _settle()
	_expect(scans.size() == 2, "A different UID is never suppressed by another tag's debounce.")
	clock.now = 1499
	plugin.tag_discovered.emit("04aa0001", 80)
	await _settle()
	_expect(scans.size() == 2, "Interleaving another tag cannot bypass a UID's 500 ms debounce.")
	clock.now = 1500
	plugin.tag_discovered.emit("04aa0001", 80)
	await _settle()
	_expect(scans.size() == 3, "Exactly 500 ms permits a repeat.")

	clock.now = 1600
	plugin.tag_discovered.emit("04cc0003", 80)
	reader.stop()
	reader.start()
	plugin.tag_discovered.emit("04dd0004", 80)
	await _settle()
	_expect(scans.size() == 3, "Stop/start discards both already-deferred and draining callbacks.")
	plugin.tag_discovered.emit("04aa0001", 80)
	await _settle()
	_expect(scans.size() == 4, "A new active window accepts the same UID after draining.")
	plugin.tag_discovered.emit("04cc0003", 80)
	reader.reset_debounce()
	await _settle()
	_expect(scans.size() == 4, "Reset is an epoch boundary, not just an emptied debounce map.")

	plugin.tag_discovered.emit("04dd0004", 80)
	paused = true
	_expect(not plugin.reading, "Tree pause disables the source even under an always-processing host.")
	plugin.tag_discovered.emit("04ee0005", 80)
	await _settle()
	paused = false
	await _settle()
	_expect(scans.size() == 4, "Paused scans and pre-pause deferred scans cannot reach a resumed window.")
	plugin.tag_discovered.emit("04aa0001", 80)
	await _settle()
	_expect(scans.size() == 5, "Resume resets debounce after the callback barrier.")

	plugin.tag_discovered.emit("04dd0004", 80)
	reader.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_expect(not plugin.reading, "Android application pause independently disables the source.")
	plugin.tag_discovered.emit("04ee0005", 80)
	reader.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await _settle()
	_expect(scans.size() == 5 and plugin.reading,
		"Application resume drains pre-pause callbacks before restoring an outstanding request.")

	var starts_before_restore := plugin.starts
	plugin.tag_discovered.emit("04dd0004", 80)
	plugin.enabled = false
	plugin.adapter_state.emit(false)
	_expect(not reader.available() and not plugin.reading, "Turning NFC off stops the active reader.")
	_expect(states.back()["reason"] == "disabled", "A disabled radio reaches the game's fallback UI.")
	reader.start()
	await _settle()
	_expect(plugin.starts == starts_before_restore,
		"Calling start while unavailable cannot reserve automatic restoration.")
	plugin.enabled = true
	plugin.adapter_state.emit(true)
	await _settle()
	_expect(reader.available() and not plugin.reading,
		"Restored availability is a notification, not permission to reopen the reader.")
	reader.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	reader.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	paused = true
	paused = false
	reader.reset_debounce()
	plugin.tag_discovered.emit("04ee0005", 80)
	await _settle()
	_expect(plugin.starts == starts_before_restore and scans.size() == 5,
		"No lifecycle or debounce callback can resurrect a request revoked by lost availability.")
	reader.start()
	await _settle()
	_expect(plugin.reading and plugin.starts == starts_before_restore + 1,
		"A fresh explicit parent start reopens the restored reader.")

	plugin.adapter_state.emit(false)
	_expect(not reader.available() and not plugin.reading,
		"A queued off event is honored even when the adapter getter already reports on.")
	plugin.adapter_state.emit(true)
	await _settle()
	_expect(reader.available() and not plugin.reading,
		"A quick off/on cycle still requires a fresh parent decision.")
	var parent_start := func(value: bool, _reason: String) -> void:
		if value:
			reader.start()
	reader.availability_changed.connect(parent_start)
	plugin.enabled = false
	plugin.adapter_state.emit(false)
	plugin.enabled = true
	plugin.adapter_state.emit(true)
	await _settle()
	_expect(plugin.reading, "The parent can explicitly start from the restored-availability callback.")
	reader.availability_changed.disconnect(parent_start)
	reader.stop()
	var starts := plugin.starts
	reader.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	reader.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	paused = true
	paused = false
	plugin.adapter_state.emit(true)
	await _settle()
	_expect(plugin.starts == starts and not plugin.reading,
		"App resume, tree resume and radio changes cannot undo an explicit game stop.")

	reader.start()
	await _settle()
	plugin.reader_error.emit("Reader mode was denied.")
	await _settle()
	_expect(errors == ["Reader mode was denied."], "Native failures are surfaced explicitly.")
	_expect(not plugin.reading and not reader.available(), "A reader error disables the failed reader.")
	reader.start()
	await _settle()
	plugin.tag_discovered.emit("keyboard:red", 80)
	await _settle()
	_expect(errors.size() == 2 and scans.size() == 5, "Malformed native output is reported, not an answer.")
	reader.start()
	await _settle()
	plugin.tag_discovered.emit("04ee0005", 80)
	host.remove_child(reader)
	_expect(not plugin.reading, "Scene exit always stops the native reader.")
	_expect(not plugin.tag_discovered.is_connected(reader._on_tag_discovered),
		"Scene exit disconnects the native callback.")
	plugin.tag_discovered.emit("04ff0006", 80)
	reader.free()
	host.free()
	await _settle()
	_expect(scans.size() == 5, "A departed scene never handles queued or later scans.")


func _key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func _settle() -> void:
	await process_frame
	await process_frame


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
