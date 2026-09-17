extends RefCounted

## Stable instruments shared by physical tags, declared keys and presentation.

const HUES: Array[StringName] = [
	&"red", &"orange", &"yellow", &"green", &"blue", &"indigo", &"violet",
]
const GROWTH_ORDER: Array[StringName] = [
	&"red", &"yellow", &"green", &"blue", &"orange", &"indigo", &"violet",
]
const SHAPES: Array[StringName] = [
	&"triangle", &"diamond", &"star", &"circle", &"square", &"hexagon", &"plus",
]
const MIDI: Array[int] = [48, 52, 55, 60, 64, 67, 72]
const COLORS: Array[Color] = [
	Color("ef4856"), Color("f58b38"), Color("f6d447"), Color("45bc7a"),
	Color("429aea"), Color("6553ba"), Color("bc59d1"),
]


## An unknown instrument is transparent, never silently substituted with red.
static func color(id: StringName) -> Color:
	var index := HUES.find(hue_id(id))
	if index < 0:
		return Color.TRANSPARENT
	var base := COLORS[index]
	match shade_index(id):
		0:
			return base.darkened(0.4)
		2:
			return base.lightened(0.45)
	return base


## Names explicitly distinguish shades even without colour vision.
static func label(id: StringName) -> String:
	var hue := hue_id(id)
	if hue.is_empty():
		return "Unknown colour"
	var name_text := String(hue).capitalize()
	match shade_index(id):
		0:
			return "Dark %s" % String(hue)
		2:
			return "Light %s" % String(hue)
	return name_text


## ASCII shape names remain readable when the current font lacks icon glyphs.
static func symbol(id: StringName) -> String:
	var index := HUES.find(hue_id(id))
	if index < 0:
		return "?"
	return String(SHAPES[index]).capitalize()


## Empty means invalid; suffixes must be exact rather than loosely prefix-matched.
static func hue_id(id: StringName) -> StringName:
	if HUES.has(id):
		return id
	var text := String(id)
	for suffix: String in ["_dark", "_light"]:
		if text.ends_with(suffix):
			var hue := StringName(text.trim_suffix(suffix))
			if HUES.has(hue):
				return hue
	return &""


## Dark / base / light are 0 / 1 / 2; -1 explicitly denotes an invalid id.
static func shade_index(id: StringName) -> int:
	if not is_valid(id):
		return -1
	if String(id).ends_with("_dark"):
		return 0
	if String(id).ends_with("_light"):
		return 2
	return 1


## Invalid hues or shade indices return the invalid, empty id.
static func id_for(hue: StringName, shade: int = 1) -> StringName:
	if not HUES.has(hue) or shade < 0 or shade > 2:
		return &""
	if shade == 0:
		return StringName("%s_dark" % hue)
	if shade == 2:
		return StringName("%s_light" % hue)
	return hue


## Spectrum order stays fixed; advanced mode lists dark / base / light per hue.
static func all_ids(shades: bool = false) -> Array[StringName]:
	var result: Array[StringName] = []
	for hue: StringName in HUES:
		if shades:
			for shade in 3:
				result.append(id_for(hue, shade))
		else:
			result.append(hue)
	return result


## Recognises only the seven base ids and their fourteen documented shades.
static func is_valid(id: StringName) -> bool:
	return not hue_id(id).is_empty()


## Shade timbres also move one semitone, never into another hue's octave.
static func midi_note(id: StringName) -> int:
	var index := HUES.find(hue_id(id))
	if index < 0:
		return -1
	return MIDI[index] + shade_index(id) - 1
