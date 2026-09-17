extends SceneTree

## Focused offline-bank and dummy-audio coverage, with no Settings/progress writes.
## Run with --headless --audio-driver Dummy --script followed by this resource URI.
## Fixtures borrow only AudioManager's public contract, not its autoload instance.

const Bank = preload("res://games/lazer_nfc/audio/sound_bank.gd")
const Director = preload("res://games/lazer_nfc/audio/audio_director.gd")
const Haptics = preload("res://games/lazer_nfc/audio/haptics.gd")
const RATE := 44100
const HUES: Dictionary[StringName, int] = {
	&"red": 48, &"orange": 52, &"yellow": 55, &"green": 60,
	&"blue": 64, &"indigo": 67, &"violet": 72,
}
const CUE_SECONDS: Dictionary[StringName, float] = {
	&"ready": 0.52, &"round": 0.30, &"go": 0.42, &"zap": 0.18, &"pop": 0.14,
	&"wrong": 0.25, &"escape": 0.35, &"round_won": 0.63, &"clean_wave": 0.82,
	&"combo_5": 0.36, &"combo_10": 0.44, &"combo_20": 0.54, &"fail": 0.80,
	&"tick": 0.035, &"not_yet": 0.065, &"unknown": 0.20, &"binding_ping": 0.10,
}

var _failures := 0
var _assertions := 0
var _created_buses: Array[StringName] = []
var _script_errors := ScriptErrorProbe.new()


class ScriptErrorProbe:
	extends Logger

	var _mutex := Mutex.new()
	var _messages := PackedStringArray()

	func _log_error(
		_function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]
	) -> void:
		if error_type != Logger.ERROR_TYPE_SCRIPT:
			return
		_mutex.lock()
		_messages.append("%s:%d: %s" % [
			file, line, rationale if not rationale.is_empty() else code,
		])
		_mutex.unlock()

	## Engine script errors do not necessarily abort a SceneTree regression run.
	func messages() -> PackedStringArray:
		_mutex.lock()
		var result := _messages.duplicate()
		_mutex.unlock()
		return result


class AudioProbe:
	extends Node

	var entries: Array[Dictionary] = []
	var players: Array[AudioStreamPlayer] = []
	var next_voice := 0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		for i in 8:
			var player := AudioStreamPlayer.new()
			player.bus = &"SFX"
			player.process_mode = Node.PROCESS_MODE_ALWAYS
			add_child(player)
			players.append(player)

	func _exit_tree() -> void:
		for player: AudioStreamPlayer in players:
			player.stop()
			player.stream = null
		entries.clear()

	## A real fixed player pool makes cancellation and dummy playback observable.
	func play_sfx(stream: AudioStream, volume_db := 0.0, pitch_scale := 1.0) -> void:
		entries.append({
			"kind": &"sound", "stream": stream, "db": volume_db, "pitch": pitch_scale,
		})
		var player := players[next_voice]
		next_voice = (next_voice + 1) % players.size()
		player.stream = stream
		player.volume_db = volume_db
		player.pitch_scale = pitch_scale
		player.play()

	## Capture ordering without enabling or persisting the player's caption setting.
	func request_caption(text: String) -> void:
		entries.append({"kind": &"caption", "text": text})


class FixtureDirector:
	extends "res://games/lazer_nfc/audio/audio_director.gd"

	var probe: Node

	func _audio_manager() -> Node:
		return probe


class FixtureHaptics:
	extends "res://games/lazer_nfc/audio/haptics.gd"

	var pulses: Array[Vector2] = []

	func _vibrate(duration_ms: int, amplitude: float) -> void:
		pulses.append(Vector2(duration_ms, amplitude))


func _initialize() -> void:
	OS.add_logger(_script_errors)
	_run.call_deferred()


func _run() -> void:
	_ensure_buses()
	_test_samples()
	await process_frame
	_test_director()
	_test_haptics()
	await process_frame
	# The dummy mixer retires stopped playback references on its next audio blocks.
	await create_timer(0.2).timeout
	for bus: StringName in _created_buses:
		AudioServer.remove_bus(AudioServer.get_bus_index(bus))
	await process_frame
	OS.remove_logger(_script_errors)
	var script_errors := _script_errors.messages()
	_expect(script_errors.is_empty(),
		"Unexpected SCRIPT ERROR during audio coverage:\n%s" % "\n".join(script_errors))
	if _failures == 0:
		print("LaZer NFC audio: 154 WAVs and %d focused assertions passed." % _assertions)
	else:
		push_error("LaZer NFC audio: %d of %d assertions failed." % [_failures, _assertions])
	quit(0 if _failures == 0 else 1)


func _ensure_buses() -> void:
	for bus: StringName in [&"Music", &"SFX"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			_created_buses.append(bus)


func _test_samples() -> void:
	_expect(Bank.NOTES.size() == 21, "All seven base/dark/light instruments must ship.")
	_expect(Bank.CUES.size() == CUE_SECONDS.size(), "Every named feedback cue must ship.")
	_expect(Bank.LOOPS.size() == 2, "Music and motion are the only owned loops.")
	_expect(Bank.VOICE.size() == 114, "All portable, baked voice prompts must ship.")
	var fingerprints: Dictionary[int, bool] = {}
	for color_id: StringName in Bank.NOTES:
		var stream := Bank.NOTES[color_id]
		if not _inspect_sample(str(color_id), stream, 0.4, false, 0.561):
			continue
		fingerprints[hash(stream.data)] = true
		var hue := StringName(str(color_id).get_slice("_", 0))
		var semitone := 0
		if str(color_id).ends_with("_dark"):
			semitone = -1
		elif str(color_id).ends_with("_light"):
			semitone = 1
		var hz := _hz(HUES[hue] + semitone)
		var expected := _tone_energy(stream, hz)
		var below := _tone_energy(stream, hz / pow(2.0, 1.0 / 12.0))
		var above := _tone_energy(stream, hz * pow(2.0, 1.0 / 12.0))
		_expect(expected > maxf(below, above) * 1.25,
			"%s must carry its documented pitch, not just a renamed timbre." % color_id)
	_expect(fingerprints.size() == 21, "No colour/shade may duplicate another PCM sample.")
	for hue: StringName in HUES:
		var dark := Bank.NOTES[StringName(str(hue) + "_dark")]
		var light := Bank.NOTES[StringName(str(hue) + "_light")]
		if (
			dark.format != AudioStreamWAV.FORMAT_16_BITS
			or light.format != AudioStreamWAV.FORMAT_16_BITS
		):
			continue
		var dark_brightness := _brightness(dark, _hz(HUES[hue] - 1))
		var light_brightness := _brightness(light, _hz(HUES[hue] + 1))
		_expect(light_brightness > dark_brightness * 1.01,
			"%s shades must differ in spectral brightness as well as pitch." % hue)
	for key: StringName in CUE_SECONDS:
		_inspect_sample(str(key), Bank.CUES[key], CUE_SECONDS[key], false, 0.501)
	_inspect_sample("motion_riser", Bank.LOOPS[&"motion_riser"], 2.0, false, 0.281, true)
	_inspect_sample("toy_lab", Bank.LOOPS[&"toy_lab"], 24.0, true, 0.381, true)
	for key: StringName in Bank.VOICE:
		var stream := Bank.VOICE[key]
		_inspect_sample("voice/" + str(key), stream, stream.get_length(), false, 0.561)
		_expect(stream.get_length() >= 0.08 and stream.get_length() <= 5.0,
			"Baked voice '%s' must be a short, nonempty prompt." % key)
		if str(key).begins_with("round_") and str(key).trim_prefix("round_").is_valid_int():
			_expect(stream.get_length() < 0.75,
				"Numbered round '%s' must finish before the first memorization note." % key)


func _inspect_sample(
	label: String, stream: AudioStreamWAV, seconds: float, stereo: bool,
	peak_limit: float, looping: bool = false
) -> bool:
	_expect(stream.format == AudioStreamWAV.FORMAT_16_BITS,
		"%s must remain uncompressed PCM16." % label)
	_expect(stream.mix_rate == RATE, "%s must be 44.1 kHz." % label)
	_expect(stream.stereo == stereo, "%s must have its authored channel layout." % label)
	var valid_length := absf(stream.get_length() - seconds) <= 1.1 / RATE
	_expect(valid_length,
		"%s duration must match the authored contract." % label)
	_expect(stream.data.size() >= 4, "%s needs nonempty PCM." % label)
	if stream.format != AudioStreamWAV.FORMAT_16_BITS or stream.data.size() < 4:
		return false
	var data := stream.data
	var count := data.size() >> 1
	var peak := 0.0
	var sum_squares := 0.0
	var sum_values := 0.0
	for i in count:
		var value := float(data.decode_s16(i * 2)) / 32768.0
		peak = maxf(peak, absf(value))
		sum_squares += value * value
		sum_values += value
	var rms := sqrt(sum_squares / count)
	_expect(peak >= 0.08 and peak <= peak_limit,
		"%s needs audible signal and at least its promised headroom (peak %.4f)." % [label, peak])
	_expect(rms >= 0.025 and rms <= 0.165,
		"%s must have useful, controlled loudness (RMS %.4f)." % [label, rms])
	_expect(absf(sum_values / count) < 0.004, "%s must not carry significant DC." % label)
	var channels := 2 if stereo else 1
	for channel in channels:
		var first := float(data.decode_s16(channel * 2)) / 32768.0
		var last := float(data.decode_s16((count - channels + channel) * 2)) / 32768.0
		if looping:
			var next := float(data.decode_s16((channels + channel) * 2)) / 32768.0
			var prior := float(data.decode_s16((count - 2 * channels + channel) * 2)) / 32768.0
			var local_step := maxf(absf(first - next), absf(last - prior))
			_expect(absf(last - first) <= maxf(0.02, 2.0 * local_step),
				"%s must close without a loop-boundary click." % label)
		else:
			_expect(absf(first) < 0.0001 and absf(last) < 0.0001,
				"%s needs click-free sample edges." % label)
	return valid_length and stream.mix_rate == RATE and stream.stereo == stereo


func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, float(midi - 69) / 12.0)


func _tone_energy(stream: AudioStreamWAV, hz: float) -> float:
	var data := stream.data
	var real := 0.0
	var imaginary := 0.0
	var start := roundi(RATE * 0.05)
	var end := roundi(RATE * 0.35)
	for i in range(start, end, 4):
		var phase := TAU * hz * float(i) / RATE
		var window := sin(PI * float(i - start) / float(end - start))
		var value := float(data.decode_s16(i * 2)) / 32768.0 * window * window
		real += value * cos(phase)
		imaginary += value * sin(phase)
	return real * real + imaginary * imaginary


func _brightness(stream: AudioStreamWAV, hz: float) -> float:
	var data := stream.data
	var energy := 0.0
	var slope_energy := 0.0
	var previous := 0.0
	for i in range(1, data.size() >> 1):
		var value := float(data.decode_s16(i * 2)) / 32768.0
		energy += value * value
		slope_energy += (value - previous) * (value - previous)
		previous = value
	return slope_energy / maxf(energy, 0.000001) * pow(float(RATE) / (TAU * hz), 2.0)


func _test_director() -> void:
	var probe := AudioProbe.new()
	root.add_child(probe)
	var director := FixtureDirector.new()
	director.probe = probe
	root.add_child(director)
	var music := director.get_node("ToyLabMusic") as AudioStreamPlayer
	var riser := director.get_node("MotionRiser") as AudioStreamPlayer
	_expect(music.bus == &"Music" and riser.bus == &"SFX",
		"Owned loops must use the existing volume/mute buses.")
	_expect(director.get_child_count() == 2 and probe.players.size() == 8,
		"Only two persistent loop players and the shared-style SFX pool are needed.")
	_expect((music.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"READY music must actually loop.")
	_expect((riser.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"Motion must reuse a loop rather than allocate synthesized hits.")
	var started: Array[StringName] = []
	director.note_started.connect(func(color_id: StringName) -> void: started.append(color_id))

	director.announce("Ready. Tap a tag to start.", &"ready")
	_caption_first(probe, "READY")
	_expect(music.playing and not music.stream_paused, "READY starts owned music.")
	_expect(_sound_count(probe, director._voice[&"ready"]) == 1,
		"Voice is on by default and plays a baked asset without runtime TTS.")
	director.configure(false)
	_expect(not _any_playing(probe, director._voice_samples),
		"Turning voice off cancels the current utterance.")
	probe.entries.clear()
	director.play_event({"type": &"round_started", "round": 3, "count": 3})
	director.advance(0.1, _snapshot(&"ROUND_START"))
	_expect(_sounds_in(probe, director._voice_samples) == 0,
		"Voice-off still permits cues and captions but no spoken clips.")

	director.configure(true)
	probe.entries.clear()
	director.play_event({
		"type": &"round_started", "round": 3, "count": 3, "new_colors": [&"orange"],
	})
	_caption_first(probe, "round start")
	director.advance(0.03, _snapshot(&"ROUND_START"))
	_expect(_sound_count(probe, director._voice[&"round_3"]) == 1,
		"The round number uses its short pre-baked take.")
	_expect(music.stream_paused, "No competing melody may enter memorization.")
	probe.entries.clear()
	director.play_event({"type": &"note", "color_id": &"red_dark", "index": 0, "count": 3})
	_caption_first(probe, "SHOWING")
	_expect(started == [&"red_dark"], "Model notes emit presentation on the same event frame.")
	_expect(not _any_playing(probe, director._voice_samples),
		"The first note cancels any announcement tail and queued palette names.")
	var shown := _sounds_in(probe, director._note_samples)
	director.announce("Red.", &"red")
	director.advance(8.0, _snapshot(&"SHOWING"))
	_expect(_sounds_in(probe, director._note_samples) == shown,
		"advance() must never invent or schedule SHOWING notes.")
	_expect(_sounds_in(probe, director._voice_samples) == 0,
		"Note memorization must remain word-free even if announce() is called.")
	director.play_event({"type": &"note_end"})
	_expect(not _any_playing(probe, director._note_samples), "note_end cuts only note tails.")

	probe.entries.clear()
	director.play_event({"type": &"go"})
	_caption_first(probe, "go")
	director.advance(0.03, _snapshot(&"SHOW_END"))
	_expect(_sound_count(probe, director._cues[&"go"]) == 1
		and _sound_count(probe, director._voice[&"recall"]) == 1,
		"The recall transition has both its signature and baked spoken prompt.")
	director.configure(false)
	director.play_event({"type": &"awaiting", "index": 1, "count": 3})
	probe.entries.clear()
	director.advance(0.499, _snapshot(&"AWAITING", 1.0))
	_expect(_sound_count(probe, director._cues[&"tick"]) == 0, "Early ticks wait 0.5 seconds.")
	director.advance(0.002, _snapshot(&"AWAITING", 1.0))
	_expect(_sound_count(probe, director._cues[&"tick"]) == 1, "Early ticks then fire once.")
	director.play_event({"type": &"awaiting", "index": 1, "count": 3})
	probe.entries.clear()
	director.advance(0.119, _snapshot(&"AWAITING", 0.0))
	_expect(_sound_count(probe, director._cues[&"tick"]) == 0, "Late ticks wait 0.12 seconds.")
	director.advance(0.002, _snapshot(&"AWAITING", 0.0))
	_expect(_sound_count(probe, director._cues[&"tick"]) == 1, "Late ticks accelerate to 0.12 s.")
	director.advance(10.0, _snapshot(&"AWAITING", 0.0))
	_expect(_sound_count(probe, director._cues[&"tick"]) == 2,
		"A hitch skips missed ticks instead of playing a catch-up burst.")
	_expect(_caption_count(probe) == 0, "Ticks never spam captions.")
	director.advance(0.2, _snapshot(&"AWAITING"), 0.0)
	_expect(not riser.playing, "Still/no-sensor players hear no motion riser.")
	director.advance(0.2, _snapshot(&"AWAITING"), 9.0)
	_expect(riser.playing and riser.volume_db <= -27.0, "Motion adds only a subtle SFX bonus.")

	probe.entries.clear()
	director.play_event({"type": &"hit", "color_id": &"blue", "combo": 10, "points": 120})
	_caption_first(probe, "hit/combo")
	_expect(_sound_count(probe, director._cues[&"zap"]) == 1
		and _sound_count(probe, director._cues[&"pop"]) == 1
		and _sound_count(probe, director._cues[&"combo_10"]) == 1,
		"A hit combines original laser/pop feedback and the exact combo milestone.")
	for entry: Dictionary in probe.entries:
		if entry.get("stream") == director._notes[&"blue"]:
			_expect(is_equal_approx(float(entry["pitch"]), 2.0),
				"Correct answers reuse the hue sample one octave up.")
	_expect(not riser.playing, "Resolving a hit stops the waiting riser immediately.")
	probe.entries.clear()
	director.play_event({
		"type": &"wrong", "color_id": &"red_light", "expected_color": &"red_dark", "lives": 2,
	})
	_caption_first(probe, "wrong")
	director.advance(0.28, _snapshot(&"AWAITING"))
	_expect(_sound_count(probe, director._notes[&"red_dark"]) == 1,
		"An explicitly supplied near-miss shade is taught quietly after the buzz.")
	probe.entries.clear()
	director.play_event({"type": &"timeout", "lives": 1})
	_caption_first(probe, "timeout")
	_expect(_sound_count(probe, director._cues[&"escape"]) == 1, "Timeout has its escape signature.")
	for kind: StringName in [&"not_yet", &"unknown"]:
		probe.entries.clear()
		director.play_event({"type": kind})
		_caption_first(probe, str(kind))
		_expect(_sound_count(probe, director._cues[kind]) == 1,
			"%s remains identifiable without speech." % kind)

	probe.entries.clear()
	director.play_event({"type": &"round_won", "round": 3, "perfect": true})
	_caption_first(probe, "clean wave")
	director.advance(0.2, _snapshot(&"ROUND_WON"))
	_expect(_sound_count(probe, director._cues[&"clean_wave"]) == 1
		and _sounds_in(probe, director._note_samples) == 0,
		"Round completion works without reading or requiring a hidden sequence.")
	director.play_event({
		"type": &"round_won", "perfect": false, "sequence": [&"red", &"green", &"blue"],
	})
	director.advance(0.13, _snapshot(&"ROUND_WON"))
	_expect(_sound_count(probe, director._notes[&"red"]) == 1,
		"An explicitly supplied, already-public recap may schedule feedback notes.")
	probe.entries.clear()
	director.play_event({"type": &"run_over", "score": 320})
	_caption_first(probe, "run over")
	_expect(_sound_count(probe, director._cues[&"fail"]) == 1, "Run over has its descending motif.")
	director.stop()
	_expect(not music.playing and not riser.playing
		and not _any_playing(probe, director._all_samples),
		"stop() cancels loops, pooled tails, recap and vocals for navigation/results.")
	probe.entries.clear()
	director.advance(20.0, _snapshot(&"AWAITING"), 9.0)
	director.play_event({"type": &"hit", "color_id": &"red"})
	_expect(probe.entries.is_empty(), "Stopped directors ignore stale active-run callbacks.")
	director.advance(0.01, _snapshot(&"READY"))
	_expect(music.playing and not music.stream_paused, "The next READY restarts stopped music.")

	director.configure(true)
	probe.entries.clear()
	director.play_note(&"green")
	director.announce("Green. Circle.")
	_expect(_sounds_in(probe, director._voice_samples) == 0,
		"Practice naming waits until the instrument has sounded.")
	director.advance(0.43, _snapshot(&"READY"))
	_expect(_sound_count(probe, director._voice[&"green"]) == 1,
		"Practice naming uses baked colour prompts after the note.")
	probe.entries.clear()
	director.announce(
		"Double tap red for shades, yellow for the touch pad, "
		+ "or violet to bind tags again.", &"gestures"
	)
	_caption_first(probe, "READY gestures")
	_expect(_sound_count(probe, director._voice[&"gestures"]) == 1,
		"READY shortcut guidance must use its baked prompt, not runtime TTS.")
	director.play_note(&"blue")
	_expect(not _any_playing(probe, director._voice_samples),
		"Learning an instrument interrupts gesture guidance rather than masking the note.")
	director.advance(0.41, _snapshot(&"READY"))
	var parent_prompts: Dictionary[StringName, String] = {
		&"binding": "Tap the upper back of your phone against each tag.",
		&"need_tags": "Bind at least three colours, or choose keys and touch.",
		&"nfc_off": "NFC unavailable. Keys and touch are ready.",
		&"unknown": "Unknown tag. Use Settings to rebind tags.",
		&"settings_changed": "Shades enabled.",
		&"shades_on": "Shades on.",
		&"shades_off": "Shades off.",
		&"touch_on": "Touch pad shown.",
		&"touch_off": "Touch pad hidden.",
	}
	for key: StringName in parent_prompts:
		probe.entries.clear()
		director.announce(parent_prompts[key], key)
		_caption_first(probe, str(key))
		_expect(probe.entries[0]["text"] == parent_prompts[key],
			"The full parent caption must survive a shorter baked announcement.")
		_expect(_sound_count(probe, director._voice[key]) == 1,
			"The parent's '%s' key must speak its baked prompt immediately." % key)
	for color_id: StringName in Bank.NOTES:
		var key := StringName("bind_" + str(color_id))
		probe.entries.clear()
		director.announce("Scan the tag for %s." % director._color_label(color_id), key)
		_caption_first(probe, str(key))
		_expect(_sound_count(probe, director._voice[key]) == 1,
			"'%s' must speak its exact colour/shade without a queued-word clock." % key)
	_test_announcement_keys(director, probe)
	director.configure(true)
	_expect(director._number_words(21005) == [&"number_20", &"number_1", &"number_1000", &"number_5"],
		"Composed counters cover rounds/scores beyond the short numbered takes.")
	_expect(director._number_words(1000000).size() == 7, "Large counters remain speakable as digits.")

	var sibling := FixtureDirector.new()
	sibling.probe = probe
	root.add_child(sibling)
	sibling.play_note(&"violet")
	var sibling_note := sibling._notes[&"violet"]
	_expect(sibling_note != director._notes[&"violet"], "Resource ownership is per director.")
	director.suspend()
	_expect(_playing(probe, sibling_note), "Suspending one scene must not stop another's sound.")
	_expect(director._voice_queue.is_empty() and not _any_playing(probe, director._all_samples),
		"Suspension discards queued and currently borrowed vocal voices.")
	probe.entries.clear()
	director.advance(5.0, _snapshot(&"READY"))
	director.announce("Ready.", &"ready")
	_expect(probe.entries.is_empty(), "Suspended directors stay silent under stale callbacks.")
	director.resume()
	director.advance(0.01, _snapshot(&"READY"))
	director.announce("Ready.", &"ready")
	paused = true
	_expect(director._suspended and not _any_playing(probe, director._all_samples),
		"Tree pause cancels SFX even though the shared-style pool processes always.")
	paused = false
	director.resume()
	_expect(director._voice_queue.is_empty(), "Unpausing never resumes fragments of old words.")
	director.suspend()
	director.stop()
	director.advance(0.01, _snapshot(&"READY"))
	_expect(music.playing and not music.stream_paused,
		"Ending a suspended run must not leave the next READY permanently suspended.")

	probe.play_sfx(Bank.CUES[&"unknown"], -30.0)
	director.play_note(&"red")
	var owned_note := director._notes[&"red"]
	director.free()
	_expect(not _playing(probe, owned_note), "Scene deletion cancels its borrowed one-shots.")
	_expect(_playing(probe, Bank.CUES[&"unknown"]), "Scene deletion preserves unrelated UI sounds.")
	_expect(probe.get_child_count() == 8, "Hits and announcements never allocate extra player nodes.")
	sibling.free()
	probe.free()


func _test_announcement_keys(director: FixtureDirector, probe: AudioProbe) -> void:
	var duplicate_tag := "That tag already has a colour in this roll call."
	var cases: Array[Dictionary] = [
		{"text": duplicate_tag, "omit_key": true},
		{"text": duplicate_tag, "key": &""},
		{"text": duplicate_tag, "key": &"no_such_baked_prompt"},
		{"text": "Red. Triangle.", "omit_key": true, "sample": &"red"},
		{"text": "Red. Triangle.", "key": &"", "sample": &"red"},
		{"text": "Red. Triangle.", "key": &"no_such_baked_prompt"},
		{"text": "Unknown tag. Rebind in Settings.", "key": &"unknown", "sample": &"unknown"},
		{"text": "Shades enabled.", "key": &"shades_on", "sample": &"shades_on"},
		{"text": "", "omit_key": true},
		{"text": "", "key": &""},
		{"text": " \t\n", "key": &""},
	]
	for item: Dictionary in cases:
		var text: String = item["text"]
		var key: StringName = item.get("key", &"")
		var sample_key: StringName = item.get("sample", &"")
		var expected_words: Array[StringName] = []
		if not sample_key.is_empty():
			expected_words.append(sample_key)
		# Preserve the actual returned array metadata rather than coercing it in the test.
		var words: Variant = director.call("_announcement_words", text, key)
		_expect(words is Array, "Announcement resolution must always return an array.")
		if not words is Array:
			continue
		_expect(words.is_same_typed(expected_words),
			"Every announcement branch, including an empty result, needs StringName elements.")
		_expect(words == expected_words,
			"An explicit unknown key must not borrow a different phrase from the caption.")
		for enabled: bool in [true, false]:
			for dynamic_call: bool in [false, true]:
				director.configure(false)
				director.configure(enabled)
				probe.entries.clear()
				if bool(item.get("omit_key", false)):
					if dynamic_call:
						director.call("announce", text)
					else:
						director.announce(text)
				elif dynamic_call:
					director.call("announce", text, key)
				else:
					director.announce(text, key)
				if text.strip_edges().is_empty():
					_expect(probe.entries.is_empty(),
						"Empty announcement text must not enqueue audio or an empty caption.")
				else:
					_caption_first(probe, "default/empty/unknown-key announcement")
					_expect(probe.entries[0]["text"] == text,
						"Duplicate-tag/error captions stay intact with voice enabled or disabled.")
				var audible := enabled and not sample_key.is_empty()
				_expect(_sounds_in(probe, director._voice_samples) == (1 if audible else 0),
					"Only an enabled, resolved baked phrase may enter the SFX pool.")
				if audible:
					_expect(_sound_count(probe, director._voice[sample_key]) == 1,
						"An omitted or empty voice key still resolves known colour text correctly.")
				else:
					_expect(director._voice_queue.is_empty()
						and is_zero_approx(director._voice_remaining),
						"Caption-only and disabled-voice paths leave no delayed speech behind.")


func _test_haptics() -> void:
	var haptics := FixtureHaptics.new()
	root.add_child(haptics)
	haptics.configure(0.5)
	haptics.play_event({"type": &"hit"})
	_expect(haptics.pulses == [Vector2(60, 0.5)], "Correct feedback is one 60 ms scaled pulse.")
	haptics.advance(0.02)
	_expect(haptics.pulses.size() == 1, "A frame inside a pulse does not restart the motor.")
	haptics.configure(0.25)
	_expect(haptics.pulses.back().is_equal_approx(Vector2(40, 0.25)),
		"Live strength changes use only the unelapsed part of the current pulse.")
	haptics.configure(0.0)
	_expect(haptics.pulses.back() == Vector2.ZERO, "Zero strength stops the current vibration.")
	var count := haptics.pulses.size()
	haptics.play_event({"type": &"wrong"})
	haptics.advance(10.0)
	_expect(haptics.pulses.size() == count, "Zero strength disables the whole pulse chain.")
	haptics.configure(1.0)
	haptics.pulses.clear()
	haptics.play_event({"type": &"go"})
	haptics.advance(0.04)
	haptics.advance(0.04)
	haptics.advance(0.04)
	_expect(_positive_pulses(haptics).size() == 2 and haptics._pattern.is_empty(),
		"GO is a double pulse separated by explicit parent-clock silence.")
	haptics.pulses.clear()
	haptics.play_event({"type": &"timeout"})
	haptics.advance(0.15)
	haptics.advance(0.15)
	haptics.advance(0.04)
	_expect(_positive_pulses(haptics).size() == 3 and haptics._pattern.is_empty(),
		"Timeout is three spaced short pulses, not the wrong-answer rough tail.")
	haptics.pulses.clear()
	haptics.play_event({"type": &"wrong"})
	for i in 84:
		haptics.advance(0.005)
	_expect(_positive_pulses(haptics).size() == 7 and haptics._pattern.is_empty(),
		"Wrong has three taps followed by a textured 200 ms rough tail.")
	haptics.pulses.clear()
	haptics.play_event({"type": &"round_won"})
	_expect(haptics.pulses[0].is_equal_approx(Vector2(400, 0.35)), "Round won is long and soft.")
	haptics.advance(0.4)
	haptics.pulses.clear()
	haptics.play_event({"type": &"run_over"})
	for i in 4:
		haptics.advance(0.125)
	haptics.advance(0.1)
	_expect(_positive_pulses(haptics).size() == 5 and haptics._pattern.is_empty(),
		"Run over has a distinct 600 ms rough envelope.")
	haptics.pulses.clear()
	haptics.play_event({"type": &"wrong"})
	haptics.advance(10.0)
	_expect(_positive_pulses(haptics).size() == 1, "A hitch cannot replay expired vibration pulses.")
	haptics.play_event({"type": &"wrong"})
	paused = true
	_expect(haptics._pattern.is_empty() and haptics.pulses.back() == Vector2.ZERO,
		"Pause cancels the current motor pulse and all queued pulses.")
	paused = false
	count = haptics.pulses.size()
	haptics.advance(10.0)
	_expect(haptics.pulses.size() == count, "Unpausing cannot resurrect a cancelled pattern.")
	haptics.stop()
	haptics.free()
	var native := Haptics.new()
	root.add_child(native)
	if DisplayServer.get_name() == "headless":
		_expect(not native._handheld_supported(), "Headless playback must not call unsupported vibration.")
		native.play_event({"type": &"go"})
		native.advance(0.2)
	native.stop()
	native.free()


func _snapshot(state: StringName, ratio: float = 1.0) -> Dictionary:
	return {
		"state": state, "window_ratio": ratio, "round": 3, "length": 3,
		"lives": 2, "combo": 0, "score": 320,
	}


func _caption_first(probe: AudioProbe, event: String) -> void:
	_expect(not probe.entries.is_empty() and probe.entries[0]["kind"] == &"caption",
		"%s must request its meaningful caption before audio." % event)


func _sound_count(probe: AudioProbe, stream: AudioStream) -> int:
	var count := 0
	for entry: Dictionary in probe.entries:
		if entry.get("stream") == stream:
			count += 1
	return count


func _sounds_in(probe: AudioProbe, samples: Array[AudioStreamWAV]) -> int:
	var count := 0
	for entry: Dictionary in probe.entries:
		if entry["kind"] == &"sound" and samples.has(entry["stream"]):
			count += 1
	return count


func _caption_count(probe: AudioProbe) -> int:
	var count := 0
	for entry: Dictionary in probe.entries:
		if entry["kind"] == &"caption":
			count += 1
	return count


func _playing(probe: AudioProbe, stream: AudioStream) -> bool:
	for player: AudioStreamPlayer in probe.players:
		if player.stream == stream and player.playing:
			return true
	return false


func _any_playing(probe: AudioProbe, samples: Array[AudioStreamWAV]) -> bool:
	for player: AudioStreamPlayer in probe.players:
		if samples.has(player.stream) and player.playing:
			return true
	return false


func _positive_pulses(haptics: FixtureHaptics) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for pulse: Vector2 in haptics.pulses:
		if pulse.x > 0.0:
			result.append(pulse)
	return result


func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if not condition:
		_failures += 1
		push_error(message)
