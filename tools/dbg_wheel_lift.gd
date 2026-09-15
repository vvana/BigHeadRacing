extends Node3D
## Замер подъёма колёс в арку (гипотеза 15.09 «передние диски иногда
## пропадают»: при клевке носом _animate_wheels поднимает пивот переднего
## колеса до 0.6 радиуса + подъём кузова — диск уходит в арку крыла).
## ИИ едут 40 с по классике; для каждой машины — максимум и доля кадров
## с подъёмом > 0.08 м у передних и задних колёс.
## Запуск: godot --headless --path . res://tools/DbgWheelLift.tscn

var _main: Node3D
var _t := 0.0
var _frames := 0
var _max_f: Array[float] = []
var _max_r: Array[float] = []
var _hi_f: Array[int] = []
var _hi_r: Array[int] = []


func _ready() -> void:
	GameState.track_kind = TrackBuilder.KIND_GRASS
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	GameState.track_kind = ""


func _process(delta: float) -> void:
	_t += delta
	if _t < 5.0:
		return
	var cars: Array = _main._cars
	if _max_f.is_empty():
		for _c in cars:
			_max_f.append(0.0)
			_max_r.append(0.0)
			_hi_f.append(0)
			_hi_r.append(0)
	_frames += 1
	for i in cars.size():
		var car: Car = cars[i]
		for pivot: Node3D in car._wheel_pivots:
			var lift: float = pivot.get_meta("lift")
			if pivot.get_meta("is_front"):
				_max_f[i] = maxf(_max_f[i], lift)
				if lift > 0.08:
					_hi_f[i] += 1
			else:
				_max_r[i] = maxf(_max_r[i], lift)
				if lift > 0.08:
					_hi_r[i] += 1
	if _t < 45.0:
		return
	for i in cars.size():
		var car: Car = cars[i]
		var radius := 0.0
		if not car._wheel_pivots.is_empty():
			radius = car._wheel_pivots[0].get_meta("wheel_radius")
		print("[lift] %d r=%.2f перед: max %.3f, >8см в %.1f%% кадров; зад: max %.3f, %.1f%%" % [
			i, radius, _max_f[i], 100.0 * _hi_f[i] / (2.0 * _frames),
			_max_r[i], 100.0 * _hi_r[i] / (2.0 * _frames)])
	get_tree().quit(0)
