extends SceneTree

## Pure contracts for the ten settings, stable controls and all 21 instruments.

const OPTIONS := preload("res://games/lazer_nfc/lazer_nfc_options.gd")
const PALETTE := preload("res://games/lazer_nfc/run/palette.gd")
const MANIFEST := preload("res://scripts/game_manifest.gd")

var _failures := PackedStringArray()
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_tunables()
	_test_bindings()
	_test_feel_constants()
	_test_palette()
	if _failures.is_empty():
		print("LaZer NFC options tests passed (%d checks)." % _checks)
		quit(0)
	else:
		for failure: String in _failures:
			printerr(failure)
		quit(1)


func _test_tunables() -> void:
	_expect(OPTIONS.GAME_ID == "lazer_nfc", "The save/catalog id must stay stable.")
	var keys: Array[String] = [
		OPTIONS.LIVES_KEY, OPTIONS.SCAN_WINDOW_KEY, OPTIONS.RAMP_KEY,
		OPTIONS.START_LENGTH_KEY, OPTIONS.PALETTE_START_KEY, OPTIONS.SHADE_MODE_KEY,
		OPTIONS.TOUCH_PAD_KEY, OPTIONS.HAPTICS_KEY, OPTIONS.VOICE_KEY,
		OPTIONS.REBIND_TAGS_KEY,
	]
	_expect(OPTIONS.TUNABLES.size() == 10, "Exactly ten designed options must ship.")
	_expect(OPTIONS.TUNABLES.get_typed_builtin() == TYPE_DICTIONARY,
		"The manifest requires a typed Array[Dictionary] of tunables.")
	var seen: Array[String] = []
	for option: Dictionary in OPTIONS.TUNABLES:
		var key := str(option.get("key", ""))
		_expect(keys.has(key) and key.begins_with("game/lz_"),
			"Each tunable must use its declared, game-owned key: %s." % key)
		_expect(not seen.has(key), "Tunable keys cannot collide: %s." % key)
		seen.append(key)
		_expect(not str(option.get("title", "")).is_empty(),
			"Every option needs readable title copy: %s." % key)
		_expect(not str(option.get("description", "")).is_empty(),
			"Every option needs meaningful help: %s." % key)
		_expect(not str(option.get("heading", "")).is_empty(),
			"Every option needs a generated settings group: %s." % key)
	_test_slider(OPTIONS.LIVES_KEY, 3.0, 1.0, 5.0, MANIFEST.FORMAT_LIVES)
	_test_slider(OPTIONS.SCAN_WINDOW_KEY, 4.0, 2.0, 6.0, MANIFEST.FORMAT_SECONDS)
	_test_slider(OPTIONS.START_LENGTH_KEY, 3.0, 2.0, 4.0, MANIFEST.FORMAT_COUNT)
	_test_slider(OPTIONS.PALETTE_START_KEY, 4.0, 3.0, 7.0, MANIFEST.FORMAT_COUNT)
	_test_slider(OPTIONS.HAPTICS_KEY, 1.0, 0.0, 1.0, MANIFEST.FORMAT_PERCENT)
	var toggles := {
		OPTIONS.SHADE_MODE_KEY: false, OPTIONS.TOUCH_PAD_KEY: false,
		OPTIONS.VOICE_KEY: true, OPTIONS.REBIND_TAGS_KEY: false,
	}
	for key: String in toggles:
		var option := _option(key)
		_expect(option.get("type") == MANIFEST.OPTION_TOGGLE,
			"%s must use the framework toggle kind." % key)
		_expect(option.get("default") is bool and option.get("default") == toggles[key],
			"%s must have its documented boolean default." % key)
	var ramp := _option(OPTIONS.RAMP_KEY)
	_expect(ramp.get("type") == MANIFEST.OPTION_CHOICE and ramp.get("default") == 1,
		"The named ramp must default to Standard.")
	var choices: Array = ramp.get("choices", [])
	_expect(choices == [
		{"value": 0, "title": "Gentle"},
		{"value": 1, "title": "Standard"},
		{"value": 2, "title": "Steep"},
	], "Ramp values must match the model's Gentle / Standard / Steep indices.")


func _test_slider(
	key: String, initial: float, minimum: float, maximum: float, format: String
) -> void:
	var option := _option(key)
	_expect(option.get("type") == MANIFEST.OPTION_SLIDER,
		"%s must use the framework slider kind." % key)
	_expect_approx(float(option.get("default", -100.0)), initial, "%s default" % key)
	_expect_approx(float(option.get("min", -100.0)), minimum, "%s minimum" % key)
	_expect_approx(float(option.get("max", -100.0)), maximum, "%s maximum" % key)
	_expect(option.get("format") == format, "%s must declare its real units." % key)
	var step := float(option.get("step", 0.0))
	_expect(step > 0.0 and step <= maximum - minimum,
		"%s needs a usable positive step." % key)
	if key in [OPTIONS.LIVES_KEY, OPTIONS.START_LENGTH_KEY, OPTIONS.PALETTE_START_KEY]:
		_expect_approx(step, 1.0, "%s uses whole counts" % key)


func _test_bindings() -> void:
	_expect(OPTIONS.CONTROL_BINDINGS.size() == 10,
		"Seven colour keys, two shade keys and confirm must all be declared.")
	_expect(OPTIONS.CONTROL_BINDINGS.get_typed_builtin() == TYPE_DICTIONARY,
		"Controls must use the manifest's typed dictionary array.")
	_expect(OPTIONS.COLOR_ACTIONS.get_typed_builtin() == TYPE_STRING_NAME,
		"Input sources require a typed StringName action array.")
	_expect(OPTIONS.COLOR_ACTIONS.size() == 7, "The colour row must stay seven keys.")
	var keys: Array[String] = []
	var actions: Array[StringName] = []
	var physical_keys: Array[int] = []
	for index in OPTIONS.CONTROL_BINDINGS.size():
		var binding: Dictionary = OPTIONS.CONTROL_BINDINGS[index]
		var key := str(binding.get("key", ""))
		var action: StringName = binding.get("action", &"")
		var physical := int(binding.get("default", 0))
		_expect(not keys.has(key) and key == "controls/%s" % action,
			"Binding keys must be unique and match their stable action: %s." % key)
		_expect(binding.get("action") is StringName and not actions.has(action),
			"Every action must be an explicitly declared, unique StringName.")
		_expect(physical != 0 and not physical_keys.has(physical),
			"Default physical keys cannot conflict inside LaZer NFC.")
		_expect(binding.get("player") == 0 and not bool(binding.get("movement", false)),
			"These are P1 instrument keys, not shared or movement bindings.")
		_expect(not str(binding.get("heading", "")).is_empty(),
			"Generated control rows need a heading.")
		keys.append(key)
		actions.append(action)
		physical_keys.append(physical)
		if index < 7:
			_expect(action == StringName("lz_color_%d" % (index + 1))
				and action == OPTIONS.COLOR_ACTIONS[index] and physical == KEY_1 + index,
				"Colour key numbering must stay in spectrum order.")
			_expect(binding.get("title") == "%s - %s" % [
				PALETTE.label(PALETTE.HUES[index]), PALETTE.SHAPES[index],
			], "Control labels must name the same geometric shapes as the palette.")
	_expect(actions.has(OPTIONS.DARK_ACTION) and actions.has(OPTIONS.LIGHT_ACTION)
		and actions.has(OPTIONS.CONFIRM_ACTION), "All non-colour actions must be exposed.")
	_expect(physical_keys.slice(7) == [KEY_Q, KEY_E, KEY_SPACE],
		"Shade and confirmation defaults must remain Q, E and Space.")


func _test_feel_constants() -> void:
	_expect(OPTIONS.SEQ_LEN_MAX == 12, "Memory sequences must cap at twelve.")
	_expect(OPTIONS.PALETTE_GROWTH_ROUNDS == [3, 5, 7],
		"New hues activate on rounds three, five and seven.")
	_expect(OPTIONS.ALLOW_REPEAT_FROM_ROUND == 4, "Early tag repeats must be excluded.")
	_expect(OPTIONS.WINDOW_RAMP == [0.1, 0.2, 0.3],
		"Window tightening must match all three named ramps.")
	_expect(OPTIONS.SHOW_RAMP == [0.03, 0.05, 0.08],
		"Show-time tightening must match all three named ramps.")
	var seconds := {
		"round start": [OPTIONS.ROUND_START_TIME, 0.8],
		"show": [OPTIONS.SHOW_TIME, 0.8],
		"show floor": [OPTIONS.SHOW_TIME_MIN, 0.5],
		"show gap": [OPTIONS.SHOW_GAP, 0.3],
		"go gap": [OPTIONS.SHOW_END_TIME, 0.6],
		"window floor": [OPTIONS.SCAN_WINDOW_MIN, 2.0],
		"recall gap": [OPTIONS.RECALL_GAP, 0.5],
		"round recap": [OPTIONS.ROUND_WON_TIME, 1.5],
		"note duration": [OPTIONS.NOTE_DURATION, 0.4],
		"first tick": [OPTIONS.TICK_PERIOD_START, 0.5],
		"last tick": [OPTIONS.TICK_PERIOD_END, 0.12],
		"binding timeout": [OPTIONS.BINDING_TIMEOUT_S, 12.0],
		"maximum event age": [OPTIONS.MAX_ANSWER_AGE_S, 0.23],
	}
	for name_text: String in seconds:
		var values: Array = seconds[name_text]
		_expect_approx(float(values[0]), float(values[1]), "%s seconds" % name_text)
	_expect(OPTIONS.GRACE_MS == 150 and OPTIONS.NFC_LATENCY_COMP_MS == 80
		and OPTIONS.NFC_DEBOUNCE_MS == 500 and OPTIONS.DOUBLE_SCAN_MS == 1500,
		"Physical input timings must retain their documented millisecond units.")
	_expect(OPTIONS.RECALL_GAP >= OPTIONS.NFC_DEBOUNCE_MS / 1000.0,
		"A legitimate repeat must survive source debounce.")
	_expect(OPTIONS.SHOW_TIME_MIN >= OPTIONS.NOTE_DURATION,
		"A shown note must never be shorter than its instrument sample.")
	_expect_approx(OPTIONS.COMBO_STEP, 0.25, "Combo step")
	_expect_approx(OPTIONS.COMBO_MAX, 4.0, "Combo cap")
	_expect_approx(OPTIONS.MOMENTUM_BONUS_MAX, 0.5, "Momentum bonus cap")
	_expect_approx(OPTIONS.MOMENTUM_ENERGY_FULL, 25.0, "Full momentum acceleration")


func _test_palette() -> void:
	_expect(PALETTE.HUES == [
		&"red", &"orange", &"yellow", &"green", &"blue", &"indigo", &"violet",
	], "Hue order must match the stable keyboard spectrum.")
	_expect(PALETTE.GROWTH_ORDER == [
		&"red", &"yellow", &"green", &"blue", &"orange", &"indigo", &"violet",
	], "Growth order must prioritise distinguishable early hues.")
	_expect(PALETTE.SHAPES == [
		&"triangle", &"diamond", &"star", &"circle", &"square", &"hexagon", &"plus",
	], "Presentation needs seven distinct named geometric symbols.")
	_expect(PALETTE.MIDI == [48, 52, 55, 60, 64, 67, 72],
		"The stacked-triad instrument pitches must remain stable.")
	var base_ids := PALETTE.all_ids()
	var full_ids := PALETTE.all_ids(true)
	_expect(base_ids == PALETTE.HUES and full_ids.size() == 21,
		"Base play has seven instruments; advanced play really has 21.")
	_expect(full_ids.get_typed_builtin() == TYPE_STRING_NAME,
		"UID maps and model config require typed StringName colour ids.")
	var names: Array[String] = []
	var swatches: Array[Color] = []
	for id: StringName in full_ids:
		var hue := PALETTE.hue_id(id)
		var shade := PALETTE.shade_index(id)
		_expect(PALETTE.is_valid(id) and PALETTE.HUES.has(hue) and shade in [0, 1, 2],
			"Every advanced id must be a recognised hue and shade: %s." % id)
		_expect(PALETTE.id_for(hue, shade) == id and full_ids.count(id) == 1,
			"Instrument ids must round-trip uniquely: %s." % id)
		var name_text := PALETTE.label(id)
		_expect(not name_text.is_empty() and not names.has(name_text),
			"Every shade needs its own readable name: %s." % id)
		names.append(name_text)
		var icon := PALETTE.symbol(id)
		_expect(not icon.is_empty() and icon != "?", "Every valid hue needs an icon name.")
		for index in icon.length():
			_expect(icon.unicode_at(index) >= 32 and icon.unicode_at(index) <= 126,
				"Shape labels must work without Unicode icon font support.")
		var swatch := PALETTE.color(id)
		_expect(swatch.a == 1.0 and not swatches.has(swatch),
			"All 21 instruments need distinct, opaque colours: %s." % id)
		swatches.append(swatch)
		_expect(PALETTE.midi_note(id) == PALETTE.MIDI[PALETTE.HUES.find(hue)] + shade - 1,
			"Dark/light pitch markers must be exactly one semitone: %s." % id)
	for hue: StringName in PALETTE.HUES:
		var dark := PALETTE.color(PALETTE.id_for(hue, 0))
		var base := PALETTE.color(hue)
		var light := PALETTE.color(PALETTE.id_for(hue, 2))
		_expect(dark.get_luminance() < base.get_luminance()
			and base.get_luminance() < light.get_luminance(),
			"Shade brightness must reinforce, not contradict, the name: %s." % hue)
		_expect(PALETTE.symbol(PALETTE.id_for(hue, 0)) == PALETTE.symbol(hue)
			and PALETTE.symbol(PALETTE.id_for(hue, 2)) == PALETTE.symbol(hue),
			"Shade changes must retain the hue's geometric identity.")
	for id: StringName in [&"", &"Red", &"red_base", &"red_dark_light", &"blueish", &" red"]:
		_expect(not PALETTE.is_valid(id) and PALETTE.hue_id(id) == &""
			and PALETTE.shade_index(id) == -1,
			"Malformed ids must not silently alias a playable instrument: %s." % id)
		_expect(PALETTE.color(id) == Color.TRANSPARENT and PALETTE.midi_note(id) == -1,
			"Unknown instruments must retain explicit invalid markers.")
	_expect(PALETTE.id_for(&"red", -1) == &"" and PALETTE.id_for(&"red", 3) == &""
		and PALETTE.id_for(&"red_dark") == &"", "Invalid id construction must fail clearly.")
	base_ids.clear()
	full_ids.clear()
	_expect(PALETTE.all_ids().size() == 7 and PALETTE.all_ids(true).size() == 21,
		"Returned palettes must not alias global constants.")


func _option(key: String) -> Dictionary:
	for option: Dictionary in OPTIONS.TUNABLES:
		if option.get("key") == key:
			return option
	_expect(false, "Missing declared option: %s." % key)
	return {}


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_approx(actual: float, expected: float, message: String) -> void:
	_expect(absf(actual - expected) < 0.00000001,
		"%s: expected %.9f, got %.9f." % [message, expected, actual])
