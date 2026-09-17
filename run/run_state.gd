extends RefCounted

## Pause-safe, node-free memory rules. Only advance() moves the explicit clock.

const OPTIONS := preload("res://games/lazer_nfc/lazer_nfc_options.gd")
const PALETTE := preload("res://games/lazer_nfc/run/palette.gd")
const SEQUENCE := preload("res://games/lazer_nfc/run/sequence.gd")

enum State {
	READY, ROUND_START, SHOWING, SHOW_END, AWAITING,
	RECALL_GAP, ROUND_WON, RUN_OVER,
}

const TIME_EPSILON := 0.000000001
const SCORE_EPSILON := 0.000000001
const GRACE_SECONDS := OPTIONS.GRACE_MS / 1000.0
const DELIVERY_SECONDS := OPTIONS.NFC_LATENCY_COMP_MS / 1000.0
const CONFIG_NUMBERS: Array[Dictionary] = [
	{
		"key": "lives", "default": OPTIONS.DEFAULT_LIVES,
		"min": OPTIONS.MIN_LIVES, "max": OPTIONS.MAX_LIVES, "integer": true,
	},
	{
		"key": "scan_window", "default": OPTIONS.DEFAULT_SCAN_WINDOW,
		"min": OPTIONS.MIN_SCAN_WINDOW, "max": OPTIONS.MAX_SCAN_WINDOW,
		"integer": false,
	},
	{
		"key": "ramp", "default": OPTIONS.DEFAULT_RAMP,
		"min": OPTIONS.RAMP_GENTLE, "max": OPTIONS.RAMP_STEEP, "integer": true,
	},
	{
		"key": "start_length", "default": OPTIONS.DEFAULT_START_LENGTH,
		"min": OPTIONS.MIN_START_LENGTH, "max": OPTIONS.MAX_START_LENGTH,
		"integer": true,
	},
	{
		"key": "palette_start", "default": OPTIONS.DEFAULT_PALETTE_START,
		"min": OPTIONS.MIN_PALETTE_START, "max": OPTIONS.MAX_PALETTE_START,
		"integer": true,
	},
]

var state := State.READY
var clock := 0.0
var round_n := 0
var lives := OPTIONS.DEFAULT_LIVES
var score := 0
var combo := 0
var best_combo := 0
var hits := 0
var wrongs := 0
var timeouts := 0
var assisted := false
var rounds_cleared := 0
var flawless_six := false
var shade_mode := false
var sequence: Array[StringName] = []
var active_palette: Array[StringName] = []
var recall_index := 0
var show_index := -1
var show_duration := OPTIONS.SHOW_TIME
var window_duration := OPTIONS.DEFAULT_SCAN_WINDOW
## Actual model-clock boundaries, in seconds; resume replaces all four.
var window_started_at := 0.0
var window_deadline := 0.0
var window_physical_deadline := 0.0
## Dispatch is strictly after this boundary, so an on-boundary input wins.
var window_timeout_at := 0.0
var window_remaining: float:
	get:
		if state != State.AWAITING:
			return 0.0
		return clampf(window_deadline - clock, 0.0, window_duration)
## Invalid configuration/delta errors also remain inspectable by pure callers.
var last_error := ""

var _events: Array[Dictionary] = []
var _generator := SEQUENCE.new()
var _available_colors: Array[StringName] = []
var _start_length := OPTIONS.DEFAULT_START_LENGTH
var _palette_start := OPTIONS.DEFAULT_PALETTE_START
var _scan_window := OPTIONS.DEFAULT_SCAN_WINDOW
var _ramp := OPTIONS.DEFAULT_RAMP
var _next_transition_at := INF
var _visible_color := &""
var _raw_score := 0
var _round_life_lost := false


func _init() -> void:
	reset({})


## Rejects a bad configuration atomically, preserving any run already in progress.
func reset(config: Dictionary, seed_value: int = 0) -> void:
	var error := _configuration_error(config)
	if not error.is_empty():
		_report_error(error)
		return
	last_error = ""
	_start_length = int(config.get("start_length", OPTIONS.DEFAULT_START_LENGTH))
	_palette_start = int(config.get("palette_start", OPTIONS.DEFAULT_PALETTE_START))
	_scan_window = float(config.get("scan_window", OPTIONS.DEFAULT_SCAN_WINDOW))
	_ramp = int(config.get("ramp", OPTIONS.DEFAULT_RAMP))
	shade_mode = bool(config.get("shade_mode", OPTIONS.DEFAULT_SHADE_MODE))
	var available: Array = config.get("available_colors", PALETTE.all_ids(shade_mode))
	_available_colors.clear()
	for id: StringName in PALETTE.all_ids(shade_mode):
		if available.has(id):
			_available_colors.append(id)
	_generator.reset(seed_value)
	state = State.READY
	clock = 0.0
	round_n = 0
	lives = int(config.get("lives", OPTIONS.DEFAULT_LIVES))
	score = 0
	_raw_score = 0
	combo = 0
	best_combo = 0
	hits = 0
	wrongs = 0
	timeouts = 0
	assisted = false
	rounds_cleared = 0
	flawless_six = false
	sequence.clear()
	active_palette = _palette_for_round(1)
	recall_index = 0
	show_index = -1
	show_duration = OPTIONS.SHOW_TIME
	window_duration = _scan_window
	window_started_at = 0.0
	window_deadline = 0.0
	window_physical_deadline = 0.0
	window_timeout_at = 0.0
	_next_transition_at = INF
	_visible_color = &""
	_round_life_lost = false
	_events.clear()


## Tag binding and sound practice happen outside the model, before this call.
func begin() -> void:
	if state != State.READY:
		_ignore(&"not_yet", &"", &"already_started")
		return
	_start_round()


## Processes every crossed boundary at its scheduled time, including long hitches.
func advance(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		_report_error("delta must be finite and non-negative seconds.")
		return
	var target := clock + delta
	if not is_finite(target):
		_report_error("delta overflows the model clock.")
		return
	if state == State.READY or state == State.RUN_OVER:
		return
	while _next_transition_at <= target + TIME_EPSILON:
		if state == State.AWAITING and target <= window_timeout_at + TIME_EPSILON:
			break
		clock = maxf(clock, _next_transition_at)
		_transition()
		if state == State.RUN_OVER:
			return
	clock = maxf(clock, target)


## Returns true only for a credited hit; wrong attempts keep the original deadline.
func answer(
	color_id: StringName, age_seconds: float = 0.0,
	momentum: float = 0.0, assisted_input: bool = false
) -> bool:
	if not PALETTE.is_valid(color_id) or not active_palette.has(color_id):
		_ignore(&"unknown", color_id, &"unavailable_color")
		return false
	if state != State.AWAITING:
		_ignore(&"not_yet", color_id, &"no_window")
		return false
	if not is_finite(age_seconds) or age_seconds < 0.0 \
			or age_seconds > OPTIONS.MAX_ANSWER_AGE_S:
		_ignore(&"not_yet", color_id, &"invalid_age")
		return false
	if not is_finite(momentum):
		_ignore(&"not_yet", color_id, &"invalid_momentum")
		return false
	var physical_time := clock - age_seconds
	if physical_time < window_started_at - TIME_EPSILON:
		_ignore(&"not_yet", color_id, &"before_window")
		return false
	if physical_time > window_physical_deadline + TIME_EPSILON:
		_ignore(&"not_yet", color_id, &"after_deadline")
		return false
	if assisted_input and not assisted:
		assisted = true
		_sync_score()
	var expected := sequence[recall_index]
	if color_id != expected:
		wrongs += 1
		_lose_life()
		_emit(&"wrong", {
			"color_id": color_id, "expected_color": expected,
			"near_miss": PALETTE.hue_id(color_id) == PALETTE.hue_id(expected),
			"index": recall_index, "lives": lives, "combo": combo,
			"points": 0, "score": score, "assisted": assisted,
		})
		if lives == 0:
			_end_run()
		return false
	hits += 1
	combo += 1
	best_combo = maxi(best_combo, combo)
	var fraction := clampf(
		(window_deadline - physical_time) / window_duration, 0.0, 1.0
	)
	# Shades have their own factor; the palette factor counts distinct hues.
	var palette_factor := 1.0 + 0.15 * (_active_hues() - 4)
	var shade_factor := 1.5 if shade_mode else 1.0
	var motion_factor := 1.0 + OPTIONS.MOMENTUM_BONUS_MAX * clampf(
		momentum / OPTIONS.MOMENTUM_ENERGY_FULL, 0.0, 1.0
	)
	var points_value := (
		OPTIONS.HIT_POINTS * (0.5 + 0.5 * fraction) * palette_factor
		* shade_factor * _multiplier() * motion_factor
	)
	# Exact half-point ties must not flip with floating-point frame accumulation.
	var raw_points := roundi(points_value + SCORE_EPSILON)
	var points := _credit(raw_points)
	_emit(&"hit", {
		"color_id": color_id, "index": recall_index,
		"points": points, "raw_points": raw_points, "score": score,
		"lives": lives, "combo": combo, "assisted": assisted,
		"time_fraction": fraction,
	})
	_resolve_enemy(true)
	return true


## Reissues this enemy only; paused wall-clock time never enters the calculation.
func resume_window() -> void:
	if state == State.AWAITING:
		_open_window()


## Transfers event ownership so later mutation cannot rewrite the model's queue.
func drain_events() -> Array[Dictionary]:
	var result := _events
	_events = []
	return result


## Recall never exposes the sequence or expected instrument, even during grace.
func snapshot() -> Dictionary:
	return {
		"state": StringName(State.keys()[state]),
		"round": round_n, "length": sequence.size(),
		"recall_index": recall_index, "show_index": show_index,
		"visible_color": _visible_color if state == State.SHOWING else &"",
		"active_palette": active_palette.duplicate(),
		"window_ratio": clampf(window_remaining / window_duration, 0.0, 1.0),
		"lives": lives, "combo": combo, "multiplier": _multiplier(),
		"score": score, "best_combo": best_combo, "rounds_cleared": rounds_cleared,
		"shade_mode": shade_mode,
	}


func _start_round() -> void:
	round_n += 1
	var next_palette := _palette_for_round(round_n)
	var new_colors: Array[StringName] = []
	for id: StringName in next_palette:
		if not active_palette.has(id):
			new_colors.append(id)
	active_palette = next_palette
	var length := mini(_start_length + round_n - 1, OPTIONS.SEQ_LEN_MAX)
	sequence = _generator.grow(sequence, length, active_palette, round_n)
	show_duration = maxf(
		OPTIONS.SHOW_TIME_MIN, OPTIONS.SHOW_TIME - (round_n - 1) * OPTIONS.SHOW_RAMP[_ramp]
	)
	window_duration = maxf(
		OPTIONS.SCAN_WINDOW_MIN, _scan_window - (round_n - 1) * OPTIONS.WINDOW_RAMP[_ramp]
	)
	recall_index = 0
	show_index = -1
	_visible_color = &""
	_round_life_lost = false
	state = State.ROUND_START
	_next_transition_at = clock + OPTIONS.ROUND_START_TIME
	_emit(&"round_started", {"count": length, "new_colors": new_colors})


func _transition() -> void:
	match state:
		State.ROUND_START:
			state = State.SHOWING
			show_index = 0
			_show_note()
		State.SHOWING:
			if not _visible_color.is_empty():
				_emit(&"note_end", {"color_id": _visible_color, "index": show_index})
				_visible_color = &""
				_next_transition_at = clock + OPTIONS.SHOW_GAP
			elif show_index + 1 < sequence.size():
				show_index += 1
				_show_note()
			else:
				state = State.SHOW_END
				show_index = -1
				_next_transition_at = clock + OPTIONS.SHOW_END_TIME
		State.SHOW_END, State.RECALL_GAP:
			_open_window()
		State.AWAITING:
			timeouts += 1
			_lose_life()
			_emit(&"timeout", {
				"color_id": sequence[recall_index], "index": recall_index,
				"lives": lives, "combo": combo, "points": 0, "score": score,
			})
			if lives == 0:
				_end_run()
			else:
				_resolve_enemy(false)
		State.ROUND_WON:
			_start_round()


func _show_note() -> void:
	_visible_color = sequence[show_index]
	_next_transition_at = clock + show_duration
	_emit(&"note", {
		"color_id": _visible_color, "index": show_index,
		"count": sequence.size(), "duration": show_duration,
	})


func _open_window() -> void:
	var opens_recall := state == State.SHOW_END
	state = State.AWAITING
	_visible_color = &""
	window_started_at = clock
	window_deadline = clock + window_duration
	window_physical_deadline = window_deadline + GRACE_SECONDS
	window_timeout_at = window_physical_deadline + DELIVERY_SECONDS
	_next_transition_at = window_timeout_at
	if opens_recall:
		_emit(&"go", {"count": sequence.size()})
	_emit(&"awaiting", {
		"index": recall_index, "count": sequence.size(), "duration": window_duration,
		"window_started_at": window_started_at, "deadline": window_deadline,
		"physical_deadline": window_physical_deadline, "timeout_at": window_timeout_at,
	})


func _resolve_enemy(hit: bool) -> void:
	if recall_index + 1 < sequence.size():
		recall_index += 1
		state = State.RECALL_GAP
		_next_transition_at = clock + OPTIONS.RECALL_GAP
		return
	state = State.ROUND_WON
	_next_transition_at = clock + OPTIONS.ROUND_WON_TIME
	if hit:
		rounds_cleared += 1
		var perfect := not _round_life_lost
		var raw_bonus := OPTIONS.ROUND_BONUS_PER_NOTE * sequence.size()
		if perfect:
			raw_bonus *= 2
			if sequence.size() >= 6:
				flawless_six = true
		var points := _credit(raw_bonus)
		_emit(&"round_won", {
			"count": sequence.size(), "points": points, "raw_points": raw_bonus,
			"perfect": perfect, "score": score, "lives": lives, "combo": combo,
		})


func _lose_life() -> void:
	lives = maxi(lives - 1, 0)
	combo = 0
	_round_life_lost = true


func _end_run() -> void:
	if state == State.RUN_OVER:
		return
	state = State.RUN_OVER
	_visible_color = &""
	_next_transition_at = INF
	_emit(&"run_over", {
		"score": score, "lives": lives, "combo": combo,
		"count": rounds_cleared, "assisted": assisted,
	})


func _credit(points: int) -> int:
	var before := score
	_raw_score += points
	_sync_score()
	return score - before


func _sync_score() -> void:
	score = floori(_raw_score * 0.5) if assisted else _raw_score


func _multiplier() -> float:
	return minf(OPTIONS.COMBO_MAX, 1.0 + combo * OPTIONS.COMBO_STEP)


func _active_hues() -> int:
	var count := 0
	for hue: StringName in PALETTE.HUES:
		for id: StringName in active_palette:
			if PALETTE.hue_id(id) == hue:
				count += 1
				break
	return count


func _palette_for_round(number: int) -> Array[StringName]:
	var hue_limit := _palette_start
	for growth_round: int in OPTIONS.PALETTE_GROWTH_ROUNDS:
		if number >= growth_round:
			hue_limit += 1
	var result: Array[StringName] = []
	var hue_count := 0
	for hue: StringName in PALETTE.GROWTH_ORDER:
		var colors: Array[StringName] = []
		for id: StringName in _available_colors:
			if PALETTE.hue_id(id) == hue:
				colors.append(id)
		if colors.is_empty():
			continue
		result.append_array(colors)
		hue_count += 1
		if hue_count >= hue_limit:
			break
	return result


func _emit(type: StringName, details: Dictionary) -> void:
	details["type"] = type
	details["round"] = round_n
	details["time"] = clock
	_events.append(details)


func _ignore(type: StringName, color_id: StringName, reason: StringName) -> void:
	_emit(type, {"color_id": color_id, "index": recall_index, "reason": reason})


func _report_error(message: String) -> void:
	last_error = "LaZer NFC: %s" % message
	push_error(last_error)


func _configuration_error(config: Dictionary) -> String:
	var keys: Array[String] = ["shade_mode", "available_colors"]
	for rule: Dictionary in CONFIG_NUMBERS:
		var key: String = rule["key"]
		keys.append(key)
		var value: Variant = config.get(key, rule["default"])
		if not (value is int or value is float):
			return "%s must be a number." % key
		var number := float(value)
		if not is_finite(number) or number < float(rule["min"]) \
				or number > float(rule["max"]):
			return "%s must be finite and between %s and %s." % [
				key, rule["min"], rule["max"],
			]
		if bool(rule["integer"]) and number != floorf(number):
			return "%s must be an integer." % key
	for key: Variant in config:
		if not (key is String or key is StringName) or not keys.has(String(key)):
			return "unknown configuration key: %s." % str(key)
	var shades: Variant = config.get("shade_mode", OPTIONS.DEFAULT_SHADE_MODE)
	if not shades is bool:
		return "shade_mode must be a bool."
	var available: Variant = config.get("available_colors", PALETTE.all_ids(bool(shades)))
	if not available is Array:
		return "available_colors must be an Array[StringName]."
	var seen: Array[StringName] = []
	var usable := 0
	for id: Variant in available:
		if not id is StringName or not PALETTE.is_valid(id):
			return "available_colors must contain only valid StringName colour ids."
		if seen.has(id):
			return "available_colors must not contain duplicate colour ids."
		seen.append(id)
		if bool(shades) or PALETTE.shade_index(id) == 1:
			usable += 1
	if usable < 2:
		return "available_colors needs two usable instruments to avoid early repeats."
	return ""
