extends Node3D
## Тест «ИИ не вылетает на поворотах»: гонка едет сама 60 с, считаем,
## сколько раз каждый ИИ оказался за ограждением (dist > OFFTRACK_DIST,
## по фронту события — респавн возвращает на ось, дальше новый счёт).
## Заодно следим, что торможение перед поворотами не убило темп.

const RUN_TIME := 60.0
const MERGE_GAP := 3.0          # кадры «вне» ближе 3 с — один и тот же инцидент
const DEBUG_ZONE := false       # телеметрия ИИ в зоне отметок 0.25-0.40

var _main: Node3D
var _t := 0.0
var _next_log := 0.0
var _incidents: Array[int] = [0, 0, 0, 0]
var _last_out: Array[float] = [-99.0, -99.0, -99.0, -99.0]
var _episode_start: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _max_episode := 0.0         # самое долгое непрерывное катание снаружи


func _ready() -> void:
	# Фиксированный seed: машины ИИ и разброс их характеристик случайны,
	# без seed результат гуляет от прогона к прогону.
	seed(1234)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_delta: float) -> void:
	_t += _delta
	for i in range(1, _main._cars.size()):
		var car: Car = _main._cars[i]
		# Полотно переменной ширины — порог берём в точке машины.
		var out: bool = _main._track.distance_from_axis(car.global_position) \
				> _main._track.half_width_at_pos(car.global_position) \
				+ _main._track.offtrack_margin
		if out:
			if _t - _last_out[i] > MERGE_GAP:
				_incidents[i] += 1
				_episode_start[i] = _t
				var curve: Curve3D = _main._track._curve
				var frac: float = curve.get_closest_offset(car.global_position) \
						/ curve.get_baked_length()
				print("  t=%.1f: ИИ%d вылетел (инцидент №%d, отметка %.2f, v=%.0f)" % [
					_t, i, _incidents[i], frac, car.linear_velocity.length()])
			_last_out[i] = _t
			_max_episode = maxf(_max_episode, _t - _episode_start[i])
		if DEBUG_ZONE and Engine.get_physics_frames() % 3 == 0:
			var curve: Curve3D = _main._track._curve
			var off: float = curve.get_closest_offset(car.global_position)
			var frac: float = off / curve.get_baked_length()
			if frac > 0.25 and frac < 0.40:
				var axis_y: float = curve.sample_baked(off).y
				print("  DBG t=%.1f ИИ%d frac=%.3f dist=%.1f dy=%+.2f v=%.0f vy=%+.1f колёс=%d стена=%s" % [
					_t, i, frac,
					_main._track.distance_from_axis(car.global_position),
					car.global_position.y - axis_y,
					car.linear_velocity.length(), car.linear_velocity.y,
					car._grounded_wheels, car._touching_wall()])
	if _t >= _next_log:
		_next_log += 10.0
		var progs: Array[String] = []
		for i in _main._progress.size():
			progs.append("%.0f" % _main._progress[i])
		print("t=%.0f progress: %s  инциденты: %s" % [_t, ", ".join(progs),
				str(_incidents.slice(1))])
	if _t < RUN_TIME:
		return
	var length: float = _main._track._curve.get_baked_length()
	var worst := 1e9
	for i in range(1, _main._progress.size()):
		worst = minf(worst, _main._progress[i])
	var total: int = _incidents[1] + _incidents[2] + _incidents[3]
	# Редкие вылеты допустимы (толкучка), но не «всегда на каждом повороте»;
	# застрявших снаружи возвращает автовозврат (эпизод < 2.5 с);
	# торможение перед поворотами не должно убивать темп.
	var ok := total <= 3 and _max_episode < 2.5 and worst > length * 0.5
	print("AICORNERS TEST: %s (инцидентов: %d, макс. эпизод %.1f с, худший ИИ %.0f м)" % [
		"PASS" if ok else "FAIL", total, _max_episode, worst])
	get_tree().quit(0 if ok else 1)


