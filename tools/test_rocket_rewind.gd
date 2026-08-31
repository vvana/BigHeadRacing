extends Node3D
## Автотест ОТМОТКИ ДЛЯ СНАРЯДОВ (протокол 13, жалоба 28.08 «оружие
## пролетает сквозь даже ботов»). Игрок целится по СВОЕМУ экрану, где
## соперники нарисованы с отставанием буфера; сервер же считал попадание
## по «сейчас», и на 25-30 м/с расхождение — метры. Лазер отматывали с
## 27.08, снаряды — нет.
##
## Сценарий подобран так, чтобы РАЗЛИЧАТЬ наличие компенсации:
## цель долго стоит на месте, трогается вбок ровно в миг выстрела, а лететь
## снаряду меньше, чем величина отставания. Значит ВСЁ время полёта в
## «мире стрелявшего» цель ещё стоит там, куда он целился, а в настоящем
## мире она уже уехала на несколько метров.
##   без отмотки — чистый промах (так и было в бою);
##   с отмоткой — попадание.

const LAG := 0.25       # отставание картинки у стрелявшего
const DIST := 8.0       # до цели: полёт ~0.15 c, короче отставания
const SIDE_SPEED := 25.0

var _main: Node3D
var _shooter: Car
var _victim: Car
var _frame := 0
var _shot_at := 0
var _aim := Vector3.ZERO
var _side := Vector3.ZERO


func _ready() -> void:
	Net.port = 29979   # не мешаем настоящему локальному серверу
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
		# Машина живого игрока на сервере — марионетка; она же доложила
		# своё отставание картинки (протокол 13).
		_shooter.net_make_puppet()
		_shooter.net_client_lag = LAG
		var fwd: Vector3 = -_shooter.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		_side = _shooter.global_transform.basis.x
		_aim = _shooter.global_position + fwd * DIST
		_victim.global_position = _aim
		_victim.linear_velocity = Vector3.ZERO
		return
	if _shooter == null:
		return
	# Цель СТОИТ целую секунду — её и видит стрелявший.
	if _frame > 30 and _frame <= 90:
		_victim.global_position = _aim
		_victim.linear_velocity = Vector3.ZERO
		return
	# Выстрел ровно в миг, когда цель трогается вбок.
	if _frame == 91:
		_shot_at = _frame
		_shooter.weapon = Weapons.ROCKET
		_shooter.use_weapon()
		return
	if _frame > 91 and _frame <= 91 + 20:
		# Цель уезжает вбок: в настоящем мире ракета мимо, в мире
		# стрелявшего (отставание LAG) она всё ещё стоит на прицеле.
		var t := float(_frame - 91) / 60.0
		_victim.global_position = _aim + _side * SIDE_SPEED * t
		_victim.linear_velocity = _side * SIDE_SPEED
		return
	if _frame == 91 + 21:
		var away := _victim.global_position.distance_to(_aim)
		var hit := not _victim.alive or _victim.is_ghost()
		print("к концу полёта цель уехала на %.1f м от прицела" % away)
		print("ROCKETREWIND TEST: %s" % ("PASS" if hit
				else "FAIL — ракета прошла сквозь то, что видел стрелявший"))
		get_tree().quit(0 if hit else 1)
