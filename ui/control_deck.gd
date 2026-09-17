extends PanelContainer

## Native-resolution keys sit outside the 3D viewport and never reveal recall.

signal color_pressed(color_id: StringName)
signal start_requested
signal skip_requested
signal fallback_requested
signal practice_toggled(enabled: bool)

const Palette = preload("res://games/lazer_nfc/run/palette.gd")
const Glyph = preload("res://games/lazer_nfc/ui/shape_glyph.gd")
const INK := Color("102632")
const PAPER := Color("fff0cd")

var _layout: VBoxContainer
var _status: Label
var _actions: HBoxContainer
var _start: Button
var _practice: Button
var _skip: Button
var _fallback: Button
var _pad: GridContainer
var _shade_row: HBoxContainer
var _keys: Array[ColorKey] = []
var _shade_buttons: Array[Button] = []
var _labels: Array[String] = []
var _available: Array[StringName] = []
var _active: Array[StringName] = []
var _shade := 1
var _shades := false
var _binding := false
var _ready_mode := true
var _pad_visible := true
var _ui_scale := 1.0
var _confirmation := "Space"
var _dark_key := "Q"
var _light_key := "E"


class ColorKey extends Button:
	## Lettering and a geometric badge supplement the colour on every key.
	var hue: StringName
	var color_id: StringName
	var binding_label := ""
	var ui_scale := 1.0

	func _draw() -> void:
		var alpha := 0.38 if disabled else 1.0
		var compact := size.x < 116.0 * ui_scale
		var center := Vector2(size.x * 0.5, 18.0 * ui_scale) if compact \
			else Vector2(32.0 * ui_scale, size.y * 0.5)
		var radius := minf((11.0 if compact else 17.0) * ui_scale, size.y * 0.26)
		var tint := Palette.color(color_id)
		tint.a = alpha
		draw_circle(center, radius + 5.0 * ui_scale, Color(0.02, 0.08, 0.12, alpha))
		Glyph.draw_glyph(self, center, radius, color_id, tint)
		var font := get_theme_font("font")
		var x := (6.0 if compact else 60.0) * ui_scale
		var width := size.x - x - 6.0 * ui_scale
		var alignment := HORIZONTAL_ALIGNMENT_CENTER if compact else HORIZONTAL_ALIGNMENT_LEFT
		var name_y := 52.0 * ui_scale if compact else size.y * 0.46
		var key_y := 70.0 * ui_scale if compact else size.y * 0.74
		draw_string(font, Vector2(x, name_y), str(hue).capitalize(),
			alignment, width, roundi((14.0 if compact else 17.0) * ui_scale),
			Color(1.0, 0.94, 0.81, alpha))
		draw_string(font, Vector2(x, key_y), binding_label,
			alignment, width, roundi((11.0 if compact else 14.0) * ui_scale),
			Color(0.65, 0.84, 0.87, alpha))


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := StyleBoxFlat.new()
	panel.bg_color = INK
	panel.border_color = Color("3a646c")
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(18)
	panel.content_margin_left = 16
	panel.content_margin_right = 16
	panel.content_margin_top = 12
	panel.content_margin_bottom = 12
	add_theme_stylebox_override("panel", panel)
	_layout = VBoxContainer.new()
	_layout.add_theme_constant_override("separation", 10)
	add_child(_layout)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", PAPER)
	_layout.add_child(_status)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	_layout.add_child(_actions)
	_start = _button("Start experiment", _actions)
	_start.pressed.connect(func() -> void: start_requested.emit())
	_practice = _button("Learn the sounds", _actions)
	_practice.toggle_mode = true
	_practice.toggled.connect(func(enabled: bool) -> void: practice_toggled.emit(enabled))
	_skip = _button("Skip this tag", _actions)
	_skip.pressed.connect(func() -> void: skip_requested.emit())
	_fallback = _button("Use keys / touch", _actions)
	_fallback.pressed.connect(func() -> void: fallback_requested.emit())
	_pad = GridContainer.new()
	_pad.columns = 7
	_pad.add_theme_constant_override("h_separation", 8)
	_pad.add_theme_constant_override("v_separation", 8)
	_layout.add_child(_pad)
	for hue: StringName in Palette.HUES:
		var key := ColorKey.new()
		key.hue = hue
		key.color_id = hue
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key.custom_minimum_size = Vector2(88, 68)
		# These have declared keyboard actions; Space must remain the run action.
		key.focus_mode = Control.FOCUS_NONE
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color("1a3948")
		normal.border_color = Palette.color(hue).darkened(0.35)
		normal.set_border_width_all(2)
		normal.set_corner_radius_all(10)
		key.add_theme_stylebox_override("normal", normal)
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color("284d5b")
		hover.border_color = Palette.color(hue)
		key.add_theme_stylebox_override("hover", hover)
		var pressed := hover.duplicate() as StyleBoxFlat
		pressed.bg_color = Color("376572")
		key.add_theme_stylebox_override("pressed", pressed)
		key.add_theme_stylebox_override("disabled", normal)
		key.pressed.connect(_on_color_pressed.bind(hue))
		_pad.add_child(key)
		_keys.append(key)
	_shade_row = HBoxContainer.new()
	_shade_row.add_theme_constant_override("separation", 8)
	_layout.add_child(_shade_row)
	for i in 3:
		var button := _button(["Dark", "Base", "Light"][i], _shade_row)
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_select_shade.bind(i))
		_shade_buttons.append(button)
	resized.connect(_resize)
	_sync_visibility()
	_resize()


## Labels arrive from Settings, so rebinding never leaves a stale keycap.
func configure(
	key_labels: Array[String], confirmation: String, dark: String, light: String,
	shades: bool, show_pad: bool, available: Array[StringName]
) -> void:
	_labels = key_labels.duplicate()
	_confirmation = confirmation
	_dark_key = dark
	_light_key = light
	_shades = shades
	_pad_visible = show_pad
	_available = available.duplicate()
	if not shades:
		_shade = 1
	if not is_node_ready():
		return
	_start.text = "Start experiment  [%s]" % confirmation
	_start.tooltip_text = _start.text
	_shade_buttons[0].text = "Dark  [%s]" % dark
	_shade_buttons[1].text = "Base"
	_shade_buttons[2].text = "Light  [%s]" % light
	_shade_buttons[0].tooltip_text = "Hold %s with a colour key, or select dark touch answers." % dark
	_shade_buttons[2].tooltip_text = "Hold %s with a colour key, or select light touch answers." % light
	_update_keys()
	_sync_visibility()
	_resize()


## Only the palette is public in recall; no secret sequence enters this view.
func present(snapshot: Dictionary, message: String) -> void:
	_ready_mode = StringName(snapshot.get("state", &"READY")) == &"READY"
	_active.assign(snapshot.get("active_palette", []))
	if not is_node_ready():
		return
	_status.text = message
	_sync_visibility()
	_update_keys()


## Physical setup always includes an immediate hardware-free exit.
func set_binding(active: bool, message := "") -> void:
	_binding = active
	if not is_node_ready():
		return
	if active:
		_status.text = message
	_sync_visibility()


## Cosmetic practice never marks a run assisted or consumes a life.
func set_practice(enabled: bool) -> void:
	if _practice != null:
		_practice.set_pressed_no_signal(enabled)


## Sizes are in the same scaled canvas coordinates as the inherited HUD.
func set_ui_scale(value: float) -> void:
	_ui_scale = value
	if is_node_ready():
		_resize()


## Used by the parent when reserving the deck's responsive space.
func preferred_height(width: float) -> float:
	var columns := _columns_for_width(width)
	var rows := ceili(7.0 / columns)
	var height := 58.0
	if _ready_mode or _binding:
		height += 54.0
	if _pad_visible and not _binding:
		height += rows * (_key_height(width, columns) + 8.0)
		if _shades:
			height += 54.0
	return height * _ui_scale


func _button(title: String, parent: Container) -> Button:
	var button := Button.new()
	button.text = title
	button.clip_text = true
	button.custom_minimum_size.y = 44
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The declared run action owns Space, even after a practice or fallback click.
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button


func _on_color_pressed(hue: StringName) -> void:
	color_pressed.emit(Palette.id_for(hue, _shade))


func _select_shade(index: int) -> void:
	_shade = index
	_update_keys()


func _update_keys() -> void:
	for i in _keys.size():
		var key := _keys[i]
		key.color_id = Palette.id_for(key.hue, _shade)
		key.binding_label = "[%s]" % _labels[i] if i < _labels.size() else ""
		key.tooltip_text = "%s - %s" % [Palette.label(key.color_id), key.binding_label]
		var allowed := _available if _ready_mode else _active
		key.disabled = not allowed.has(key.color_id)
		key.queue_redraw()
	for i in _shade_buttons.size():
		_shade_buttons[i].set_pressed_no_signal(i == _shade)


func _sync_visibility() -> void:
	_start.visible = _ready_mode and not _binding
	_practice.visible = _ready_mode and not _binding
	_skip.visible = _binding
	_fallback.visible = _binding
	_actions.visible = _ready_mode or _binding
	_pad.visible = _pad_visible and not _binding
	_shade_row.visible = _pad_visible and _shades and not _binding


func _resize() -> void:
	_pad.columns = _columns_for_width(size.x)
	var compact := size.x < 640.0 * _ui_scale
	_start.text = ("%s  [%s]" % [
		"Start" if compact else "Start experiment", _confirmation
	])
	_practice.text = "Learn sounds" if compact else "Learn the sounds"
	_skip.text = "Skip colour" if compact else "Skip this tag"
	_fallback.text = "Keys / touch" if compact else "Use keys / touch"
	_shade_buttons[0].text = "Dark" if compact else "Dark  [%s]" % _dark_key
	_shade_buttons[2].text = "Light" if compact else "Light  [%s]" % _light_key
	_status.add_theme_font_size_override("font_size", roundi(18 * _ui_scale))
	for key in _keys:
		key.ui_scale = _ui_scale
		key.custom_minimum_size = Vector2(88, _key_height(size.x, _pad.columns)) * _ui_scale
		key.queue_redraw()
	for button: Button in [_start, _practice, _skip, _fallback] + _shade_buttons:
		button.add_theme_font_size_override("font_size", roundi(17 * _ui_scale))
		button.custom_minimum_size.y = 44.0 * _ui_scale


func _columns_for_width(width: float) -> int:
	var maximum := 4 if width < 1120.0 * _ui_scale else 7
	return clampi(floori((width - 24.0) / (88.0 * _ui_scale + 8.0)), 1, maximum)


func _key_height(width: float, columns: int) -> float:
	var key_width := (width - 32.0 - (columns - 1) * 8.0) / columns
	return 76.0 if key_width < 116.0 * _ui_scale else 68.0
