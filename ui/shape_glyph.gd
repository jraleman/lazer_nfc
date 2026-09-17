extends RefCounted

## The lab, key deck and printed artwork share these seven non-colour identities.
## Coordinates are canvas-space; the arena extrudes the same outlines as toy stamps.

const Palette = preload("res://games/lazer_nfc/run/palette.gd")
const INK := Color("173743")
const PAPER := Color("fff4d8")
const NEUTRAL := Color("bbc8c9")


## Resolves shade variants to the same shape, in the palette's spectrum order.
static func hue_index(id: StringName) -> int:
	return Palette.HUES.find(Palette.hue_id(id))


## A closed, un-repeated outline: triangle, diamond, star, circle, square, hexagon, plus.
## Empty/unknown ids deliberately have no outline, rather than a fallback answer.
static func polygon(
	id: StringName, center: Vector2, radius: float
) -> PackedVector2Array:
	var index := hue_index(id)
	var result := PackedVector2Array()
	if index < 0:
		return result
	if index == 6:
		for point: Vector2 in [
			Vector2(-0.32, -1), Vector2(0.32, -1),
			Vector2(0.32, -0.32), Vector2(1, -0.32),
			Vector2(1, 0.32), Vector2(0.32, 0.32),
			Vector2(0.32, 1), Vector2(-0.32, 1),
			Vector2(-0.32, 0.32), Vector2(-1, 0.32),
			Vector2(-1, -0.32), Vector2(-0.32, -0.32),
		]:
			result.append(center + point * radius)
		return result
	var count: int = [3, 4, 10, 32, 4, 6][index]
	var offset := -PI * 0.5
	if index == 4:
		offset = -PI * 0.75
	for corner in count:
		var angle := offset + TAU * float(corner) / float(count)
		var distance := radius
		if index == 2 and corner % 2 == 1:
			distance *= 0.45
		if index == 4:
			distance *= 1.13
		result.append(center + Vector2.from_angle(angle) * distance)
	return result


## Draws just the silhouette, useful inside a parent's existing button or label.
static func draw_glyph(
	canvas: CanvasItem, center: Vector2, radius: float,
	id: StringName, tint: Color
) -> void:
	var points := polygon(id, center, radius)
	if not points.is_empty():
		canvas.draw_colored_polygon(points, tint)


## Draws a legible stamp with one/two/three shade pips; a concealed badge is a lock.
## Call from _draw(). It never displays a supplied id when neutral is true.
static func draw_badge(
	canvas: CanvasItem, rect: Rect2, id: StringName, neutral := false
) -> void:
	var radius := minf(rect.size.x, rect.size.y) * 0.39
	var center := rect.get_center() - Vector2(0, radius * 0.10)
	var hidden := neutral or not Palette.is_valid(id)
	var tint := NEUTRAL if hidden else Palette.color(id)
	canvas.draw_circle(center + Vector2(0, radius * 0.13), radius * 1.10, INK)
	canvas.draw_circle(center, radius * 1.08, PAPER)
	canvas.draw_circle(center, radius * 0.94, INK)
	if hidden:
		var lock := Rect2(center - Vector2(radius * 0.32, 0), Vector2(
			radius * 0.64, radius * 0.48))
		canvas.draw_arc(center - Vector2(0, radius * 0.02), radius * 0.23,
			PI, TAU, 16, NEUTRAL, maxf(radius * 0.10, 2.0), true)
		canvas.draw_rect(lock, NEUTRAL)
		canvas.draw_circle(center + Vector2(0, radius * 0.16), radius * 0.06, INK)
	else:
		draw_glyph(canvas, center, radius * 0.64, id, tint)
		var shade := Palette.shade_index(id)
		for dot in 3:
			var at := center + Vector2((dot - 1) * radius * 0.37, radius * 0.81)
			canvas.draw_circle(at, radius * 0.105, INK)
			canvas.draw_circle(at, radius * 0.070,
				PAPER if dot <= shade else Color("64848a"))
