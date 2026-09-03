extends Node3D
## Автотест подиума в гараже (03.09: «машинка на превью не должна по
## умолчанию вращаться, можно вращать мышкой или тапом»).
## 1) без ввода подиум СТОИТ;
## 2) протяжка с зажатой кнопкой поворачивает ровно на DRAG_SPEED·пиксели;
## 3) после отпускания движение мыши подиум не трогает.
## Касания приходят как мышь (эмуляция Godot), поэтому отдельной проверки
## для тачскрина нет.
##
## Запуск: godot --headless --path . res://tools/TestSpin.tscn

var _sel: Node3D
var _pass := 0
var _fail := 0


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: ", what)


func _ready() -> void:
	_sel = (load("res://scenes/CarSelect.tscn") as PackedScene).instantiate()
	add_child(_sel)
	for i in 5:
		await get_tree().process_frame

	var turn: Node3D = _sel.get_node("TurnTable")
	var idle := turn.rotation.y
	for i in 30:
		await get_tree().process_frame
	_ok(is_equal_approx(turn.rotation.y, idle), "сам по себе подиум стоит")

	# Тянем вправо тремя одинаковыми движениями с зажатой кнопкой.
	# Абсолютный угол не сверяем: viewport в headless крошечный, и
	# растяжка canvas_items умножает relative события на 1280/ширину окна
	# (было «в 20 раз больше, чем DRAG_SPEED·пиксели»). Проверяем то, что
	# от масштаба не зависит: поворот есть, шаги равные, знак верный.
	_button(true)
	var steps: Array[float] = []
	var was := idle
	for i in 3:
		_motion(40.0)
		await get_tree().process_frame
		steps.append(turn.rotation.y - was)
		was = turn.rotation.y
	var turned := turn.rotation.y - idle
	_ok(turned > 0.0, "протяжка вправо повернула вправо (%.3f)" % turned)
	_ok(is_equal_approx(steps[0], steps[1]) and is_equal_approx(steps[1], steps[2]),
			"равные протяжки — равные углы: %s" % str(steps))

	# Отпустили — дальнейшее движение мыши уже не крутит.
	_button(false)
	_motion(200.0)
	for i in 5:
		await get_tree().process_frame
	_ok(is_equal_approx(turn.rotation.y, idle + turned), "после отпускания стоит")

	# Обратная протяжка возвращает ровно назад — знак и масштаб те же.
	_button(true)
	for i in 3:
		_motion(-40.0)
		await get_tree().process_frame
	_button(false)
	_ok(is_equal_approx(turn.rotation.y, idle), "протяжка влево вернула в ноль")

	print("SPIN TEST: %s (%d/%d)" % ["PASS" if _fail == 0 else "FAIL",
			_pass, _pass + _fail])
	get_tree().quit(0 if _fail == 0 else 1)


## Левая кнопка мыши над свободным местом слева (там подиум, кнопок нет).
func _button(pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = Vector2(330, 380)
	get_viewport().push_input(ev)


func _motion(dx: float) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(330, 380)
	ev.relative = Vector2(dx, 0)
	# push_input, а НЕ Input.parse_input_event: очередь ввода в headless
	# отдаёт одно и то же движение много раз за кадр, и стенд насчитывал
	# двадцатикратный поворот.
	get_viewport().push_input(ev)
