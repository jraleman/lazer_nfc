extends RefCounted

## The fallback uses the live InputMap, never saved keycodes or synthetic tag UIDs.

const Palette = preload("res://games/lazer_nfc/run/palette.gd")
const OPTIONS = preload("res://games/lazer_nfc/lazer_nfc_options.gd")
const DARK_ACTION: StringName = OPTIONS.DARK_ACTION
const LIGHT_ACTION: StringName = OPTIONS.LIGHT_ACTION
const CONFIRM_ACTION: StringName = OPTIONS.CONFIRM_ACTION


## Both held shade actions deliberately cancel to the base colour.
func color_from_event(event: InputEvent, shade_mode: bool) -> StringName:
	if not event.is_pressed() or event.is_echo():
		return &""
	for index in Palette.HUES.size():
		var action: StringName = OPTIONS.COLOR_ACTIONS[index]
		if not InputMap.has_action(action) or not InputMap.event_is_action(event, action):
			continue
		var shade := 1
		if shade_mode:
			var dark := InputMap.has_action(DARK_ACTION) and Input.is_action_pressed(DARK_ACTION)
			var light := InputMap.has_action(LIGHT_ACTION) and Input.is_action_pressed(LIGHT_ACTION)
			if dark != light:
				shade = 0 if dark else 2
		return Palette.id_for(Palette.HUES[index], shade)
	return &""


## Confirm starts immediately, without passing through an NFC gesture delay.
func confirm_pressed(event: InputEvent) -> bool:
	return (
		event.is_pressed() and not event.is_echo()
		and InputMap.has_action(CONFIRM_ACTION)
		and InputMap.event_is_action(event, CONFIRM_ACTION)
	)
