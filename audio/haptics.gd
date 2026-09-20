extends Node

## Named handheld envelopes use only the parent's unpaused clock, never timers.
## Vector3 entries are on milliseconds, following silence milliseconds, amplitude.
## Android provides cancellable durations; unsupported platforms stay silent.

const ROUND_START: Array[Vector3] = [Vector3(40, 0, 0.45)]
const NOTE: Array[Vector3] = [Vector3(40, 0, 0.32)]
const GO: Array[Vector3] = [Vector3(40, 40, 0.75), Vector3(40, 0, 0.9)]
const CORRECT: Array[Vector3] = [Vector3(60, 0, 1.0)]
const COMBO: Array[Vector3] = [
	Vector3(60, 50, 1.0), Vector3(30, 35, 0.65), Vector3(30, 0, 0.75),
]
const WRONG: Array[Vector3] = [
	Vector3(40, 25, 1.0), Vector3(40, 25, 1.0), Vector3(40, 45, 0.9),
	Vector3(35, 20, 0.8), Vector3(35, 20, 1.0),
	Vector3(35, 20, 0.75), Vector3(35, 0, 1.0),
]
const TIMEOUT: Array[Vector3] = [
	Vector3(40, 110, 0.75), Vector3(40, 110, 0.75), Vector3(40, 0, 0.75),
]
const ROUND_WON: Array[Vector3] = [Vector3(400, 0, 0.35)]
const RUN_OVER: Array[Vector3] = [
	Vector3(100, 25, 1.0), Vector3(100, 25, 0.7), Vector3(100, 25, 1.0),
	Vector3(100, 25, 0.7), Vector3(100, 0, 0.95),
]
const NOT_YET: Array[Vector3] = [Vector3(20, 0, 0.2)]
const UNKNOWN: Array[Vector3] = [Vector3(100, 0, 0.5)]

var _strength := 1.0
var _pattern: Array[Vector3] = []
var _pulse_index := 0
var _on := false
var _remaining_ms := 0.0
var _motor_active := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		stop()


func _exit_tree() -> void:
	stop()


## Strength is linear 0..1; turning it off cancels a pulse already in progress.
func configure(strength: float) -> void:
	if not is_finite(strength):
		push_warning("LaZer NFC: haptic strength must be finite.")
		stop()
		return
	_strength = clampf(strength, 0.0, 1.0)
	if _strength <= 0.0:
		stop()
	elif _motor_active and _on:
		_issue_phase()


## Feedback preempts its previous cause, so a new hit never inherits a wrong buzz.
func play_event(event: Dictionary) -> void:
	if not is_inside_tree():
		push_warning("LaZer NFC: add haptics to the scene before playing a pattern.")
		return
	if _strength <= 0.0 or get_tree().paused:
		stop()
		return
	var pattern := _event_pattern(event)
	if pattern.is_empty():
		return
	stop()
	_pattern = pattern
	_pulse_index = 0
	_on = true
	_remaining_ms = _pattern[0].x
	_issue_phase()


## Consume crossed phases, but do not replay missed motor pulses after a hitch.
func advance(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		push_warning("LaZer NFC: haptic time must be finite and nonnegative.")
		return
	if is_inside_tree() and get_tree().paused:
		stop()
		return
	if _pattern.is_empty():
		return
	var elapsed_ms := delta * 1000.0
	var changed := false
	while not _pattern.is_empty() and elapsed_ms >= _remaining_ms:
		elapsed_ms -= _remaining_ms
		_next_phase()
		changed = true
	if not _pattern.is_empty():
		_remaining_ms -= elapsed_ms
	if changed:
		_issue_phase()


## Navigation, suspension and replay all discard the remaining pulse chain.
func stop() -> void:
	_pattern = []
	_pulse_index = 0
	_remaining_ms = 0.0
	_on = false
	if _motor_active:
		_vibrate(0, 0.0)
		_motor_active = false


func _event_pattern(event: Dictionary) -> Array[Vector3]:
	var kind := StringName(str(event.get("type", "")))
	match kind:
		&"round_started":
			return ROUND_START
		&"note":
			return NOTE
		&"go":
			return GO
		&"hit":
			return COMBO if int(event.get("combo", 0)) in [5, 10, 20] else CORRECT
		&"wrong":
			return WRONG
		&"timeout":
			return TIMEOUT
		&"round_won":
			return ROUND_WON
		&"run_over":
			return RUN_OVER
		&"not_yet":
			return NOT_YET
		&"unknown":
			return UNKNOWN
		&"note_end", &"awaiting":
			return []
		_:
			push_warning("LaZer NFC: unknown haptic event '%s'." % kind)
			return []


func _next_phase() -> void:
	if _on and _pattern[_pulse_index].y > 0.0:
		_on = false
		_remaining_ms = _pattern[_pulse_index].y
		return
	_pulse_index += 1
	if _pulse_index >= _pattern.size():
		_pattern = []
		_on = false
		_remaining_ms = 0.0
	else:
		_on = true
		_remaining_ms = _pattern[_pulse_index].x


func _issue_phase() -> void:
	if _on and not _pattern.is_empty():
		_vibrate(maxi(ceili(_remaining_ms), 1), _pattern[_pulse_index].z * _strength)
		_motor_active = true
	elif _motor_active:
		_vibrate(0, 0.0)
		_motor_active = false


func _handheld_supported() -> bool:
	# iOS routes vibrate_handheld through Core Haptics from iOS 13 on, so both
	# duration and amplitude are honoured exactly as on Android.
	return (
		(OS.has_feature("android") or OS.has_feature("ios"))
		and DisplayServer.get_name() != "headless"
	)


func _vibrate(duration_ms: int, amplitude: float) -> void:
	if _handheld_supported():
		Input.vibrate_handheld(duration_ms, amplitude)
