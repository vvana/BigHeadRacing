extends Node3D
## Автотест проезда трамплина: машина стартует за 10 м до первого трамплина
## (доля 0.12 длины трассы), газ в пол на 6 секунд. PASS — уехала дальше
## трамплина, STUCK — стоит. Запуск:
## godot --headless --path . tools/TestRamp.tscn --quit-after 999999

var _car: Car
var _track: TrackBuilder
var _t := 0.0
var _ramp_offset := 0.0


func _ready() -> void:
	_track = TrackBuilder.new()
	add_child(_track)

	var curve: Curve3D = _track._curve
	var length := curve.get_baked_length()
	_ramp_offset = length * 0.12
	var start := fposmod(_ramp_offset - 10.0, length)

	_car = Car.new()
	_car.controls_enabled = true
	var pos := curve.sample_baked(start)
	var ahead := curve.sample_baked(fposmod(start + 3.0, length))
	_car.transform = Transform3D(
		Basis.looking_at((ahead - pos).normalized()), pos + Vector3(0, 1.0, 0))
	add_child(_car)

	Input.action_press("accelerate")


var _next_log := 0.0
var _max_off := 0.0

func _physics_process(delta: float) -> void:
	_t += delta
	# Тест газует без руля и после трамплина может отскочить от стены
	# поворота — поэтому важен максимум пройденного, а не финальная точка.
	_max_off = maxf(_max_off, _track._curve.get_closest_offset(
			_car.global_position))
	if _t >= _next_log:
		_next_log += 1.0
		var c: Curve3D = _track._curve
		print("t=%.0f offset=%.1f speed=%.1f pos=%s" % [
			_t, c.get_closest_offset(_car.global_position),
			_car.linear_velocity.length(), _car.global_position])
	if _t < 6.0:
		return
	var speed := _car.linear_velocity.length()
	var passed := _max_off > _ramp_offset + 3.0
	print("RAMP TEST: %s (max_offset %.1f, ramp %.1f, speed %.1f m/s)" % [
		"PASS" if passed else "STUCK", _max_off, _ramp_offset, speed])
	get_tree().quit(0 if passed else 1)
