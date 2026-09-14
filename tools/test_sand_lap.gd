extends Node3D
## Автотест ПЕСЧАНОЙ трассы (TrackBuilder.KIND_SAND).
## Фаза 1 (0-60 с): ИИ накатывают круги по пустыне — худший должен
## проехать больше полукруга (как TestLap). Трасса обязана быть песчаной
## И С ОТБОЙНИКАМИ (14.09: «на трассе пустыня нужно установить отбойники»;
## до того пустыня была без ограждений, и стенд проверял езду по песку —
## теперь за отбойник не попасть, те фазы убраны).
## Фаза 2 (60-62 с): игрока ставим на полотно в 3 м от борта, курс 60°
## к нему, 25 м/с без газа: отбойник обязан удержать машину на полотне
## (не дальше полуширины + 1 м от оси) и не убить её. Чтобы стенд не
## проходил «даром», ведение вдоль борта (Car._wall_slide: касание или
## упреждающий перехват _wall_align_time) обязано сработать хоть в одном
## кадре, а кузов — подойти к кромке ближе 2.5 м (перехват идёт за кадр до
## касания, и «касание» как таковое при ударе под углом может не
## подняться вовсе — скорость уже направлена вдоль стены).
## Запуск: godot --headless --path . res://tools/TestSandLap.tscn

var _main: Node3D
var _t := 0.0
var _next_log := 0.0
var _phase := 1
var _lap_ok := false
var _hit_t := 0.0           # момент броска на отбойник
var _worst_out := -999.0    # максимум выхода за полуширину, м
var _hit_frames := 0        # кадров, когда борт вёл машину (касание/перехват)


func _ready() -> void:
	# Вид трассы Main читает из GameState (тесты без выбора получают
	# классику — поэтому здесь выбираем песок ЯВНО, до создания Main).
	GameState.track_kind = TrackBuilder.KIND_SAND
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	GameState.track_kind = ""


func _physics_process(delta: float) -> void:
	_t += delta
	var track: TrackBuilder = _main._track
	if _t >= _next_log:
		_next_log += 10.0
		var progs: Array[String] = []
		for i in _main._progress.size():
			progs.append("%.0f" % _main._progress[i])
		print("t=%.0f progress: %s" % [_t, ", ".join(progs)])
	if _phase == 1:
		if _t < 60.0:
			return
		# Сама трасса обязана быть песчаной и С ОТБОЙНИКАМИ.
		if track.kind != TrackBuilder.KIND_SAND or not track.has_walls \
				or track.get_node_or_null("Walls") == null:
			print("SAND LAP TEST: FAIL (трасса не песчаная или нет отбойников)")
			get_tree().quit(1)
			return
		var length: float = track._curve.get_baked_length()
		var worst := 1e9
		for i in range(1, _main._progress.size()):
			worst = minf(worst, _main._progress[i])
		_lap_ok = worst > length * 0.5
		print("  фаза 1: худший ИИ проехал %.0f м (круг %.0f м) — %s" % [
			worst, length, "ok" if _lap_ok else "FAIL"])
		# Фаза 2: игрок в 3 м от борта, курс 60° к нему, 25 м/с без газа.
		var car: Car = _main._cars[0]
		var off := length * 0.3
		var pos: Vector3 = track._curve.sample_baked(off)
		var ahead: Vector3 = track._curve.sample_baked(
				fmod(off + 3.0, length))
		var dir := (ahead - pos).normalized()
		var side := dir.cross(Vector3.UP)
		var run := (dir * 0.5 + side * 0.87).normalized()
		var half: float = track.half_width_at_offset(off)
		var start: Vector3 = pos + side * (half - 3.0)
		start.y = pos.y + 0.7
		car.global_transform = Transform3D(Basis.looking_at(run), start)
		car.linear_velocity = run * 25.0
		car.angular_velocity = Vector3.ZERO
		car.reset_speed_memory()
		_hit_t = _t
		_phase = 2
		return
	var car: Car = _main._cars[0]
	# Фаза 2: 2 с меряем выход за полуширину полотна.
	var p := car.global_position
	var out := track.distance_from_axis(p) - track.half_width_at_pos(p)
	_worst_out = maxf(_worst_out, out)
	if car._wall_touch or car._wall_align_time > 0.0:
		_hit_frames += 1
	if int(_t * 8.0) != int((_t - delta) * 8.0):
		print("    t+%.2f: кромка %+.2f м, ход %.1f м/с%s" % [_t - _hit_t, out,
				car.linear_velocity.length(), ", борт" if car._wall_touch else ""])
	if _t < _hit_t + 2.0:
		return
	var hold_ok := _worst_out > -2.5 and _worst_out < 1.0 and car.alive \
			and _hit_frames > 0
	var moving := car.linear_velocity.length()
	print("  фаза 2: бросок на отбойник 25 м/с — выход за кромку %.2f м, "
			% _worst_out + "ведение борта %d кадров, ход через 2 с %.1f м/с (%s)"
			% [_hit_frames, moving, "ok" if hold_ok else "FAIL"])
	var ok := _lap_ok and hold_ok
	print("SAND LAP TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
