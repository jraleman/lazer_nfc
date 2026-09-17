extends "res://games/lazer_nfc/input/nfc_source.gd"

## Scene integration fixture; the input tests exercise the native bridge itself.

var adapter_enabled := true
var reader_started := false
var stops := 0


func _ready() -> void:
	pass


## Availability and reader activation are deliberately independent.
func available() -> bool:
	return adapter_enabled


## A scene can only ask for reading, not manufacture a tag event.
func start() -> void:
	reader_started = adapter_enabled


## Records pause/exit cancellation without touching a hardware adapter.
func stop() -> void:
	reader_started = false
	stops += 1
