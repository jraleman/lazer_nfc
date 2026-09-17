extends Control

## Crisp readouts stay outside the 3D texture: one visible note, numbered progress,
## and the actual shrinking response ratio. No colours are stored in progress cells.

const Palette = preload("res://games/lazer_nfc/run/palette.gd")
const Badge = preload("res://games/lazer_nfc/ui/color_badge.gd")
const INK := Color("173743")
const PAPER := Color("fff2d4")
const MINT := Color("9ce6cf")
const MUTED := Color("97b8bf")

var badge: Badge
var _snapshot: Dictionary = {"state": &"READY"}
var _identity: StringName = &""
var _message := ""
var _success := false
var _panel: StyleBoxFlat
var _cell: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = StyleBoxFlat.new()
	_panel.bg_color = Color(0.045, 0.115, 0.15, 0.91)
	_panel.border_color = Color(0.62, 0.83, 0.80, 0.24)
	_panel.set_border_width_all(1)
	_panel.set_corner_radius_all(14)
	_cell = StyleBoxFlat.new()
	_cell.set_corner_radius_all(6)
	_cell.set_border_width_all(1)
	badge = Badge.new()
	badge.name = "CurrentNoteBadge"
	badge.show_label = false
	add_child(badge)
	resized.connect(_layout)
	_layout()


## Pass only the public, whitelisted snapshot assembled by arena.gd.
func present(snapshot: Dictionary, identity: StringName, message: String, success: bool) -> void:
	_snapshot = snapshot
	_identity = identity
	_message = message
	_success = success
	if not is_node_ready():
		return
	badge.configure(identity, identity.is_empty())
	badge.visible = StringName(snapshot.get("state", &"READY")) != &"READY" \
		or not identity.is_empty()
	_layout()


## These bands are reserved by the 3D framing, including at very short heights.
func top_height() -> float:
	return 58.0 if size.y >= 230.0 else 48.0


## Portrait uses a separate window row rather than squeezing twelve unreadable cells.
func bottom_height() -> float:
	if StringName(_snapshot.get("state", &"READY")) == &"READY":
		return 49.0 if size.y >= 230.0 else 0.0
	return 83.0 if size.x < 600.0 and size.y >= 230.0 else 61.0


## Actual native rectangles, used by the graphics regression instead of magic margins.
func native_rects() -> Array[Rect2]:
	var result: Array[Rect2] = [
		Rect2(Vector2(8, 4), Vector2(maxf(size.x - 16, 1), top_height() - 4)),
	]
	if bottom_height() > 0.0:
		result.append(Rect2(Vector2(8, size.y - bottom_height()),
			Vector2(maxf(size.x - 16, 1), bottom_height() - 4)))
	if badge != null and badge.visible:
		result.append(Rect2(badge.position, badge.size))
	return result


func _layout() -> void:
	if badge != null:
		badge.position = Vector2(13, 3)
		badge.size = Vector2(top_height() - 3, top_height() - 3)
	queue_redraw()


func _draw() -> void:
	if _panel == null or size.x < 24 or size.y < 24:
		return
	var state := StringName(_snapshot.get("state", &"READY"))
	var round_n := int(_snapshot.get("round", 0))
	var length := maxi(int(_snapshot.get("length", 0)), 0)
	var recall := int(_snapshot.get("recall_index", 0))
	var showing := int(_snapshot.get("show_index", -1))
	var is_recall := state == &"AWAITING" or state == &"RECALL_GAP"
	var top := top_height()
	var footer := size.y - bottom_height()
	draw_style_box(_panel, Rect2(8, 4, size.x - 16, top - 4))
	if bottom_height() > 0.0:
		draw_style_box(_panel, Rect2(8, footer, size.x - 16, bottom_height() - 4))
	var x := top + 16.0 if badge.visible else 22.0
	var title_width := maxf(size.x - x - 102.0, 30.0)
	var phase := "YOUR POCKET MEMORY LAB"
	var title := "Make a little magic."
	match state:
		&"ROUND_START":
			phase = "ONE MORE BRIGHT IDEA"
			title = "%d robots to remember" % length
		&"SHOWING", &"SHOW_END":
			phase = "WATCH + LISTEN"
			title = Palette.label(_identity) if not _identity.is_empty() else "Remember the pattern"
		&"AWAITING", &"RECALL_GAP":
			phase = "YOUR TURN"
			title = Palette.label(_identity) if not _identity.is_empty() \
				else "Recall %d of %d" % [mini(recall + 1, length), length]
		&"ROUND_WON":
			phase = "EXPERIMENT SUCCESSFUL"
			title = "Clean sweep!" if _success else "Lovely recall!"
		&"RUN_OVER":
			phase = "THANKS, LAB PARTNER"
			title = "A brilliant experiment."
	if state == &"READY" and not _identity.is_empty():
		phase = "MEET THE COLOURS"
		title = Palette.label(_identity)
	_text(phase, Vector2(x, 21 if top > 50 else 18), 11, MUTED, title_width)
	_text(title, Vector2(x, 44 if top > 50 else 37),
		19 if size.x > 460 else 16, PAPER, title_width)
	var chip := Rect2(size.x - 94, 12, 72, top - 20)
	_cell.bg_color = Color("2a545b")
	_cell.border_color = Color("54817f")
	draw_style_box(_cell, chip)
	_text("R%02d" % maxi(round_n, 1), chip.position + Vector2(0, 20),
		17, PAPER, chip.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var combo := int(_snapshot.get("combo", 0))
	if top > 50:
		_text("COMBO %d" % combo if combo > 0 else "LET'S PLAY",
			chip.position + Vector2(0, 32), 9, MINT, chip.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if state == &"READY":
		if bottom_height() == 0.0:
			return
		_text("Start below, or try a colour.", Vector2(20, footer + 24),
			16 if size.x > 420 else 14, PAPER, size.x - 40, HORIZONTAL_ALIGNMENT_CENTER)
		var center := Vector2(size.x * 0.5, footer + 35)
		draw_polyline(PackedVector2Array([
			center + Vector2(-5, -3), center + Vector2(0, 1), center + Vector2(5, -3),
		]), MINT, 2.0, true)
		return
	_draw_progress(state, length, recall, showing, footer, is_recall)
	if not _message.is_empty() and size.y >= 260:
		var font := get_theme_default_font()
		var font_size := 17 if size.x >= 600 else 14
		var width := minf(font.get_string_size(_message, HORIZONTAL_ALIGNMENT_LEFT,
			-1, font_size).x + 40, size.x - 42)
		var toast := Rect2((size.x - width) * 0.5, footer - 40, width, 30)
		_cell.bg_color = Color("fff0cd") if _success else Color("244650")
		_cell.border_color = Color("f4cc76") if _success else Color("709a9c")
		draw_style_box(_cell, toast)
		_text(_message, toast.position + Vector2(10, 21), font_size,
			INK if _success else PAPER, width - 20, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_progress(
	state: StringName, length: int, recall: int, showing: int,
	footer: float, is_recall: bool
) -> void:
	var count := clampi(length, 1, 12)
	var narrow := size.x < 600.0 and size.y >= 230.0
	var progress_width := size.x - 44 if narrow else (size.x - 62) * 0.68
	var passed := recall if is_recall or state == &"RUN_OVER" else maxi(showing, 0)
	if state == &"ROUND_WON":
		passed = length
	var status := "PROGRESS" if is_recall or state == &"ROUND_WON" else "PATTERN"
	_text("%s  %02d / %02d" % [status, clampi(passed, 0, length), length],
		Vector2(22, footer + 16), 11, MUTED, progress_width)
	var gap := 4.0
	var cell_width := minf((progress_width - gap * (count - 1)) / count, 37.0)
	for index in count:
		var done := index < passed
		var current := index == (recall if is_recall else showing)
		_cell.bg_color = Color("9ddcca") if done else Color("234650")
		_cell.border_color = PAPER if current else Color("5d838a")
		var rect := Rect2(22 + index * (cell_width + gap), footer + 23, cell_width, 23)
		draw_style_box(_cell, rect)
		_text(str(index + 1), rect.position + Vector2(0, 16), 12,
			INK if done else PAPER, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var at := Vector2(22, footer + 58) if narrow \
		else Vector2(progress_width + 42, footer + 16)
	var width := size.x - 44 if narrow else size.x - at.x - 22
	var ratio := clampf(float(_snapshot.get("window_ratio", 0.0)), 0.0, 1.0)
	var window_title := "WINDOW  %d%%" % ceili(ratio * 100.0) if state == &"AWAITING" \
		else ("ROUND COMPLETE" if state == &"ROUND_WON" else "LISTEN FIRST")
	if state == &"RECALL_GAP":
		window_title = "NEXT ROBOT..."
	elif state == &"RUN_OVER":
		window_title = "ALL DONE"
	_text(window_title, at, 11, PAPER, width)
	var bar := Rect2(at + Vector2(0, 8), Vector2(width, 8 if narrow else 11))
	_cell.bg_color = Color("30535a")
	_cell.border_color = Color("54747a")
	draw_style_box(_cell, bar)
	var amount := ratio if state == &"AWAITING" else 0.0
	if state == &"ROUND_WON":
		amount = 1.0
	if amount > 0.0:
		_cell.bg_color = Color("f2c977") if amount < 0.25 else MINT
		_cell.border_color = _cell.bg_color
		draw_style_box(_cell, Rect2(bar.position, Vector2(bar.size.x * amount, bar.size.y)))


func _text(
	value: String, at: Vector2, font_size: int, tint: Color,
	width: float, alignment := HORIZONTAL_ALIGNMENT_LEFT
) -> void:
	var font := get_theme_default_font()
	var display := value
	while display.length() > 1 and font.get_string_size(display, alignment, -1, font_size).x > width:
		display = display.left(display.length() - 1)
	if display != value and display.length() > 3:
		display = display.left(display.length() - 3) + "..."
	draw_string(font, at, display, alignment, width, font_size, tint)
