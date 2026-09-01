extends Node3D
## Автотест ВЕДЕНИЯ МЯЧА (просьба 01.09): «в режиме футбол при врезании
## передом мяч примагничивается; чтобы перехватить — нужно ударить в
## машину, ведущую мяч; мяч отмагничивается и при повторном ударе передом
## снова примагничивается».
## Фазы:
## 1) машина едет носом в мяч — мяч ПРИМАГНИЧЕН (carrier) и держится у
##    носа при движении;
## 2) вторая машина таранит ведущего — мяч ОТЛИПАЕТ;
## 3) в окне запрета экс-ведущий тычет мяч передом — НЕ липнет (_no_grab);
## 4) после окна — удар передом снова примагничивает.

var _soccer: Node3D
var _ball: SoccerBall
var _car: Car          # «ведущий» (машина игрока, controls выключены)
var _hitter: Car       # перехватчик
var _frame := 0
var _phase := 0
var _phase_frame := 0
var _carry_far := 0    # кадры, когда ведомый мяч оторвался от носа
var _ok_grab := false
var _ok_steal := false
var _ok_nograb := true
var _ok_regrab := false


func _ready() -> void:
	_soccer = (load("res://scenes/Soccer.tscn") as PackedScene).instantiate()
	add_child(_soccer)


func _fail(msg: String) -> void:
	print("SOCCER DRIBBLE TEST: FAIL — %s" % msg)
	get_tree().quit(1)


## Поставить машину в p носом на цель, со скоростью v в ту же сторону.
func _aim(car: Car, p: Vector3, at: Vector3, v: float) -> void:
	var dir := at - p
	dir.y = 0.0
	dir = dir.normalized()
	p.y = 0.6
	car.global_transform = Transform3D(
			Basis.looking_at(dir), p)
	car.linear_velocity = dir * v
	car.angular_velocity = Vector3.ZERO
	car.reset_speed_memory()


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame < 30:
		return
	_ball = _soccer._ball
	_car = _soccer._cars[0]
	_hitter = _soccer._cars[4]
	# Управление выключено ВЕСЬ тест (отсчёт GO включил бы ботов).
	for c: Car in _soccer._cars:
		c.controls_enabled = false
	if _frame == 30:
		# Лишние боты — по углам поля, внутри бортов (иначе автовозврат).
		for i in _soccer._cars.size():
			if i == 0 or i == 4:
				continue
			var k: int = i % 4
			var cx := SoccerArena.HALF_LEN - 6.0
			var cz := SoccerArena.HALF_WID - 6.0
			var corner := Vector3(cx if k < 2 else -cx, 0.6,
					cz if k % 2 == 0 else -cz)
			_soccer._cars[i].global_transform = Transform3D(
					Basis.IDENTITY, corner)
			_soccer._cars[i].linear_velocity = Vector3.ZERO
		_hitter.global_transform = Transform3D(
				Basis.IDENTITY, Vector3(20.0, 0.6, 15.0))
		_hitter.linear_velocity = Vector3.ZERO
		return
	if _frame < 40:
		return

	_phase_frame += 1
	match _phase:
		0:
			# Пуск ведущего носом в мяч.
			_ball.reset_to(Vector3(0, SoccerBall.RADIUS, 0))
			_aim(_car, Vector3(-9.0, 0.6, 0.0), _ball.global_position, 12.0)
			_phase = 1
			_phase_frame = 0
		1:
			# Ждём примагничивания.
			if _ball.carrier == _car:
				_ok_grab = true
				print("фаза 1 (захват): ok (кадр %d)" % _phase_frame)
				_phase = 2
				_phase_frame = 0
			elif _phase_frame > 180:
				_fail("удар передом не примагнитил мяч за 3 c")
		2:
			# Ведение 45 кадров: газ вперёд, мяч обязан держаться у носа.
			var fwd := -_car.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			_car.linear_velocity = fwd * 8.0 \
					+ Vector3.UP * _car.linear_velocity.y
			if _ball.carrier != _car or _ball.global_position.distance_to(
					_car.global_position) > 5.0:
				_carry_far += 1
			if _phase_frame >= 45:
				if _carry_far > 3:
					_fail("мяч не удержался у носа (%d кадров врозь)"
							% _carry_far)
				print("фаза 2 (ведение): ok (мяч у носа)")
				# Таран сбоку: перехватчик бьёт в ВЕДУЩЕГО, не в мяч.
				# Ведущего останавливаем, чтобы прицел тарана не устарел.
				_car.linear_velocity = Vector3.ZERO
				var side := _car.global_transform.basis.x
				side.y = 0.0
				side = side.normalized()
				_aim(_hitter, _car.global_position + side * 7.0,
						_car.global_position, 14.0)
				_phase = 3
				_phase_frame = 0
		3:
			# Ждём отлипания от удара по ведущему.
			if _ball.carrier == null:
				_ok_steal = true
				print("фаза 3 (перехват): ok (кадр %d)" % _phase_frame)
				# Перехватчика — прочь, чтобы сам не увёл мяч.
				_hitter.global_transform = Transform3D(
						Basis.IDENTITY, Vector3(20.0, 0.6, 15.0))
				_hitter.linear_velocity = Vector3.ZERO
				_phase = 4
				_phase_frame = 0
			elif _phase_frame > 120:
				_fail("удар по ведущему не отлепил мяч за 2 c")
		4:
			# Окно запрета (1.2 c): экс-ведущий тычет мяч — липнуть не должно.
			if _phase_frame == 5:
				_aim(_car, _ball.global_position
						+ Vector3(-3.5, 0.0, 0.0), _ball.global_position, 6.0)
			if _phase_frame < 40 and _ball.carrier == _car:
				_ok_nograb = false
			if _phase_frame >= 40:
				print("фаза 4 (запрет сразу после перехвата): %s"
						% ("ok" if _ok_nograb else "FAIL — прилип сразу"))
				# Отъехать и подождать конец окна запрета.
				_aim(_car, _ball.global_position
						+ Vector3(-12.0, 0.0, 0.0), _ball.global_position, 0.0)
				_car.linear_velocity = Vector3.ZERO
				_phase = 5
				_phase_frame = 0
		5:
			# Дать окну запрета истечь (1.2 c с запасом).
			if _phase_frame >= 80:
				_aim(_car, _ball.global_position
						+ Vector3(-8.0, 0.0, 0.0), _ball.global_position, 12.0)
				_phase = 6
				_phase_frame = 0
		6:
			# Повторный удар передом — снова примагничивается.
			if _ball.carrier == _car:
				_ok_regrab = true
				print("фаза 5 (повторный захват): ok (кадр %d)" % _phase_frame)
				_finish()
			elif _phase_frame > 180:
				_fail("повторный удар передом не примагнитил мяч")


func _finish() -> void:
	var ok := _ok_grab and _ok_steal and _ok_nograb and _ok_regrab
	print("SOCCER DRIBBLE TEST: %s (захват=%s, перехват=%s, запрет=%s, "
			% ["PASS" if ok else "FAIL", str(_ok_grab), str(_ok_steal),
				str(_ok_nograb)]
			+ "повтор=%s)" % str(_ok_regrab))
	get_tree().quit(0 if ok else 1)
