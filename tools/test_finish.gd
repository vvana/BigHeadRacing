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
		if _t > 150.0:
			print("FINISH TEST: FAIL (гонка не финишировала за 150 с)")
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
	print("FINISH TEST: %s (макс. скорость после остановки %.2f м/с%s)" % [
		"PASS" if ok else "FAIL", vmax,
		", кто-то двигался после 8 с" if _moved_after_stop else ""])
	get_tree().quit(0 if ok else 1)
