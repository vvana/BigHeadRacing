extends Node3D
## Автотест «стрелял по прямой — ракета пролетела сквозь бота» (жалоба
## 31.08, вторая часть). В сетевом пути (отмотка, протокол 13) кузов цели
## считался ТОЧКОЙ-ЦЕНТРОМ с радиусом HIT_R = 1.6: машина длиной ~3.2 м,
## и снаряд, проходящий сквозь её НОС или КОРМУ (дальше 1.6 м от центра),
## «промахивался», хотя на экране прошёл сквозь бампер. Теперь кузов —
## три пробы вдоль курса (центр, ±1.1 м).
##
## Сценарий: жертва СТОИТ, развёрнута поперёк линии огня, центр в 2.0 м
## сбоку от линии, нос воткнут В ЛИНИЮ (кончик в ~0.4 м от неё). Старый
## код: 2.0 > 1.6 — промах. Новый: проба «нос» в 0.9 м — попадание.

const LAG := 0.25
const DIST := 10.0
const SIDE := 2.0

var _main: Node3D
var _shooter: Car
var _victim: Car
var _frame := 0


func _ready() -> void:
	Net.port = 29981   # не мешаем настоящему локальному серверу
	Net.start_server()
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 30:
		_shooter = _main._cars[0]
		_victim = _main._cars[1]
		for i in _main._cars.size():
			var c: Car = _main._cars[i]
			c.controls_enabled = false
			if i > 1:
				c.alive = false
				c.global_position = Vector3(150, 2, 150 + i * 8)
		# Машина живого игрока на сервере — марионетка с доложенным
		# отставанием (протокол 13): включается ручной путь проверки.
		_shooter.net_make_puppet()
		_shooter.net_client_lag = LAG
		var fwd: Vector3 = -_shooter.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var side: Vector3 = _shooter.global_transform.basis.x
		# Центр сбоку от линии огня, нос смотрит В линию.
		_victim.global_transform = Transform3D(
				Basis.looking_at(-side),
				_shooter.global_position + fwd * DIST + side * SIDE)
		_victim.linear_velocity = Vector3.ZERO
		return
	if _shooter == null:
		return
	# Жертве стоять смирно: физика без газа сама её не сдвинет, но пусть
	# скорость не накапливается от случайных сил.
	if _frame < 90:
		_victim.linear_velocity = Vector3.ZERO
	if _frame == 90:
		_shooter.weapon = Weapons.ROCKET
		_shooter.use_weapon()
		return
	if _frame == 120:
		var hit := not _victim.alive or _victim.is_ghost()
		print("ROCKETGRAZE TEST: %s" % ("PASS" if hit
				else "FAIL — ракета прошла сквозь нос кузова (центр в %.1f м от линии)"
				% SIDE))
		get_tree().quit(0 if hit else 1)
