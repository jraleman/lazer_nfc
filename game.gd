extends RefCounted

## A pocket-sized memory laboratory, discovered without changing the host.

const OPTIONS := preload("res://games/lazer_nfc/lazer_nfc_options.gd")
const GAME_ID := OPTIONS.GAME_ID


## One experiment is one shell round; its growing sequences are game-owned.
static func manifest() -> GameManifest:
	var game := GameManifest.new()
	game.id = GAME_ID
	game.title = "LaZer NFC"
	game.tagline = "Little robots. Big memory. One more experiment."
	game.menu_order = 5
	game.gameplay_scene_path = "res://games/lazer_nfc/gameplay.tscn"
	game.intro_scene_path = "res://games/lazer_nfc/intro.tscn"
	game.supports_single_player = true
	game.supports_multiplayer = false
	game.supports_cpu_opponent = false
	game.uses_shell_round_rules = false
	game.default_lives_mode = false
	game.control_style = GameManifest.CONTROL_STYLE_CUSTOM_KEYS
	game.tunables = OPTIONS.TUNABLES
	game.control_bindings = OPTIONS.CONTROL_BINDINGS
	game.stats_url = "https://deskcansaw.com/stats/lz"
	game.tutorial_video_path = "res://games/lazer_nfc/assets/video/tutorial.ogv"
	game.tutorial_poster_path = (
		"res://games/lazer_nfc/assets/video/tutorial_poster.webp"
	)
	game.share_art_scene_path = "res://games/lazer_nfc/ui/share_art.tscn"
	game.share_art_style = GAME_ID
	game.copy = {
		"single_player_description": (
			"Watch and listen to the little robots, then recall their colours "
			+ "in order. Play with keys, the colour pad, or real NFC tags."
		),
		"solo_confirm_title": "Your next bright idea",
		"solo_confirm_description": (
			"One phone, one memory, a laboratory full of mischief."
		),
		"instructions_headline": "Remember. Recall. Light up the lab.",
		"instructions_rules": (
			"Listen to the whole sequence before answering. Each robot has "
			+ "a colour, shape and instrument.\n"
			+ "When the robots turn grey, repeat their colours in order. "
			+ "A wrong answer costs a life without restarting the deadline; "
			+ "a timeout costs a life and the robot escapes.\n"
			+ "Clean rounds and consecutive hits earn bonuses. Each round "
			+ "adds a robot, up to twelve. The experiment ends at zero lives."
		),
		"instructions_demo_prompt": "HEAR THE PATTERN. FIRE THE COLOURS.",
		"instructions_solo_summary": (
			"Use Learn the sounds before starting. The first palette is red, "
			+ "yellow, green and blue; more colours join as you advance. "
			+ "The lab shows your progress, never the next answer."
		),
		"instructions_player_one_controls": (
			"Use the colour keys below or tap the labelled colour pad. "
			+ "The shade keys are held with a colour key in advanced mode; "
			+ "the pad has Dark, Base and Light selectors.\n"
			+ "On Android, enabled NFC offers a guided tag roll call. "
			+ "Tap the upper back of the phone against each labelled tag. "
			+ "Lift before tapping the same tag again.\n"
			+ "On iPhone the same roll call runs behind Apple's scanning "
			+ "sheet, which covers the lab while it waits. Dismiss it with "
			+ "Cancel to switch to keys and touch.\n"
			+ "Touch answers mark the run Assisted (half score); keys and "
			+ "NFC use full scoring. Trying sounds before a run is free. "
			+ "Esc pauses. Rebind keys in Settings > Controls."
		),
	}
	game.achievements = {
		"lazer_nfc_first_run": {
			"title": "First Contact",
			"description": "Finish a LaZer NFC experiment.",
			"badge": "LZ",
		},
		"lazer_nfc_round_five": {
			"title": "Long Memory",
			"description": "Reach round five in one experiment.",
			"badge": "5",
		},
		"lazer_nfc_flawless_round": {
			"title": "Clean Sweep",
			"description": "Recall six or more robots without losing a life.",
			"badge": "6",
		},
		"lazer_nfc_shade_run": {
			"title": "Full Spectrum",
			"description": "Finish an experiment with advanced shades enabled.",
			"badge": "21",
		},
		"lazer_nfc_unassisted": {
			"title": "No Handrail",
			"description": "Reach round four using only keys or NFC tags.",
			"badge": "NFC",
		},
	}
	game.credits = [
		{"heading": "Game Design & Code", "lines": ["DeskCanSaw"]},
		{
			"heading": "The Little Laboratory",
			"lines": [
				"Original toy robots, tabletop laboratory and vector artwork",
				"DeskCanSaw - no external model or sample packs",
			],
		},
		{
			"heading": "Music & Sound",
			"lines": [
				"Original offline-authored instruments, lab music and playful cues",
				"Reproducible PCM sound bank in tools/bake_colors.py",
				"Original prompt text; offline Microsoft Zira Desktop speech",
			],
		},
		{
			"heading": "Accessible Experiments",
			"lines": [
				"Colour, shape and instrument identify every robot",
				"Rebindable keys, touch fallback, captions and reduced motion",
				"Native Android reader mode and iPhone Core NFC, hardware optional",
			],
		},
	]
	game.theme = _theme()
	return game


static func _theme() -> GameTheme:
	var theme := GameTheme.new()
	theme.logo_texture_path = "res://games/lazer_nfc/assets/visual/logo.svg"
	theme.logo_color = Color.WHITE
	theme.plaque_color = Color.WHITE
	theme.accent = Color("7ce6d2")
	theme.light = Color("fff0cd")
	theme.background_top = Color("152d39")
	theme.background_bottom = Color("08131e")
	theme.background_material = preload("res://games/lazer_nfc/ui/menu_background.tres")
	theme.plaque_material = preload("res://games/lazer_nfc/ui/menu_plaque.tres")
	theme.ui_theme = preload("res://games/lazer_nfc/ui/menu_skin.tres")
	theme.menu_motion = GameTheme.MenuMotion.SPRING
	theme.style_share_card = true
	return theme
