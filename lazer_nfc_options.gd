extends RefCounted

## Constants only: the manifest and pure tests load these before autoloads exist.

const MANIFEST := preload("res://scripts/game_manifest.gd")

const GAME_ID := "lazer_nfc"
const LIVES_KEY := "game/lz_lives"
const SCAN_WINDOW_KEY := "game/lz_scan_window"
const RAMP_KEY := "game/lz_ramp"
const START_LENGTH_KEY := "game/lz_start_length"
const PALETTE_START_KEY := "game/lz_palette_start"
const SHADE_MODE_KEY := "game/lz_shade_mode"
const TOUCH_PAD_KEY := "game/lz_touch_pad"
const HAPTICS_KEY := "game/lz_haptics"
const VOICE_KEY := "game/lz_voice"
const REBIND_TAGS_KEY := "game/lz_rebind_tags"

const MIN_LIVES := 1
const MAX_LIVES := 5
const DEFAULT_LIVES := 3
const MIN_SCAN_WINDOW := 2.0
const MAX_SCAN_WINDOW := 6.0
const DEFAULT_SCAN_WINDOW := 4.0
const MIN_START_LENGTH := 2
const MAX_START_LENGTH := 4
const DEFAULT_START_LENGTH := 3
const MIN_PALETTE_START := 3
const MAX_PALETTE_START := 7
const DEFAULT_PALETTE_START := 4
const DEFAULT_SHADE_MODE := false
const DEFAULT_TOUCH_PAD := false
const MIN_HAPTICS := 0.0
const MAX_HAPTICS := 1.0
const DEFAULT_HAPTICS := 1.0
const DEFAULT_VOICE := true
const DEFAULT_REBIND_TAGS := false

const RAMP_GENTLE := 0
const RAMP_STANDARD := 1
const RAMP_STEEP := 2
const DEFAULT_RAMP := RAMP_STANDARD
## Seconds removed per round, in Gentle / Standard / Steep order.
const WINDOW_RAMP: Array[float] = [0.1, 0.2, 0.3]
const SHOW_RAMP: Array[float] = [0.03, 0.05, 0.08]

## Durations are seconds unless the name explicitly ends in _MS.
const ROUND_START_TIME := 0.8
const SHOW_TIME := 0.8
const SHOW_TIME_MIN := 0.5
const SHOW_GAP := 0.3
const SHOW_END_TIME := 0.6
const SCAN_WINDOW_MIN := MIN_SCAN_WINDOW
const RECALL_GAP := 0.5
const ROUND_WON_TIME := 1.5
const NOTE_DURATION := 0.4
const TICK_PERIOD_START := 0.5
const TICK_PERIOD_END := 0.12
const BINDING_TIMEOUT_S := 12.0
const GRACE_MS := 150
const NFC_LATENCY_COMP_MS := 80
const NFC_DEBOUNCE_MS := 500
const DOUBLE_SCAN_MS := 1500
## Bound callback ages; an arbitrarily old timestamp cannot buy extra time.
const MAX_ANSWER_AGE_S := (GRACE_MS + NFC_LATENCY_COMP_MS) / 1000.0

const SEQ_LEN_MAX := 12
const PALETTE_GROWTH_ROUNDS: Array[int] = [3, 5, 7]
const ALLOW_REPEAT_FROM_ROUND := 4
const HIT_POINTS := 100
const ROUND_BONUS_PER_NOTE := 50
const COMBO_STEP := 0.25
const COMBO_MAX := 4.0
const MOMENTUM_BONUS_MAX := 0.5
## Linear acceleration in metres per second squared, not a time or a ratio.
const MOMENTUM_ENERGY_FULL := 25.0

const COLOR_ACTIONS: Array[StringName] = [
	&"lz_color_1", &"lz_color_2", &"lz_color_3", &"lz_color_4",
	&"lz_color_5", &"lz_color_6", &"lz_color_7",
]
const DARK_ACTION := &"lz_shade_dark"
const LIGHT_ACTION := &"lz_shade_light"
const CONFIRM_ACTION := &"lz_confirm"

const TUNABLES: Array[Dictionary] = [
	{
		"key": LIVES_KEY,
		"type": MANIFEST.OPTION_SLIDER,
		"default": DEFAULT_LIVES,
		"min": MIN_LIVES, "max": MAX_LIVES, "step": 1.0,
		"title": "Starting batteries",
		"description": "Lives in the next run's shared pool of memory rounds.",
		"format": MANIFEST.FORMAT_LIVES,
		"heading": "LaZer NFC - next run",
	},
	{
		"key": SCAN_WINDOW_KEY,
		"type": MANIFEST.OPTION_SLIDER,
		"default": DEFAULT_SCAN_WINDOW,
		"min": MIN_SCAN_WINDOW, "max": MAX_SCAN_WINDOW, "step": 0.1,
		"title": "Scan window",
		"description": "Seconds to recall each robot in the first memory round.",
		"format": MANIFEST.FORMAT_SECONDS,
		"heading": "LaZer NFC - next run",
	},
	{
		"key": RAMP_KEY,
		"type": MANIFEST.OPTION_CHOICE,
		"default": DEFAULT_RAMP,
		"title": "Difficulty ramp",
		"description": "How quickly recall windows and shown notes shorten.",
		"heading": "LaZer NFC - next run",
		"choices": [
			{"value": RAMP_GENTLE, "title": "Gentle"},
			{"value": RAMP_STANDARD, "title": "Standard"},
			{"value": RAMP_STEEP, "title": "Steep"},
		],
	},
	{
		"key": START_LENGTH_KEY,
		"type": MANIFEST.OPTION_SLIDER,
		"default": DEFAULT_START_LENGTH,
		"min": MIN_START_LENGTH, "max": MAX_START_LENGTH, "step": 1.0,
		"title": "Starting sequence",
		"description": "Robots in round one; each round adds one, up to twelve.",
		"format": MANIFEST.FORMAT_COUNT,
		"heading": "LaZer NFC - next run",
	},
	{
		"key": PALETTE_START_KEY,
		"type": MANIFEST.OPTION_SLIDER,
		"default": DEFAULT_PALETTE_START,
		"min": MIN_PALETTE_START, "max": MAX_PALETTE_START, "step": 1.0,
		"title": "Starting colours",
		"description": "Active hues, limited to the tags actually available.",
		"format": MANIFEST.FORMAT_COUNT,
		"heading": "LaZer NFC - next run",
	},
	{
		"key": SHADE_MODE_KEY,
		"type": MANIFEST.OPTION_TOGGLE,
		"default": DEFAULT_SHADE_MODE,
		"title": "Shade mode",
		"description": "Recall dark, base and light instruments: up to 21 tags.",
		"heading": "LaZer NFC - next run",
	},
	{
		"key": TOUCH_PAD_KEY,
		"type": MANIFEST.OPTION_TOGGLE,
		"default": DEFAULT_TOUCH_PAD,
		"title": "Always show touch pad",
		"description": "Touch answers mark the run Assisted and halve its total score.",
		"heading": "LaZer NFC - feedback",
	},
	{
		"key": HAPTICS_KEY,
		"type": MANIFEST.OPTION_SLIDER,
		"default": DEFAULT_HAPTICS,
		"min": MIN_HAPTICS, "max": MAX_HAPTICS, "step": 0.05,
		"title": "Vibration strength",
		"description": "Strength of meaningful haptic cues; zero disables vibration.",
		"format": MANIFEST.FORMAT_PERCENT,
		"heading": "LaZer NFC - feedback",
	},
	{
		"key": VOICE_KEY,
		"type": MANIFEST.OPTION_TOGGLE,
		"default": DEFAULT_VOICE,
		"title": "Spoken announcements",
		"description": "Read prompts aloud without disabling visual audio captions.",
		"heading": "LaZer NFC - feedback",
	},
	{
		"key": REBIND_TAGS_KEY,
		"type": MANIFEST.OPTION_TOGGLE,
		"default": DEFAULT_REBIND_TAGS,
		"title": "Ask for my tags again",
		"description": "Repeat physical tag setup next run; cleared after binding.",
		"heading": "LaZer NFC - tag setup",
	},
]

const CONTROL_BINDINGS: Array[Dictionary] = [
	{
		"key": "controls/lz_color_1", "action": COLOR_ACTIONS[0],
		"default": KEY_1, "title": "Red - triangle",
		"player": 0, "heading": "Colour keys",
	},
	{
		"key": "controls/lz_color_2", "action": COLOR_ACTIONS[1],
		"default": KEY_2, "title": "Orange - diamond",
		"player": 0, "heading": "Colour keys",
	},
	{
		"key": "controls/lz_color_3", "action": COLOR_ACTIONS[2],
		"default": KEY_3, "title": "Yellow - star",
		"player": 0, "heading": "Colour keys",
	},
	{
		"key": "controls/lz_color_4", "action": COLOR_ACTIONS[3],
		"default": KEY_4, "title": "Green - circle",
		"player": 0, "heading": "Colour keys",
	},
	{
		"key": "controls/lz_color_5", "action": COLOR_ACTIONS[4],
		"default": KEY_5, "title": "Blue - square",
		"player": 0, "heading": "Colour keys",
	},
	{
		"key": "controls/lz_color_6", "action": COLOR_ACTIONS[5],
		"default": KEY_6, "title": "Indigo - hexagon",
		"player": 0, "heading": "Colour keys",
	},
	{
		"key": "controls/lz_color_7", "action": COLOR_ACTIONS[6],
		"default": KEY_7, "title": "Violet - plus",
		"player": 0, "heading": "Colour keys",
	},
	{
		"key": "controls/lz_shade_dark", "action": DARK_ACTION,
		"default": KEY_Q, "title": "Hold for dark shade",
		"description": "Hold both shade keys for the base shade.",
		"player": 0, "heading": "Shade keys",
	},
	{
		"key": "controls/lz_shade_light", "action": LIGHT_ACTION,
		"default": KEY_E, "title": "Hold for light shade",
		"description": "Hold both shade keys for the base shade.",
		"player": 0, "heading": "Shade keys",
	},
	{
		"key": "controls/lz_confirm", "action": CONFIRM_ACTION,
		"default": KEY_SPACE, "title": "Start / confirm",
		"player": 0, "heading": "Run",
	},
]
