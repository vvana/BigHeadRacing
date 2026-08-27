extends Node
## Диагностика (с рендером!): насколько ровно ЕДЕТ КАРТИНКА марионетки.
## Сравниваем в каждом кадре рендера шаг ТЕЛА (шагает 60 Гц) и шаг МОДЕЛИ
## (интерполируется) против скорости из снимка. Если интерполяция работает,
## модель заметно ровнее тела. Запуск: без --headless, сервер должен идти.
##   godot --path . res://tools/DbgVisualJitter.tscn [-- адрес]

var _main: Node3D
var _t := 0.0
var _car: Car
var _prev_body := Vector3.ZERO
var _prev_model := Vector3.ZERO
var _body_dev: Array[float] = []
var _model_dev: Array[float] = []


func _ready() -> void:
	_main = get_parent() as Node3D
	var addr := "127.0.0.1"
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			addr = a
			break
	print("  сервер: %s" % addr)
	Net.join_server(addr, Net.PORT, false)


func _physics_process(delta: float) -> void:
	_t += delta
	Input.action_press("accelerate")


func _process(delta: float) -> void:
	if Net.my_slot < 0 or _main._car == null or not _main._car.controls_enabled:
		return
	if _car == null:
		for i in _main._cars.size():
			if i != Net.my_slot:
				_car = _main._cars[i]
				break
		return
	var body := _car.global_position
	var model_node := _car.get_node_or_null("CarModel") as Node3D
	if model_node == null:
		return
	var model := model_node.global_position
	var vel: Vector3 = _car._snap_vel
	vel.y = 0.0
	if _prev_body != Vector3.ZERO and vel.length() > 5.0 and delta > 0.0001:
		var expected := vel.length() * delta
		var bstep := body - _prev_body
		var mstep := model - _prev_model
		bstep.y = 0.0
		mstep.y = 0.0
		_body_dev.append(absf(bstep.length() - expected) / expected)
		_model_dev.append(absf(mstep.length() - expected) / expected)
	_prev_body = body
	_prev_model = model
	if _body_dev.size() >= 600:
		print("  кадров рендера: %d, fps примерно %.0f" % [
				_body_dev.size(), Engine.get_frames_per_second()])
		print("  ТЕЛО:   шаг расходится со скоростью на %.1f%%" % _avg(_body_dev))
		print("  МОДЕЛЬ: шаг расходится со скоростью на %.1f%%" % _avg(_model_dev))
		get_tree().quit(0)


func _avg(a: Array[float]) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / a.size() * 100.0
