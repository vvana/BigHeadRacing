extends Node3D
## Автотест: гонка едет сама 60 секунд. Проверяем, что ИИ проходит трассу
## с перепадами высот — накатывает круги, а не застревает на подъёмах.

var _main: Node3D
var _t := 0.0
var _next_log := 0.0


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


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
	var length: float = _main._track._curve.get_baked_length()
	var worst := 1e9
	for i in range(1, _main._progress.size()):
		worst = minf(worst, _main._progress[i])
	# За 60 с даже самый медленный ИИ должен проехать больше половины круга.
	var ok := worst > length * 0.5
	print("LAP TEST: %s (круг=%.0f м, худший ИИ проехал %.0f м)" % [
		"PASS" if ok else "FAIL", length, worst])
	get_tree().quit(0 if ok else 1)
