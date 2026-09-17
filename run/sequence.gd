extends RefCounted

## A private seeded generator; retries never depend on frame rate or global RNG.

const OPTIONS := preload("res://games/lazer_nfc/lazer_nfc_options.gd")
const PALETTE := preload("res://games/lazer_nfc/run/palette.gd")

var _rng := RandomNumberGenerator.new()


## Zero is a real reproducible seed, not a request to read the wall clock.
func reset(seed_value: int = 0) -> void:
	_rng.seed = seed_value


## Grows the learned pattern, then rolls it at the cap to keep experts learning.
func grow(
	previous: Array[StringName], length: int,
	palette: Array[StringName], round_n: int
) -> Array[StringName]:
	if length < OPTIONS.MIN_START_LENGTH or length > OPTIONS.SEQ_LEN_MAX \
			or previous.size() > length or round_n < 1 or palette.is_empty():
		push_error("LaZer NFC sequence: invalid length, round or empty palette.")
		return []
	for id: StringName in palette:
		if not PALETTE.is_valid(id) or palette.count(id) != 1:
			push_error("LaZer NFC sequence: palette ids must be valid and unique.")
			return []
	for id: StringName in previous:
		if not palette.has(id):
			push_error("LaZer NFC sequence: the learned prefix needs an unavailable tag.")
			return []
	if round_n < OPTIONS.ALLOW_REPEAT_FROM_ROUND and palette.size() < 2:
		push_error("LaZer NFC sequence: early rounds need two distinct instruments.")
		return []
	var result := previous.duplicate()
	var rolling := result.size() == OPTIONS.SEQ_LEN_MAX
	if rolling:
		result.remove_at(0)
	while result.size() < length:
		var candidates := palette.duplicate()
		if (round_n < OPTIONS.ALLOW_REPEAT_FROM_ROUND or rolling) and not result.is_empty() \
				and candidates.size() > 1:
			candidates.erase(result.back())
		result.append(candidates[_rng.randi_range(0, candidates.size() - 1)])
	return result
