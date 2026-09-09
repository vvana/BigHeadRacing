extends Node3D
## Автотест: после финиша ВСЕ машины плавно останавливаются.
## Машина игрока переводится на ИИ-управление и сама проходит 4 круга;
## через 8 c после финиша все должны стоять (v < 1 м/с) и не трогаться.

var _main: Node3D
var _t := 0.0
var _finish_t := -1.0
var _next_log := 0.0
var _moved_after_stop := false


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	# Игрок едет сам, как ИИ, — гонка финиширует естественно.
	_main._car.is_player = false


func _physics_process(_delta: float) -> void:
	_t += _delta

	if _finish_t < 0.0 and _main._finished:
		_finish_t = _t
		print("t=%.1f: ФИНИШ игрока (прогресс=%.0f)" % [_t, _main._progress[0]])

	if _t >= _next_log:
		_next_log = _t + 3.0
		var info: Array[String] = []
		for i in _main._cars.size():
			info.append("%s: v=%.1f" % [
				"P" if i == 0 else "ИИ%d" % i,
				_main._cars[i].linear_velocity.length()])
		print("t=%.1f fin=%s | %s" % [_t, _main._finished, " | ".join(info)])

	if _finish_t < 0.0:
		# Финиш теперь ПОФИНИШНЫЙ: _finished ждёт, пока доедут ВСЕ
		# (или таймаут 40 с после первого) — лимит поднят с запасом.
		if _t > 220.0:
			print("FINISH TEST: FAIL (гонка не финишировала за 220 с)")
			get_tree().quit(1)
		return

	# С 8-й по 14-ю секунду после финиша никто не должен двигаться.
	if _t > _finish_t + 8.0:
		for car in _main._cars:
			if car.linear_velocity.length() > 1.0:
				_moved_after_stop = true

	if _t < _finish_t + 14.0:
		return
	var vmax := 0.0
	for car in _main._cars:
		vmax = maxf(vmax, car.linear_velocity.length())
	var ok := not _moved_after_stop and vmax < 1.0
	# Хронометраж и таблица мест (09.09, вечер): у игрока есть время гонки
	# и лучший круг (круг короче гонки), таблица заполнена по всем машинам,
	# рекорды трассы записаны в тестовый файл на имя игрока.
	var t_ok := true
	var fin0: int = _main._finish_ms[0]
	var lap0: int = _main._best_lap_ms[0]
	if fin0 <= 0 or lap0 <= 0 or lap0 >= fin0:
		t_ok = false
		print("  FAIL: время игрока %d мс, лучший круг %d мс" % [fin0, lap0])
	if _main._result_rows.size() != _main._cars.size():
		t_ok = false
		print("  FAIL: строк таблицы %d, машин %d"
				% [_main._result_rows.size(), _main._cars.size()])
	var filled := 0
	for row: Dictionary in _main._result_rows:
		if (row.time as Label).text != "" and (row.name as Label).text != "":
			filled += 1
	if filled != _main._result_rows.size():
		t_ok = false
		print("  FAIL: заполнено строк таблицы %d" % filled)
	if int(_main._records.get("lap_ms", 0)) <= 0 \
			or str(_main._records.get("race_name", "")) != _main.car_label(0):
		t_ok = false
		print("  FAIL: рекорды %s" % str(_main._records))
	var rec_path: String = GameState.records_path()
	var on_disk := {}
	if FileAccess.file_exists(rec_path):
		var parsed: Variant = JSON.parse_string(
				FileAccess.get_file_as_string(rec_path))
		if parsed is Dictionary:
			on_disk = parsed
	if not on_disk.has(_main._track_kind):
		t_ok = false
		print("  FAIL: файл рекордов %s без трассы %s" % [rec_path, _main._track_kind])
	print("таблица: %s | рекорды: %s" % [
		", ".join(_main._result_rows.map(func(r: Dictionary) -> String:
			return "%s %s %s %s" % [(r.place as Label).text, (r.name as Label).text,
					(r.time as Label).text, (r.lap as Label).text])),
		str(_main._records)])
	ok = ok and t_ok
	print("FINISH TEST: %s (макс. скорость после остановки %.2f м/с%s)" % [
		"PASS" if ok else "FAIL", vmax,
		", кто-то двигался после 8 с" if _moved_after_stop else ""])
	get_tree().quit(0 if ok else 1)
