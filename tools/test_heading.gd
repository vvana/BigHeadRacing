extends Node3D
## Автотест лимита разворота: машина не должна отклоняться от направления
## трассы больше чем на max_track_angle_deg (80°).
## Фаза 1: машину ставят задом наперёд (180°) — кламп должен довернуть.
## Фаза 2: 2 секунды каждый кадр насильно крутим рысканье (6 рад/с) —
## угол не должен выходить за предел ни на одном кадре.

var _main: Node3D
var _frame := 0
var _max_angle := 0.0
var _flipped_back := false


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _angle_to_track() -> float:
	var car: Car = _main._car
	var track: TrackBuilder = _main._track
	var curve: Curve3D = track._curve
	var off := curve.get_closest_offset(car.global_position)
	var tangent := curve.sample_baked(fposmod(off + 0.5, curve.get_baked_length())) \
			- curve.sample_baked(off)
	tangent.y = 0.0
	var fwd := -car.global_transform.basis.z
	fwd.y = 0.0
	return rad_to_deg(tangent.angle_to(fwd))


func _physics_process(_delta: float) -> void:
	_frame += 1
	var car: Car = _main._car
	match _frame:
		30:
			# Фаза 1: разворачиваем задом наперёд.
			car.rotate(Vector3.UP, PI)
			car.linear_velocity = Vector3.ZERO
			car.angular_velocity = Vector3.ZERO
		35:
			var a := _angle_to_track()
			_flipped_back = a <= car.max_track_angle_deg + 1.0
			print("после разворота на 180°: %.1f° (лимит %.0f°) — %s" % [
				a, car.max_track_angle_deg,
				"довернуло" if _flipped_back else "НЕ довернуло"])
	# Фаза 2: с 40-го кадра 2 секунды крутим насильно.
	if _frame >= 40 and _frame < 160:
		car.angular_velocity.y = 6.0
		_max_angle = maxf(_max_angle, _angle_to_track())
	if _frame == 165:
		var ok := _flipped_back and _max_angle <= car.max_track_angle_deg + 1.0
		print("HEADING TEST: %s (макс. угол при закрутке %.1f°, лимит %.0f°)" % [
			"PASS" if ok else "FAIL", _max_angle, car.max_track_angle_deg])
		get_tree().quit(0 if ok else 1)
