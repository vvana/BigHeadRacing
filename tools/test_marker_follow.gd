extends Node3D
## Автотест: стрелка-указатель и значок эффекта ДЕРЖАТСЯ НАД МАШИНОЙ.
##
## С 26.08 картинка машины отвязана от её тела (top_level) и каждый кадр
## рендера ставится между двумя последними положениями тела — иначе на
## живом мониторе дёргалось всё, кроме своей машины. Стрелка и значок
## отвязаны так же и ставятся по Car.visual_origin(). Ошибка тут выглядит
## как «стрелка висит сама по себе посреди трассы», и headless-стенды
## гонки её не заметят — потому и нужен этот.
##
## Запуск: godot --headless --path . res://tools/TestMarkerFollow.tscn

const PLAN_TOL := 0.35     # допуск в плане, м (интерполяция даёт доли метра)
const FRAMES := 240        # столько кадров мерим ПОСЛЕ того, как машина поехала
const GO_SPEED := 5.0      # с этой скорости (м/с) считаем, что заезд идёт

var _main: Node3D
var _frames := 0
var _worst_marker := 0.0
var _worst_icon := 0.0
var _icon_seen := false
var _start_pos := Vector3.ZERO


func _ready() -> void:
	# Без капа fps headless крутит кадры тысячами в секунду, и отведённые
	# на замер кадры заканчиваются раньше, чем отсчёт 3-2-1-GO, — первая
	# версия стенда мерила стоящую на решётке машину и всё одобряла.
	Engine.max_fps = 120
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	# Мерить — ПОСЛЕ Main._process: стрелку ставит он, и замер «до» показывал
	# бы не отрыв, а обычный шаг машины за кадр.
	process_priority = 100


func _physics_process(_delta: float) -> void:
	# Газ в пол: стоящая машина проверяет ровно ничего — отрыв стрелки виден
	# только на ходу.
	Input.action_press("accelerate")


func _process(_delta: float) -> void:
	# Мерить надо В КАДРЕ РЕНДЕРА: именно здесь ставятся и модель, и стрелка,
	# и значок. В кадре физики они ещё от прошлого кадра — замер бы врал.
	if _main == null or _main._cars.is_empty():
		return
	var car: Car = _main._cars[0]
	# Отсчёт и разгон не мерим вовсе: стенд начинается, когда машина
	# РЕАЛЬНО ЕДЕТ — только так отрыв стрелки вообще может проявиться.
	if _frames == 0 and car.linear_velocity.length() < GO_SPEED:
		return
	_frames += 1
	if _frames == 1:
		_start_pos = car.global_position
		# Разовый значок эффекта просим показать подольше (обычно он
		# живёт доли секунды), чтобы проверить и его тоже.
		car.show_effect_icon(Weapons.BOOST, 60.0)
	var vis: Vector3 = car.visual_origin()
	if _main._player_marker != null:
		_worst_marker = maxf(_worst_marker,
				_plan_dist(_main._player_marker.global_position, vis))
	var icon := car.get_node_or_null("StatusIcon") as Node3D
	if icon != null and icon.visible:
		_icon_seen = true
		_worst_icon = maxf(_worst_icon, _plan_dist(icon.global_position, vis))
	if _frames < FRAMES:
		return
	# Стенд обязан доказать, что мерил НА ХОДУ: стоящая машина «не отрывается»
	# от стрелки при любой ошибке в коде.
	var moved := _start_pos.distance_to(car.global_position)
	print("  машина проехала %.1f м" % moved)
	if moved < 10.0:
		print("MARKERFOLLOW TEST: FAIL (машина не поехала — замер бессмыслен)")
		get_tree().quit(1)
		return
	var ok_marker := _worst_marker <= PLAN_TOL
	var ok_icon := _icon_seen and _worst_icon <= PLAN_TOL
	print("  стрелка над машиной: %s (худший отрыв %.2f м)"
			% ["ok" if ok_marker else "FAIL", _worst_marker])
	print("  значок над машиной: %s (худший отрыв %.2f м, значок виден: %s)"
			% ["ok" if ok_icon else "FAIL", _worst_icon, str(_icon_seen)])
	print("MARKERFOLLOW TEST: %s" % ("PASS" if ok_marker and ok_icon else "FAIL"))
	get_tree().quit(0 if ok_marker and ok_icon else 1)


## Расстояние в плане (высота не в счёт: стрелка и значок висят НАД машиной).
func _plan_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
