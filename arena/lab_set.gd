extends Node3D

## A handmade pocket laboratory: enamel, rubber feet, candy switches and toy rails.
## Static detail is baked into two surfaces; the reactor's rotating collar is separate.

const MeshBuilder = preload("res://games/lazer_nfc/arena/lab_mesh.gd")
const Palette = preload("res://games/lazer_nfc/run/palette.gd")
const Glyph = preload("res://games/lazer_nfc/ui/shape_glyph.gd")
const CREAM := Color("fff0cd")
const MINT := Color("b8e5d6")
const TEAL := Color("528a91")
const INK := Color("244855")
const CORAL := Color("ec9a87")
const GOLD := Color("edc36e")
const SILVER := Color("a6bcc0")

static var _meshes: Dictionary = {}

var collar: MeshInstance3D
var muzzle: Marker3D


## Headless keeps the same named nodes and transforms but does not construct geometry.
func build(inert: bool) -> void:
	if not inert and _meshes.is_empty():
		_meshes = _make_meshes()
	_mesh("EnamelAndFittings", &"solid", MeshBuilder.paint(), true, inert)
	_mesh("InlaidMarkings", &"inlay", MeshBuilder.paint(), false, inert)
	_mesh("ReactorLenses", &"lenses", MeshBuilder.paint(true), false, inert)
	collar = _mesh("ReactorCollar", &"collar", MeshBuilder.paint(), true, inert)
	collar.position = Vector3(-3.35, 1.92, 0.50)
	muzzle = Marker3D.new()
	muzzle.name = "BeamMuzzle"
	muzzle.position = Vector3(-1.75, 1.44, 0.53)
	add_child(muzzle)


## Only the explicit round clock animates this prop, never _process or shader TIME.
func pose(clock: float, reduced_motion: bool) -> void:
	if collar != null:
		collar.rotation.y = 0.18 if reduced_motion else 0.18 + clock * 0.24


## Extremal silhouettes, rather than a mostly empty box, determine orthographic framing.
static func framing_points() -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(-6.10, -0.72, -3.98), Vector3(6.10, -0.72, -3.98),
		Vector3(-6.10, -0.72, 3.98), Vector3(6.10, -0.72, 3.98),
		Vector3(-6.10, 0.44, -3.98), Vector3(6.10, 0.44, -3.98),
		Vector3(-6.10, 0.44, 3.98), Vector3(6.10, 0.44, 3.98),
		Vector3(-2.90, 3.37, -2.67), Vector3(1.70, 3.37, -2.67),
		Vector3(-4.50, 2.65, 0.50), Vector3(-2.20, 2.65, 0.50),
		Vector3(-0.20, 4.45, 1.22), Vector3(2.85, 4.45, 1.22),
		Vector3(5.30, 2.25, -1.00),
	])


func _mesh(
	title: String, key: StringName, material: Material, shadows: bool, inert: bool
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = title
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not inert:
		instance.mesh = _meshes[key]
	add_child(instance)
	return instance


static func _make_meshes() -> Dictionary:
	var solid := MeshBuilder.new()
	var inlay := MeshBuilder.new()
	var lenses := MeshBuilder.new()
	var rotor := MeshBuilder.new()
	_bench(solid, inlay)
	_track(solid, inlay)
	_sign_and_samples(solid, inlay)
	_reactor(solid, inlay, lenses, rotor)
	_accessories(solid, inlay)
	return {
		&"solid": solid.finish(), &"inlay": inlay.finish(),
		&"lenses": lenses.finish(), &"collar": rotor.finish(),
	}


static func _bench(solid: MeshBuilder, inlay: MeshBuilder) -> void:
	for x: float in [-4.85, 4.85]:
		for z: float in [-2.85, 2.85]:
			solid.drum(Vector3(x, -0.51, z), 0.58, 0.51, 0.36, INK)
			solid.drum(Vector3(x, -0.35, z), 0.50, 0.50, 0.24, CREAM)
	solid.block(Vector3(0, -0.06, 0), Vector3(12, 0.66, 7.9), CORAL, 0.20)
	solid.block(Vector3(0, -0.27, 0), Vector3(11.98, 0.14, 7.87),
		Color("cf7b73"), 0.045)
	solid.block(Vector3(0, 0.27, 0), Vector3(12.04, 0.17, 7.94), CREAM, 0.055)
	solid.block(Vector3(0, 0.37, 0), Vector3(11.48, 0.09, 7.38), MINT, 0.03)
	for line in range(-8, 9):
		inlay.block(Vector3(line * 0.61, 0.418, 0), Vector3(0.012, 0.004, 6.75),
			Color("a1d1c5"), 0)
	for line in range(-5, 6):
		inlay.block(Vector3(0, 0.419, line * 0.61), Vector3(10.95, 0.004, 0.012),
			Color("a1d1c5"), 0)
	for x: float in [-5.62, 5.62]:
		for z: float in [-3.48, 3.48]:
			solid.drum(Vector3(x, 0.425, z), 0.10, 0.10, 0.04, GOLD, Basis.IDENTITY, 8)
			inlay.block(Vector3(x, 0.45, z), Vector3(0.10, 0.01, 0.02), INK, 0)
	solid.block(Vector3(-2.9, -0.02, 3.96), Vector3(3.3, 0.39, 0.055), INK, 0.055)
	inlay.lettering(Vector3(-2.9, -0.01, 4.005), "MEMORY LAB", 0.28, CREAM)
	for slot in 7:
		solid.block(Vector3(1.5 + slot * 0.43, -0.01, 3.96),
			Vector3(0.26, 0.16, 0.055), CORAL.darkened(0.25), 0.03)
		inlay.block(Vector3(1.5 + slot * 0.43, 0.015, 3.995),
			Vector3(0.15, 0.026, 0.012), CREAM, 0.005)
	for x: float in [-5.85, 5.85]:
		solid.rod(Vector3(x, 0.51, -2.9), Vector3(x, 0.51, 2.9), 0.085, TEAL)
		for z: float in [-2.9, 2.9]:
			solid.pebble(Vector3(x, 0.51, z), Vector3.ONE * 0.13, CREAM)


static func _track(solid: MeshBuilder, inlay: MeshBuilder) -> void:
	solid.block(Vector3(1.15, 0.46, 0.43), Vector3(8.0, 0.12, 2.36),
		Color("719b9d"), 0.055)
	inlay.block(Vector3(1.15, 0.526, 0.43), Vector3(7.70, 0.015, 1.85),
		Color("81afae"), 0.004)
	for x in range(-3, 10):
		inlay.block(Vector3(x * 0.48, 0.54, 0.42),
			Vector3(0.025, 0.008, 1.68), Color("a0c9bf"), 0)
	for z: float in [-0.77, 1.64]:
		solid.rod(Vector3(-2.6, 0.64, z), Vector3(4.95, 0.64, z), 0.064, CREAM)
		for x: float in [-2.6, -0.50, 2.75, 4.95]:
			solid.drum(Vector3(x, 0.51, z), 0.14, 0.095, 0.20, TEAL)
			solid.pebble(Vector3(x, 0.66, z), Vector3.ONE * 0.09, GOLD)
	for entry: Vector3 in [
		Vector3(1.30, 0.57, 0.49), Vector3(3.47, 0.57, 0.08),
		Vector3(4.34, 0.50, -1.34),
	]:
		var radius := 1.0 if entry.x < 2.0 else (0.64 if entry.x < 4.0 else 0.50)
		solid.drum(entry, radius, radius * 0.98, 0.095, CREAM, Basis.IDENTITY, 24)
		inlay.drum(entry + Vector3(0, 0.054, 0), radius * 0.83,
			radius * 0.83, 0.016, TEAL, Basis.IDENTITY, 24)
		inlay.washer(entry + Vector3(0, 0.066, 0), radius * 0.64,
			radius * 0.71, 0.012, MINT)
	# Unlabelled steps indicate a queue, not a hidden sequence.
	for step in 3:
		var x := 0.18 + step * 0.26
		inlay.stamp(Vector3(x, 0.554, 0.50), PackedVector2Array([
			Vector2(-0.08, -0.12), Vector2(0.08, 0), Vector2(-0.08, 0.12),
		]), 0.01, CREAM, Basis.from_euler(Vector3(-PI * 0.5, 0, 0)))


static func _sign_and_samples(solid: MeshBuilder, inlay: MeshBuilder) -> void:
	for x: float in [-2.63, 1.37]:
		solid.block(Vector3(x, 0.61, -2.66), Vector3(0.53, 0.34, 0.67), GOLD)
		solid.rod(Vector3(x, 0.67, -2.66), Vector3(x, 2.94, -2.66), 0.09, TEAL)
	solid.block(Vector3(-0.63, 2.82, -2.67), Vector3(4.73, 1.08, 0.26),
		CREAM, 0.10)
	solid.block(Vector3(-0.63, 2.86, -2.514), Vector3(4.28, 0.72, 0.07),
		INK, 0.03)
	inlay.lettering(Vector3(-0.63, 2.99, -2.447), "LaZer NFC", 0.57, CREAM)
	inlay.lettering(Vector3(-0.63, 2.57, -2.439), "LITTLE ROBOTS. BIG IDEAS.", 0.155, MINT)
	var forward := Basis.from_euler(Vector3(PI * 0.5, 0, 0))
	for x: float in [-2.77, 1.51]:
		for y: float in [2.46, 3.20]:
			solid.drum(Vector3(x, y, -2.51), 0.059, 0.059, 0.038, GOLD, forward, 8)
	solid.block(Vector3(-0.50, 0.62, -2.47), Vector3(5.60, 0.28, 0.68),
		CREAM, 0.08)
	for sample in 7:
		var x := -2.78 + sample * 0.75
		var hue: StringName = Palette.HUES[sample]
		var color := Palette.color(hue)
		solid.drum(Vector3(x, 0.83, -2.48), 0.23, 0.21, 0.18, INK)
		solid.drum(Vector3(x, 1.02, -2.48), 0.19, 0.19, 0.29,
			color.lerp(CREAM, 0.28))
		solid.pebble(Vector3(x, 1.15, -2.48), Vector3(0.19, 0.15, 0.19), color)
		solid.drum(Vector3(x, 0.92, -2.48), 0.207, 0.207, 0.06, CREAM)
		inlay.stamp(Vector3(x, 1.035, -2.274),
			Glyph.polygon(hue, Vector2.ZERO, 0.091), 0.018, INK)
		inlay.drum(Vector3(x, 0.779, -2.11), 0.044, 0.044, 0.018, color,
			Basis.IDENTITY, 8)


static func _reactor(
	solid: MeshBuilder, inlay: MeshBuilder, lenses: MeshBuilder, rotor: MeshBuilder
) -> void:
	var at := Vector3(-3.35, 0.43, 0.50)
	solid.drum(at + Vector3(0, 0.08, 0), 1.03, 0.96, 0.18, INK, Basis.IDENTITY, 16)
	solid.drum(at + Vector3(0, 0.21, 0), 0.97, 0.85, 0.20, CREAM)
	solid.drum(at + Vector3(0, 0.36, 0), 0.78, 0.73, 0.22, GOLD)
	solid.drum(at + Vector3(0, 0.79, 0), 0.64, 0.58, 0.78, TEAL)
	solid.drum(at + Vector3(0, 1.14, 0), 0.72, 0.71, 0.16, CREAM)
	solid.drum(at + Vector3(0, 1.24, 0), 0.65, 0.54, 0.12, CORAL)
	for side in 8:
		var angle := TAU * float(side) / 8.0
		var radial := Vector3(cos(angle), 0, sin(angle))
		solid.pebble(at + radial * 0.78 + Vector3(0, 0.33, 0),
			Vector3.ONE * 0.08, CORAL)
		if side % 2 == 0:
			solid.rod(at + radial * 0.52 + Vector3(0, 1.24, 0),
				at + radial * 0.40 + Vector3(0, 1.83, 0), 0.047, INK)
	lenses.drum(at + Vector3(0, 1.49, 0), 0.28, 0.28, 0.58,
		Color("baf8d6"), Basis.IDENTITY, 16)
	lenses.pebble(at + Vector3(0, 1.78, 0), Vector3(0.27, 0.25, 0.27),
		Color("fff3b4"))
	for level in 3:
		lenses.washer(at + Vector3(0, 1.29 + level * 0.21, 0),
			0.28, 0.43, 0.055, Color("f5ffde"))
	solid.drum(at + Vector3(0, 1.96, 0), 0.53, 0.34, 0.15, CREAM)
	solid.pebble(at + Vector3(0, 2.065, 0), Vector3(0.23, 0.12, 0.23), GOLD)
	var right := Basis.from_euler(Vector3(0, 0, -PI * 0.5))
	solid.drum(Vector3(-2.61, 1.44, 0.53), 0.32, 0.25, 0.76, CREAM, right)
	solid.drum(Vector3(-2.20, 1.44, 0.53), 0.29, 0.29, 0.24, CORAL, right)
	solid.drum(Vector3(-2.03, 1.44, 0.53), 0.23, 0.23, 0.21, INK, right)
	solid.washer(Vector3(-1.90, 1.44, 0.53), 0.115, 0.26, 0.10, GOLD, right)
	lenses.drum(Vector3(-1.832, 1.44, 0.53), 0.116, 0.116, 0.028,
		Color("fcffdc"), right)
	var front := Basis.from_euler(Vector3(PI * 0.5, 0, 0))
	solid.drum(at + Vector3(0, 0.79, 0.62), 0.32, 0.32, 0.08, CREAM, front)
	inlay.drum(at + Vector3(0, 0.79, 0.673), 0.26, 0.26, 0.03, INK, front)
	inlay.stamp(at + Vector3(0, 0.80, 0.698), PackedVector2Array([
		Vector2(0.035, -0.20), Vector2(-0.14, 0.04), Vector2(-0.015, 0.04),
		Vector2(-0.05, 0.21), Vector2(0.145, -0.04), Vector2(0.02, -0.04),
	]), 0.023, GOLD)
	for side in 3:
		var angle := TAU * float(side) / 3.0
		var radial := Vector3(cos(angle), 0, sin(angle))
		rotor.rod(radial * 0.34, radial * 0.58, 0.045, CORAL)
		rotor.pebble(radial * 0.59, Vector3(0.10, 0.075, 0.10), CREAM)
	rotor.washer(Vector3.ZERO, 0.45, 0.51, 0.04, GOLD)
	var cable := PackedVector3Array([
		at + Vector3(-0.43, 0.39, -0.36), Vector3(-4.19, 0.57, -0.45),
		Vector3(-4.42, 0.53, -1.56), Vector3(-3.86, 0.53, -2.32),
		Vector3(-3.27, 0.65, -2.49),
	])
	for segment in cable.size() - 1:
		solid.rod(cable[segment], cable[segment + 1], 0.084, CORAL)
		solid.pebble(cable[segment], Vector3.ONE * 0.086, CORAL)


static func _accessories(solid: MeshBuilder, inlay: MeshBuilder) -> void:
	var front := Basis.from_euler(Vector3(PI * 0.5, 0, 0))
	# The little scope, its recessed display and a real chunky dial.
	solid.block(Vector3(3.78, 0.91, -2.85), Vector3(1.70, 1.01, 0.81), GOLD, 0.13)
	solid.block(Vector3(3.55, 1.04, -2.408), Vector3(0.90, 0.56, 0.085), INK, 0.035)
	for stroke in 4:
		var x := 3.22 + stroke * 0.19
		inlay.block(Vector3(x, 1.01, -2.354),
			Vector3(0.075, 0.12 + (stroke % 3) * 0.08, 0.015), MINT, 0.004)
	solid.drum(Vector3(4.31, 0.95, -2.39), 0.16, 0.15, 0.12, CORAL, front, 12)
	inlay.block(Vector3(4.31, 1.016, -2.312), Vector3(0.025, 0.085, 0.014), CREAM, 0.003)
	for x: float in [3.15, 4.40]:
		solid.block(Vector3(x, 0.48, -2.83), Vector3(0.19, 0.17, 0.51), INK)
	# An open notebook and a pencil, not another screen competing with the recall.
	solid.block(Vector3(-4.25, 0.49, 2.62), Vector3(1.90, 0.14, 1.15), TEAL)
	solid.block(Vector3(-4.25, 0.579, 2.62), Vector3(1.71, 0.06, 1.01), CREAM, 0.02)
	for line in 4:
		inlay.block(Vector3(-4.32, 0.615, 2.35 + line * 0.17),
			Vector3(1.03 - (line % 2) * 0.24, 0.007, 0.022), SILVER, 0)
	solid.rod(Vector3(-3.00, 0.51, 2.02), Vector3(-2.65, 0.51, 3.15), 0.060, CORAL, 6)
	solid.pebble(Vector3(-3.00, 0.51, 2.02), Vector3.ONE * 0.070, CREAM)
	# Spare washers and domed switches tell a miniature story at the front right.
	solid.block(Vector3(3.83, 0.50, 2.79), Vector3(2.12, 0.16, 0.81), CREAM)
	for button in 3:
		var at := Vector3(3.10 + button * 0.70, 0.64, 2.79)
		solid.drum(at, 0.22, 0.21, 0.08, INK)
		solid.pebble(at + Vector3(0, 0.06, 0), Vector3(0.18, 0.13, 0.18),
			[CORAL, MINT, GOLD][button])
	for index in 2:
		var at := Vector3(0.1 + index * 0.65, 0.47, 2.82)
		solid.washer(at, 0.115, 0.25, 0.10, GOLD, Basis.IDENTITY, 12)
	inlay.block(Vector3(1.75, 0.43, 2.85), Vector3(0.82, 0.006, 0.53), CREAM, 0)
	inlay.stamp(Vector3(1.75, 0.438, 2.85), PackedVector2Array([
		Vector2(-0.16, 0.0), Vector2(-0.04, 0.12), Vector2(0.20, -0.14),
		Vector2(0.14, -0.20), Vector2(-0.045, 0.01), Vector2(-0.10, -0.05),
	]), 0.008, TEAL, Basis.from_euler(Vector3(-PI * 0.5, 0, 0)))
