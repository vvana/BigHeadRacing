extends Node3D
## Волна глушилки ГАСНЕТ ТОЛЬКО ОТ ВРЕМЕНИ (просьба игрока 11.09: «волна
## оглушения гаснет от времени, а не от первого столкновения. Нужно так»).
## До этого она умирала об первую же задетую машину, а её копия на экранах
## летела дальше и «касалась» тех, кого сервер уже не проверял, — игрок
## видел кольца на машине и никакого эффекта.
## Проверяем:
##   1) одна волна оглушает ДВЕ машины, стоящие друг за другом на трассе;
##   2) каждую — по одному разу (эффект не продлевается, пока кольца рядом);
##   3) на каждое попадание сервер шлёт клиентам вспышку
##      (race.net_broadcast_wave_hit), а сама волна живёт дальше;
##   4) копия у клиента (inert) не глушит и сквозь машины проходит — её
##      дело только картинка;
##   5) волну всё-таки забирает срок жизни.
##
## Запуск: godot --headless --path . res://tools/TestWaveLife.tscn

var _main: Node3D
var _frame := 0
var _pass := 0
var _fail := 0
var _phase := 0
var _mark := 0
var _wave: ScrambleWave
var _near: Car       # ближняя жертва
var _far: Car        # дальняя жертва, за ней
var _shooter: Car
var _spy: Node
var _near_stun := 0.0
var _base := 0.0     # отметка ровной прямой, на которой стоит вся сцена


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: ", what)


func _ready() -> void:
	seed(11)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	_spy = Node.new()
	_spy.set_script(load("res://tools/wave_spy.gd"))
	add_child(_spy)


## Поставить машину на ось трассы у отметки off, носом по ходу.
func _place(car: Car, off: float) -> void:
	var xf: Transform3D = _main._track.respawn_transform_at(off)
	car.alive = true
	car.controls_enabled = false
	car.global_transform = xf
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.reset_speed_memory()
	car.reset_track_offset()


func _park(car: Car) -> void:
	car.alive = false
	car.global_transform = Transform3D(Basis.IDENTITY,
			Vector3(140.0, 2.0, 140.0 + randf_range(0, 20)))
	car.linear_velocity = Vector3.ZERO


func _spawn_wave(is_inert: bool) -> ScrambleWave:
	var w := ScrambleWave.new()
	w.inert = is_inert
	w.shooter = _shooter
	w.track = _main._track
	w.direction = -_shooter.global_transform.basis.z
	_main.add_child(w)
	w.global_position = _shooter.global_position \
			+ w.direction * 2.3 + Vector3.UP * 0.55
	return w


func _physics_process(_d: float) -> void:
	_frame += 1
	match _phase:
		0:
			if _frame < 100:
				return   # ждём, пока сцена и трасса встанут
			_shooter = _main._cars[0]
			_near = _main._cars[1]
			_far = _main._cars[2]
			for i in range(3, _main._cars.size()):
				_park(_main._cars[i])
			_shooter.race = _spy
			_phase = 1
			_mark = _frame
		1:
			if _frame < _mark + 5:
				return
			# Две жертвы на пути волны: одна в 20 м, вторая ещё в 25 м за ней.
			# Место выбираем РОВНОЕ И ПРЯМОЕ (см. _find_straight): на дуге
			# волна идёт по касательной трассы и проходит мимо машины,
			# стоящей строго на оси, а на горке — уезжает по высоте.
			_base = _find_straight()
			_place(_shooter, _base)
			_place(_near, _base + 20.0)
			_place(_far, _base + 45.0)
			_near._scramble_time = 0.0
			_far._scramble_time = 0.0
			_wave = _spawn_wave(false)
			_phase = 2
			_mark = _frame
		2:
			# Ближнюю накрывает примерно через 0.4 с — ловим момент, когда
			# она уже оглушена, а дальняя ещё нет.
			if _near.scramble_left() <= 0.0:
				if _frame > _mark + 120:
					_ok(false, "ближняя машина так и не оглушена")
					_phase = 4
				return
			_near_stun = _near.scramble_left()
			_ok(is_instance_valid(_wave) and not _wave.is_queued_for_deletion(),
					"после первого попадания волна жива и летит дальше")
			_ok(_spy.hits >= 1, "сервер разослал вспышку попадания (%d)"
					% _spy.hits)
			_phase = 3
			_mark = _frame
		3:
			if _frame < _mark + 90:
				return
			_ok(_far.scramble_left() > 0.0,
					"та же волна достала ВТОРУЮ машину: %.2f"
					% _far.scramble_left())
			_ok(_spy.hits == 2, "вспышка на каждое попадание (%d, ждали 2)"
					% _spy.hits)
			# Эффект ближней не продлевался: остаток только убывал.
			_ok(_near.scramble_left() < _near_stun,
					"ближнюю оглушило один раз, а не каждый кадр (%.2f → %.2f)"
					% [_near_stun, _near.scramble_left()])
			_phase = 4
			_mark = _frame
		4:
			# Срок жизни волны — 1.8 с; к этому времени её быть не должно.
			if _frame < _mark + 130:
				return
			_ok(not is_instance_valid(_wave) or _wave.is_queued_for_deletion(),
					"волну забрал срок жизни")
			_phase = 5
			_mark = _frame
		5:
			if _frame < _mark + 5:
				return
			# Копия у клиента: не глушит и не гаснет о кузов.
			_place(_shooter, _base)
			_place(_near, _base + 20.0)
			_park(_far)
			_near._scramble_time = 0.0
			_spy.hits = 0
			_wave = _spawn_wave(true)
			_phase = 6
			_mark = _frame
		6:
			if _frame < _mark + 45:
				return
			_ok(_near.scramble_left() <= 0.0,
					"копия НЕ глушит (это дело сервера): %.2f"
					% _near.scramble_left())
			_ok(_spy.hits == 0, "копия ничего не рассылает (%d)" % _spy.hits)
			_ok(is_instance_valid(_wave) and not _wave.is_queued_for_deletion(),
					"копия не гаснет о кузов — летит свой срок")
			_shooter.race = _main
			print("RESULT: %d/%d ok" % [_pass, _pass + _fail])
			print("WAVE LIFE TEST: %s" % ("PASS" if _fail == 0 else "FAIL"))
			get_tree().quit(0 if _fail == 0 else 1)


## Самый прямой и ровный отрезок трассы длиной SPAN: волна катится по
## касательной оси, и на дуге она обходит машину, стоящую ровно на оси,
## а на горке уходит по высоте. Берём место, где курс за SPAN метров
## меняется меньше всего, а подъём не больше полуметра.
func _find_straight() -> float:
	var curve: Curve3D = _main._track._curve
	var length := curve.get_baked_length()
	const SPAN := 50.0
	var best := 0.0
	var best_turn := 1e9
	var off := 0.0
	while off < length - SPAN:
		var a: Vector3 = curve.sample_baked(off + 1.0) - curve.sample_baked(off)
		var b: Vector3 = curve.sample_baked(off + SPAN + 1.0) 				- curve.sample_baked(off + SPAN)
		a.y = 0.0
		b.y = 0.0
		var climb: float = absf(curve.sample_baked(off + SPAN).y
				- curve.sample_baked(off).y)
		if a.length_squared() > 1e-6 and b.length_squared() > 1e-6 				and climb < 0.5:
			var turn: float = a.normalized().angle_to(b.normalized())
			if turn < best_turn:
				best_turn = turn
				best = off
		off += 5.0
	print("  прямая для стенда: отметка %.0f м, поворот на %.0f м — %.1f°"
			% [best, SPAN, rad_to_deg(best_turn)])
	return best
