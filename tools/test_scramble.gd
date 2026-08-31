extends Node3D
## Автотест нового оружия ГЛУШИЛКА (звуковая волна, Weapons.SCRAMBLE):
##   1) волна долетает и вешает эффект на 5 c (Car.scramble_left);
##   2) пока эффект идёт, руль ИНВЕРТИРОВАН — при одном и том же вводе
##      машина доворачивает в СТОРОНУ, ПРОТИВОПОЛОЖНУЮ чистой машине;
##   3) эффект сам истекает, и руль возвращается в норму;
##   4) стрелявшего собственная волна не задевает.
## Руль проверяем, вызывая Car._drive напрямую (управление у машин снято):
## иначе пришлось бы гадать по траектории, куда её повёл ИИ.

var _main: Node3D
var _frame := 0
var _ok := {}
var _attacker: Car
var _victim: Car     # по нему бьём волной
var _clean: Car      # контрольная машина, эффекта нет
var _base := Vector3.ZERO
var _tan := Vector3.FORWARD
var _right := Vector3.RIGHT
var _yaw_scrambled := 0.0
var _yaw_clean := 0.0


func _ready() -> void:
	seed(7)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _place(car: Car, pos: Vector3, look: Vector3) -> void:
	car.alive = true
	car.global_transform = Transform3D(
			Basis.looking_at(look), pos + Vector3.UP * 0.62)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.reset_speed_memory()


func _park(car: Car) -> void:
	car.alive = false
	car.global_transform = Transform3D(Basis.IDENTITY,
			Vector3(120.0, 2.0, 120.0) + Vector3.RIGHT * randf_range(0, 20))
	car.linear_velocity = Vector3.ZERO


## Один кадр «газ в пол, руль влево» для обеих машин. Скорость держим
## руками: руль работает только на ходу (см. Car._drive).
func _steer_both(delta: float) -> void:
	for c: Car in [_victim, _clean]:
		c.linear_velocity = -c.global_transform.basis.z * 14.0
		c._drive(delta, true, 1.0, 1.0, false, false)


func _physics_process(delta: float) -> void:
	_frame += 1
	if _frame < 160:
		return   # ждём конца отсчёта: до него управление всё равно снято
	match _frame:
		160:
			var curve: Curve3D = _main._track._curve
			var off: float = curve.get_baked_length() * 0.06
			_base = curve.sample_baked(off)
			_tan = curve.sample_baked(off + 1.0) - _base
			_tan.y = 0.0
			_tan = _tan.normalized()
			_right = _tan.cross(Vector3.UP).normalized()
			for c: Car in _main._cars:
				c.controls_enabled = false
				c.weapon = -1
			_attacker = _main._cars[0]
			_victim = _main._cars[1]
			_clean = _main._cars[2]
			for i in range(3, _main._cars.size()):
				_park(_main._cars[i])
			_place(_attacker, _base, _tan)
			_place(_victim, _base + _tan * 15.0, _tan)
			# Контрольная машина — сбоку, вне коридора волны (HIT_R 2.6).
			_place(_clean, _base + _tan * 15.0 + _right * 7.0, _tan)
		165:
			_attacker.weapon = Weapons.SCRAMBLE
			_attacker.use_weapon()
		200:
			# 15 м на 38 м/с — примерно 0.4 c, волна уже долетела.
			_ok["волна сбила управление"] = _victim.scramble_left() > 4.0
			_ok["соседа волна не задела"] = _clean.scramble_left() == 0.0
			_ok["стрелявший цел"] = _attacker.scramble_left() == 0.0
			if _victim.scramble_left() <= 4.0:
				print("  [глушилка] осталось %.2f c" % _victim.scramble_left())
			_place(_victim, _base + _tan * 15.0, _tan)
			_place(_clean, _base + _tan * 15.0 + _right * 7.0, _tan)
		214:
			# Пятая доля секунды одинакового «руля влево» — сравниваем
			# доворот. Дольше рулить НЕЛЬЗЯ: жертва едет в противоположную
			# сторону, доезжает до ограждения, и доворот ей начинает задавать
			# ведение у стены (первая версия стенда ловила именно это —
			# «жертва 1.62, контроль 5.53», обе в плюс).
			_yaw_scrambled = _victim.angular_velocity.y
			_yaw_clean = _clean.angular_velocity.y
			_ok["руль перевёрнут"] = absf(_yaw_clean) > 0.3 \
					and signf(_yaw_scrambled) == -signf(_yaw_clean)
			if not _ok["руль перевёрнут"]:
				print("  [руль] жертва %.2f, контроль %.2f рад/с"
						% [_yaw_scrambled, _yaw_clean])
			_ok["эффект тикает"] = _victim.scramble_left() < 4.6
		560:
			# Волна летит до жертвы ~0.4 c, так что отсчитываем от попадания
			# (~кадр 189), а не от выстрела: 560 — это 6.2 c, эффект (5 c)
			# обязан истечь сам.
			_ok["эффект истёк"] = _victim.scramble_left() == 0.0
			_place(_victim, _base + _tan * 15.0, _tan)
			_place(_clean, _base + _tan * 15.0 + _right * 7.0, _tan)
		574:
			_ok["руль вернулся"] = signf(_victim.angular_velocity.y) \
					== signf(_clean.angular_velocity.y) \
					and absf(_clean.angular_velocity.y) > 0.3
			var all_ok := true
			for k: String in _ok:
				if not _ok[k]:
					all_ok = false
				print("  %s: %s" % [k, "ok" if _ok[k] else "FAIL"])
			print("SCRAMBLE TEST: %s" % ("PASS" if all_ok else "FAIL"))
			get_tree().quit(0 if all_ok else 1)
	# Окна «руления»: сразу после попадания и после истечения эффекта.
	if (_frame > 200 and _frame < 214) or (_frame > 560 and _frame < 574):
		_steer_both(delta)
