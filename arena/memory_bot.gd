extends Node3D

## Friendly rigid-part memory-bot. Its only identity is the public current/resolved note.
## Prospective bots are constructed without ids and cannot acquire a hidden answer.

const MeshBuilder = preload("res://games/lazer_nfc/arena/lab_mesh.gd")
const Palette = preload("res://games/lazer_nfc/run/palette.gd")
const Glyph = preload("res://games/lazer_nfc/ui/shape_glyph.gd")
const CREAM := Color("fff1d2")
const INK := Color("224653")
const GREY := Color("b4c3c7")
const JOINT := Color("7c999e")

static var _meshes: Dictionary = {}
static var _stamps: Dictionary = {}

var revealed_color: StringName = &""
var _inert := false
var _body: Node3D
var _shell: MeshInstance3D
var _face: MeshInstance3D
var _badge: MeshInstance3D
var _left_arm: MeshInstance3D
var _right_arm: MeshInstance3D
var _paint: StandardMaterial3D
var _mood: StringName = &"neutral"
var _welcoming := false


## Meshes are shared across all three robots and future rounds, not rebuilt on hits.
func build(inert: bool) -> void:
	_inert = inert
	if not inert and _meshes.is_empty():
		_meshes = _make_meshes()
	_body = Node3D.new()
	_body.name = "Pose"
	add_child(_body)
	_paint = MeshBuilder.paint()
	_shell = _part("Enamel", &"shell", _paint, true)
	_part("TrimAndFaceplate", &"trim", MeshBuilder.paint(), true)
	_face = _part("Expression", &"neutral", MeshBuilder.paint(true), false)
	_left_arm = _part("LeftMitten", &"left_arm", MeshBuilder.paint(), true)
	_left_arm.position = Vector3(-0.64, 1.05, 0)
	_right_arm = _part("RightMitten", &"right_arm", MeshBuilder.paint(), true)
	_right_arm.position = Vector3(0.64, 1.05, 0)
	_badge = _part("ShapeStamp", &"welcome", MeshBuilder.paint(true), false)
	_badge.visible = false
	set_note(&"")
	pose(0, 0, &"neutral", true)


## An empty id closes the badge shutter. Concealment never retains the previous hue.
func set_note(id: StringName) -> void:
	var next: StringName = id if Palette.is_valid(id) else &""
	if revealed_color == next and not _welcoming and _paint != null:
		_paint.albedo_color = GREY if next.is_empty() else Palette.color(next)
		return
	_welcoming = false
	revealed_color = next
	if _paint == null:
		return
	_paint.albedo_color = GREY if next.is_empty() else Palette.color(next)
	_badge.visible = not next.is_empty()
	if not next.is_empty() and not _inert:
		if not _stamps.has(next):
			_stamps[next] = _make_stamp(next)
		_badge.mesh = _stamps[next]


## A mint lab mascot belongs to setup, never to a prospective sequence position.
func welcome() -> void:
	revealed_color = &""
	_welcoming = true
	if _paint == null:
		return
	_paint.albedo_color = Color("89cdbb")
	_badge.visible = true
	if not _inert:
		_badge.mesh = _meshes[&"welcome"]


## Cosmetic squash, a crooked antenna and waving mittens; all settle in reduced motion.
func pose(clock: float, reaction: float, mood: StringName, reduced_motion: bool) -> void:
	if _body == null:
		return
	_set_expression(mood)
	var bounce := 0.0
	var lean := 0.0
	var squash := 0.0
	if not reduced_motion:
		bounce = sin(clock * 2.1 + 0.4) * 0.024
		lean = sin(clock * 1.35) * 0.026
		if mood == &"happy":
			bounce += sin(reaction * PI) * 0.28
			lean += sin(reaction * TAU) * 0.13
			squash = sin(reaction * TAU) * 0.07
		elif mood == &"oops":
			lean += sin(reaction * TAU * 2.0) * reaction * 0.15
	_body.position.y = bounce
	_body.rotation.z = lean
	_body.scale = Vector3(1.0 + squash, 1.0 - squash, 1.0 + squash * 0.3)
	var wave := 0.0 if reduced_motion else sin(clock * 3.3) * 0.10
	_left_arm.rotation.z = -0.12 - wave
	_right_arm.rotation.z = 0.12 + wave
	if mood == &"happy" or _welcoming:
		_right_arm.rotation.z = 2.28 if reduced_motion else 2.28 + wave * 2.0
	if mood == &"happy":
		_left_arm.rotation.z = -2.25 if reduced_motion else -2.25 - wave


## Exposes the entire rigid pose for pause and accessibility regression assertions.
func pose_transforms() -> Array[Transform3D]:
	return [_body.transform, _left_arm.transform, _right_arm.transform]


func _set_expression(mood: StringName) -> void:
	var key: StringName = mood if mood in [&"happy", &"oops"] else &"neutral"
	if _mood == key:
		return
	_mood = key
	if not _inert:
		_face.mesh = _meshes[key]


func _part(
	title: String, key: StringName, material: Material, shadows: bool
) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = title
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not _inert:
		node.mesh = _meshes[key]
	_body.add_child(node)
	return node


static func _make_meshes() -> Dictionary:
	var shell := MeshBuilder.new()
	var trim := MeshBuilder.new()
	shell.block(Vector3(0, 0.80, 0), Vector3(1.09, 0.82, 0.70), Color.WHITE, 0.13)
	shell.block(Vector3(0, 1.68, 0.02), Vector3(1.61, 1.02, 0.94), Color.WHITE, 0.19)
	shell.pebble(Vector3(0.15, 2.45, 0.04), Vector3.ONE * 0.13, Color.WHITE)
	var front := Basis.from_euler(Vector3(PI * 0.5, 0, 0))
	var side := Basis.from_euler(Vector3(0, 0, PI * 0.5))
	for sign_x: float in [-1.0, 1.0]:
		trim.block(Vector3(sign_x * 0.34, 0.105, 0.07),
			Vector3(0.56, 0.21, 0.65), INK, 0.07)
		trim.block(Vector3(sign_x * 0.34, 0.23, 0.12),
			Vector3(0.55, 0.20, 0.59), CREAM, 0.07)
		trim.drum(Vector3(sign_x * 0.33, 0.39, 0),
			0.135, 0.135, 0.18, JOINT, Basis.IDENTITY, 10)
		trim.washer(Vector3(sign_x * 0.33, 0.39, 0), 0.12, 0.17, 0.045, CREAM,
			Basis.IDENTITY, 10)
		trim.drum(Vector3(sign_x * 0.82, 1.65, 0.02),
			0.255, 0.255, 0.14, INK, side, 12)
		shell.drum(Vector3(sign_x * 0.935, 1.65, 0.02),
			0.207, 0.207, 0.16, Color.WHITE, side, 12)
		trim.drum(Vector3(sign_x * 1.027, 1.65, 0.02),
			0.106, 0.106, 0.022, CREAM, side, 10)
		trim.block(Vector3(sign_x * 0.61, 1.44, 0.512),
			Vector3(0.09, 0.054, 0.025), GREY, 0.008)
	trim.block(Vector3(0, 1.68, 0.504), Vector3(1.30, 0.68, 0.13), CREAM, 0.075)
	trim.block(Vector3(0, 1.71, 0.586), Vector3(1.15, 0.52, 0.052), INK, 0.018)
	trim.drum(Vector3(0, 0.81, 0.405), 0.335, 0.335, 0.14, CREAM, front, 20)
	trim.drum(Vector3(0, 0.81, 0.489), 0.271, 0.271, 0.045, INK, front, 20)
	for shutter in 3:
		trim.block(Vector3(0, 0.72 + shutter * 0.085, 0.518),
			Vector3(0.26, 0.025, 0.012), JOINT, 0.004)
	trim.block(Vector3(0, 0.68, -0.43), Vector3(0.71, 0.44, 0.24), JOINT, 0.045)
	trim.block(Vector3(0, 1.165, 0), Vector3(0.46, 0.12, 0.41), INK, 0.025)
	trim.drum(Vector3(0, 2.20, 0.02), 0.19, 0.14, 0.12, CREAM)
	trim.rod(Vector3(0, 2.24, 0.02), Vector3(0.15, 2.46, 0.04), 0.043, INK)
	var welcome := MeshBuilder.new()
	welcome.stamp(Vector3(0, 0.81, 0.558), PackedVector2Array([
		Vector2(0.035, -0.21), Vector2(-0.16, 0.035), Vector2(-0.035, 0.035),
		Vector2(-0.065, 0.20), Vector2(0.15, -0.055), Vector2(0.025, -0.055),
	]), 0.045, CREAM)
	return {
		&"shell": shell.finish(), &"trim": trim.finish(),
		&"neutral": _make_face(&"neutral"), &"happy": _make_face(&"happy"),
		&"oops": _make_face(&"oops"), &"welcome": welcome.finish(),
		&"left_arm": _make_arm(-1.0), &"right_arm": _make_arm(1.0),
	}


static func _make_arm(side: float) -> ArrayMesh:
	var arm := MeshBuilder.new()
	arm.pebble(Vector3.ZERO, Vector3.ONE * 0.17, JOINT)
	arm.rod(Vector3.ZERO, Vector3(side * 0.17, -0.29, 0.03), 0.105, GREY)
	arm.pebble(Vector3(side * 0.19, -0.37, 0.11), Vector3(0.20, 0.22, 0.21), CREAM)
	arm.pebble(Vector3(side * 0.05, -0.34, 0.24), Vector3.ONE * 0.095, CREAM)
	return arm.finish()


static func _make_face(mood: StringName) -> ArrayMesh:
	var face := MeshBuilder.new()
	for side: float in [-1.0, 1.0]:
		var x := side * 0.285
		if mood == &"happy":
			face.rod(Vector3(x - 0.085, 1.715, 0.623),
				Vector3(x, 1.805, 0.623), 0.033, CREAM)
			face.rod(Vector3(x, 1.805, 0.623),
				Vector3(x + 0.085, 1.715, 0.623), 0.033, CREAM)
		elif mood == &"oops":
			face.rod(Vector3(x - 0.071, 1.80, 0.623),
				Vector3(x + 0.071, 1.72, 0.623), 0.038, CREAM)
		else:
			face.block(Vector3(x, 1.77, 0.623), Vector3(0.145, 0.194, 0.023),
				CREAM, 0.009)
			face.block(Vector3(x + 0.025, 1.81, 0.639),
				Vector3(0.033, 0.056, 0.008), Color.WHITE, 0.002)
	var mouth := PackedVector3Array([
		Vector3(-0.12, 1.59, 0.626), Vector3(-0.06, 1.56, 0.626),
		Vector3(0.06, 1.56, 0.626), Vector3(0.12, 1.59, 0.626),
	])
	if mood == &"oops":
		mouth = PackedVector3Array([
			Vector3(-0.09, 1.575, 0.626), Vector3(0.09, 1.575, 0.626)])
	for part in mouth.size() - 1:
		face.rod(mouth[part], mouth[part + 1], 0.023, CREAM)
	return face.finish()


static func _make_stamp(id: StringName) -> ArrayMesh:
	var stamp := MeshBuilder.new()
	stamp.stamp(Vector3(0, 0.835, 0.557), Glyph.polygon(id, Vector2.ZERO, 0.187),
		0.055, CREAM)
	var facing := Basis.from_euler(Vector3(PI * 0.5, 0, 0))
	for pip in 3:
		stamp.drum(Vector3((pip - 1) * 0.104, 0.620, 0.555),
			0.026, 0.026, 0.025, CREAM if pip <= Palette.shade_index(id) else JOINT,
			facing, 8)
	return stamp.finish()
