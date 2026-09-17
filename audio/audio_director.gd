extends Node

## A scene-owned director: model events start notes; only feedback uses this clock.
## Shared pooled one-shots respect SFX settings, and owned loops use Music/SFX.
## Speech is baked System.Speech PCM, never an Android runtime TTS requirement.

signal note_started(color_id: StringName)

const Bank = preload("res://games/lazer_nfc/audio/sound_bank.gd")
const TICK_SLOW := 0.5
const TICK_FAST := 0.12
const MUSIC_DB := -13.0
const MUSIC_DUCK_DB := -23.0
const VOICE_DB := -4.0
const NOTE_DB := -3.0
const SILENT_DB := -60.0
const VOICE_GAP := 0.025
const PHASES: Array[StringName] = [
	&"BINDING", &"READY", &"ROUND_START", &"SHOWING", &"SHOW_END", &"AWAITING",
	&"RESOLVING", &"RECALL_GAP", &"ROUND_WON", &"RUN_OVER",
]

var _notes: Dictionary[StringName, AudioStreamWAV] = {}
var _cues: Dictionary[StringName, AudioStreamWAV] = {}
var _voice: Dictionary[StringName, AudioStreamWAV] = {}
var _all_samples: Array[AudioStreamWAV] = []
var _note_samples: Array[AudioStreamWAV] = []
var _cue_samples: Array[AudioStreamWAV] = []
var _voice_samples: Array[AudioStreamWAV] = []
var _music: AudioStreamPlayer
var _riser: AudioStreamPlayer
var _voice_enabled := true
var _stopped := false
var _suspended := false
var _warned_manager := false
var _phase: StringName = &""
var _round_number := 1
var _sequence_length := 0
var _score := 0
var _note_remaining := 0.0
var _voice_remaining := 0.0
var _voice_delay := 0.0
var _voice_queue: Array[StringName] = []
var _tick_remaining := TICK_SLOW
var _tick_duck_remaining := 0.0
var _motion_amount := 0.0
var _correction: StringName = &""
var _correction_delay := 0.0
var _recap: Array[StringName] = []
var _recap_remaining := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_notes = _own_samples(Bank.NOTES, _note_samples)
	_cues = _own_samples(Bank.CUES, _cue_samples)
	_voice = _own_samples(Bank.VOICE, _voice_samples)
	_music = _make_loop(&"toy_lab", "ToyLabMusic", &"Music")
	_music.volume_db = MUSIC_DB
	_riser = _make_loop(&"motion_riser", "MotionRiser", &"SFX")
	_riser.volume_db = SILENT_DB


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		suspend()


func _exit_tree() -> void:
	stop()


## Live voice changes cancel queued words rather than leaving old utterances behind.
func configure(voice_enabled: bool) -> void:
	_voice_enabled = voice_enabled
	if not voice_enabled:
		_cancel_voice()


## Consumes public model events without consulting its sequence or hidden answers.
func play_event(event: Dictionary) -> void:
	var kind := StringName(str(event.get("type", "")))
	if not _available() or (_stopped and kind != &"round_started"):
		return
	match kind:
		&"round_started":
			_round_number = maxi(int(event.get("round", 1)), 1)
			_sequence_length = int(event.get("count", event.get("length", 0)))
			var new_colors := _event_colors(event, "new_colors")
			var caption := "Round %d" % _round_number
			if not new_colors.is_empty():
				var labels := PackedStringArray()
				for color_id: StringName in new_colors:
					labels.append(_color_label(color_id))
				caption += " - %s joins" % ", ".join(labels)
			_caption(caption)
			_clear_feedback()
			_stop_pooled(_all_samples)
			_stopped = false
			_phase = &"ROUND_START"
			_silence_loops()
			_cue(&"round", -11.0)
			var words := _round_words(_round_number)
			words.append_array(new_colors)
			_queue_words(words, 0.02, maxf(float(event.get("start_delay", 0.8)), 0.0))
		&"note":
			_phase = &"SHOWING"
			_clear_feedback()
			_silence_loops()
			_stop_pooled(_all_samples)
			var color_id := StringName(str(event.get("color_id", "")))
			var count := maxi(int(event.get("count", _sequence_length)), 1)
			var index := maxi(int(event.get("index", 0)) + 1, 1)
			_caption("Showing %d of %d - %s" % [index, count, _color_label(color_id)])
			_start_note(color_id, 1.0, NOTE_DB, true)
		&"note_end":
			_note_remaining = 0.0
			_stop_pooled(_note_samples)
		&"go":
			_phase = &"SHOW_END"
			_clear_feedback()
			_stop_pooled(_note_samples)
			_silence_loops()
			_caption("Recall now")
			_cue(&"go", -9.0)
			_queue_words([&"recall"], 0.025)
		&"awaiting":
			_phase = &"AWAITING"
			_tick_remaining = TICK_SLOW
			_motion_amount = 0.0
			_caption("Enemy %d of %d" % [
				maxi(int(event.get("index", 0)) + 1, 1),
				maxi(int(event.get("count", _sequence_length)), 1),
			])
		&"hit":
			_hit(event)
		&"wrong":
			_wrong(event)
		&"timeout":
			_clear_feedback()
			_phase = &"RECALL_GAP"
			_silence_loops()
			_caption("Escaped - %s" % _lives_phrase(int(event.get("lives", 0))))
			_cue(&"escape", -5.0)
		&"round_won":
			_round_won(event)
		&"run_over":
			_clear_feedback()
			_stop_pooled(_all_samples)
			_phase = &"RUN_OVER"
			_silence_loops()
			_caption("Run over - score %d" % int(event.get("score", _score)))
			_cue(&"fail", -5.0)
			var words: Array[StringName] = [&"run_over", &"score"]
			words.append_array(_number_words(maxi(int(event.get("score", _score)), 0)))
			if bool(event.get("assisted", false)):
				words.append(&"assisted")
			_queue_words(words, 0.45)
		&"not_yet":
			_caption("Not yet - listen to the colours")
			_cue(&"not_yet", -18.0)
		&"unknown":
			_caption("Unknown tag")
			_cue(&"unknown", -12.0)
		_:
			push_warning("LaZer NFC: unknown audio event '%s'." % kind)


## Practice and confirmation use the very same preloaded instruments as SHOWING.
func play_note(color_id: StringName, pitch: float = 1.0) -> void:
	if not _available() or _stopped:
		return
	_cancel_voice()
	_caption("%s tone" % _color_label(color_id))
	if _music != null:
		_music.stream_paused = true
	_start_note(color_id, pitch, NOTE_DB, true)


## Known keys/text use baked phrases; arbitrary text remains an honest caption.
## READY explicitly opens the next run even after stop(), including its owned music.
func announce(text: String, voice_key: StringName = &"") -> void:
	if not _available() or (_stopped and voice_key != &"ready"):
		return
	if text.strip_edges().is_empty():
		push_warning("LaZer NFC: an announcement needs caption text.")
		return
	_caption(text)
	if voice_key == &"ready" and (_stopped or _phase != &"READY"):
		_begin_ready()
	elif voice_key == &"binding" or str(voice_key).begins_with("bind_"):
		_phase = &"BINDING"
		_silence_loops()
	_cancel_voice()
	if not _voice_enabled or _phase == &"SHOWING":
		return
	var delay := 0.0
	if _phase == &"READY" and _note_remaining > 0.0:
		delay = _note_remaining + 0.025
	var words: Array[StringName] = _announcement_words(text, voice_key)
	_queue_words(words, delay)


## Parent-driven time freezes with the model; a hitch never backfills a tick burst.
## snapshot needs only state and public counters, never the remembered sequence.
func advance(delta: float, snapshot: Dictionary, motion_peak: float = 0.0) -> void:
	if not is_finite(delta) or delta < 0.0 or not is_finite(motion_peak):
		push_warning("LaZer NFC: audio time and motion must be finite; time cannot be negative.")
		return
	if not _available():
		return
	var phase := StringName(str(snapshot.get("state", "")).to_upper())
	if not PHASES.has(phase):
		push_warning("LaZer NFC: audio snapshot needs a named model state.")
		return
	if phase == &"READY" and (_stopped or _phase != &"READY"):
		_caption("Ready - learn the sounds, then start the experiment")
		_begin_ready()
	if _stopped:
		return
	if phase != _phase:
		if phase == &"SHOWING":
			_cancel_voice()
			_recap.clear()
			_correction = &""
		if phase == &"AWAITING":
			_tick_remaining = TICK_SLOW
		_phase = phase
	_round_number = int(snapshot.get("round", _round_number))
	_sequence_length = int(snapshot.get("length", _sequence_length))
	_score = int(snapshot.get("score", _score))
	_note_remaining = maxf(_note_remaining - delta, 0.0)
	_tick_duck_remaining = maxf(_tick_duck_remaining - delta, 0.0)
	_advance_voice(delta)
	_advance_feedback(delta)
	_update_music(delta)
	if _phase == &"AWAITING":
		var ratio := clampf(float(snapshot.get("window_ratio", 1.0)), 0.0, 1.0)
		var interval := lerpf(TICK_FAST, TICK_SLOW, ratio)
		_tick_remaining = minf(_tick_remaining, interval) - delta
		if _tick_remaining <= 0.0:
			if _tick_duck_remaining <= 0.0:
				_cue(&"tick", -23.0)
			_tick_remaining = interval
		_update_riser(delta, maxf(motion_peak, 0.0))
	else:
		_stop_riser()


## Results/navigation release every owned loop, pooled tail and pending utterance.
## Only a new READY phase or round_started event may reopen this director.
func stop() -> void:
	_clear_feedback()
	_stop_pooled(_all_samples)
	if _music != null:
		_music.stop()
		_music.stream_paused = false
	_stop_riser()
	_stopped = true
	_suspended = false
	_phase = &""


## Shared SFX voices process while paused, so explicitly cancel only our samples.
func suspend() -> void:
	_suspended = true
	_clear_feedback()
	_stop_pooled(_all_samples)
	if _music != null:
		_music.stream_paused = true
	_stop_riser()


## Resume loops when appropriate, never old vocal fragments or stale haptic clocks.
func resume() -> void:
	_suspended = false
	_tick_remaining = TICK_SLOW
	if not _stopped and _available():
		_update_music(0.0)


func _own_samples(
	source: Dictionary[StringName, AudioStreamWAV],
	group: Array[AudioStreamWAV]
) -> Dictionary[StringName, AudioStreamWAV]:
	var result: Dictionary[StringName, AudioStreamWAV] = {}
	for key: StringName in source:
		var sample := source[key].duplicate() as AudioStreamWAV
		result[key] = sample
		group.append(sample)
		_all_samples.append(sample)
	return result


func _make_loop(key: StringName, node_name: String, bus: StringName) -> AudioStreamPlayer:
	var stream := Bank.LOOPS[key].duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = roundi(stream.get_length() * float(stream.mix_rate))
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = bus
	player.stream = stream
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	return player


func _audio_manager() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("AudioManager")


func _available() -> bool:
	if not is_node_ready() or not is_inside_tree():
		push_warning("LaZer NFC: add the audio director to the scene before playing cues.")
		return false
	return not _suspended and not get_tree().paused


func _caption(text: String) -> void:
	var manager := _audio_manager()
	if manager != null and manager.has_method("request_caption"):
		manager.call("request_caption", text)
	elif not _warned_manager:
		_warned_manager = true
		push_warning("LaZer NFC audio needs AudioManager for shared playback and captions.")


func _sample(stream: AudioStreamWAV, volume_db: float, pitch: float = 1.0) -> void:
	var manager := _audio_manager()
	if manager != null and manager.has_method("play_sfx"):
		manager.call("play_sfx", stream, volume_db, pitch)
	elif not _warned_manager:
		_warned_manager = true
		push_warning("LaZer NFC audio needs AudioManager.play_sfx().")


func _stop_pooled(samples: Array[AudioStreamWAV]) -> void:
	var manager := _audio_manager()
	if manager == null or samples.is_empty():
		return
	# play_sfx has no voice handle. Per-director resource identities let cleanup
	# cancel borrowed pool voices without stopping UI sounds or another scene.
	for child: Node in manager.get_children():
		if child is AudioStreamPlayer:
			var player := child as AudioStreamPlayer
			if samples.has(player.stream):
				player.stop()
				player.stream = null


func _cue(key: StringName, volume_db: float) -> void:
	_sample(_cues[key], volume_db)


func _canonical_color(color_id: StringName) -> StringName:
	if Bank.NOTES.has(color_id):
		return color_id
	var text := str(color_id)
	if text.ends_with("_base"):
		text = text.trim_suffix("_base")
	elif text.begins_with("dark_"):
		text = text.trim_prefix("dark_") + "_dark"
	elif text.begins_with("light_"):
		text = text.trim_prefix("light_") + "_light"
	var key := StringName(text)
	return key if Bank.NOTES.has(key) else &""


func _color_label(color_id: StringName) -> String:
	var key := str(_canonical_color(color_id))
	if key.is_empty():
		return "Unknown colour"
	var parts := key.split("_")
	if parts.size() == 1:
		return key.capitalize()
	return "%s %s" % [parts[1].capitalize(), parts[0]]


func _start_note(color_id: StringName, pitch: float, volume_db: float, emit_note: bool) -> void:
	var key := _canonical_color(color_id)
	if key.is_empty() or not is_finite(pitch) or pitch <= 0.0:
		push_warning("LaZer NFC: a note needs a known colour and positive finite pitch.")
		return
	_sample(_notes[key], volume_db, pitch)
	_note_remaining = _notes[key].get_length() / pitch
	if emit_note:
		note_started.emit(color_id)


func _begin_ready() -> void:
	_clear_feedback()
	_stop_pooled(_all_samples)
	_stopped = false
	_phase = &"READY"
	_stop_riser()
	_music.stop()
	_music.stream_paused = false
	_music.volume_db = MUSIC_DB
	_music.play()
	_cue(&"ready", -12.0)


func _silence_loops() -> void:
	if _music != null:
		_music.stream_paused = true
	_stop_riser()


func _update_music(delta: float) -> void:
	if _phase != &"READY" or _note_remaining > 0.0:
		_music.stream_paused = true
		return
	if not _music.playing:
		_music.play()
	_music.stream_paused = false
	var speaking := _voice_remaining > 0.0 or not _voice_queue.is_empty()
	var target := MUSIC_DUCK_DB if speaking else MUSIC_DB
	_music.volume_db = move_toward(_music.volume_db, target, delta * 36.0)


func _update_riser(delta: float, motion_peak: float) -> void:
	var target := clampf((motion_peak - 0.35) / 8.0, 0.0, 1.0)
	_motion_amount = move_toward(_motion_amount, target, delta * 3.0)
	if _motion_amount <= 0.001:
		_stop_riser()
		return
	_riser.volume_db = -27.0 + linear_to_db(_motion_amount)
	_riser.pitch_scale = lerpf(0.94, 1.12, _motion_amount)
	if not _riser.playing:
		_riser.play()


func _stop_riser() -> void:
	if _riser != null:
		_riser.stop()
		_riser.stream_paused = false
		_riser.volume_db = SILENT_DB
	_motion_amount = 0.0


func _hit(event: Dictionary) -> void:
	_clear_feedback()
	_phase = &"RECALL_GAP"
	_silence_loops()
	var color_id := StringName(str(event.get("color_id", "")))
	var combo := int(event.get("combo", 0))
	var caption := "Hit"
	if not color_id.is_empty():
		caption += " - %s" % _color_label(color_id)
	if combo in [5, 10, 20]:
		caption += ". Combo x%d!" % combo
	_caption(caption)
	_cue(&"zap", -8.0)
	_cue(&"pop", -11.0)
	if not color_id.is_empty():
		_start_note(color_id, 2.0, -7.0, false)
	if combo in [5, 10, 20]:
		_cue(StringName("combo_%d" % combo), -9.0)


func _wrong(event: Dictionary) -> void:
	_cancel_voice()
	_correction = &""
	_tick_duck_remaining = 0.32
	_caption("Wrong - %s" % _lives_phrase(int(event.get("lives", 0))))
	_cue(&"wrong", -5.0)
	var chosen := _canonical_color(StringName(str(event.get("color_id", ""))))
	var expected := _canonical_color(StringName(str(event.get("expected_color", ""))))
	if (
		not chosen.is_empty() and not expected.is_empty() and chosen != expected
		and str(chosen).get_slice("_", 0) == str(expected).get_slice("_", 0)
	):
		_correction = expected
		_correction_delay = 0.27


func _round_won(event: Dictionary) -> void:
	_clear_feedback()
	_phase = &"ROUND_WON"
	_silence_loops()
	var perfect := bool(event.get("perfect", false))
	var round_n := int(event.get("round", _round_number))
	_caption("Round %d cleared%s" % [round_n, " - clean sweep!" if perfect else ""])
	_cue(&"clean_wave" if perfect else &"round_won", -7.0)
	_recap = _event_colors(event, "sequence")
	_recap_remaining = 0.12
	var words: Array[StringName] = [&"clean_wave" if perfect else &"round_won"]
	if event.has("score"):
		words.append(&"score")
		words.append_array(_number_words(maxi(int(event["score"]), 0)))
	_queue_words(words, 0.22 if _recap.is_empty() else 0.8)


func _lives_phrase(lives: int) -> String:
	return "%d %s left" % [maxi(lives, 0), "life" if lives == 1 else "lives"]


func _event_colors(event: Dictionary, key: String) -> Array[StringName]:
	var result: Array[StringName] = []
	var value: Variant = event.get(key, [])
	if not value is Array and not value is PackedStringArray:
		push_warning("LaZer NFC: event.%s must be an array of colour IDs." % key)
		return result
	for item: Variant in value:
		var color_id := _canonical_color(StringName(str(item)))
		if color_id.is_empty():
			push_warning("LaZer NFC: unknown colour in event.%s." % key)
		else:
			result.append(color_id)
	return result


func _advance_feedback(delta: float) -> void:
	if not _correction.is_empty():
		_correction_delay -= delta
		if _correction_delay <= 0.0:
			if _phase == &"AWAITING":
				_caption("Correct shade - %s" % _color_label(_correction))
				_start_note(_correction, 1.0, -17.0, false)
			_correction = &""
	if _phase != &"ROUND_WON" or _recap.is_empty():
		return
	_recap_remaining -= delta
	if _recap_remaining <= 0.0:
		_start_note(_recap.pop_front(), 2.0, -15.0, false)
		_recap_remaining = 0.14


func _clear_feedback() -> void:
	_cancel_voice()
	_note_remaining = 0.0
	_tick_remaining = TICK_SLOW
	_tick_duck_remaining = 0.0
	_correction = &""
	_correction_delay = 0.0
	_recap.clear()
	_recap_remaining = 0.0


func _cancel_voice() -> void:
	_voice_queue.clear()
	_voice_remaining = 0.0
	_voice_delay = 0.0
	_stop_pooled(_voice_samples)


func _announcement_words(text: String, key: StringName) -> Array[StringName]:
	var words: Array[StringName] = []
	if _voice.has(key):
		words.append(key)
		return words
	if not key.is_empty():
		var binding := str(key).begins_with("bind_")
		var color_id := _canonical_color(StringName(str(key).trim_prefix("bind_")))
		if not color_id.is_empty():
			words.append(StringName("bind_" + str(color_id)) if binding else color_id)
			return words
		push_warning("LaZer NFC: no baked voice for key '%s'; caption remains available." % key)
		return words
	var phrase := text.to_lower().get_slice(".", 0).strip_edges().trim_suffix("!")
	var suffix: StringName = &""
	if phrase.ends_with(" bound") or phrase.ends_with(" skipped"):
		suffix = &"bound" if phrase.ends_with(" bound") else &"skipped"
		phrase = phrase.trim_suffix(" " + str(suffix))
	var color_id := _canonical_color(StringName(phrase.replace(" ", "_")))
	if not color_id.is_empty():
		words.append(color_id)
		if not suffix.is_empty():
			words.append(suffix)
		return words
	var phrase_key := StringName(phrase.replace(" ", "_"))
	if _voice.has(phrase_key):
		words.append(phrase_key)
	return words


func _round_words(number: int) -> Array[StringName]:
	var key := StringName("round_%d" % number)
	if _voice.has(key):
		return [key]
	var words: Array[StringName] = [&"round"]
	words.append_array(_number_words(number))
	return words


func _number_words(number: int) -> Array[StringName]:
	var words: Array[StringName] = []
	if number < 0:
		push_warning("LaZer NFC: spoken counters cannot be negative.")
		return words
	if number >= 1000000:
		for digit: String in str(number):
			words.append(StringName("number_" + digit))
		return words
	if number >= 1000:
		words.append_array(_number_words(floori(float(number) / 1000.0)))
		words.append(&"number_1000")
		number %= 1000
	if number >= 100:
		words.append(StringName("number_%d" % floori(float(number) / 100.0)))
		words.append(&"number_100")
		number %= 100
	if number > 20:
		words.append(StringName("number_%d" % (floori(float(number) / 10.0) * 10)))
		number %= 10
	if number > 0 or words.is_empty():
		words.append(StringName("number_%d" % number))
	return words


func _queue_words(words: Array[StringName], delay: float, budget: float = INF) -> void:
	if not _voice_enabled or _phase == &"SHOWING":
		return
	_voice_delay = delay
	var remaining := budget - delay
	for key: StringName in words:
		if not _voice.has(key):
			push_warning("LaZer NFC: missing baked voice '%s'." % key)
			continue
		var seconds := _voice[key].get_length() + VOICE_GAP
		if seconds > remaining:
			break
		_voice_queue.append(key)
		remaining -= seconds
	if delay <= 0.0:
		_advance_voice(0.0)


func _advance_voice(delta: float) -> void:
	if not _voice_enabled or _phase == &"SHOWING":
		return
	if _voice_remaining > 0.0:
		_voice_remaining -= delta
		if _voice_remaining > 0.0:
			return
		delta = -_voice_remaining
		_voice_remaining = 0.0
	_voice_delay = maxf(_voice_delay - delta, 0.0)
	if _voice_delay > 0.0 or _voice_queue.is_empty():
		return
	var key: StringName = _voice_queue.pop_front()
	_sample(_voice[key], VOICE_DB)
	_voice_remaining = _voice[key].get_length() + VOICE_GAP
