extends SceneTree

## Real-renderer coverage for the full shell, diorama and native input deck.

const OPTIONS := preload("res://games/lazer_nfc/lazer_nfc_options.gd")
const GAME_PATH := "res://games/lazer_nfc/gameplay.tscn"
const FIXTURE_PATH := "res://games/lazer_nfc/tests/lazer_nfc_scene_fixture.gd"

var _failures := PackedStringArray()
var _capture_dir := ""


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lazer-capture-dir="):
			_capture_dir = argument.trim_prefix("--lazer-capture-dir=")
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("LaZer NFC layout coverage requires a graphics display.")
		quit(1)
		return
	var settings := root.get_node("Settings")
	var values := settings.get("_values") as Dictionary
	var original := values.duplicate(true)
	var timer := settings.get("_save_timer") as Timer
	var timer_mode := timer.process_mode
	timer.process_mode = Node.PROCESS_MODE_DISABLED
	for option: Dictionary in OPTIONS.TUNABLES:
		settings.call("set_value", option["key"], option["default"])
	settings.call("set_value", OPTIONS.VOICE_KEY, false)
	settings.call("set_value", OPTIONS.HAPTICS_KEY, 0.0)
	settings.call("set_value", "ui/scale", 1.0)
	GameCatalog.select(OPTIONS.GAME_ID)
	var packed := load(GAME_PATH) as PackedScene
	var fixture := load(FIXTURE_PATH) as Script
	if packed == null or fixture == null or not fixture.can_instantiate():
		printerr("The real game must compile before capturing its layout.")
		quit(1)
		return
	var game := packed.instantiate()
	var color: Color = game.get("player_one_color")
	game.set_script(fixture)
	game.set("player_one_color", color)
	root.add_child(game)
	game.set_process(false)
	for frame in 4:
		await process_frame
	var configurations: Array[Dictionary] = [
		{"name": "landscape", "canvas": Vector2i(1920, 1080), "window": Vector2i(1280, 720)},
		{"name": "portrait", "canvas": Vector2i(720, 1280), "window": Vector2i(540, 960)},
		{"name": "ultrawide", "canvas": Vector2i(1920, 1080), "window": Vector2i(1720, 720)},
	]
	for configuration in configurations:
		root.content_scale_size = configuration["canvas"]
		root.size = configuration["window"]
		for frame in 5:
			await process_frame
		game.call("_queue_layout")
		for frame in 3:
			await process_frame
		_check_layout(game, str(configuration["name"]))
		await _capture(str(configuration["name"]) + "-ready")
		game.call("_begin_experiment")
		game.call("_update_round", 1.0, 0.0)
		for frame in 3:
			await process_frame
		await _capture(str(configuration["name"]) + "-showing")
		game.call("_update_round", 5.0, 0.0)
		for frame in 3:
			await process_frame
		await _capture(str(configuration["name"]) + "-recall")
		game.call("_on_play_again_pressed")
	settings.call("set_value", OPTIONS.SHADE_MODE_KEY, true)
	settings.call("set_value", Settings.REDUCED_MOTION_KEY, true)
	settings.call("set_value", Settings.VISUAL_EFFECTS_KEY, false)
	root.content_scale_size = Vector2i(720, 1280)
	root.size = Vector2i(540, 960)
	game.call("_on_play_again_pressed")
	for frame in 6:
		await process_frame
	_check_layout(game, "portrait-shades-reduced")
	await _capture("portrait-shades-reduced")
	settings.call("set_value", "ui/scale", 1.5)
	(game.get_node("%PauseButton") as Button).show()
	game.call("_queue_layout")
	for frame in 10:
		await process_frame
	_check_layout(game, "portrait-large-ui")
	await _capture("portrait-large-ui")
	settings.call("set_value", "ui/scale", 1.0)
	game.call("_queue_layout")
	for frame in 6:
		await process_frame
	game.call("_on_round_timer_timeout")
	for frame in 10:
		await process_frame
	await _capture("portrait-results")
	var panel := game.get_node("%RoundPanel") as Control
	print("Results: screen=", root.get_visible_rect(), " panel=", panel.get_global_rect(),
		" min=", panel.get_combined_minimum_size(),
		" center=", (game.get("_results_center") as Control).get_global_rect())
	_expect(panel.get_global_rect().end.x <= root.get_visible_rect().end.x + 1.0,
		"Portrait results must remain inside the screen.")
	game.call("_on_see_score_pressed")
	for frame in 12:
		await process_frame
	await _capture("portrait-scorecard")
	var preview := game.get_node("%ShareCardPreview") as TextureRect
	if not _capture_dir.is_empty() and preview.texture != null:
		var card := preview.texture.get_image()
		_expect(card.save_png(_capture_dir.path_join("share-card.png")) == OK,
			"The full-resolution share card must save for inspection.")
	var score_panel := game.get_node("%ScorePanel") as Control
	_expect(score_panel.get_global_rect().end.x <= root.get_visible_rect().end.x + 1.0,
		"Portrait scorecards must stay within the scrollable screen.")
	game.queue_free()
	await process_frame
	values.clear()
	values.merge(original, true)
	settings.call("apply_controls")
	settings.call("_update_content_scale")
	timer.stop()
	timer.process_mode = timer_mode
	if _failures.is_empty():
		print("LaZer NFC full-scene layout tests passed.")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _check_layout(game: Node, name_text: String) -> void:
	var arena := game.get("_arena") as Control
	var deck := game.get("_deck") as Control
	var screen := root.get_visible_rect()
	print(name_text, ": screen=", screen, " arena=", arena.get_global_rect(),
		" deck=", deck.get_global_rect(), " hint=",
		(game.get_node("%Hint") as Control).get_global_rect())
	_expect(arena.size.x > 0 and arena.size.y > 100,
		"%s must leave meaningful height for the laboratory." % name_text)
	_expect(arena.get_global_rect().end.y <= deck.get_global_rect().position.y + 1,
		"%s must keep the native controls below the 3D viewport." % name_text)
	_expect(deck.get_global_rect().end.x <= screen.end.x + 1
		and deck.get_global_rect().end.y <= screen.end.y + 1,
		"%s control deck must stay inside the screen." % name_text)
	var hint_panel := game.get_node("%Hint").get_parent() as Control
	_expect(deck.get_global_rect().end.y < hint_panel.get_global_rect().position.y,
		"%s controls must not cover the shell's instruction hint." % name_text)
	var key_controls: Array = deck.get("_keys")
	for control: Control in key_controls:
		_expect(deck.get_global_rect().encloses(control.get_global_rect()),
			"%s colour buttons must fit their responsive deck." % name_text)
		var scale: float = control.get("ui_scale")
		if control.size.x < 116.0 * scale:
			var font := control.get_theme_font("font")
			var label_width := font.get_string_size(str(control.get("hue")).capitalize(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(14.0 * scale)).x
			_expect(label_width <= control.size.x - 12.0 * scale,
				"%s compact keys must show complete colour names." % name_text)


func _capture(name_text: String) -> void:
	if _capture_dir.is_empty():
		return
	if DirAccess.make_dir_recursive_absolute(_capture_dir) != OK:
		_expect(false, "Could not create the requested capture directory.")
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_expect(image != null and not image.is_empty(), "A captured frame must contain an image.")
	if image != null and not image.is_empty():
		_expect(image.save_png(_capture_dir.path_join(name_text + ".png")) == OK,
			"The requested screenshot must save.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
