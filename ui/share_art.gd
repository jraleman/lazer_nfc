extends Control

## The shared scorecard owns titles, stats and QR. This is only our original portrait.
## No world, input, sound, game state or additional scorecard is started for a share.


## Accepts the common art hook without modifying or retaining the caller's score data.
func configure(_data: Dictionary) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
