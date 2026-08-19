extends Node3D
## Тест закрутки от столкновения машин: «поддел зад — соперника развернуло».
## Фаза 1: атакующий на 15 м/с бьёт стоящую машину в УГОЛ кормы (смещение
##   0.7 м вбок) — жертву должно заметно развернуть (и толкнуть).
## Фаза 2: тот же таран строго ПО ЦЕНТРУ — толкнуть должно, а вот
##   крутиться жертва почти не должна (момента у центрального удара нет).
## Фаза 3: две машины стоят борт к борту ВНАХЛЁСТ — должны разлепиться
##   (расталкивание в _bounce_off_cars), а не «слипнуться».

const START_T := 0.06           # доля круга — место сцены
const SETTLE_FRAMES := 220      # ждём конец отсчёта и посадку машин
const RUN_FRAMES := 45          # 0.75 с на фазу: дальше идёт уже не удар,
								# а продавливание ИИ-атакующим — не меряем

var _main: Node3D
var _frame := 0
var _phase := 0
var _start_fwd := Vector3.ZERO  # курс жертвы в момент пуска
var _max_yaw := 0.0             # максимум |отклонения курса| за фазу, рад
var _yaws: Array[float] = []
var _pushed: Array[float] = []  # скорость жертвы в конце фазы
var _gap := 0.0                 # фаза 3: дистанция между бортами в конце
var _names := ["1: удар в угол кормы", "2: удар строго в центр",
		"3: борт к борту — расталкивание"]


func _ready() -> void:
	# Фиксированный seed: атакующий — случайная машина ИИ со случайным
	# разбросом характеристик, без seed порог «центр < 8°» плавает.
	seed(1234)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _launch(lateral: float) -> void:
	var curve: Curve3D = _main._track._curve
	var off := curve.get_baked_length() * START_T
	var pos := curve.sample_baked(off)
	var tangent := curve.sample_baked(off + 1.0) - pos
	tangent.y = 0.0
	tangent = tangent.normalized()
	var right := tangent.cross(Vector3.UP).normalized()
	var victim: Car = _main._cars[0]
	var attacker: Car = _main._cars[1]
	victim.global_transform = Transform3D(
			Basis.looking_at(tangent), pos + Vector3.UP * 0.62)
	victim.linear_velocity = Vector3.ZERO
	victim.angular_velocity = Vector3.ZERO
	victim.reset_speed_memory()
	attacker.global_transform = Transform3D(Basis.looking_at(tangent),
			pos - tangent * 6.0 + right * lateral + Vector3.UP * 0.62)
	attacker.linear_velocity = tangent * 15.0
	attacker.angular_velocity = Vector3.ZERO
	attacker.reset_speed_memory()
	_start_fwd = tangent
	_max_yaw = 0.0


## Фаза 3: обе машины стоят борт к борту с небольшим нахлёстом, без
## управления (и без газа) — меряем чистое расталкивание корпусов.
func _launch_side() -> void:
	var curve: Curve3D = _main._track._curve
	var off := curve.get_baked_length() * START_T
	var pos := curve.sample_baked(off)
	var tangent := curve.sample_baked(off + 1.0) - pos
	tangent.y = 0.0
	tangent = tangent.normalized()
	var right := tangent.cross(Vector3.UP).normalized()
	var a: Car = _main._cars[0]
	var b: Car = _main._cars[1]
	for car: Car in [a, b]:
		car.controls_enabled = false
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		car.reset_speed_memory()
	a.global_transform = Transform3D(
			Basis.looking_at(tangent), pos + Vector3.UP * 0.62)
	b.global_transform = Transform3D(Basis.looking_at(tangent),
			pos + right * 1.65 + Vector3.UP * 0.62)
	_start_fwd = tangent
	_max_yaw = 0.0


## Лишние ИИ не должны вмешиваться: увозим на другой конец трассы,
## глушим управление и оружие (иначе подстрелят жертву — тест соврёт).
func _park_extras() -> void:
	var curve: Curve3D = _main._track._curve
	for i in range(1, _main._cars.size()):
		var car: Car = _main._cars[i]
		car.ammo = 0
		car.mines = 0
		if i >= 2:
			car.controls_enabled = false
			var off := curve.get_baked_length() * 0.5 + i * 6.0
			car.global_transform = Transform3D(Basis.IDENTITY,
					curve.sample_baked(off) + Vector3.UP * 0.62)
			car.linear_velocity = Vector3.ZERO
			car.angular_velocity = Vector3.ZERO
			car.reset_speed_memory()


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame < SETTLE_FRAMES:
		return
	var victim: Car = _main._cars[0]
	var local := _frame - SETTLE_FRAMES - _phase * (RUN_FRAMES + 10)
	if local == 0:
		_park_extras()
		if _phase == 2:
			_launch_side()
		else:
			_launch(0.7 if _phase == 0 else 0.0)
		print("--- %s ---" % _names[_phase])
	elif local > 0 and local <= RUN_FRAMES:
		var fwd := -victim.global_transform.basis.z
		fwd.y = 0.0
		_max_yaw = maxf(_max_yaw,
				absf(_start_fwd.signed_angle_to(fwd.normalized(), Vector3.UP)))
		if local % 10 == 0:
			var attacker: Car = _main._cars[1]
			print("    t=%2d  курс %+5.1f°  w.y %+.2f  v жертвы %.1f  дист %.2f" % [
				local, rad_to_deg(_max_yaw), victim.angular_velocity.y,
				victim.linear_velocity.length(),
				victim.global_position.distance_to(attacker.global_position)])
	elif local == RUN_FRAMES + 1:
		_yaws.append(rad_to_deg(_max_yaw))
		var h := victim.linear_velocity
		h.y = 0.0
		_pushed.append(h.length())
		if _phase == 2:
			_gap = victim.global_position.distance_to(
					_main._cars[1].global_position)
			print("  дистанция между машинами: %.2f м (старт 1.65)" % _gap)
		else:
			print("  развернуло на %.1f°, скорость жертвы %.1f м/с" % [
				_yaws[_phase], _pushed[_phase]])
		_phase += 1
		if _phase == 3:
			# Угловой удар крутит (>= 20°), центральный — почти нет (< 8°),
			# толчок есть, борта расталкиваются (>= 2.2 м).
			var ok := _yaws[0] >= 20.0 and _yaws[1] < 8.0 \
					and _pushed[0] >= 1.5 and _pushed[1] >= 1.5 \
					and _gap >= 2.2
			print("ИТОГ: угол %.1f°/центр %.1f°, толчок %.1f/%.1f м/с, разлепились до %.2f м" % [
				_yaws[0], _yaws[1], _pushed[0], _pushed[1], _gap])
			print("CARBOUNCE TEST: %s (угол >= 20, центр < 8, толчок >= 1.5, гэп >= 2.2)"
					% ("PASS" if ok else "FAIL"))
			get_tree().quit(0 if ok else 1)
