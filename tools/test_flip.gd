extends Node3D
## Автотест: машину переворачивают на крышу посреди трассы.
## Проверяем, что она сама встаёт на колёса и возвращается в игру.

var _main: Node3D
var _frame := 0
var _air_false_positive := false


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_delta: float) -> void:
	_frame += 1
	var car: Car = _main._car
	# Фаза 1 (кадры 200-260): машина кувыркается ВЫСОКО В ВОЗДУХЕ —
	# отсчёт «Перевернулся!» начинаться не должен.
	if _frame == 200:
		car.global_position += Vector3.UP * 6.0
		car.global_transform.basis = car.global_transform.basis.rotated(
				Vector3.FORWARD, PI)
		car.linear_velocity = Vector3.UP * 4.0
	if _frame > 200 and _frame < 260:
		if _main._flip_time[0] > 0.0:
			_air_false_positive = true
	if _frame == 260:
		print("air phase: false_positive=%s (flip_time=%.2f)" % [
			_air_false_positive, _main._flip_time[0]])

	match _frame:
		320:  # фаза 2: лежит на крыше на земле
			var t := car.global_transform
			car.global_transform = Transform3D(
				t.basis.rotated(Vector3.FORWARD, PI), t.origin + Vector3.UP * 0.5)
			car.linear_velocity = Vector3.ZERO
			car.angular_velocity = Vector3.ZERO
			print("flipped on ground: up_dot=%.2f" % car.global_transform.basis.y.dot(Vector3.UP))
		500:  # ~3 с спустя — должна стоять на колёсах
			var up_dot := car.global_transform.basis.y.dot(Vector3.UP)
			var ok := up_dot > 0.8 and not _air_false_positive
			print("FLIP TEST: %s (up_dot=%.2f, air_false_positive=%s)" % [
				"PASS" if ok else "FAIL", up_dot, _air_false_positive])
			get_tree().quit(0 if ok else 1)
