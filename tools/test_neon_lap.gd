extends Node3D
## Автотест НОЧНОЙ ГОРОДСКОЙ трассы (TrackBuilder.KIND_NEON).
## ИИ 60 с накатывают круги по городу — худший должен проехать больше
## полукруга (как TestLap/TestSandLap). Заодно проверяется, что трасса
## действительно неоновая: стены ЕСТЬ (в отличие от песка), профиль
## плоский, а у машин построены фары (SpotLight3D).

var _main: Node3D
var _t := 0.0
var _next_log := 0.0


func _ready() -> void:
	# Вид трассы Main читает из GameState (тесты без выбора получают
	# классику — поэтому здесь выбираем город ЯВНО, до создания Main).
	GameState.track_kind = TrackBuilder.KIND_NEON
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	GameState.track_kind = ""


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= _next_log:
		_next_log += 10.0
		var progs: Array[String] = []
		for i in _main._progress.size():
			progs.append("%.0f" % _main._progress[i])
		print("t=%.0f progress: %s" % [_t, ", ".join(progs)])
	if _t < 60.0:
		return
	var track: TrackBuilder = _main._track
	if track.kind != TrackBuilder.KIND_NEON or not track.has_walls \
			or track.get_node_or_null("Walls") == null:
		print("NEON LAP TEST: FAIL (трасса не городская или нет стен)")
		get_tree().quit(1)
		return
	var length: float = track._curve.get_baked_length()
	var worst := 1e9
	for i in range(1, _main._progress.size()):
		worst = minf(worst, _main._progress[i])
	var lap_ok := worst > length * 0.5
	var lights := 0
	for car: Car in _main._cars:
		# Споты лежат в держателе Headlights (top_level, см. Car._process),
		# а не прямо в машине — ищем во всём поддереве.
		lights += _count_spots(car)
	var lights_ok: bool = lights >= _main._cars.size() * 2
	print("  худший ИИ проехал %.0f м (круг %.0f м) — %s; фар %d — %s" % [
		worst, length, "ok" if lap_ok else "FAIL",
		lights, "ok" if lights_ok else "FAIL"])
	var ok: bool = lap_ok and lights_ok
	print("NEON LAP TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _count_spots(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child is SpotLight3D:
			n += 1
		n += _count_spots(child)
	return n
