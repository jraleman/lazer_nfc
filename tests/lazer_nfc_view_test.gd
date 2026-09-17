extends SceneTree

## Focused presentation coverage: no match, Settings changes, audio or save writes.
## Use a graphics window; --lazer-capture-dir=<absolute directory> saves actual frames.
## A headless invocation checks only inert structure and reports that distinction.

const Palette = preload("res://games/lazer_nfc/run/palette.gd")
const Glyph = preload("res://games/lazer_nfc/ui/shape_glyph.gd")
const ARENA_PATH := "res://games/lazer_nfc/arena/arena.tscn"
const UI_PATH := "res://games/lazer_nfc/ui/"

var _failures := PackedStringArray()
var _capture_dir := ""
var _arena: Control
var _viewport: SubViewport
var _camera: Camera3D
var _checks := 0
var _rendered_phases := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lazer-capture-dir="):
			_capture_dir = argument.trim_prefix("--lazer-capture-dir=")
	if not _capture_dir.is_empty():
		var error := DirAccess.make_dir_recursive_absolute(_capture_dir)
		if error != OK:
			push_error("Cannot create LaZer capture directory: %s" % error)
			quit(1)
			return
	Engine.max_fps = 60
	# This fixture owns pixel dimensions; the full-scene test covers Settings scaling.
	var auto_scale := Callable(get_root().get_node("Settings"), "_update_content_scale")
	if get_root().size_changed.is_connected(auto_scale):
		get_root().size_changed.disconnect(auto_scale)
	get_root().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_root().content_scale_size = Vector2i.ZERO
	get_root().content_scale_factor = 1.0
	var scene := load(ARENA_PATH) as PackedScene
	if scene == null:
		push_error("The shipped LaZer arena must compile and instantiate.")
		quit(1)
		return
	_arena = scene.instantiate() as Control
	if not _arena.has_method("diagnostics"):
		push_error("The LaZer arena script must compile, not just its scene resource.")
		_arena.free()
		quit(1)
		return
	get_root().add_child(_arena)
	_viewport = _arena.get_node("%LabViewport") as SubViewport
	_camera = _arena.get_node("%LabCamera") as Camera3D
	_resize(Vector2i(1280, 720))
	await process_frame
	_check_structure()
	_check_glyphs()
	_expect(await _check_ready_previews(), "READY preview coverage must complete.")
	if DisplayServer.get_name() == "headless":
		await _check_inert()
		_finish("headless structure only; no graphics coverage")
		return
	await _check_rendered_states()
	await _check_accessibility_and_pause()
	await _check_sizes()
	await _check_menu_and_share()
	_expect(_rendered_phases == 4, "All four rendering phases must reach their final assertion.")
	_arena.queue_free()
	await process_frame
	_finish("actual gl_compatibility rendering")


func _check_structure() -> void:
	var container := _arena.get_node("%LabViewportContainer") as SubViewportContainer
	_expect(container.stretch, "The embedding container must own stretch sizing.")
	_expect(_viewport.transparent_bg and _viewport.own_world_3d and _viewport.gui_disable_input,
		"The diorama must be a transparent, isolated, noninteractive world.")
	_expect(_arena.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and container.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"The arena must not intercept the shell or key/touch deck.")
	for control: Node in _arena.find_children("*", "Control", true, false):
		_expect((control as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"Every view-owned Control must ignore pointer input: %s" % control.name)
	for kind: String in ["GPUParticles3D", "CPUParticles3D", "AnimationPlayer", "Timer"]:
		_expect(_arena.find_children("*", kind, true, false).is_empty(),
			"No implicit-clock %s may run behind a paused parent." % kind)
	for kind: String in ["AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D"]:
		_expect(_arena.find_children("*", kind, true, false).is_empty(),
			"The read-only lab must not own %s sound playback." % kind)
	_expect(_camera.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"The toy-lab camera must retain its stable miniature perspective.")


func _check_glyphs() -> void:
	var signatures: Array[String] = []
	for hue: StringName in Palette.HUES:
		var polygon := Glyph.polygon(hue, Vector2.ZERO, 1.0)
		_expect(polygon.size() >= 3 and not Geometry2D.triangulate_polygon(polygon).is_empty(),
			"Every shape must be a real triangulatable silhouette: %s" % hue)
		_expect(polygon.size() == [3, 4, 10, 32, 4, 6, 12][Palette.HUES.find(hue)],
			"The canonical outline must retain its vertex count, including six for Indigo.")
		_expect(Palette.symbol(hue).to_lower() == [
			&"triangle", &"diamond", &"star", &"circle", &"square", &"hexagon", &"plus",
		][Palette.HUES.find(hue)], "Shape metadata and drawn geometry must agree.")
		var signature := str(polygon)
		_expect(not signatures.has(signature), "Hue glyphs must be distinct without colour.")
		signatures.append(signature)
		for shade in 3:
			var id := Palette.id_for(hue, shade)
			_expect(Glyph.polygon(id, Vector2.ZERO, 1.0) == polygon,
				"Shades must keep the hue's shape rather than become another instrument.")
	_expect(Glyph.polygon(&"", Vector2.ZERO, 1).is_empty()
		and Glyph.polygon(&"not_a_colour", Vector2.ZERO, 1).is_empty(),
		"Unknown identities must not be silently drawn as a real answer.")


func _check_ready_previews() -> bool:
	var ready := {
		"state": &"READY", "visible_color": &"", "active_palette": Palette.all_ids(),
	}
	_arena.call("reset")
	var readout := _arena.get_node("%Readout") as Control
	var badge := readout.get("badge") as Control
	var hero := _arena.get("_hero") as Node3D
	_arena.call("react", {"type": &"note", "color_id": &"red_dark", "index": 0})
	_arena.call("present", ready)
	_arena.call("advance", 60.0)
	_arena.call("present", ready)
	_expect((_arena.call("diagnostics") as Dictionary)["revealed_color"] == &"red_dark",
		"A READY snapshot with no visible note must preserve its preview beyond the old timeout.")
	_expect(badge.visible and badge.get("color_id") == &"red_dark"
		and not bool(badge.get("neutral")) and (hero.get("_badge") as MeshInstance3D).visible,
		"Both the native icon/shade pips and the robot's shape stamp must stay visible in READY.")
	_arena.call("react", {"type": &"note_end", "color_id": &"red_dark", "index": 0})
	_expect((_arena.call("diagnostics") as Dictionary)["revealed_color"] == &"red_dark",
		"Ending a preview's sound must not erase its setup identity.")
	_arena.call("configure_accessibility", true, false)
	_arena.call("advance", 60.0)
	_expect(badge.get("color_id") == &"red_dark",
		"Live accessibility changes must preserve READY's informational colour and icon.")

	_arena.call("react", {"type": &"note", "color_id": &"blue_light", "index": 0})
	_arena.call("advance", 60.0)
	_expect((_arena.call("diagnostics") as Dictionary)["revealed_color"] == &"blue_light"
		and badge.get("color_id") == &"blue_light",
		"A tag roll-call preview must replace the previous one without requiring present().")
	if DisplayServer.get_name() != "headless":
		await _render()
		_check_native_colour(&"blue_light")
		_capture("00-ready-latched-preview.png")
	_arena.call("reset")
	_expect((_arena.call("diagnostics") as Dictionary)["revealed_color"] == &""
		and not badge.visible and StringName(_arena.get("_practice_color")).is_empty(),
		"Reset must clear the latched preview rather than revive it on the next READY snapshot.")

	for phase: StringName in [
		&"ROUND_START", &"SHOWING", &"SHOW_END", &"AWAITING",
		&"RECALL_GAP", &"ROUND_WON", &"RUN_OVER",
	]:
		_arena.call("reset")
		_arena.call("react", {"type": &"note", "color_id": &"indigo", "index": 0})
		_arena.call("present", _snapshot(phase))
		_expect((_arena.call("diagnostics") as Dictionary)["revealed_color"] == &""
			and StringName(_arena.get("_practice_color")).is_empty(),
			"Leaving READY must discard its preview, especially before recall: %s" % phase)
		_arena.call("present", ready)
		_expect(not badge.visible,
			"Returning to READY without a new preview must not resurrect a previous colour.")
	for type: StringName in [&"round_started", &"go", &"awaiting", &"run_over"]:
		_arena.call("reset")
		_arena.call("react", {"type": &"note", "color_id": &"orange", "index": 0})
		_arena.call("react", {"type": type})
		_expect((_arena.call("diagnostics") as Dictionary)["revealed_color"] == &""
			and StringName(_arena.get("_practice_color")).is_empty(),
			"A start/recall/end event must clear setup even before the next snapshot: %s" % type)
	_arena.call("present", _snapshot(&"AWAITING"))
	_arena.call("react", {"type": &"note", "color_id": &"violet", "index": 0})
	_expect((_arena.call("diagnostics") as Dictionary)["revealed_color"] == &""
		and StringName(_arena.get("_practice_color")).is_empty(),
		"An out-of-phase note event must never expose or retain a recall identity.")
	_arena.call("reset")
	_arena.call("configure_accessibility", false, true)
	return true


func _check_inert() -> void:
	_arena.call("present", _snapshot(&"AWAITING", &"red", 12))
	_arena.call("react", {"type": &"hit", "color_id": &"blue", "index": 0, "points": 100})
	_arena.call("advance", 0.1)
	var info: Dictionary = _arena.call("diagnostics")
	var particles: Dictionary = info["particles"]
	_expect(info["inert"] and int(particles["capacity"]) == 0 and int(particles["active"]) == 0,
		"Headless must allocate neither a particle pool nor active effects.")
	_expect(not bool(info["beam"]) and is_zero_approx(float(info["clock"])),
		"Headless must not animate decorative geometry or firing effects.")
	_expect(_arena.get_node("%Laboratory").get_child_count() >= 8,
		"Headless must still expose the world, props, bots and layout nodes.")
	_check_no_answer_leak()
	for dimensions: Vector2i in [Vector2i(420, 720), Vector2i(1920, 480)]:
		_resize(dimensions)
		await process_frame
		_check_layout()
	_arena.queue_free()
	await process_frame


func _check_rendered_states() -> void:
	_arena.call("reset")
	await _render()
	_capture("01-ready.png")
	_check_bright_diorama()
	_check_budget("ready")
	var input := _snapshot(&"SHOWING", &"red", 6, 2)
	input["sequence"] = [&"violet", &"orange", &"green", &"indigo"]
	var before := input.duplicate(true)
	_arena.call("present", input)
	await _render()
	_expect(input == before, "present() must never mutate its caller's snapshot.")
	var retained: Dictionary = _arena.get("_snapshot")
	_expect(not retained.has("sequence"), "The view must not even cache private extra keys.")
	_check_native_colour(&"red")
	_capture("02-showing-red.png")
	for id: StringName in Palette.all_ids(true):
		_arena.call("present", _snapshot(&"SHOWING", id, 6, 2))
		await _render()
		_check_native_colour(id)
		if id == &"indigo_dark":
			_capture("03-showing-dark-indigo.png")
	_check_no_answer_leak()
	await _render()
	_capture("04-neutral-recall.png")

	var window := _snapshot(&"AWAITING", &"", 6, 2)
	window["window_ratio"] = 1.0
	_arena.call("present", window)
	await _render()
	var full := _window_ink_pixels()
	window["window_ratio"] = 0.19
	_arena.call("present", window)
	await _render()
	var short := _window_ink_pixels()
	_expect(full - short > 400,
		"The actual native response bar must visibly shrink with window_ratio.")
	_capture("05-shrinking-window.png")

	_arena.call("react", {
		"type": &"hit", "color_id": &"yellow", "index": 2, "points": 150, "combo": 8,
	})
	_arena.call("present", _snapshot(&"RECALL_GAP", &"violet", 6, 3))
	_arena.call("advance", 0.06)
	await _render()
	var info: Dictionary = _arena.call("diagnostics")
	_expect(info["revealed_color"] == &"yellow",
		"A resolved hit must reveal exactly that hit, never a next snapshot colour.")
	_expect(bool(info["beam"]) and int(info["particles"]["active"]) > 0,
		"An ordinary hit must show the real beam and pooled harmless pop.")
	var beam := _arena.get("_beam_rim") as MeshInstance3D
	var lab := _arena.get("_lab") as Node3D
	var muzzle := lab.get("muzzle") as Marker3D
	var beam_start := beam.global_transform * Vector3(0, -0.5, 0)
	var beam_end := beam.global_transform * Vector3(0, 0.5, 0)
	var hero := _arena.get("_hero") as Node3D
	_expect(beam_start.distance_to(muzzle.global_position) < 0.01,
		"The actual rotated beam must start at the barrel, not stretch on a world axis.")
	_expect(beam_end.distance_to(hero.global_position + Vector3(-0.18, 0.90, 0.21)) < 0.01,
		"The beam's other endpoint must reach the resolved target.")
	_expect(await _particle_pixels() > 30,
		"Hit sprinkles must actually render in front of the bot, not inside its housing.")
	_check_budget("hit and sprinkles")
	_capture("06-beam-and-pop.png")
	_arena.call("react", {"type": &"awaiting", "index": 3})
	_arena.call("present", _snapshot(&"AWAITING", &"yellow", 6, 3))
	_expect((_arena.call("diagnostics") as Dictionary)["revealed_color"] == &"",
		"The next recall target must close the previous hit's colour shutter.")
	_arena.call("react", {"type": &"round_won", "perfect": true, "points": 600})
	_arena.call("present", _snapshot(&"ROUND_WON", &"", 6, 5))
	_arena.call("advance", 0.18)
	await _render()
	_expect(await _particle_pixels() > 70,
		"A clean sweep must have a visibly airborne confetti fan, not only a live counter.")
	_capture("07-clean-sweep.png")
	_check_budget("clean sweep")
	_rendered_phases += 1


func _check_no_answer_leak() -> void:
	for phase: StringName in [&"ROUND_START", &"SHOW_END", &"AWAITING", &"RUN_OVER"]:
		var data := _snapshot(phase, &"violet_light", 12, 3)
		data["sequence"] = [&"red", &"green", &"violet_light"]
		_arena.call("present", data)
		var info: Dictionary = _arena.call("diagnostics")
		_expect(info["revealed_color"] == &"",
			"Only SHOWING or a resolved target may reveal an identity: %s" % phase)
		for id: StringName in info["future_colors"]:
			_expect(id.is_empty(), "A prospective bot must never receive a colour id.")
		var queue: Array = _arena.get("_queue")
		for robot: Node3D in queue:
			_expect(not (robot.get("_badge") as MeshInstance3D).visible,
				"Future shape meshes must be actually hidden, not only colour-neutral.")
	_arena.call("present", _snapshot(&"AWAITING", &"red", 6, 2))
	for type: StringName in [&"wrong", &"unknown", &"not_yet", &"timeout"]:
		_arena.call("react", {"type": type, "color_id": &"orange", "index": 2})
		_expect((_arena.call("diagnostics") as Dictionary)["revealed_color"] == &"",
			"Wrong/unknown/early/expired inputs cannot identify the current robot: %s" % type)
	var hero := _arena.get("_hero") as Node3D
	var material := hero.get("_paint") as StandardMaterial3D
	_expect(material.albedo_color.is_equal_approx(Color("b4c3c7")),
		"The actual recall robot housing must be neutral grey.")
	var readout := _arena.get_node("%Readout") as Control
	var badge := readout.get("badge") as Control
	_expect(badge.get("neutral") and StringName(badge.get("color_id")).is_empty(),
		"The native overlay must also conceal colour, shape and shade pips.")


func _check_accessibility_and_pause() -> void:
	_arena.call("configure_accessibility", false, true)
	_arena.call("present", _snapshot(&"RECALL_GAP", &"", 12, 2))
	_arena.call("react", {"type": &"hit", "color_id": &"green", "points": 100, "index": 1})
	_arena.call("advance", 0.07)
	await _render()
	var frozen_clock: float = (_arena.call("diagnostics") as Dictionary)["clock"]
	var frozen := get_root().get_texture().get_image().get_data()
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	_expect(get_root().get_texture().get_image().get_data() == frozen,
		"Without advance(), actual bot/beam/particles/camera pixels must all freeze.")
	_expect(is_equal_approx(float((_arena.call("diagnostics") as Dictionary)["clock"]), frozen_clock),
		"Idle SceneTree frames must never advance the arena's cosmetic clock.")
	var child_count := _arena.find_children("*", "", true, false).size()
	for hit in 80:
		_arena.call("react", {
			"type": &"hit", "color_id": Palette.HUES[hit % 7], "points": 100, "index": 1,
		})
		_arena.call("advance", 0.015)
	var particles: Dictionary = (_arena.call("diagnostics") as Dictionary)["particles"]
	_expect(int(particles["capacity"]) == 56 and int(particles["active"]) <= 56,
		"An arbitrarily fast combo must stay inside one fixed particle pool.")
	_expect(_arena.find_children("*", "", true, false).size() == child_count,
		"Hits must not allocate scene nodes or new emitters.")

	_arena.call("configure_accessibility", true, true)
	_arena.call("present", _snapshot(&"SHOWING", &"blue_light", 12, 3))
	await _render()
	_check_native_colour(&"blue_light")
	var hero := _arena.get("_hero") as Node3D
	var pose: Array = hero.call("pose_transforms")
	var parked := _camera.transform
	frozen_clock = float((_arena.call("diagnostics") as Dictionary)["clock"])
	_arena.call("advance", 2.0)
	await _render()
	var info: Dictionary = _arena.call("diagnostics")
	_expect(int(info["particles"]["active"]) == 0 and not bool(info["particles"]["enabled"]),
		"Reduced motion immediately clears and disables sprinkles.")
	_expect(hero.call("pose_transforms") == pose and _camera.transform.is_equal_approx(parked),
		"Reduced motion fixes both ambient robot poses and the framing camera.")
	_expect(is_equal_approx(float(info["clock"]), frozen_clock),
		"Reduced motion must also fix the reactor's ambient clock.")
	_capture("08-reduced-motion.png")

	_arena.call("configure_accessibility", false, false)
	_arena.call("present", _snapshot(&"AWAITING", &"", 6, 2))
	parked = _camera.transform
	_arena.call("react", {"type": &"wrong", "color_id": &"red"})
	_arena.call("advance", 0.05)
	info = _arena.call("diagnostics")
	_expect(is_zero_approx(float(info["flash"])) and is_zero_approx(float(info["shake"]))
		and _camera.transform.is_equal_approx(parked),
		"Intense effects off independently disables flash and camera shake.")
	_expect(float(info["clock"]) > frozen_clock,
		"Disabling intense effects must not silently enable reduced motion.")
	_arena.call("react", {"type": &"hit", "color_id": &"yellow", "index": 2, "points": 100})
	_arena.call("present", _snapshot(&"RECALL_GAP", &"", 6, 3))
	_arena.call("advance", 0.05)
	info = _arena.call("diagnostics")
	_expect(info["revealed_color"] == &"yellow"
		and is_zero_approx(float(info["flash"])) and is_zero_approx(float(info["shake"])),
		"A low-intensity hit keeps its information without flashes or shake.")
	_arena.call("reset")
	info = _arena.call("diagnostics")
	_expect(info["revealed_color"] == &"" and int(info["particles"]["active"]) == 0
		and not bool(info["beam"]) and float(info["clock"]) == 0.0,
		"Replay must discard all prior identities, clocks and transient effects.")
	_rendered_phases += 1


func _check_sizes() -> void:
	_arena.call("configure_accessibility", true, false)
	for dimensions: Vector2i in [
		Vector2i(420, 720), Vector2i(360, 360), Vector2i(800, 240), Vector2i(1920, 480),
	]:
		_resize(dimensions)
		_arena.call("present", _snapshot(&"SHOWING", &"orange_light", 12, 10))
		await _render()
		_check_layout()
		_check_native_colour(&"orange_light")
		_capture("09-layout-%dx%d.png" % [dimensions.x, dimensions.y])
	_resize(Vector2i(480, 180))
	_arena.call("reset")
	_arena.call("react", {"type": &"note", "color_id": &"blue_light", "index": 0})
	await _render()
	_check_layout()
	var short_layout: Dictionary = _arena.call("diagnostics")
	_expect((short_layout["stage_rect"] as Rect2).size.y > 100.0,
		"A short READY view prioritizes the toy lab over redundant start instructions.")
	_check_native_colour(&"blue_light")
	_resize(Vector2i(1280, 720))
	await _render()
	_rendered_phases += 1


func _check_layout() -> void:
	var info: Dictionary = _arena.call("diagnostics")
	var bounds := Rect2(Vector2.ZERO, _arena.size)
	var stage: Rect2 = info["stage_rect"]
	_expect(bounds.encloses(stage), "The 3D stage must stay inside the parent-owned rectangle.")
	_expect(Vector2(info["viewport_size"]).distance_to(stage.size) < 2.0,
		"Container stretch, not a competing viewport size assignment, must size the render.")
	for rect: Rect2 in info["native_rects"]:
		_expect(bounds.encloses(rect), "Every icon and native readout must remain in its safe rect.")
	var safe := Rect2(Vector2.ZERO, Vector2(_viewport.size)).grow(-1.0)
	for point: Vector3 in _arena.call("framing_points"):
		_expect(safe.has_point(_camera.unproject_position(point)),
			"The real camera must retain bench, signs, reactor and robot silhouettes at %s."
			% _arena.size)


func _check_native_colour(id: StringName) -> void:
	var readout := _arena.get_node("%Readout") as Control
	var badge := readout.get("badge") as Control
	var at := badge.get_global_rect().get_center() - Vector2(0, 2)
	var image := get_root().get_texture().get_image()
	var pixel := image.get_pixelv(Vector2i(at))
	_expect(_colour_distance(pixel, Palette.color(id)) < 0.055,
		"The rendered native glyph must retain the exact readable shade: %s (%s)." % [id, pixel])


func _window_ink_pixels() -> int:
	var image := get_root().get_texture().get_image()
	var count := 0
	for y in range(image.get_height() - 61, image.get_height()):
		for x in range(image.get_width()):
			if _colour_distance(image.get_pixel(x, y), Color("9ce6cf")) < 0.018:
				count += 1
	return count


func _check_bright_diorama() -> void:
	var image := _viewport.get_texture().get_image()
	var bright := 0
	var colourful := 0
	var opaque := 0
	var clipped := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var pixel := image.get_pixel(x, y)
			if pixel.a < 0.8:
				continue
			opaque += 1
			if pixel.get_luminance() > 0.48:
				bright += 1
			if pixel.s > 0.22 and pixel.v > 0.40:
				colourful += 1
			if minf(pixel.r, minf(pixel.g, pixel.b)) > 0.995:
				clipped += 1
	_expect(bright > 500 and colourful > 500,
		"The actual viewport must render a bright colourful miniature, not grey on black.")
	_expect(float(clipped) / maxf(float(opaque), 1.0) < 0.02,
		"Warm key and cool fill must retain the pastel paint, not clip it to white.")
	print("LaZer paint: %d bright / %d colourful / %d clipped of %d opaque samples." % [
		bright, colourful, clipped, opaque])


func _check_budget(label: String) -> void:
	var visible := _viewport.get_render_info(
		Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var shadows := _viewport.get_render_info(
		Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	print("LaZer %s draw calls: %d visible + %d shadow = %d" % [
		label, visible, shadows, visible + shadows])
	_expect(visible > 0 and visible + shadows <= 60,
		"The detailed lab must stay within sixty 3D draw calls, including shadows.")
	for instance: Node in _arena.find_children("*", "MeshInstance3D", true, false):
		var mesh := (instance as MeshInstance3D).mesh
		_expect(mesh == null or mesh.get_surface_count() == 1,
			"Toy details must remain batched in one surface per rigid part.")


func _particle_pixels() -> int:
	var sparks := _arena.get("_sparks") as Node3D
	var pool := sparks.get("_view") as MultiMeshInstance3D
	var with_sprinkles := _viewport.get_texture().get_image()
	pool.hide()
	await _render()
	var without_sprinkles := _viewport.get_texture().get_image()
	var changed := 0
	for y in range(0, with_sprinkles.get_height(), 2):
		for x in range(0, with_sprinkles.get_width(), 2):
			var before := with_sprinkles.get_pixel(x, y)
			var after := without_sprinkles.get_pixel(x, y)
			if _colour_distance(before, after) > 0.06 or absf(before.a - after.a) > 0.1:
				changed += 1
	pool.show()
	await _render()
	print("LaZer airborne sprinkle samples: %d" % changed)
	return changed


func _check_menu_and_share() -> void:
	_arena.hide()
	var material := load(UI_PATH + "menu_background.tres") as ShaderMaterial
	var skin := load(UI_PATH + "menu_skin.tres") as Theme
	var plaque := load(UI_PATH + "menu_plaque.tres") as StandardMaterial3D
	_expect(material != null and skin != null and plaque != null,
		"All three GameTheme presentation resources must load.")
	if material == null or skin == null or plaque == null:
		_arena.show()
		return
	var uniforms: Array[StringName] = []
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		uniforms.append(StringName(uniform["name"]))
	for key: StringName in [&"top_color", &"bottom_color", &"glow_color", &"aspect", &"speed"]:
		_expect(uniforms.has(key), "The menu shader must implement GameTheme's %s uniform." % key)
	_expect(plaque.albedo_texture != null and plaque.roughness >= 0.7,
		"The logo plaque must wear its original matte enamel texture.")
	_expect(skin.has_stylebox("focus", "Button"), "The menu skin must preserve keyboard focus.")
	var backdrop := ColorRect.new()
	backdrop.size = _arena.size
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.material = material.duplicate(true)
	var local_material := backdrop.material as ShaderMaterial
	local_material.set_shader_parameter("speed", 0.0)
	local_material.set_shader_parameter("aspect", Vector2(1280.0 / 720.0, 1.0))
	get_root().add_child(backdrop)
	await _render()
	var still := get_root().get_texture().get_image()
	var peak := 0.0
	for y in range(0, still.get_height(), 12):
		for x in range(0, still.get_width(), 12):
			peak = maxf(peak, still.get_pixel(x, y).srgb_to_linear().get_luminance())
	_expect(peak < 0.12, "The actual lab backdrop must retain cream-label contrast.")
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	_expect(get_root().get_texture().get_image().get_data() == still.get_data(),
		"The GameTheme speed=0 contract must freeze actual menu pixels.")
	_capture("10-menu-backdrop.png")
	var logo := TextureRect.new()
	logo.texture = load("res://games/lazer_nfc/assets/visual/logo.svg") as Texture2D
	logo.position = Vector2(260, 65)
	logo.size = Vector2(760, 490)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_root().add_child(logo)
	await _render()
	_expect(logo.texture != null and logo.texture.get_width() == 1024,
		"The original vector wordmark and mascot must import without font dependencies.")
	_capture("11-original-logo.png")
	logo.queue_free()
	backdrop.queue_free()
	await process_frame

	var share_scene := load(UI_PATH + "share_art.tscn") as PackedScene
	_expect(share_scene != null, "The shared scorecard's art scene must load.")
	if share_scene != null:
		var art := share_scene.instantiate() as Control
		var payload := {"score": 8250, "round": 8, "extra": {"retain": true}}
		var original := payload.duplicate(true)
		art.call("configure", payload)
		get_root().add_child(art)
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await _render()
		_expect(payload == original, "Share art must leave scorecard data untouched.")
		_expect(art.find_children("*", "SubViewport", true, false).is_empty(),
			"Sharing must reuse the poster, not start another 3D world.")
		_capture("12-original-poster-share.png")
		art.queue_free()
		await process_frame
	_arena.show()
	_rendered_phases += 1


func _snapshot(state: StringName, colour: StringName = &"", length := 6, index := 0) -> Dictionary:
	return {
		"state": state, "round": 5, "length": length, "recall_index": index,
		"show_index": index, "visible_color": colour, "active_palette": Palette.all_ids(),
		"window_ratio": 0.73, "lives": 3, "combo": 7, "multiplier": 2,
		"score": 3250, "best_combo": 9, "rounds_cleared": 4, "shade_mode": true,
	}


func _resize(dimensions: Vector2i) -> void:
	get_root().size = dimensions
	_arena.position = Vector2.ZERO
	_arena.size = Vector2(dimensions)


func _render() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw


func _capture(file_name: String) -> void:
	if _capture_dir.is_empty():
		return
	var error := get_root().get_texture().get_image().save_png(_capture_dir.path_join(file_name))
	_expect(error == OK, "The requested frame must save successfully: %s" % file_name)


func _colour_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish(scope: String) -> void:
	if _failures.is_empty():
		print("LaZer presentation: %d assertions passed (%s)." % [_checks, scope])
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)
