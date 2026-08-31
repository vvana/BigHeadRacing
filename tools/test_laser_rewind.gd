extends Node3D
## Автотест отмотки лазера (протокол 11, жалоба 28.08: «нажал E ... мог бы
## подбить машину друга, если бы выстрел появился сразу»). Стрелявший
## целится в картину СВОЕГО экрана, где цель отстаёт на буфер
## воспроизведения (~0.35 c) и полёт пакета; сервер же мерил попадание по
## текущим позициям — «на экране попал, сервер промахнулся».
## Теперь выстрел живого игрока (его машина на сервере — марионетка)
## отматывает цели на 0.4 c по истории _pos_hist.
## Сценарий: жертва уезжает вбок из коридора луча за те же 0.4 c —
## по ТЕКУЩЕЙ позиции промах (4 м > полуширины 1.6), по ОТМОТАННОЙ (где её
## видел стрелявший) — попадание.

var _main: Node3D
var _shooter: Car
var _victim: Car
var _frame := 0
var _a := Vector3.ZERO   # где жертва была 0.4 c назад (в коридоре)
var _b := Vector3.ZERO   # где жертва сейчас (вне коридора)


func _ready() -> void:
	Net.port = 29978   # не мешаем настоящему локальному серверу
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
		# Машина живого игрока на сервере — марионетка.
		_shooter.net_make_puppet()
		# С протокола 13 сервер отматывает не «на глазок 0.4», а на
		# ОТСТАВАНИЕ, доложенное владельцем (Car.net_client_lag). Стенд
		# задаёт его явно — сценарий ниже построен ровно на этой величине.
		_shooter.net_client_lag = 0.4
		var fwd: Vector3 = -_shooter.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var side: Vector3 = _shooter.global_transform.basis.x
		_a = _shooter.global_position + fwd * 15.0
		_b = _a + side * 4.0
		_victim.global_position = _a
		_victim.linear_velocity = Vector3.ZERO
		return
	# Жертва уезжает вбок ровно за 24 кадра (0.4 c) перед выстрелом.
	if _frame > 60 and _frame <= 84:
		_victim.global_position = _a.lerp(_b, float(_frame - 60) / 24.0)
		_victim.linear_velocity = Vector3.ZERO
		return
	if _frame == 85:
		var side_now := (_victim.global_position - _shooter.global_position) \
				- (-_shooter.global_transform.basis.z) \
				* (_victim.global_position - _shooter.global_position).dot(
				-_shooter.global_transform.basis.z)
		print("жертва сейчас в %.1f м от оси луча (полуширина 1.6)"
				% side_now.length())
		_shooter.weapon = Weapons.LASER
		_shooter.use_weapon()
		return
	if _frame == 87:
		var hit := _victim.is_ghost() or not _victim.alive
		print("LASERREWIND TEST: %s" % ("PASS" if hit
				else "FAIL — лазер промахнулся по тому, что видел стрелявший"))
		get_tree().quit(0 if hit else 1)
