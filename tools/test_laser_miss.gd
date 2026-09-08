extends Node3D
## «Стреляю лазером ПЕРЕД ним — на моём экране луч его не касается, а он
## уничтожается» (жалоба 08.09).
##
## Разбор: соперник на экране стрелявшего отстаёт от правды на буфер плюс
## дорогу владелец → сервер → я. Сервер отматывал цели только на буфер
## (клиент докладывал именно его), недостающие полпути с обеих сторон
## оставались — и выстрел с упреждением попадал в то, чего стрелявший не
## видел. Теперь клиент шлёт своё ПОЛНОЕ отставание (Car.net_view_lag), а
## сервер добавляет полпути владельца цели (Car.aim_lag).
##
## Стенд задаёт обе половины руками и проверяет ДВА выстрела:
##   1) в точку, где цель ВИДНА стрелявшему → должно убить;
##   2) в точку, где цель НА САМОМ ДЕЛЕ (3.6 м впереди видимой) → мимо.

const LAG_OWNER := 0.40     # что доложил стрелявший (буфер + его полпути)
const LAG_WIRE := 0.05      # полпути владельца цели до сервера
const SIDE_SPEED := 8.0     # цель пересекает курс, м/с

var _main: Node3D
var _shooter: Car
var _victim: Car
var _frame := 0
var _a := Vector3.ZERO
var _side := Vector3.ZERO
var _miss_ok := false


func _ready() -> void:
	Net.port = 29979   # не мешаем настоящему локальному серверу
	Net.start_server()
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _seen() -> Vector3:
	return _victim.past_position(LAG_OWNER + LAG_WIRE)


func _aim_at(p: Vector3) -> void:
	var dir := p - _shooter.global_position
	dir.y = 0.0
	_shooter.global_transform = Transform3D(Basis.looking_at(dir.normalized()),
			_shooter.global_position)


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
		_shooter.net_make_puppet()
		_shooter.net_client_lag = LAG_OWNER
		_victim.net_wire_lag = LAG_WIRE
		var fwd: Vector3 = -_shooter.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		_side = _shooter.global_transform.basis.x
		_a = _shooter.global_position + fwd * 18.0
		return
	if _frame < 40:
		return
	# Цель едет вбок, история пишется сама (Car._pos_hist на сервере).
	if _frame >= 40:
		_victim.global_position = _a \
				+ _side * (SIDE_SPEED * float(_frame - 40) / 60.0)
		_victim.linear_velocity = _side * SIDE_SPEED
	if _frame == 100:
		# ВЫСТРЕЛ ПЕРЕД НИМ: целимся туда, где цель на самом деле, — а
		# стрелявший видел её на 3.6 м позади. Убивать НЕ должно.
		var gap := _victim.global_position.distance_to(_seen())
		print("[miss] видимая и настоящая точки разошлись на %.1f м" % gap)
		_aim_at(_victim.global_position)
		_shooter.weapon = Weapons.LASER
		_shooter.use_weapon()
		return
	if _frame == 102:
		_miss_ok = _victim.alive and not _victim.is_ghost()
		print("[miss] выстрел в НАСТОЯЩУЮ точку: %s"
				% ("цела — верно" if _miss_ok else "убита — НЕВЕРНО"))
		_shooter._laser_left = 0.0   # луч не должен догорать в кадр 160
		return
	if _frame == 160:
		_aim_at(_seen())
		_shooter.weapon = Weapons.LASER
		_shooter.use_weapon()
		return
	if _frame == 162:
		var hit_ok := not _victim.alive or _victim.is_ghost()
		print("[miss] выстрел в ВИДИМУЮ точку: %s"
				% ("убита — верно" if hit_ok else "цела — НЕВЕРНО"))
		var ok := _miss_ok and hit_ok
		print("LASERMISS TEST: %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
