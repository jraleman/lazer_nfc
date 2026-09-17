extends SceneTree

## Pure deterministic regressions: no scene, Settings or autoload instance imports.

const OPTIONS := preload("res://games/lazer_nfc/lazer_nfc_options.gd")
const Palette := preload("res://games/lazer_nfc/run/palette.gd")
const Sequence := preload("res://games/lazer_nfc/run/sequence.gd")
const RunState := preload("res://games/lazer_nfc/run/run_state.gd")

var _failures := PackedStringArray()
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_ready_and_show()
	_test_clean_scoring_and_atomic_input()
	_test_palette_scoring()
	_test_wrong_and_timeout()
	_test_grace_and_event_ages()
	_test_resume()
	_test_palette_growth_and_ramps()
	_test_bound_palette_holes()
	_test_shades()
	_test_assisted_scoring()
	_test_momentum_bounds()
	_test_frame_splits_and_hitches()
	_test_replay_and_generator()
	_test_invalid_configuration_and_deltas()
	if _failures.is_empty():
		print("LaZer NFC run tests passed (%d checks)." % _checks)
		quit(0)
	else:
		for failure: String in _failures:
			printerr(failure)
		quit(1)


func _test_ready_and_show() -> void:
	var model := _model()
	_expect(RunState.State.keys() == [
		"READY", "ROUND_START", "SHOWING", "SHOW_END", "AWAITING",
		"RECALL_GAP", "ROUND_WON", "RUN_OVER",
	], "Binding must remain scene-owned; atomic resolution needs no accepting state.")
	_expect(model.state == RunState.State.READY and model.round_n == 0
		and model.clock == 0.0 and model.sequence.is_empty(), "Reset must enter idle READY.")
	model.advance(20.0)
	_expect(model.clock == 0.0, "READY must not consume active run time.")
	_expect(not model.answer(&"red", 0.0, 0.0, true),
		"Sound practice must not be interpreted as a scored answer.")
	_expect(model.hits == 0 and model.wrongs == 0 and not model.assisted,
		"An early touch cannot spend lives, earn points or mark assistance.")
	_expect(_event_count(model.drain_events(), &"not_yet") == 1,
		"Early input must emit a readable not-yet event.")
	model.begin()
	model.begin()
	_expect(model.round_n == 1 and model.state == RunState.State.ROUND_START,
		"Repeated begin calls cannot restart the clock or duplicate a round.")
	model.drain_events()
	model.advance(OPTIONS.ROUND_START_TIME)
	_expect(model.snapshot()["visible_color"] == model.sequence[0],
		"The first visible instrument must match the first played note.")
	_expect(not model.answer(model.sequence[0]), "Answers during SHOWING must be ignored.")
	model.advance(OPTIONS.SHOW_TIME)
	_expect(model.state == RunState.State.SHOWING
		and model.snapshot()["visible_color"] == &"", "A show gap must hide the old colour.")
	var events := model.drain_events()
	_expect(_event_count(events, &"note") == 1 and _event_count(events, &"note_end") == 1,
		"Each visible note must have its own end event.")
	_reach_recall(model)
	_expect_approx(model.clock, 4.7, "Default first recall time, including the final show gap")
	_expect_approx(model.window_started_at, 4.7, "Actual first window opening")
	_expect_approx(model.window_deadline, 8.7, "Visible first deadline")
	_expect_approx(model.window_physical_deadline, 8.85, "Physical-event grace deadline")
	_expect_approx(model.window_timeout_at, 8.93, "NFC delivery deadline")
	var snapshot := model.snapshot()
	var expected_keys: Array[String] = [
		"state", "round", "length", "recall_index", "show_index", "visible_color",
		"active_palette", "window_ratio", "lives", "combo", "multiplier", "score",
		"best_combo", "rounds_cleared", "shade_mode",
	]
	_expect(snapshot.size() == expected_keys.size(),
		"The presentation snapshot must not acquire a hidden answer channel.")
	for key: String in expected_keys:
		_expect(snapshot.has(key), "The contracted snapshot needs %s." % key)
	_expect(snapshot["state"] is StringName and snapshot["state"] == &"AWAITING"
		and snapshot["visible_color"] == &"", "Recall must be an unlabelled silhouette.")
	var palette: Array = snapshot["active_palette"]
	_expect(palette.get_typed_builtin() == TYPE_STRING_NAME,
		"Snapshot palettes must retain their element type.")
	palette.clear()
	snapshot["score"] = 999
	_expect(model.active_palette.size() == 4 and model.score == 0,
		"A presentation snapshot must not mutate the live model.")
	for event: Dictionary in model.drain_events():
		_expect(event["type"] is StringName, "Event types must be StringNames.")
		if event["type"] == &"awaiting":
			_expect(not event.has("color_id") and not event.has("sequence"),
				"Opening a recall window must not leak its answer in an event.")
	var cue := _model()
	cue.begin()
	cue.advance(4.1)
	_expect(cue.state == RunState.State.SHOW_END
		and _event_count(cue.drain_events(), &"go") == 0,
		"The show-end rest must not tell players to answer a closed window.")
	cue.advance(0.6)
	_expect(cue.state == RunState.State.AWAITING
		and _event_count(cue.drain_events(), &"go") == 1
		and cue.answer(cue.sequence[0]),
		"An immediate response to the double GO cue must be accepted.")


func _test_clean_scoring_and_atomic_input() -> void:
	var model := _open_first()
	_expect(model.answer(model.sequence[0]), "An exact answer in the window must hit.")
	_expect(model.score == 125 and model.combo == 1 and model.best_combo == 1,
		"The first full-window hit must include the newly earned 1.25x combo.")
	_expect(model.state == RunState.State.RECALL_GAP and model.recall_index == 1,
		"A hit must resolve atomically into the half-second gap.")
	_expect(not model.answer(model.sequence[1]) and model.hits == 1,
		"A second input in the same frame cannot hit the next enemy or queue itself.")
	model.advance(0.499)
	_expect(model.state == RunState.State.RECALL_GAP, "Recall must not restart early.")
	model.advance(0.001)
	_expect(model.state == RunState.State.AWAITING and model.hits == 1,
		"Opening the next window must not replay a queued gap input.")
	_expect(not model.answer(model.sequence[1], 0.01) and model.hits == 1,
		"A stale callback from before the new window must not score.")
	_expect(model.answer(model.sequence[1]), "A current event can answer the new enemy.")
	_expect(model.score == 275 and model.combo == 2, "The second clean hit must earn 150.")
	_reach_recall(model)
	_expect(model.answer(model.sequence[2]), "The last correct colour must clear the round.")
	_expect(model.score == 750 and model.combo == 3 and model.hits == 3,
		"125 + 150 + 175 plus the doubled 300-point bonus must total 750.")
	_expect(model.rounds_cleared == 1 and model.lives == 3,
		"A clean round must preserve the life pool and increment clear count.")
	var events := model.drain_events()
	var won := _last_event(events, &"round_won")
	_expect(won.get("points") == 300 and won.get("perfect") == true,
		"A no-life-lost clear must emit its doubled bonus explicitly.")
	_expect(_event_count(events, &"hit") == 3 and _event_count(events, &"round_won") == 1,
		"Atomic input must award every hit and the clear bonus exactly once.")
	_expect(model.snapshot()["visible_color"] == &"", "The recap state cannot leak a note.")
	_reach_recall(model)
	_expect(model.round_n == 2 and model.sequence.size() == 4, "Round two adds one note.")
	_expect_approx(model.window_duration, 3.8, "Standard round-two recall window")
	_expect_approx(model.show_duration, 0.75, "Standard round-two show time")


func _test_wrong_and_timeout() -> void:
	var wrong := _open_first()
	var deadline := wrong.window_deadline
	var timeout_at := wrong.window_timeout_at
	_expect(not wrong.answer(_different(wrong)), "A known wrong colour cannot report a hit.")
	_expect(wrong.wrongs == 1 and wrong.lives == 2 and wrong.recall_index == 0,
		"A wrong colour costs exactly one life but keeps the enemy.")
	_expect(wrong.state == RunState.State.AWAITING and wrong.combo == 0,
		"Wrong resolution is atomic and returns to this same window.")
	_expect(wrong.window_deadline == deadline and wrong.window_timeout_at == timeout_at,
		"Wrong answers must never extend either visible or dispatch deadlines.")
	_clear_wave(wrong)
	_expect(wrong.score == 600 and wrong.rounds_cleared == 1,
		"Three corrected hits plus the ordinary 150-point bonus must total 600.")
	var won := _last_event(wrong.drain_events(), &"round_won")
	_expect(won.get("perfect") == false and won.get("points") == 150,
		"Losing a life removes only the clean-round doubling.")

	var model := _open_first({"lives": 5, "start_length": 2, "scan_window": 2.0})
	model.drain_events()
	model.answer(_different(model))
	deadline = model.window_deadline
	model.advance(deadline - model.clock)
	_expect(model.window_remaining == 0.0 and model.state == RunState.State.AWAITING,
		"Visible expiry must not prematurely dispatch the physical-event grace timeout.")
	_expire_window(model)
	_expect(model.timeouts == 1 and model.wrongs == 1 and model.lives == 3
		and model.recall_index == 1, "Wrong plus timeout must cost two lives, not one or three.")
	_reach_recall(model)
	_expire_window(model)
	_expect(model.lives == 2 and model.timeouts == 2 and model.score == 0
		and model.rounds_cleared == 0, "An escaping final enemy must not earn a clear bonus.")
	_expect(_event_count(model.drain_events(), &"round_won") == 0,
		"A final escape must not announce a successful clear.")
	_reach_recall(model)
	_expect(model.round_n == 2 and model.sequence.size() == 3,
		"A final escape with lives remaining must progress rather than softlock.")
	model.advance(1000.0)
	_expect(model.state == RunState.State.RUN_OVER and model.lives == 0
		and model.timeouts == 4, "A large hitch must exhaust the remaining pool exactly.")
	var end_clock := model.clock
	var events := model.drain_events()
	_expect(_event_count(events, &"run_over") == 1, "Run completion must be emitted once.")
	model.advance(1000.0)
	model.answer(model.sequence[model.recall_index])
	model.resume_window()
	_expect(model.clock == end_clock and model.lives == 0,
		"Completed runs must stop their clock and never spend negative lives.")
	_expect(_event_count(model.drain_events(), &"run_over") == 0,
		"Later advances, input and resume cannot emit a second completion.")

	var last_life := _open_first({"lives": 1})
	last_life.drain_events()
	last_life.answer(_different(last_life))
	_expect(last_life.state == RunState.State.RUN_OVER and last_life.lives == 0
		and last_life.wrongs == 1, "A wrong colour on the final life must end immediately.")
	_expect(_event_count(last_life.drain_events(), &"run_over") == 1,
		"The immediate wrong-answer end must use the same single completion door.")


func _test_palette_scoring() -> void:
	var small := _open_first({"palette_start": 3})
	small.answer(small.sequence[0])
	_expect(small.score == 106,
		"The documented palette formula gives three hues 0.85x, below the four-hue baseline.")
	var full := _open_first({"palette_start": 7})
	full.answer(full.sequence[0])
	_expect(full.score == 181, "Seven active hues must give the documented 1.45x factor.")
	var shades := _open_first({"palette_start": 7, "shade_mode": true})
	shades.answer(shades.sequence[0])
	_expect(shades.score == 272,
		"The complete 21-tag mode uses seven hues at 1.45x and a separate 1.5x shade factor.")
	var available: Array[StringName] = [&"orange", &"indigo", &"violet"]
	var limited := _open_first({"palette_start": 7, "available_colors": available})
	limited.answer(limited.sequence[0])
	_expect(limited.score == small.score,
		"Palette difficulty must reflect usable hues, not unavailable requested colours.")


func _test_grace_and_event_ages() -> void:
	var exact := _open_first()
	exact.advance(exact.window_duration)
	_expect(exact.answer(exact.sequence[0]) and exact.score == 63,
		"An answer at visible expiry must earn the clamped minimum-time hit.")
	var physical := _open_first()
	physical.advance(physical.window_duration + 0.15)
	_expect(physical.answer(physical.sequence[0]) and physical.score == 63,
		"A key at the physical grace boundary is still timely, without negative time points.")

	var late_key := _open_first()
	late_key.advance(late_key.window_duration + 0.16)
	_expect(late_key.state == RunState.State.AWAITING and late_key.timeouts == 0,
		"The callback delivery allowance must remain open after physical grace.")
	_expect(not late_key.answer(late_key.sequence[0], 0.0, 0.0, true),
		"An uncompensated late key must not borrow the NFC callback allowance.")
	_expect(late_key.hits == 0 and late_key.lives == 3 and not late_key.assisted,
		"Ignored late input cannot change scoring, assistance or the pending life loss.")
	_expect(_last_event(late_key.drain_events(), &"not_yet").get("reason") == &"after_deadline",
		"A late physical event must explain why it was ignored.")
	_expire_window(late_key)
	_expect(late_key.timeouts == 1 and late_key.lives == 2,
		"The original timeout must still dispatch after ignoring a late key.")

	var nfc := _open_first()
	nfc.advance(nfc.window_duration + 0.23)
	_expect(nfc.state == RunState.State.AWAITING and nfc.timeouts == 0,
		"Timeout dispatch must leave room for the entire 80 ms NFC compensation.")
	_expect(nfc.answer(nfc.sequence[0], 0.08) and nfc.score == 63,
		"A callback aged 80 ms at the final physical grace boundary must still hit.")
	var too_late := _open_first()
	too_late.advance(too_late.window_duration + 0.230001)
	_expect(too_late.timeouts == 1 and not too_late.answer(too_late.sequence[0], 0.08),
		"A callback arriving after the dispatch horizon cannot resurrect the old enemy.")

	var invalid := _open_first()
	invalid.drain_events()
	var ages: Array[float] = [-0.01, NAN, INF, 100.0, OPTIONS.MAX_ANSWER_AGE_S + 0.001]
	for age: float in ages:
		_expect(not invalid.answer(invalid.sequence[0], age, 0.0, true),
			"Invalid or forged ages must not be accepted: %s." % str(age))
	_expect(not invalid.answer(invalid.sequence[0], 0.08),
		"Even an ordinary NFC age is stale if it predates this window.")
	_expect(invalid.score == 0 and invalid.hits == 0 and invalid.wrongs == 0
		and invalid.lives == 3 and not invalid.assisted,
		"Invalid and pre-window timestamps must be side-effect free.")
	_expect(_event_count(invalid.drain_events(), &"not_yet") == ages.size() + 1,
		"Every invalid timestamp needs a visible ignored-input event.")
	invalid.advance(0.08)
	_expect(invalid.answer(invalid.sequence[0], 0.08) and invalid.score == 125,
		"Compensation must recover a genuinely on-opening scan without exceeding full points.")


func _test_resume() -> void:
	var model := _open_first()
	model.advance(1.25)
	var clock_before := model.clock
	var index_before := model.recall_index
	var original_deadline := model.window_deadline
	model.drain_events()
	model.resume_window()
	_expect(model.clock == clock_before and model.recall_index == index_before,
		"Resume must not advance time or skip the current enemy.")
	_expect_approx(model.window_remaining, model.window_duration, "Full resumed window")
	_expect(model.window_started_at == clock_before and model.window_deadline > original_deadline,
		"Resume must create genuinely new window boundaries, not just refill a gauge.")
	_expect_approx(model.window_deadline, clock_before + model.window_duration,
		"Resumed visible deadline")
	_expect_approx(model.window_timeout_at, model.window_deadline + 0.23,
		"Resumed dispatch deadline")
	_expect(_event_count(model.drain_events(), &"awaiting") == 1,
		"Resume must reissue the current silhouette/timer event.")
	_expect(not model.answer(model.sequence[0], 0.08),
		"A queued pre-resume callback must not enter the freshly reissued window.")
	model.advance(0.08)
	_expect(model.answer(model.sequence[0], 0.08), "A new resumed scan must work normally.")
	var gap_snapshot := model.snapshot()
	model.resume_window()
	_expect(_equivalent(model.snapshot(), gap_snapshot),
		"Resuming a gap cannot manufacture an early window.")


func _test_palette_growth_and_ramps() -> void:
	var model := _model()
	var previous: Array[StringName] = []
	for number in range(1, 17):
		_reach_recall(model)
		var expected_hues := mini(4 + int(number >= 3) + int(number >= 5)
			+ int(number >= 7), 7)
		_expect(model.round_n == number and model.sequence.size() == mini(number + 2, 12),
			"Each wave grows by one note until twelve, including capped later waves.")
		_expect(model.active_palette.size() == expected_hues,
			"Hue activation must happen only on the documented growth rounds.")
		if previous.size() == OPTIONS.SEQ_LEN_MAX:
			_expect(model.sequence.slice(0, OPTIONS.SEQ_LEN_MAX - 1) == previous.slice(1),
				"At the cap the remembered suffix rolls forward, rather than freezing forever.")
			_expect(model.sequence.back() != previous.back() and model.sequence != previous,
				"Every capped round must introduce a genuinely new ending.")
		else:
			_expect(model.sequence.slice(0, previous.size()) == previous,
				"Before the cap, growing the pattern must retain its learned prefix.")
		_expect(model.window_duration >= 2.0 and model.show_duration >= 0.5,
			"Difficulty ramp floors must survive arbitrarily deep rounds.")
		if number < 4:
			for index in range(1, model.sequence.size()):
				_expect(model.sequence[index] != model.sequence[index - 1],
					"Adjacent repeats must be absent before round four.")
		var added: Array[StringName] = []
		if number == 3:
			added = [&"orange"]
		elif number == 5:
			added = [&"indigo"]
		elif number == 7:
			added = [&"violet"]
		var event := _last_event(model.drain_events(), &"round_started")
		_expect(event.get("new_colors") == added,
			"Round announcements must name exactly the newly usable instruments.")
		previous = model.sequence.duplicate()
		_clear_wave(model)
	_expect(model.flawless_six and model.best_combo == model.hits,
		"A clean six-note wave and peak combo must survive later rounds.")
	_expect_approx(float(model.snapshot()["multiplier"]), 4.0, "Deep-run combo cap")
	_expect_approx(model.window_duration, 2.0, "Deep-run recall floor")
	_expect_approx(model.show_duration, 0.5, "Deep-run show floor")
	_reach_recall(model)
	var best_before := model.best_combo
	model.answer(_different(model))
	_expect(model.combo == 0 and model.best_combo == best_before and model.flawless_six,
		"Mistakes must not regress the run's peak combo or earned flawless-six flag.")

	for ramp in 3:
		var ramped := _model({"scan_window": 6.0, "ramp": ramp})
		_clear_wave(ramped)
		_reach_recall(ramped)
		_expect_approx(ramped.window_duration, 6.0 - OPTIONS.WINDOW_RAMP[ramp],
			"Each named ramp must actually affect recall time")
		_expect_approx(ramped.show_duration, 0.8 - OPTIONS.SHOW_RAMP[ramp],
			"Each named ramp must actually affect show time")
		for count in 5:
			_clear_wave(ramped)
		_reach_recall(ramped)
		_expect_approx(ramped.show_duration,
			maxf(0.5, 0.8 - (ramped.round_n - 1) * OPTIONS.SHOW_RAMP[ramp]),
			"Each show ramp must stop at its hardware-safe floor")


func _test_bound_palette_holes() -> void:
	var available: Array[StringName] = [&"violet", &"orange", &"indigo", &"green", &"blue"]
	var model := _model({"available_colors": available, "palette_start": 3})
	var supplied := available.duplicate()
	available.clear()
	_expect(model.active_palette == [&"green", &"blue", &"orange"],
		"A missing red/yellow must not be fabricated from a bound-tag count.")
	for number in range(1, 8):
		_reach_recall(model)
		for id: StringName in model.active_palette:
			_expect(supplied.has(id), "Every activated id must have a real usable tag.")
		for id: StringName in model.sequence:
			_expect(model.active_palette.has(id), "Generated notes must be physically answerable.")
		var lives_before := model.lives
		_expect(not model.answer(&"red", 0.0, 0.0, true),
			"A valid but unavailable tag colour must be ignored.")
		if number < 3:
			_expect(not model.answer(&"indigo"), "A future palette colour is not active yet.")
		_expect(model.lives == lives_before and model.wrongs == 0 and not model.assisted,
			"Unavailable and inactive colours cannot penalise or mark the run.")
		_expect(_event_count(model.drain_events(), &"unknown") >= 1,
			"Unavailable colours must emit an unknown event, never silently disappear.")
		_expect(model.active_palette.size() == mini(3 + int(number >= 3)
			+ int(number >= 5) + int(number >= 7), 5),
			"Growth must be capped by usable tags, not by the requested starting size.")
		_clear_wave(model)
	var partial: Array[StringName] = [
		&"red_dark", &"yellow_light", &"blue_dark", &"blue", &"indigo_light", &"violet",
	]
	var shades := _model({
		"shade_mode": true, "palette_start": 3, "available_colors": partial,
	})
	_expect(shades.active_palette == [&"red_dark", &"yellow_light", &"blue_dark", &"blue"],
		"Shade mode must preserve exact UID holes, even where a base shade is missing.")
	for number in range(1, 8):
		_reach_recall(shades)
		for id: StringName in shades.active_palette:
			_expect(partial.has(id), "Shade growth must never invent an unbound shade.")
		for id: StringName in shades.sequence:
			_expect(partial.has(id), "Every shown shade must have an actual bound instrument.")
		_clear_wave(shades)
	var pair: Array[StringName] = [&"orange", &"violet"]
	var two := _open_first({"available_colors": pair})
	_expect(two.active_palette.size() == 2 and two.sequence.size() == 3,
		"A reduced but playable physical palette must remain capped and usable.")
	for index in range(1, two.sequence.size()):
		_expect(two.sequence[index] != two.sequence[index - 1],
			"Small available palettes must still generate without repeat retries.")


func _test_shades() -> void:
	var model := _open_first({"shade_mode": true})
	_expect(model.active_palette.size() == 12 and model.snapshot()["shade_mode"] == true,
		"Four active hues in advanced mode must expose all twelve usable shades.")
	model.sequence[0] = &"blue_dark"
	var deadline := model.window_deadline
	_expect(not model.answer(&"blue"), "Right hue but wrong shade must still be wrong.")
	var wrong := _last_event(model.drain_events(), &"wrong")
	_expect(wrong.get("near_miss") == true and wrong.get("expected_color") == &"blue_dark",
		"A shade near miss must carry enough information for its teaching cue.")
	_expect(model.lives == 2 and model.window_deadline == deadline,
		"Shade mistakes obey the same one-life, original-window rule.")
	_expect(model.answer(&"blue_dark") and model.score == 188,
		"The exact dark id must hit, with a 1.5x shade factor rather than a 12-hue factor.")
	var full := _model({"shade_mode": true})
	for number in range(1, 8):
		_reach_recall(full)
		_clear_wave(full)
	_expect(full.active_palette.size() == 21, "The growth path must reach all 21 instruments.")
	for id: StringName in Palette.all_ids(true):
		var other := &"red" if id != &"red" else &"blue"
		var available: Array[StringName] = [id, other]
		var one := _open_first({
			"shade_mode": true, "available_colors": available, "start_length": 2,
		})
		_expect(one.sequence.has(id), "Every one of the 21 ids must really be generatable.")
		_clear_wave(one)
		_expect(one.hits == 2 and one.wrongs == 0,
			"Every advanced instrument must be exactly recallable: %s." % id)


func _test_assisted_scoring() -> void:
	var assisted := _model()
	var ordinary := _model()
	for index in 8:
		_reach_recall(assisted)
		_reach_recall(ordinary)
		var mark_touch := index == 1 or index == 2 or index == 5
		_expect(ordinary.answer(ordinary.sequence[ordinary.recall_index]),
			"The unassisted scoring reference must hit.")
		_expect(assisted.answer(assisted.sequence[assisted.recall_index], 0.0, 0.0, mark_touch),
			"A touch answer has the same correctness rules.")
		var expected := floori(ordinary.score * 0.5) if index >= 1 else ordinary.score
		_expect(assisted.score == expected and assisted.snapshot()["score"] == expected,
			"Assistance must halve the accumulated total once, including later hits and bonuses.")
		_expect(assisted.assisted == (index >= 1),
			"The assistance flag starts at the first valid touch and remains sticky.")
	var ordinary_score := ordinary.score
	var halved_score := assisted.score
	ordinary.advance(1000.0)
	assisted.advance(1000.0)
	_expect(ordinary.score == ordinary_score and assisted.score == halved_score,
		"Run-over processing must not apply the assistance penalty again.")
	_expect(_last_event(assisted.drain_events(), &"run_over").get("score") == halved_score,
		"The completion event must publish the already adjusted model score.")

	var wrong_touch := _open_first()
	wrong_touch.answer(wrong_touch.sequence[0])
	_reach_recall(wrong_touch)
	var prior_score := wrong_touch.score
	wrong_touch.answer(_different(wrong_touch), 0.0, 0.0, true)
	_expect(wrong_touch.assisted and wrong_touch.score == floori(prior_score * 0.5),
		"A timely wrong touch is still an answer and must immediately rebase banked points.")
	var rebased := wrong_touch.score
	wrong_touch.answer(_different(wrong_touch), 0.0, 0.0, true)
	_expect(wrong_touch.score == rebased,
		"Repeated wrong touches must not repeatedly compound the penalty.")


func _test_momentum_bounds() -> void:
	var still := _open_first()
	still.answer(still.sequence[0], 0.0, -100.0)
	_expect(still.score == 125, "Negative motion must clamp to no bonus, not subtract points.")
	var moving := _open_first()
	moving.answer(moving.sequence[0], 0.0, 25.0)
	_expect(moving.score == 188, "Full momentum must grant the documented maximum 50% bonus.")
	var forged := _open_first()
	forged.answer(forged.sequence[0], 0.0, 1000000.0)
	_expect(forged.score == moving.score, "Unbounded motion cannot forge unbounded points.")
	var invalid := _open_first()
	for energy: float in [NAN, INF, -INF]:
		_expect(not invalid.answer(invalid.sequence[0], 0.0, energy, true),
			"Non-finite motion cannot be used in scoring.")
	_expect(invalid.hits == 0 and invalid.lives == 3 and not invalid.assisted,
		"Invalid motion must not mutate score, lives or the assistance flag.")


func _test_frame_splits_and_hitches() -> void:
	for lower_point in range(64, 125):
		var point_models: Array[RunState] = []
		for step: float in [1.0 / 30.0, 1.0 / 60.0, INF]:
			var boundary_model := _open_first()
			var fraction := (lower_point + 0.5) / 62.5 - 1.0
			var delay := boundary_model.window_duration * (1.0 - fraction)
			_advance_split(boundary_model, delay, step)
			boundary_model.answer(boundary_model.sequence[0])
			point_models.append(boundary_model)
		_expect(point_models[0].score == lower_point + 1
			and point_models[1].score == lower_point + 1
			and point_models[2].score == lower_point + 1,
			"Exact half-point scores must round identically across frame splits: %d.5."
			% lower_point)
	var thirty := _scripted_run(1.0 / 30.0)
	var sixty := _scripted_run(1.0 / 60.0)
	var hitches := _scripted_run(INF)
	_expect_models_equal(thirty, sixty, "30 Hz versus 60 Hz")
	_expect_models_equal(thirty, hitches, "Frame updates versus crossed-boundary hitches")
	var events := thirty.drain_events()
	_expect(_equivalent(events, sixty.drain_events()),
		"30 Hz and 60 Hz must emit identical ordered events and event-time scoring.")
	_expect(_equivalent(events, hitches.drain_events()),
		"Large show/recall transitions must not skip or duplicate presentation events.")
	var tiny := _model({"lives": 5, "start_length": 2, "scan_window": 2.0})
	var huge := _model({"lives": 5, "start_length": 2, "scan_window": 2.0})
	tiny.begin()
	huge.begin()
	_advance_split(tiny, 1000.0, 1.0 / 60.0)
	huge.advance(1000.0)
	_expect_models_equal(tiny, huge, "Untouched run at 60 Hz versus one huge hitch")
	_expect(_equivalent(tiny.drain_events(), huge.drain_events()),
		"A hitch crossing timeouts and a new wave must retain every event in order.")


func _test_replay_and_generator() -> void:
	var model := _scripted_run(INF)
	model.drain_events()
	model.reset({}, 17)
	_expect(model.clock == 0.0 and model.round_n == 0 and model.state == RunState.State.READY,
		"Replay must reset both the phase and the explicit clock.")
	_expect(model.score == 0 and model.combo == 0 and model.best_combo == 0
		and model.hits == 0 and model.wrongs == 0 and model.timeouts == 0,
		"Replay must clear every per-run score and accuracy counter.")
	_expect(not model.assisted and not model.flawless_six and model.rounds_cleared == 0
		and model.sequence.is_empty() and model.drain_events().is_empty(),
		"Replay must discard flags, the old pattern and undrained completion events.")
	_expect(model.lives == 3 and model.active_palette == [&"red", &"yellow", &"green", &"blue"],
		"Replay must restore the requested pool and initial palette.")
	_expect(model.window_started_at == 0.0 and model.window_deadline == 0.0
		and model.window_timeout_at == 0.0 and model.window_remaining == 0.0,
		"Replay must not retain a stale recall window.")
	var fresh := _model({}, 17)
	_reach_recall(model)
	_reach_recall(fresh)
	_expect_models_equal(model, fresh, "Seeded replay versus a fresh run")
	_expect(_equivalent(model.drain_events(), fresh.drain_events()),
		"Reusing a seed must reproduce the opening event stream.")
	var generator := Sequence.new()
	var colors := Palette.all_ids()
	generator.reset(0)
	var first := generator.grow([], 12, colors, 1)
	generator.reset(0)
	_expect(first == generator.grow([], 12, colors, 1),
		"Seed zero must also be reproducible, never secretly randomised.")
	for index in range(1, first.size()):
		_expect(first[index] != first[index - 1],
			"Direct early-round generation must never rely on retrying an adjacent repeat.")
	generator.reset(1)
	var observed_repeat := false
	for sample in 32:
		var later := generator.grow([], 12, colors, 4)
		for index in range(1, later.size()):
			observed_repeat = observed_repeat or later[index] == later[index - 1]
	_expect(observed_repeat, "Round-four generation must really permit adjacent repeats.")


func _test_invalid_configuration_and_deltas() -> void:
	var model := _open_first()
	model.drain_events()
	var before := model.snapshot()
	var before_sequence := model.sequence.duplicate()
	var before_clock := model.clock
	var bad_configs: Array[Dictionary] = [
		{"lives": 0}, {"lives": 6}, {"lives": 2.5}, {"lives": true},
		{"scan_window": 1.99}, {"scan_window": 6.01}, {"scan_window": NAN},
		{"scan_window": INF}, {"scan_window": "fast"},
		{"ramp": -1}, {"ramp": 3}, {"ramp": 0.5},
		{"start_length": 1}, {"start_length": 5},
		{"palette_start": 2}, {"palette_start": 8},
		{"shade_mode": 1}, {"lives_typo": 3}, {42: 3},
		{"available_colors": []}, {"available_colors": [&"red"]},
		{"available_colors": [&"red", &"red", &"blue"]},
		{"available_colors": [&"red", &"mauve", &"blue"]},
		{"available_colors": ["red", "yellow", "blue"]},
		{"available_colors": PackedStringArray(["red", "yellow", "blue"])},
		{"available_colors": [&"red_dark", &"blue_light"]},
	]
	# These deliberate failures must report an error, without flooding the runner.
	var print_errors := Engine.print_error_messages
	Engine.print_error_messages = false
	for config: Dictionary in bad_configs:
		model.last_error = ""
		model.reset(config)
		_expect(not model.last_error.is_empty(),
			"Invalid config must surface a clear error: %s." % str(config))
		_expect(_equivalent(model.snapshot(), before) and model.sequence == before_sequence
			and model.clock == before_clock and model.drain_events().is_empty(),
			"Rejecting config must be atomic, not silently start a default or partly reset run.")
	for delta: float in [-1.0, NAN, INF, -INF]:
		model.last_error = ""
		model.advance(delta)
		_expect(not model.last_error.is_empty(), "Invalid delta must surface a clear error.")
		_expect(model.clock == before_clock and _equivalent(model.snapshot(), before)
			and model.drain_events().is_empty(), "An invalid delta cannot change model state.")
	Engine.print_error_messages = print_errors
	model.reset({
		"lives": 1, "scan_window": 2.0, "ramp": 0,
		"start_length": 2, "palette_start": 3, "shade_mode": false,
	})
	_expect(model.last_error.is_empty() and model.lives == 1,
		"The lower documented option limits must form a valid run.")
	model.reset({
		"lives": 5, "scan_window": 6.0, "ramp": 2,
		"start_length": 4, "palette_start": 7, "shade_mode": true,
	})
	_expect(model.last_error.is_empty() and model.lives == 5
		and model.active_palette.size() == 21, "The upper documented limits must work too.")
	model.begin()
	model.advance(0.0)
	_expect(model.clock == 0.0 and model.state == RunState.State.ROUND_START,
		"A zero delta is valid but cannot invent elapsed time.")


func _model(config: Dictionary = {}, seed_value: int = 17) -> RunState:
	var model := RunState.new()
	model.reset(config, seed_value)
	_expect(model.last_error.is_empty(), "Test setup must use a valid model config.")
	return model


func _open_first(config: Dictionary = {}, seed_value: int = 17) -> RunState:
	var model := _model(config, seed_value)
	_reach_recall(model)
	return model


func _reach_recall(model: RunState, split: float = INF) -> void:
	if model.state == RunState.State.READY:
		model.begin()
	for transition in 64:
		if model.state == RunState.State.AWAITING:
			return
		if model.state == RunState.State.RUN_OVER:
			_expect(false, "A regression helper unexpectedly reached an exhausted run.")
			return
		var boundary: float = model.get("_next_transition_at")
		_advance_split(model, maxf(0.0, boundary - model.clock), split)
	_expect(false, "The next recall window must be reachable within one complete show.")


func _clear_wave(model: RunState) -> void:
	_reach_recall(model)
	var remaining := model.sequence.size() - model.recall_index
	for index in remaining:
		_reach_recall(model)
		_expect(model.answer(model.sequence[model.recall_index]),
			"A clean-wave helper must correctly answer each current note.")


func _expire_window(model: RunState) -> void:
	model.advance(maxf(0.0, model.window_timeout_at - model.clock) + 0.000001)


func _advance_split(model: RunState, duration: float, split: float) -> void:
	var remaining := duration
	while remaining > 0.0000000001 and model.state != RunState.State.RUN_OVER:
		var delta := minf(remaining, split)
		model.advance(delta)
		remaining -= delta


func _scripted_run(split: float) -> RunState:
	var model := _model({"lives": 5})
	for number in range(1, 9):
		_reach_recall(model, split)
		var count := model.sequence.size()
		for index in count:
			_reach_recall(model, split)
			_advance_split(model, 0.4, split)
			if number == 2 and index == 1:
				model.answer(_different(model))
			_expect(model.answer(model.sequence[model.recall_index], 0.08,
				12.5, number == 3 and index == 0), "Scripted replay inputs must hit.")
			model.answer(model.sequence[mini(model.recall_index, model.sequence.size() - 1)])
	_advance_split(model, 1000.0, split)
	return model


func _different(model: RunState) -> StringName:
	for id: StringName in model.active_palette:
		if id != model.sequence[model.recall_index]:
			return id
	_expect(false, "A test requiring a wrong colour needs another active instrument.")
	return &""


func _event_count(events: Array[Dictionary], type: StringName) -> int:
	var count := 0
	for event: Dictionary in events:
		if event.get("type") == type:
			count += 1
	return count


func _last_event(events: Array[Dictionary], type: StringName) -> Dictionary:
	for index in range(events.size() - 1, -1, -1):
		if events[index].get("type") == type:
			return events[index]
	_expect(false, "Expected event was not emitted: %s." % type)
	return {}


func _expect_models_equal(left: RunState, right: RunState, message: String) -> void:
	_expect(_equivalent(left.snapshot(), right.snapshot()), "%s: snapshots differ." % message)
	_expect(left.sequence == right.sequence, "%s: seeded patterns differ." % message)
	_expect(left.hits == right.hits and left.wrongs == right.wrongs
		and left.timeouts == right.timeouts and left.assisted == right.assisted
		and left.flawless_six == right.flawless_six,
		"%s: run totals/flags differ." % message)
	_expect_approx(left.clock, right.clock, "%s: final clock" % message)
	_expect_approx(left.window_started_at, right.window_started_at,
		"%s: last window opening" % message)
	_expect_approx(left.window_deadline, right.window_deadline,
		"%s: last visible deadline" % message)
	_expect_approx(left.window_timeout_at, right.window_timeout_at,
		"%s: last dispatch deadline" % message)


func _equivalent(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	if left is float:
		return absf(float(left) - float(right)) < 0.00000001
	if left is Array:
		if left.size() != right.size():
			return false
		for index in left.size():
			if not _equivalent(left[index], right[index]):
				return false
		return true
	if left is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not _equivalent(left[key], right[key]):
				return false
		return true
	return left == right


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_approx(actual: float, expected: float, message: String) -> void:
	_expect(absf(actual - expected) < 0.00000001,
		"%s: expected %.9f, got %.9f." % [message, expected, actual])
