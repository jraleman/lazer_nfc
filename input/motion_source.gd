extends RefCounted

## Optional linear acceleration only adds momentum; absent sensors remain neutral.

var _peak := 0.0


## The gameplay clock owns sampling, so paused and menu motion cannot earn a bonus.
func sample() -> void:
	var linear := Input.get_accelerometer() - Input.get_gravity()
	if linear.is_finite():
		_peak = maxf(_peak, linear.length())


## Consume one answer's peak so it cannot be reused for another answer.
func take_peak() -> float:
	var peak := _peak
	reset()
	return peak


## Audio may follow momentum without consuming the answer's measurement.
func peek_peak() -> float:
	return _peak


## A new run or resumed window starts without pre-pause motion.
func reset() -> void:
	_peak = 0.0
