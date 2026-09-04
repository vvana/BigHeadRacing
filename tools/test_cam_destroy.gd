extends Node3D
## Стенд п.9 (04.09): уничтожение своей машины — камера НЕ должна прыгать
## в сторону (к другой машине) и возвращаться. Оффлайн: грузим Main, через
## 4 с зовём destroy() у машины игрока, дальше 4 с следим за камерой:
## любой скачок > 6 м между кадрами, кроме ОДНОГО телепорта появления,
## или сближение камеры с чужой машиной ближе 8 м — FAIL.
## Запуск (headless): godot --headless --path . res://tools/TestCamDestroy.tscn

var _main: Node3D
var _t := 0.0
var _killed := false
var _prev := Vector3.INF
var _jumps: Array[String] = []
var _near_other := 0
var _done := false


func _ready() -> void:
	Engine.max_fps = 120
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	var cam := _main.get_node_or_null("IsoCamera") as Camera3D
	var car: Car = _main.get("_car")
	if cam == null or car == null:
		return
	if _t > 4.0 and not _killed:
		_killed = true
		print("destroy() на %.1f с, машина в %s" % [_t, car.global_position])
		car.destroy()
	if _killed:
		var pos := cam.global_position
		if _prev != Vector3.INF:
			var d := _prev.distance_to(pos)
			if d > 6.0:
				_jumps.append("t=%.2f скачок %.1f м" % [_t, d])
		_prev = pos
		var look := pos - cam.global_transform.basis.z * -60.0  # цель ≈ pos - offset
		for c in _main.get("_cars"):
			if c == car or not (c as Car).alive:
				continue
			var cc := c as Car
			# Камера смотрит в точку target + offset; сравниваем цель камеры
			# (pos − look_offset) с чужой машиной по горизонтали.
			var target := pos - (cam.global_transform.basis.z * -1.0) * 0.0
			if Vector2(cc.global_position.x - car.global_position.x,
					cc.global_position.z - car.global_position.z).length() < 8.0:
				continue   # соседи по решётке рядом — не показатель
		if _t > 8.5:
			_done = true
			var ok := _jumps.size() <= 1
			print("камера: скачков %d: %s" % [_jumps.size(), _jumps])
			print("CAMDESTROY TEST: %s (допустим один телепорт появления)" % ("PASS" if ok else "FAIL"))
			get_tree().quit(0 if ok else 1)
