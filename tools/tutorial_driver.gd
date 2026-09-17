extends RefCounted

## The host recorder plays a seeded, real keyboard run, never a staged score.

signal keycap_requested(text: String)

const OPTIONS := preload("res://games/lazer_nfc/lazer_nfc_options.gd")
const Palette = preload("res://games/lazer_nfc/run/palette.gd")
const RunState = preload("res://games/lazer_nfc/run/run_state.gd")

var _started := false
var _preview_one := false
var _preview_two := false
var _wrong_shown := false
var _next_input := 0.0


## LaZer NFC has one player and one tutorial.
func configure(variant: String) -> bool:
	return variant == "solo"


## Captions follow the actual wave timings with room to see each consequence.
func steps() -> Array[Dictionary]:
	return [
		{"time": 0.0, "title": "Meet your little laboratory",
			"body": "Try colours before starting. Each has a shape and a distinct instrument."},
		{"time": 3.0, "title": "Listen to the whole pattern",
			"body": "Remember the robots in order. Do not answer until the double recall cue."},
		{"time": 7.0, "title": "Recall one robot at a time",
			"body": "Use the shown keys or tap the colour pad. NFC tags work on Android too."},
		{"time": 11.0, "title": "Chase a clean sweep",
			"body": "Consecutive hits build your combo. A perfect round doubles its round bonus."},
		{"time": 22.0, "title": "One more bright idea",
			"body": "Each round adds a robot. New colours join as your memory grows."},
		{"time": 28.0, "title": "A mistake is not the end",
			"body": "A wrong colour costs one battery. Correct it before the original deadline."},
	]


## Enough time for three genuine shows, two clears and one corrected mistake.
func duration() -> float:
	return 36.0


## The recorder applies these in memory, never to the player's settings file.
func settings_overrides() -> Dictionary:
	return {
		OPTIONS.LIVES_KEY: 3,
		OPTIONS.SCAN_WINDOW_KEY: 4.0,
		OPTIONS.RAMP_KEY: 1,
		OPTIONS.START_LENGTH_KEY: 3,
		OPTIONS.PALETTE_START_KEY: 4,
		OPTIONS.SHADE_MODE_KEY: false,
		OPTIONS.TOUCH_PAD_KEY: true,
		OPTIONS.VOICE_KEY: false,
		OPTIONS.HAPTICS_KEY: 0.0,
		OPTIONS.REBIND_TAGS_KEY: false,
	}


## The ordinary solo route is the route the tutorial teaches.
func configure_session(session: Node) -> void:
	session.call("configure_single_player")


## A seed fixes the melody without replacing any gameplay rules.
func start(scene: Node) -> void:
	_started = false
	_preview_one = false
	_preview_two = false
	_wrong_shown = false
	_next_input = 0.0
	var state: RunState = scene.get("_state")
	var config: Dictionary = scene.get("_config")
	state.reset(config, 42603)
	scene.call("_update_model_hud")


## Leave the lower caption card clear of the interactive control deck.
func capture_inset() -> float:
	return 255.0


## All answers go through the real parent-viewport input actions.
func update(scene: Node, time: float, _delta: float) -> void:
	if not bool(scene.get("_round_active")):
		return
	if not _preview_one and time >= 0.65:
		_preview_one = true
		_press(scene, &"red")
	if not _preview_two and time >= 1.25:
		_preview_two = true
		_press(scene, &"yellow")
	if not _started and time >= 2.0:
		_started = true
		_dispatch(scene, OPTIONS.CONFIRM_ACTION)
	var state: RunState = scene.get("_state")
	if state.state != RunState.State.AWAITING or time < _next_input:
		return
	if state.window_duration - state.window_remaining < 0.6:
		return
	var expected := state.sequence[state.recall_index]
	if state.round_n >= 3 and not _wrong_shown:
		for color_id: StringName in state.active_palette:
			if color_id != expected:
				_wrong_shown = true
				_press(scene, color_id)
				_next_input = time + 0.65
				return
	_press(scene, expected)
	_next_input = time + 0.6


## Reject a take in which the scripted lesson stopped reaching the live game.
func validate_finished(scene: Node) -> bool:
	var state: RunState = scene.get("_state")
	return state.round_n >= 3 and state.hits >= 8 and state.wrongs == 1 and state.lives > 0


func _press(scene: Node, color_id: StringName) -> void:
	var index := Palette.HUES.find(Palette.hue_id(color_id))
	var action: StringName = OPTIONS.COLOR_ACTIONS[index]
	var settings := scene.get_tree().root.get_node("Settings")
	keycap_requested.emit("%s  %s" % [
		str(settings.call("control_key_label", action)), Palette.label(color_id),
	])
	_dispatch(scene, action)


func _dispatch(scene: Node, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	scene.get_viewport().push_input(event)
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	scene.get_viewport().push_input(event)
