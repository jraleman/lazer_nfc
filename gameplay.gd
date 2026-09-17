extends GameShell

## The shell owns a run; the model owns its memory rounds and the lab reads it.

const OPTIONS := preload("res://games/lazer_nfc/lazer_nfc_options.gd")
const Palette = preload("res://games/lazer_nfc/run/palette.gd")
const RunState = preload("res://games/lazer_nfc/run/run_state.gd")
const TagBindings = preload("res://games/lazer_nfc/run/tag_bindings.gd")
const NfcSource = preload("res://games/lazer_nfc/input/nfc_source.gd")
const KeySource = preload("res://games/lazer_nfc/input/key_source.gd")
const MotionSource = preload("res://games/lazer_nfc/input/motion_source.gd")
const AudioDirector = preload("res://games/lazer_nfc/audio/audio_director.gd")
const Haptics = preload("res://games/lazer_nfc/audio/haptics.gd")
const Arena = preload("res://games/lazer_nfc/arena/arena.gd")
const ControlDeck = preload("res://games/lazer_nfc/ui/control_deck.gd")
const ARENA_SCENE := preload("res://games/lazer_nfc/arena/arena.tscn")
const BINDING_SECONDS := 12.0
const MINIMUM_TAGS := 3

var _state := RunState.new()
var _tags := TagBindings.new()
var _keys := KeySource.new()
var _motion := MotionSource.new()
var _nfc: NfcSource
var _sound: AudioDirector
var _haptics: Haptics
var _arena: Arena
var _deck: ControlDeck
var _config: Dictionary = {}
var _available_colors: Array[StringName] = []
var _binding_order: Array[StringName] = []
var _binding_seen: Dictionary = {}
var _binding := false
var _binding_index := 0
var _binding_remaining := 0.0
var _binding_ping := 0.0
var _binding_last_read := -INF
var _binding_last_uid := ""
var _binding_notice := ""
var _input_available := false
var _physical_run := false
var _fallback_requested := false
var _prefer_fallback := false
var _practice := false
var _source_note := ""
var _feedback := ""
var _feedback_remaining := 0.0
var _ready_reminder := 0.0
var _ready_clock := 0.0
var _gesture_color: StringName
var _gesture_uid := ""
var _gesture_deadline := -1.0
var _reader_idle := 0.0
var _reader_hint_given := false
var _suspended := false
var _leaving := false
var _entering_transition := false
var _completed_run := false
var _ui_factor := 1.0
var _hud_size := Vector2.ZERO
var _layout_queued := false
var _hud_font_sizes: Dictionary = {}
var _capture_inset := 0.0
var _results_scroll: ScrollContainer
var _results_center: CenterContainer
var _result_rows: Array[BoxContainer] = []


func _ready() -> void:
	_entering_transition = Router.is_transitioning()
	if _entering_transition:
		Router.transition_finished.connect(_on_entry_transition_finished, CONNECT_ONE_SHOT)
	AudioManager.stop_music(0.0)
	music = null
	super()


func _process(delta: float) -> void:
	if _abort_if_exiting():
		return
	super(delta)
	if _completed_run and not _round_active and not _suspended:
		_sound.advance(delta, _state.snapshot(), 0.0)
		_haptics.advance(delta)


func _exit_tree() -> void:
	_leaving = true
	_round_active = false
	_stop_input_and_audio()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		if is_node_ready() and _round_active and not _leaving:
			open_pause_menu()
	elif what == NOTIFICATION_PAUSED:
		if is_node_ready():
			_suspend_sources()


## The manifest is the only place the framework learns this game's identity.
func game_id() -> String:
	return OPTIONS.GAME_ID


func _load_round_settings() -> void:
	super()
	_config = {
		"lives": roundi(Settings.tunable(OPTIONS.LIVES_KEY)),
		"scan_window": Settings.tunable(OPTIONS.SCAN_WINDOW_KEY),
		"ramp": Settings.tunable_choice(OPTIONS.RAMP_KEY),
		"start_length": roundi(Settings.tunable(OPTIONS.START_LENGTH_KEY)),
		"palette_start": roundi(Settings.tunable(OPTIONS.PALETTE_START_KEY)),
		"shade_mode": Settings.tunable_bool(OPTIONS.SHADE_MODE_KEY),
	}


func _prepare_session() -> void:
	# A direct scene launch, like the normal solo menu path, needs one seat.
	GameSession.configure_single_player()
	super()


func _build_playfield() -> void:
	_arena = ARENA_SCENE.instantiate() as Arena
	_playfield.add_child(_arena)
	_arena.configure_accessibility(_reduced_motion_enabled, _intense_effects_enabled)
	_deck = ControlDeck.new()
	_deck.name = "LaboratoryControls"
	_hud.get_node("Overlay").add_child(_deck)
	_deck.color_pressed.connect(_on_touch_color)
	_deck.start_requested.connect(_begin_experiment)
	_deck.skip_requested.connect(_skip_binding)
	_deck.fallback_requested.connect(_use_fallback)
	_deck.practice_toggled.connect(_on_practice_toggled)
	_sound = AudioDirector.new()
	_sound.name = "LaboratoryAudio"
	add_child(_sound)
	_sound.configure(Settings.tunable_bool(OPTIONS.VOICE_KEY))
	_haptics = Haptics.new()
	_haptics.name = "LaboratoryHaptics"
	add_child(_haptics)
	_haptics.configure(Settings.tunable(OPTIONS.HAPTICS_KEY))
	var error := _tags.load_file()
	if error != OK and error != ERR_FILE_NOT_FOUND:
		_source_note = "Saved tags could not be read. Existing data will not be overwritten."
		_sound.announce(_source_note)
	_nfc = NfcSource.new()
	_nfc.name = "NfcReader"
	_nfc.availability_changed.connect(_on_nfc_availability_changed)
	_nfc.reader_error.connect(_on_reader_error)
	_nfc.tag_scanned.connect(_on_tag_scanned)
	add_child(_nfc)
	get_viewport().size_changed.connect(_queue_layout)
	_callout.resized.connect(_queue_layout)
	_hint.resized.connect(_queue_layout)
	_deck.minimum_size_changed.connect(_queue_layout)
	_build_responsive_results()
	_resize_hud()
	_queue_layout()


func _start_round() -> void:
	if not _abort_if_exiting():
		super()


func _reset_round_state() -> void:
	if _completed_run:
		_sound.suspend()
		_sound.resume()
	_haptics.stop()
	_completed_run = false
	_binding = false
	_practice = false
	_suspended = false
	if Settings.tunable_bool(OPTIONS.REBIND_TAGS_KEY) and _nfc.available():
		_prefer_fallback = false
	_fallback_requested = _prefer_fallback
	_feedback = ""
	_feedback_remaining = 0.0
	_ready_reminder = 0.0
	_ready_clock = 0.0
	_reader_idle = 0.0
	_reader_hint_given = false
	_reset_gesture()
	_motion.reset()
	_physical_run = _nfc.available() and not _prefer_fallback
	_available_colors = _tags.bound_colors(bool(_config["shade_mode"])) \
		if _physical_run else Palette.all_ids(bool(_config["shade_mode"]))
	if _base_hue_count(_available_colors) < MINIMUM_TAGS:
		_available_colors = Palette.all_ids(bool(_config["shade_mode"]))
	_config["available_colors"] = _available_colors
	_reset_prepared_model()
	_arena.reset()
	_deck.show()
	_deck.set_binding(false)
	_deck.set_practice(false)
	_sound.configure(Settings.tunable_bool(OPTIONS.VOICE_KEY))
	_haptics.configure(Settings.tunable(OPTIONS.HAPTICS_KEY))
	_sync_deck()
	_update_model_hud()


func _activate_round() -> void:
	if _physical_run:
		_nfc.start()
		var colors := _tags.bound_colors(bool(_config["shade_mode"]))
		if (
			_base_hue_count(colors) < MINIMUM_TAGS
			or Settings.tunable_bool(OPTIONS.REBIND_TAGS_KEY)
			or (bool(_config["shade_mode"]) and not _contains_shades(colors))
		):
			_begin_binding()
			return
	_enter_ready()


func _enter_ready() -> void:
	_binding = false
	_deck.set_binding(false)
	_feedback = ""
	_ready_reminder = 0.0
	_deck.set_practice(false)
	_practice = false
	_sound.announce(
		"Ready. Learn the sounds, then start your experiment. Tap a tag or press %s."
		% Settings.control_key_label(OPTIONS.CONFIRM_ACTION),
		&"ready"
	)
	_sync_deck()
	_present()
	_queue_layout()


func _update_round(delta: float, _time_left: float) -> void:
	if _suspended:
		return
	_haptics.advance(delta)
	_feedback_remaining = maxf(_feedback_remaining - delta, 0.0)
	if _binding:
		_update_binding(delta)
	else:
		if _state.state == RunState.State.READY:
			_update_ready(delta)
		else:
			_motion.sample()
			_state.advance(delta)
			_round_elapsed = _state.clock
			_drain_model_events()
		if _round_active:
			var snapshot := _state.snapshot()
			_sound.advance(delta, snapshot, _motion.peek_peak())
			_arena.advance(delta)
			_present()
	_round_elapsed = _state.clock
	_update_reader_hint(delta)


func _update_ready(delta: float) -> void:
	_ready_clock += delta
	_ready_reminder += delta
	if _gesture_deadline >= 0.0 and _ready_clock >= _gesture_deadline:
		_reset_gesture()
		_begin_experiment()
		return
	if _ready_reminder >= 10.0 and not _practice:
		_ready_reminder = 0.0
		_sound.announce("Ready. Tap a tag or start the experiment.", &"ready")


func _begin_experiment() -> void:
	if (
		not _round_active or _binding or _suspended or _abort_if_exiting()
		or _state.state != RunState.State.READY
	):
		return
	_practice = false
	_deck.set_practice(false)
	_reset_gesture()
	_motion.reset()
	_feedback = ""
	_feedback_remaining = 0.0
	_state.begin()
	_drain_model_events()
	_present()
	_queue_layout()


func _handle_gameplay_input(event: InputEvent) -> void:
	if _suspended or _abort_if_exiting():
		return
	if _keys.confirm_pressed(event):
		get_viewport().set_input_as_handled()
		if _binding:
			_skip_binding()
		else:
			_begin_experiment()
		return
	var color_id := _keys.color_from_event(event, bool(_config["shade_mode"]))
	if color_id.is_empty():
		return
	get_viewport().set_input_as_handled()
	if _binding:
		_use_fallback()
	_preview_or_answer(color_id, &"key")


func _on_touch_color(color_id: StringName) -> void:
	_preview_or_answer(color_id, &"touch")


func _preview_or_answer(color_id: StringName, source: StringName, age_ms := 0) -> void:
	if not _round_active or _binding or _suspended or _abort_if_exiting():
		return
	if _state.state == RunState.State.READY:
		_sound.play_note(color_id)
		_sound.announce("%s. %s." % [Palette.label(color_id), Palette.symbol(color_id)])
		_arena.react({"type": &"note", "color_id": color_id, "index": 0})
		_feedback = "%s - listen, learn, then start." % Palette.label(color_id)
		_feedback_remaining = 2.0
		_present()
		return
	_state.answer(color_id, float(age_ms) / 1000.0, _motion.take_peak(), source == &"touch")
	_drain_model_events()
	_present()


func _drain_model_events() -> void:
	for event: Dictionary in _state.drain_events():
		if not _round_active or _leaving:
			return
		var kind := StringName(event.get("type", &""))
		_arena.react(event)
		_sound.play_event(event)
		_haptics.play_event(event)
		match kind:
			&"round_started":
				_feedback = ""
				_feedback_remaining = 0.0
				_show_announcement("ROUND %d" % _state.round_n, Color("fff0cd"), 0.5)
			&"hit":
				_feedback = "+%d  %s  |  Combo x%d" % [
					int(event.get("points", 0)),
					Palette.label(StringName(event.get("color_id", &""))),
					_state.combo,
				]
				_feedback_remaining = 0.7
				_add_screen_shake(2.0 if _state.combo < 5 else 4.0)
			&"wrong":
				_feedback = "Wrong colour - same robot, same deadline."
				_feedback_remaining = 1.0
				_flash_screen(DANGER_COLOR, 0.1)
			&"timeout":
				_feedback = "That one escaped. The next robot is yours."
				_feedback_remaining = 0.8
			&"round_won":
				var perfect := bool(event.get("perfect", false))
				_feedback = "CLEAN SWEEP! Double round bonus." if perfect \
					else ("Round complete. A fresh ending joins the pattern!"
						if _state.sequence.size() >= OPTIONS.SEQ_LEN_MAX
						else "Round complete. Here comes one more robot!")
				_feedback_remaining = 1.5
				_show_announcement(
					"CLEAN SWEEP!" if perfect else "NICE RECALL!",
					Color("ffd36c") if perfect else player_one_color, 0.7
				)
			&"not_yet":
				_feedback = "Listen first. Recall after the double cue."
				_feedback_remaining = 0.8
			&"unknown":
				_feedback = "That colour is not in this experiment."
				_feedback_remaining = 1.0
			&"run_over":
				_update_model_hud()
				_completed_run = true
				_end_round()
				return
		_update_model_hud()


func _update_model_hud() -> void:
	_scores[PLAYER_ONE] = _state.score
	_streaks[PLAYER_ONE] = _state.combo
	_best_streaks[PLAYER_ONE] = _state.best_combo
	_update_scores()
	_update_streaks()
	_time_label.text = str(_state.lives)
	_time_progress.value = _state.lives


func _reset_round_gauge() -> void:
	super()
	_time_caption.text = "BATTERIES LEFT"
	_time_label.text = str(_config.get("lives", 3))
	_time_progress.show()
	_time_progress.max_value = int(_config.get("lives", 3))
	_time_progress.value = _time_progress.max_value


func _present() -> void:
	if _arena == null or _deck == null or _leaving:
		return
	var snapshot := _state.snapshot()
	_arena.present(snapshot)
	var message := _phase_message()
	if _feedback_remaining > 0.0:
		message = _feedback
	_deck.present(snapshot, message)
	var recall := _state.state == RunState.State.AWAITING
	_callout.text = "ROUND %d  |  %d ROBOTS  |  %s" % [
		maxi(_state.round_n, 1), _state.sequence.size(),
		"RECALL %d" % (_state.recall_index + 1) if recall
		else ("LEARN THE SOUNDS" if _practice else "THE LITTLE LABORATORY"),
	]
	if _state.state == RunState.State.READY:
		_callout.text = "A LITTLE PRACTICE. A BIG BRIGHT IDEA."


func _phase_message() -> String:
	match _state.state:
		RunState.State.READY:
			if _gesture_deadline >= 0.0:
				return "Starting... tap %s again for its shortcut." % Palette.label(_gesture_color)
			if _practice:
				return "Sound check: try every colour. No lives or points at stake."
			if not _source_note.is_empty():
				return _source_note
			return "Try a colour to hear it. Ready for your next experiment?"
		RunState.State.ROUND_START:
			return "Round %d - remember %d robots." % [_state.round_n, _state.sequence.size()]
		RunState.State.SHOWING:
			return "LISTEN  |  Robot %d of %d" % [
				_state.show_index + 1, _state.sequence.size(),
			]
		RunState.State.SHOW_END:
			return "Get ready. The double cue opens recall."
		RunState.State.AWAITING:
			return "RECALL  %d / %d  |  %.1fs  |  %s" % [
				_state.recall_index + 1, _state.sequence.size(),
				maxf(_state.window_remaining, 0.0),
				"Assisted: half score" if _state.assisted else "Keep the combo!",
			]
		RunState.State.RECALL_GAP:
			return "Lift, reset, and get ready for the next robot."
		RunState.State.ROUND_WON:
			return "Keep eleven, learn one new ending!" if _state.sequence.size() >= OPTIONS.SEQ_LEN_MAX \
				else "Another bright idea. The next round adds one robot."
		_:
			return "Experiment complete."


func _begin_binding() -> void:
	if not _round_active or not _nfc.available() or _leaving:
		return
	_binding = true
	_practice = false
	_binding_order.clear()
	for hue: StringName in Palette.GROWTH_ORDER:
		_binding_order.append(hue)
	if bool(_config["shade_mode"]):
		for shade in [0, 2]:
			for hue: StringName in Palette.GROWTH_ORDER:
				_binding_order.append(Palette.id_for(hue, shade))
	_binding_index = 0
	_binding_seen.clear()
	_binding_last_read = -INF
	_binding_last_uid = ""
	_binding_notice = ""
	_reset_gesture()
	_sound.announce(
		"Tag roll call. Tap the upper back of your phone against each tag. "
		+ "You can skip a colour or use keys and touch instead.", &"binding"
	)
	_prompt_binding()
	_queue_layout()


func _prompt_binding() -> void:
	if _binding_index >= _binding_order.size():
		_complete_binding()
		return
	_binding_remaining = BINDING_SECONDS
	_binding_ping = 0.0
	_binding_notice = ""
	var color_id := _binding_order[_binding_index]
	_sound.announce("Scan the tag for %s." % Palette.label(color_id),
		StringName("bind_" + str(color_id)))
	_arena.react({"type": &"note", "color_id": color_id, "index": 0})
	_refresh_binding_message()


func _update_binding(delta: float) -> void:
	_ready_clock += delta
	_binding_remaining -= delta
	_binding_ping += delta
	if _binding_remaining <= 0.0:
		_skip_binding()
	elif _binding_ping >= 2.0:
		_binding_ping = 0.0
		_sound.play_note(_binding_order[_binding_index])
	_refresh_binding_message()


func _refresh_binding_message() -> void:
	if not _binding:
		return
	var name_text := Palette.label(_binding_order[_binding_index])
	_callout.text = "TAG ROLL CALL  %d / %d" % [_binding_index + 1, _binding_order.size()]
	var message := "Scan %s  |  %ds  |  %d colours bound" % [
		name_text, maxi(ceili(_binding_remaining), 0),
		_tags.bound_colors(bool(_config["shade_mode"])).size(),
	]
	if not _binding_notice.is_empty():
		message = _binding_notice + "\n" + message
	_deck.set_binding(true, message)


func _skip_binding() -> void:
	if not _binding or _suspended or _leaving:
		return
	_sound.announce("%s skipped." % Palette.label(_binding_order[_binding_index]))
	_binding_index += 1
	_prompt_binding()


func _complete_binding() -> void:
	var colors := _tags.bound_colors(bool(_config["shade_mode"]))
	if _base_hue_count(colors) < MINIMUM_TAGS:
		_sound.announce("Bind at least three colours, or choose keys and touch.", &"need_tags")
		_binding_index = 0
		_prompt_binding()
		return
	var error := _tags.save_file()
	if error != OK:
		_source_note = "Tags work for this session, but could not be saved."
		_sound.announce(_source_note)
	else:
		Settings.set_value(OPTIONS.REBIND_TAGS_KEY, false)
		_source_note = "Tags ready. Tap one to start, or learn their sounds."
	_available_colors = colors
	_config["available_colors"] = colors
	if bool(_config["shade_mode"]) and not _contains_shades(colors):
		_config["shade_mode"] = false
		_source_note = "No shade tags bound. This experiment uses base colours and base scoring."
		_sound.announce(_source_note)
	_reset_prepared_model()
	_enter_ready()


func _use_fallback(persist_choice := true) -> void:
	if not _round_active or _leaving:
		return
	_binding = false
	_physical_run = false
	_fallback_requested = true
	if persist_choice:
		_prefer_fallback = true
		Settings.set_value(OPTIONS.REBIND_TAGS_KEY, false)
	_nfc.stop()
	_available_colors = Palette.all_ids(bool(_config["shade_mode"]))
	_config["available_colors"] = _available_colors
	_reset_prepared_model()
	_source_note = "Keys ready. Touch answers are Assisted (half score); trying sounds is free."
	_update_model_hud()
	_enter_ready()


func _on_tag_scanned(uid: String, age_ms: int) -> void:
	if not _round_active or _suspended or _abort_if_exiting():
		return
	_reader_idle = 0.0
	_reader_hint_given = false
	if _binding:
		if uid != _binding_last_uid and _ready_clock - _binding_last_read < 0.15:
			_binding_notice = "Tags too close - separate them before scanning."
			_sound.announce(_binding_notice)
			return
		_binding_last_uid = uid
		_binding_last_read = _ready_clock
		if _binding_seen.has(uid) and StringName(_binding_seen[uid]) != _binding_order[_binding_index]:
			_binding_notice = "That tag already has a colour in this roll call."
			_sound.announce(_binding_notice)
			return
		var requested := _binding_order[_binding_index]
		var error := _tags.bind_tag(uid, requested, true)
		if error != OK:
			_binding_notice = "That tag could not be bound. Try another tag."
			_sound.announce(_binding_notice)
			return
		_binding_seen[uid] = requested
		_sound.play_note(requested)
		_sound.announce("%s bound." % Palette.label(requested))
		_haptics.play_event({"type": &"hit"})
		_binding_index += 1
		_prompt_binding()
		return
	var color_id := _tags.color_for(uid)
	if color_id.is_empty():
		_sound.play_event({"type": &"unknown"})
		_feedback = "Unknown tag. Use Settings > Game > Rebind tags."
		_feedback_remaining = 2.0
		return
	if _state.state == RunState.State.READY and not _practice:
		_handle_ready_tag(color_id, uid)
	else:
		_preview_or_answer(color_id, &"nfc", age_ms)


func _handle_ready_tag(color_id: StringName, uid: String) -> void:
	var hue := Palette.hue_id(color_id)
	if not [&"red", &"yellow", &"violet"].has(hue):
		_begin_experiment()
		return
	if hue == _gesture_color and uid == _gesture_uid and _ready_clock <= _gesture_deadline:
		_reset_gesture()
		match hue:
			&"red":
				var enabled := not Settings.tunable_bool(OPTIONS.SHADE_MODE_KEY)
				Settings.set_value(OPTIONS.SHADE_MODE_KEY, enabled)
				_load_round_settings()
				_config["available_colors"] = _tags.bound_colors(enabled)
				_available_colors.assign(_config["available_colors"])
				if enabled and not _contains_shades(_available_colors):
					_begin_binding()
					return
				_reset_prepared_model()
				_sound.announce("Shades on." if enabled else "Shades off.",
					&"shades_on" if enabled else &"shades_off")
				_sync_deck()
			&"yellow":
				var shown := not Settings.tunable_bool(OPTIONS.TOUCH_PAD_KEY)
				Settings.set_value(OPTIONS.TOUCH_PAD_KEY, shown)
				_sound.announce("Touch pad shown." if shown else "Touch pad hidden.",
					&"touch_on" if shown else &"touch_off")
			&"violet":
				Settings.set_value(OPTIONS.REBIND_TAGS_KEY, true)
				_begin_binding()
		return
	_gesture_color = hue
	_gesture_uid = uid
	_gesture_deadline = _ready_clock + float(OPTIONS.DOUBLE_SCAN_MS) / 1000.0
	_feedback_remaining = 0.0


func _reset_gesture() -> void:
	_gesture_color = &""
	_gesture_uid = ""
	_gesture_deadline = -1.0


func _on_practice_toggled(enabled: bool) -> void:
	if not _round_active or _binding or _state.state != RunState.State.READY:
		return
	_practice = enabled
	_reset_gesture()
	_present()


func _on_nfc_availability_changed(available: bool, reason: String) -> void:
	var previously_available := _input_available
	_input_available = available
	if not available:
		_source_note = (
			"NFC is off. Keys and the colour pad are available."
			if reason == "disabled"
			else "No NFC needed: use keys, or the Assisted colour pad."
		)
	elif not _source_note.begins_with("Saved tags"):
		_source_note = "NFC ready. Tap your tags or use the colour keys."
	if _deck != null:
		_sync_deck()
	if not _round_active or _leaving:
		return
	if previously_available and not available:
		if _binding:
			_use_fallback(false)
		_sound.announce("NFC unavailable. Paused; keys and touch are ready.", &"nfc_off")
		open_pause_menu()
	elif available and _physical_run and not _suspended:
		_nfc.start()


func _on_reader_error(message: String) -> void:
	_source_note = "NFC reader: %s. Keys and touch remain available." % message
	_fallback_requested = true
	_sound.announce(_source_note)
	_sync_deck()
	if _round_active and not _leaving:
		open_pause_menu()


func _update_reader_hint(delta: float) -> void:
	if not _round_active or not _physical_run or not _input_available or _reader_hint_given:
		return
	_reader_idle += delta
	if _reader_idle < 30.0:
		return
	_reader_hint_given = true
	_fallback_requested = true
	_source_note = "No tags detected. Check NFC, or use keys and touch."
	_sound.announce(_source_note)
	_sync_deck()


func _base_hue_count(colors: Array[StringName]) -> int:
	var hues: Array[StringName] = []
	for color_id in colors:
		var hue := Palette.hue_id(color_id)
		if not hues.has(hue):
			hues.append(hue)
	return hues.size()


func _contains_shades(colors: Array[StringName]) -> bool:
	for color_id in colors:
		if Palette.shade_index(color_id) != 1:
			return true
	return false


func _reset_prepared_model() -> void:
	_state.reset(_config, _rng.randi())
	_state.drain_events()
	_reset_round_gauge()
	_update_model_hud()


func _configure_mode_ui() -> void:
	super()
	_hint.text = "Watch the whole pattern. Recall after the double cue. Esc pauses."
	(_hint.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_round_instructions.text = "Keep the pattern, chase a clean sweep, then try one more experiment."
	_sync_deck()


func _sync_deck() -> void:
	if _deck == null:
		return
	var labels: Array[String] = []
	for action: StringName in OPTIONS.COLOR_ACTIONS:
		labels.append(Settings.control_key_label(action))
	_deck.configure(
		labels, Settings.control_key_label(OPTIONS.CONFIRM_ACTION),
		Settings.control_key_label(OPTIONS.DARK_ACTION),
		Settings.control_key_label(OPTIONS.LIGHT_ACTION),
		bool(_config.get("shade_mode", false)),
		not _physical_run or not _input_available or _fallback_requested
			or Settings.tunable_bool(OPTIONS.TOUCH_PAD_KEY),
		_available_colors
	)
	_queue_layout()


func _on_controls_changed() -> void:
	_sync_deck()


func _on_game_setting_changed(key: String, _value: Variant) -> void:
	if _deck == null:
		return
	if key == OPTIONS.HAPTICS_KEY:
		_haptics.configure(Settings.tunable(OPTIONS.HAPTICS_KEY))
	elif key == OPTIONS.VOICE_KEY:
		_sound.configure(Settings.tunable_bool(OPTIONS.VOICE_KEY))
	elif key == OPTIONS.TOUCH_PAD_KEY:
		_sync_deck()
	elif key == "ui/scale":
		_resize_hud()
		_queue_layout()


func _set_reduced_motion_enabled(value: bool) -> void:
	super(value)
	if _arena != null:
		_arena.configure_accessibility(value, _intense_effects_enabled)


func _set_intense_effects_enabled(value: bool) -> void:
	super(value)
	if _arena != null:
		_arena.configure_accessibility(_reduced_motion_enabled, value)


## Pause is still the shared overlay; only hardware and local loops need hooks.
func open_pause_menu() -> void:
	if is_instance_valid(_pause_menu) or _leaving or _entering_transition:
		return
	_suspend_sources()
	super()


func _suspend_sources() -> void:
	_suspended = true
	_reset_gesture()
	_motion.reset()
	if _nfc != null:
		_nfc.stop()
	if _sound != null:
		_sound.suspend()
	if _haptics != null:
		_haptics.stop()


func _on_pause_closed() -> void:
	super()
	if not _round_active or _abort_if_exiting():
		return
	_suspended = false
	_state.resume_window()
	_motion.reset()
	_nfc.reset_debounce()
	if _physical_run and _nfc.available():
		_nfc.start()
	_sound.resume()
	if _binding:
		_binding_remaining = BINDING_SECONDS
		_prompt_binding()
	_drain_model_events()
	_present()


func _end_round() -> void:
	if not _round_active or _abort_if_exiting():
		return
	super()


func _finish_round() -> void:
	_binding = false
	_reset_gesture()
	if _completed_run and not _leaving:
		_nfc.stop()
	else:
		_stop_input_and_audio()
	if _deck != null and _deck.is_inside_tree():
		_deck.hide()


func _stop_input_and_audio() -> void:
	if is_instance_valid(_nfc):
		_nfc.stop()
	if is_instance_valid(_sound):
		_sound.stop()
	if is_instance_valid(_haptics):
		_haptics.stop()


func _on_entry_transition_finished(_path: String) -> void:
	_entering_transition = false


func _abort_if_exiting() -> bool:
	if not _leaving and Router.is_transitioning() and not _entering_transition:
		_leaving = true
		_round_active = false
		_finish_round()
	return _leaving


func _on_exit_to_main_menu_pressed() -> void:
	_leaving = true
	_round_active = false
	_finish_round()
	if Router.is_transitioning():
		await Router.transition_finished
	if is_inside_tree():
		Router.goto(main_menu_scene)


func _describe_round_outcome(one: int, _two: int) -> Dictionary:
	var title := "BRIGHT BEGINNINGS"
	if _state.round_n >= 8:
		title = "MEMORY MAESTRO!"
	elif _state.round_n >= 5:
		title = "BRILLIANT EXPERIMENT!"
	elif _state.rounds_cleared > 0:
		title = "A BRIGHT IDEA!"
	return {
		"result": title,
		"subtitle": "Round %d reached. %d robots recalled. %d points.%s" % [
			maxi(_state.round_n, 1), _state.hits, one,
			" Assisted touch run: half score." if _state.assisted else "",
		],
		"color": Color("ffd36c") if _state.round_n >= 5 else player_one_color,
	}


func _round_totals() -> Dictionary:
	return {"hits": _state.hits, "attempts": _state.hits + _state.wrongs + _state.timeouts}


func _player_stats(player_index: int) -> Dictionary:
	if player_index != PLAYER_ONE:
		return super(player_index)
	return {
		"score": _scores[PLAYER_ONE],
		"hits": _state.hits,
		"misses": _state.wrongs + _state.timeouts,
		"accuracy": _accuracy_percent(_state.hits, _state.hits + _state.wrongs + _state.timeouts),
		"streak": _best_streaks[PLAYER_ONE],
	}


func _round_highlight_summary() -> String:
	return "%d rounds cleared  |  %s" % [_state.rounds_cleared, super()]


func _round_mode_summary() -> String:
	return "Memory run - %d colours%s%s" % [
		_available_colors.size(),
		" - shades" if bool(_config.get("shade_mode", false)) else "",
		" - Assisted" if _state.assisted else "",
	]


func _award_round_achievements(_one: int, _two: int) -> void:
	if not _completed_run:
		return
	_unlock_round_achievement("lazer_nfc_first_run")
	if _state.round_n >= 5:
		_unlock_round_achievement("lazer_nfc_round_five")
	if _state.flawless_six:
		_unlock_round_achievement("lazer_nfc_flawless_round")
	if bool(_config["shade_mode"]):
		_unlock_round_achievement("lazer_nfc_shade_run")
	if _state.round_n >= 4 and not _state.assisted:
		_unlock_round_achievement("lazer_nfc_unassisted")


func _share_payload() -> Dictionary:
	var payload := super()
	payload["rounds_cleared"] = _state.rounds_cleared
	payload["round_reached"] = _state.round_n
	payload["assisted"] = _state.assisted
	payload["hits_caption"] = "ROBOTS RECALLED"
	payload["challenge"] = "CAN YOU REACH ROUND %d?" % (maxi(_state.round_n, 1) + 1)
	payload["footer"] = "ONE MORE EXPERIMENT?  |  %s" % StudioInfo.website_label()
	return payload


func _spawn_round_confetti(color: Color) -> void:
	if _intense_effects_enabled:
		super(color)


func _queue_layout() -> void:
	if _layout_queued or not is_inside_tree():
		return
	_layout_queued = true
	_layout_lab.call_deferred()


func _resize_hud() -> void:
	var screen := get_viewport_rect().size
	var preference := float(Settings.get_value("ui/scale", 1.0))
	var factor := maxf(1.0, screen.x * preference / maxf(get_window().size.x, 1.0) / 1.5)
	if screen == _hud_size and is_equal_approx(factor, _ui_factor):
		return
	_hud_size = screen
	_ui_factor = factor
	var compact := screen.y > screen.x
	var pause_parent := _player_one_card.get_parent()
	if _pause_button.get_parent() != pause_parent:
		_pause_button.reparent(pause_parent, false)
	_player_one_card.custom_minimum_size.x = minf(190.0 * _ui_factor, screen.x * 0.3) \
		if compact else 280.0 * _ui_factor
	_pause_button.custom_minimum_size.x = (44.0 if compact else 104.0) * _ui_factor
	_pause_button.text = "II" if compact else "Pause"
	_pause_button.tooltip_text = "Pause"
	_hint.text = "Listen first. Recall after GO." if compact else \
		"Watch the whole pattern. Recall after the double cue. Esc pauses."
	for control: Control in [
		_player_one_caption, _player_one_score, _player_one_streak,
		_time_label, _time_caption, _mode_title, _callout, _hint, _pause_button,
	]:
		if not _hud_font_sizes.has(control):
			_hud_font_sizes[control] = control.get_theme_font_size("font_size")
		control.add_theme_font_size_override(
			"font_size", roundi(float(_hud_font_sizes[control]) * _ui_factor)
		)
	if compact and screen.y < 1000.0:
		_player_one_score.add_theme_font_size_override("font_size", roundi(40.0 * _ui_factor))
		_time_label.add_theme_font_size_override("font_size", roundi(40.0 * _ui_factor))
	_player_one_streak.custom_minimum_size.y = 24.0 * _ui_factor
	if _deck != null:
		_deck.set_ui_scale(_ui_factor)
	_resize_results(screen, compact)


func _build_responsive_results() -> void:
	# Reuse the shell's controls and signals, giving long phone reports a scroll.
	for row: BoxContainer in [
		_play_again_button.get_parent(),
		_back_to_results_button.get_parent(),
		_score_panel.get_node("Layout/Report"),
		_score_panel.get_node("Layout/Overview"),
	]:
		var flexible := BoxContainer.new()
		flexible.name = row.name
		flexible.alignment = row.alignment
		flexible.size_flags_horizontal = row.size_flags_horizontal
		flexible.add_theme_constant_override("separation", row.get_theme_constant("separation"))
		var parent := row.get_parent()
		var index := row.get_index()
		var owned: Array[Node] = []
		for descendant in row.find_children("*", "", true, false):
			if descendant.owner == self:
				owned.append(descendant)
		parent.remove_child(row)
		parent.add_child(flexible)
		parent.move_child(flexible, index)
		for child in row.get_children():
			child.reparent(flexible, false)
		for descendant in owned:
			descendant.owner = self
		row.free()
		_result_rows.append(flexible)
	_results_center = _round_panel.get_parent() as CenterContainer
	var owned_results: Array[Node] = []
	for descendant in _results_center.find_children("*", "", true, false):
		if descendant.owner == self:
			owned_results.append(descendant)
	_results_scroll = ScrollContainer.new()
	_results_scroll.name = "ResultsScroll"
	_results_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_results_scroll.follow_focus = true
	_round_over.add_child(_results_scroll)
	_results_center.reparent(_results_scroll, false)
	_results_center.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	for descendant in owned_results:
		descendant.owner = self
	_results_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for label: Label in [
		_result_label, _round_subtitle, _round_highlight, _round_instructions,
		_score_screen_title, _score_screen_subtitle,
	]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 0.0
	_see_score_button.custom_minimum_size.x = 0.0
	(_score_panel.get_node("Layout/Actions") as Control).custom_minimum_size.x = 0.0
	(_score_panel.get_node("Layout/Report/SharePanel") as Control).custom_minimum_size.x = 0.0


func _resize_results(screen: Vector2, compact: bool) -> void:
	if _results_scroll == null:
		return
	var margin := 22.0 * _ui_factor
	var available := screen - Vector2.ONE * margin * 2.0
	var width := minf(available.x - 18.0, (720.0 if compact else 1180.0) * _ui_factor)
	_round_panel.custom_minimum_size.x = width if compact else minf(width, 850.0)
	_score_panel.custom_minimum_size.x = width
	for row in _result_rows:
		row.vertical = compact
	for panel: Control in [_round_panel, _score_panel]:
		for descendant in panel.find_children("*", "Control", true, false):
			var control := descendant as Control
			if control is Label or control is Button:
				if not _hud_font_sizes.has(control):
					_hud_font_sizes[control] = control.get_theme_font_size("font_size")
				control.add_theme_font_size_override(
					"font_size", roundi(float(_hud_font_sizes[control]) * _ui_factor)
				)
	_fit_results_scroll.call_deferred()


func _fit_results_scroll() -> void:
	if not is_inside_tree() or _results_scroll == null:
		return
	var margin := 22.0 * _ui_factor
	var available := get_viewport_rect().size - Vector2.ONE * margin * 2.0
	# Let the child constraints shrink before sizing a non-scrolling horizontal axis.
	_results_scroll.position = Vector2.ONE * margin
	_results_scroll.size = available
	_results_center.custom_minimum_size.y = available.y


func _layout_lab() -> void:
	_layout_queued = false
	if _arena == null or _deck == null or not is_inside_tree() or _leaving:
		return
	_resize_hud()
	var bounds := _content_bounds()
	var deck_height := maxf(
		_deck.preferred_height(bounds.size.x), _deck.get_combined_minimum_size().y
	)
	_deck.position = Vector2(bounds.position.x, bounds.end.y - deck_height)
	_deck.size = Vector2(bounds.size.x, deck_height)
	_arena.position = bounds.position
	_arena.size = Vector2(bounds.size.x, maxf(_deck.position.y - bounds.position.y - 14.0, 1.0))


func _content_bounds() -> Rect2:
	var screen := get_viewport_rect().size
	var top := maxf(190.0 * _ui_factor, _callout.get_global_rect().end.y + 10.0 * _ui_factor)
	var layout := _callout.get_parent() as BoxContainer
	var margins := layout.get_parent() as MarginContainer
	var hint_panel := _hint.get_parent() as Control
	var bottom := screen.y - margins.get_theme_constant("margin_bottom") \
		- hint_panel.get_combined_minimum_size().y - 24.0 * _ui_factor
	var caption := layout.get_node("AudioCaption") as Control
	if caption.visible:
		bottom -= caption.get_combined_minimum_size().y + layout.get_theme_constant("separation")
	bottom = minf(bottom, screen.y - _capture_inset)
	var margin := 32.0 * _ui_factor
	return Rect2(Vector2(margin, top),
		Vector2(maxf(screen.x - margin * 2.0, 1.0), maxf(bottom - top, 1.0)))


## The host's development recorder reserves room for its teaching captions.
func _set_capture_inset(bottom: float) -> void:
	_capture_inset = maxf(bottom, 0.0)
	_queue_layout()


func _playfield_bounds() -> Rect2:
	if _arena != null:
		return Rect2(_arena.position, _arena.size)
	return super()
