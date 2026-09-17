extends Control

## Native-resolution, noninteractive colour + shape + shade identity.
## configure(id, neutral) is safe before add_child(); concealment discards the id.

const Palette = preload("res://games/lazer_nfc/run/palette.gd")
const Glyph = preload("res://games/lazer_nfc/ui/shape_glyph.gd")

var color_id: StringName = &""
var neutral := true
var show_label := true
var caption := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	queue_redraw()


## The parent owns placement and size. Shade dots use dark=1, base=2, light=3.
func configure(id: StringName, concealed := false) -> void:
	var next_neutral := concealed or not Palette.is_valid(id)
	var next_id: StringName = &"" if next_neutral else id
	if color_id == next_id and neutral == next_neutral:
		return
	color_id = next_id
	neutral = next_neutral
	tooltip_text = "Recall from memory" if neutral else "%s - %s" % [
		Palette.label(color_id), Palette.symbol(color_id)]
	queue_redraw()


## Optional public-state copy, such as "RECALL 3"; never put a future answer here.
func set_caption(value: String) -> void:
	if caption != value:
		caption = value
		queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var font_size := clampi(roundi(size.x * 0.155), 12, 20)
	var label_height := float(font_size + 8) if show_label else 0.0
	Glyph.draw_badge(self, Rect2(Vector2.ZERO,
		Vector2(size.x, maxf(size.y - label_height, 1.0))), color_id, neutral)
	if not show_label:
		return
	var title := caption
	if title.is_empty():
		title = "RECALL" if neutral else Palette.label(color_id).to_upper()
	draw_string_outline(font, Vector2(0, size.y - 3), title,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, 5, Glyph.INK)
	draw_string(font, Vector2(0, size.y - 3), title,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, Glyph.PAPER)
