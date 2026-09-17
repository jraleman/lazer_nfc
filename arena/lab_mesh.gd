extends RefCounted

## Original moulded-resin geometry. Each builder becomes one vertex-painted surface.
## Small bevels and thick inset pieces do the work of textures and renderer-only glow.

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()


## A chamfered housing with bevels on its vertical edges and both horizontal rims.
func block(
	at: Vector3, dimensions: Vector3, tint: Color, bevel := 0.06,
	basis := Basis.IDENTITY
) -> void:
	var half := dimensions * 0.5
	var edge := minf(bevel, minf(half.x, minf(half.y, half.z)) * 0.8)
	var levels := PackedFloat32Array([-half.y, -half.y + edge, half.y - edge, half.y])
	var rings: Array[PackedVector3Array] = []
	for level in 4:
		var inset := edge * 0.48 if level == 0 or level == 3 else 0.0
		var x := half.x - inset
		var z := half.z - inset
		var cut := maxf(edge - inset * 0.5, 0.001)
		var outline := PackedVector2Array([
			Vector2(-x + cut, -z), Vector2(x - cut, -z),
			Vector2(x, -z + cut), Vector2(x, z - cut),
			Vector2(x - cut, z), Vector2(-x + cut, z),
			Vector2(-x, z - cut), Vector2(-x, -z + cut),
		])
		var ring := PackedVector3Array()
		for point in outline:
			ring.append(at + basis * Vector3(point.x, levels[level], point.y))
		rings.append(ring)
	for corner in 8:
		var next := (corner + 1) % 8
		_triangle(at + basis * Vector3(0, half.y, 0),
			rings[3][next], rings[3][corner], tint)
		_triangle(at - basis * Vector3(0, half.y, 0),
			rings[0][corner], rings[0][next], tint)
		for level in 3:
			_quad(rings[level][corner], rings[level + 1][corner],
				rings[level + 1][next], rings[level][next], tint)


## A faceted spool, button, bottle or tapered housing along its local Y axis.
func drum(
	at: Vector3, bottom: float, top: float, height: float, tint: Color,
	basis := Basis.IDENTITY, sides := 16
) -> void:
	for side in sides:
		var angle := TAU * float(side) / float(sides)
		var next_angle := TAU * float(side + 1) / float(sides)
		var lower := Vector3(cos(angle) * bottom, -height * 0.5, sin(angle) * bottom)
		var upper := Vector3(cos(angle) * top, height * 0.5, sin(angle) * top)
		var lower_next := Vector3(
			cos(next_angle) * bottom, -height * 0.5, sin(next_angle) * bottom)
		var upper_next := Vector3(
			cos(next_angle) * top, height * 0.5, sin(next_angle) * top)
		_quad(at + basis * lower, at + basis * upper,
			at + basis * upper_next, at + basis * lower_next, tint)
		_triangle(at + basis * Vector3(0, height * 0.5, 0),
			at + basis * upper_next, at + basis * upper, tint)
		_triangle(at - basis * Vector3(0, height * 0.5, 0),
			at + basis * lower, at + basis * lower_next, tint)


## Rounded mittens and lamp lenses stay deliberately low-poly rather than glassy.
func pebble(
	at: Vector3, radii: Vector3, tint: Color, sides := 12, bands := 6
) -> void:
	for band in bands:
		var lower := -PI * 0.5 + PI * float(band) / float(bands)
		var upper := -PI * 0.5 + PI * float(band + 1) / float(bands)
		for side in sides:
			var left := TAU * float(side) / float(sides)
			var right := TAU * float(side + 1) / float(sides)
			var a := at + _sphere_point(lower, left) * radii
			var b := at + _sphere_point(upper, left) * radii
			var c := at + _sphere_point(upper, right) * radii
			var d := at + _sphere_point(lower, right) * radii
			if band > 0:
				_triangle(a, c, d, tint)
			if band < bands - 1:
				_triangle(a, b, c, tint)


## Cables and toy rails are real six/eight-sided rods, batched with their fittings.
func rod(from: Vector3, to: Vector3, radius: float, tint: Color, sides := 8) -> void:
	var direction := to - from
	if direction.length_squared() < 0.000001:
		push_error("LabMesh.rod needs distinct endpoints.")
		return
	var basis := Basis(Quaternion(Vector3.UP, direction.normalized()))
	drum((from + to) * 0.5, radius, radius, direction.length(), tint, basis, sides)


## An open washer; stacked pale rings suggest a lit core without bloom or lights.
func washer(
	at: Vector3, inner: float, outer: float, height: float,
	tint: Color, basis := Basis.IDENTITY, sides := 24
) -> void:
	for side in sides:
		var angles := Vector2(TAU * float(side) / sides, TAU * float(side + 1) / sides)
		var points := PackedVector3Array()
		for angle: float in [angles.x, angles.y]:
			for radius: float in [inner, outer]:
				for y: float in [-height * 0.5, height * 0.5]:
					points.append(at + basis * Vector3(cos(angle) * radius, y,
						sin(angle) * radius))
		_quad(points[1], points[5], points[7], points[3], tint)
		_quad(points[0], points[2], points[6], points[4], tint)
		_quad(points[2], points[3], points[7], points[6], tint)
		_quad(points[0], points[4], points[5], points[1], tint)


## Canvas-space polygons become chunky front-facing stamps, including concave stars.
func stamp(
	at: Vector3, outline: PackedVector2Array, depth: float, tint: Color,
	basis := Basis.IDENTITY
) -> void:
	if outline.size() < 3:
		push_error("LabMesh.stamp needs a closed silhouette.")
		return
	var faces := Geometry2D.triangulate_polygon(outline)
	var front := PackedVector3Array()
	var back := PackedVector3Array()
	for point in outline:
		front.append(at + basis * Vector3(point.x, -point.y, depth * 0.5))
		back.append(at + basis * Vector3(point.x, -point.y, -depth * 0.5))
	for offset in range(0, faces.size(), 3):
		_triangle(front[faces[offset]], front[faces[offset + 2]],
			front[faces[offset + 1]], tint)
		_triangle(back[faces[offset]], back[faces[offset + 1]],
			back[faces[offset + 2]], tint)
	for corner in outline.size():
		var next := (corner + 1) % outline.size()
		_quad(back[corner], front[corner], front[next], back[next], tint.darkened(0.16))


## Built-in font outlines become embossed geometry, not a floating billboard.
func lettering(
	at: Vector3, text: String, height: float, tint: Color,
	basis := Basis.IDENTITY
) -> void:
	var letters := TextMesh.new()
	letters.text = text
	letters.font = ThemeDB.fallback_font
	letters.font_size = 64
	letters.pixel_size = height / 64.0
	letters.depth = 0.028
	letters.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letters.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_append_mesh(letters, Transform3D(basis, at), tint)


## A mesh uses one material slot regardless of the number of lab details.
func finish() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	var result := ArrayMesh.new()
	if not _vertices.is_empty():
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


## Vertex colours are authored as sRGB paint; only small lens meshes are unshaded.
static func paint(unshaded := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.78
	material.metallic_specular = 0.22
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _sphere_point(latitude: float, longitude: float) -> Vector3:
	return Vector3(cos(latitude) * cos(longitude), sin(latitude),
		cos(latitude) * sin(longitude))


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, tint: Color) -> void:
	_triangle(a, b, c, tint)
	_triangle(a, c, d, tint)


func _triangle(a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.0000001:
		return
	normal = normal.normalized()
	# Godot's front-face winding is clockwise, opposite the outward cross product.
	for point: Vector3 in [a, c, b]:
		_vertices.append(point)
		_normals.append(normal)
		_colors.append(tint)


func _append_mesh(mesh: Mesh, transform: Transform3D, tint: Color) -> void:
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for offset in count:
			var index := indices[offset] if not indices.is_empty() else offset
			_vertices.append(transform * vertices[index])
			_normals.append((transform.basis * normals[index]).normalized())
			_colors.append(tint)
