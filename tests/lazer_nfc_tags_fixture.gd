extends "res://games/lazer_nfc/run/tag_bindings.gd"

## Real binding rules with an intercepted save; persistence has separate coverage.

var saves := 0


## Completing a fixture roll call must never write the player's physical tags.
func save_file(_path: String = DEFAULT_PATH) -> Error:
	saves += 1
	return OK
