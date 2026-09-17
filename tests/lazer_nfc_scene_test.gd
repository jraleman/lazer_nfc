extends SceneTree

## Real keyboard/touch rounds, replay, pause and exit around the shared shell.

const OPTIONS := preload("res://games/lazer_nfc/lazer_nfc_options.gd")
const Palette = preload("res://games/lazer_nfc/run/palette.gd")
const RunState = preload("res://games/lazer_nfc/run/run_state.gd")
const GAME_PATH := "res://games/lazer_nfc/gameplay.tscn"
const FIXTURE_PATH := "res://games/lazer_nfc/tests/lazer_nfc_scene_fixture.gd"

var _failures := PackedStringArray()
var _settings: Node
var _saved_values: Dictionary
var _saved_game := ""
var _save_process := Node.PROCESS_MODE_INHERIT


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_settings = root.get_node("Settings")
	_saved_values = (_settings.get("_values") as Dictionary).duplicate(true)
	_saved_game = GameCatalog.current_id()
	var save_timer := _settings.get("_save_timer") as Timer
	_save_process = save_timer.process_mode
	save_timer.process_mode = Node.PROCESS_MODE_DISABLED
	GameCatalog.select(OPTIONS.GAME_ID)
	_expect(GameCatalog.current_gameplay_scene_path() == GAME_PATH,
		"The live game manifest must not be shadowed by an archived copy.")
	for option: Dictionary in OPTIONS.TUNABLES:
		_settings.call("set_value", option["key"], option["default"])
	_settings.call("reset_controls_to_defaults", OPTIONS.GAME_ID)
	_settings.call("set_value", OPTIONS.VOICE_KEY, false)
	_settings.call("set_value", OPTIONS.HAPTICS_KEY, 0.0)
	await _test_full_run()
	await _test_shades_and_pause()
	await _test_physical_setup_and_loss()
	await _test_navigation_cancels_completion()
	var values := _settings.get("_values") as Dictionary
	values.clear()
	values.merge(_saved_values, true)
	_settings.call("apply_controls")
	save_timer.stop()
	save_timer.process_mode = _save_process
	GameCatalog.select(_saved_game)
	await create_timer(0.2).timeout
	if _failures.is_empty():
		print("LaZer NFC scene tests passed.")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _new_game() -> Node:
	var packed := load(GAME_PATH) as PackedScene
	var fixture := load(FIXTURE_PATH) as Script
	if packed == null or fixture == null or not fixture.can_instantiate():
		printerr("The LaZer NFC gameplay scene and fixture must compile.")
		quit(1)
		return null
	var game := packed.instantiate()
	var color: Color = game.get("player_one_color")
	game.set_script(fixture)
	game.set("player_one_color", color)
	root.add_child(game)
	game.set_process(false)
	await process_frame
	await process_frame
	return game


func _test_full_run() -> void:
	var game := await _new_game()
	if game == null:
		return
	var state: RunState = game.get("_state")
	_expect(state.state == RunState.State.READY and not bool(game.get("_binding")),
		"Without NFC the real game starts READY, never in a physical-tag softlock.")
	_expect((game.get_node("%RoundTimer") as Timer).is_stopped(),
		"Memory runs must not start the shell's arcade timer.")
	game.call("_on_touch_color", &"red")
	_expect(state.score == 0 and not state.assisted and state.hits == 0,
		"Trying a touch colour before the run must not spend a life or halve a score.")
	var practice := (game.get("_deck") as Node).get("_practice") as Button
	_expect(practice.focus_mode == Control.FOCUS_NONE,
		"Clicking sound practice must not steal the declared Space run action.")
	_dispatch(OPTIONS.CONFIRM_ACTION)
	_reach_recall(game)
	_expect(state.state == RunState.State.AWAITING, "The entire show must lead to recall.")
	var echo := InputEventKey.new()
	echo.pressed = true
	echo.echo = true
	echo.physical_keycode = KEY_1
	root.push_input(echo)
	_expect(state.hits == 0 and state.wrongs == 0, "Key-repeat echoes cannot answer.")
	_answer_expected(game)
	_expect(state.hits == 1 and state.score > 0,
		"A real parent-viewport colour action must recall a robot.")
	_expect(int(game.get("_scores")[0]) == state.score,
		"The shell HUD must use the model's exact score.")
	for i in 100:
		if state.round_n >= 5 or state.state == RunState.State.RUN_OVER:
			break
		_reach_recall(game)
		if state.state == RunState.State.AWAITING:
			_answer_expected(game)
		else:
			break
	_expect(state.round_n >= 5 and state.flawless_six,
		"Clean keyboard play reaches palette growth and the six-robot clean sweep.")
	var prior_score := state.score
	_reach_recall(game)
	if state.state == RunState.State.AWAITING:
		game.call("_on_touch_color", state.sequence[state.recall_index])
	_expect(state.assisted and state.score < prior_score,
		"The first touch answer flags and halves the banked score once.")
	_settings.call("set_value", OPTIONS.VOICE_KEY, true)
	for i in 2500:
		if not bool(game.get("_round_active")):
			break
		game.call("_update_round", 0.1, 0.0)
	_expect(state.lives == 0 and state.state == RunState.State.RUN_OVER,
		"Unanswered robots eventually exhaust the life pool.")
	_expect((game.get_node("%RoundOver") as Control).visible,
		"Exhausting the game-owned pool opens the real shell results.")
	_expect(int(game.get("recorded_count")) == 1,
		"A run records exactly once.")
	var sound := game.get("_sound") as Node
	_expect(not bool(sound.get("_stopped")) and sound.get("_phase") == &"RUN_OVER",
		"Opening results must retain the terminal motif and score announcement.")
	var voice_delay := float(sound.get("_voice_delay"))
	game.call("_process", 0.1)
	_expect(float(sound.get("_voice_delay")) < voice_delay,
		"Result speech continues on the scene clock after the model ends.")
	_settings.call("set_value", OPTIONS.VOICE_KEY, false)
	game.call("_end_round")
	_expect(int(game.get("recorded_count")) == 1,
		"Repeated completion callbacks are idempotent.")
	var achievements: Array = game.get("unlocked_ids")
	_expect(achievements.has("lazer_nfc_first_run") and achievements.has("lazer_nfc_round_five")
		and achievements.has("lazer_nfc_flawless_round")
		and not achievements.has("lazer_nfc_unassisted"),
		"Achievement predicates must describe the completed run, including assistance.")
	var payload: Dictionary = game.call("_share_payload")
	_expect(int(payload["score_values"][0]) == state.score
		and int(payload["hits_value"]) == state.hits
		and int(payload["misses_value"]) == state.wrongs + state.timeouts
		and bool(payload["assisted"]),
		"Share, results and model agree on score, accuracy inputs and assistance.")
	game.call("_on_play_again_pressed")
	state = game.get("_state")
	_expect(state.state == RunState.State.READY and state.score == 0 and not state.assisted,
		"Play Again resets the entire run and returns to a usable READY screen.")
	_expect(not (game.get_node("%RoundOver") as Control).visible
		and (game.get("_deck") as Control).visible,
		"Replay replaces the result modal with working controls.")
	game.queue_free()
	await process_frame


func _test_shades_and_pause() -> void:
	_settings.call("set_value", OPTIONS.SHADE_MODE_KEY, true)
	var game := await _new_game()
	if game == null:
		return
	var state: RunState = game.get("_state")
	_dispatch(OPTIONS.CONFIRM_ACTION)
	_reach_recall(game)
	state.sequence[state.recall_index] = &"blue_dark"
	Input.action_press(OPTIONS.DARK_ACTION)
	_dispatch(OPTIONS.COLOR_ACTIONS[4])
	Input.action_release(OPTIONS.DARK_ACTION)
	_expect(state.hits == 1,
		"A held, rebindable dark-shade action must answer the dark shade.")
	_reach_recall(game)
	game.call("_update_round", 0.6, 0.0)
	var clock := state.clock
	game.call("open_pause_menu")
	_expect(paused and bool(game.get("_suspended")),
		"The shared overlay pauses both gameplay and hardware sources.")
	game.call("_update_round", 20.0, 0.0)
	_expect(is_equal_approx(state.clock, clock),
		"Even a queued game update must not advance the model while suspended.")
	var menu := game.get("_pause_menu") as Node
	if menu != null:
		menu.call("resume")
	await process_frame
	_expect(not paused and not bool(game.get("_suspended"))
		and is_equal_approx(state.window_remaining, state.window_duration),
		"Resume restores the current recall window in full, not a wall-clock remainder.")
	_settings.call("set_value", Settings.REDUCED_MOTION_KEY, true)
	_settings.call("set_value", Settings.VISUAL_EFFECTS_KEY, false)
	_expect(bool(game.get("_reduced_motion_enabled")) and not bool(game.get("_intense_effects_enabled")),
		"Live accessibility changes still pass through the inherited shell.")
	var lives := state.lives
	game.call("_preview_or_answer", &"invalid_tag", &"nfc", 80)
	_expect(state.lives == lives, "An unknown tag is not a mistake.")
	game.queue_free()
	await process_frame
	_settings.call("set_value", OPTIONS.SHADE_MODE_KEY, false)


func _test_navigation_cancels_completion() -> void:
	var game := await _new_game()
	if game == null:
		return
	_dispatch(OPTIONS.CONFIRM_ACTION)
	_reach_recall(game)
	var router := root.get_node("Router")
	var was_busy := bool(router.get("_busy"))
	router.set("_busy", true)
	game.call("_process", 0.5)
	game.call("_end_round")
	_expect(bool(game.get("_leaving")) and not bool(game.get("_round_active"))
		and int(game.get("recorded_count")) == 0,
		"A Router exit fade cancels gameplay before a simultaneous completion can record.")
	router.set("_busy", was_busy)
	game.queue_free()
	await process_frame


func _test_physical_setup_and_loss() -> void:
	var game := await _new_game()
	if game == null:
		return
	var source_script := load("res://games/lazer_nfc/tests/lazer_nfc_source_fixture.gd") as Script
	var tags_script := load("res://games/lazer_nfc/tests/lazer_nfc_tags_fixture.gd") as Script
	if source_script == null or tags_script == null:
		_expect(false, "Hardware-free NFC scene fixtures must load.")
		game.queue_free()
		await process_frame
		return
	var source: Node = source_script.new()
	var tags: RefCounted = tags_script.new()
	(game.get("_nfc") as Node).free()
	game.set("_nfc", source)
	game.set("_tags", tags)
	game.add_child(source)
	source.connect("tag_scanned", Callable(game, "_on_tag_scanned"))
	source.connect("availability_changed", Callable(game, "_on_nfc_availability_changed"))
	source.emit_signal("availability_changed", true, "")
	game.call("_on_play_again_pressed")
	_expect(bool(game.get("_binding")) and bool(source.get("reader_started")),
		"A real available reader with no tags enters the active roll call.")
	source.emit_signal("tag_scanned", "04abcdef", 80)
	game.call("_update_round", 0.6, 0.0)
	source.emit_signal("tag_scanned", "04abcdef", 80)
	_expect(int(game.get("_binding_index")) == 1,
		"One physical tag cannot be assigned to two prompts in a roll call.")
	game.call("_update_round", 0.2, 0.0)
	source.emit_signal("tag_scanned", "05abcdef", 80)
	game.call("_update_round", 0.2, 0.0)
	source.emit_signal("tag_scanned", "06abcdef", 80)
	for i in 4:
		game.call("_skip_binding")
	_expect(not bool(game.get("_binding")) and int(tags.get("saves")) == 1,
		"Three distinct hues plus skipped prompts complete and persist one roll call.")
	var available: Array = game.get("_available_colors")
	_expect(available.size() == 3 and available.has(&"red")
		and available.has(&"yellow") and available.has(&"green"),
		"The run's palette uses the actual bound hues, not an assumed prefix.")
	source.emit_signal("tag_scanned", "04abcdef", 80)
	game.call("_update_round", 0.6, 0.0)
	source.emit_signal("tag_scanned", "04abcdef", 80)
	_expect(bool(_settings.call("tunable_bool", OPTIONS.SHADE_MODE_KEY)),
		"A debounced same-UID red double scan writes the real shade setting.")
	_expect(not bool(game.get("_completed_run")),
		"READY gestures never complete or score an experiment.")
	source.set("adapter_enabled", false)
	source.emit_signal("availability_changed", false, "disabled")
	_expect(paused and not bool(source.get("reader_started"))
		and bool((game.get("_deck") as Node).get("_pad_visible")),
		"Losing NFC pauses the game, stops reading and exposes fallback controls.")
	var pause_menu := game.get("_pause_menu") as Node
	if pause_menu != null:
		pause_menu.call("resume")
	await process_frame
	_expect(not paused and not bool(source.get("reader_started")),
		"Resuming with NFC disabled cannot reactivate the reader.")
	source.set("adapter_enabled", true)
	source.emit_signal("availability_changed", true, "")
	game.call("_on_play_again_pressed")
	game.call("_use_fallback")
	game.call("_on_play_again_pressed")
	_expect(not bool(game.get("_binding")) and not bool(game.get("_physical_run"))
		and bool((game.get("_deck") as Node).get("_pad_visible")),
		"Choosing keys and touch must survive Play Again instead of repeating tag setup.")
	game.queue_free()
	await process_frame
	_settings.call("set_value", OPTIONS.SHADE_MODE_KEY, false)


func _reach_recall(game: Node) -> void:
	var state: RunState = game.get("_state")
	for i in 1500:
		if state.state == RunState.State.AWAITING or not bool(game.get("_round_active")):
			return
		game.call("_update_round", 1.0 / 30.0, 0.0)
	_expect(false, "A live sequence must reach its next recall window.")


func _answer_expected(game: Node) -> void:
	var state: RunState = game.get("_state")
	if state.state != RunState.State.AWAITING or state.recall_index >= state.sequence.size():
		_expect(false, "The scripted player must have a current recall target.")
		return
	var color_id := state.sequence[state.recall_index]
	var shade := Palette.shade_index(color_id)
	if shade == 0:
		Input.action_press(OPTIONS.DARK_ACTION)
	elif shade == 2:
		Input.action_press(OPTIONS.LIGHT_ACTION)
	_dispatch(OPTIONS.COLOR_ACTIONS[Palette.HUES.find(Palette.hue_id(color_id))])
	Input.action_release(OPTIONS.DARK_ACTION)
	Input.action_release(OPTIONS.LIGHT_ACTION)


func _dispatch(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	root.push_input(event)
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	root.push_input(event)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
