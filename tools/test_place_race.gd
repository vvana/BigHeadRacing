extends Node3D
## Стенд «место в гонке» ОФФЛАЙН (жалоба 03.09 «часто неправильно
## показывается текущее место»). Все машины ведёт ИИ (нулевую тоже), заезд
## идёт SECONDS секунд игрового времени на трассе `--kind=` (по умолчанию
## классика). Каждый кадр физики место каждой машины считается НЕЗАВИСИМО:
## свои круги по ГЛОБАЛЬНОЙ отметке оси (переход через линию) плюс сама
## отметка — и сравнивается с Main._place_of. Пары ближе 1.5 м друг к другу
## не судим (порядок там зависит от сантиметров), машины вне полотна,
## призраки и финишировавшие — тоже. Заодно ловим расползание накопленного
## Main._progress относительно независимого счёта (допуск 2 м).

const SECONDS := 60.0

var _main: Node3D
var _frame := 0
var _kind := TrackBuilder.KIND_GRASS
var _prev_off: Array[float] = []
var _laps: Array[int] = []
var _mismatch := 0
var _judged := 0
var _drift_max := 0.0
var _first_bad := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kind="):
			_kind = a.trim_prefix("--kind=")
	GameState.track_kind = _kind
	# Судим ПОСЛЕ счёта Main в том же тике (иначе прогресс отставал бы на
	# кадр от позиций — ложное «расползание» до 0.75 м на полном ходу).
	# Engine.time_scale тут не годится: он растягивает и delta физики,
	# машины ехали бы с шагом 0.05 с и физика становилась бы другой.
	process_physics_priority = 100
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_d: float) -> void:
	_frame += 1
	var track: TrackBuilder = _main._track
	var curve: Curve3D = track._curve
	var length := curve.get_baked_length()
	var cars: Array = _main._cars
	var n := cars.size()
	if _frame < 10:
		return
	if _frame == 10:
		for c: Car in cars:
			c.is_player = false   # нулевую тоже ведёт ИИ
		for i in n:
			var off := curve.get_closest_offset(cars[i].global_position)
			_prev_off.append(off)
			_laps.append(-1 if off > length * 0.5 else 0)
		print("трасса %s, машин %d, длина %.0f м" % [_kind, n, length])
		return

	var indep: Array[float] = []
	for i in n:
		var off := curve.get_closest_offset(cars[i].global_position)
		if _prev_off[i] > length * 0.8 and off < length * 0.2:
			_laps[i] += 1
		elif _prev_off[i] < length * 0.2 and off > length * 0.8:
			_laps[i] -= 1
		_prev_off[i] = off
		indep.append(_laps[i] * length + off)

	var any_over := false
	for c: Car in cars:
		if c.race_over:
			any_over = true
	if not any_over:
		for i in n:
			var car: Car = cars[i]
			if not car.alive or car.is_ghost():
				continue
			var half := track.half_width_at_offset(car.track_offset)
			if track.distance_from_axis_at(car.global_position, car.track_offset) > half \
					or track.distance_from_axis(car.global_position) > half:
				continue
			_drift_max = maxf(_drift_max, absf(indep[i] - _main._progress[i]))
			var place := 1
			var close := false
			for j in n:
				if j == i:
					continue
				if absf(indep[j] - indep[i]) < 1.5:
					close = true
				elif indep[j] > indep[i]:
					place += 1
			if close:
				continue
			_judged += 1
			var shown: int = _main._place_of(i)
			if shown != place:
				_mismatch += 1
				if _first_bad == "":
					_first_bad = "кадр %d: машина %d показано %d, независимо %d; прогресс %s / независимо %s" \
							% [_frame, i, shown, place,
							str(_main._progress.map(func(v: float) -> int: return int(v))),
							str(indep.map(func(v: float) -> int: return int(v)))]

	if _frame >= 10 + int(SECONDS * 60.0):
		print("проверок %d, расхождений %d, расползание прогресса макс. %.2f м, круги %s"
				% [_judged, _mismatch, _drift_max, str(_laps)])
		if _first_bad != "":
			print("первое расхождение — " + _first_bad)
		var ok := _mismatch == 0 and _drift_max < 2.0 and _judged > 1000
		print("PLACERACE TEST: %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
