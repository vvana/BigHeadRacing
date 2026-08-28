extends Node3D
## Автотест: ФАРЫ ДЕРЖАТСЯ НА МАШИНЕ (ночная городская трасса).
##
## С 26.08 картинка машины отвязана от тела (top_level) и каждый кадр
## рендера ставится МЕЖДУ двумя последними положениями тела
## (Car._process). Фары же строились детьми ТЕЛА и потому шагали с
## частотой физики: на ходу лампы и лучи отставали от собственного
## кузова на «шаг тела» (при 25 м/с это ~0.4 м) и туда-сюда болтались —
## жалоба «фары не жёстко прикреплены». Стенд ловит именно это.
##
## Мерим расстояние от лампы до ВИДИМОГО центра машины
## (Car.visual_origin): у жёстко связанных точек оно постоянно при любом
## повороте, а «плавающая» фара его гуляет.
## Заодно проверяем, что лампы вообще стоят НА КУЗОВЕ (в габаритах
## модели), а не висят рядом с ним в воздухе.
##
## Запуск: godot --headless --path . res://tools/TestHeadlights.tscn

const HOLD_TOL := 0.05     # допуск «болтанки», м
const FIT_TOL := 0.25      # насколько лампе позволено торчать из габаритов, м
const FRAMES := 240        # столько кадров мерим ПОСЛЕ того, как машина поехала
const GO_SPEED := 5.0      # с этой скорости (м/с) считаем, что заезд идёт

var _main: Node3D
var _frames := 0
var _worst := 0.0          # худшее отклонение расстояния «лампа — центр»
var _base: Array[float] = []   # эталонные расстояния (первый замер)
var _lamps: Array[Node3D] = []
var _start_pos := Vector3.ZERO
var _fit_worst := 0.0      # худший вылет лампы за габариты модели


func _ready() -> void:
	# Без капа fps headless крутит кадры тысячами в секунду, и кадры замера
	# кончаются раньше отсчёта 3-2-1-GO (грабли из TestMarkerFollow).
	Engine.max_fps = 120
	GameState.track_kind = TrackBuilder.KIND_NEON
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	GameState.track_kind = ""
	# Мерить — ПОСЛЕ Car._process: именно он ставит и модель, и фары.
	process_priority = 100


func _physics_process(_delta: float) -> void:
	Input.action_press("accelerate")


func _process(_delta: float) -> void:
	if _main == null or _main._cars.is_empty():
		return
	var car: Car = _main._cars[0]
	if _frames == 0 and car.linear_velocity.length() < GO_SPEED:
		return
	_frames += 1
	var vis: Vector3 = car.visual_origin()
	if _frames == 1:
		_start_pos = car.global_position
		_lamps = _find_lamps(car)
		for lamp in _lamps:
			_base.append(lamp.global_position.distance_to(vis))
	for i in _lamps.size():
		var d: float = _lamps[i].global_position.distance_to(vis)
		_worst = maxf(_worst, absf(d - _base[i]))
	_check_fit(car)
	if _frames < FRAMES:
		return
	_report(car)


## Все источники света и «лампы» машины, где бы они ни висели (на теле или
## в держателе): стенд не должен зависеть от того, как их сгруппировали.
func _find_lamps(node: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for child in node.get_children():
		if child is SpotLight3D:
			out.append(child)
		elif child is MeshInstance3D and String(child.name).begins_with("Lamp"):
			out.append(child)
		out.append_array(_find_lamps(child))
	return out


## Лампы должны сидеть на кузове: считаем габариты видимой модели в её
## собственных осях и смотрим, далеко ли лампа снаружи.
func _check_fit(car: Car) -> void:
	var model := car.get_node_or_null("CarModel") as Node3D
	if model == null or _lamps.is_empty():
		return
	var box := _model_aabb(model)
	if box.size == Vector3.ZERO:
		return
	var inv := model.global_transform.affine_inverse()
	for lamp in _lamps:
		if lamp is SpotLight3D:
			continue   # луч светит вперёд, ему торчать носом можно
		var p: Vector3 = inv * lamp.global_position
		# Расстояние наружу по каждой оси, в МЕТРАХ (у модели свой масштаб).
		var s: Vector3 = model.global_transform.basis.get_scale()
		var out := Vector3(
			maxf(maxf(box.position.x - p.x, p.x - box.end.x), 0.0) * s.x,
			maxf(maxf(box.position.y - p.y, p.y - box.end.y), 0.0) * s.y,
			maxf(maxf(box.position.z - p.z, p.z - box.end.z), 0.0) * s.z)
		_fit_worst = maxf(_fit_worst, out.length())


## Габариты модели в её собственных осях (детали лежат в дочерних узлах,
## колёса — в пивотах).
func _model_aabb(model: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [[model, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node3D = item[0]
		var xf: Transform3D = item[1]
		var mi := node as MeshInstance3D
		if mi != null and mi.mesh != null:
			var box: AABB = xf * mi.mesh.get_aabb()
			out = box if first else out.merge(box)
			first = false
		for child in node.get_children():
			if child is Node3D:
				stack.append([child, xf * (child as Node3D).transform])
	return out


func _report(car: Car) -> void:
	var moved := _start_pos.distance_to(car.global_position)
	print("  машина проехала %.1f м, ламп найдено %d" % [moved, _lamps.size()])
	if moved < 10.0:
		print("HEADLIGHTS TEST: FAIL (машина не поехала — замер бессмыслен)")
		get_tree().quit(1)
		return
	if _lamps.size() < 4:
		print("HEADLIGHTS TEST: FAIL (фар не построено: ждали 2 спота + 2 лампы)")
		get_tree().quit(1)
		return
	var ok_hold := _worst <= HOLD_TOL
	var ok_fit := _fit_worst <= FIT_TOL
	print("  фары держатся на кузове: %s (худшая болтанка %.3f м)"
			% ["ok" if ok_hold else "FAIL", _worst])
	print("  лампы в габаритах модели: %s (худший вылет %.3f м)"
			% ["ok" if ok_fit else "FAIL", _fit_worst])
	print("HEADLIGHTS TEST: %s" % ("PASS" if ok_hold and ok_fit else "FAIL"))
	get_tree().quit(0 if ok_hold and ok_fit else 1)
