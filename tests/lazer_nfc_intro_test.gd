extends SceneTree

## The inherited briefing teaches safe setup and keeps the normal menu handoff.

var _failures := PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var manifest := GameCatalog.get_manifest("lazer_nfc")
	_expect(manifest != null, "LaZer NFC must be registered.")
	if manifest == null:
		_finish()
		return
	_expect(manifest.intro_scene_path == "res://games/lazer_nfc/intro.tscn",
		"The standalone opening must use the normal manifest hook.")
	var packed := load(manifest.intro_scene_path) as PackedScene
	if packed == null:
		_expect(false, "The declared opening must load.")
		_finish()
		return
	var intro := packed.instantiate()
	root.add_child(intro)
	await process_frame
	var cards: Array = intro.get("cards")
	var words := " ".join(PackedStringArray(cards))
	_expect(cards.size() >= 4 and words.contains("15 cm") and words.contains("Keys or touch"),
		"The briefing explains accessible fallback and safe tag spacing.")
	_expect(str(intro.get("next_scene")) == "res://scenes/menus/main_menu.tscn",
		"The opening must lead to the main menu, not bypass it into gameplay.")
	_expect(intro.has_method("_on_skip_pressed") and intro.get_node_or_null("%SkipButton") != null,
		"The briefing keeps an explicit skip button.")
	var router := root.get_node("Router")
	var busy := bool(router.get("_busy"))
	router.set("_busy", true)
	intro.call("_on_skip_pressed")
	intro.call("_on_skip_pressed")
	_expect(bool(intro.get("_finished")), "Skip settles the opening idempotently.")
	router.set("_busy", busy)
	intro.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("LaZer NFC intro tests passed.")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)
