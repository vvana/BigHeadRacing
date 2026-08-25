extends Node3D
## Автотест ПЕСЧАНОЙ трассы (TrackBuilder.KIND_SAND).
## Фаза 1 (0-60 с): ИИ накатывают круги по пустыне без ограждений —
## худший должен проехать больше полукруга (как TestLap).
## Фаза 2 (60-64 с): машину игрока ставим НА ПЕСОК рядом с полотном и
## давим газ: скорость должна упереться заметно ниже максимума (песок
## замедляет), флаг _on_sand гореть, а из-под колёс идти пыль.

var _main: Node3D
var _t := 0.0
var _next_log := 0.0
var _phase := 1
var _lap_ok := false
var _sand_top := 0.0        # максимум скорости на песке
var _sand_frames := 0       # кадров с _on_sand за фазу 2
var _smoke_frames := 0      # кадров с включённой пылью за фазу 2


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
		# Сама трасса обязана быть песчаной и БЕЗ ограждений.
		if track.kind != TrackBuilder.KIND_SAND or track.has_walls \
				or track.get_node_or_null("Walls") != null:
			print("SAND LAP TEST: FAIL (трасса не песчаная или есть стены)")
			get_tree().quit(1)
			return
		var length: float = track._curve.get_baked_length()
		var worst := 1e9
		for i in range(1, _main._progress.size()):
			worst = minf(worst, _main._progress[i])
		_lap_ok = worst > length * 0.5
		print("  фаза 1: худший ИИ проехал %.0f м (круг %.0f м) — %s" % [
			worst, length, "ok" if _lap_ok else "FAIL"])
		# Фаза 2: игрок на песок сбоку от полотна, газ в пол вдоль трассы.
		var car: Car = _main._cars[0]
		var off := length * 0.3
		var pos: Vector3 = track._curve.sample_baked(off)
		var ahead: Vector3 = track._curve.sample_baked(
				fmod(off + 3.0, length))
		var dir := (ahead - pos).normalized()
		var side := dir.cross(Vector3.UP)
		var half: float = track.half_width_at_offset(off)
		var start: Vector3 = pos + side * (half + 4.0)
		start.y = track._ground_height(start.x, start.z) + 0.7
		car.global_transform = Transform3D(Basis.looking_at(dir), start)
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		car.reset_speed_memory()
		Input.action_press("accelerate")
		_phase = 2
		return
	# Фаза 2: копим метрики песка.
	var car: Car = _main._cars[0]
	if car._on_sand:
		_sand_frames += 1
		_sand_top = maxf(_sand_top, car.linear_velocity.length())
		if not car._smoke.is_empty() and car._smoke[0].emitting:
			_smoke_frames += 1
	if _t < 64.0:
		return
	Input.action_release("accelerate")
	# Песок должен пускать (машина едет), но душить: максимум скорости на
	# песке заметно ниже max_speed. Пыль — почти в каждом кадре езды.
	var slow_ok := _sand_top > 5.0 and _sand_top < car.max_speed * 0.75
	var dust_ok := _sand_frames > 30 and _smoke_frames > _sand_frames / 2
	print("  фаза 2: на песке %d кадров, максимум %.1f м/с (лимит %.1f), " % [
			_sand_frames, _sand_top, car.max_speed * 0.75]
			+ "пыль в %d кадрах" % _smoke_frames)
	var ok := _lap_ok and slow_ok and dust_ok
	print("SAND LAP TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
