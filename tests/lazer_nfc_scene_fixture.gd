extends "res://games/lazer_nfc/gameplay.gd"

## Exercise the shipped scene without writing the player's achievement file.

var recorded_count := 0
var unlocked_ids: Array[String] = []


func _record_round(_one: int, _two: int) -> String:
	recorded_count += 1
	return ""


func _unlock_round_achievement(id: String) -> void:
	if not unlocked_ids.has(id):
		unlocked_ids.append(id)
