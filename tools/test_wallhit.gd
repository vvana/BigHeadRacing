extends Node3D
## Удары в стену под крутыми углами: машина влетает в ограждение на
## 20 м/с под 55..85°. После контакта скорость ВДОЛЬ трассы не должна
## развернуться против носа машины (баг «внезапно меняет направление»).

var _main: Node3D
var _frame := 0
var _angles: Array = [55.0, 65.0, 75.0, 82.0, 88.0]
var _idx := 0
var _launch_frame := 0
var _along_sign0 := 0.0
var _bad := 0
var _worst := 0.0


func _ready() -> void:
	seed(7)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _tangent_at(pos: Vector3) -> Vector3:
	var curve: Curve3D = _main._track._curve
	var off := curve.get_closest_offset(pos)
	var t: Vector3 = curve.sample_baked(
			fposmod(off + 0.5, curve.get_baked_length())) \
			- curve.sample_baked(off)
	t.y = 0.0
	return t.normalized()


func _physics_process(_d: float) -> void:
	_frame += 1
	var car: Car = _main._car
	if _frame == 5:
		for i in range(1, _main._cars.size()):
			var extra: Car = _main._cars[i]
			extra.controls_enabled = false
			extra.alive = false  # и от автовозврата на трассу
			extra.weapon = -1
			extra.global_transform = Transform3D(Basis.IDENTITY,
					Vector3(110.0 + i * 6.0, 2.0, 110.0))
			extra.linear_velocity = Vector3.ZERO
	if _frame < 30:
		return
	if _launch_frame == 0:
		# Пуск в стену со стартовой прямой под нужным углом.
		var curve: Curve3D = _main._track._curve
		var off := curve.get_baked_length() * 0.05
		var pos := curve.sample_baked(off)
		var tangent := _tangent_at(pos)
		var side := tangent.cross(Vector3.UP).normalized()
		var a: float = _angles[_idx]
		var dir := (tangent * cos(deg_to_rad(a))
				+ side * sin(deg_to_rad(a))).normalized()
		car.global_transform = Transform3D(
				Basis.looking_at(dir), pos + Vector3.UP * 0.62)
		car.linear_velocity = dir * 20.0
		car.angular_velocity = Vector3.ZERO
		_along_sign0 = signf(car.linear_velocity.dot(tangent))
		_launch_frame = _frame
	elif _frame - _launch_frame < 75:
		# 1.25 с после пуска: скорость вдоль трассы против исходного
		# хода — разворот.
		var along := car.linear_velocity.dot(_tangent_at(car.global_position))
		var back := -along * _along_sign0
		if back > _worst:
			_worst = back
		if back > 3.0:
			_bad += 1
			print("BACKWARD угол=%.0f° f=%d вдоль=%.1f (знак пуска %.0f)" % [
					_angles[_idx], _frame - _launch_frame, along, _along_sign0])
	else:
		print("угол %.0f°: худший «назад» %.1f м/с" % [_angles[_idx], _worst])
		_idx += 1
		_worst = 0.0
		_launch_frame = 0
		if _idx >= _angles.size():
			print("WALLHIT: bad_frames=%d" % _bad)
			get_tree().quit(0 if _bad == 0 else 1)
