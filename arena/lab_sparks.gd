extends Node3D

## One fixed MultiMesh of harmless resin sprinkles, integrated only by advance().
## No GPU emitters, timers, per-hit nodes, physics bodies or hidden model randomness.

const MeshBuilder = preload("res://games/lazer_nfc/arena/lab_mesh.gd")
const CAPACITY := 56

class Sprinkle extends RefCounted:
	var active := false
	var age := 0.0
	var lifetime := 0.7
	var origin := Vector3.ZERO
	var velocity := Vector3.ZERO
	var spin := Vector3.ZERO
	var size := 0.1

var _pool: Array[Sprinkle] = []
var _view: MultiMeshInstance3D
var _instances: MultiMesh
var _random := RandomNumberGenerator.new()
var _cursor := 0
var _enabled := true


## Headless has no pool or render resource, rather than invisible active emitters.
func build(inert: bool) -> void:
	_random.seed = 714239
	if inert:
		_enabled = false
		return
	_instances = MultiMesh.new()
	_instances.transform_format = MultiMesh.TRANSFORM_3D
	_instances.use_colors = true
	var geometry := MeshBuilder.new()
	geometry.block(Vector3.ZERO, Vector3(1.0, 0.38, 0.56), Color.WHITE, 0.10)
	_instances.mesh = geometry.finish()
	_instances.instance_count = CAPACITY
	_instances.visible_instance_count = 0
	_view = MultiMeshInstance3D.new()
	_view.name = "PooledSprinkles"
	_view.multimesh = _instances
	_view.material_override = MeshBuilder.paint(true)
	_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_view.custom_aabb = AABB(Vector3(-9, -2, -6), Vector3(18, 11, 12))
	add_child(_view)
	for slot in CAPACITY:
		_pool.append(Sprinkle.new())
		_hide_slot(slot)


## Reduced motion drops already airborne confetti immediately, not just future bursts.
func set_enabled(value: bool) -> void:
	_enabled = value and _instances != null
	if not _enabled:
		clear()


## A short pop scatters painted pieces; celebrations use a slower, wider fan.
func burst(at: Vector3, tint: Color, count: int, celebration := false) -> void:
	if not _enabled:
		return
	for emitted in mini(count, CAPACITY):
		var slot := _cursor
		_cursor = (_cursor + 1) % CAPACITY
		var piece := _pool[slot]
		piece.active = true
		piece.age = 0.0
		piece.lifetime = _random.randf_range(0.58, 1.10) if celebration \
			else _random.randf_range(0.35, 0.64)
		piece.origin = at
		var angle := _random.randf() * TAU
		var speed := _random.randf_range(0.6, 2.1) if celebration \
			else _random.randf_range(0.4, 1.2)
		piece.velocity = Vector3(cos(angle) * speed,
			_random.randf_range(1.6, 3.0), sin(angle) * speed * 0.68)
		piece.spin = Vector3(_random.randf(), _random.randf(), _random.randf()) * 8.0
		piece.size = _random.randf_range(0.095, 0.17)
		_instances.set_instance_color(slot, tint.lerp(Color("fff6d5"),
			_random.randf_range(0.05, 0.38)))
		_place_slot(slot)
	_instances.visible_instance_count = CAPACITY


## Analytic gravity and finite lifetimes behave predictably through a frame hitch.
func advance(delta: float) -> void:
	if not _enabled:
		return
	var live := 0
	for slot in _pool.size():
		var piece := _pool[slot]
		if not piece.active:
			continue
		piece.age += delta
		if piece.age >= piece.lifetime:
			piece.active = false
			_hide_slot(slot)
		else:
			live += 1
			_place_slot(slot)
	_instances.visible_instance_count = CAPACITY if live > 0 else 0


## Replays reuse the same pool and start from the same purely visual seed.
func reset() -> void:
	clear()
	_cursor = 0
	_random.seed = 714239


## Cancels particles on results, exit, and live accessibility changes.
func clear() -> void:
	if _instances == null:
		return
	for slot in _pool.size():
		if _pool[slot].active:
			_pool[slot].active = false
			_hide_slot(slot)
	_instances.visible_instance_count = 0


## The pool size and live count make headless and repeated-hit costs observable.
func diagnostics() -> Dictionary:
	var count := 0
	for piece in _pool:
		if piece.active:
			count += 1
	return {"capacity": _pool.size(), "active": count, "enabled": _enabled}


func _place_slot(slot: int) -> void:
	var piece := _pool[slot]
	var time := piece.age
	var at := piece.origin + piece.velocity * time + Vector3(0, -3.4 * time * time, 0)
	var fade := clampf((piece.lifetime - time) * 5.0, 0.0, 1.0)
	var basis := Basis.from_euler(piece.spin * time).scaled(Vector3.ONE * piece.size * fade)
	_instances.set_instance_transform(slot, Transform3D(basis, at))


func _hide_slot(slot: int) -> void:
	_instances.set_instance_transform(slot,
		Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
