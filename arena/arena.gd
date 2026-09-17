extends Control

## Read-only LaZer toy laboratory, mounted and sized by the shared shell's playfield.
## All clocks are explicit: the parent simply stops advance() on pause or results.

const Palette = preload("res://games/lazer_nfc/run/palette.gd")
const LabSet = preload("res://games/lazer_nfc/arena/lab_set.gd")
const MemoryBot = preload("res://games/lazer_nfc/arena/memory_bot.gd")
const LabSparks = preload("res://games/lazer_nfc/arena/lab_sparks.gd")
const MeshBuilder = preload("res://games/lazer_nfc/arena/lab_mesh.gd")
const Readout = preload("res://games/lazer_nfc/ui/lab_readout.gd")
const STATES: Array[StringName] = [
	&"READY", &"ROUND_START", &"SHOWING", &"SHOW_END", &"AWAITING",
	&"RECALL_GAP", &"ROUND_WON", &"RUN_OVER",
]
const HERO_AT := Vector3(1.30, 0.64, 0.49)

@onready var _container: SubViewportContainer = %LabViewportContainer
@onready var _viewport: SubViewport = %LabViewport
@onready var _world: Node3D = %Laboratory
@onready var _camera: Camera3D = %LabCamera
@onready var _key: DirectionalLight3D = %WarmKey
@onready var _impact: Control = %ImpactInk
@onready var _readout: Readout = %Readout

var inert := false
var reduced_motion := false
var intense_effects := true
var _lab: LabSet
var _hero: MemoryBot
var _queue: Array[MemoryBot] = []
var _sparks: LabSparks
var _beam: Node3D
var _beam_rim: MeshInstance3D
var _beam_core: MeshInstance3D
var _beam_material: StandardMaterial3D
var _camera_home := Transform3D.IDENTITY
var _stage_rect := Rect2()
var _snapshot: Dictionary = {
	"state": &"READY", "round": 0, "length": 0, "show_index": -1,
	"recall_index": 0, "visible_color": &"", "active_palette": [],
	"window_ratio": 0.0, "combo": 0, "multiplier": 1,
}
var _clock := 0.0
var _reaction_left := 0.0
var _reaction_duration := 0.5
var _reaction_kind: StringName = &"neutral"
var _beam_left := 0.0
var _flash_left := 0.0
var _shake := 0.0
var _message := ""
var _message_left := 0.0
var _perfect := false
var _resolved_color: StringName = &""
var _resolved_index := -1
var _practice_color: StringName = &""
var _frame_color := Color("21424e")
var _back_panel: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	inert = DisplayServer.get_name() == "headless"
	_back_panel = StyleBoxFlat.new()
	_back_panel.bg_color = _frame_color
	_back_panel.border_color = Color("578087")
	_back_panel.set_border_width_all(1)
	_back_panel.set_corner_radius_all(22)
	if inert:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_viewport.msaa_3d = Viewport.MSAA_DISABLED
		_key.shadow_enabled = false
	_build_lab()
	_impact.draw.connect(_draw_impact)
	resized.connect(_layout)
	_viewport.size_changed.connect(_frame_camera)
	configure_accessibility(reduced_motion, intense_effects)
	_layout()
	_sync_view()


## Live toggles are independent: less motion removes bounces/particles, less intensity
## removes the tiny impact flash and camera kick while preserving colour and progress.
func configure_accessibility(reduced_motion_value: bool, intense_effects_value: bool) -> void:
	reduced_motion = reduced_motion_value
	intense_effects = intense_effects_value
	if not is_node_ready():
		return
	_sparks.set_enabled(not reduced_motion and not inert)
	if reduced_motion:
		_reaction_left = 0.0
	if reduced_motion or not intense_effects:
		_flash_left = 0.0
		_shake = 0.0
		_camera.transform = _camera_home
	_sync_view()


## Only public scalar fields and the one visible note cross into this presentation.
## In particular, extra dictionary keys are not copied, cached or inspected.
func present(snapshot: Dictionary) -> void:
	var state := StringName(snapshot.get("state", &"READY"))
	if not STATES.has(state):
		push_error("LaZer arena received an unknown presentation state: %s" % state)
		return
	if state != &"READY":
		_practice_color = &""
	var previous := StringName(_snapshot.get("state", &"READY"))
	var visible: StringName = &""
	if state == &"SHOWING":
		var candidate := StringName(snapshot.get("visible_color", &""))
		if Palette.is_valid(candidate):
			visible = candidate
	var active: Array[StringName] = []
	for id: StringName in snapshot.get("active_palette", []):
		if Palette.is_valid(id):
			active.append(id)
	_snapshot = {
		"state": state,
		"round": maxi(int(snapshot.get("round", 0)), 0),
		"length": clampi(int(snapshot.get("length", 0)), 0, 12),
		"recall_index": maxi(int(snapshot.get("recall_index", 0)), 0),
		"show_index": int(snapshot.get("show_index", -1)),
		"visible_color": visible,
		"active_palette": active,
		"window_ratio": clampf(float(snapshot.get("window_ratio", 0.0)), 0.0, 1.0),
		"combo": maxi(int(snapshot.get("combo", 0)), 0),
		"multiplier": maxi(int(snapshot.get("multiplier", 1)), 1),
	}
	if state != previous:
		if state == &"AWAITING" or state == &"ROUND_START" or state == &"SHOW_END":
			_resolved_color = &""
			_resolved_index = -1
	_sync_view()
	if state != previous and is_node_ready():
		_layout()


## READY previews latch until setup ends. In a run, only a resolved hit paints a target;
## wrong/early/unknown inputs never identify a hidden robot.
func react(event: Dictionary) -> void:
	var kind := StringName(event.get("type", &""))
	match kind:
		&"round_started":
			_clear_effects()
			_resolved_color = &""
			_resolved_index = -1
			_practice_color = &""
			_perfect = false
			_message = ""
			_message_left = 0.0
		&"note":
			var id := StringName(event.get("color_id", &""))
			if _snapshot.get("state", &"READY") == &"READY" and Palette.is_valid(id):
				_practice_color = id
		&"note_end":
			pass
		&"go", &"awaiting":
			_practice_color = &""
			_resolved_color = &""
			_resolved_index = -1
			_reaction_left = 0.0
		&"hit":
			var id := StringName(event.get("color_id", &""))
			if not Palette.is_valid(id):
				push_error("LaZer hit presentation needs a valid resolved colour.")
				return
			_resolved_color = id
			_resolved_index = int(event.get("index", -1))
			_react_pose(&"happy", 0.50)
			var combo := int(event.get("combo", 0))
			_message = "+%d  BRIGHT IDEA!" % int(event.get("points", 0))
			if combo >= 5:
				_message = "+%d  COMBO %d!" % [int(event.get("points", 0)), combo]
			_message_left = 0.65
			if is_node_ready() and not inert:
				_fire_beam(Palette.color(id))
				_sparks.burst(HERO_AT + Vector3(-0.15, 1.35, 0.92), Palette.color(id),
					14 if intense_effects else 8)
		&"wrong":
			_react_pose(&"oops", 0.32)
			_message = "Same robot. Try another colour."
			_message_left = 0.85
		&"timeout":
			_resolved_color = &""
			_resolved_index = int(event.get("index", -1))
			_react_pose(&"oops", 0.32)
			_message = "That one got away. Keep going!"
			_message_left = 0.85
		&"round_won":
			_perfect = bool(event.get("perfect", false))
			_react_pose(&"happy", 1.1)
			_message = "CLEAN SWEEP!" if _perfect else "NICE RECALL!"
			_message_left = 1.55
			if is_node_ready() and not inert:
				_celebrate()
		&"run_over":
			_clear_effects()
			_resolved_color = &""
			_practice_color = &""
			_message = ""
			_message_left = 0.0
		&"not_yet":
			_message = "Watch first. Your turn is coming."
			_message_left = 0.8
		&"unknown":
			_message = "That colour is outside this experiment."
			_message_left = 0.8
		_:
			push_warning("LaZer arena ignored an unknown event type: %s" % kind)
	_sync_view()


## This is the only animation driver. No implicit engine-time effect runs behind pause.
func advance(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		push_error("LaZer arena.advance needs a finite, nonnegative delta.")
		return
	if not is_node_ready() or is_zero_approx(delta):
		return
	if not reduced_motion and not inert:
		_clock += delta
	_reaction_left = maxf(_reaction_left - delta, 0.0)
	_beam_left = maxf(_beam_left - delta, 0.0)
	_flash_left = maxf(_flash_left - delta, 0.0)
	_message_left = maxf(_message_left - delta, 0.0)
	_shake *= exp(-delta * 17.0)
	_sparks.advance(delta)
	_sync_view()


## A new experiment reuses its geometry and pools but not a previous answer or pose.
func reset() -> void:
	_clock = 0.0
	_clear_effects()
	_message = ""
	_message_left = 0.0
	_resolved_color = &""
	_resolved_index = -1
	_practice_color = &""
	_perfect = false
	if _sparks != null:
		_sparks.reset()
	present({"state": &"READY"})


## Stable observability for the focused view test and shell headless integration.
func diagnostics() -> Dictionary:
	var future: Array[StringName] = []
	for robot in _queue:
		future.append(robot.revealed_color)
	return {
		"inert": inert,
		"state": _snapshot.get("state", &"READY"),
		"revealed_color": &"" if _hero == null else _hero.revealed_color,
		"future_colors": future,
		"resolved_index": _resolved_index,
		"clock": _clock,
		"particles": {} if _sparks == null else _sparks.diagnostics(),
		"beam": _beam != null and _beam.visible,
		"flash": _flash_left,
		"shake": _shake,
		"stage_rect": _stage_rect,
		"native_rects": [] if _readout == null else _readout.native_rects(),
		"viewport_size": Vector2i.ZERO if _viewport == null else _viewport.size,
	}


## World-space silhouettes used by the real camera, also available to render coverage.
func framing_points() -> PackedVector3Array:
	return LabSet.framing_points()


func _build_lab() -> void:
	_lab = LabSet.new()
	_lab.name = "BatchedToyLab"
	_world.add_child(_lab)
	_lab.build(inert)
	_hero = MemoryBot.new()
	_hero.name = "CurrentMemoryBot"
	_hero.position = HERO_AT
	_hero.scale = Vector3.ONE * 1.28
	_hero.rotation.y = 0.10
	_world.add_child(_hero)
	_hero.build(inert)
	for index in 2:
		var robot := MemoryBot.new()
		robot.name = "UnassignedBot%d" % (index + 1)
		robot.position = Vector3(3.47, 0.64, 0.08) if index == 0 \
			else Vector3(4.34, 0.57, -1.34)
		robot.scale = Vector3.ONE * (0.64 if index == 0 else 0.49)
		robot.rotation.y = 0.10
		_world.add_child(robot)
		robot.build(inert)
		_queue.append(robot)
	_sparks = LabSparks.new()
	_sparks.name = "HarmlessPops"
	_world.add_child(_sparks)
	_sparks.build(inert)
	_beam = Node3D.new()
	_beam.name = "ToyBeam"
	_world.add_child(_beam)
	_beam.visible = false
	_beam_material = MeshBuilder.paint(true)
	_beam_rim = MeshInstance3D.new()
	_beam_rim.name = "ColourSleeve"
	_beam_rim.material_override = _beam_material
	_beam_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.add_child(_beam_rim)
	_beam_core = MeshInstance3D.new()
	_beam_core.name = "CreamFilament"
	var core := MeshBuilder.paint(true)
	core.albedo_color = Color("ffffe1")
	_beam_core.material_override = core
	_beam_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.add_child(_beam_core)
	if not inert:
		var beam_shape := CylinderMesh.new()
		beam_shape.top_radius = 1.0
		beam_shape.bottom_radius = 1.0
		beam_shape.height = 1.0
		beam_shape.radial_segments = 8
		_beam_rim.mesh = beam_shape
		_beam_core.mesh = beam_shape


func _sync_view() -> void:
	if not is_node_ready():
		return
	var state := StringName(_snapshot.get("state", &"READY"))
	var id: StringName = &""
	if state == &"SHOWING":
		id = StringName(_snapshot.get("visible_color", &""))
	elif state == &"RECALL_GAP" or state == &"ROUND_WON":
		id = _resolved_color
	elif state == &"READY":
		id = _practice_color
	if state == &"READY" and id.is_empty():
		_hero.welcome()
	else:
		_hero.set_note(id)
	var mood: StringName = _reaction_kind if _reaction_left > 0.0 else &"neutral"
	if state == &"ROUND_WON":
		mood = &"happy"
	elif state == &"RECALL_GAP" and not id.is_empty():
		mood = &"happy"
	var reaction := _reaction_left / maxf(_reaction_duration, 0.001)
	_hero.pose(_clock, reaction, mood, reduced_motion or inert)
	var remaining := int(_snapshot.get("length", 0)) \
		- int(_snapshot.get("recall_index", 0)) - 1
	for index in _queue.size():
		var robot := _queue[index]
		robot.visible = state == &"READY" or (remaining > index \
			and state != &"ROUND_WON" and state != &"RUN_OVER")
		robot.pose(_clock + index * 1.7, 0, &"neutral", reduced_motion or inert)
	_lab.pose(_clock, reduced_motion or inert)
	_beam.visible = _beam_left > 0.0 and not inert
	_camera.transform = _camera_home
	if intense_effects and not reduced_motion and not inert and _shake > 0.0001:
		_camera.position += _camera.basis.x * sin(_clock * 53.0) * _shake
		_camera.position += _camera.basis.y * cos(_clock * 47.0) * _shake * 0.55
	_readout.present(_snapshot, id, _message if _message_left > 0.0 else "", _perfect)
	_impact.queue_redraw()
	queue_redraw()


func _react_pose(kind: StringName, duration: float) -> void:
	_reaction_kind = kind
	_reaction_duration = duration
	_reaction_left = 0.0 if reduced_motion or inert else duration
	if intense_effects and not reduced_motion and not inert:
		_shake = 0.028 if kind == &"happy" else 0.018
		_flash_left = 0.13 if kind == &"happy" else 0.0


func _fire_beam(tint: Color) -> void:
	_beam_left = 0.18
	_beam_material.albedo_color = tint.lerp(Color("fff4cf"), 0.15)
	var start := _lab.muzzle.global_position
	var finish := _hero.global_position + Vector3(-0.18, 0.90, 0.21)
	var direction := finish - start
	var basis := Basis(Quaternion(Vector3.UP, direction.normalized()))
	var radius := 0.035 if reduced_motion or not intense_effects else 0.070
	_beam_rim.transform = Transform3D(basis * Basis.from_scale(
		Vector3(radius, direction.length(), radius)), (start + finish) * 0.5)
	_beam_core.transform = Transform3D(basis * Basis.from_scale(
		Vector3(radius * 0.36, direction.length() + 0.01, radius * 0.36)),
		(start + finish) * 0.5)
	_beam.visible = true


func _celebrate() -> void:
	var colors: Array[StringName] = []
	colors.assign(_snapshot.get("active_palette", []))
	if colors.is_empty():
		colors.assign(Palette.GROWTH_ORDER)
	for index in 4:
		var tint := Palette.color(colors[index % colors.size()])
		var at := HERO_AT + Vector3((index - 1.5) * 0.76, 2.80, 0.95)
		_sparks.burst(at, tint, 12 if _perfect else 8, true)


func _clear_effects() -> void:
	_reaction_left = 0.0
	_reaction_kind = &"neutral"
	_beam_left = 0.0
	_flash_left = 0.0
	_shake = 0.0
	if _sparks != null:
		_sparks.clear()
	if _beam != null:
		_beam.visible = false


func _layout() -> void:
	if not is_node_ready():
		return
	_readout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var top := _readout.top_height()
	var bottom := _readout.bottom_height()
	_stage_rect = Rect2(8, top + 2, maxf(size.x - 16, 1),
		maxf(size.y - top - bottom - 4, 1))
	_container.position = _stage_rect.position
	_container.size = _stage_rect.size
	# stretch owns the viewport size, including resize ordering and high-DPI scaling.
	_frame_camera()
	queue_redraw()


func _frame_camera() -> void:
	if not is_node_ready() or _stage_rect.size.x <= 0.0:
		return
	var aspect := _stage_rect.size.x / maxf(_stage_rect.size.y, 1.0)
	var direction := Vector3(5.7, 11.8, 18.0).normalized()
	_camera.position = Vector3(0, 1.0, 0) + direction * 29.0
	_camera.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	var inverse := _camera.global_transform.affine_inverse()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point in LabSet.framing_points():
		var local := inverse * point
		low = low.min(Vector2(local.x, local.y))
		high = high.max(Vector2(local.x, local.y))
	var center := (low + high) * 0.5
	_camera.position += _camera.basis.x * center.x + _camera.basis.y * center.y
	var span := high - low
	_camera.size = maxf(span.y, span.x / maxf(aspect, 0.01)) * 1.075
	_camera_home = _camera.transform


func _draw() -> void:
	if _back_panel == null or size.x <= 0.0 or size.y <= 0.0:
		return
	draw_style_box(_back_panel, Rect2(Vector2.ZERO, size))
	var center := _stage_rect.get_center()
	var spread := Vector2(minf(size.x * 0.43, _stage_rect.size.y * 0.93),
		_stage_rect.size.y * 0.39)
	var backdrop := PackedVector2Array()
	for point in 64:
		var angle := TAU * float(point) / 64.0
		backdrop.append(center + Vector2(cos(angle), sin(angle)) * spread)
	draw_colored_polygon(backdrop, Color(0.30, 0.56, 0.56, 0.21))
	for line in range(1, 8):
		var x := size.x * float(line) / 8.0
		draw_line(Vector2(x, _stage_rect.position.y + 8),
			Vector2(x, _stage_rect.end.y - 8), Color(0.70, 0.91, 0.83, 0.032), 1)


func _draw_impact() -> void:
	if _flash_left <= 0.0 or not intense_effects or reduced_motion or inert:
		return
	var point := _camera.unproject_position(_hero.global_position + Vector3(0, 1.12, 0))
	point += _stage_rect.position
	var alpha := _flash_left / 0.13
	_impact.draw_arc(point, 28 + (1.0 - alpha) * 14, 0, TAU, 32,
		Color(1.0, 0.94, 0.74, alpha * 0.45), 2.5, true)
