extends Node3D
## Автотест «нырок носом»: машина падает носом вниз (35°) на 18 м/с.
## Раньше удар носом о землю отталкивал её назад, а защита скорости
## подхватывала уже РАЗВЁРНУТУЮ скорость — машина уезжала задним ходом.
## Критерий: через ~1.5 с после нырка скорость ВДОЛЬ исходного курса
## положительная и не меньше 5 м/с (едет вперёд, не назад).

var _main: Node3D
var _frame := 0
var _fwd0 := Vector3.ZERO


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_delta: float) -> void:
	_frame += 1
	var car: Car = _main._car
	if _frame == 160:
		# Гонка идёт; ставим машину в пикирование.
		var fwd := -car.global_transform.basis.z
		fwd.y = 0.0
		_fwd0 = fwd.normalized()
		var dive := (_fwd0 * cos(deg_to_rad(35.0))
				- Vector3.UP * sin(deg_to_rad(35.0))).normalized()
		car.global_position.y += 4.0
		car.global_transform.basis = Basis.looking_at(dive)
		car.linear_velocity = dive * 18.0
		car.angular_velocity = Vector3.ZERO
	elif _frame == 250:
		var along := car.linear_velocity.dot(_fwd0)
		var ok := along > 5.0
		print("DIVE TEST: %s (скорость по курсу после нырка: %.1f м/с, лимит 5)" % [
			"PASS" if ok else "FAIL", along])
		get_tree().quit(0 if ok else 1)
